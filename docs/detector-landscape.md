# The detector landscape, and what we can actually reach (2026-07-31)

*Researched and measured 2026-07-31 for the perception stage; kept as the research record.*

Follow-up to [vision-model-choice.md](vision-model-choice.md), which chose D-FINE-N.
That choice was right and is still the default. What changed is the
discovery of **how much else is one line away** — and that we were unable
to use any of it, because `chase` hardcoded its detector.

Every claim below about our own toolchain was verified by reading
`usls-0.2.0-alpha.3` in the local cargo registry, not from a web page. That
mattered: the research also reported `sam3_litetext_*` constructors, and
**those do not exist in our version** — they are on the upstream `main`
branch. Web docs describe the newest release; you compile against the one
you pinned.

## What `usls` gives us today, verified

Closed-set detection (all COCO-80, all NMS-free DETR descendants,
**all Apache-2.0**):

| Family | Constructors available | Runtime type |
|---|---|---|
| D-FINE | `d_fine_{n,s,m,l,x}_coco`, `_obj365` variants | `RTDETR` |
| DEIM | `deim_dfine_{s,m,l,x}_coco` | `RTDETR` |
| **DEIMv2** | `deim_v2_{atto,femto,pico,n,s,m,l,x}_coco` | `RTDETR` |
| **RF-DETR** | `rfdetr_{nano,small,medium,base,large,xlarge,2xlarge}` + `_seg` | `RFDETR` |
| RT-DETR | v1, v2, v4 | `RTDETR` |

The important structural fact: upstream declares
`pub type DEIMv2 = crate::RTDETR;` and `Config::deimv2()` is literally
`Config::d_fine().with_name("deimv2")`. **DEIMv2 is a drop-in for D-FINE**
— same runtime, same post-processing, different weights. RF-DETR has its
own impl but returns the same `Y { hbbs }`, so extraction is shared.

Open-vocabulary (text-prompted):

| Model | Licence | Note |
|---|---|---|
| Grounding DINO T/B | Apache-2.0 | what we use; **3352 ms/frame measured** |
| **LLMDet** tiny/base/large | Apache-2.0 | CVPR 2025 highlight |
| OWLv2 | Apache-2.0 | base / ft / ensemble |
| YOLOE (v8/11/26) | **AGPL-3.0** | excluded by our licence rule |

Vision-language: Florence-2, Moondream2, SmolVLM, SmolVLM2, FastVLM, BLIP.

## DEIMv2 on COCO — the numbers that matter

Published by the project (Apache-2.0, Sept 2025). **Latency is GPU and does
not transfer to the development laptop** — treat only the AP and parameter columns as
portable.

| Model | AP | Params |
|---|---|---|
| Atto | 23.8 | 0.5M |
| Femto | 31.0 | 1.0M |
| **Pico** | 38.5 | 1.5M |
| **N** | 43.0 | 3.6M |
| **S** | 50.9 | 9.7M |
| M | 53.0 | 18.1M |
| L | 56.0 | 32.2M |
| X | 57.8 | 50.3M |

Against our current **D-FINE-N at 42.8 mAP / 4.0M**:

- **DEIMv2-N** is the same size for +0.2 AP — a free, if marginal, swap.
- **DEIMv2-S** is **+8.1 AP** for 2.4× the parameters. On a robot that must
  not chase a false positive, that looked like the interesting one.
- **DEIMv2-Pico** gives up 4.3 AP to run at 37% of the parameters — the
  option if perception ever has to share the CPU with control.

> These were the *expectations*. See **MEASURED** below: on the development laptop
> DEIMv2-S costs 3.3× the latency, not the 2.5× its GPU table implies, and
> that verdict flipped.

## RF-DETR

Apache-2.0 for nano/small/medium/base/large (**XL and 2XL are PML-1.0** —
do not ship those). Roboflow claims the first real-time model past 60 mAP
on COCO and, more usefully for us, the lead on **RF100-VL**, a
domain-transfer benchmark. That is the metric that predicts behaviour on
objects COCO never photographed — which is every object in a home.

## The open-vocabulary problem is *not* solved

We measured Grounding DINO at **3352 ms/frame (0.30 fps)** — 64× slower
than D-FINE. The obvious hope was that a newer model fixes this. It does
not:

- **LLMDet** builds on MM-Grounding-DINO — the *same* architecture family.
  Expect better accuracy at similar cost, not a speed fix.
- **OWLv2** is a ViT-based open-vocab detector, also not a real-time one.
- The genuinely fast open-vocab models (YOLOE, YOLO-World) are **AGPL-3.0
  and GPL-3.0** respectively, and stay excluded.

So the architecture conclusion stands and is now better evidenced: **open
vocabulary is a goal-setting tool, not a control-loop tool.** Name the
target once at 0.3 fps; track it at 20 fps with a closed-set detector.

**Built, 2026-07-31** — `vision::lock`, 100% covered:

```sh
cargo run --release -p vision --bin chase -- --find "red mug"
```

Grounding DINO interprets the phrase **once**, then hands over a
`TargetLock` and is dropped. D-FINE tracks from there. The control loop
never waits on the slow model.

### The bridge is spatial, not lexical

The obvious design — take Grounding DINO's label and look it up in COCO —
does not work. The phrase is free-form ("mug", "coffee cup", "the thing I
drink from"); COCO's vocabulary is fixed and different ("cup"). String
matching would fail on exactly the flexible phrasing that made open
vocabulary worth having.

So both detectors run on the **same frame** during acquisition and their
boxes are matched by IoU. Whatever COCO class the fast detector reports
*in the same place* is what gets tracked, regardless of what either model
calls it. `MIN_OVERLAP` is a loose 0.30 because the two models were
trained separately and genuinely draw different boxes around one object —
Grounding DINO includes more context, DETR-family models hug the edges.

### Colour is measured, not asked

"Red" never reaches a model. `dominant_hue` computes it from the pixels
and the lock carries it, so *the red mug* is distinguishable from the blue
one beside it — something no COCO class can express. Matching uses
circular hue distance (359° and 1° are 2° apart) with a generous 35°
tolerance, because hue shifts 20–30° between a warm bulb and a window.

Colour washed out by shadow or motion blur **keeps** the lock. Dropping it
on every desaturated frame would make tracking useless, and the candidate
set is already class-filtered.

### It reports what it cannot do

If nothing in COCO-80 overlaps the named object, acquisition fails and
says so, listing what *was* in frame. "Find my keys" has no closed-set
equivalent, and locking onto the nearest plausible box would mean chasing
a wallet while claiming success — the exact failure mode this project has
been bitten by four times.

## What changed in the code because of this

`DFineDetector` became [`ObjectDetector`] with a `DetectorModel` enum, and
`chase` now takes `Box<dyn Detector>`:

```sh
cargo run --release -p vision --bin chase                      # D-FINE-N
cargo run --release -p vision --bin chase -- --model deimv2-pico # 27 fps
cargo run --release -p vision --bin chase -- --find "red mug"  # open-vocab
```

That last line is the one worth noticing. It is not a new feature — every
piece of it was written and tested weeks ago. It did not work because
nothing was wired to the abstraction. See
[architecture-review.md](architecture-review.md).

## MEASURED, 2026-07-31 — on the development MacBook, CPU provider

`cargo run --release -p vision --bin bench -- --synthetic --all`
40 runs each after 5 warmup, same frames for every model.

| Model | COCO mAP | mean ms | fps | p90 ms | mAP/ms |
|---|---:|---:|---:|---:|---:|
| **deimv2-pico** | 38.5 | **36.6** | **27.3** | 37.6 | **1.05** |
| **deimv2-n** | **43.0** | **49.8** | 20.1 | 51.3 | 0.86 |
| d-fine-n *(default)* | 42.8 | 52.4 | 19.1 | 54.0 | 0.82 |
| rfdetr-nano | — | 88.0 | 11.4 | 89.6 | — |
| d-fine-s | 48.5 | 106.0 | 9.4 | 107.6 | 0.46 |
| rfdetr-small | — | 145.2 | 6.9 | 147.3 | — |
| deimv2-s | 50.9 | 164.0 | 6.1 | 166.1 | 0.31 |

**D-FINE-N at 52.4 ms reproduces the 52 ms / 19.5 fps measured end-to-end
in P1**, which is a good sign the harness is honest.

### Four conclusions

**1. DEIMv2-N strictly dominates D-FINE-N.** +0.2 mAP *and* 5% faster,
same Apache-2.0 licence, same `RTDETR` runtime. Free, if marginal. Not
promoted to default: 0.2 mAP is inside the noise, and D-FINE-N is named
across [perception.md](perception.md) and
[vision-model-choice.md](vision-model-choice.md), so the churn costs more than the
win. Use `--model deimv2-n` when you want it.

**2. DEIMv2-S is NOT affordable.** This was the question the sweep existed
to answer. +8.1 mAP for **3.3× the latency** — 164 ms is 6.1 fps, and a
visual servo at 6 fps is sluggish enough to feel. Reserve it for offline
work where accuracy is the only axis.

**3. DEIMv2-Pico is the real speed option** and the best accuracy per
millisecond on the list: 27.3 fps for 4.3 mAP less than D-FINE-N. This is
the one to reach for when perception has to share a CPU with control — the
Stage 3 situation.

**4. RF-DETR is not competitive here.** Nano costs 1.77× DEIMv2-N for no
COCO advantage. Its claim is *domain transfer* (RF100-VL), not COCO mAP, so
it may still earn its place on objects COCO never photographed — but not at
11 fps, and not until we have a labelled clip set to prove the transfer
claim on our own objects.

### The transferable lesson

**Published GPU latency ratios understate CPU differences.** DEIMv2's own
table has S at 2.49× N (5.78 vs 2.32 ms); we measured **3.29×**. Pico is
listed at 0.92× N; we measured **0.73×**.

The reason is structural: at these model sizes a GPU is largely
launch-overhead-bound, so parameter count barely moves the number. A CPU is
compute-bound, so it moves it a lot. Any conclusion of the form "this model
is only slightly slower" that was drawn from a GPU table will be wrong on a
laptop, and wrong in the direction that hurts.

Absolute figures are ~20–30× the published GPU ones. Ratios are the only
part worth carrying across hardware, and even those need a correction.
