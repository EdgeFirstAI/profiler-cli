#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright 2025-2026 Au-Zone Technologies
# SPDX-License-Identifier: Apache-2.0
"""Export an Ultralytics checkpoint to fp16 CoreML and fp16 ONNX.

On the CPU export a Mac performs, neither stock Ultralytics export gives
fp16 tensor boundaries:

* ``format=coreml`` declares an ``ImageType`` input (uint8 CVPixelBuffer,
  1/255 baked in) and fp32 outputs. ``quantize=16`` only sets
  ``compute_precision``.
* ``format=onnx`` with ``quantize=16`` post-converts with
  ``keep_io_types=True``, so the graph's inputs and outputs stay fp32.
  Exporting from a non-CPU device does give fp16 boundaries, because
  Ultralytics halves the model and the sample input before tracing, but
  that path is not available here.

The profiler's zero-copy IOSurface ring carries an fp16 planar-RGB tensor,
and a native-vs-EP comparison is only meaningful when both arms take the
identical input. This script produces that matched pair.

Run one at a time per output directory. The two artifacts are published
together and rolled back together, but that transaction is not locked
against a second copy of this script publishing the same names at the same
moment.
"""

from __future__ import annotations

import argparse
import contextlib
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np


@contextlib.contextmanager
def _patched_arange_out():
    """Work around a coremltools 9.0 TorchScript-frontend gap.

    ``ultralytics.utils.tal.make_anchors`` builds its grid with
    ``torch.arange(n, out=feats[0].new_full(...))`` -- chosen upstream to
    dodge a nondeterministic CUDA cumsum while still inheriting the runtime
    device in traces. That call traces to an ``aten::arange`` node with
    exactly 2 inputs (``end``, ``out``), but coremltools 9.0's TorchScript
    ``arange`` op converter only accepts 1, 5, 6, or 7 traced inputs and
    raises ``ValueError: arange must have exactly 5, 6, or 7 inputs, got 2``.

    Swapping in the mathematically identical ``out``-less call for the
    duration of the trace records the widely supported ``arange.start`` op
    instead. This patches ``torch.arange`` only inside this process, only for
    the trace below -- it does not touch Ultralytics or coremltools on disk,
    and it does not change any value the model computes.
    """
    import torch

    orig_arange = torch.arange

    def arange(*args, out=None, **kwargs):
        if out is not None:
            kwargs.setdefault("dtype", out.dtype)
            kwargs.setdefault("device", out.device)
            return orig_arange(*args, **kwargs)
        return orig_arange(*args, **kwargs)

    torch.arange = arange
    try:
        yield
    finally:
        torch.arange = orig_arange


def export_coreml_fp16(weights: Path, imgsz: int, out: Path) -> Path:
    """Trace the model and convert with float16 MLMultiArray I/O."""
    import coremltools as ct
    import torch
    from ultralytics import YOLO
    from ultralytics.nn.modules.head import Detect

    yolo = YOLO(str(weights))
    model = yolo.model.eval()
    # Detection must be confirmed, not merely un-contradicted, so an unknown
    # task is refused alongside a known-wrong one. The conversion below
    # declares one `output0` and writes `task: detect` regardless, so an
    # unidentified checkpoint would be silently truncated and mislabelled --
    # a segmentation model's second (proto) output simply dropped.
    task = getattr(yolo, "task", None) or getattr(model, "task", None)
    if task != "detect":
        raise SystemExit(
            f"{weights}: task={task!r} is not supported. This exporter writes "
            "the matched fp16 detection pair only, and needs the checkpoint to "
            "report task='detect'; a segmentation checkpoint would also need "
            "its second (proto) output converted."
        )
    # The head must be exactly `Detect`, not merely a detector. RT-DETR
    # reports task='detect' but ends in `RTDETRDecoder`, which is not a
    # `Detect` at all, so the export-mode loop below would skip it and the
    # trace would return its inference tuple instead of the single `output0`
    # this converter declares. `WorldDetect`, `YOLOEDetect` and `v10Detect`
    # do subclass `Detect` and would pass an isinstance check while carrying
    # their own output contracts, so identity is the fail-closed test.
    head = model.model[-1]
    if type(head) is not Detect:
        raise SystemExit(
            f"{weights}: head is {type(head).__name__}, not Detect. This "
            "exporter writes the matched fp16 pair for an ordinary YOLO "
            "detection head only."
        )

    # An end-to-end head cannot be made into a matched pair here. The trace
    # below follows whatever head the checkpoint carries, while Ultralytics'
    # ONNX exporter defaults to the ordinary-head shape, so the two arms would
    # describe different graphs -- and the end-to-end head's `TopK` is on
    # `onnxconverter-common`'s block list, so the ONNX arm would leave fp32
    # islands and trip the Cast guard once the CoreML half had already been
    # built. Refuse up front instead of doing that work twice.
    if bool(getattr(head, "end2end", False)):
        raise SystemExit(
            f"{weights}: end2end=True is not supported. This exporter writes "
            "the matched fp16 pair for an ordinary detection head only; an "
            "end-to-end head exports a different graph on each arm and its "
            "TopK cannot be converted to float16."
        )
    # Ultralytics' own exporter flips every Detect head into export mode before
    # tracing (engine/exporter.py); skipping this leaves Detect.forward returning
    # its training-shape `(tensor, {"one2many": {...}})` tuple, which the tracer
    # cannot handle (a dict mixing a Tensor and a List[Tensor]).
    for m in model.modules():
        if isinstance(m, Detect):
            m.export = True
            m.format = "coreml"
    im = torch.zeros(1, 3, imgsz, imgsz)
    # check_trace=False: Detect._get_decode_boxes caches self.shape and skips
    # recomputing anchors once it matches, so torch.jit.trace's internal re-trace
    # verification pass takes a different branch than the first pass and reports
    # "Graphs differed across invocations!". Ultralytics' own torchscript/openvino
    # exporters (utils/export/torchscript.py, utils/export/openvino.py) hit the
    # same issue and disable the check for the same reason.
    with _patched_arange_out():
        traced = torch.jit.trace(model, im, strict=False, check_trace=False)

    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[ct.TensorType("images", shape=(1, 3, imgsz, imgsz), dtype=np.float16)],
        outputs=[ct.TensorType("output0", dtype=np.float16)],
        compute_precision=ct.precision.FLOAT16,
        # float16 MLMultiArray inputs/outputs need iOS16+; coremltools otherwise
        # defaults to a lower minimum_deployment_target and rejects the dtype.
        minimum_deployment_target=ct.target.iOS16,
    )

    # Carry the Ultralytics metadata across so the profiler's auto-discovery
    # sees the same `names` / `task` / `end2end` keys the ONNX arm sees.
    names = model.names
    mlmodel.user_defined_metadata.update(
        {
            "task": "detect",
            "head": type(model.model[-1]).__name__,
            "end2end": str(bool(getattr(model, "end2end", False))),
            "imgsz": f"[{imgsz}, {imgsz}]",
            "names": str({int(k): v for k, v in names.items()}),
            "batch": "1",
            "channels": "3",
            "author": "Ultralytics",
        }
    )
    mlmodel.save(str(out))
    return out


def _restore_resize_control_inputs(model) -> list[str]:
    """Put `Resize`'s `roi` and `scales` inputs back to float32.

    ONNX types `Resize` asymmetrically: `X` follows the tensor being resized,
    but `roi` (input 1) and `scales` (input 2) are specified as
    ``tensor(float)`` *whatever* `X` is. ``convert_float_to_float16`` does not
    model that exception -- it rewrites every float initializer in the graph --
    so converting `Resize` at all produces a model ONNX Runtime rejects:

        Type 'tensor(float16)' of input parameter (...) of operator (Resize)
        in node (/model.11/Resize) is invalid.

    Converting those two inputs back is what makes fp16 `Resize` legal, and it
    is what a known-good fp16 export of this network does: data input float16,
    `scales` float32 ``[1, 1, 2, 2]``.

    Returns the initializer names it restored, so the caller can report them.
    """
    from onnx import TensorProto, numpy_helper

    inits = {i.name: i for i in model.graph.initializer}
    restored: list[str] = []
    for node in model.graph.node:
        if node.op_type != "Resize":
            continue
        # Inputs are positional: 0=X, 1=roi, 2=scales, 3=sizes. Only 1 and 2
        # are the float-typed exceptions; `sizes` is int64 and never converted.
        for idx in (1, 2):
            if idx >= len(node.input):
                continue
            name = node.input[idx]
            init = inits.get(name)
            if init is None or init.data_type != TensorProto.FLOAT16:
                continue
            if name in restored:
                continue  # two Resize nodes can share one scales initializer
            init.CopyFrom(
                numpy_helper.from_array(
                    numpy_helper.to_array(init).astype("float32"), name
                )
            )
            restored.append(name)
    return restored


def export_onnx_fp16(weights: Path, imgsz: int, out: Path) -> Path:
    """Export fp32 ONNX via Ultralytics, then convert including I/O."""
    import onnx
    from onnxconverter_common import float16
    from ultralytics import YOLO

    # Ultralytics writes the intermediate next to the checkpoint, as
    # `<stem>.onnx`, overwriting whatever is there. Export from a copy in a
    # scratch directory so an existing fp32 export of the same model survives
    # and no unasked-for third artifact is left behind.
    with tempfile.TemporaryDirectory(prefix="export_fp16.") as scratch:
        staged = Path(scratch) / weights.name
        shutil.copy2(weights, staged)
        fp32 = Path(YOLO(str(staged)).export(format="onnx", imgsz=imgsz, simplify=True))
        model = onnx.load(str(fp32))
    # `convert_float_to_float16` refuses to convert the operators in
    # `DEFAULT_OP_BLOCK_LIST`, leaving each one as an fp32 island wrapped in
    # Cast nodes. For a YOLO detection graph exactly one of those operators is
    # present -- `Resize`, twice, on the FPN upsample path -- and leaving it
    # blocked is actively harmful: two fp32 islands force the CoreML execution
    # provider to partition the graph mid-stream, which measured ~2.7x slower
    # per inference on the Apple Neural Engine than the same network exported
    # without them (M2 Max, macOS 27.0, yolo26n @640). The partition is also
    # what shows up as "6 of 372 nodes on the CPU" in CoreML residency.
    #
    # Resize is bilinear/nearest interpolation -- a weighted average of
    # neighbouring pixels, with no accumulation over a long reduction axis --
    # so fp16 is numerically fine for it. The rest of the block list stays:
    # those entries guard operators where fp16 genuinely can lose a model
    # (NonMaxSuppression, TopK, CumSum, Range, Min/Max used with sentinels),
    # and none of them appear in this graph anyway.
    op_block_list = [op for op in float16.DEFAULT_OP_BLOCK_LIST if op != "Resize"]
    # keep_io_types=False is the whole point: the default leaves the graph's
    # inputs and outputs fp32 with Cast nodes inserted, which defeats the
    # zero-copy fp16 handoff.
    model16 = float16.convert_float_to_float16(
        model, keep_io_types=False, op_block_list=op_block_list
    )
    restored = _restore_resize_control_inputs(model16)
    if restored:
        print(f"  Resize control inputs restored to float32: {restored}")

    # convert_float_to_float16 rewrites node and initializer dtypes but leaves
    # the fp32 graph's value_info entries behind. ORT validates every node's
    # declared value_info against its real output type and refuses the model
    # ("Type (tensor(float)) of output arg ... does not match expected type
    # (tensor(float16))"). Dropping the stale entries and re-inferring rebuilds
    # them from the converted graph.
    del model16.graph.value_info[:]
    model16 = onnx.shape_inference.infer_shapes(model16)

    # A surviving Cast is the failure this export exists to avoid: it means an
    # operator stayed fp32 and the graph now has a precision boundary an
    # accelerator has to partition around. Such a model loads and scores
    # correctly while benchmarking as though the route were slow, so it is
    # rejected rather than emitted.
    casts = [n.name for n in model16.graph.node if n.op_type == "Cast"]
    if casts:
        raise SystemExit(
            f"{len(casts)} Cast node(s) survived fp16 conversion: {casts}\n"
            "Each marks an operator left in fp32, which forces an accelerator to "
            "partition the graph. Check which op_type produced them and decide "
            "whether it is safe to drop from op_block_list."
        )

    onnx.save(model16, str(out))
    return out


def report(path: Path) -> None:
    """Print the declared I/O, check it is float16, then load the artifact.

    Two separate checks, because neither implies the other. A float16
    boundary is the whole contract of this script, so an fp32 input or
    output is fatal here rather than a printed note -- without that, a
    converter that quietly kept fp32 I/O produces a pair that loads, scores,
    and silently defeats the zero-copy handoff it exists to enable.

    Loading the artifact catches the other half: a graph whose declared
    boundary types look right but still fails to instantiate (e.g. stale
    ``value_info`` from the pre-conversion graph tripping ONNX Runtime's
    validation on an interior node). Load failures propagate rather than
    being caught and warned about.
    """
    wrong: list[str] = []

    if path.suffix == ".onnx":
        import onnx
        import onnxruntime as ort
        from onnx import TensorProto

        et = {TensorProto.FLOAT: "float32", TensorProto.FLOAT16: "float16"}
        m = onnx.load(str(path))
        for tag, items in (("in ", m.graph.input), ("out", m.graph.output)):
            for t in items:
                tt = t.type.tensor_type
                shape = [d.dim_value or d.dim_param for d in tt.shape.dim]
                dtype = et.get(tt.elem_type, tt.elem_type)
                print(f"  {tag} {t.name}: {dtype} {shape}")
                if tt.elem_type != TensorProto.FLOAT16:
                    wrong.append(f"{t.name}: {dtype}")
        ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])
        print("  loads: OK (onnxruntime.InferenceSession)")
    else:
        import coremltools as ct

        fp16 = ct.proto.FeatureTypes_pb2.ArrayFeatureType.FLOAT16
        spec = ct.models.MLModel(str(path), skip_model_load=True).get_spec()
        for tag, items in (
            ("in ", spec.description.input),
            ("out", spec.description.output),
        ):
            for t in items:
                kind = t.type.WhichOneof("Type")
                if kind == "multiArrayType":
                    ma = t.type.multiArrayType
                    print(f"  {tag} {t.name}: dataType={ma.dataType} {list(ma.shape)}")
                    if ma.dataType != fp16:
                        wrong.append(f"{t.name}: multiArray dataType={ma.dataType}")
                else:
                    print(f"  {tag} {t.name}: {kind}")
                    wrong.append(f"{t.name}: {kind}, not a multiArray")
        ct.models.MLModel(str(path))
        print("  loads: OK (coremltools.models.MLModel)")

    if wrong:
        raise SystemExit(
            f"{path.name}: boundary is not float16: {', '.join(wrong)}\n"
            "This pair is only meaningful with float16 at every tensor "
            "boundary, so nothing has been written to --outdir."
        )


def _remove(path: Path) -> None:
    """Delete `path` whether it is a file or an .mlpackage directory."""
    if path.is_dir():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("weights", type=Path)
    ap.add_argument("--imgsz", type=int, default=640)
    ap.add_argument("--outdir", type=Path, default=Path.cwd())
    args = ap.parse_args()

    args.outdir.mkdir(parents=True, exist_ok=True)

    stem = args.weights.stem

    # Both halves are built and checked in a staging directory and reach
    # --outdir only once both have succeeded. The two artifacts are only
    # meaningful as a pair, and writing each one as it finished would leave a
    # failed second export beside a fresh first one -- an apparently matched
    # pair whose halves came from different runs, which is exactly the
    # comparison this script exists to make trustworthy.
    with tempfile.TemporaryDirectory(prefix="export_fp16.out.") as staging:
        stage = Path(staging)
        coreml = export_coreml_fp16(
            args.weights, args.imgsz, stage / f"{stem}_fp16.mlpackage"
        )
        onnx_out = export_onnx_fp16(
            args.weights, args.imgsz, stage / f"{stem}_fp16.onnx"
        )

        for p in (coreml, onnx_out):
            print(f"{p.name}:")
            report(p)

        # Publishing two paths cannot be one atomic operation, so the
        # existing pair is moved aside first and restored if either move
        # fails. Without that, a failure between the two (no space, no
        # permission, an interrupt) leaves the new half of the pair beside
        # the old one -- the mismatch the staging above exists to prevent,
        # reintroduced at the last step.
        # Backups go to a unique directory inside --outdir, never to a fixed
        # `<name>.previous`: that name may already hold the only surviving
        # output of an earlier publication that was killed part-way, and a
        # rerun must not be what destroys it. Inside --outdir so the rename
        # stays on one filesystem and cannot itself half-fail.
        backup_dir = Path(tempfile.mkdtemp(dir=args.outdir, prefix=".export_fp16.bak."))
        backups: list[tuple[Path, Path]] = []
        written: list[Path] = []
        recovered = True
        try:
            for src in (coreml, onnx_out):
                dst = args.outdir / src.name
                if dst.exists():
                    kept = backup_dir / dst.name
                    # Registered BEFORE the rename, for the same reason `written`
                    # is registered before the move: an interrupt in the window
                    # between them would leave the only copy somewhere rollback
                    # does not look, and the cleanup below would then delete it.
                    backups.append((kept, dst))
                    dst.rename(kept)
                # Registered BEFORE the move, not after it. The staging
                # directory is usually on another filesystem, where moving an
                # .mlpackage is a recursive copy; a failure part-way through
                # leaves a partial directory at `dst` that rollback has to
                # delete before it can put the previous one back.
                written.append(dst)
                shutil.move(str(src), str(dst))
        except BaseException:
            try:
                for dst in written:
                    _remove(dst)
                for kept, dst in backups:
                    # Absent when the interrupt landed before its rename ran,
                    # in which case `dst` was never moved and needs nothing.
                    if kept.exists():
                        kept.rename(dst)
            except BaseException:
                recovered = False
                raise
            raise
        finally:
            if recovered:
                shutil.rmtree(backup_dir, ignore_errors=True)
            else:
                # Holds the only copy of whatever could not be put back.
                print(f"previous artifacts retained in {backup_dir}", file=sys.stderr)

    for dst in written:
        print(f"wrote {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
