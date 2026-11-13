# Media throughput ceiling

## What the current transport can deliver

There is no verified maximum live gergram speed for a particular account, file, route, or machine. Useful throughput is bounded by the account entitlement, the actual media DC or CDN path, available TCP capacity, request concurrency, decoding and disk. Telegram's published per-DC parallel-file limits are runtime soft limits for the small and large file classes. The configuration page currently shows examples of five small and two large downloads. Consume the account's configuration rather than treating those examples as constants. Telegram also documents timed retries for `FLOOD_WAIT_X` and `FLOOD_PREMIUM_WAIT_X`. MTProto download requests still have alignment and a 1 MiB boundary, and CDN bytes require trusted SHA-256 verification. [File API](https://core.telegram.org/api/files) · [Configuration](https://core.telegram.org/api/config) · [AutoDownloadSettings](https://core.telegram.org/constructor/autoDownloadSettings) · [CDN integrity](https://core.telegram.org/cdn) · [Telegram Premium FAQ](https://telegram.org/faq_premium/)

| Layer | Current source-backed capacity |
| --- | --- |
| Rust `FetchV2` per resource | Six parts initially, growing on completed parts under one second to at most 16 master or 32 CDN pending parts. A part over two seconds can halve the adaptive window down to two. Unknown-length files begin with one part while no range has completed. The master starts at 128 KiB for ordinary media and 512 KiB for story resources. Once four or more recent master parts show at least 4 MiB/s, the configured chunk size becomes 512 KiB. It returns to 128 KiB below 1.5 MiB/s. The CDN starts and remains at 128 KiB in this revision, because the throughput-based part-size change is master-only. |
| Multiplexed requests | One account's one master target key has four workers × three active requests = 12 executing RPCs. A Rust CDN target key has eight × four = 32. The actual key also distinguishes background continuation. File admission must still count active files for the DC across purposes. CDN hash and reupload calls consume master slots. |
| Approximate useful in-flight payload | About 6 MiB for one saturated warm master target with aligned 512 KiB chunks. About 4 MiB for one warm CDN target with 128 KiB chunks. Initial six ordinary master parts give 768 KiB in flight. Alignment, sharing with other resources, outstanding hash verification, adaptation and the requested range reduce usable payload. |
| gergram direct FFmpeg playback | One rolling 2 MiB interval with a 512 KiB cache probe. The previous reader waited until the current request no longer covered the probe. The current reader replenishes the window after advancing 512 KiB while reading if the next tail is missing from the cache. The reader intentionally decodes only around ten seconds ahead of playback. This application-level bound can limit a saturated transfer independently of the underlying transport. |

Source links at the checkout's Telegram-iOS pin `24638bc69bd083981b178dd1e7f921eebbf7fc46`. [FetchV2 constants and range planner](https://github.com/TelegramMessenger/Telegram-iOS/blob/24638bc69bd083981b178dd1e7f921eebbf7fc46/submodules/TelegramCore/Sources/Network/FetchV2.swift#L8-L115) · [Pending work selection](https://github.com/TelegramMessenger/Telegram-iOS/blob/24638bc69bd083981b178dd1e7f921eebbf7fc46/submodules/TelegramCore/Sources/Network/FetchV2.swift#L676-L748) · [Adaptation](https://github.com/TelegramMessenger/Telegram-iOS/blob/24638bc69bd083981b178dd1e7f921eebbf7fc46/submodules/TelegramCore/Sources/Network/FetchV2.swift#L1216-L1239) · [Master/CDN workers](https://github.com/TelegramMessenger/Telegram-iOS/blob/24638bc69bd083981b178dd1e7f921eebbf7fc46/submodules/TelegramCore/Sources/Network/MultiplexedRequestManager.swift#L209-L215) · [CDN worker configuration](https://github.com/TelegramMessenger/Telegram-iOS/blob/24638bc69bd083981b178dd1e7f921eebbf7fc46/submodules/TelegramCore/Sources/Network/Network.swift#L1079-L1094)

On a clean, continuously fed, constant-rate link, with `N` outstanding parts, part payload `B` bytes, path capacity `L` bits/s, and round trip `R` seconds, this serialization model has the ideal bound:

```text
goodput <= min(L, (8 * N * B) / (R + 8 * B / L))
```

Keeping the link continuously occupied requires roughly a bandwidth-delay product plus one serialized part. For a 200 Mbit/s link with 100 ms RTT and 512 KiB requests, this is about 2.88 MiB of outstanding payload. At 1 Gbit/s and 100 ms, it is about 12.42 MiB, beyond the current one-target payload budget. Full file demand can keep more transport slots occupied than the direct player needs, particularly when startup or a seek only consumes a keyframe and its preceding bytes. The formula describes the model, and live paths can deliver less.

## Reproduced 256 MiB sequential sweep

The fixture compiled the previous `DirectMediaReadAhead` at blob `53ca4b0530801bb3068f67861bda88db3b9077b9`, the early-refill policy at blob `df92ee7a10e16a90507d99b2671321bff075badc`, the exact pinned `FetchV2` range helpers and a Swift event model of the adaptive window. It reused the repository HLS simulator's FIFO link serialization equation, and read contiguous cached bytes immediately in 64 KiB increments. Candidate early rollover refreshed bounded demand after advancing 512 KiB. Each path starts cold, with an ordinary master part size of 128 KiB. The clean-link model omits codec, disk, actual encryption and hash CPU, hash/reupload RTT, proxy, server throttle, competing traffic, and real playback pacing. The full-file column keeps enough demand pending and measures the same model's transport ceiling.

All values are Mbit/s. The link column is Mbit/s / RTT in ms. More throughput for bulk reads improves playback only when the current throughput or response time cannot cover the required data.

| Target | Link | Previous 2 MiB | Late 8 MiB | Early 2 MiB | Early 4 MiB | Early 6 MiB | Early 8 MiB | Full-file demand |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Master | 50 / 20 | 48.55 | 49.67 | 49.98 | 49.98 | 49.98 | 49.98 | 49.98 |
| Master | 200 / 100 | 84.16 | 154.30 | 137.29 | 196.05 | 196.05 | 196.05 | 196.05 |
| Master | 500 / 100 | 106.80 | 268.26 | 153.43 | 299.58 | 438.96 | 438.96 | 438.96 |
| Master | 1000 / 20 | 420.78 | 771.48 | 686.45 | 980.27 | 980.27 | 980.27 | 980.27 |
| Master | 1000 / 100 | 117.33 | 288.15 | 159.68 | 311.95 | 457.29 | 457.29 | 457.29 |
| Master | 1000 / 250 | 49.88 | 120.63 | 65.48 | 127.97 | 187.62 | 187.62 | 187.62 |
| CDN | 50 / 20 | 49.98 | 49.98 | 49.98 | 49.98 | 49.98 | 49.98 | 49.98 |
| CDN | 200 / 100 | 88.66 | 157.32 | 137.43 | 196.05 | 196.05 | 196.05 | 196.05 |
| CDN | 500 / 100 | 109.63 | 243.30 | 153.50 | 299.40 | 316.62 | 316.62 | 316.62 |
| CDN | 1000 / 20 | 443.28 | 786.59 | 687.14 | 980.27 | 980.27 | 980.27 | 980.27 |
| CDN | 1000 / 100 | 119.01 | 271.38 | 159.72 | 311.85 | 320.94 | 320.94 | 320.94 |
| CDN | 1000 / 250 | 50.18 | 116.63 | 65.48 | 127.93 | 129.43 | 129.43 | 129.43 |

All 108 cases completed. The 200/100 master profile went from 84.16 to 137.29 Mbit/s with earlier refill at the same 2 MiB cap, or 196.05 Mbit/s with 4 MiB. The 500/100 profile went from 106.80 to 438.96 Mbit/s with early 6 MiB. The higher network rate at 1000/100 meets the worker limit before it fills the network. First 512 KiB was unchanged across the window variants within each profile, including 120.97 ms at 200/100. This timestamp models media byte availability. First decoded frame depends on the container, keyframe and decoder path. Raising late-rollover demand above 6 MiB actually reduced simulated master goodput at 1000/100 and 1000/250 because the larger batches produced longer replenishment gaps.

Reproduce the sweep from the repository root with the pinned Telegram-iOS submodule and enough Git history to include the previous read-ahead policy.

```sh
python3 tools/networklab/read_ahead_sweep.py
```

The runner extracts and verifies the exact pinned `FetchV2.swift` helpers. An exact copy of that file can be passed with `--fetch-v2` when the checkout is unavailable. It compiles the previous and current gergram policies and prints 108 result rows as CSV.

## Playback and stories

Ran all six `HLSPlaybackLabTests` with Swift 6.4. The modeled first playback times without preloaded data were 0.20 s at 50 Mbit/s and 20 ms, 0.70 s at 10 Mbit/s and 60 ms, 2.05 s at 3 Mbit/s and 150 ms, and 4.05 s at 1.5 Mbit/s and 300 ms. A ten-second opening preloaded at the selected rendition reduced these model startup times to 0.05 s. All table profiles recorded zero stalls. Tests also check that a cold open near a segment end waits for contiguous playable data. These HLS observations concern startup and segment scheduling, and the direct file speed values above concern a continuously advancing demand window.

```sh
fixture=$(mktemp -d /tmp/gergram-ceiling-hls.XXXXXX)
CLANG_MODULE_CACHE_PATH="$fixture/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$fixture/swift-cache" \
xcrun swift test --package-path packages/HLSPlayback --scratch-path "$fixture/build" \
  --manifest-cache none --disable-sandbox --filter HLSPlaybackLabTests
```

Stories use `StoryVideoView`'s streamable `MediaPlayer` and a story resource reference. Their speed work belongs in the story preload and presentation path as well as the shared transport. `StoryChatContent` already chooses among alternative media, looks ahead to up to three stories, uses a known server prefix for ranged preload, and tracks loaded ranges in MediaBox. Speculative video preloads now request at most 512 KiB when no usable server prefix is present, instead of requesting the complete resource. A positive advertised prefix still applies and is clipped to the file size. Foreground playback has no new mandatory prefix in the missing-metadata case. The viewer and preload paths now share representation selection. The nearest upcoming viewer story owns priority 1 while its media is missing, and the speculative reaction phase begins after its media attempt. Cached media skips the speculative fetch. Thirty-eight preload cases and 34 lifecycle cases passed with the exact pinned SwiftSignalKit and RangeSet dependencies where used. Keep the account's story-quality choice, authorization, and auto-download/network settings. Measure cold open, next swipe and short dwell separately with and without a server prefix, and count speculative bytes discarded on rapid swipes.

## Live verification and tuning order

1. Use the implemented early-refill change with the same 2 MiB limit as the first live comparison. Keep the old startup and seek budget. Increase the demand horizon to 4 MiB or 6 MiB only after sustained sequential consumption, available network and account budgets, and evidence that the current horizon leaves transport idle. Back off speculative demand promptly on seek, buffering-state changes, stalls, pressure and cancellation. Use a per-account budget across two simultaneous readers and explicit downloads. Instrument subscription updates because earlier rollover can increase handovers and cache probes.
2. The existing `DownloadThroughputMeter` measures actual media part durations and counts overlapping request intervals once. HLS already uses the resource-engine estimate for an initial bandwidth seed. A low estimate from a window-starved transfer is itself limited by demand. Validate a bounded probe and hysteresis before choosing the next window from the estimate. Ensure cached bytes, duplicates, cancelled work, and CDN replies discarded after failed hash verification cannot bias the tuned policy. Use a measured RTT or a separately justified fallback rather than equating request service time to RTT. [Pinned throughput meter](https://github.com/TelegramMessenger/Telegram-iOS/blob/24638bc69bd083981b178dd1e7f921eebbf7fc46/submodules/TelegramCore/Sources/Network/DownloadThroughputMeter.swift)
3. Prepare a fork-aware Debug NetworkLab run. Use the gergram bundle identity and a dedicated test account with authorized synthetic fixtures. The shell wrapper resolves the selected Debug app's metadata and uses one output directory for its own report lookup and the app's `-PerfLabOutput`. Its existing `bigfile` scenario accepts a fixture channel and measures complete useful bytes, time to first progress, duration and throughput. Prefer comparable cold and warm runs at several RTTs and report p50/p95 first frame and seek, wire/unique bytes, useful throughput, active requests, CPU and memory. The wrapper currently performs cache cleanup, so restrict the run to dedicated fixture resources.
4. Sweep file admission separately from the early-refill change. Same-DC file admission should observe the runtime file-class settings and allow foreground startup/seek to proceed without starving explicit downloads. Raising request concurrency makes sense only after identifying the current bottleneck and confirming queue pressure, retransmissions, and CPU/disk headroom. Keep the pinned engine's reference refresh, CDN authentication/hash behavior, and wait deadlines. A user watching one encoded stream has no reason to saturate a fast link once it has safe playback headroom.

The upstream benchmark document is historical context. It reports a live media measurement of 267 Mbit/s for Rust and 141 Mbit/s for MtProtoKit before the fast-download policy. In the simulated 200 Mbit/s, 100 ms path, it reports 22.3 MB/s for a master big file and 13.7 MB/s for a CDN big file with Rust. It explicitly leaves a live big-file recheck after the fast-download change open. gergram has no live throughput result from this run. [Upstream benchmark](mtproto-rust-vs-mtprotokit.md)
