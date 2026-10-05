# Which vision model — and does a VLA even need one? (July 2026)

*Researched July 2026 for the perception stage (Stage 1), corrected 2026-07-30; kept as the research record.*

Companion to [perception.md](perception.md). This page
exists because the research turned up something that changes how Stage 1
should be understood.

## The headline finding

**Modern VLAs are end-to-end. Perception lives inside the VLM backbone.
No object detector runs in the control loop.**

Verified from actual model configs, not marketing:

| VLA | Vision comes from | Action head |
|---|---|---|
| **π0 / π0.5** | **PaliGemma** (`gemma_2b`) @ 224² | `gemma_300m` flow-matching, 50-step chunks |
| **SmolVLA** | **SmolVLM2-500M** (SigLIP + SmolLM2), 64 tokens/image | ~100M flow-matching expert |
| **GR00T N1.7** | **Cosmos-Reason2-2B** (Qwen3-VL arch), SigLIP2 ViT | flow-matching DiT, horizon 40 |
| **OpenVLA** | **DINOv2 + SigLIP** fused → Llama-2-7B | discretized action tokens |
| **EO-1** | Qwen2.5-VL-3B | flow matching |
| **ACT / Diffusion Policy** | ResNet per camera | transformer / DDPM |

And **LeRobot has no perception stage at all** — its docs contain zero
detection pages; the observation dict is literally
`observation.images.<camera>` + `observation.state` + a task string.
Policies eat raw frames. The only VLM in that workflow is
`lerobot-annotate`, which runs Qwen2.5-VL *offline* to label recorded
episodes with language — never at control time.

### So is Stage 1 pointless?

No — but be honest about what it's for. **The detector is a teaching
instrument and a utility layer, not a component of the final robot.**

What transfers 100%:
- camera capture, format negotiation, frame timing
- the inference runtime (`ort`) — the same crate later runs whatever
  ONNX-exportable model you want
- preprocessing, letterboxing, tensor layout
- visualization on the Rerun timeline
- **turning a perception output into a control signal** (bearing → PID)
- latency budgeting: what "30 FPS" costs you in a control loop

What gets replaced: the detector itself. Which is fine — you replace it
*inside the same pipeline*, and `usls` already carries the replacements.

What still uses detectors in 2026, genuinely:
- **ROS 2 stacks** (navigation, industrial inspection, safety monitors) —
  because they aren't running VLAs
- **dora-rs dataflows**, where `boxes2d`/`masks` are typed wire primitives
  feeding `yolo → sam2 → object-to-pose → xyzrpy` for classical control
- **safety/monitoring outside the policy** — a VLA is a black box; a
  detector watching for humans is auditable
- **π0.5 predicts bounding boxes *inside its own forward pass*.** From
  [arXiv:2504.16054](https://arxiv.org/html/2504.16054v1), verbatim:
  *"We also label relevant bounding boxes shown in the current
  observation and train π₀.₅ to predict them **before** predicting the
  subtask."* So the actual computation is
  **pixels → predict boxes → predict semantic subtask → predict action
  chunk.** Detection is step one of the VLA itself — trained jointly,
  never a separate model or process. **The capability was absorbed, not
  deleted.**

## The three tiers

### Tier 1 — fixed-class detectors (COCO-80)

> **Corrected 2026-07-30.** An earlier draft of this page recommended
> YOLO26n. Follow-up research on licensing overturned that. The
> permissive alternatives are not a compromise — **they win on the
> benchmarks too.**

| Model | mAP | Params | T4 TensorRT | NMS-free | License |
|---|---|---|---|---|---|
| YOLO11n | 39.5 | 2.6M | 1.5 ms | ✗ | **AGPL-3.0** |
| YOLO26n | 40.9 (40.1 e2e) | 2.4M | 1.7 ms | ✓ | **AGPL-3.0** |
| **DEIMv2-Pico** | 38.5 | **1.5M** | 2.13 ms | ✓ | **Apache-2.0** |
| **DEIMv2-N** | **43.0** | **3.6M** | 2.32 ms | ✓ | **Apache-2.0** |
| **D-FINE-N** | 42.8 | 4M | 2.12 ms | ✓ | **Apache-2.0** |
| **D-FINE-S** | **48.5** | 10M | 3.49 ms | ✓ | **Apache-2.0** |
| RT-DETR-R18 | 46.5 | 20M | ~4.6 ms | ✓ | Apache-2.0 |

**DEIMv2-N beats YOLO26n on mAP *and* is comparable in size. D-FINE-S
beats it by 7.6 mAP.** Both are Apache-2.0, both are in `usls`
(`deim`, `dfine`, `rtdetr`), both are peer-reviewed (D-FINE = ICLR 2025
Spotlight, DEIM = CVPR 2025).

**And NMS-free is not a YOLO26 innovation** — every DETR-family model
(RT-DETR, D-FINE, DEIM) has been NMS-free since 2020. YOLO26 is YOLO
catching up. So the AGPL buys nothing the Apache models don't already
give.

NMS-free still matters enormously, for three reasons: in-graph NMS is
what makes exports partition badly on CoreML and fall back to CPU (see
[perception.md](perception.md)); NMS cost **scales with candidate count**,
so a cluttered frame costs more than an empty one — bad for a fixed-rate
control loop; and it deletes an entire category of Rust post-processing
(no IoU loop, no `conf`/`iou` threshold pair to tune, no
"why are there 400 boxes" debugging).

#### The licensing problem, stated plainly

Ultralytics' [license page](https://www.ultralytics.com/license) says
AGPL-3.0 covers *"code, models, and architectures"*, that compliance
means *"publicly releasing the complete corresponding source code for
the entire derivative work, including the larger application"*, that it
applies **even for internal/R&D use**, and it names **"robotics"** and
**"edge devices"** as Enterprise-License triggers.

Two readings exist — the strict license text (obligations attach on
distribution or network service, so a private local repo trips neither)
versus Ultralytics' stated broader interpretation. **For this project the
distinction is moot:** the repo was written to be publishable (and now
is), and in a public repo the viral clause plausibly
reaches the *entire workspace* — `sim-core`, the firmware, everything.

**Rule adopted: no AGPL/GPL dependency in the default build, ever.** If
YOLOE or YOLO-World are worth experimenting with later, they go behind an
optional Cargo feature (`--features yoloe`) so the core stays
Apache-compatible.

### Tier 2 — open-vocabulary detectors (text prompt → boxes)

**No fast + permissive + open-vocabulary option exists in 2026.** YOLOE is
AGPL-3.0, YOLO-World is GPL-3.0, and the only Apache-2.0 option
(Grounding DINO) is the slow one. That constraint shapes the whole plan.

The 2025 objection ("too slow") is otherwise **dead**:

- **YOLOE26-L: 36.8% LVIS mAP, 32.3M params, 6.2 ms / 161 FPS on T4.**
  vs YOLO-World: +3.5 AP at ⅓ the training cost and 1.4× faster.
  YOLOE26-S beats YOLO-World-S by **+11.4 AP**.
- Three modes: text prompt, visual prompt, and **prompt-free** (built-in
  1200+ LVIS/Objects365 vocabulary).
- **The open-vocab modules cost nothing in closed-set mode** — it
  degrades exactly to YOLO11 speed.
- **Grounding DINO** is production in ROS 2 with a runtime `set_prompt`
  service — but only **23.4 FPS on an AGX Thor**, and NVIDIA's own
  guidance is to distil it to RT-DETR for fixed vocabularies.
- **SAM 3** (848M, Nov 2025) / **SAM 3.1** (2026-03-27) exhaustively
  segment *all* instances of an open-vocabulary concept from a phrase.

#### Two hard truths about open-vocabulary detection

**1. Accuracy is much worse than fixed-class.** YOLO-World-S scores
**18.5 AP on LVIS**; D-FINE-S scores 48.5 mAP on COCO. Different (much
harder) benchmark, but the direction is real: you trade 10–20 points of
reliability for vocabulary freedom.

**2. Attributes are the weak spot — and "red cube" is an attribute
query.** CLIP-style text embeddings handle colour/material adjectives
unevenly. Expect an open-vocab detector to find *a cube* reliably and to
confuse *which colour* far more often than you'd like.

**The pragmatic answer, and it's a good engineering lesson:** detect
"cube" (fixed-class or open-vocab), then classify colour from **HSV
statistics inside the box**. Deterministic, ~0 ms, and essentially 100%
accurate for saturated primaries. Knowing which parts of a problem
deserve a learned component and which deserve ten lines of arithmetic is
worth more than either model.

#### Prompt changes are architectural, not a config flag

- **YOLOE / YOLO-World are "prompt-then-detect"**: the text embedding is
  computed once and **re-parameterized into the detection head's
  weights**. After that it *is* a closed-set detector — zero per-frame
  cost. But in an **ONNX-exported Rust pipeline the vocabulary is frozen
  into the exported graph**, so changing it means re-export unless you
  also run a text encoder at runtime (`usls` does expose
  `encode_texts()`). Practical pattern: pre-encode 20–50 tabletop phrases
  at startup, swap the embedding matrix between frames.
- **Grounding DINO is "fuse-then-detect"**: text and image cross-attend
  inside the network, so prompts are genuine per-inference input — fully
  free-form, no re-export. That flexibility is exactly why it's slow.

### Tier 3 — VLMs that are detector APIs

**Moondream** (3.1 released 2026-07-07) ships five first-class skills:
`query`, `caption`, **`point`** (coordinates), **`detect`** (boxes from
text), `segment` (masks). That is a VLM with a detection API, and `usls`
carries Moondream2 today.

**Florence-2** unifies captioning, OCR, open-vocab detection and
grounding — there's even a [ROS 2 wrapper paper](https://arxiv.org/abs/2604.01179)
(2026-04) whose framing is the whole trend in one line: *"foundation
vision-language models can provide richer semantic perception than narrow
task-specific pipelines."*

## Where the momentum actually is

**VLM-as-perception.** The evidence is unambiguous:

- NVIDIA's own [Dec 2025 guidance](https://developer.nvidia.com/blog/getting-started-with-edge-ai-on-nvidia-jetson-llms-vlms-and-foundation-models-for-robotics/):
  *"VLMs such as VILA and Qwen2.5-VL are becoming a common way to add
  this capability because **they can reason about entire scenes rather
  than only detect objects**."*
- **Jetson AI Lab's 2026 model catalog contains ~48 LLMs/VLMs and zero
  detectors.** No YOLO of any version, no YOLO-World, no Grounding DINO.
- **NanoOWL is frozen** (last commit 2025-02) and **NanoSAM is dead**
  (2023). Neither runs on JetPack 7 / Thor. NVIDIA has effectively
  abandoned open-vocab detection on Jetson in favour of VLMs.

Tier 2 is being squeezed from both sides: YOLO26 eats its speed niche
from below, VLMs eat its flexibility niche from above.

## When VLAs *do* want boxes: as prompts, not preprocessing

A live 2026 research thread argues pure end-to-end VLAs under-ground —
they're weak at *object referring in clutter* — and the fix is to feed
boxes **into** the VLA:

- **HiVLA** ([arXiv:2604.14125](https://arxiv.org/abs/2604.14125)) — VLM
  planner emits subtask + target bounding box; DiT fuses global context
  with high-resolution object-centric crops.
- **VP-VLA** ([arXiv:2603.22003](https://arxiv.org/abs/2603.22003)) —
  renders crosshairs and boxes **directly into the RGB observation** as
  visual prompts. Critique of the mainstream: *"this 'black-box' mapping
  forces a single forward pass to simultaneously handle instruction
  interpretation, spatial grounding, and low-level control."*
- **Point-VLA** ([arXiv:2512.18933](https://arxiv.org/abs/2512.18933)) —
  plug-and-play boxes to resolve referential ambiguity.

None of them replaces the VLA's vision encoder. Detection became a
*prompt*, not a pipeline stage.

## The recommendation

**Stage 1 starts with DEIMv2-N or D-FINE-N** — Apache-2.0, NMS-free,
under 4M params, better mAP than YOLO26n, and already in `usls`. The
point is to build the pipeline, not to admire the model; pick the one
that keeps the repo publishable and makes the *rest* of the code easier.

**Then swap the model, not the pipeline:**

```
DEIMv2-N / D-FINE-N  ──→  YOLOE (feature-gated)  ──→  Florence-2-base  ──→  (VLA)
Apache-2.0, NMS-free      "red cube" → boxes         MIT, 0.23B,           end-to-end
learn the pipeline        60+ FPS, AGPL              phrase grounding       no detector
                                                     ~1 Hz
```

**Florence-2-base is the standout of the VLM tier**: 0.23B params,
**MIT-licensed**, and genuine bounding-box outputs including
`<CAPTION_TO_PHRASE_GROUNDING>`. It is the only entry that is small,
permissive, *and* grounding-capable at once. (Moondream 3 is more capable
but **BSL-1.1**, not OSI-open; Moondream2 is the Apache fallback, Q8/Q4f16
only in `usls`. FastVLM is fast but **cannot emit boxes** — wrong tool.)

Realistic VLM latency on an M-series Mac: **0.3–2 s per query.** Fine for
"which object should I grab?" asked once per attempt; useless at 30 FPS.

**Which points at the architecture that actually matters: fast tracker +
slow reasoner.** Ask Florence-2 for a box once at ~1 Hz, hand it to a
cheap frame-rate tracker. Build that pattern here, because it is
structurally the same as SmolVLA's **asynchronous inference** (decouple
perception/prediction from execution — measured ~30% faster task
completion), which is what Stage 5 would run.

### Encode the cost in the type system

```rust
trait Detector  { fn detect(&mut self, frame: &Image) -> Vec<Detection>; }
trait Promptable { fn set_vocabulary(&mut self, phrases: &[&str]) -> Result<()>; }
```

Keeping `set_vocabulary` a **separate, explicitly expensive** method is
not cosmetic — it directly encodes the prompt-then-detect architecture
(one-time re-parameterization, zero per-frame cost) so the API can't
mislead anyone into thinking prompts are free per frame. Same discipline as
putting capture behind a trait in [perception.md](perception.md).

**And know where it ends:** by Stage 5, the arm's VLA (SmolVLA, π0.5)
takes raw frames and a task string. The detector will not be in that
loop. What remains is everything around it — camera, runtime,
timing, visualization, and the control plumbing that turns a model output
into a wheel command.

## Practical VLA numbers (for Stage 4/5 planning)

| Model | Hardware | Latency | Rate |
|---|---|---|---|
| π0.5 (TensorRT FP8+NVFP4) | AGX Thor | ~49 ms | ~20 Hz |
| π0.5 (PyTorch BF16) | AGX Thor | ~132 ms | 7.6 Hz |
| GR00T N1.7 (TRT full) | AGX Thor | 93.8 ms | 10.7 Hz |
| GR00T N1.7 (TRT DiT-only) | **Orin** | 216.5 ms | **4.6 Hz** |
| SmolVLA | MacBook / consumer GPU / CPU | — | async stack: ~30% faster response, ~2× throughput |

Both big models need **action-chunk execution** (predict 40–50 steps,
execute them open-loop) to reach usable control rates. That's why
`Odometry`-style dead reckoning and local control on the MCU still
matter: the VLA is slow and occasional; the chip is fast and constant.

## Version corrections worth carrying

- There is **no GR00T N2**: N1 → N1.5 → N1.6 → **N1.7 (GA)**. N1.5 was
  *removed* in LeRobot v0.6.0 — pin `lerobot==0.5.1` if you need it.
- Physical Intelligence shipped **two models past π0.5**: π0.6
  (2025-11-17, RL from experience) and **π0.7** (2026-04-16, steerable,
  world-model visual subgoals).
- LeRobot is at **v0.6.0** (2026-07-06) and now has end-to-end **depth
  camera support** (RealSense, 12-bit depth video).
