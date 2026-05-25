# Changelog

All notable changes to the **EdgeFirst Profiler CLI** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.3] - 2026-05-25

### Fixed

- Validation sessions no longer hang at 100 % inference. The pipeline orchestrator's infer thread held a clone of the buffer-return channel sender for its error path and never dropped it before the post-loop drain — leaving itself as the last live sender so `buffer_rx` could never disconnect. The thread then blocked on `for _buf in buffer_rx {}` forever, which in turn blocked the engine hand-back, the thread joins, and the entire publish flow. Symptom was a progress bar pinned at `5000/5000` with no CPU, no memory growth, and no further output. The clone is now dropped immediately after `drop(tx)` so the drain terminates as soon as the decoder exits.
- ONNX Runtime per-op profiling no longer spams `Maximum number of events reached, could not record profile event.` partway through long runs. ORT's profiler uses a fixed-capacity 1 M-event ring buffer in upstream `core/common/profiler.cc` and the buffer is not exposed as a session config option in any released ORT version. A YOLO-class graph emits ~240–500 events per `session.run`, so a 5 000-frame run overflows the cap around frame 4 100 and loses every subsequent per-op event. `OrtEngine` now counts invocations and ends profiling early once `ORT_PROFILE_INVOCATION_CAP` (3 000 frames) is reached; the cached profile path is returned later by the trait `end_profiling()` call so the post-loop parser is unchanged. Aggregate stage timing (`tensor_ref`, `session_run`, `output_copy`) keeps running for every subsequent frame through the existing `StagedTimer`.

### Changed

- Post-loop ORT profile emission now streams the JSON file event-by-event instead of `serde_json::from_reader`-ing the whole array into a `Vec<OrtTraceEvent>`. ORT writes one JSON object per line with comma separators (Chrome-tracing convention), so the new `stream_ort_profile` parser walks the file line-by-line, buffers nodes until the per-frame `SequentialExecutor::Execute` envelope event, then yields one `OrtFrameProfile` and frees the buffer. Combined with `stream_emit_ort_trace_events`, this drops peak post-loop memory from roughly 200 MB to ~48 KB for a 3 000-frame capped run and eliminates the multi-second pause that used to happen between the last inference and the start of the publish step.
- CLI now renders dataset, model, predictions, and trace transfers as indicatif progress bars matching the style used by `edgefirst-cli`. Downloads show decimal bytes (model artifact, trace) or item counts (dataset enumeration); uploads show decimal bytes. The TUI path is unchanged — it continues to consume the structured `PROF:` event stream and reports progress through its dashboard.
- Inference loop progress is now an indicatif bar instead of a per-100-frame `[N/Total] X.X FPS | elapsed: Ys` `println!`. The bar shows elapsed and ETA, the current/total frame counts with thousands separators, and a custom `{fps}` key formatted to one decimal place (avoids indicatif's default `{per_sec}` which renders the full f64). Skipped under `--emit-prof` (TUI mode) so the parent's PROF: event parser doesn't see ANSI escape sequences.
- Several "stuck at the end" silences now have status lines so neither the CLI nor the TUI parent process looks frozen: `Inference complete. Finalizing results...` between the last frame and stats computation, `ORT profile: <path>` before the streaming parse begins, `Finalizing trace file...` between the pipeline return and the pftrace `BufWriter` drop, and `Publishing results to Studio...` before the upload. Combined with the streaming ORT parse and the deadlock fix, the gap between "last frame" and "results published" is now visibly attributed instead of being one long silence.

## [1.0.2] - 2026-05-25

### Added

- Prebuilt `libtrt_shim.so` now ships in linux-aarch64 release archives and wheels. Jetson Orin users on JetPack 6.x can `pip install edgefirst-profiler` or `curl install.sh | bash` and run TensorRT models out of the box — no more "TensorRT shim not found" with a "build it on the Jetson" follow-up. The shim is built in CI from the NVIDIA L4T TensorRT 10.3 container. Users on other JetPack versions can still build from source via `shims/trt-shim/README.md`.

### Changed

- TensorRT shim search path now checks binary-relative locations first: `dirname(profiler_binary)/libtrt_shim.so` for flat archives and manual drop-ins, and `dirname(profiler_binary)/../lib/libtrt_shim.so` for pip-installed wheels. `$TRT_SHIM_PATH`, `LD_LIBRARY_PATH`, and the `/usr/local/lib` / `/usr/lib` fallbacks remain.

## [1.0.1] - 2026-05-25

### Fixed

- Release archives on `EdgeFirstAI/profiler-cli` GitHub Releases now ship a `.sha256` sidecar alongside each `.tar.gz` / `.zip`. The v1.0.0 release was missing these sidecars, causing `install.sh` and `install.ps1` to fail their checksum-verification step with a 404 on the first install attempt (worked around manually for v1.0.0 by uploading sidecars after the fact).
- `install.sh` no longer prints `tmpdir: unbound variable` during cleanup on success. The script's EXIT trap referenced a `local` variable that had gone out of scope by the time the trap fired; the variable is now process-scoped and the trap defensively defaults if unset.

### Changed

- CI builders for the wheel and binary matrix switched from `ubuntu-latest` and `ubuntu-22.04-arm` to `ubuntu-22.04-large` and `ubuntu-22.04-arm-large` respectively. The larger SKUs cut wall-clock build times on the long-pole entries.
- CHANGELOG body reformatted with one paragraph per line so GitHub Release pages, PyPI project descriptions, and other markdown consumers can wrap the text to fit their layout instead of preserving the source-file hard wraps.

## [1.0.0] - 2026-05-25

Initial public release of the EdgeFirst Profiler CLI — an on-target profiling agent for AI vision pipelines, designed to characterize real-world inference performance on the hardware your model will actually run on.

### Platforms

- Linux x86_64 (glibc 2.17+ / manylinux2014)
- Linux aarch64 (glibc 2.17+ / manylinux2014)
- macOS arm64 (macOS 11+)

Windows support is planned and not yet shipped; the installer prints a clear message for Windows users in the meantime.

### Edge hardware support

- NVIDIA Jetson Orin / Orin Nano — CUDA via ONNX Runtime, optional TensorRT execution provider.
- NXP i.MX 95 — Neutron NPU via the TFLite delegate.
- NXP i.MX 8M Plus — VSI NPU via the TFLite delegate.
- Raspberry Pi 5 — CPU baseline plus optional accelerators.
- Kinara Ara-2 — DVM models via the `ara2-proxy` daemon.
- Hailo-8 / Hailo-8L — via HailoRT.
- Apple Silicon — CoreML execution provider via ONNX Runtime.

### Execution providers

ONNX Runtime is the default, lowest-common-denominator backend. Vendor backends opt in per build: TFLite (with NXP Neutron and VSI delegates), Hailo, TensorRT, Apple CoreML.

### Features

- Per-operator timing dashboard with a live terminal UI (TUI).
- Pipeline orchestrator with 4-thread pipelined validation for realistic-throughput measurements.
- EdgeFirst Studio integration: launch profiling sessions from Studio, report status and progress, publish traces and validation runs to your Studio account.
- Offline-first: runs without a Studio account; Studio sign-in is only required to publish or pull data.

### Distribution

- Standalone binary archives via GitHub Releases on [EdgeFirstAI/profiler-cli](https://github.com/EdgeFirstAI/profiler-cli) (`install.sh` / `install.ps1` resolve the latest version).
- Python wheels on PyPI as `edgefirst-profiler` — the wheel ships the same native binary as the standalone archive, installed onto your `PATH` via `pip install edgefirst-profiler`.
