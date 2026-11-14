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

Use a separate build directory and `-DGERGRAM_WHISPER_ASAN=ON` to run with Address Sanitizer. Pass `--asan` to the bridge script for that build. The C tests exercise upstream context loading, validation errors and cancellation using the upstream Tiny fixture with no trained weights. The Swift fixture also installs the model through the cache and reaches the C runtime through the module map. End-to-end speech recognition requires a real model and remains to be verified.

The runtime is synchronous. Call once at a time on a background queue, passing the borrowed descriptor for an immutable, verified model from `WhisperModelCache.withInstalledModel` and up to 60 seconds of finite 16 kHz mono Float32 PCM. Copy transcript bytes inside the callback. The caller owns the descriptor. Cancellation is checked during model reads and inference. [Runtime source and MIT license](https://github.com/ggml-org/whisper.cpp/blob/d1be6fde11ac6e0407606b4e42fe72d34add8037/LICENSE)
