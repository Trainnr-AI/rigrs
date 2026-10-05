# Architecture review (2026-07-31)

*Written 2026-07-31, with a second review on 2026-08-07; kept as the review record.*

Everything built so far — Stage 0 (laptop sim), Stage 2 (firmware), Stage 1
(perception) — reviewed for how it ties together and where it violates
DRY/composability. **5,204 lines in `crates/`, 767 in `firmware/`.**

## What the system actually is

Three environments running one robot's worth of ideas:

```
                    ┌──────────────────────────────────────┐
                    │            sim-core                   │
                    │  Pose · DiffDrive · Odometry · Pid    │
                    │  Motor · Rng · Encoders · Segment     │  no_std subset
                    │  ─────────────────────────────────    │
                    │  World · DepthCamera · Grid · A*      │  std only (alloc)
                    └──────────────────────────────────────┘
                       ▲            ▲              ▲
          ┌────────────┘            │              └──────────────┐
          │                         │                             │
    ┌─────┴──────┐          ┌───────┴────────┐          ┌─────────┴────────┐
    │  sim-run   │          │   hil-host     │          │     vision       │
    │  Stage 0   │          │   Level 3      │          │    Stage 1       │
    │  laptop    │          │   physics for  │          │  camera+detector │
    │  robot     │          │   a chip brain │          │  → control       │
    └────────────┘          └───────┬────────┘          └──────────────────┘
                                    │ UART (ASCII protocol)
                            ┌───────┴────────┐
                            │  pico-robot    │  ← sim-core compiled no_std
                            │  pico-odom     │  ← + quad-encoder
                            │  pico-imu      │  ← + mpu6050-driver
                            └────────────────┘
```

**This part is genuinely good.** `sim-core` compiles twice from one source
(std for the laptop, `no_std` for ARM), so `Odometry` and `Pid` are the
*same struct* in the simulator, the HIL rig, and on-chip. The driver crates
(`mpu6050-driver`, `quad-encoder`) are `no_std` libraries host-tested with
mocks — the professional embedded pattern. Traits sit at the seams that
were predicted to move: `CameraSource` (nokhwa is maintainer-disowned),
`Detector` (models are stepping stones), `Promptable`.

## Violations found, with evidence

### 1. ⚠️ The control law is written three times

The robot's actual brain — bearing → error → PID → alignment-throttled
velocity — is copy-pasted:

```
crates/sim-run/src/main.rs:251        let alignment = (1.0 - heading_error.abs()/FRAC_PI_2).max(0.0)
crates/vision/src/bin/chase.rs:195    let alignment = (1.0 - error.abs()/FRAC_PI_2).max(0.0)
firmware/pico-robot/src/main.rs:145   let align     = (1.0 - err.abs()/FRAC_PI_2).max(0.0)
```

This is the worst violation because it is the *most important code in the
project* and it lives nowhere. A fix or improvement to the control law must
be made in three places, in two build configurations.

### 2. ⚠️ Robot geometry duplicated four times, PID gains three times

```
WHEEL_RADIUS / TRACK_WIDTH / TICKS_PER_REV
  chase.rs · hil-host · pico-robot · pico-odom        (4 copies)

HEADING_KP / HEADING_KD
  sim-run   6.0 / 0.6
  pico-robot 6.0 / 0.6
  chase.rs  3.0 / 0.3        ← different, and it is not obvious why
```

The gain divergence may be legitimate (a visual servo is a different plant
from a waypoint follower) — but as scattered `const`s it is impossible to
tell intent from drift. These are *robot configuration*, not per-binary
trivia.

### 3. ⚠️ `CameraRig` exists but six binaries ignore it

`nokhwa_initialize` + permission handling + a capture thread appears in
`see`, `detect`, `chase`, `find`, `bench`, `sweep` — all written *before*
the rig existed, none updated after. ~25 duplicated lines each.

Worse, they use `NokhwaCamera::open(index, …)`, which we **proved
unreliable** — the index bug that made two roles open one camera. The rig's
`open_named` fix does not protect them.

### 4. ⚠️ `chase` hardcodes its detector, blocking a free feature

```rust
let mut detector = DFineDetector::new(MIN_CONFIDENCE)?;   // concrete type
```

We have a `Detector` trait and *two* implementations. If `chase` took
`Box<dyn Detector>`, then **"name a target and chase it" would already
work** — `find`'s open-vocabulary detector plugged into `chase`'s control
loop, no new code. The pieces exist; the wiring doesn't. That is the
clearest composability failure in the repo.

### 5. Rerun robot visualisation written three times

`robot/trail` + `robot/body` + `robot/heading` — the same three archetypes
with the same colours — in `sim-run`, `hil-host`, and `chase`.

### 6. The HIL wire protocol never got its Level 2

[hil-protocol.md](hil-protocol.md) describes ASCII lines as a deliberate learning choice with
`postcard` as the follow-up. The follow-up hasn't happened, so the parser
is hand-rolled `split_whitespace` on both sides.

## What is fine and should NOT be changed

- **Per-binary tuning constants that are genuinely experiment knobs**
  (`BEARING_ALPHA`, `AVOID_ENTER`, camera resolution). These are meant to
  be edited; centralising them would remove the point.
- **The `firmware/` crates being outside the workspace.** Different target,
  different build config. Correct.
- **Separate driver crates** rather than modules in `sim-core`. They have
  different dependency needs (`embedded-hal`) and are independently useful.
- **Duplicated `Detection`→Rerun box logging** in `detect`/`find`/`chase` —
  each renders slightly different labels. Borderline, low value to unify.

## Proposed refactor, in priority order

| # | Change | Removes | Unlocks |
|---|---|---|---|
| 1 | `sim-core::control::GotoController` — the control law, once | 3 copies | one place to improve steering |
| 2 | `sim-core::RobotSpec` — geometry + named gain sets | 4+3 copies | intent visible; one robot definition |
| 3 | `vision::CameraRig` used by every binary | ~150 lines | index-bug fix applies everywhere |
| 4 | `chase` takes `Box<dyn Detector>` | ~0 | **"name it and chase it", free** |
| 5 | `sim-core::viz` (std-only) for the robot triple | ~40 lines | consistent visuals |
| 6 | `postcard` on the HIL wire | hand-rolled parsing | typed, versioned protocol |

Items 1–4 are the ones that matter. 5 is cosmetic. 6 is Level 2 work that
should wait until there is a second consumer of the protocol.

**Estimated net: ~200 lines removed, two capabilities gained.**

---

## STATUS: items 1–4 landed, 2026-07-31

- **1. Control law** → `sim_core::GotoController` (`control.rs`), with
  `steer()` as the primitive and `goto_point()` for the waypoint case.
  All three copies deleted. `pico-robot` no longer imports `Float` at all
  — the chip does no float math of its own now.
- **2. Geometry + gains** → `sim_core::RobotSpec::SIM_BOT` and
  `ControlGains::{WAYPOINT, VISUAL_SERVO}` (`spec.rs`). The gain
  divergence is now a named profile with the reason on it, and a test
  (`visual_servo_is_gentler_than_waypoint`) that fails if someone
  "unifies" them.
- **3. Camera boilerplate** → `vision::Stream::start(Source, res, fps)`:
  permission + open + latest-wins capture thread in one call. `detect`,
  `see`, `find`, and `chase` adopted it. `find` now opens the Brio **by
  name**, so it inherits the index-bug fix.
- **4. Detector** → `ObjectDetector` + `DetectorModel` (7 models), and
  `chase` takes `Box<dyn Detector>`. `--model` and `--find` now work.

**Verification:** whole workspace builds, 103 tests pass, all six firmware
crates still build for `thumbv6m-none-eabi`, and `sim-run` reproduces the
recorded baseline **exactly** — mission complete at t = 22.5 s, final drift
0.052 m. Behaviour-preserving.

**Not done:** items 5 (Rerun viz helper) and 6 (postcard wire protocol),
deliberately. Also `bench` still sweeps *backends*, not models — so none of
the six new detectors has a measured latency on the development machine yet
(they were measured later the same day: see
[detector-landscape.md](detector-landscape.md)).

## The principle to hold

The project's real architectural asset is that **one definition serves
every environment**: `Odometry` runs on a laptop and on ARM; `Pid` steers a
simulated robot, an emulated one, and a camera-driven one. Every violation
above is a place where that principle was breached under time pressure —
usually because the second copy was written before the shared home existed.

The fix is not to be more disciplined next time. It is to **create the
shared home as soon as the second copy appears**, which is exactly the
signal that `GotoController` and `RobotSpec` are now overdue.

---

# Second review — 2026-08-07

Prompted by a full re-read after a heavy week of hardware work. Five
findings, four fixed, one recorded deliberately.

## 1. ⚠️ The exact violation this document exists about, recreated

`build.rs`, `memory-rp2040.x`, `memory-rp2350.x` and `.cargo/config.toml`
were copied into **eight** firmware crates: **32 files, 4 distinct
contents.** Introduced during the RP2350 port by copying scaffolding from
`pico-blink` into each crate.

**Fixed.** `firmware/build-support` holds one copy of both layouts and the
chip-selection logic; each `build.rs` is now one line. The cargo config
moved to `firmware/.cargo/config.toml` — cargo's config lookup walks *up*
from the crate directory, so one file covers all eight.

The lesson from the first review applies verbatim: *the second copy was
written before the shared home existed.* Knowing the rule did not prevent
it. What would have prevented it is a check.

## 2. ⚠️ `cargo clippy --all-targets` was FAILING

`diagram_claims.rs` asserts `TAU - 6.2832 < 1e-4` and clippy's
`approx_constant` is deny-by-default. The lint gate had been red since the
diagram tests landed and nothing surfaced it, because `cargo test` passes
— clippy lints do not run in a normal build.

**Fixed** with a narrow `#[allow]` and a comment: the test deliberately
checks the doc's *rounded* value, which is the one case where a literal
near a constant is correct. Allowed narrowly rather than by weakening the
lint, per the rule adopted from the anti-panic review.

## 3. ⚠️ The digital-twin claim had no test

`hil-host` never calls `step()`. It calls `observe()`, ships the result to
a chip, and calls `advance()`. That path — which the entire twin claim
rests on — was verified only by a human running the emulator and reading
the numbers.

**Fixed.** `driving_it_by_hand_matches_step_exactly` drives the mission
both ways and requires identical outcomes. It is the twin property as an
assertion rather than a claim.

## 4. 🔴 The controller commands wheel speeds the robot cannot deliver

Found by writing a test about the wire format, which is not where anyone
would look for it.

Peak measured overshoot: **~169 rad/s against a 30 rad/s motor** — over
six times what exists. The source is the PID's D term: `Kd · de/dt` with
`dt = 0.02` means a target jumping sideways gives `de/dt ≈ 157`, so
`w ≈ 94 rad/s`, which is ~235 rad/s at the wheel.

It does not break anything today — `Motor::step` clamps and the mission
completes in 22.5 s. But **the controller is relying on saturation to
clean up after it**, which is not the same as being correct. On real
hardware the turn's shape will differ from what the controller computed,
with no feedback telling the PID its output was ignored.

**FIXED 2026-08-07, after a failed first attempt.** Peak overshoot
**169 → 33 rad/s**, and the Stage 0 baseline did not move (22.5 s /
0.052 m).

*Attempt 1 — derivative on measurement (the textbook fix), REJECTED.*
Taking `D` from the robot's own turn rate instead of the error is the
standard cure for derivative kick, and it **broke the mission**: 0/1
waypoints, 21.6 m drift. `Kd = 0.6` was tuned against the *error*
derivative, which carries a feed-forward term (`d(bearing)/dt`)
anticipating the path curving. Dropping it needs a full retune.
The implementation was kept for a while, documented as
correct-but-not-a-drop-in, then **deleted the same day** in a dead-code
pass — it had no callers, and 45 lines of method plus 40 of doc comment is
a lot of weight for a finding that is fully recorded right here. The
*measurement* is what mattered, and it is above.

*What shipped instead:*
- **`Pid::derivative_limit`** — the mirror of `integral_limit`, bounding the derivative's
  *contribution*. Sized to 12 rad/s, the fastest this robot can physically
  spin (`2·r·max_wheel_speed / L`).
- **`RobotSpec::fit_wheels`** — when a wheel command saturates, scale
  *both* by the same factor. Clamping each independently distorts the
  turn: (40, 10) on a 30 rad/s motor becomes (30, 10), a difference of 20
  where 30 was intended. Scaling gives (30, 7.5) — same arc, just slower.

The ~33 rad/s that remains is the **P** term, and it is honest: a large
heading error genuinely warrants a turn the robot cannot make that fast.
`fit_wheels` now handles it by preserving the arc.

*The twin test earned its keep within minutes.* Adding `fit_wheels` to
`step()` and not to the manual path made
`driving_it_by_hand_matches_step_exactly` fail immediately — catching a
divergence that would otherwise have shown up as the rig and the simulator
quietly disagreeing.

Related gap: `RobotSpec::check` advertises catching "commanding speeds the
robot cannot reach" and **misses this entirely** — it validates `max_forward_speed`
against `max_body_speed` and never looks at the turn component.

## 5. USB descriptor boilerplate is written twice

`pico-selftest` and `pico-robot`'s USB transport each carry the same
`StaticCell` descriptor-buffer dance. ~25 lines duplicated.

**Not fixed.** Two copies is the threshold where a shared home becomes
worth it, and a third would settle it — but the natural home is another
firmware support crate, and the two uses differ enough (one streams a
report, one is a `Link` impl) that a premature abstraction would cost more
than the duplication. Flagged so the third copy triggers action.

## State after this review

274 tests · clippy clean · pure-logic coverage 98.8% · `sim-run` 22.5 s /
0.052 m · HIL rig 22.8 s / 0.052 m on both emulator and real silicon ·
all eight firmware crates build for both chips.
