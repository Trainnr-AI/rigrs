# Simulator design (Stage 0), revised after red-teaming

*Written July 2026 for the simulator's first stage; kept as the design record.*

The first Stage 0 sketch ("Bevy + Avian/Rapier sim") had real flaws. This doc
records the critique and the corrected design. **This supersedes the Stage 0
tech choices in [roadmap.md](roadmap.md).**

## Flaws found in the original plan, and fixes

| # | Flaw | Fix |
|---|------|-----|
| 1 | A physics engine (Avian/Rapier) would integrate motion for us — but writing the kinematics IS lesson #1. (2D rigid-body friction is also physically wrong for top-down wheels.) | **No physics engine in Stage 0.** Hand-write the kinematic update (~10 lines) and segment raycasts (~30 lines). |
| 2 | With pure kinematics, commanded speeds take effect instantly → a P-controller is perfect → **the PID lesson cannot happen** (no overshoot, nothing for I/D to do). | Model actuator dynamics: first-order motor lag + accel/velocity saturation. Overshoot, windup, and D-damping become real phenomena. |
| 3 | Bevy front-loads game-engine learning (ECS, schedules, 0.x churn, compile times) — weeks of budget spent off-curriculum; and it duplicates Rerun, which is already a 2D viewer *with time scrubbing* (perfect for the drift lesson). | Invert the architecture: pure headless `sim-core` crate + thin **Rerun** runner. Interactive window (teleop, click-to-goal) is a later bolt-on frontend — macroquad for cheap, Bevy only when we want the wasm+WebGPU shareable demo. |
| 4 | Game loop ≠ control loop; determinism unspecified. | Fixed-dt stepping, fully decoupled from display; seeded RNG. Buys reproducible bugs, regression tests, 1000×-realtime headless tuning runs. **Honest limit:** sim cannot teach real-time deadline pressure — that arrives in Stage 2 on the MCU. |
| 5 | Noise model hand-waved. No noise → no drift → hollow milestone; pose-level Gaussian noise → wrong intuitions. | Noise at the physical source: encoder tick quantization, per-wheel random slip, and a **systematic** error (mismatched wheel radii). Systematic error is what makes odometry curve away confidently — the effect that motivates sensor fusion. |
| 6 | Curriculum gaps: coordinate frames (world vs robot, SE(2) composition — the #1 real-world bug source) and **angle wrapping** (naive heading error breaks at ±π). | Both become explicit lessons with tests. |
| 7 | No verification culture. | Unit tests against closed-form truth: equal speeds → straight line of known length; constant unequal speeds → circle of known radius; zero noise → odometry == ground truth exactly. |
| 8 | In-process `sensors()` returning perfect structs hides the Stage-3 reality (messages over a wire: latency, dropouts, units). | Fine for day 1; **before Stage 3, do the "sim robot as a device" refactor** — put the sim behind the same postcard-rpc protocol the real Pico will speak, so the brain can't tell sim from hardware. Add latency/dropout injection then. |
| 9 | Motivation/scope risks: Stage 0 balloons into game-making, or drags while the hardware itch goes unscratched. | Timebox (the July 2026 plan): ~3–4 weekends with defined "done". Guardrail: everything must run headless. **Plan: order the Pico 2 W + Debug Probe (~$25) at the start** and blink an LED in a parallel evening — Stages 0 and 2 overlap fine. |
| 10 | Reactive avoidance gets stuck in U-shaped obstacles (local minima). | Kept on purpose: it's the cliffhanger that motivates occupancy grids + A* (stretch goal) and eventually SLAM. |

## Revised architecture

```
crates/
├── sim-core/      # PURE library. No engine, minimal deps (glam or nalgebra).
│   │              # Fixed-dt, seeded, deterministic, fully unit-tested.
│   ├── robot.rs   # diff-drive kinematics + motor lag + saturation
│   ├── world.rs   # wall segments, obstacles
│   ├── sensors.rs # encoders (quantized, noisy, biased), ray "lidar"
│   ├── odometry.rs# dead reckoning from encoder ticks
│   ├── control.rs # PID (speed, heading w/ angle wrap, goto-point)
│   └── behavior.rs# state machine: DRIVE_TO_GOAL / AVOID / (stuck?)
├── sim-run/       # thin binary: steps sim-core, logs everything to Rerun
│                  # (truth pose, believed pose, rays, PID terms, FSM state)
└── sim-ui/        # LATER, optional: interactive frontend (macroquad or
                   # Bevy → wasm+WebGPU shareable demo)
```

*As built:* the behaviour state machine landed in `crates/sim-core/src/nav.rs`
rather than a `behavior.rs`; the optional `sim-ui` frontend was never written;
neither glam nor nalgebra was needed (`sim-core` depends only on `num-traits`
with `libm`); and the "sim robot as a device" refactor of flaw 8 became the
line-based protocol in [hil-protocol.md](hil-protocol.md) rather than
postcard-rpc.

Design rules:
- `sim-core` never knows about rendering, wall-clock time, or I/O.
- Every random process takes a seed; same seed → bit-identical run.
- Every milestone has tests against analytic truth before it has pixels.

## Milestone ladder (each is one sitting-to-few-evenings sized)

- **M0 — kinematics:** diff-drive update + tests (straight line, circle radius,
  spin in place). Covers: kinematics, frames, SE(2).
- **M1 — see it:** `sim-run` logs a scripted drive to Rerun. Covers: telemetry
  habit; Rerun time-scrubbing.
- **M2 — believe vs truth:** encoders with quantization + slip + wheel-radius
  bias; odometry integration; both poses in Rerun, drifting apart. Covers: dead
  reckoning, why estimation exists.
- **M3 — control:** motor lag + saturation added; PID for wheel speed, then
  heading (angle-wrap test!), then goto-point. Tune gains, watch overshoot.
  Covers: PID for real.
- **M4 — react:** ray sensors + avoid/goto state machine. Robot reaches a goal
  around obstacles. Covers: perceive→decide→act, FSMs. **Stage-0 "done."**
- **M5 — stretch:** U-trap demo of local minima → occupancy grid + A*
  replanning; and/or `sim-ui` interactive frontend.

## What survives the red-team unchanged

Sim-before-hardware; 2D before 3D; differential drive first; Rerun as the
telemetry backbone; MuJoCo deferred until manipulation matters; Rust
throughout. The correction is philosophical: **Stage 0's foundation is a pure,
tested, deterministic library — not a game engine.** Viewers are disposable
attachments.

## Version pins (July 2026 — expect churn, pin everything)

- rerun 0.34.x, glam or nalgebra 0.35 (decide at M0; ecosystem drifting toward
  glam per Dimforge), macroquad/Bevy 0.18 only if/when `sim-ui` happens.
