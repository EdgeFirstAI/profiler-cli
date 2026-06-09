# Changelog

All notable changes to the **EdgeFirst Profiler CLI** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.1] - 2026-06-08

### Added

- TensorRT validation now keeps two frames in flight by default — the GPU works on frame N while frame N+1 is being decoded and preprocessed on the CPU, matching the pipelined behaviour already available for ONNX Runtime and Ara-2. The Perfetto trace gains `trt.h2d`, `trt.infer`, and `trt.d2h` per-frame timing tracks showing accurate GPU-side durations (measured with CUDA events rather than host-side wall clock, so pipeline overlap no longer inflates the inference figure). **Note:** this release requires rebuilding `libtrt_shim.so` on Jetson before deploying; see `shims/trt-shim/README.md`.

### Fixed

- Validation sessions on all platforms no longer silently produce zero detections when the runtime selects GPU-backed output buffers. Output buffers are now always allocated as host memory until a fix is available in the underlying HAL; inference and preprocessing paths are unaffected.
- Decoder failures are now reported as a warning at the end of every run. When any frame fails to produce detections due to a decoder error the run reports a count (e.g. "42 of 5000 frames had decoder errors") so unexpectedly low detection counts are visible rather than silently absorbed.

## [1.3.0] - 2026-06-08

### Added

- New `--batch-size N` option (also available in the TUI Profiler screen). In this release, any `--batch-size` value greater than 1 is capped to 1 and logs a warning, because accelerator support for N>1 device batching is still in development; the flag/UI are shipped now so batching can be re-enabled in a later release without changing your workflow.
- ONNX validation on macOS now uses a zero-copy GPU preprocessing path that hands preprocessed pixels straight to ONNX Runtime without an extra CPU normalize or transpose pass. For half-precision (FP16) models this engages automatically on every CoreML variant and on the ONNX CPU run, removing the per-frame CPU copy from the pipeline. Models exported with full-precision (FP32) inputs continue to run on the existing CPU staging path with no change in behaviour — re-export with FP16 inputs to opt into the new fast path. Falls back transparently on macOS configurations where the required GPU extensions aren't exposed.
- ONNX validation on Linux x86_64 with the CUDA execution provider (`--provider cuda`) now has a true zero-copy GPU preprocessing path: the letterboxed, normalized FP32 input is rendered straight into a GPU buffer (an OpenGL PBO registered with CUDA) and bound directly into ONNX Runtime as device memory, eliminating the per-frame host normalize and the host-to-device input copy. It engages automatically for FP32 models and works at any `--pipeline-depth` — the profiler gives each inference slot its own CUDA stream and orders each frame's GPU render→read with a CUDA event, so overlapping inferences stay correct. Detections are identical to the staging path (validated bit-exact on yolov5n across depths 1/2/4). Note on throughput: on a fast discrete GPU (tested on an RTX 3090) this path is *not* faster than the existing staging path — moving the normalize onto the GPU as a float render, and synchronizing it per frame, costs more than the host↔device copies it removes, which are cheap over PCIe. Its expected benefit is on bandwidth-constrained / integrated targets (where the copy is the bottleneck), still to be measured on-device. Falls back transparently to CPU staging when the CUDA-GL interop isn't available.
- macOS ONNX runs can now pin which CoreML compute unit handles the model: ONNX CPU (the existing baseline, unchanged), CoreML CPU (Apple's CoreML CPU kernels), CoreML GPU (Metal Performance Shaders with CPU fallback for unsupported ops), or CoreML NPU (Apple Neural Engine with CPU fallback only). The previous single "CoreML" mode let CoreML's scheduler pick the unit per subgraph, which made the same model land on different hardware across runs and OS releases — the four explicit modes are now the only way to select CoreML, so every measurement reflects exactly the hardware the user asked for. Available via `--provider coreml-cpu` / `coreml-gpu` / `coreml-ane` on the CLI and via the launch-time modal in the TUI; the bare `--provider coreml` value is no longer accepted and prints an error listing the three replacements.
- TUI execution-provider modal is now a navigable list rather than a fixed two-key prompt. Use ↑/↓ to highlight an option and Enter to launch, or press the number shown next to the row (1 through the number of options offered, up to 9) to jump straight to it and launch in one keypress. The same list layout is now used on Linux x86_64 with CUDA available, so the keystroke flow for picking an EP is identical across hosts.
- Traces from NXP Ara240 NPU runs now show a per-frame device timing breakdown — PCIe host-to-device transfer, NPU compute, and PCIe device-to-host transfer on their own timeline tracks (`npu.h2d`, `npu.compute`, `npu.d2h`) — so you can see where each inference spends its time and confirm the NPU stays busy across the run. The track namespace is vendor-neutral (`npu.*` rather than `ara2.*`) so traces from future NPU backends land on the same set of tracks.
- F4 Profiler dashboard now reports live system CPU, application CPU, system memory, and application memory on macOS. All four gauges previously read 0% on every Apple Silicon run because the underlying probes only knew the Linux `/proc` paths; they now use mach / sysctl / `proc_pid_rusage` readers and behave the same as on Linux. The application-CPU reader applies the mach-timebase conversion that Apple Silicon's `proc_pid_rusage` requires (it returns mach ticks, not nanoseconds, so the previous code was reporting roughly 42× too low — typically rounding to 0%). The system-memory denominator is correct from the very first frame instead of starting at 0% until the first per-second sample tick arrives.
- F4 Profiler dashboard now shows live per-component power draw on macOS — CPU package, GPU, Apple Neural Engine, and DRAM controller — alongside the CPU/memory gauges. Readings come from Apple's IOReport framework directly, the same source `powermetrics` uses, so the values match what you'd see in Activity Monitor's Energy tab. No sudo required. On Linux and Windows the rows are present but read 0.0W until a per-platform backend is wired; the trace omits zero readings to keep those files tight.
- F4 Profiler dashboard now shows live CPU and GPU die temperatures on macOS, populated from the SMC sensor namespace (`Tp*`/`Te*`/`Ts*`/`Tg*` keys). The TEMP row used to read N/A on every Apple Silicon run because the previous reader was Linux-only; it now reports the hottest sensor in each zone family, matching what Activity Monitor's CPU temperature shows.
- Recorded pftrace files now capture every system metric the live dashboard displays — system CPU, application CPU, system and process memory, all four power components, per-zone temperatures, and aggregate max-CPU / max-GPU temperature tracks. Each metric lands on its own dedicated track in Perfetto Trace Viewer so post-processing tools (Trace Viewer, `trace_processor` SQL) can reconstruct the same time series after the run. Power and per-sensor temp tracks are omitted on samples where the platform reports zero, keeping Linux and Windows traces tight rather than carrying rows of `0.0W` markers.
- Image decoding now runs across several worker threads, so JPEG decode is no longer the throughput ceiling on fast execution providers. A new `--decode-threads N` flag sets how many decode workers run; the default `0` auto-selects from the available CPU cores (clamped to a measured-safe range), or pass an explicit count to pin it. Detection results are unchanged.
- Starting a Studio validation against a project you can't write to (for example a read-only public project) no longer fails outright. The profiler explains the problem and offers a choice: cancel, or continue with a profiling-only run that still measures the model on the project's dataset and writes `predictions.parquet` and `trace.pftrace` locally without publishing to Studio. The message links to the documentation for creating your own project and copying the dataset over.
- Studio validation now reports live per-stage progress to the web app: download, inference, and upload each advance incrementally (time-throttled to about every 5 seconds) instead of jumping straight from 0% to 100%. The inference stage reports frames processed (e.g. `3100/5000 frames`) and uploads report per-artifact percent. Reporting is best-effort — a failed progress update never blocks or fails the run.

### Changed

- macOS validation runs of FP16 ONNX models now show a lower per-frame CPU cost in the F4 Pipeline Stages panel because the legacy CPU normalize step is bypassed in favour of the new GPU preprocessing path. CPU usage and inference numbers on every other platform / backend pair are unchanged.
- NXP Ara240 NPU validation now keeps several frames in flight at once and feeds the NPU with zero copies: preprocessed images are written straight into the NPU's input buffers and results are read straight from its output buffers. On a representative YOLOv8n model this roughly doubled throughput (about 55 to 99 FPS at `--pipeline-depth 4`) with identical detections. Increase `--pipeline-depth` to keep the NPU busier; other backends are unaffected.
- ONNX validation now honours `--pipeline-depth N` to keep several inferences in flight concurrently, matching the existing Ara240 behaviour. Throughput gain depends on the execution provider: macOS CoreML GPU shows a noticeable lift at depth 2–4; CoreML Neural Engine and the ORT CPU EP benefit mostly from overlapping preprocess with inference because their per-frame device work is serialised by the hardware (ANE) or by CPU contention. Memory usage rises with depth — depth ≥ 2 doubles the model footprint per additional slot — so values above 4 are clamped. Default depth (`2`) keeps memory close to today's single-session footprint while unlocking the preprocess overlap for every provider.
- F4 Profiler trace now shows a three-track per-frame device breakdown for ONNX runs at `--pipeline-depth > 1` — `ort.bind`, `ort.run`, and `ort.extract` Perfetto tracks for input binding, inference, and output extraction respectively. Mirrors the breakdown the Ara240 backend reports and lets you see at a glance whether the macOS IOSurface fast path is collapsing the `bind` time to near-zero.
- Hailo NPU validation now runs through HailoRT's asynchronous inference API with DMA-BUF zero-copy buffers, replacing the previous VStream path. Per-frame device timing lands on the same vendor-neutral `npu.h2d` / `npu.compute` / `npu.d2h` Perfetto tracks as the other NPU backends. Detections are identical and throughput is unchanged on the models tested — the validation pipeline is bound by NPU compute time, so the Hailo NPU is already kept busy and `--pipeline-depth` has little effect on this workload. The Hailo backend now requires an additional support library; see HAILORT.md for build and setup instructions. Validated on Raspberry Pi 5 with Hailo-8L; other Hailo configurations have not been verified yet.
- F4 Profiler dashboard layout: the FPS, Latency, Frames, and Elapsed run statistics moved out of the System panel into a new Run Stats panel directly under the Pipeline Stages table, freeing vertical space in the System panel for the new power gauges. No metrics were lost — the same numbers appear in the same dashboard, just regrouped to be easier to scan at a glance.
- F4 Profiler's Pipeline Stages panel now reflects live performance instead of looking frozen mid-run. While a run is in progress the panel reports each stage over a rolling one-second window, then switches to full-session statistics once the run finishes — previously it showed a cumulative average that gradually settled to a fixed value and stopped visibly moving. Each row now lists the stage's p99 latency, its concurrency, and a utilization figure, and the rows are sorted so the bottleneck stage sits on top, marked with a ◀ indicator. Because utilization accounts for how many frames a stage handles in parallel, the panel now points at the true throughput-limiting stage even when stages overlap or run multi-threaded — something raw per-stage latency alone could not reveal.
- Inference-only profiling (a run with no images directory) now keeps several inferences in flight at `--pipeline-depth > 1`, the same way the full validation pipeline does. On discrete NPUs (NXP Ara240, Hailo) the input and output tensors still cross the PCIe bus on every inference, so overlapping those transfers raises the reported throughput to reflect real sustained FPS rather than a single-inference round-trip. A new `--iterations N` option sets how many inferences a model-only run measures (default 100). Backends that can't run concurrent inferences are unaffected and continue to run one at a time.
- Studio validations now start the Validator app as soon as the session is created, rather than after results are uploaded. The validator downloads the ground-truth annotations while profiling runs, so analysis begins sooner once the run finishes and the results are published.

### Fixed

- Validation detection counts are now deterministic and independent of `--decode-threads`. A geometry-aware EGLImage-cache fix in the HAL stops recycled zero-copy decode buffers from being sampled at a stale geometry by the GPU letterbox — which previously produced slightly wrong counts that also varied run-to-run once parallel decode was enabled. Decode stays zero-copy DMA-BUF.
- Validation on a desktop x86_64 host without DMA-heap access (the common case for a developer workstation) now returns detections instead of silently reporting zero. Previously the per-frame output buffers fell back to shared-memory (SHM) backing that the output decoder couldn't sub-view, so every frame was dropped with an internal error and `predictions.parquet` came out empty. Fixed via the updated EdgeFirst HAL, which prioritises plain host-memory backing and handles the decoder sub-view. Embedded and macOS hosts, which already had DMA / IOSurface backing, are unaffected.

## [1.2.1] - 2026-05-29

### Fixed

- Command-line validation now launches the EdgeFirst Validator app the same way the TUI does — early, right after the session is created, so it analyses results as soon as they upload. The CLI and `publish` flows previously had their own copy of the launch logic, which could behave differently from the TUI; all three now go through a single launch path, so they can no longer drift apart.
- Models with float16 (fp16) inputs and outputs now produce detections. Previously these models — including every TensorRT engine produced by EdgeFirst Studio with `fp16` precision — completed without errors but returned no predictions, leaving `predictions.parquet` empty. fp16-input ONNX models now run on the Linux CUDA and CPU execution providers as well; these previously aborted the run outright with an "Unsupported input dtype" error. Validated on Jetson (TensorRT) and x86_64 CUDA (yolov5n fp16); other platforms and runtimes have not been verified yet.

## [1.2.0] - 2026-05-27

### Added

- The F2 Studio explorer now shows a coloured deployability indicator next to every artifact in a training session. Green means this build of the profiler on this host can run the artifact; yellow means the artifact targets accelerator hardware that can't be confirmed without a runtime probe; red means the artifact targets a different SoC or the matching backend isn't built into this profiler. For yellow and red, a short inline reason explains the diagnosis at a glance — for example `[Hailo-8L] (Hailo runtime and accessory not confirmed)` or `[NXP i.MX 95 Neutron] (TFLite backend not built into this profiler)`. A short legend appears below the list. The indicator is informational only and does not block selection — you can still attempt to profile any artifact.
- New pipelining guide explaining how the validation pipeline overlaps its six stages so the NPU stays busy while the CPU prepares the next frame, what guarantees the bounded-channel design gives you about latency and memory, and how to read stalls in the F4 Pipeline Stages panel. Linked from the README and the architecture overview.

### Changed

- The training session list in the F2 Studio explorer now shows the most recently trained model at the top instead of the bottom. The session you most likely want to validate is the first one highlighted when you open an experiment.
- TensorRT engine-load failures now surface the underlying TensorRT runtime reason — plan-header size mismatch, version mismatch, compute-capability mismatch — instead of the previous generic "deserializeCudaEngine failed" message. Incompatible-artifact failures are now actionable from the profiler's error output alone.

### Fixed

- Validation sessions in EdgeFirst Studio no longer show as "complete" while the profiler CLI is still running. Each stage of a newly-created validation session is now correctly displayed as not-yet-started until work for that stage begins, and the post-profiling analysis step stays visible as a separate stage that remains pending until the EdgeFirst Validator app picks it up and runs. If the validator fails to launch after the profiler finishes uploading results, the analysis stage is now marked with an error instead of being left in a misleading "queued" state.
- EdgeFirst Studio validation sessions launched from the F2 Studio tab for ONNX models now record the actual execution provider in the session name. A CUDA run on a Linux x86_64 host produces a session named like `…-x86_64-onnx-cuda`; a CoreML Neural Engine run on macOS produces `…-macos-onnx-coreml-ane` (similarly `…-coreml-gpu` and `…-coreml-cpu` for the other CoreML compute units); a plain CPU run produces `…-onnx-cpu`. Previously every ONNX session ended in `…-onnx-cpu` regardless of which provider actually ran, which made CPU runs and accelerated runs indistinguishable in Studio's session listings. The execution-provider modal also now opens before the Studio session is created instead of after, so the name is correct on the first attempt rather than relying on a rename afterwards.
- TensorRT `.engine` artifacts produced by EdgeFirst Studio training sessions now load on Jetson targets. Previously every such artifact failed at deserialization, so TensorRT validation on Jetson required pointing the profiler at an `.onnx` and rebuilding the engine locally.
- F4 Pipeline Stages panel now reports correct per-stage timing averages on the second (and any subsequent) validation session launched in the same TUI process. Previously the per-run accumulators were never reset between sessions, so the panel mixed numbers from both runs together — a fast second run could show a mean inference time of 6 ms while the FPS gauge correctly read 300+ frames per second. Each new session now starts from a clean slate, and the displayed averages match the FPS gauge again.
- TUI execution-provider modal no longer drops the last option when the terminal is too short to display the full dialog. The constraint-based layout previously gave the bottom row zero rows when the window was tight, so pressing the number for the last provider on a short terminal had no effect. The modal now reserves space for every option even when it has to shrink other rows, so every choice is selectable regardless of terminal height.

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
