#ifndef GERGRAM_WHISPER_RUNTIME_H
#define GERGRAM_WHISPER_RUNTIME_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    GergramWhisperOK,
    GergramWhisperInvalidInput,
    GergramWhisperCancelled,
    GergramWhisperModelLoadFailed,
    GergramWhisperInferenceFailed,
    GergramWhisperNoSpeech,
    GergramWhisperTranscriptTooLong,
} GergramWhisperStatus;

typedef bool (*GergramWhisperIsCancelled)(void *context);
typedef void (*GergramWhisperTranscript)(const char *utf8, size_t length, void *context);

GergramWhisperStatus gergramWhisperTranscribe(
    int verifiedImmutableModelDescriptor, const float *samples, size_t sampleCount, const char *language,
    GergramWhisperIsCancelled isCancelled, GergramWhisperTranscript receiveTranscript, void *context
);

#ifdef __cplusplus
}
#endif

#endif
