#include "WhisperRuntime.h"

#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <limits>
#include <unistd.h>
#include <vector>

namespace {
struct Observation {
    int checks = 0;
    int cancelOn = 0;
    int transcripts = 0;
};

bool isCancelled(void *context) {
    auto &observation = *static_cast<Observation *>(context);
    ++observation.checks;
    return observation.cancelOn > 0 && observation.checks >= observation.cancelOn;
}

void receiveTranscript(const char *, size_t, void *context) {
    ++static_cast<Observation *>(context)->transcripts;
}

void expect(bool success, const char *description) {
    if (!success) {
        std::fprintf(stderr, "Failed: %s\n", description);
        std::exit(EXIT_FAILURE);
    }
}
}

int main(int argc, char **argv) {
    expect(argc == 2, "Path to the pinned no-weights Tiny test fixture");
    const int model = open(argv[1], O_RDONLY | O_CLOEXEC);
    expect(model >= 0, "Open the pinned no-weights fixture");
    expect(lseek(model, 7, SEEK_SET) == 7, "Set an independent caller-owned file position");

    std::vector<float> pcm(16000, 0);
    Observation state;
    const auto transcribe = [&](int descriptor, const char *language = "en") {
        return gergramWhisperTranscribe(descriptor, pcm.data(), pcm.size(), language,
                                     isCancelled, receiveTranscript, &state);
    };
    expect(transcribe(-1) == GergramWhisperInvalidInput, "Invalid descriptor");
    expect(transcribe(model, "unknown-language") == GergramWhisperInvalidInput, "Unknown language");
    pcm.front() = std::numeric_limits<float>::quiet_NaN();
    expect(transcribe(model) == GergramWhisperInvalidInput, "Nonfinite PCM");
    pcm.front() = 0;
    expect(gergramWhisperTranscribe(model, pcm.data(), 60 * 16000 + 1, "en",
                                  isCancelled, receiveTranscript, &state) == GergramWhisperInvalidInput,
           "PCM outside byte and duration budget");

    FILE *corrupt = tmpfile();
    expect(corrupt != nullptr, "Create corrupt model fixture");
    const int corruptDescriptor = fileno(corrupt);
    const char corruptHeader[48] = {};
    expect(write(corruptDescriptor, corruptHeader, sizeof(corruptHeader)) == sizeof(corruptHeader), "Write invalid magic");
    expect(transcribe(corruptDescriptor) == GergramWhisperModelLoadFailed, "Reject invalid model magic");
    expect(fclose(corrupt) == 0, "Caller owns corrupt descriptor");

    state = {0, 1, 0};
    expect(transcribe(model) == GergramWhisperCancelled && state.checks == 1, "Cancel before model load");
    state = {0, 2, 0};
    expect(transcribe(model) == GergramWhisperCancelled && state.checks == 2, "Cancel during real CPU model loading");
    expect(state.transcripts == 0, "Cancellation emits no text");

    state = {};
    expect(transcribe(model) == GergramWhisperNoSpeech, "No trained weights means no speech");
    expect(state.transcripts == 0, "No transcript from the fixture without weights");

    const int uncancelledChecks = state.checks;
    expect(uncancelledChecks > 3, "Native fixture reaches inference");
    state = {0, uncancelledChecks - 2, 0};
    expect(transcribe(model) == GergramWhisperCancelled && state.checks == uncancelledChecks - 2,
           "Cancel after model loading during real CPU inference");
    expect(state.transcripts == 0, "Inference cancellation emits no text");
    expect(lseek(model, 0, SEEK_CUR) == 7, "Caller descriptor remains open at its original offset");
    expect(close(model) == 0, "Caller closes the borrowed descriptor");
}
