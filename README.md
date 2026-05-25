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


## Built on the EdgeFirst Perception Foundation

The EdgeFirst Profiler is built on the [EdgeFirst Perception Foundation](https://github.com/EdgeFirstAI/.github/blob/main/profile/foundation.md), the same zero-copy, platform-aware infrastructure that runs production EdgeFirst perception pipelines. It uses `edgefirst-hal` for hardware-accelerated decode and pre/post-processing, `edgefirst-tflite` and `edgefirst-ara2` for NPU-aware inference, and `edgefirst-client` for Studio integration.

## Supported hardware

| Vendor / family | Notes |
|---|---|
| NVIDIA Jetson Orin / Orin Nano | aarch64; CUDA execution provider via ONNX Runtime |
| NXP i.MX 95 | aarch64; Neutron NPU via the TFLite delegate |
| Hailo-8 / Hailo-8L | HailoRT runtime via HEF models; host-agnostic (Raspberry Pi, x86_64, or any Linux machine) |
| Kinara Ara-2 | DVM models via the `ara2-proxy` daemon |
| Generic Linux x86_64 / macOS / Windows | CPU profiling and Studio workflow |

## Documentation, support, status

- **Reference documentation:** [edgefirst.studio](https://edgefirst.studio) (the EdgeFirst Profiler section, when published).
- **Issues:** use the [GitHub issue tracker](https://github.com/EdgeFirstAI/profiler-cli/issues) — bug-report and feature-request templates are provided.
- **Support, sales, anything else:** `support@au-zone.com`.

---

<p align="center">
  <sub>Copyright © 2026 Au-Zone Technologies Inc. — Part of <a href="https://edgefirst.studio">EdgeFirst Studio</a>.</sub>
</p>
