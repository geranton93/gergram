#include "WhisperRuntime.h"
#include "whisper.h"

#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstring>
#include <memory>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

namespace {
constexpr size_t maximumSamples = 60 * WHISPER_SAMPLE_RATE;
constexpr off_t maximumModelBytes = 1024 * 1024 * 1024;
constexpr size_t maximumTranscriptBytes = 32 * 1024;
constexpr off_t minimumModelHeaderBytes = 48;

struct Operation {
    GergramWhisperIsCancelled isCancelled;
    void *context;
    bool cancelled = false;

    bool checkCancellation() {
        cancelled = cancelled || (isCancelled != nullptr && isCancelled(context));
        return cancelled;
    }
};

struct ModelInput {
    int descriptor;
    off_t size;
    Operation &operation;
    off_t offset = 0;
    bool reachedEnd = false;

    struct Interrupted {};

    size_t read(void *buffer, size_t requested) {
        auto *output = static_cast<unsigned char *>(buffer);
        size_t copied = 0;
        while (copied < requested) {
            if (operation.checkCancellation()) throw Interrupted{};
            if (offset == size) {
                if (copied != 0) throw Interrupted{};
                reachedEnd = true;
                break;
            }
            const size_t amount = std::min<size_t>({requested - copied, size_t(size - offset), 256 * 1024});
            const auto count = pread(descriptor, output + copied, amount, offset);
            if (count < 0 && errno == EINTR) continue;
            if (count <= 0) throw Interrupted{};
            offset += count;
            copied += size_t(count);
        }
        if (copied < requested) {
            std::memset(output + copied, 0, requested - copied);
        }
        return copied;
    }
};
}

GergramWhisperStatus gergramWhisperTranscribe(
    int verifiedImmutableModelDescriptor, const float *samples, size_t sampleCount, const char *language,
    GergramWhisperIsCancelled isCancelled, GergramWhisperTranscript receiveTranscript, void *context
) {
    if (samples == nullptr || sampleCount == 0 || sampleCount > maximumSamples || receiveTranscript == nullptr
        || (language != nullptr && std::strcmp(language, "auto") != 0 && whisper_lang_id(language) < 0)) {
        return GergramWhisperInvalidInput;
    }
    Operation operation{isCancelled, context};
    if (operation.checkCancellation()) return GergramWhisperCancelled;
    if (!std::all_of(samples, samples + sampleCount, [](float value) { return std::isfinite(value); })) {
        return GergramWhisperInvalidInput;
    }

    struct stat metadata;
    if (fstat(verifiedImmutableModelDescriptor, &metadata) != 0 || !S_ISREG(metadata.st_mode)
        || metadata.st_size > maximumModelBytes) {
        return GergramWhisperInvalidInput;
    }
    if (metadata.st_size < minimumModelHeaderBytes) return GergramWhisperModelLoadFailed;

    try {
        ModelInput input{verifiedImmutableModelDescriptor, metadata.st_size, operation};
        whisper_model_loader loader{
            &input,
            [](void *state, void *output, size_t size) { return static_cast<ModelInput *>(state)->read(output, size); },
            [](void *state) { return static_cast<ModelInput *>(state)->reachedEnd; },
            [](void *) {},
        };
        auto modelParameters = whisper_context_default_params();
        modelParameters.use_gpu = false;
        std::unique_ptr<whisper_context, decltype(&whisper_free)> model(
            whisper_init_with_params(&loader, modelParameters), whisper_free
        );
        if (operation.checkCancellation()) return GergramWhisperCancelled;
        if (!model || input.offset != input.size) return GergramWhisperModelLoadFailed;

        auto parameters = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        parameters.n_threads = 2;
        parameters.language = language == nullptr ? "auto" : language;
        parameters.no_timestamps = true;
        parameters.print_progress = false;
        parameters.print_realtime = false;
        parameters.print_timestamps = false;
        parameters.abort_callback = [](void *state) { return static_cast<Operation *>(state)->checkCancellation(); };
        parameters.abort_callback_user_data = &operation;

        const int status = whisper_full(model.get(), parameters, samples, static_cast<int>(sampleCount));
        if (operation.checkCancellation()) return GergramWhisperCancelled;
        if (status != 0) return GergramWhisperInferenceFailed;

        std::string text;
        const int count = whisper_full_n_segments(model.get());
        for (int index = 0; index < count; ++index) {
            const char *segment = whisper_full_get_segment_text(model.get(), index);
            if (segment == nullptr) return GergramWhisperInferenceFailed;
            const size_t remaining = maximumTranscriptBytes - text.size();
            const size_t length = strnlen(segment, remaining + 1);
            if (length > remaining) return GergramWhisperTranscriptTooLong;
            text.append(segment, length);
        }
        if (operation.checkCancellation()) return GergramWhisperCancelled;
        if (text.empty()) return GergramWhisperNoSpeech;
        receiveTranscript(text.data(), text.size(), context);
        return GergramWhisperOK;
    } catch (...) {
        return GergramWhisperInferenceFailed;
    }
}
