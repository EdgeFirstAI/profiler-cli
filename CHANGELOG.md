# Changelog

All notable changes to the **EdgeFirst Profiler CLI** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.8.1] - 2026-06-27

### Added

- **A `--serialize-core` flag on `validate` for clean per-stage latency runs.** This is the command-line equivalent of the dashboard's **s** launch shortcut: it runs every core pipeline stage one frame at a time (no overlap), giving contention-free per-frame latency to compare against the overlapped, throughput-oriented default run. Image decode stays concurrent, and any explicit `--preprocess-depth` / `--inference-depth` / `--postprocess-depth` / `--mask-depth` you also pass takes precedence over the preset.

## [1.8.0] - 2026-06-27

### Added

- **A serialized-core latency preset in the launch dialog.** Press **s** in the dashboard's runtime launch dialog to run with every pipeline stage depth set to 1, so a single inference flows through with no overlap. This gives a clean per-stage latency measurement instead of the overlapped, throughput-oriented timing of the default **Enter** (Auto) launch. It joins the existing Auto and **c** Customize-depths options.
- **NXP Ara240 traces now show a per-layer breakdown of NPU compute time.** For models built with a recent converter (≥ 2.5.0), the NPU compute phase in the trace is split into one slice per layer, in execution order and named by layer (for example `model.22.dfl.Softmax`), so you can see which layers dominate the compute time rather than only its total. The split is an estimate of each layer's share of the measured compute time — the Ara240 reports no per-layer hardware timings — so treat it as relative guidance. Models from older converters show only the total, as before.

### Changed

- **`--model` is now rejected with a clear error when it cannot be used, instead of being silently ignored or misread.** Passing `--model <path>` together with `--session-id` did nothing (the validation session defines its own model); passing a local file path with `--training-session` — where `--model` selects a Studio artifact *by name* — failed later with a confusing "artifact not found". Both combinations now fail fast with an explanatory message. Validating a local model still works with `--model` on its own.

### Removed

- **The persistent CoreML compile cache.** macOS CoreML runs no longer keep a compiled-model cache on disk. The cache could grow without bound, and could serve a stale compiled model after a model file changed in place (for example a re-export or an in-place fix) — so a corrected model sometimes still failed to load. The model is now compiled fresh each run; this one-time compile happens during session setup and does not affect measured inference timings.

## [1.7.0] - 2026-06-25

### Added

- **Power monitoring on Linux devices with a supported power sensor.** Boards with an on-board power monitor now report live power draw on Linux, where the gauges previously always read zero. Each rail is shown under its real name — for example an NVIDIA Jetson's board-input rail and its per-component breakdown — and the session report now includes a board-power line. On targets with no supported sensor, power is reported as unavailable (with a one-time note) rather than shown as a row of zeros.
- **More temperature sensors are reported on Linux.** Sensors exposed only through the hwmon interface — such as the Raspberry Pi 5's RP1 controller and an i.MX95 on-board I3C sensor — are now captured alongside the standard thermal zones, so the temperature readout reflects more of what the board actually measures.

### Changed

- **Power meters now reflect the sensors the device actually has.** The profiler shows a power meter only for each rail it can detect: the CPU/GPU/ANE/DRAM meters on Apple Silicon, and the real board rails on Linux. Devices with no power sensor show no power meters at all, instead of four meters pinned at 0 W.
- **CPU inference runs now report a compute phase for more accurate throughput modeling.** When a model runs on the CPU, Studio can now derive a true compute-bound throughput estimate from the timing breakdown. Accelerator runs (such as Apple CoreML or NVIDIA CUDA) are unaffected.
- **`validate --training-session` now creates and publishes a Studio validation session by default.** Running `edgefirst-profiler validate --training-session t-XXX --model <artifact>` (without a `--session-id`) now creates the validation session, launches the validator, and publishes results to Studio — the same flow the interactive TUI performs — instead of only profiling the model locally. Pass `--no-publish` to keep the previous profile-only behavior (no session created; results written to disk). On read-only/public projects, where a session cannot be created, the run automatically falls back to a local profiling run.

### Fixed

- **Board power is no longer over-reported on devices with a multi-rail power monitor.** On hardware that exposes a board-total rail alongside its per-component rails (such as the NVIDIA Jetson Orin Nano), the total was added to its own components and to unrelated diagnostic channels, inflating the figure several-fold (a measured ~6.7 W board reported as ~29 W). Board power is now counted once, with its true per-rail breakdown.
- **macOS per-component power readings no longer spike to impossible values.** On Apple Silicon the CPU, memory, and Neural Engine power gauges could briefly report wildly high values (thousands of watts) because those sensors update less often than the GPU. Each gauge is now scaled correctly however frequently its sensor reports, including the very first reading.
- **Placeholder temperatures no longer skew the reported average.** On some NXP i.MX95 boards, PMIC thermal zones report a fixed 105 °C when not actively sensing; these are now excluded so the average temperature reflects the real die temperature rather than being inflated by the placeholder.

## [1.6.2] - 2026-06-24

### Added

- **Output files are owned by your user automatically in Docker.** When the profiler runs elevated (the Docker root default, or under sudo) and you bind-mount a working directory, results are reassigned to that directory's owner automatically — no `--output-owner` needed. The explicit `--output-owner` / `EDGEFIRST_OUTPUT_OWNER` still overrides.

### Changed

- **Validation now decodes boxes with multi-label accuracy by default.** Validation and local-prediction runs — any run that scores a model against a dataset of images — now emit one detection candidate per class above the confidence threshold per anchor, matching the Ultralytics `val multi_label=True` decode that COCO mAP evaluation expects, instead of collapsing each anchor to a single argmax class. The box DFL head also now always dequantizes per-channel when the model is per-channel quantized, rather than collapsing to a single per-tensor scale. Together these recover a systematic accuracy delta versus the reference validator — measured **+0.56 pp box / +0.45 pp mask mAP** on COCO val2017 (yolov8n-seg) and up to **~1.6–4.7 pp INT8 mAP** on per-channel-quantized yolo26 box heads. Throughput and model-only profiling are unaffected: they stay on the single-class argmax decode so latency and FPS numbers are never inflated by the extra per-class candidates.
- **Container images run as root by default.** The Docker images now default to the root user, so NPU/GPU device access and real-time scheduling work without passing `--user root`. To run unprivileged instead, pass `--user "$(id -u):$(id -g)"`.

### Fixed

- **Validation no longer appears to hang when a device cannot run a model.** If an accelerator rejects every inference (for example a firmware or driver mismatch on an embedded NPU), the run now stops promptly and reports the underlying device error, instead of silently skipping every frame while the dashboard appears frozen.
- **No crash when offering privilege elevation in a minimal container.** In a container image without `sudo`, the profiler now skips the elevation offer and continues at normal scheduling priority, rather than failing to start the run.

## [1.6.1] - 2026-06-22

### Added

- **Pre-built container images for NXP NPUs and CPU TFLite.** Alongside the existing `onnx`, `cuda`, and `core` tags, the profiler now publishes three more on the GitHub Container Registry: **`tflite`** — CPU TFLite inference, multi-architecture (x86_64 + aarch64); **`imx95`** — NXP i.MX 95 Neutron NPU (arm64); and **`imx8mp`** — NXP i.MX 8M Plus VSI/Vivante NPU (arm64). The two NXP images bundle the vendor delegate and TFLite runtime, so accelerated on-target inference needs no local install — pull the image and map the NPU device (`--device /dev/neutron0` for i.MX 95, `--device /dev/galcore` for i.MX 8M Plus) plus the BSP DMA-heap. See DOCKER.md for the full run commands and required flags.
- **CUDA GPU profiling on NVIDIA Jetson.** The CUDA execution provider (`--provider cuda`) now runs on Linux aarch64 (Jetson / L4T), not only x86_64. The `cuda` container image is correspondingly multi-architecture: x86_64 for discrete NVIDIA GPUs and aarch64 for Jetson (JetPack 6.2, CUDA 12.6); on Jetson, run it with `--runtime nvidia` and the container picks up the Tegra driver automatically. Orin-class devices can now measure GPU inference the same way desktop GPUs do.
- **Validation sessions now record the full machine identity — platform, processor, accelerator, and architecture.** When the profiler creates an EdgeFirst Studio validation session, the session description now spells out the hardware the run happened on across four levels: the **platform** (the productized board or system-on-module and its vendor — for example *NXP FRDM-IMX95-PRO*, *Toradex Verdin iMX95 SOM*, *PHYTEC phyFLEX-i.MX 95*, *Raspberry Pi 5*, or an x86 workstation identified by its motherboard and BIOS), the **processor** (the SoC or CPU with its core type and memory), the **accelerator** that actually ran the model (with live detail such as the Hailo device architecture and firmware version, the NVIDIA GPU model with driver and compute capability, or the Jetson L4T release), and the **architecture**. Boards that share a processor but come from different vendors — the various i.MX 95 development boards, for instance — are now told apart both in the session description and in the session name, which gains a board token (for example `…-verdin-imx95-neutron` versus `…-phyflex-imx95-neutron`). If a hardware-query tool such as `nvidia-smi` or `hailortcli` is not present, the profiler falls back to a generic label and the run is otherwise unaffected.
- **`system-info` subcommand.** Run `edgefirst-profiler system-info` to print how the current machine will be identified — its architecture, processor, accelerator, and platform, plus the session name it would produce — then exit. It loads no inference runtime, so it is a fast way to confirm a host's identity before starting a validation. Pass a model filename (for example `system-info model.hailo8l.hef`) to also see the accelerator and runtime that model would use.
- **Sudo retry after privilege failures on embedded Linux.** When a profiling run fails because the account lacks the privileges needed for NPU or GPU zero-copy access (for example a Kinara Ara240 connection refused for permissions while `ara2.service` is running), the dashboard now explains that elevated privileges are required and offers to re-run the run under `sudo`. If passwordless sudo is not configured, you are prompted for your password first; trace and prediction files are handed back to your user afterward so the EdgeFirst Studio upload still works.
- **Privilege diagnostics in `profiler.log`.** Each run now records whether it had the privileges it needed — the user it ran as, whether it was elevated via sudo, and whether inference obtained real-time scheduling priority or fell back to normal priority. This makes it easy to confirm from the log alone that an elevated retry took effect on targets such as the Raspberry Pi 5.
- **Elevation prompt before runs that can't get real-time scheduling.** On Linux targets where real-time inference scheduling requires elevation (typical on Raspberry Pi), the TUI now asks **before validation starts** whether to run under sudo — for lower and more consistent inter-inference latency — or to continue at normal priority. Passwordless sudo skips the password prompt after you choose “Run with sudo”.
- **`--output-owner` / `EDGEFIRST_OUTPUT_OWNER`.** When the profiler runs elevated, it can hand ownership of the output directory back to a target user (`uid:gid` or username) once results are written — applied automatically when the TUI re-runs under sudo, and available for Docker or root workflows so generated traces and predictions are never left owned by root.

### Fixed

- **Ara240 proxy connection failures now mention when sudo may be required.** If connecting to the Ara240 proxy is denied for permission reasons while `ara2.service` is running, the error message now states that elevated privileges are likely needed instead of implying the service is down.
- **`--max-det` now actually limits the number of detections per image.** The flag was being ignored: every validation run capped detections at the decoder's built-in default of 300 regardless of the value supplied, so lowering or raising `--max-det` had no effect on the results. The configured value is now applied as the post-NMS detection cap as documented (300 still being the default, matching the COCO evaluation protocol).
- **Hierarchical validation datasets are now fully profiled.** Datasets whose images live in sequence subfolders (not only at the dataset root) are now walked recursively, so every downloaded image is processed. Previously only top-level image files were picked up, which could make Studio validation metrics report far fewer images than the dataset actually contains.
- **A model that declares segmentation but produces no masks is now flagged instead of failing silently.** When a model's own metadata declares its task as segmentation but the profiler cannot actually produce masks from it (the model has no mask/prototype output), the profiler now prints a clear error explaining that segmentation was declared but cannot be produced, and surfaces the same notice to EdgeFirst Studio. Previously the run completed with an all-empty mask column and no explanation. The check is driven entirely by the model's declared task — the model or session name has no bearing on it. Detection and latency results are still produced and remain valid; only the segmentation masks are unavailable.
- **Mask materialization failures are no longer swallowed.** If building masks fails for some frames during a segmentation run, the profiler now reports how many frames were affected at the end of the run (and to EdgeFirst Studio) instead of quietly emitting empty masks for them. The run still completes with results for every frame.

## [1.6.0] - 2026-06-19

### Added

- **Docker images.** `edgefirst-profiler` now **also** ships as pre-built container images on the GitHub Container Registry, alongside the existing install script and release binaries — `docker pull ghcr.io/edgefirstai/profiler-cli:onnx` and run, with no Rust toolchain or local install required. Three runtimes publish as separate tags: **`onnx`** (CPU ONNX Runtime — also the default `latest`), **`cuda`** (NVIDIA GPU via the CUDA execution provider), and **`core`** (the bare binary, as a base image for bringing your own runtime). The `onnx` and `core` tags are multi-architecture (x86_64 + aarch64); `cuda` ships for x86_64. Mount a volume at `/config` to persist the decode cache and your EdgeFirst Studio login across runs.
- **`--mask-depth N` — parallelize segmentation mask materialization.** The Materialize Masks stage (build each detection's mask from the prototype tensor, then PNG-encode it) previously ran single-threaded and is the throughput gate for segmentation models — frames materialize one at a time even when the accelerator already has the next result ready. It now fans out across `N` parallel CPU workers, each materializing a different frame concurrently. The default (`0`) auto-selects 2 workers (capped from the host core count); detection-only models ignore the flag and keep a single pass-through worker (no masks to build). The launch-time **Customize pipeline depths** dialog gains a matching **Mask** slider, and the live dashboard and Perfetto trace now report the Materialize Masks stage's effective worker count so its per-stage utilization is shown correctly.

### Changed

- **ONNX CPU profiling is dramatically faster on multi-core machines.** The profiler now automatically balances inference and image-decoding work across the available CPU cores instead of letting every inference session contend for all of them. On a 48-core AWS Graviton4 instance, `yolov8n-seg` validation rose from 17.5 to 94 FPS (and `yolov5n` to 132 FPS) with no configuration changes. The per-session thread split can be overridden with the `EDGEFIRST_ORT_INTRA_THREADS` / `EDGEFIRST_ORT_INTER_THREADS` environment variables, and Arm BF16 fast-math can be turned off with `EDGEFIRST_ORT_BF16_FASTMATH=0`.
- **Faster image pre-processing via the updated EdgeFirst HAL.** This release moves to EdgeFirst HAL 0.25, which speeds up CPU-side image conversion on the file-load → model-input path and tightens its worst-case latency. On macOS the pre-processing stage now runs its GPU work across multiple threads in parallel — a multi-thread `--preprocess-depth` run on Apple Silicon previously serialized every thread on a single shared graphics context, so raising the depth now actually improves pre-processing throughput. Measurements, predictions, and pipeline behaviour are otherwise unchanged on every platform.

## [1.5.1] - 2026-06-16

### Added

- **`--list-models` flag for `validate`.** When `--training-session` is given without `--model`, the CLI now prints every available artifact for that training session and exits instead of silently auto-selecting the first `.onnx` file. The same listing can be requested explicitly at any time with `--list-models`. Re-run with `--model <artifact-name>` to proceed.
- **Custom images with `--session-id` now work.** Passing `--images <dir>` alongside `--session-id` overrides the session dataset for profiling. Validation is disabled automatically in this case (equivalent to `--no-validate`) because the custom images have no ground-truth annotations tied to the session; a warning is printed explaining the forced flag.

### Changed

- **Validator launch failures are now surfaced.** When the EdgeFirst Validator cannot be launched after a profiling run (for example, due to a permission error on the session), the CLI prints an actionable warning and suggests re-running with `--no-validate` to upload results without triggering analysis. Previously the failure was silent.

## [1.5.0] - 2026-06-16

### Added

- **TUI: launch-time "Customize pipeline depths" dialog.** Every run (F4 Start, Studio Validate, local profiling) now opens a launch modal — for ONNX it also picks the execution provider — offering `Enter` to launch with **Auto** depths or `c` to customize. The dialog's four sliders (Capture, Preprocess, Inference, Postprocess) each default to **Auto** and show the value Auto will resolve to for the selected model, runtime, and host; pinning `1-8` is equivalent to passing `--<stage>-depth N`. It warns when a platform limit holds a stage to single-thread concurrency (CPU staging, or the i.MX 8M Plus VxDelegate / i.MX 95 Neutron single-bind delegates). Launching with Auto behaves identically to a CLI run with no depth flags on every host, so a TUI run and the equivalent CLI command produce matching results.
- `--preprocess-depth N` — run the pre-processing stage across N parallel GPU image processor threads. The default (`0`) auto-selects: 4 threads in zero-copy mode, 1 thread in CPU staging mode. Detection results are unchanged; the pipeline is order-independent end to end.
- `--postprocess-depth N` — run the model decoder (DFL + NMS) stage across N parallel threads. The default (`0`) auto-selects based on available CPU cores. On fast NPUs a single post-processing thread limits overall throughput.
- **Per-frame identity on every stage span.** Each pipeline-stage trace slice now carries the `image_name` and `frame_id` it processed, so a slow frame can be attributed to a specific image and its per-stage chain reconstructed.
- **`frame_e2e` per-frame latency marker.** A trace event emitted when each frame's result is ready, carrying `image_name`, `frame_id`, and the frame's end-to-end work-time (`e2e_us`, the sum of its own stage durations).
- **`pipeline_config` trace event.** Each Perfetto trace now opens with a record of the full pipeline geometry — the slot count and concurrency for each stage — so the trace is self-contained and post-processing tools can derive expected FPS and per-stage utilization without reference to a separate copy of the CLI output.
- **Parquet latency columns** — `capture_ms` (file load + image-codec decode), `e2e_ms` (per-frame work-time latency), and `emit_ts_ns` (absolute wall-clock of result emission, for realized FPS) alongside the existing per-stage `timing` struct.
- **TFLite delegate selection dialog.** When running a TFLite model on i.MX 95 or i.MX 8M Plus, a delegate selection dialog now appears at launch — analogous to the ONNX execution-provider modal. Pick the NPU delegate explicitly (Neutron, VX, or CPU/XNNPACK) rather than relying on auto-selection. Models that require the Neutron delegate skip the general dialog and go straight to a Neutron-specific picker.
- **NXP i.MX 95 Neutron: multi-slot inference in CPU-staging mode.** When the kernel DMA-BUF zero-copy patch is absent (e.g. on NXP phytec boards, or when `NEUTRON_ENABLE_ZERO_COPY=0`), the Neutron backend now runs up to 4 independent inference slots in parallel instead of serializing to a single slot. Measured: ~73 FPS at depth 1 rising to ~97 FPS at the auto default of depth 4, with diminishing gains beyond. The launch dialog reflects the active mode and its Auto values.

### Changed

- **Auto inference depth is now tuned per platform.** Leaving inference depth on Auto (the default, or the launch dialog's Auto slider) now picks the value measured fastest for the detected board and runtime instead of a flat 2. The standout is **NXP Ara240 (i.MX 95): throughput roughly doubles at default settings — ~100 → ~200 FPS**. macOS with the CoreML GPU provider gains ~11% (~427 → ~476 FPS), and Raspberry Pi 5 Hailo-8L runs at its accelerator's full depth. Jetson Orin Nano with TensorRT also requests the device's full slot count (the GPU sustains ~357 FPS in MAXN_SUPER), and the offline-image benchmark now keeps those slots fed (see the Jetson throughput entry below). i.MX 95 Neutron and i.MX 8M Plus VX are unchanged (their delegates run one inference at a time). Passing `--inference-depth N`, or pinning the dialog slider, always overrides the Auto value. Per-platform figures are tabulated in the README and `ARCHITECTURE.md`.
- Validation throughput on NXP Ara240 (i.MX95) roughly doubles at default settings: yolov8n on COCO-5K goes from ~118 FPS to ~227 FPS, against a 248 FPS inference-only device ceiling.
- **Much faster TensorRT inference on the Jetson Orin Nano.** End-to-end throughput roughly doubles — to ~277 FPS (YOLOv5n at 640×640, MAXN_SUPER), up from ~150 FPS previously bottlenecked on CPU image decoding. Image capture and pre-processing now run in parallel with inference, and detection outputs are read straight from GPU memory instead of being copied back to the host first. Detection accuracy is unchanged, and runs fall back automatically on hardware without the required GPU memory support.
- **Capture stage renamed.** The file-load + JPEG/PNG decode stage is now named `capture` (was `decode`), distinct from the model-output `model_decode` (NMS + mask decode). The name extends naturally to live-camera capture, where codec time is part of capture. The unused `color_convert` stage is removed — that work is folded into `preprocess`.
- **Latency is reported as per-frame work-time**, not the capture→result wall sojourn. In offline batch the capture workers race ahead of the inference bottleneck, so sojourn balloons with queue backlog (Little's law) and overstates per-image cost; work-time is the stable path latency and matches the report's end-to-end figure. Glass-to-glass sojourn becomes the meaningful number with live-camera capture (documented in `ARCHITECTURE.md`).
- **Breaking:** `--pipeline-depth` renamed to `--inference-depth`; controls the number of concurrent in-flight inference slots. The default (`0`) auto-selects per backend at engine creation; pass an explicit value to override.
- **Breaking:** `--decode-threads` renamed to `--capture-depth`; controls capture stage parallelism (image load + decode). The default (`0`) auto-selects based on available CPU cores. Explicit values are honored unchanged.
- The F4 Pipeline Stages table now reflects actual per-stage parallelism when computing utilization, keeping the bottleneck indicator accurate with the new fan-out.
- **NXP Ara240 auto inference depth raised to 8.** At depth 8, all NPU inference slots stay in flight simultaneously, reaching the device throughput ceiling: ≈194 FPS for YOLOv5n and ≈249 FPS for YOLOv8n at 640×640 on i.MX 95. Passing `--inference-depth N` overrides the Auto value.
- **ONNX CUDA on Linux x86_64 now auto-selects inference depth 4 and preprocess depth 1.** Each additional ORT inference slot overlaps GPU execution with host staging, peaking at depth 4. A single preprocess thread avoids CPU contention with CUDA kernel dispatch. Measured on an RTX 4060 with yolov8n fp16 at 640×640: ≈352 → ≈447 FPS (+27%) over the previous generic defaults. The dialog shows the selected values when Auto is active.
- **CUDA OpenGL interop (zero-copy GPU input path) is now opt-in on x86_64 Linux.** CPU staging is used by default because it is faster on discrete GPUs — the GL→CUDA map step serializes against inference kernel dispatch, while the PCIe DMA path runs independently: measured 347 FPS (CPU staging) vs 238 FPS (GL interop) on an RTX 4060. Set `EDGEFIRST_ENABLE_CUDA_ZEROCOPY=1` to re-enable it for benchmarking or bandwidth-constrained targets where the path was originally intended to help. The previous `EDGEFIRST_DISABLE_CUDA_ZEROCOPY` env var no longer has any effect.
- **Inference dispatch threads now run at elevated scheduling priority.** On macOS, the threads driving device inference are raised to `USER_INTERACTIVE` QoS, biasing them onto performance cores — measured ~+13% throughput on Apple Silicon with the CoreML ANE provider. On Linux, they request `SCHED_FIFO` at a modest real-time priority to bound the idle gap between consecutive device executions when capture-stage CPU decoding competes for cores; the fallback to normal scheduling is silent on systems without the required permissions.

### Fixed

- **NXP i.MX 95 Neutron: clean fallback on boards without the kernel zero-copy patch.** Previously, loading a Neutron model on a board where the DMA-BUF zero-copy driver is not installed caused the profiler to crash immediately on the first frame (the delegate allocated NULL-backed tensors, resulting in a segfault). The profiler now probes DMA-BUF availability immediately after delegate setup; if the probe fails it rebuilds the interpreter in CPU-staging mode and continues normally. Verified on i.MX 95 phytec (no kernel patch → CPU-staging fallback at ~79 FPS) and i.MX 95 pro (patched → zero-copy at ~84 FPS).

## [1.4.0] - 2026-06-11

### Added

- F4 Profiler dashboard now shows a `Setup:` timer next to the elapsed clock, covering model load and warmup. The timer ticks while the engine loads and warms up, then freezes when the first measured frame completes — the same instant the main `Elapsed:` clock starts. The two readouts make it obvious how much of a session was spent preparing versus measuring, and the final on-screen elapsed time now matches the reported total instead of appearing to "rewind" when load/warmup time was subtracted at completion.
- Perfetto traces from multi-slot ONNX runs now place the `ort.bind` / `ort.run` / `ort.extract` device slices at their true wall-clock positions, on one track per inference slot (`ort.run.slot0`, `ort.run.slot1`, …). Overlapping inferences render as real cross-track overlap, and the device timeline ends when the run actually ended. Previously the three durations were packed back-to-back on a single shared track, which with overlapping slots extended the device timeline well past the end of the run (e.g. ~77 s of device slices for a 42 s CPU run). Backends that only report device-side durations without host start times (Ara240, Hailo, TFLite) keep the packed layout but per slot and anchored at each frame's inference start, so their tracks also stay within the real run span.
- V4L2 hardware JPEG decode is now supported on i.MX platforms. The hardware codec path is selected automatically when available, reducing decode latency and CPU load compared to the software decoder.

### Fixed

- The TUI no longer falls behind ultra-fast models. With execution providers sustaining several hundred FPS (e.g. CoreML ANE at ~730 FPS), the dashboard previously processed one progress event per ~100 ms redraw, so the progress bar and frame counter kept animating for several seconds after the run had actually finished. Terminal rendering is now capped at ~30 FPS independent of event arrival, progress events are drained in batches as they arrive, and per-frame statistics are recomputed once per redraw instead of once per frame — the display now tracks the backend in real time at any model speed (and key input latency improves from ~100 ms to ~33 ms).
- Validation runs now report the same `total_time_ms` semantics as inference-only runs: the span from first to last measured frame completion. Previously the validation path reported elapsed time including warmup, dataset prescan, and trace finalization, which inflated the figure relative to the FPS statistics computed over measured frames only.

## [1.3.2] - 2026-06-09

### Changed

- Updated to the latest EdgeFirst HAL library, bringing fixes and improvements to tensor view handling and the batch-tiling code path — the foundations that multi-frame decode and future batched-inference features build on. No change to measurements, predictions, or pipeline behaviour on any platform.

## [1.3.1] - 2026-06-08

### Added

- TensorRT validation now keeps two frames in flight by default — the GPU works on frame N while frame N+1 is being decoded and preprocessed on the CPU, matching the pipelined behaviour already available for ONNX Runtime and Ara240. The Perfetto trace gains `trt.h2d`, `trt.infer`, and `trt.d2h` per-frame timing tracks showing accurate GPU-side durations (measured with CUDA events rather than host-side wall clock, so pipeline overlap no longer inflates the inference figure). **Note:** this release requires rebuilding `libtrt_shim.so` on Jetson before deploying; see `shims/trt-shim/README.md`.

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
- Kinara Ara240 — DVM models via the `ara2-proxy` daemon.
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
