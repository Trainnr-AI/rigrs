# Testing and coverage

*First measured 2026-07-31 and re-measured through 2026-08-15; kept as the testing record.*

Measured with `cargo-llvm-cov`; lines with `tools/loc-report.py` (not carried
into rigrs). The
2026-07-31 baseline is kept below — the point of measuring twice is the
delta.

## 2026-08-15 — delta after the servo arc and three review passes

**483 tests** (+7) · 14,050 regions at **73.2%** (+0.3 pts) · 28,369
lines (+836), documentation steady at 43.6%. The week's pattern held:
`pca9685-driver` grew ~100 regions (async twin, batched write) and its
coverage **rose** to 96.6% — the twins share a pure core, and the
byte-identity test covers both through one set of expectations. The two
flagged weak rows (`crates/arm/src/lib.rs` 49%, `wire.rs` 72%) are unchanged
and remain the queue. `rig_view`/`rig_replay` are examples, invisible to
llvm-cov by design — their proof was the two recordings the verify gate
pinned (now in [trainnr's `recordings/`](https://github.com/Trainnr-AI/trainnr/tree/main/recordings)).

## 2026-08-14 — after the camera, the chase, and two review passes

| Category | Regions | Covered |
|---|---:|---:|
| **Pure logic** — every crate that decides | **9,053** | **96.0%** |
| Model weights (ONNX) | 767 | 52.8% |
| Hardware I/O (webcam, serial, live viewer) | 972 | 33.8% |
| Binary `main()` wiring | ~3,082 | ~0% |
| **TOTAL** | **13,874** | **72.9%** |

**476 tests** (was 201). Pure-logic regions nearly **tripled** — 3,318 →
9,053 — while their coverage held at 96%: the arm, `blob`, `n20-joint`,
three sensor drivers and the protocol growth all arrived *with* their
tests, not ahead of them. Every crate written in the last week is at or
above 94%; `blob` is 99.6%, `quad-encoder` 100%.

Lines: **27,533 total across 98 files — 10,757 code, 6,861 test, 43.8%
documentation**. Code-to-test ratio 1 : 0.64.

### ⚠️ The two honest weak spots in pure logic

- **`crates/arm/src/lib.rs` at 49%** — the worst pure file in the workspace,
  and it is the arm's *core traits*: `Torque`'s default `engage`/
  `release` bodies and the `Joints` plumbing. Everything around them is
  95–100%; the centre of the arm's type system is half-covered. It was
  queued as the first item for the next round of arm work.
- **`crates/hil-host/src/wire.rs` at 72%** — 87 missed regions in the replay
  divergence checker, the tool other things rely on to catch drift.

### Firmware: 2,403 code lines, invisible to llvm-cov, pinned differently

Up 5× from the baseline's 482. Still `no_std`/`no_main` for ARM, still
outside host coverage **by design** — which is why logic keeps being
pushed into the shared crates. What pinned the firmware instead was the
verify gate's replay fixtures (they stayed in
[trainnr's `recordings/`](https://github.com/Trainnr-AI/trainnr/tree/main/recordings) when rigrs was split out, so rigrs's
`tools/verify.sh` does not replay them):
`rp2350-utrap.wire` (4,256 ticks, tick-for-tick on real silicon),
`bench-two-joint.wire`, `chase-sweep.perc` — and now
`chase-brightness.wire` (1,034 reports + 5 camera thumbnails, awaiting a
headless reader before it could join the gate).

The "why 100% is not the target" argument below stands unchanged.

# Baseline: 2026-07-31

Measured with `cargo-llvm-cov` (source-based instrumentation via LLVM —
the same mechanism `rustc` uses for `-C instrument-coverage`, so the
numbers reflect real executed regions, not line-guessing).

Reproduce:

```sh
cargo llvm-cov --workspace --summary-only     # numbers
cargo llvm-cov --workspace --html             # browsable report
open target/coverage/html/index.html
python3 tools/loc-report.py                   # lines of code (script not in rigrs)
```

## Headline

| Category | Regions | Region % | Line % |
|---|---:|---:|---:|
| **Pure logic** | 3318 | **98.5%** | **98.5%** |
| Model weights (ONNX) | 619 | 64.3% | 72.8% |
| Hardware (nokhwa) | 628 | 46.3% | 41.0% |
| Binary `main()` | 1662 | 0.0% | 0.0% |
| **TOTAL** | **6227** | **63.6%** | **66.0%** |

**201 tests**, all passing. Up from 45.6% region / 47.7% line before this
round of testing work.

The number that matters is the first row. Everything the robot *decides*
is at 98.5%. The rest is I/O.

## Why 100% is not the target

100% total coverage is unreachable here, and chasing it would make the
code worse. Precisely:

**Binary `main()` — 1662 regions, 0%.** These are `loop { }` bodies that
open a camera, spawn a Rerun viewer, or block on a UART. A `main` that
never returns is not a unit under test. The correct response is not to
test them but to **empty them**, which is what this round of work did: logic
moved out into `sim_core::nav`, `vision::target`, `vision::cli`, and
`hil-protocol`, all at or near 100%. What remains in `main` is wiring.

**Hardware — 628 regions, 46.3%.** `nokhwa` needs a physical webcam and a
macOS TCC grant. Covering it would mean either a fake USB video device in
CI or a mock so elaborate it tests itself. The *pure* parts were extracted
instead: `name_matches` (the fix for the two-roles-one-camera bug) and all
of `FrameSet` are fully covered.

**Model weights — 619 regions, 64.3%.** `.commit()` downloads hundreds of
megabytes and runs ONNX inference. Config *construction* is a pure builder,
so `every_model_maps_to_a_real_usls_config` covers the whole registry
without touching the network — that catches a typo'd weights filename,
which is the realistic failure. Actual inference is not unit-testable and
should not pretend to be.

**Firmware — 482 lines, not measured at all.** The six `firmware/` crates
are `#![no_std] #![no_main]` for `thumbv6m-none-eabi`. They do not link for
the host, so they are outside the workspace and invisible to `llvm-cov`.
This is *by design*, and it is why the shared crates matter so much: every
line of decision-making the chip runs — `GotoController`, `Odometry`,
`Pid`, `RobotSpec`, `Message`, `LineReader` — lives in `sim-core` or
`hil-protocol` and **is** covered, on the host, at ~99%. The firmware is
now little more than pin setup plus calls into tested code.

## The mission regression test

The project's headline result — *mapping plus A\* defeats the U-trap that
beat the purely reactive robot* — was for weeks verified only by a human
watching a Rerun window. It is now asserted.

`sim-run` was one 400-line `main()` with physics and ~20 Rerun calls
interleaved, so it could not be tested at all. It is now:

- `sim_run::mission` — `Mission::step()` returns a [`Tick`]; no I/O, no
  wall-clock, no viewer. **97.2% covered.**
- `crates/sim-run/src/main.rs` — sets up the world, draws each tick, paces the
  loop. Makes no decisions. 0% covered, correctly.

Ten tests, the headline one being:

```rust
#[test]
fn mapping_and_planning_beat_the_u_trap() {
    let outcome = Mission::new(MissionConfig::default()).run();
    assert!(outcome.succeeded());
    assert!((20.0..25.0).contains(&outcome.completed_at.unwrap()));  // baseline 22.5 s
    assert!(outcome.drift < 0.10);                                   // baseline 0.052 m
}
```

**The tolerances are loose on purpose.** Asserting the exact f64 output
would fail on any harmless refactor — reordering two additions changes the
last bits — while a real regression (entering the trap, ghosting through a
wall, never arriving) moves these by whole seconds and metres. A test that
cries wolf gets deleted; this one only fires when something is actually
broken.

The others cover the mechanism rather than the number: the robot must
arrive *at* the goal (not merely increment a counter), must not get there
by scraping walls (`bumps < 20` — the collision bug, caught on screen,
wearing a disguise), must be reproducible across runs, must produce a *different*
trajectory under a different seed (otherwise the drift assertion is
testing a constant), and must drift less when the wheel wear is removed.

Headless, the full mission runs in ~0.1 s. On screen it takes 22.5.

## What the tests actually caught

Two real defects, both found by tests written in this round, both fixed in
the code rather than papered over in the test:

1. **`pick_target` chased NaN.** `f32::total_cmp` sorts positive NaN
   *above* every finite value, so `max_by` returned a detection whose
   confidence was not a number and the robot would have steered at it.
   Fixed by filtering non-finite confidences; if that leaves nothing, the
   target is lost, which is the safe answer.
   (`crates/vision/src/target.rs`, `nan_confidence_does_not_panic_or_win`)

2. **`hil-host` compared motor duty with `==` on floats.** Typing the
   protocol turned duty into `i32`, and the compiler rejected
   `duty_l == 0.0`. The idle-detection that ends a HIL run was resting on
   exact float equality.

That is the standard for "meaningful": a test that cannot fail teaches
nothing. Every test here names the failure it prevents.

## Lines of code

| Crate | Code | Doc | Blank | Test | Total | Files |
|---|---:|---:|---:|---:|---:|---:|
| crates/sim-core | 682 | 570 | 125 | 929 | 2306 | 15 |
| crates/vision | 1621 | 769 | 226 | 752 | 3368 | 17 |
| crates/sim-run | 472 | 108 | 47 | 159 | 786 | 3 |
| crates/hil-host | 167 | 38 | 17 | 0 | 222 | 1 |
| crates/hil-protocol | 126 | 85 | 19 | 319 | 549 | 1 |
| crates/quad-encoder | 40 | 66 | 7 | 84 | 197 | 1 |
| crates/mpu6050-driver | 51 | 52 | 14 | 74 | 191 | 1 |
| firmware/pico-robot | 93 | 49 | 17 | 0 | 159 | 2 |
| firmware/pico-odom | 104 | 20 | 16 | 0 | 140 | 2 |
| firmware/pico-button | 68 | 47 | 13 | 0 | 128 | 2 |
| firmware/pico-encoder | 79 | 24 | 15 | 0 | 118 | 2 |
| firmware/pico-imu | 80 | 18 | 13 | 0 | 111 | 2 |
| firmware/pico-blink | 39 | 35 | 10 | 0 | 84 | 2 |
| **TOTAL** | **3622** | **1881** | **539** | **2317** | **8359** | **51** |

- **code : test = 1 : 0.64** (was 1 : 0.36)
- **doc : code = 1 : 1.93** — 34.2% of non-blank, non-test lines are prose

`tools/loc-report.py` counts `#[cfg(test)]` blocks separately, so the test
column never inflates the code column.

## Where the remaining risk actually is

Coverage is a map of what was *executed*, not of what is *correct*. The
genuinely under-tested things in this project are not low-coverage files:

- **Inference accuracy** — 100% coverage of `detect.rs` would say nothing
  about whether D-FINE finds a mug. `bench` is the right instrument, and
  it still sweeps *backends* rather than models.
- ~~**Timing**~~ — **measured on real silicon, 2026-08-07.** A control
  tick (`Odometry::update` + `GotoController::goto_point` +
  `DiffDrive::inverse`) takes **198 µs** on the RP2350, against a 20 ms
  budget: **0.99% used, 101× headroom.** See
  `firmware/pico-selftest`. Caveat: that measures the *maths*, not the
  UART, PWM writes or interrupt overhead the real loop also carries — but
  100× headroom leaves a lot of room for those.

~~`sim-run`'s mission loop~~ — closed. See the regression test above.

## Cross-platform verification

The project's central claim — *the same source runs on the laptop and the
chip* — was true of the source and **unverified of the output** until
2026-08-07. There were real reasons to doubt it:

- the Mac does `f64` in hardware; the Cortex-M33's FPU is
  **single-precision only**, so every `f64` is software-emulated — a
  completely different code path
- `libm` on bare metal is a *different implementation* of `sin`, `cos`,
  `atan2`, `exp` from the host's

`firmware/pico-selftest` runs fixed inputs through `DiffDrive`, `Pose`,
`Odometry`, `Pid`, `Motor`, `Encoders` and `GotoController` on the chip and
prints to 17 significant digits over USB serial;
`cargo run -p sim-core --example selftest` computes the same on the Mac.

**All 11 lines matched exactly.** Not "close enough" — identical to the
last digit, including 50 compounding iterations of odometry and PID.

```sh
cargo run -p sim-core --example selftest > /tmp/host.txt
tools/build-pico2.sh pico-selftest
picotool load -x firmware/pico-selftest/pico-selftest-pico2.uf2
# capture /dev/cu.usbmodem* to /tmp/chip.txt, then:
diff /tmp/host.txt /tmp/chip.txt
```

## Rules adopted

1. **Logic does not live in `main()`.** If it cannot be called from a
   test, it goes in a library module. `main` is wiring.
2. **A test names the failure it prevents.** Comments say what breaks, not
   what the code does.
3. **Do not mock hardware.** Extract the pure decision and test that.
   A mock of `nokhwa` would be more code than `nokhwa`.
4. **Coverage is reported by category**, never as one number. "59.6%"
   invites gaming; "98.6% of pure logic, 0% of `main()`" invites the right
   fix, which is to shrink `main()`.

<!-- COVERAGE:BEGIN -->
## Measured 2026-08-07

`tools/coverage.sh` — `cargo-llvm-cov` over the workspace, plus
`tools/loc-report.py` (neither script was carried into rigrs). **447 tests** as of 2026-08-13 — up from 333 with
`arm` (47), `n20-joint` (9), `blob` (12) and the wire's new `J` message.

| group | lines | covered | coverage |
|---|---:|---:|---:|
| The robot's decide path (sim-core) | 1328 | 1319 | **99.3%** |
| Mission / physics | 366 | 365 | **99.7%** |
| HIL rig loop (rig.rs) | 238 | 235 | **98.7%** |
| Wire protocol + record/replay | 662 | 599 | **90.5%** |
| Hardware drivers | 172 | 168 | **97.7%** |
| Perception libraries | 1913 | 1480 | **77.4%** |
| => everything that DECIDES | 4679 | 4166 | **89.0%** |
| Plumbing / interactive binaries | 1267 | 45 | **3.6%** |
| **WORKSPACE TOTAL** | 5946 | 4211 | **70.8%** |

Function coverage 80.4%. The workspace total is the least useful number
here: it averages the code that decides what the robot does together with
1267 lines of binaries that open cameras and spawn windows.

### Lines of code

```
                    code     doc    blank    test    total
TOTAL               5726    3478     807     4129    14140

code : test         1 : 0.72
doc  : code         1 : 1.65      (37.8% of non-blank, non-test lines)
```

| crate | code | test |
|---|---:|---:|
| `vision` | 2403 | 1545 |
| `sim-core` | 1035 | 1305 |
| `hil-host` | 651 | 336 |
| `sim-run` | 522 | 274 |
| `hil-protocol` | 214 | 511 |
| firmware (8 crates + build-support) | 810 | 0 |
| drivers (`quad-encoder`, `mpu6050`) | 91 | 158 |

Firmware carries no tests by design: it is `no_std`, builds for a
different target, and cannot run host tests. What covers it is
`pico-selftest` — the same maths on real silicon, diffed against the host
— and the HIL rig.

### Running it

`tools/coverage.sh` was not carried into rigrs; its line is kept as the
record of how these numbers were produced.

```sh
tools/setup-hooks.sh                     # once per clone — installs the gates
tools/verify.sh                          # everything that needs no hardware
tools/verify.sh --serial /dev/cu.usbmodem11   # plus a real Pico
```

### Known issue: the emulator HIL run stops at 14.6 s

The `HIL on the emulator (RP2040)` step of `tools/verify.sh` has been red
since 2026-08-12. Under rp2040js the RP2040 build of `pico-robot` stops
answering at about 14.6 s of simulated time, at the same tick on every
run (six runs then, and again on 2026-10-06), mid-spin after a decaying
turn snaps to a saturated one. The host is left waiting for a motor
command that never comes. The same mission completes (1/1 waypoints, 0
wall bumps) on real RP2350 silicon and in that session's replay, so the
shared control code, odometry and protocol are not the suspects; the
open question is the emulator or the Cortex-M0+ build. The step runs
under a time limit (`HIL_TIMEOUT`, 900 s by default), so it fails rather
than hangs, and `tools/verify.sh --fast` leaves it out.

### What is enforced, and where

| gate | runs on | what it stops |
|---|---|---|
| `cargo fmt --all --check` | every commit | formatting drift |
| `cargo clippy` (0 errors) | every commit | the lint gates below |
| `tools/check-unsafe-gates.py` | every commit | a crate quietly losing its unsafe forbid |
| `tools/check-docs.py` (not carried into rigrs) | every commit | docs describing code that no longer exists |
| `tools/verify.sh` | before pushing | everything, incl. firmware and the emulator |

Hooks live in `tools/hooks/` and are wired up by `core.hooksPath`, so they
are versioned like the rest of the repo. A hook in `.git/hooks` exists on
exactly one machine, which is how *"we always check X"* becomes *"one
laptop checks X"*.

### Unsafe code

**There is none, and the compiler is what keeps it that way.**

```toml
[workspace.lints.rust]
unsafe_code = "forbid"
```

`forbid`, not `deny`: it cannot be switched off locally by an `#[allow]`.
Every workspace crate inherits it (or spells it out, where a stricter
clippy block means Cargo will not let it inherit). Every firmware crate —
outside the workspace — carries `#![forbid(unsafe_code)]` in source. All
fourteen firmware builds pass with it on, because embassy's HAL already
wraps the peripheral access that would otherwise need it.

`tools/check-unsafe-gates.py` checks the **guard**, not the code: deleting
a line from a manifest is the only way unsafe gets in, and that deletion
is silent. An earlier version of this gate grepped for `unsafe` instead
and passed `fn f() { unsafe { } }` because it required the keyword at the
start of a line — caught by mutation-testing the gate itself.

### Where the gaps are, and which are real

**Not real — hardware-gated by nature:**

| file | cover | needs |
|---|---|---|
| `crates/vision/src/camera.rs` | 21% | a real camera to enumerate |
| `crates/vision/src/openvocab.rs` | 59% | the Grounding DINO model |
| `crates/vision/src/rig.rs` | 59% | two cameras |
| the 8 `vision` binaries | 0% | camera + a window |
| `crates/sim-run/src/viz.rs` | 0% | draws pixels; a test asserting "we called `rec.log`" is ceremony |

What covers these instead is record/replay: a committed hardware wire
recording and a synthetic perception session, both of which fail on a
behaviour change.

**Was real, now fixed.** `crates/hil-host/src/main.rs` measured **21.9%** while
containing the exchange every hardware run depends on — untested not
because it needed hardware but because it sat in `main()` next to a serial
port and an emulator. Extracted to `rig.rs`, which takes a `Wire`; since
`Wire::Replay` is a transcript in memory, the whole loop now runs in
`cargo test` with no chip at all. **`rig.rs`: 98.7%.**

### 100% is not the target

The bugs this project actually shipped — a chip carrying its previous
run's pose, a 33-byte burst into a 32-byte FIFO, a stale firmware image —
were all invisible to a passing test suite. They were found by recording
what crossed a boundary and replaying it. Coverage says which lines ran;
it does not say the system works.
<!-- COVERAGE:END -->
