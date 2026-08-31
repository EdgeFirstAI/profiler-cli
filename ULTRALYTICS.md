# Tutorial: Validating an Ultralytics Model Offline

Export a YOLOv8/YOLO11/YOLO26 model from Ultralytics, convert a COCO-style dataset, and run a full accuracy validation with `edgefirst-profiler`. No EdgeFirst Studio account, no metadata embedding step, no network access after the initial downloads.

Exporting is a workstation job, and LiteRT export in particular runs only on macOS or x86-64 Linux. Everything after it, from dataset conversion through validation, runs wherever you point it, including on the edge target itself with the model and images already on disk.

The profiler auto-configures its decoder for vanilla Ultralytics detection and segmentation exports (ONNX and TFLite, including int8, and YOLO26 with or without an end-to-end head) straight from the model's own I/O tensors and export metadata. See [Model Metadata](README.md#model-metadata) for the precedence chain and when you'd still want to embed or override it.

CoreML on Apple silicon auto-configures the same way, but a stock `yolo export format=coreml` won't load at all: it declares an image input the engine can't bind. That's a binding problem rather than a decoder problem, so auto-discovery can't fix it. [Section 6](#6-apple-silicon-native-coreml) covers the export that works.

## 1. Export the model

Install the export backends with Ultralytics rather than letting it fetch them mid-export. It resolves them through `check_requirements` at export time, which needs the network that the rest of this tutorial promises you won't:

```bash
# ONNX export
pip install "ultralytics>=8.4.83" "onnx>=1.12.0,<2.0.0" "onnxslim>=0.1.82" onnxruntime

# LiteRT export, needs Python 3.10+ (ai-edge-quantizer is only for quantize=8)
pip install "ultralytics>=8.4.83" "litert-torch>=0.9.0" "ai-edge-litert>=2.1.4" "ai-edge-quantizer>=0.6.0"
```

```bash
# ONNX
yolo export model=yolo11n.pt format=onnx imgsz=640

# LiteRT (fp32), the format formerly spelled tflite
yolo export model=yolo11n.pt format=litert imgsz=640

# LiteRT (int8, calibrated against a small dataset)
yolo export model=yolo11n.pt format=litert imgsz=640 quantize=8 data=coco8.yaml
```

`format=onnx` writes `yolo11n.onnx` beside the checkpoint. `format=litert` writes `yolo11n.tflite`, and adding `quantize=8 data=coco8.yaml` writes `yolo11n_int8.tflite` instead, where `data=` supplies the calibration images. Both still carry the `.tflite` extension, which is what the profiler dispatches on. Any detection or segmentation checkpoint works the same way: `yolov8n.pt`, `yolo11n-seg.pt`, `yolo26n.pt`.

Ultralytics 8.4.83 renamed this format, which is why the install pins that version: `format=tflite` and `int8=True` still work on it but print a deprecation warning and are rewritten to `format=litert` and `quantize=8`. On an older install the new spellings are simply rejected, and an unpinned `pip install ultralytics` leaves an existing older version alone.

**LiteRT export needs macOS or x86-64 Linux, on Python 3.10 or newer.** Ultralytics asserts the host before it starts, so the export step cannot run on an ARM64 Linux board, and `litert-torch` requires 3.10 where Ultralytics itself still allows 3.8. Export on a workstation and copy the `.tflite` across; the profiler consumes it on any target. ONNX export has neither restriction.

**Running a `.tflite` needs the TensorFlow Lite C++ runtime on the target.** The profiler loads `libtensorflow-lite.so` at run time rather than bundling it, so a standalone binary reports a load error until you set `TFLITE_LIBRARY_PATH` or put the library on the search path. This is the native library, not the Python `tflite` or `tflite_runtime` package. The container images ship it already. ONNX needs nothing extra, which is why the rest of this tutorial uses it.

CoreML is deliberately missing from that list. See [section 6](#6-apple-silicon-native-coreml) for what to run instead.

**YOLO26 is not automatically NMS-free.** The architecture supports an end-to-end head, but whether a given checkpoint exports that way lives in its `end2end` flag, and a stock `yolo26n.pt` reports `end2end=False`: an ordinary `Detect` head with the YOLOv8 output shape `[1, 84, 8400]`, needing NMS like anything else. Check rather than assume:

```bash
python -c "from ultralytics import YOLO; \
h = YOLO('yolo26n.pt').model.model[-1]; \
print(type(h).__name__, h.end2end)"
# Detect False        (stock yolo26n.pt, ultralytics 8.4.152)
```

`Detect False` is an ordinary head, `True` an end-to-end one. The flag travels with the checkpoint, so a model you trained or exported yourself may differ. Read the output.

Both kinds validate correctly without intervention, and both emit the same `model_decode` and `postprocess` spans. An `end2end=True` export skips the NMS step but still reads output tensors and produces boxes, so what changes is time inside `model_decode`, not a stage that disappears.

**Don't assume NMS-free is faster.** The end-to-end head isn't the same graph with a step removed. Selection moves *into* the graph as a fixed top-k over every anchor, so inference itself changes, and whether the resulting graph is quicker or slower is a property of the backend compiling it. Neither direction is safe to assume.

Measure on the hardware you deploy on, and compare throughput and AP rather than `model_decode` alone. Decode is a small share of frame cost on an accelerated route, so a difference there can be swamped by what the new graph costs to run. What you pay either way: the head emits `min(max_det, num_anchors)` detections, so the cap is whatever `max_det` was at export time, and there's no NMS IoU left for `--iou-threshold` to act on.

## 2. Convert the dataset

The profiler validates against the EdgeFirst Dataset Format (Arrow). One `edgefirst-client` command converts a COCO annotation file, fully offline once the JSON and images are local:

```bash
pip install edgefirst-client   # or install the released binary

edgefirst-client coco-to-arrow instances_val2017.json \
    -o val2017/val2017.arrow \
    --images ~/coco/val2017 \
    --link
```

That writes `val2017/val2017.arrow` for the ground-truth annotations and stages the images in `val2017/val2017/`, a folder named after the output stem. That nested path is why the validation command below passes `-i val2017/val2017`. `--link` symlinks rather than copies, which saves real disk on large sets. Drop it to copy.

For a multi-split dataset in one file, point the command at the COCO **directory** instead of one annotation file. It finds the split files and tags each row with the group it came from, in a single pass:

```bash
edgefirst-client coco-to-arrow ~/coco -o coco/coco.arrow --images ~/coco --link
```

`--link` requires `--images`, so name the COCO root for both. Every split's images stage into one folder beside the output, and the `group` column carries which split each row came from.

> [!WARNING]
> Don't run the command twice against the same `-o`. The output is truncated on open, so the second call replaces the first split instead of adding to it. `--group` overrides split inference rather than selecting what to convert.

A merged file is for archival, not for validating one split. Offline validation grades every row in the ground truth it's pointed at, and `--group` only tags rows for later filtering; there's no group selector at validate time. To validate a single split, give that split its own output file.

`-o file.parquet` works the same way if you prefer Parquet. The profiler reads `.arrow`, `.ipc` and `.parquet` ground truth.

## 3. Run validation

```bash
edgefirst-profiler validate \
    -m yolo11n.onnx \
    -i val2017/val2017 \
    --ground-truth val2017/val2017.arrow \
    --no-publish \
    -o results/
```

On startup the console prints how the decoder was configured:

```text
Auto-configured: Ultralytics YOLOv8/11 detect, 80 classes
```

That means auto-discovery matched the model's raw output tensors and Ultralytics export metadata against a known family, with no `edgefirst.json` needed. A segmentation export prints `Ultralytics YOLOv8/11 segment, 80 classes`. A YOLO26 model exported `end2end=True` prints `Ultralytics YOLO26 detect`, while one exported `end2end=False` carries the YOLOv8 output shape and is reported, correctly, as `Ultralytics YOLOv8/11 detect`.

**Overriding auto-discovery.** Drop an `edgefirst.json` (and optionally a `labels.txt`) beside the model file. Useful for a custom head, a renamed class set, or a model auto-discovery doesn't recognize. [Model Metadata](README.md#model-metadata) has the full precedence order, where embedded metadata beats the sidecar and the sidecar beats auto-discovery, plus how to obtain the schema. A sidecar that fails to parse is an error rather than a silent fallback, so fix it or remove it.

**TUI flow.** Launch `edgefirst-profiler` with no arguments, press **F3** for the file browser, and pick the model file. The menu offers **Benchmark**, which runs immediately with latency and throughput only and needs no dataset; **Validate**, which asks for a dataset and then launches with accuracy metrics; and **Live camera**, which is listed for a future release. Datasets are recognized by extension (`.arrow`, `.ipc`, `.parquet`) or as a dataset folder, and picking a dataset first prompts for a model next.

## 4. Inspect the results

A validated run writes five files.

**`metrics.yaml`** is the accuracy report: a `detection` or `segmentation` section carrying COCO-style `AP`/`AP50`/`AP75`/`APs`/`APm`/`APl`/`AR1`/`AR10`/`AR100` at summary and per-class level, a `deployment` section with precision, recall and F1 at one or more confidence thresholds, and the measured `system` and `timing` sections.

**`predictions.parquet`** holds every detection (or mask) the model produced, in EdgeFirst Dataset Format. Together with `trace.pftrace` it's a complete, replayable record, so you can re-grade without touching the model or images again:

```bash
edgefirst-profiler validate \
    --predictions results/predictions.parquet \
    --ground-truth val2017/val2017.arrow \
    --trace results/trace.pftrace \
    -o replay/
```

> [!WARNING]
> `-o` must name a different directory from the one holding the trace. It defaults to `./results`, and every run opens `<output>/trace.pftrace` for writing before it reads anything. Replaying out of `results/` with the default truncates the input trace, then reports metrics with the `system` and `timing.concurrency` sections missing and exits 0.

A replay recomputes the accuracy and deployment sections from the predictions, and recovers the per-stage timing and system telemetry from the trace. It deliberately leaves out `timing.runtime`, which describes the live run's own wall clock and would be meaningless re-inflated, so the replayed document is not byte-identical to the original. That makes it cheap to re-check a threshold sweep or a decoder change without re-running inference.

**`trace.pftrace`** is a Perfetto trace of the full run. Drag it into [ui.perfetto.dev](https://ui.perfetto.dev/) and look for:

- Per-frame spans, to see where time goes: `capture` (reading and decoding the image file), `preprocess`, `infer_submit` and `infer_wait` (dispatch and the wait for the result), `model_decode`, and `postprocess`. A segmentation run adds `materialize_masks` then `mask_encode`, the per-detection PNG encode, which is the first place to look when segmentation throughput disappoints. A backend that copies its outputs back to the host adds `copy_from_device`; a fully zero-copy backend such as Ara240 has no such span, because the decoder reads the output buffers in place.
- `model_decode` covers the whole decode path: box decoding, filtering, proto extraction, and NMS where there is any. It isn't an NMS span, and it's emitted for `end2end=True` models too, so don't read its duration as NMS cost. Which way it moves between the two heads is backend-dependent, so read it off your own trace.
- `frame_e2e`, one **instant** per frame rather than a span, on its own track. It's zero-duration by design, since overlapping frames would be mis-paired by Perfetto's stack-based slice model. The latency sits in its `e2e_us` annotation: the sum of that frame's stage durations, which is the cost of a path through the pipeline rather than the capture-to-result wall time. Select the instant to read it, or query `EXTRACT_ARG(s.arg_set_id, 'debug.e2e_us')`.
- Per-slot device-phase tracks named `<prefix>.<phase>.slot<N>`, when the run uses more than one inference slot or a batch larger than one: `ort.bind.slot0`, `ort.compute.slot0`, `ort.extract.slot0`, and so on for each slot. The prefix is a namespace rather than the backend's name, so a Hailo run's tracks are `npu.h2d.slot0`, never `hailo.…`.

| Prefix | Backends | Phases |
|--------|----------|--------|
| `ort` | ONNX Runtime | `bind` / `compute` / `extract` on the CPU provider, where `Session::run` is the compute. `bind` / `run` / `extract` on every accelerator provider (CoreML, CUDA, QNN HTP), where the call bundles the transfer with the compute and a `compute` label would be a false claim |
| `npu` | Ara240, Hailo | `h2d` / `compute` / `d2h` |
| `trt` | TensorRT | `h2d` / `infer` / `d2h` |
| `device` | TFLite, native CoreML | TFLite: `input_copy`, then `compute` on a CPU-only delegate or the opaque `invoke` on an NPU or external delegate that may bundle transfers inside the call, then `cache_outputs`. Native CoreML: `bind` / `invoke` / `output_read` |

Read the names off your trace rather than deriving them, and fall back to `infer_submit` and `infer_wait` for a backend that reports only a total.

Per-op tracks (`ort.<op>`, `tflite.<op>`) give operator-level hotspots, but **only if the run passed `--layer-profile`** or used a Neutron delegate, which turns the capture on by itself. The commands above do neither, so an ordinary ONNX or TFLite run has no per-op tracks at all. The capture is off by default because it writes a slice per op per frame, which reaches hundreds of megabytes on a 5000-image run.

**`platform.yaml`** records the host that ran inference: CPU, accelerator, OS, board, the resolved per-stage depths, and the profiler version. It's written once and never overwritten, so a directory re-graded later from `predictions.parquet` still names the machine that produced the measurements rather than the one that re-read them.

> [!WARNING]
> Give each run its own `-o` directory. Every other file here is replaced on a re-run, but this one isn't, so a second capture into a directory that already holds a `platform.yaml` keeps the first run's host record and pairs it with the new measurements, silently. `-o` defaults to `./results`, which makes that the easy mistake.

**`profiler.log`** carries the pipeline's warnings and errors at `WARN` and above, as plain text. The console shows these too, but a long run scrolls, so read this first when a result looks wrong. It isn't a complete transcript: a few command-level messages print straight to the console and never reach the file, so check both. A clean run still writes it, and on Linux most of what it reports is routine and harmless to accuracy. Two kinds are worth telling apart. An unavailable *facility*, such as real-time scheduling privileges or a vendor library that didn't load and fell back, can make the run slower than the hardware allows. An unavailable *sensor*, such as a missing hwmon power rail or temperature source, only leaves those gauges reading N/A and changes nothing about the run.

## 5. Accuracy parity

Auto-discovered Ultralytics models agree with `yolo val`'s own reported mAP to within about a point on a 128-image sample (`coco128`, at `--conf-threshold 0.001 --iou-threshold 0.7`, the same score threshold and NMS IoU Ultralytics' validation mode uses). The profiler's evaluator is checked against `pycocotools` on the full COCO val2017 ground truth in the test suite, agreeing to within 1e-9 on every reported statistic. That covers scoring only: the test grades detections it is handed, so it says nothing about how they were decoded. Treat the residual gap against `yolo val` as unexplained by the evaluator rather than as proof the decode is right.

Three flags matter for getting a comparable number. The last two only do anything on an ordinary pre-NMS head, since an `end2end=True` export has already made its selection inside the graph:

- `--conf-threshold 0.001` is the standard mAP protocol threshold, low enough to keep the full precision-recall curve, and the profiler's default. Use a higher value like `0.5` only for deployment-latency benchmarking, where it produces fewer detections and a faster postprocess stage but nothing comparable to a published mAP. This one applies to either head.
- `--iou-threshold 0.7` matches `yolo val`'s NMS convention. Deployment-latency benchmarking typically wants `0.45` instead. Inert on an end-to-end head, which runs no NMS.
- `--pre-nms-top-k` caps how many candidates survive into NMS. Set it to the candidate count of the model's output tensor: `N`, the last dimension of a `[1, 84, N]` detection output, not the `84`. For the 640×640 exports used throughout this tutorial that's the default `8400`. A three-scale head emits `(s/8)² + (s/16)² + (s/32)²`, so a 1280×1280 export has 33600 and the default would silently drop three quarters of them. Truncating before NMS costs recall without raising any error: the run completes and still reports a number. Also inert on an end-to-end head, whose cap is the `max_det` baked in at export.

## 6. Apple silicon: native CoreML

On an Apple silicon Mac the same model reaches the Neural Engine two ways: as a `.mlpackage` through CoreML directly (the **native engine**), or as an `.onnx` through ONNX Runtime's **CoreML execution provider**. Sections 2 to 5 apply unchanged to both, and only the export differs.

Native CoreML needs a binary that includes it, and the published macOS release binaries already do. Contributors building from the profiler source tree enable it with `cargo build --release --features macos`. A binary without it reports:

```text
Native CoreML backend not compiled in. Rebuild with `--features macos`.
```

### Export the matched pair

A stock CoreML export won't load. `yolo export format=coreml` declares an **image input**, a uint8 `CVPixelBuffer` with the 1/255 scale baked in, while the native engine consumes the same float16 planar-RGB tensor the ONNX arm consumes. So it rejects the model:

```text
ERROR Engine creation failed error=reading CoreML inputs of yolo26n.mlpackage
```

That message names the file, not the reason. It means the model declares a feature the engine can't bind: an image input from a stock export, or the `double` threshold scalars an `nms=True` export adds.

Use [`tools/export_fp16.py`](tools/export_fp16.py), which ships beside this tutorial and writes both halves of the pair with float16 at every tensor boundary. The link is relative, so it resolves to the copy from the same release you're reading.

**Needs macOS 13 or newer.** Float16 `MLMultiArray` inputs and outputs require a deployment target of iOS 16 / macOS 13, which the script sets. On anything older the conversion itself succeeds but the load-back check fails, and since nothing is published until both halves verify, the run exits with that error and leaves no artifacts at all.

**Ordinary detection heads only.** The script refuses a segmentation checkpoint, because the converter declares a single `output0` and writes `task: detect`, which would silently drop a segmentation model's second (proto) output. It also refuses an `end2end=True` checkpoint, whose two halves can't be made to match: the CoreML side traces the end-to-end head while Ultralytics' ONNX exporter produces the ordinary-head shape unless told otherwise, and the end-to-end head's `TopK` can't be converted to fp16. Both are refused before either artifact is written, rather than producing a pair that loads, scores, and benchmarks misleadingly.

```bash
# onnxslim is required: the ONNX half exports with simplify=True, and
# Ultralytics would otherwise try to fetch it mid-export. The numpy cap
# matches the one Ultralytics applies to its own CoreML export; this
# script calls coremltools directly, so nothing else enforces it.
pip install "numpy<=2.3.5" "ultralytics>=8.4.83" coremltools onnx onnxconverter-common onnxruntime onnxslim

# Writes into the current directory. --outdir puts them elsewhere, in
# which case prefix the -m paths below to match.
python tools/export_fp16.py yolo26n.pt --imgsz 640
```

It writes `yolo26n_fp16.mlpackage` and `yolo26n_fp16.onnx`, prints each one's declared I/O, and loads both back to prove the artifacts are readable. Neither stock export gets there on its own: `format=coreml` treats `quantize=16` as compute precision only and still declares an image input, and `format=onnx` honours `quantize=16` at the tensor boundary only when exporting from a non-CPU device. On a CPU export, which is what a Mac does, it post-converts with `keep_io_types=True` and leaves the inputs and outputs fp32.

### Validate

The engine follows the file extension, so this is the section 3 command with a `.mlpackage`:

```bash
edgefirst-profiler validate \
    -m yolo26n_fp16.mlpackage \
    -i val2017/val2017 \
    --ground-truth val2017/val2017.arrow \
    --no-publish \
    -o results/
```

A native run defaults to the Neural Engine. `--provider` selects the compute unit, and the value lands in `platform.yaml` as `resolved.coreml_compute_units`:

| Flag | Compute units |
|------|---------------|
| *(none)* | `cpu-and-neural-engine` |
| `--provider coreml-gpu` | `cpu-and-gpu` |
| `--provider coreml-cpu` | `cpu-only` |

**The ONNX arm doesn't default the same way, so always name the provider when comparing the two.** `--provider` defaults to `cpu`, which for an `.onnx` means ONNX Runtime's own CPU kernels, not CoreML and not the Neural Engine. Run the ONNX half of a comparison like this:

```bash
edgefirst-profiler validate -m yolo26n_fp16.onnx --provider coreml-ane \
    -i val2017/val2017 --ground-truth val2017/val2017.arrow \
    --no-publish -o results-onnx/
```

Comparing the two with no flag on either side pits the Neural Engine against a CPU, which isn't a route comparison at all. `coreml-gpu` and `coreml-cpu` mean the same thing on both sides; only the no-flag default differs.

### Where the operations actually ran

`platform.yaml` carries measured per-operation residency, read from CoreML's own compute plan. Both routes report it, the native engine and ONNX Runtime's CoreML provider alike, so this isn't a reason to prefer one over the other. It's how you check either.

```yaml
observed:
  residency:
    total_nodes: 276
    delegated_nodes: 276
```

That's where the model's operations **actually ran**, not where they were requested to run, so a model that quietly falls back to the CPU for part of its graph is visible rather than assumed. The delegated count is withheld entirely when any operation can't be attributed, because a lower bound that reads like an exact count is worse than no count.

Residency needs macOS 14.4 or newer and an ML Program model. That's a higher floor than the macOS 13 the fp16 artifact needs to load, so on macOS 13 through 14.3 the model runs and `observed.residency` is simply absent. An absent report isn't evidence that the requested placement happened, and a model saved as a NeuralNetwork or a Pipeline omits it too.

### Which route to use

On the Neural Engine the two routes sit **at parity per inference and at steady state**: the same 1.8 ms inference and the same peak-second throughput, for `yolo26n` fp16 at 640 on an M2 Max. Accuracy converges to four decimal places of AP, and the compute unit you pick moves accuracy about seven times more than the route does.

Over a whole run the native engine finishes sooner, by roughly 6% on 5000 images, but that's a fixed start-up saving rather than a rate difference, so it shrinks the longer the run goes. Any single ratio quoted for it is really a statement about run length.

So pick on artifact rather than speed: the native engine when CoreML is what you ship, the CoreML EP when ONNX is. Residency isn't a tie-breaker, since both arms read the same compute plan and report it the same way. And a speed comparison only means something when both sides run the same weights at the same precision on the same images: a float16 CoreML package against a float16 ONNX exported from the same checkpoint, not against whatever ONNX was already on disk.
