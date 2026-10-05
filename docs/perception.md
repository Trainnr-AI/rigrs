# Stage 1 — the perception stack (research, July 2026)

*Researched July 2026 for the perception stage (Stage 1), with measurements through 2026-07-31 and an on-chip status note from August 2026; kept as the research record.*

Goal: live webcam → object detection → detections drive the robot, in Rust,
on Apple Silicon now and Jetson later. Constraints set for it: *most
modern, performant, least complex, least code, state of the art.*

> **The stack: `nokhwa` (camera) → `usls` (detector, on `ort` + CoreML) →
> `rerun` (viewer) → bearing → existing `Pid`.** Roughly 40 lines of glue,
> 4 direct dependencies, no Python, no ffmpeg, no OpenCV, no brew installs.

## Decisions

### Inference runtime: `ort` — but reached *through* `usls`

`ort` 2.0.0-rc.13 (2026-07-28, wrapping ONNX Runtime 1.28) is the only
runtime that survives Stage 4: **CoreML on the Mac today, TensorRT on the
Jetson later, same Rust code** — one `#[cfg]`-gated execution-provider
line changes. `candle`, `tract` and `burn` all mean either a rewrite or
permanently giving up TensorRT (typically 2–5× on Jetson).

Performance is not the risk: Ultralytics measured **YOLO26n at ~21 ms
inference on an M4 with the plain CPU provider — ~32 FPS**. CoreML + ANE
is 3–7× headroom on top, not a prerequisite.

**Do not depend on `ort` directly** — `usls` pins it to an exact version
(`=2.0.0-rc.13` on git main, `=2.0.0-rc.11` on published alpha.3). Two
`ort` requirements in one tree = Cargo resolution failure. Use `usls`'s
feature flags instead.

### Detection layer: `usls`

The one Rust crate that bundles everything: **automatic model download**
(HuggingFace/GitHub, cached), preprocessing/letterboxing, inference, NMS,
annotation, and a model zoo of 49 vision + 13 VLM modules behind one
`Model` trait. No Python export step, ever.

Zoo highlights (all reachable without changing the stack):
YOLO v5–v13 **and v26** · RT-DETR / RF-DETR / D-FINE / DEIM / PicoDet ·
**YOLO-World, YOLOE, Grounding DINO** (open-vocabulary) ·
SAM / SAM2 / **SAM3** · **Florence-2, Moondream2, SmolVLM/2, FastVLM** ·
CLIP / SigLIP / DINOv2-3 · DepthAnything · ByteTrack.

That zoo is the reason to accept its risks: the crate that runs a fixed
detector today runs a *language-promptable* one tomorrow with a config
change, which is exactly this project's trajectory.

**Risks, eyes open:** `0.2.0-alpha.3`, single maintainer ("a personal
project maintained in spare time"), 1 reverse dependency on crates.io,
API churn between 0.1 and 0.2. Mitigation: pin the version, and be
willing to vendor or fork. It is ~45k LoC of otherwise-unavailable work.

### Camera: `nokhwa`, NOT `usls`'s built-in capture

`usls`'s webcam path shells out to ffmpeg and **hardcodes
`uyvy422 @ 1280x720 @ 30fps`** on macOS — if the camera doesn't advertise
that exact triple, it fails to open. It also drags in `video-rs` →
`ffmpeg-next` → `brew install ffmpeg`.

`nokhwa` 0.10.11 (2026-05-15) talks AVFoundation directly, negotiates
whatever the camera actually supports, and needs **zero system
dependencies**. **This single choice removes the entire ffmpeg dependency
chain** — the biggest friction reduction available.

#### Permissions: `cargo run` just works — verified empirically

This was the anticipated trap, and it isn't one. **Tested on the
development Mac during research: 23 lines, 30 fps, no bundle, no `Info.plist`, no
entitlements, no codesigning** — proven with an ad-hoc-signed binary
carrying no `__info_plist` section.

Requirements:
1. Call **`nokhwa_initialize()` first** and wait for its callback.
2. Run from **Terminal.app or iTerm2**, click Allow once.
3. **Do NOT develop from a VS Code/Cursor integrated terminal, or over
   SSH** — the TCC prompt attaches to the wrong parent process.

#### Three design constraints, from day one

- **`Camera` is `!Send`.** Pin it to a dedicated worker thread and ship
  `Buffer`s over a latest-wins channel. (This is the right architecture
  anyway: capture must not block the control loop.)
- **Never use `AbsoluteHighest*` resolution** — it hangs on M2. Use
  `Closest()` and *read back the actual resolution*, because format
  enumeration returns empty on macOS.
- **Log YUY2 straight to Rerun**, converting to RGB only for the model.
  Skips a full conversion on the viewer path.

Measured headroom: capture + conversion + logging together cost **~19% of
one core at 480p**, leaving essentially the whole 33 ms frame budget for
inference.

#### The exit ramp — plan for it now

nokhwa's macOS backend is **disowned by its own maintainer**; 0.11 will
not fix it; Cap and videocall-rs have already migrated away; and the
process-abort bug on external Logitech webcams
([#247](https://github.com/l1npengtul/nokhwa/issues/247)) is unmerged.
Other open macOS issues: [#224](https://github.com/l1npengtul/nokhwa/issues/224)
(camera not released after `stop_stream()`),
[#204](https://github.com/l1npengtul/nokhwa/issues/204) (hangs).

**Therefore: put capture behind a narrow trait from the first commit**, so
swapping in a ~250-line `objc2-av-foundation` backend later is contained
to one file. On the built-in FaceTime camera there is plenty of runway.

#### Camera options ruled out (source-level findings)

- **OpenCV** — its AVFoundation open is *architecturally guaranteed to
  fail the first run*: it calls `requestAccessForMediaType` then
  `return 0` regardless of the answer. It also spins the run loop for only
  0.1 s **and only on the main thread**, so worker-thread capture gives up
  entirely — disqualifying for a robotics pipeline. Plus device indices
  are sorted by opaque `uniqueID`, so **index 0 is not "the built-in
  camera"** and shuffles when you attach a USB cam or pair an iPhone.
  105-package install, `libclang` ritual, and a macOS Tahoe linking wrinkle.
- **video-rs** — `Location` has exactly two variants, `File` and
  `Network`; `avdevice_register_all` is never called.
  [Issue #42](https://github.com/oddity-ai/video-rs/issues/42) requested
  device support and was closed unimplemented. **Cannot capture at all.**
- **gstreamer** — genuinely the *best* permission handling (blocks on an
  `NSCondition` until the user answers; denial surfaces as a catchable
  error), but costs **110 brew packages** including both GTK 3 and 4.
  Revisit only if a real media graph is ever needed.
- **ffmpeg-next** — the sane heavyweight fallback (13 brew deps). If ever
  used: `format::open_with()` is required (`format::input()` passes a null
  iformat and cannot open a device), `opts.set("framerate", "30")` is
  **mandatory** (the default `"ntsc"` = 29.97 fails a `< 0.01` tolerance
  against Macs' exact 30.0), and `pixel_format` is silently overridden —
  always read `decoder.format()` back. Its README says the crate is *"in
  maintenance-only mode."*

### Visualization: `rerun` 0.35 — already ours

No new dependency, and it composes exactly right: log
`AnnotationContext` **once, statically** (class id → colour + label), then
`Image` + `Boxes2D` per frame with only class ids. Boxes logged under the
image's entity path (`cam/image/dets`) render inside the 2D view. Four
lines.

This also keeps the project's established habit intact: detections land on
the same scrubable timeline as odometry and control signals, so
perception bugs are debugged the way physics bugs were.

## On the chip: `crates/blob` (2026-08-13)

Everything above runs on the laptop, because a Pico has no NPU and a QQVGA
frame is 38 KB of its 520 KB. What a Pico *can* do is scan those 19,200
pixels for a colour.

**That is enough to drive the robot**, because visual servoing never asks
where anything *is* — only for the sign of the error:

```text
   blob left of centre  ─▶ turn        blob small  ─▶ drive forward
   blob above centre    ─▶ arm up      blob large  ─▶ drive back
```

⚠️ **No camera height, no tilt, no hand-eye calibration, no link lengths,
no inverse kinematics.** An earlier plan in this repo proposed all of
them; for this task none are needed. One blob yields three independent
errors, which is exactly the three motions the rig has.

One pass, four accumulators, no allocation — the same cost on a chip as on
a laptop. `no_std`, gate-built for both chip targets.

**Hue rather than RGB.** The same object under a desk lamp and by a window
is a very different RGB and nearly the same hue. ⚠️ With a **saturation
floor**, because grey has no hue at all and without one a tracker locks
onto shadows.

### What it deliberately does not do, and the check that half-works

It finds **one** blob by averaging every matching pixel — not connected
components, which would cost memory the chip should not spend. With two
matching objects the centroid lands *between them*, pointing at nothing.

`Blob::looks_like_one_object` compares pixel count to bounding-box area to
catch that. ⚠️ **It only catches well-separated blobs.** Two objects side
by side at the same height fill ~43% of the wide, short box around them
and pass comfortably, while the centroid still points at the gap. Both
cases are pinned by tests — the one it catches *and* the one it misses —
so the limit stays documented rather than becoming folklore.

### Two panics found by probing, not by reasoning

A caller may set `min_pixels: 0`, and `count >= min_pixels` was then true
with **zero** matching pixels: a blob with NaN coordinates and untouched
sentinel bounds `(65535, 65535, 0, 0)`, after which
`looks_like_one_object` panicked subtracting 65535 from 0. A zero width
divided by zero on the first pixel. In a crate destined for firmware.

A third was closed **by construction** rather than guarded:
`error_from_centre` used to take `(width, height)` as arguments, so a
caller could pass a different frame size than `find` saw and get a
confidently wrong steering error. The frame now travels *inside* the
`Blob`.

### Status 2026-08-15: the on-chip path is the one that shipped first

`blob` now runs against a live OV7670 (`firmware/pico-odom/src/camera.rs`
— PIO+DMA capture, brightness-over-mean matching after hue failed twice
under a measured colour cast), and its three errors drive the wheels and
three arm servos with no laptop in the loop. The laptop stack above
remains the plan for detectors and open-vocabulary work; the chip path
is what closes control loops.

## Rejected, with reasons

| Option | Why not |
|---|---|
| **Apple Vision framework** | **No general object detector exists.** Only faces, humans, animals, rectangles, text, barcodes, hand/body pose, class-agnostic saliency. Detecting a mug still requires supplying a CoreML model — the premise (no model, no Python) was false. Plus ~250 lines of `unsafe` FFI, bindings frozen at the Xcode 16.4 SDK, and **zero** Jetson portability. |
| **dora-rs** | Its zero-code path (18 lines of YAML) is real, but **every perception node in the hub is a Python package** (`dora-yolo` wraps ultralytics). macOS is nightly-tested only — regressions don't block their merges — and `hub:` is explicitly unstable. Adopting a daemon + coordinator to run 3 nodes on one machine is pure overhead. **Revisit at: a Jetson, a second machine, or ≥5 nodes.** |
| **Python sidecar** | `usls` closed the LOC gap (~6 lines vs ultralytics' ~10). A process boundary, a serialization format and a second toolchain to save four lines is a bad trade. **Revisit when a model appears that Rust genuinely cannot load** — a VLA policy (SmolVLA/π0) is the likely trigger. |
| **`ultralytics-inference`** | Official, 3 lines, auto-downloads everything — but **AGPL-3.0**. Fine for a private repo, as this one was in July 2026; a landmine once published, as it now is. `usls` is MIT. |
| **`candle` / `tract` / `burn`** | No ONNX (candle), CNN-detection not the optimization focus (tract Metal), 44% ONNX test pass + no NMS/RoPE/RMSNorm ops (burn-onnx). None reach TensorRT. **Nobody has published YOLO-on-Metal FPS for any of them** — you'd be the first to measure. |
| **`kornia-yolo`** | Dead since 2025-03-30. |
| **`coreml-rs`** | WIP, recent versions fail to build on docs.rs. |

## Gotchas worth knowing before writing code

**CoreML execution provider**
- Set `ModelFormat::MLProgram` — the default `NeuralNetwork` has ~30 ops
  vs ~45, and one measured case showed **4.2× purely from op coverage**.
- Set a **model cache directory**; first-run CoreML compilation costs
  1–5 s, and without a cache it recompiles on every session create.
- **Static input shapes.** Dynamic shapes trigger recompilation and erase
  the gains. Every source converged on this independently.
- **Benchmark all four `ComputeUnits` values.** In one documented M1 Pro
  case `CPUOnly` (23.7 ms) beat `CPUAndGPU` (44.1 ms) for a conv-heavy
  encoder. There is no universally right answer.
- Tiny models (<1 MB) are **slower** on CoreML than CPU — dispatch
  overhead dominates.

**Apple Silicon performance counterintuitions (all measured)**
- **FP32 beats FP16 on Mac CPU** (~21 ms vs ~24 ms for YOLO26n). FP16
  only buys file size.
- **Do not set `intra_threads` manually** — ONNX Runtime's auto-threading
  measured 21 ms vs 40 ms hand-configured. Twice as slow.
- Prefer an **NMS-free (end-to-end) export**. In-graph NMS is precisely
  what makes YOLO exports partition badly on CoreML and fall back to CPU
  (the root of onnxruntime#17654: YOLOv8 at ~40 FPS on an M2 Max).

**ort on macOS**
- Links ONNX Runtime **statically** — no dylib, so no rpath/codesigning
  issues on the default path. Conflicts only if another crate ships its
  own ORT.
- rc.11 **dropped Intel macOS**; maintainer: *"expect little to no macOS
  support in general from now on."* A real long-term risk.
- Wire up `tracing-subscriber` + `RUST_LOG=ort=debug` **before** debugging
  any execution provider — ort logs through `tracing`, and without a
  subscriber even explicit failure modes are silent.

**Jetson, for Stage 4**
- `ort` ships **no aarch64-linux CUDA/TensorRT prebuilts**. Budget half a
  day to build ONNX Runtime on-device, or use `load-dynamic` +
  `ORT_DYLIB_PATH` against NVIDIA's Jetson Zoo libraries.
- **The Rust code does not change** — only the build/link step.
- Check JetPack's CUDA version first: ort rc.13 ships CUDA 13 only.

## MEASURED: CoreML cannot accelerate D-FINE (2026-07-31)

The research promised 3–7× from CoreML. We measured **1.00×**, then found
out exactly why. `cargo run --release -p vision --bin bench`:

| Provider | mean | verdict |
|---|---|---|
| CPU | **51.6 ms** | baseline, 19.4 fps ceiling |
| CoreML (static shapes required) | 52.2 ms | identical — every node fell back to CPU |
| CoreML (dynamic shapes allowed) | — | **SIGABRT, exit 134** |

**Root cause, from the ORT logs:**

```
CoreML EP is set to only allow static input shapes. Input has a dynamic
shape. Input: images, shape: {-1,3,640,640}
...
All nodes placed on [CPUExecutionProvider]. Number of nodes: 731
```

The `-1` is a dynamic batch dimension in the shipped ONNX export. usls
sets `RequireStaticInputShapes: true` (which the research recommends), so
CoreML **rejects all 731 nodes** and the graph runs entirely on CPU.

Relaxing that setting doesn't help — it crashes. CoreML tries to compile
the graph and dies in Apple's MIL compiler: *"has unbounded dimension
which is not supported"* → *"shapes of x and y are not broadcastable"* →
abort. C++ exceptions don't cross FFI into catchable Rust errors.
**usls's default is therefore the correct one**: it degrades to CPU
instead of dying.

**The real fix** would be re-exporting the ONNX with a fixed batch
dimension of 1 — a Python step this project deliberately avoids. Not
worth it: 52 ms is a 19 fps ceiling and the pipeline already runs at
~19 fps, so inference is *matched to*, not limiting, the camera.

**This says nothing about the Jetson.** TensorRT compiles engines
ahead-of-time with explicit shape profiles rather than partitioning at
runtime, and handles DETRs well. Stage 4's plan is unaffected.

### How to see this yourself — two independent log gates

This took a wrong turn worth recording. `RUST_LOG=ort=info` produced
*nothing*, and the first hypothesis ("DETR attention ops map poorly to
CoreML") was wrong. There are **two** gates:

| Variable | Controls |
|---|---|
| `ORT_LOG` | the ONNX Runtime **C++** log level — defaults to `error` |
| `RUST_LOG` | the Rust `tracing` subscriber's filter |

The C++ layer filters first, so `RUST_LOG` alone can never reveal
execution-provider diagnostics — the events are never emitted. Both are
required:

```sh
ORT_LOG=verbose RUST_LOG=ort=trace cargo run --release -p vision --bin bench
```

and a `tracing_subscriber` must be installed in `main`, or even that
produces silence.

## MEASURED ON CAMERA: two limits of the fast/slow handoff (2026-07-31)

`vision::lock` works end to end — name a thing in English, track it at
~20 fps, heading error converges to 0.000 and holds. Two limitations only
became visible by pointing a real camera at real objects. Neither blocks
anything; both will mislead someone who does not know about them.

### 1. The lock needs the fast model to be consistent, not correct

D-FINE-N classifies a water bottle as a **"toilet" at 90%**, with IoU 0.99
against Grounding DINO's box for "water bottle". Tracking works perfectly
anyway:

```
"water bottle" -> tracking COCO 'toilet' that is orange (hue 38°)
   toilet 93%  err=+0.002 rad  ->  w=+0.00
   toilet 92%  err=+0.000 rad  ->  w=+0.00     <- locked, stable
```

`class_id` is an **opaque token** meaning "whatever this model calls that
object". D-FINE calls the bottle a toilet on every frame at 85–93%, so
filtering for `toilet` finds the bottle every time. The label is alarming
to read and functionally irrelevant.

The real exposure is not the wrong name — it is **collision**: if a second
object that D-FINE also labels `toilet` enters frame, the lock matches it
too. The hue filter is the only thing separating them, which leads to:

### 2. Box-based hue reads the background on anything transparent

The same run reported the bottle as `orange (hue 38°)`. The bottle is
translucent grey with a purple cap, standing on a **wooden desk**. The hue
is the desk's, seen through and around the bottle.

`dominant_hue` averages over the whole box and assumes the box is mostly
object. That holds for a solid red mug and fails for glass, mesh, wire,
anything thin, and anything backlit. The saturation gate helps (grey is
skipped) but cannot help when the *background* is the saturated thing.

Worth knowing before trusting colour as a discriminator: it is reliable
for saturated opaque objects and close to meaningless otherwise. A centre-
weighted or segmentation-masked sample would fix it; neither is worth
building until something depends on it.

### And one about the slow model

Prompted for "coffee mug" with no mug present, Grounding DINO returned a
box on a **blank wall at 87%**. Open-vocabulary detectors localise the
prompt rather than returning nothing — absence is not something they
express well.

Acquisition correctly refused to lock, because no COCO object overlapped
that region. The spatial cross-check turns out to be a **sanity filter on
open-vocab false positives**, which is a better argument for it than the
one it was designed around (bridging free-form phrases to a fixed
vocabulary).

## Reality check

**There is no public example anywhere of webcam → YOLO → Rerun in Rust on
macOS.** GitHub search finds two Rust webcam+YOLO repos (one Linux-only,
one a 0-star practice project) and zero YOLO+Rerun repos. The ~40 lines of
glue we write will not exist on the internet until we write them.

## Build order

Each step is independently verifiable — the project's standing rule
(check the screen, not the exit code) applies throughout.

| Step | Deliverable | Proves |
|---|---|---|
| **P0** | webcam frames live in Rerun, nothing else | permissions, camera negotiation, the `!Send` threading shape |
| **P1** | YOLO26n boxes drawn over those frames | model download, CoreML EP, latency budget |
| **P2** | detection → bearing → **existing `Pid`** → sim robot turns | the actual point: perception driving control |
| **P3** *(optional)* | swap YOLO26n → YOLOE, prompt "red cube" | language-conditioned perception, one config line |

P0 is the one that de-risks everything: it settles the permission
question on *the development* machine before a single ML dependency is added.

## Model choice

See [vision-model-choice.md](vision-model-choice.md) — the question of fixed-class
vs open-vocabulary vs VLM-grounding, and whether a detector is even part
of a VLA stack, is consequential enough to deserve its own page.

## Sources

[usls](https://github.com/jamjamjon/usls) ·
[ort](https://github.com/pykeio/ort) · [ort docs](https://ort.pyke.io/) ·
[nokhwa](https://github.com/l1npengtul/nokhwa) ·
[rerun](https://github.com/rerun-io/rerun) ·
[ONNX Runtime CoreML EP](https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html) ·
[onnxruntime#17654 (YOLO/CoreML partitioning)](https://github.com/microsoft/onnxruntime/issues/17654) ·
[CoreML 6.8× writeup](https://www.xybrid.ai/blog/onnx-runtime-6x-faster-apple-silicon-coreml) ·
[SAMURAI ComputeUnits benchmarks](https://egordmitriev.dev/blog/2026-05-18-optimizing-samurai-part-3) ·
[Ultralytics Rust crate](https://github.com/ultralytics/inference) ·
[dora-hub](https://github.com/dora-rs/dora-hub) ·
[objc2-vision](https://docs.rs/objc2-vision/latest/objc2_vision/) ·
[kornia-rs](https://github.com/kornia/kornia-rs)
