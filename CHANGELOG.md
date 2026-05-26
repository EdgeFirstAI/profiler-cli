# Changelog

All notable changes to the **EdgeFirst Profiler CLI** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Fixed

## [1.1.0] - 2026-05-26

### Added

- Prebuilt `libhailort_profiler.so` now builds in CI for both linux-aarch64 (RPi5 / AI Kit) and linux-x86_64 (Hailo-8 PCIe). Each shim is built against HailoRT v4.23.0 compiled from source (no Hailo Developer Zone account required), uploaded as a workflow artifact, then bundled into the matching release archive and wheel via the same glob-based injection used for `libtrt_shim.so`. The wheel-injection and archive-packaging steps were generalized to iterate over `shims/prebuilt/<arch>/*.so` so future vendor shims drop in without further CI surgery.
- `ProfilingStatus::Failed { error: String, frames_done, frames_total, total_time_ms }` variant in `src/tui/event.rs`. Carries the human-readable failure message, the last-known progress at the moment of failure, and the wall-clock elapsed time captured at the transition (so the dashboard's "Elapsed" stops counting on a dead run). Future framework steps will promote the `error` field to a typed `Diagnostic` with structured `code`/`stage`/`hint` fields; the wire-level PROF: protocol is unchanged in this release.
- Strict pre-flight for `--provider cuda` (`strict_cuda_preflight` in `src/inference/ort_backend.rs`). Verifies each CUDA / cuDNN runtime SONAME the EP plugin needs is loadable; on a miss, the run hard-errors with the exact `pip install nvidia-*-cu12 ...` command instead of silently running on CPU. The check runs only when CUDA is the selected provider, so CPU users on partial setups never see CUDA-specific warnings. Paired with `error_on_failure()` on the CUDA EP dispatch so ort propagates registration failures instead of swallowing them.
- F4 Profiler completion popup now shows two persistent per-artifact progress bars (predictions.parquet and trace.pftrace) during Studio uploads, with byte/percent labels and pending/active/done/skipped state colouring. Replaces the previous ◌→✓ icon-only step indicators that flashed past too quickly for the user to see on fast uploads; each bar now stays at 100% green once its artifact finishes so the visual trail is preserved. A new `artifact_bar_lines` helper backed by an `ArtifactState` enum centralises the rendering; the `Skipped` variant covers the case where `trace.pftrace` was not produced but the session still completed (rendered dim with a "skipped (not produced)" label instead of a perpetually spinning ◌). `UploadProgress` now stores per-artifact byte counters (`parquet_current/_total`, `trace_current/_total`) that are fed by routing `BackgroundEvent::DownloadProgress` events on phase labels matching `tui::event::UPLOAD_LABEL_PREDICTIONS` / `UPLOAD_LABEL_TRACE`.
- F2 Studio validation screen now has an explicit "start new session" affordance. On the Complete / Failed page, Enter resets the phase state machine and returns to the Explorer with a freshly-loaded projects list; Esc resets and returns to the current breadcrumb level. The footer hint reads `Press Enter to start a new session • Esc to return to Explorer`. Previously the screen had no way out other than quitting and relaunching the binary.

### Changed

- TUI provider modal now binds **`g`** (for GPU) instead of `u` for CUDA, with the hint text shortened to "Run with CUDA". `m` for CoreML and `c` for CPU are unchanged. `ONNX.md` updated to match.
- TUI-created Studio validation sessions now carry a platform-aware name and a multi-line description. The name is `<model_stem>-<host>-<npu>` (e.g. `yolov5m-t-27e4_quant-u8-i8_smart-imx95-neutron`) — the model artifact's filename has its runtime extension and any `.imx95` / `.hailo8l` style hint stripped, then the runtime-resolved `<host>-<npu>` tag is appended. The host is detected from `/sys/firmware/devicetree/base/compatible` (covering imx8mp / imx95 / imx93 / orin-nano / rpi5) on Linux, short-circuits to `macos` / `windows` on those targets, and falls back to `uname -m` for DT-less Unix hosts; the NPU is derived from the model contents (TFLite `NeutronGraph` blob scan), the filename multi-suffix (Hailo `.hailo8l.hef` / `.hailo8.hef` / `.hailo10.hef`), and a host-side probe of `libvx_delegate.so` for generic TFLite on i.MX 8M Plus. Filename hints from Studio are treated as user-facing conventions only — the runtime host and the model contents are the source of truth, so a `.imx95.tflite` running on i.MX 8M Plus correctly resolves to `imx8mp-vsi` (or `imx8mp-cpu`), never `imx95-neutron`. The session description block is 4-7 lines (gracefully degrading on hosts where a probe is unavailable): hostname, kernel `Version` (sysname + release, no arch suffix), SoC / CPU model + core count, NPU name with a short detection note, total memory, and the profiler version. All Linux-specific probes (`/sys/firmware/devicetree/*`, `/proc/cpuinfo`, `/proc/meminfo`) sit behind `cfg(target_os = "linux")` and `libc::uname` sits behind `cfg(unix)`, so the module compiles cleanly on macOS today and will accept a Windows backend without touching public API. New SoMs and accelerators extend two enums (`HostTag`, `NpuTag`) with one variant + one match arm each — see `src/platform/`.
- TUI validation workflow now downloads the model **before** creating the Studio session so the platform identification has the model bytes in hand. The session is created with the final name and description on the first call instead of being renamed afterwards. The `download` stage in `set_session_stages` covers both model + dataset; after the reorder, stages are initialized with the stage's progress label set to `"Downloading dataset"` to describe the remaining work (the model is already on disk). The stage itself is opened in `running` and is not explicitly transitioned to `complete` — same as on `main` — leaving the existing server-side stage machine to resolve it when a later stage moves to running. The "Downloading model" progress bar is unchanged from the user's perspective — only the Studio-side label and the moment of session creation have shifted. The blocking `std::fs::read` for the Neutron-blob scan is now `tokio::fs::read` so large models don't stall the tokio worker thread.
- `tui/components/profiler.rs::detect_delegate` is now a thin shim over the new `platform::delegate_hint_for_host()` helper; the inline `/sys/firmware/devicetree/base/compatible` probe lived in two places (also the configure-panel default) and is now centralized in `src/platform/host.rs`.

### Fixed

- 5000-image validation runs no longer drop the last `pipeline_depth` frames with `PboDisconnected`. The HAL `ImageProcessor` was moved into the preprocess thread closure, so when the preprocess loop exited at end-of-run the processor was dropped, tearing down its GL thread / PBO `Sender` while the inference thread still held depth-many PBO-backed staging tensors with only `WeakSender`s. Wrapping the processor in `Arc<Mutex<>>` and holding one `Arc` in the orchestrator scope past all thread joins keeps the GL `Sender` alive until inference fully drains, so every `pre_tensor.map()` succeeds. Mutex is uncontended in practice (only the preprocess thread ever calls `convert()`).
- Inference-thread skip log now names the failing file. The decode and preprocess skip sites already logged `frame_id` and `path`, but `infer.rs` only carried the error message — which sent the `PboDisconnected` regression hunt down the wrong rabbit hole. `PreprocessedFrame` now carries `image_path` through from `DecodedFrame`, and the infer-thread error WARN includes it.
- Pipeline summary splits the skip count by stage: `decode=N preprocess=N infer=N` instead of the previous lump-sum "decode or processing failure". `OrchestratorResult` gained `decode_skipped` / `preprocess_skipped` / `infer_skipped` fields (the existing `skipped_frames` is now their sum).
- yolo26 ONNX exports with `model.end2end = false` (pre-NMS head) now decode correctly and produce `predictions.parquet`. `edgefirst-hal` 0.23's `DecoderVersion::is_end_to_end()` treats the `Yolo26` variant as unconditionally embedded-NMS, so the builder rejected the model with `InvalidConfig("Yolo26 Segmentation Detection must have num_features be 6 + num_protos = ...")` and the pipeline silently fell into timing-only mode. The profiler now rewrites `decoder_version` to `"yolov8"` whenever it sees `decoder_version: "yolo26"` paired with `model.end2end: false` — the head shape (4 box + N class + M mask coefs × anchors) is structurally identical to yolov8, so HAL's existing yolov8 DFL path handles it correctly. Compat shim only; reverts to passthrough once HAL gains an explicit `end2end` field.
- TUI validation sessions no longer stay stuck on the "Running" dashboard when the child pipeline reports a fatal error (e.g. `libonnxruntime.so` not found). `BackgroundEvent::Error` previously only set `shared.pipeline_error` and showed an error popup, leaving `ProfilingStatus` in `Running` forever — the dashboard kept counting elapsed time on zero frames and the F2 Studio tab stayed on `RunningInference`, even though the Studio backend session was correctly errored via `report_session_error`. A new `ProfilingStatus::Failed` variant gives the Error event a terminal target; the dispatcher now transitions Running → Failed, clears `profiling_active`, and bridges the failure to the Studio screen by enqueueing `ValidationPhase::Failed` on `bg_tx`. The error popup behaviour is unchanged.
- TUI now also surfaces silent child-exit failures (panic, SIGKILL, or any path that closes the child's stderr without emitting `PROF:complete` or `PROF:error`). `ingest_prof_stream` synthesises a `BackgroundEvent::Error("Child process exited without producing a result...")` on EOF when no terminal event was seen, so the same Running → Failed transition fires.
- TUI partial-failure runs (`run_bench_internal` invoke fails mid-loop at `src/tui/bench.rs:166-173`) now correctly stay in the Failed state. The child emits `PROF:error` for the failing iteration and then still emits `PROF:complete` with the partial stats from the iterations that did succeed; pre-fix, the parent's `ProfilingFinished` handler unconditionally transitioned to `Finished` and the completion popup masked the error popup. The handler now no-ops when `ProfilingStatus` is already `Failed`, preserving the failure state and its error message.
- Failed-state TUI dashboard no longer counts elapsed time on a dead run. The renderer used to call `started_at.elapsed()` every frame; it now reads a frozen `total_time_ms` captured at the moment of transition. The progress bar and FPS row also switch to `Theme::DANGER` (red) with an explicit "Failed" label so the failed state is visually distinct from the live-run teal.
- TUI now clears stale failure state when launching a new run or pressing the stop affordance. Previously `shared.pipeline_error` and the profiler's error popup were set on failure but never cleared, so the next run's `ChildExited` handler would still read `pipeline_error.is_some()` and skip the Studio upload (reporting the *previous* error to Studio), and the old error popup would cover the new dashboard. `dispatch_profile_launch`, `dispatch_studio_launch`, and `AppAction::StopProfiling` now reset both.
- `ingest_prof_stream` now distinguishes a stderr read error (broken pipe, invalid UTF-8) from a clean EOF. Previously `while let Ok(Some(line)) = ...` swallowed both and the post-loop synthesis branch emitted "Child process exited without producing a result..." in either case — misleading on the read-error path because the child didn't exit. Read errors now emit a specific `BackgroundEvent::Error("Failed to read child stderr: ...")`.
- Studio upload progress no longer corrupts the TUI. `upload_and_validate_stepped` used `indicatif::ProgressBar` for parquet and trace uploads — those bars write ANSI escape codes directly to stderr, bypassing ratatui's alternate-screen buffer, so they smeared across the dashboard while the TUI's 100 ms render tick kept repainting widgets on top of them. A new `spawn_tui_progress_forwarder` consumes `edgefirst_client::Progress` events from `upload_data` and re-emits them as `BackgroundEvent::DownloadProgress`, which both the F2 dialog gauge and the F4 popup bars now render natively. The forwarder primes the gauge with the file's known size before the first byte streams (so even if all intermediate `try_send` events get dropped under buffer pressure, the bar appears with the correct denominator) and emits a defensive terminal event on receiver close. CLI paths (`fetch_session`, `download_model_standalone`, `publish_results`) still use indicatif as before; only the TUI upload path was migrated.
- F2 Studio validation screen now resets after a run completes. `handle_validation_key` previously only flipped `state` back to `Explorer` on Esc and never reset `validation_phase`, so re-entering F2 from another tab (e.g. F4 → F2) re-rendered the stale `Complete { session_id }` / `Failed(msg)` page indefinitely. A new `reset_validation_state` helper clears `validation_phase` back to `CreatingSession` and zeroes the byte counters; it is called from both the Esc and Enter handlers. The `StudioValidationPhase` event handler now also gates its mutations on `state == Validation` so background-task events emitted after Esc cannot pull the screen back into a stale view.
- F2 in-dialog gauge now also drives upload progress, not just downloads. The phase-event handler's "preserve counters" match was broadened to include `UploadingResults` and `UploadedParquet` (in addition to the existing `DownloadingModel` / `DownloadingDataset`), so the gauge stays populated across the parquet→trace transition. `studio.rs` re-broadcasts `UploadingResults` between artifacts so the dialog title stays coherent with what the gauge is showing.
- F4 Profiler completion popup no longer carries stale upload state into the next run. `ProfilingFinished` now wipes `upload_progress` back to default, so when a second validation run is launched the popup opens cleanly instead of briefly showing the previous run's bars at 100% green until the new `UploadingResults` event arrives.

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
