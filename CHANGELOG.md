# Changelog

All notable changes to the **EdgeFirst Profiler CLI** are documented
in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-05-25

Initial public release of the EdgeFirst Profiler CLI — an on-target
profiling agent for AI vision pipelines, designed to characterize
real-world inference performance on the hardware your model will
actually run on.

### Platforms

- Linux x86_64 (glibc 2.17+ / manylinux2014)
- Linux aarch64 (glibc 2.17+ / manylinux2014)
- macOS arm64 (macOS 11+)

Windows support is planned and not yet shipped; the installer prints
a clear message for Windows users in the meantime.

### Edge hardware support

- NVIDIA Jetson Orin / Orin Nano — CUDA via ONNX Runtime, optional
  TensorRT execution provider.
- NXP i.MX 95 — Neutron NPU via the TFLite delegate.
- NXP i.MX 8M Plus — VSI NPU via the TFLite delegate.
- Raspberry Pi 5 — CPU baseline plus optional accelerators.
- Kinara Ara-2 — DVM models via the `ara2-proxy` daemon.
- Hailo-8 / Hailo-8L — via HailoRT.
- Apple Silicon — CoreML execution provider via ONNX Runtime.

### Execution providers

ONNX Runtime is the default, lowest-common-denominator backend. Vendor
backends opt in per build: TFLite (with NXP Neutron and VSI delegates),
Hailo, TensorRT, Apple CoreML.

### Features

- Per-operator timing dashboard with a live terminal UI (TUI).
- Pipeline orchestrator with 4-thread pipelined validation for
  realistic-throughput measurements.
- EdgeFirst Studio integration: launch profiling sessions from Studio,
  report status and progress, publish traces and validation runs to
  your Studio account.
- Offline-first: runs without a Studio account; Studio sign-in is
  only required to publish or pull data.

### Distribution

- Standalone binary archives via GitHub Releases on
  [EdgeFirstAI/profiler-cli](https://github.com/EdgeFirstAI/profiler-cli)
  (`install.sh` / `install.ps1` resolve the latest version).
- Python wheels on PyPI as `edgefirst-profiler` — the wheel ships the
  same native binary as the standalone archive, installed onto your
  `PATH` via `pip install edgefirst-profiler`.
