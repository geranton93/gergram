# Speech model storage

`WhisperModelCache` installs staged Whisper Tiny, Base, and Small artifacts from the built-in pinned catalog. Pass a dedicated cache directory under an existing app-owned parent. Keep the directory and its parent in place while using the cache. The cache creates its own private directory and coordinates access across instances that share it.

Call these synchronous operations on a background queue. Use `withInstalledModel` to consume a verified read handle inside its callback. The handle closes when the callback finishes. Keep the handle within the callback and complete all reads before returning. Cancellation checks and read callbacks should finish promptly and avoid calling back into the cache.

Create one `WhisperModelAcquisition` per app container to handle explicit local imports and removals. Pass the original file URL selected by the user. The acquisition owner balances the file's security scope, keeps one read descriptor open through verification and returns typed completion on the main queue. Imports and removals share one worker, and additional requests receive `.busy` until the active operation finishes. Call the returned closure to request cancellation during staging or while waiting for the cache. The worker checks cancellation before committing the file operation. An operation that has passed that final check can still complete successfully.

The cache keeps at most one installed file per model and one temporary installation. The current catalog totals 713,245,145 installed bytes and peaks at 1,200,847,112 bytes during replacement, excluding filesystem overhead and the caller’s staged file. The caller owns the staged file and can remove it after installation returns.

The converted model records and MIT license are published at the [pinned model revision](https://huggingface.co/ggerganov/whisper.cpp/commit/80da2d8bfee42b0e836fc3a9890373e5defc00a6). The [original Whisper weights](https://github.com/openai/whisper#license) use the MIT license.

## Optional native runtime

`NativeRuntime` builds a static CPU-only C interface against a local, pinned whisper.cpp v1.9.5 source tree. It checks the Git blob hashes of the build inputs and uses the exact upstream CMake targets. It is currently an explicit offline build and test target. The main app and Swift package build independently.

```sh
git clone https://github.com/ggml-org/whisper.cpp.git /tmp/whisper.cpp
git -C /tmp/whisper.cpp checkout --detach d1be6fde11ac6e0407606b4e42fe72d34add8037
cmake -S packages/SpeechModelSupport/NativeRuntime -B /tmp/gergram-whisper-build \
  -DWHISPER_SOURCE=/tmp/whisper.cpp -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0
cmake --build /tmp/gergram-whisper-build
ctest --test-dir /tmp/gergram-whisper-build --output-on-failure
bash packages/SpeechModelSupport/NativeRuntime/verify-swift-bridge.sh /tmp/gergram-whisper-build
```

Use a separate build directory and `-DGERGRAM_WHISPER_ASAN=ON` to run with Address Sanitizer. The bridge script uses the architecture, deployment target and sanitizer from that CMake build. Use `x86_64` instead of `arm64` on an Intel Mac, or run Intel checks on Apple Silicon with Rosetta. The C tests exercise upstream context loading, validation errors and cancellation using the upstream Tiny fixture with no trained weights. The Swift fixture also installs the model through the cache and reaches the C runtime through the module map. End-to-end speech recognition requires a real model and remains to be verified.

Feed the decoder's 48 kHz signed-16 mono or interleaved stereo CoreMedia buffers to one `WhisperPCMBuffer` per job. Finish the stream to drain the resampler and get at most 960,000 mono Float32 samples at 16 kHz. Use the same cancellation check for decoding, conversion and inference.

Compile `NativeRuntime/WhisperNativeTranscription.swift` with the optional C module from an application target that links the runtime. Its synchronous `recognize` call borrows the verified model descriptor from `WhisperModelCache` and copies the UTF-8 transcript inside the native callback. Run one inference job at a time on a background queue. Cancellation is checked during model reads and inference. [Runtime source and MIT license](https://github.com/ggml-org/whisper.cpp/blob/d1be6fde11ac6e0407606b4e42fe72d34add8037/LICENSE)

### Export the optional universal library

Build the pinned runtime in separate `arm64` and `x86_64` CMake directories using the same macOS SDK and deployment target of 11.0 or later. The Intel slice can be cross-compiled on Apple Silicon. The export contains one static archive, its C header and module map, and the pinned upstream license.

```sh
runtime=packages/SpeechModelSupport/NativeRuntime
bash "$runtime/export-universal-archive.sh" /tmp/gergram-whisper-arm64 /tmp/gergram-whisper-x86_64 /tmp/gergram-whisper-universal
bash "$runtime/verify-swift-bridge.sh" /tmp/gergram-whisper-arm64 --archive /tmp/gergram-whisper-universal
```

For sanitizer verification, use two Address Sanitizer builds and pass `--asan` to the export command. To link the exported library, make its `include` directory visible to Swift and link `libGergramWhisperRuntime.a` with `libc++`. Use a deployment target at least as high as the one selected for the archive. Intel execution requires an Intel Mac or Rosetta.
