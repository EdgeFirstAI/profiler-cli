<p align="center">
  <img alt="" src="assets/hero@2x.png" width="512">
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/edgefirst-wordmark-dark.png">
    <img alt="EdgeFirst" src="assets/edgefirst-wordmark-light.png" width="360">
  </picture>
</p>

<h1 align="center">EdgeFirst Profiler CLI</h1>

<p align="center"><i>Command-line interface for the EdgeFirst Profiler — on-target performance measurement for AI vision pipelines.</i></p>

<p align="center">
  <a href="https://github.com/EdgeFirstAI/profiler-cli/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/EdgeFirstAI/profiler-cli?color=3E3371&label=release&style=flat-square"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-linux%20%7C%20macOS%20%7C%20windows-3E3371?style=flat-square">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-EdgeFirst%20EULA-E8B820?style=flat-square"></a>
  <a href="https://edgefirst.studio"><img alt="EdgeFirst Studio" src="https://img.shields.io/badge/EdgeFirst-Studio-E8B820?style=flat-square"></a>
</p>

---

## Why edgefirst-profiler

The EdgeFirst Profiler is a feature of [EdgeFirst Studio](https://edgefirst.studio) that measures how AI vision pipelines actually perform on the hardware they will run on — not on your laptop, not in a simulator, not against an emulated tensor.

- **Per-operator timing on the real device.** Find the actual bottleneck inside your model — the specific Conv layer, the NPU op, the post-processing pass — rather than guessing from a single end-to-end number.
- **Results and traces publish to EdgeFirst Studio.** Compare runs across models, devices, and configurations side-by-side. Track regressions over time. Share findings with your team without copying files around.
- **Validation against your dataset.** Combine a model with a Studio validation session to get mAP / mIoU alongside latency in one command.

<p align="center"><img alt="EdgeFirst Profiler TUI" src="assets/tui-profiler.png" width="780"></p>

## Install

**Linux and macOS**

```sh
curl -fsSL https://raw.githubusercontent.com/EdgeFirstAI/profiler-cli/main/install.sh | bash
```

**Windows (PowerShell)**

```powershell
irm https://raw.githubusercontent.com/EdgeFirstAI/profiler-cli/main/install.ps1 | iex
```

**Python (pip)**

```sh
pip install --user edgefirst-profiler
```

The wheel ships the same precompiled native binary as the curl / PowerShell installers — `pip install` simply drops it into the Python environment of your choice. Use `--user` for a per-user install (the binary lands on your Python user-scripts path — `~/.local/bin/` on Linux, `~/Library/Python/<ver>/bin/` on macOS), inside a `venv` for project-local, or with `sudo` for a system-wide install. Wheels are published for Linux x86_64 / aarch64 (manylinux2014) and macOS arm64; Windows wheels are planned. See the [PyPI project page](https://pypi.org/project/edgefirst-profiler/) for the version index.

**Pin a specific version**

```sh
curl -fsSL https://raw.githubusercontent.com/EdgeFirstAI/profiler-cli/main/install.sh | bash -s -- --version 0.2.0
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/EdgeFirstAI/profiler-cli/main/install.ps1))) -Version 0.2.0
```

The installer detects your OS and architecture, fetches the matching release artifact, verifies its SHA-256, and installs to `/usr/local/bin` (when run as root) or `~/.local/bin` (otherwise). On Windows it installs to `%ProgramFiles%\edgefirst-profiler\` (elevated) or `%LOCALAPPDATA%\Programs\edgefirst-profiler\` (per-user) and updates your `PATH`. Use `--prefix DIR` (or `-Prefix DIR`) to override.

**Verify**

```sh
edgefirst-profiler --version
```

## Examples

**Profile a YOLOv8 model offline (ONNX)**

```sh
edgefirst-profiler validate --model yolov8n.onnx --images ./val
```

**Profile a TFLite model with the NPU on i.MX 95**

```sh
edgefirst-profiler validate --model yolov8n.tflite --delegate libneutron_delegate.so
```

**Validate against an EdgeFirst Studio session and publish results**

```sh
edgefirst-profiler login
edgefirst-profiler validate --session-id v-abc123 --publish
```

<p align="center"><img alt="File Browser" src="assets/tui-files.png" width="780"></p>

## Tutorial: Ultralytics + COCO, fully offline

You can validate any standard Ultralytics detection or instance-segmentation
export — YOLOv8, YOLO11, or YOLO26, ONNX or TFLite, including int8 and
YOLO26's NMS-free heads — against a COCO dataset with no EdgeFirst Studio
account and no network access after the initial downloads. The result is a
full COCO accuracy report (`metrics.yaml`), every prediction the model made
(`predictions.parquet`), and a Perfetto trace (`trace.pftrace`).

**1. Export the model** ([docs.ultralytics.com/modes/export](https://docs.ultralytics.com/modes/export/)):

```sh
pip install ultralytics
yolo export model=yolo11n.pt format=onnx imgsz=640
# int8 TFLite (calibration data required):
yolo export model=yolo11n.pt format=tflite int8=True data=coco8.yaml imgsz=640
```

**2. Convert a COCO dataset** — `edgefirst-client`'s `coco-to-arrow`
command turns a COCO annotation file into the EdgeFirst Dataset Format the
profiler validates against, fully offline once the JSON and images are
local:

```sh
pip install edgefirst-client   # or the released binary
edgefirst-client coco-to-arrow instances_val2017.json \
  -o val2017/val2017.arrow --images ~/coco/val2017 --link
```

**3. Run validation:**

```sh
edgefirst-profiler validate -m yolo11n.onnx \
  -i val2017/val2017 --ground-truth val2017/val2017.arrow \
  --no-publish -o results/
```

The console prints how the decoder was auto-configured — for example
`Auto-configured: Ultralytics YOLOv8/11 detect, 80 classes` — no
`edgefirst.json` needed for a vanilla export. Dropping an `edgefirst.json`
next to the model overrides auto-detection for a custom head or class set.

The same flow works from the TUI: launch `edgefirst-profiler`, press **F3**,
pick the model, then choose **Validate** and pick the dataset (or
**Benchmark** for an immediate latency/throughput-only run with no dataset).

**4. Inspect the results:**

- `results/metrics.yaml` — mAP50-95, per-class AP, and timing percentiles.
- `results/predictions.parquet` — every prediction, in EdgeFirst Dataset
  Format. Re-grade it any time without touching the model or images again:

  ```sh
  edgefirst-profiler validate --predictions results/predictions.parquet \
    --ground-truth val2017/val2017.arrow --trace results/trace.pftrace
  ```

- `results/trace.pftrace` — drag it into
  [ui.perfetto.dev](https://ui.perfetto.dev/) to see per-stage and
  per-operator timing.

Auto-discovered Ultralytics models agree with `yolo val`'s own reported mAP
to within about a point on a 128-image sample across YOLOv8/11/26; the
evaluator itself is verified bit-for-bit against `pycocotools`. For an
apples-to-apples comparison against `yolo val`, add
`--conf-threshold 0.001 --iou-threshold 0.7`. See the [profiler
repository's tutorial](https://github.com/EdgeFirstAI/profiler/blob/main/ULTRALYTICS.md)
for the full walkthrough and validation-methodology reference.

EdgeFirst Studio remains the recommended integrated experience — session
tracking, dashboards, and fleet benchmarking across devices — and the same
artifacts from this tutorial publish there automatically once you're
connected.

## Run with Docker

Pre-built images publish to `ghcr.io/edgefirstai/profiler-cli` on every release — pull and run, no toolchain required.

> **`onnx` / `latest` run inference on the CPU.** GPU measurement requires the `cuda` tag — throughput measured on the `onnx`/`latest` images reflects CPU performance regardless of the GPU in the host.

| Tag | Arch | Use for |
|---|---|---|
| `onnx` / `latest` | amd64 + arm64 | CPU ONNX inference (default; CPU-only) |
| `tflite` | amd64 + arm64 | CPU TFLite inference |
| `cuda` | amd64 + arm64 | NVIDIA discrete GPU (amd64) or Jetson / Orin (arm64) |
| `imx95` | arm64 only | NXP i.MX 95 Neutron NPU |
| `imx8mp` | arm64 only | NXP i.MX 8M Plus VSI NPU |
| `core` | amd64 + arm64 | Binary only — base image for custom runtime mounts |

Immutable per-release tags follow `VERSION-VARIANT` (e.g. `1.6.1-onnx`); the `imx95` and `imx8mp` tags are arm64-only. The `ara240` (Kinara Ara-2) and `hailo` (Hailo-8 / Hailo-8L) images are on the roadmap.

Mount a named volume at `/config` for the cache and EdgeFirst Studio auth token — it persists across runs. The common Studio workflow needs nothing else mounted; bind-mounting a working directory at `/workdir` is only for the advanced CLI form below.

**Launch the TUI** — the default invocation opens the interactive dashboard. Press `F2` to connect to EdgeFirst Studio (log in once; the token persists in the volume) and pull models + validation sessions, or `F3` to browse for local models:

```sh
docker run -it --rm -v edgefirst:/config \
  ghcr.io/edgefirstai/profiler-cli:onnx
```

The same launch works for every variant — add only that variant's GPU or device flags:

```sh
# NVIDIA discrete GPU (amd64) — Jetson / Orin uses --runtime nvidia in place of --gpus all
docker run -it --rm --gpus all -v edgefirst:/config \
  ghcr.io/edgefirstai/profiler-cli:cuda

# NXP i.MX 95 Neutron NPU — i.MX 8M Plus uses --device /dev/galcore in place of /dev/neutron0
docker run -it --rm \
  --device /dev/neutron0 --device /dev/dma_heap/linux,cma \
  -v edgefirst:/config \
  ghcr.io/edgefirstai/profiler-cli:imx95
```

**Advanced — CLI with local files.** To profile a model from the host non-interactively, bind-mount a working directory at `/workdir`, drop `-it`, and pass a `validate` command. `--user "$(id -u):$(id -g)"` keeps output files owned by your local user:

```sh
docker run --rm --user "$(id -u):$(id -g)" \
  -v edgefirst:/config -v "$PWD":/workdir \
  ghcr.io/edgefirstai/profiler-cli:onnx \
  validate --model /workdir/model.onnx --images /workdir/val --count 100
```

The same `-v "$PWD":/workdir` mapping combines with any variant's GPU/device flags — e.g. add `--gpus all --provider cuda` for discrete-GPU CUDA, or the `--device` flags for an NPU image.

## Running with elevated privileges

The profiler runs fine as a normal user, but some measurements benefit from — or require — elevated privileges on the target:

- **Real-time scheduling.** Many systems cap real-time priority for normal users (`RLIMIT_RTPRIO=0`). Running under `sudo` lets the profiler request `SCHED_FIFO` for the inference dispatch threads, tightening the gap between consecutive device executions. Without elevation, scheduling stays at normal priority and profiling continues unaffected.
- **Accelerator device access.** Reaching NPU and accelerator devices on embedded targets — `/dev/neutron0` (i.MX 95 Neutron), `/dev/galcore` (i.MX 8M Plus VSI), or the Ara240 proxy — often requires elevated privileges unless your user has been granted access.

When a run fails on a privilege-related error, the TUI detects it and offers to retry under `sudo` — using passwordless `sudo` where available, otherwise prompting for your password (held only in memory and wiped after use). The elevated invocation preserves only a safe allowlist of environment variables.

To keep output artifacts owned by your user after an elevated run, pass `--output-owner <uid:gid|username>` (or set `EDGEFIRST_OUTPUT_OWNER`); the profiler reassigns ownership of the results once the run completes, so nothing is left root-owned.

## Built on the EdgeFirst Perception Foundation

The EdgeFirst Profiler is built on the [EdgeFirst Perception Foundation](https://github.com/EdgeFirstAI/.github/blob/main/profile/foundation.md), the same zero-copy, platform-aware infrastructure that runs production EdgeFirst perception pipelines. It uses `edgefirst-hal` for hardware-accelerated decode and pre/post-processing, `edgefirst-tflite` and `edgefirst-ara2` for NPU-aware inference, and `edgefirst-client` for Studio integration.

## Supported hardware

| Vendor / family | Notes |
|---|---|
| NVIDIA Jetson Orin / Orin Nano | aarch64; CUDA execution provider via ONNX Runtime (JetPack 6.2 / L4T R36.4, CUDA 12.6). Docker: `cuda` |
| NVIDIA discrete GPU (x86_64) | CUDA execution provider; compute capability sm_70+ (Volta and newer). Docker: `cuda` |
| NXP i.MX 95 | aarch64; Neutron NPU via the TFLite delegate. Validated on FRDM-IMX95-PRO, Toradex Verdin iMX95, and PHYTEC phyFLEX-i.MX 95. Docker: `imx95` |
| NXP i.MX 8M Plus | aarch64; VSI/Vivante NPU via the VX TFLite delegate. Docker: `imx8mp` |
| Kinara / NXP Ara-2 (Ara240) | DVM models via the `ara2-proxy` daemon |
| Hailo-8 / Hailo-8L | HailoRT runtime via HEF models; host-agnostic (Raspberry Pi 5, x86_64, or any Linux machine) |
| Apple Silicon (macOS arm64) | CoreML execution provider (CPU / GPU / ANE) |
| Generic Linux x86_64 / macOS / Windows | CPU profiling and Studio workflow |

## Documentation, support, status

- **Reference documentation:** [edgefirst.studio](https://edgefirst.studio) (the EdgeFirst Profiler section, when published).
- **Issues:** use the [GitHub issue tracker](https://github.com/EdgeFirstAI/profiler-cli/issues) — bug-report and feature-request templates are provided.
- **Support, sales, anything else:** `support@au-zone.com`.

---

<p align="center">
  <sub>Copyright © 2026 Au-Zone Technologies Inc. — Part of <a href="https://edgefirst.studio">EdgeFirst Studio</a>.</sub>
</p>
