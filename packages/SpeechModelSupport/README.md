# Speech model storage

`WhisperModelCache` installs staged Whisper Tiny, Base, and Small artifacts from the built-in pinned catalog. Pass a dedicated cache directory under an existing app-owned parent. Keep the directory and its parent in place while using the cache. The cache creates its own private directory and coordinates access across instances that share it.

Call these synchronous operations on a background queue. Use `withInstalledModel` to consume a verified read handle inside its callback. The handle closes when the callback finishes. Keep the handle within the callback and complete all reads before returning. Cancellation checks and read callbacks should finish promptly and avoid calling back into the cache.

The cache keeps at most one installed file per model and one temporary installation. The current catalog totals 713,245,145 installed bytes and peaks at 1,200,847,112 bytes during replacement, excluding filesystem overhead and the caller’s staged file. The caller owns the staged file and can remove it after installation returns.

The converted model records and MIT license are published at the [pinned model revision](https://huggingface.co/ggerganov/whisper.cpp/commit/80da2d8bfee42b0e836fc3a9890373e5defc00a6). The [original Whisper weights](https://github.com/openai/whisper#license) use the MIT license.
