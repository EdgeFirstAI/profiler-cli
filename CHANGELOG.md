# Changelog

All notable changes to the **EdgeFirst Profiler CLI** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2026-05-27

### Added

- The F2 Studio explorer now shows a coloured deployability indicator next to every artifact in a training session. Green means this build of the profiler on this host can run the artifact; yellow means the artifact targets accelerator hardware that can't be confirmed without a runtime probe; red means the artifact targets a different SoC or the matching backend isn't built into this profiler. For yellow and red, a short inline reason explains the diagnosis at a glance — for example `[Hailo-8L] (Hailo runtime and accessory not confirmed)` or `[NXP i.MX 95 Neutron] (TFLite backend not built into this profiler)`. A short legend appears below the list. The indicator is informational only and does not block selection — you can still attempt to profile any artifact.
- New pipelining guide explaining how the validation pipeline overlaps its six stages so the NPU stays busy while the CPU prepares the next frame, what guarantees the bounded-channel design gives you about latency and memory, and how to read stalls in the F4 Pipeline Stages panel. Linked from the README and the architecture overview.

### Changed

- The training session list in the F2 Studio explorer now shows the most recently trained model at the top instead of the bottom. The session you most likely want to validate is the first one highlighted when you open an experiment.
- TensorRT engine-load failures now surface the underlying TensorRT runtime reason — plan-header size mismatch, version mismatch, compute-capability mismatch — instead of the previous generic "deserializeCudaEngine failed" message. Incompatible-artifact failures are now actionable from the profiler's error output alone.

### Fixed

- Validation sessions in EdgeFirst Studio no longer show as "complete" while the profiler CLI is still running. Each stage of a newly-created validation session is now correctly displayed as not-yet-started until work for that stage begins, and the post-profiling analysis step stays visible as a separate stage that remains pending until the EdgeFirst Validator app picks it up and runs. If the validator fails to launch after the profiler finishes uploading results, the analysis stage is now marked with an error instead of being left in a misleading "queued" state.
- EdgeFirst Studio validation sessions launched from the F2 Studio tab for ONNX models now record the actual execution provider in the session name. A CUDA run on a Linux x86_64 host produces a session named like `…-x86_64-onnx-cuda`, a CoreML run on macOS produces `…-macos-onnx-coreml`, and a plain CPU run produces `…-onnx-cpu`. Previously every ONNX session ended in `…-onnx-cpu` regardless of which provider actually ran, which made CPU runs and accelerated runs indistinguishable in Studio's session listings. The execution-provider modal also now opens before the Studio session is created, so the name is correct on the first attempt rather than relying on a rename afterwards.
- TensorRT `.engine` artifacts produced by EdgeFirst Studio training sessions now load on Jetson targets. Previously every such artifact failed at deserialization, so TensorRT validation on Jetson required pointing the profiler at an `.onnx` and rebuilding the engine locally.

## [1.1.0] - 2026-05-26

### Added

- Hailo accelerator support no longer requires building HailoRT yourself. Release archives and PyPI wheels for Linux aarch64 (Raspberry Pi 5 / AI Kit) and Linux x86_64 (Hailo-8 PCIe) now bundle the prebuilt Hailo shim, so `pip install edgefirst-profiler` or the install script is enough to run `.hef` models out of the box.
- CUDA runs now fail with an actionable error when the CUDA or cuDNN libraries the model needs aren't loadable, instead of silently falling back to CPU. The error names the missing library and prints the exact `pip install nvidia-*-cu12 …` command to fix the install. CPU users on partial setups never see CUDA-specific warnings — the check only runs when `--provider cuda` is selected.
- The F4 Profiler completion popup now shows persistent per-artifact progress bars for `predictions.parquet` and `trace.pftrace` during Studio uploads, with byte and percent labels and pending / active / done / skipped colouring. The previous spinner icons flashed past too quickly on fast uploads; each bar now stays at 100% green once its artifact finishes so the visual trail is preserved. When a run produced no trace file, the trace bar is rendered dim with a "skipped (not produced)" label instead of spinning indefinitely.
- The F2 Studio validation screen now has an explicit "start a new session" affordance on the Complete and Failed pages. Pressing Enter returns you to the Explorer with a freshly-loaded projects list ready for another run; Esc returns to the current breadcrumb level. Previously there was no way out of the completion screen other than quitting and relaunching the binary.

### Changed

- The TUI execution-provider modal now binds **`g`** (for GPU) to CUDA instead of `u`, with the hint text shortened to "Run with CUDA". `m` for CoreML and `c` for CPU are unchanged.
- Studio validation sessions created from the TUI now carry a platform-aware name and a multi-line description. Names look like `yolov5m-t-27e4_quant-u8-i8_smart-imx95-neutron` — the model filename followed by a `host-npu` tag derived from the machine you're running on. The description block lists hostname, kernel, SoC and core count, NPU with a short detection note, total memory, and the profiler version. Studio's session listings are now self-describing — you can tell at a glance which SoC and accelerator each run came from without opening the session.
- The TUI validation workflow now downloads the model before creating the Studio session, so the platform-aware session name and description are correct on the first request instead of being renamed afterwards. From the user's perspective the "Downloading model" progress bar is unchanged.

### Fixed

- 5000-image validation runs no longer drop the last several frames at the end of the run with a pipeline disconnection error. Long runs now complete with the full frame count actually processed.
- When the profiler skips a frame during inference, the warning now names the file that failed, matching the behaviour of the decode and preprocess skip warnings. Tracking down a bad image in a 5000-image dataset no longer requires guessing.
- The end-of-run pipeline summary now splits the skip count by stage (`decode=N preprocess=N infer=N`) instead of a single lump-sum "decode or processing failure" count, so it's clear which stage actually dropped the frame.
- YOLOv26 ONNX exports with `model.end2end = false` (pre-NMS head) now decode correctly and produce `predictions.parquet`. Previously these models were silently rejected as misconfigured and the run fell back to timing-only mode with no predictions.
- TUI validation sessions no longer stay stuck on the "Running" dashboard forever when the underlying pipeline reports a fatal error (for example, `libonnxruntime.so` not found). The dashboard now transitions to a clearly-marked Failed state with the error message, and the F2 Studio tab no longer keeps showing "Running inference" for a run that has already died.
- The TUI also now surfaces silent crashes — panics, `SIGKILL`, or any path where the child profiler process exits without reporting completion or an explicit error — as a Failed run with a clear message, instead of leaving the dashboard counting elapsed time on a dead run.
- Partial-failure benchmark runs (an error mid-loop with some successful iterations still reported) now correctly stay in the Failed state. The completion popup no longer masks the error popup with stale "success" stats from the iterations that happened to finish first.
- The Failed-state TUI dashboard no longer counts elapsed time on a dead run. The progress bar and FPS row freeze at the moment of failure and switch to red with an explicit "Failed" label, so the failed state is visually distinct from a live run.
- Launching a new run or pressing the stop key now clears any leftover failure state from the previous run. Previously a stale error from a prior failure could be re-reported to Studio, and the old error popup could cover the new dashboard.
- Studio upload progress no longer corrupts the TUI display. Parquet and trace uploads now render through the dashboard's native progress widgets instead of writing terminal escape codes that smeared across the screen.
- The F2 Studio validation screen now resets correctly after a run completes. Switching away to another tab and back no longer redisplays the stale "Complete" or "Failed" page from the previous session.
- The F2 in-dialog progress gauge now also drives upload progress, not just downloads. The gauge stays populated across the parquet-to-trace transition instead of going blank between the two upload steps.
- The F4 Profiler completion popup no longer carries stale upload state into the next run. Launching a second validation run opens a clean popup instead of briefly flashing the previous run's bars at 100% before the new upload starts.

## [1.0.3] - 2026-05-25

### Fixed

- Validation sessions no longer hang at 100% inference. Runs that had completed every frame would previously sit forever with the progress bar pinned at the final frame count, no CPU activity, and no further output — the publish step is now reached every time.
- ONNX Runtime per-op profiling no longer spams `Maximum number of events reached, could not record profile event.` partway through long runs. Per-op data is now collected for roughly the first 3 000 frames (enough for stable per-op statistics on YOLO-class graphs); aggregate stage timing keeps running for every subsequent frame, so the run still produces complete timing output.

### Changed

- Long inference runs now use far less memory at the end. The multi-second pause that used to happen between the last inference and the start of the publish step is gone, and the post-loop ORT profile no longer holds the whole event list in memory at once.
- The CLI now renders dataset, model, predictions, and trace transfers as progress bars in the same style as `edgefirst-cli`, with decimal byte counts (or item counts for dataset enumeration) and ETAs. The TUI is unchanged — it continues to drive its dashboard from the profiler's structured event stream.
- The CLI inference loop is now a single progress bar with elapsed time, ETA, current and total frame counts, and an FPS readout, instead of a one-line `[N/Total] X.X FPS | elapsed: Ys` log every 100 frames.
- The CLI and the TUI parent no longer go silent at the end of a long run. New status lines explain what's happening — "Inference complete. Finalizing results…" between the last frame and stats, "Finalizing trace file…" before the trace is closed, and "Publishing results to Studio…" before the upload — so the gap between the last frame and "results published" is visibly attributed instead of looking frozen.

## [1.0.2] - 2026-05-25

### Added

- The TensorRT shim now ships prebuilt in Linux aarch64 release archives and PyPI wheels. Jetson Orin users on JetPack 6.x can `pip install edgefirst-profiler` or run the install script and immediately use TensorRT models out of the box — no more "TensorRT shim not found" followed by a "build it on the Jetson" detour. Users on other JetPack versions can still build from source.

### Changed

- The profiler now finds its TensorRT shim next to the profiler binary first — both the flat layout used by release archives and the `lib/` sibling used by pip-installed wheels are picked up automatically. The previous `$TRT_SHIM_PATH`, `LD_LIBRARY_PATH`, and `/usr/local/lib` / `/usr/lib` fallbacks still apply.

## [1.0.1] - 2026-05-25

### Fixed

- GitHub Release archives now ship a `.sha256` sidecar alongside each `.tar.gz` / `.zip`. The v1.0.0 release was missing these sidecars, so `install.sh` and `install.ps1` failed their checksum-verification step with a 404 on first install.
- `install.sh` no longer prints `tmpdir: unbound variable` during cleanup on a successful install.

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
