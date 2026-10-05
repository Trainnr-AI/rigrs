# Parts list (prices as of July 2026)

*Written July 2026 as the shopping list for the hardware stages and extended through August 2026 with what arrived, how it measured and how it was wired; kept as the hardware record.*

Buy per stage, never upfront.

> **Market note (July 2026):** a DRAM shortage has inflated SBC prices
> (Pi 5, Jetson) — but **microcontrollers, sensors, motors and passives are
> barely affected**. Everything on the Tier 1 list below is cheap and
> stable. Buy compute (Pi/Jetson) only when a stage demands it.


## The debug port needs a header (verified on the board, 2026-08-06)

**Our Pico 2 W has three bare through-holes marked `DEBUG`, not a JST-SH
socket.** Checked physically: light passes through them, and the white
marking is printed silkscreen, not a plastic connector.

So the Debug Probe's JST-SH ↔ JST-SH cable has nothing to plug into. To
use the Probe you need a **3-pin male header soldered into those holes**,
then its JST-SH → 0.1" cable pushes on. Pin order is printed beside the
holes — normally `SWCLK` / `GND` / `SWDIO`.

**This blocks nothing.** Flashing works over USB with no soldering at all:

```sh
# 1. hold BOOTSEL, plug in USB — the board mounts as a drive
# 2. build, then drag the .uf2 onto it
cd firmware/pico-blink && cargo build --release
elf2uf2-rs target/thumbv8m.main-none-eabihf/release/pico-blink pico-blink.uf2
```

(`.uf2` is what every `tools/sim-*.sh` already produces for the emulator —
the same file flashes real silicon.)

What the Probe adds over drag-and-drop: **breakpoints, stepping, variable
inspection, and `defmt` logs**. Real quality-of-life, not a requirement.
Printed output alone can come over USB serial on the same cable.

## ⚠️ Two things to check the moment the Pico arrives

**1. ~~The onboard LED will not blink~~ — SOLVED 2026-08-06.** The six
older firmware crates drive `PIN_25`, which is correct for a Pico 2 but is
the *radio's chip-select* on a Pico 2 W; the LED hangs off the CYW43's own
GPIO 0. `firmware/pico-led` boots the radio and drives it properly:

```sh
tools/build-pico2.sh pico-led
picotool load -x firmware/pico-led/pico-led-pico2.uf2
```

**Verified blinking on the physical board.** The other six crates still
drive GP25 and still will not light anything on a W — that is fine, their
heartbeat is a nicety, and `pico-led` is the reference for when one is
wanted.

**2. ~~We build for the wrong chip~~ — DONE, 2026-08-06.** All six
firmware crates now build for both RP2040 (emulator) and RP2350 (the
physical board), verified down to the boot structures in the linked images.

```sh
tools/build-pico2.sh pico-blink     # → a .uf2 for the real board
```

Flashing needs no Debug Probe and no soldering: hold **BOOTSEL**, plug in
USB, drop the `.uf2` on the drive that appears. You will need `picotool`
(`brew install picotool`) — `elf2uf2-rs` is RP2040-only.

## ⚠️ Measure these when the parts arrive

`RobotSpec::SIM_BOT` in `crates/sim-core/src/spec.rs` holds **plausible
placeholders, not measurements** — chosen 2026-07-27 when no hardware was
in view. They are self-consistent, which is all the simulator needs, but
none of them is pinned by anything on this list.

Known mismatch, deliberately left alone: `SIM_BOT.max_wheel_speed` is
30 rad/s (~286 RPM); the ordered motor is **~200 RPM** (~20.9 rad/s), so
the simulator assumes a motor ~43% faster than the real one. Retuning the
sim to a part that has not arrived would move the recorded Stage 0
baseline for no gain. `spec.rs` has a test that fails if these ever
silently converge.

**When the parts land, measure and fill in `RobotSpec::REAL_BOT`** —
`crates/sim-core/src/spec.rs`, **one line**. The firmware (`pico-robot`)
and the HIL host both already read `REAL_BOT`, so they pick it up with no
further edit. `sim-run` deliberately stays on `SIM_BOT` so its recorded
Stage 0 baseline keeps meaning something.

```rust
pub const REAL_BOT: RobotSpec =
    RobotSpec::from_measurements(/* wheel Ø mm */, /* track mm */,
                                 /* ticks/rev */, /* max RPM */);
```

| # | measure | how, and why the obvious way is wrong |
|---|---|---|
| 1 | **wheel diameter** | Calipers, **under load** with the robot's weight on it. A squashy tyre has a smaller effective radius than a free one. This is the **largest single source of odometry drift** — it is why the simulator models a deliberate 1% error. |
| 2 | **track width** | Centre-to-centre of the two **contact patches**. Not the axle length, not the outer edges. |
| 3 | **ticks per rev** | Do **not** compute `PPR × 4 × gear_ratio`. Ratios sold as "50:1" are routinely 51.45:1. Spin the wheel exactly ten turns by hand, read the counter, divide by ten. |
| 4 | **max RPM** | On **the robot's own** battery at the voltage the robot actually runs at — not the datasheet's nominal 6 V. |

Then run `RobotSpec::check(&gains)` — it rejects a `max_forward_speed` the motors
cannot reach, which otherwise gets misdiagnosed as bad tuning.

## Tier 1 — unblocks H4 and everything already written (~$55–70)

| Item | Price | Why |
|---|---|---|
| **Raspberry Pi Pico 2 W — headers pre-soldered** | ~$8–10 | The board. RP2350, best-in-class embassy support. Pre-soldered: see the soldering note. |
| **Raspberry Pi Debug Probe** | ~$12 | `cargo run` → flash + breakpoints + `defmt` logs. Ships with its own cables — but see "the debug port" below: **our board needs a 3-pin header soldered in first**. Not a blocker; UF2 drag-and-drop works without it. |
| **Electronics starter kit** (breadboard, M-M + M-F jumpers, resistors, LEDs, buttons) | ~$20–25 | Physical H0/H1. Any generic "Arduino starter kit" minus the Arduino. |
| **MPU6050 breakout** (search "GY-521") | ~$3–5 | **This exact chip** — the driver in `crates/mpu6050-driver` was written and tested against it (H2). Works day one. |
| **N20 gearmotor WITH magnetic encoder**, 6V, ~200 RPM | ~$12–15 | The H4 blocker. Must say *with encoder* — plain ones give no feedback. |
| **TB6612FNG motor driver breakout** | ~$5–8 | The H-bridge. NOT L298N (obsolete, lossy). |
| **4×AA battery holder + batteries** | ~$5 | Motors need their own supply — never off the Pico's 3.3 V rail. Simplest safe bench power. |

## Tier 2 — Stage 3's rolling robot (~$60–90)

| Item | Price | Why |
|---|---|---|
| Second N20 gearmotor with encoder | ~$12–15 | Differential drive needs two. |
| 2WD chassis kit (plate, wheels, castor) | ~$20–30 | Or cut your own from anything flat. |
| 2S LiPo + charger, **or** 6×AA pack | ~$10–25 | Untethered power. LiPo = lighter/longer, needs care; AA = boring and safe. |
| Standoffs, velcro, zip ties, spare wire | ~$10 | Mounting. Always underestimated. |

## Tier 3 — the camera rig, ordered 2026-08-13 (~₹2,650–3,350)

Base, arm, camera and power. Everything is 3.3 V logic, so **no level
shifters anywhere**.

| item | qty | why |
|---|---|---|
| plastic 5-DOF arm kit (SG90 mounts, servos NOT included) | 1 | the arm |
| **MG90S** | 2 | shoulder + elbow — the loaded joints |
| **SG90** | 3 | base rotation, wrist, gripper |
| **PCA9685** 16-ch servo driver | 1 | ⚠️ **without it the pins do not fit** — 30 needed, 26 available |
| **OV7670**, plain (Robocraze RC-A-648) | 1 | 3.3 V, SCCB; no FIFO |
| electrolytic cap kit, **≥16 V** | 1 | ~~1000 µF across the servo rail~~ **arrived built-in (2026-08-14): the PCA9685 board ships with 1000 µF/10 V mounted across `V+`** — at the load, which is the right place. 10 V on a ~6.4 V rail is fine; the kit is no longer blocking anything |
| jumper wires F-F and M-F | ~40 | the camera alone is 14 lines |
| inline battery switch | 1 | stop unplugging cells |

### The pin budget, which is the binding constraint

```text
   TB6612    GP6 7 8 9 10 11 12                   7
   encoders  GP16 17 18 19                        4
   I2C       GP4 5   (PCA9685 + camera SCCB)      2
   OV7670    D0-D7, PCLK, HREF, VSYNC, XCLK      12
                                               ────
                                                 25      of 26, one spare
```

GP23/24/29 are internal and **GP25 is the radio's chip-select on a Pico
2 W**, so neither counts. Five servos wired directly would need 30 pins
and be impossible; through the PCA9685 they cost 2, shared with the
camera's SCCB.

### Power

```text
   2x 4xAA parallel  6 V ─┬─▶ TB6612 VM     (rated 2.5-13.5 V)
                          └─▶ PCA9685 V+    (servos 4.8-6 V)
                               └─ 1000 µF on the board itself covers the
                                  start surges; the PARALLEL PACKS are
                                  still what covers sustained load
   Pico 3V3 ─┬─▶ TB6612 VCC / PCA9685 VCC
             └─▶ OV7670 3.3 V   (~60 mA of ~300 mA available)
   Pico  ←── USB.    ALL grounds common.
```

⚠️ **Never** the 6 V pack to the Pico — `VSYS` maxes at 5.5 V. Parallel
packs halve the sag; ~1–1.6 A typical draw lands the rail at 5.2–5.6 V,
above the SG90's 4.8 V floor. Alkalines are a bench compromise: **do not
re-run the calibration sweep on them**, because a sagging supply measures
tired batteries rather than the robot.

### What it will not do

- **No joint feedback on the arm.** `Guard::authorise`, the step limiter
  and `Thermal` run on the base only; `Plan::interpolate` rate-limits the
  arm instead. An AS5600 per joint (~₹1,200 with an I2C mux) fixes this
  and is deferred.
- **Payload 20–50 g** at reach. An SG90's ~1.8 kg·cm across ~15 cm, minus
  the arm's own weight. ⚠️ Fit a rubber band from the shoulder link to the
  base — the ₹0 version of mitigation #2 in trainnr's
  [compute-and-hardware research](https://github.com/Trainnr-AI/trainnr/blob/main/docs/e2e-research/24-compute-and-hardware.md),
  *"counterbalance joint 2 so holding torque ≈ 0"*.
- **No depth.** Visual servoing only, which needs no calibration because
  it uses the sign of the error rather than a position.
- **QQVGA 160×120**, not VGA. A Pico cannot catch VGA at 30 fps from any
  module; the OV7670 has no frame buffer at all.
- **Not untethered** until a 5 V/3 A UBEC is added.

### ⚠️ Verify physically on arrival

1. **Wheel hubs vs the N20's 3 mm D-shaft** — before drilling anything.
2. **Headers pre-soldered** on the PCA9685 and OV7670? The MPU-6050 has
   been blocked on exactly this since it arrived.
3. **MG90S in an SG90 pocket** — usually drops in, occasionally wants a
   light file.

## Not yet — deliberately deferred

- **Pi 5 / Jetson** (Stage 4): DRAM-inflated; Jetson Orin Nano Super went
  $249 → $399 in July 2026. Decide at the stage, not before.
- **Lidar** (~$70–90): the `DepthCamera` in `sim-core` becomes a lidar by
  setting `fov = 2π`; buy only if SLAM demands it.
- **SO-101 arm** (~$230–450, Stage 5), **depth camera** (OAK-D/RealSense):
  much later.
- **BNO085 IMU** (~$22): better than the MPU6050 (onboard sensor fusion,
  quaternions out) — but a *different* driver. The choice when
  orientation is wanted for free; the MPU6050 is the one to learn on.

## The thing that catches every beginner: headers

A bare Pico 2 W ships with **holes, not pins** — it will not plug into a
breadboard.

- **Recommended now:** buy the "with headers" variant (a couple dollars
  more). Removes the first obstacle entirely.
- **Eventually:** a soldering iron (~$25–30 basic) becomes necessary —
  motor wires, connectors, custom leads. Just don't make it blocker #1.
- The Debug Probe attaches to the Pico's 3-pin debug socket with an
  included cable — no soldering needed for debugging.

## Where to buy

- **Adafruit / SparkFun** — best documentation attached to each product,
  US-based, reliable.
- **PiShop / Pimoroni / The Pi Hut** — good Pi-ecosystem coverage.
- **Amazon** — fastest, fine for kits/motors, check reviews for encoders.
- **AliExpress** — cheapest, weeks of shipping.

**Both boards are A2 — CONFIRMED on both (board #1 and board #2),
2026-08-07.** No good board
to fall back on; the E9 pull-down erratum must be designed around.
Both run the robot firmware and command **byte-identical** motor duty
across all 1139 ticks of the Stage 0 mission.
Also: `picotool load -x` works where drag-and-drop UF2 stalls — use it.

**On arrival: ⚠️ THE BOARD DELIVERED IS A2, NOT A4.** Read off the silicon
by `picotool info -a` on 2026-08-06:

```
type:      RP2350
revision:  A2          ← the stepping WITH the E9 erratum
package:   QFN60
```

We predicted A4 ("anything shipped new in mid-2026 should be A4"). Wrong —
this is old stock. **E9 is present on this board.**

**Why it matters to us specifically.** E9 makes a GPIO pad configured as
an *input with an internal pull-down* able to latch high (~2.2 kΩ to
ground) instead of reading a clean low. Six of our pins use exactly that:

| file | pins | purpose |
|---|---|---|
| `pico-encoder` | GP16, GP17 | encoder A/B |
| `pico-odom` | GP16–GP19 | both wheels' encoders |

### The motors that arrived (2026-08-08)

Two N20-class micro metal gearmotors with rear magnetic encoders. The
encoder board is silkscreened, so nothing here is guesswork — read the
pads, top to bottom:

```text
   M1     motor terminal        ─┐ the two motor lines sit at the OUTER
   GND    encoder ground         │ ends, deliberately: it keeps the
   C1     encoder channel A      │ high-current pair physically away
   C2     encoder channel B      │ from the two signal lines
   VCC    encoder power         ─┘
   M2     motor terminal
```

**Power VCC from 3V3, not 5V.** The C1/C2 outputs swing to whatever VCC
is, and 5 V logic into an RP2350 input is out of spec — so this is a
signal-level requirement, not a wiring convenience.

#### ✅ Measured: 28 ticks per MOTOR revolution (2026-08-08)

Model **GA12-N20**, from a listing claiming **"Count: 3PPR (Pulse per
Revolutions)"**. That claim is **wrong** — 3 PPR would be 12 ticks per
revolution after quadrature.

| Method | Result | |
|---|---:|---|
| Listing's claim | 12 | ✗ off by 2.3× |
| Bulk count, "10 rounds" of the magnet | 40.5 | ✗ really ~14.5 rounds |
| ~6 rounds, cross-check | 27.2 | ✓ |
| **1 revolution back, then 1 forward** | **28** | ✓ **round trip closed exactly** |

**28 = 7 PPR × 4 quadrature edges**, one of the most common N20 encoder
resolutions.

**The method matters more than the number.** Counting many revolutions by
hand failed badly — a small magnet disc rolls further than it feels like,
and the answer came out 45% high while looking entirely plausible. What
worked was a **single revolution with the mark realigned, done once in
each direction**:

```text
   981  --1 rev backward-->  953   (-28)
   953  --1 rev forward -->  981   (+28)
```

Returning to the *exact* starting count is the evidence. It rules out the
magnet slipping on the shaft, a miscounted revolution, and lost
transitions, all at once — none of which a bulk count can distinguish.
`errors` stayed at 0 throughout, without which the delta would just be an
undercount.

#### ✅ Measured: `ticks_per_revolution` ≈ 4290 per WHEEL revolution

Same day, by turning the rotor until the **output** shaft had completed
exactly one turn — so the rotor turns were never counted at all, only
watched:

| Run | ticks | errors | |
|---|---:|---:|---|
| 1 | 4327 | 0 | ✓ |
| — | *(3-rev attempt)* | *93* | ✗ **discarded** — see below |
| 2 | 4253 | 0 | ✓ |
| **mean** | **4290** | | **±0.9%** |

```text
   ticks_per_revolution  ≈  4290       ← the RobotSpec field
   4290 ÷ 28             =  153 : 1    ← the TRUE gear ratio
```

**The listing states no gear ratio at all** — the GA12-N20 ships 1:30
through 1:298 — and the nominal is probably "1:150". `crates/sim-core/src/spec.rs`
predicted exactly this: *"ratios advertised as '50:1' are routinely
51.45:1."*

**`SIM_BOT`'s placeholder is `1024.0`, out by 4.2×.** Odometry resolution
is four times finer than the simulator has assumed since Stage 0.

⚠️ **One run was discarded, and that is the point of the `errors`
column.** A 3-revolution attempt returned 93 errors and implied 3594
ticks/rev — 20% below the clean runs. The cause was cranking hard while
holding the motor, which tugged the bare wires in their breadboard holes.
Note that 93 flagged errors accompanied a ~1,466-tick shortfall: the
decoder only detects a jump to a *non-adjacent* state, so **a whole missed
cycle is silent**. Flagged errors always under-report their own damage.

Before turning: rest the motor on the desk, tape the wires down, and turn
slowly. Re-seat any wire whose stranded end has frayed from repeated
insertion — twisting the strands tight, or tinning the tip, makes it
stick.

#### 🚨 Wire colours — read this before touching anything

Traced against the silkscreen on 2026-08-08, on both motors:

| Pad | Colour | |
|---|---|---|
| `M1` | **white** | motor terminal |
| `GND` | **blue** | encoder ground |
| `C1` | **green** | encoder channel A |
| `C2` | **yellow** | encoder channel B |
| `VCC` | **black** | encoder power |
| `M2` | **red** | motor terminal |

> **⚠️ BLACK IS POWER. BLUE IS GROUND. RED IS A MOTOR LEAD.**
>
> Every convention says black is ground and red is positive. **On this
> motor both are wrong**, and the mistake is not recoverable: black to
> ground and blue to 3V3 puts the supply across the Hall sensor backwards
> and kills it silently.
>
> The two thick-looking outer wires — white and red — are the *motor*, not
> the power pair. Do not connect them for encoder work.

The colours are self-consistent with the silkscreen order, which is the
check that they were read correctly: reading down the connector gives
white, blue, green, yellow, black, red against `M1 / GND / C1 / C2 / VCC
/ M2`.

Bring-up wiring, which needs no H-bridge, no battery and no soldering:

```text
   VCC -> 3V3     C1 -> GP16      M1, M2 -> NOT CONNECTED
   GND -> GND     C2 -> GP17
```

Leaving the motor leads disconnected is the point: the encoder draws
milliamps, while a stalled N20 draws ~500 mA, and that current anywhere
near the Pico's 3V3 rail browns the chip out mid-tick — which reads
exactly like a firmware bug.

**C1 versus C2 does not matter.** Swapping them only makes the count run
negative when the shaft turns forward, which is a sign flip in software.
**VCC versus GND matters permanently.**

#### ✅ E9 bit, and `Pull::Up` fixed it — measured 2026-08-08

The prediction above was correct. Same motor, same wiring, magnet turned
by hand, only the pull direction changed:

| Pin config | counts | **errors** |
|---|---:|---:|
| `Pull::Down` | 44 | **15** |
| `Pull::Up` | 53 | **0** |

An error in `quad-encoder` is a state change to a non-adjacent state —
a **missed transition**. So `Pull::Down` was losing roughly a quarter of
the signal and **undercounting silently**, which is the dangerous
failure: nothing looks broken, the number is just wrong. At hand speed
against a 10 kHz poll the honest figure is 0, which is what makes 15
diagnostic rather than noise.

It also answers the open question: **the Hall outputs are push-pull.**
`Pull::Down` produced counts at all, so they actively drive high — and a
weak internal pull-up cannot fight a driven output, which is why the fix
has no side effects. It removes E9's preconditions and changes nothing
else. `firmware/pico-encoder` now sets `Pull::Up` with the numbers above
recorded beside it.

Consequence for `pico-odom`, which reads **four** encoder pins on
GP16–GP19: it has the same exposure and has never run on real silicon.
Apply the same change before trusting anything it reports.

### The bench rig, as actually built (2026-08-08)

The full page for this bench, with the bring-up commands and the
measurement methods, is [bench-rig.md](bench-rig.md).

A 400-point half-size breadboard: columns **1–30**, letters `a`–`e` and
`f`–`j` either side of the centre channel. Holes in the same **column and
half** are one electrical point; the channel joins nothing.

The Pico 2 W straddles the channel across **columns 1–20**, **USB at the
column-1 end**, its two pin rows landing in letters **`c`** and **`h`**
(the only spacing that fits — the header rows are 0.7", and `c`→`h` is
exactly that). Free reachable holes are therefore `a`/`b` and `i`/`j`.

**Physical pin → column.** The pin numbers run down one edge and back up
the other, so the two edges count in opposite directions:

```text
   left edge  (letter c):  pin N  ->  column N          N = 1..20   GP0..GP15
   right edge (letter h):  pin N  ->  column 41 - N     N = 21..40  GP16..VBUS
```

Self-check that catches an off-by-one: `GND` sits at **columns 3, 8, 13,
18 on both halves**, because the two edges count opposite ways over the
same spacing.

#### The wiring

```text
   Pico 2 W (cols 1-20, USB at col 1)          N20 motor + encoder
   ─────────────────────────────────           ───────────────────
   3V3(OUT)  pin 36  ->  col 5   hole 5i  ───── BLACK    VCC
   GND       pin 23  ->  col 18  hole 18i ───── BLUE     GND
   GP16      pin 21  ->  col 20  hole 20i ───── GREEN    C1
   GP17      pin 22  ->  col 19  hole 19i ───── YELLOW   C2
                                                WHITE    M1  ── not connected
                                                RED      M2  ── not connected
```

`j` substitutes for `i` anywhere; both are the same column. Column 18 is
chosen over the equally-valid column 3 only so three of the four wires
land next to each other.

> **⚠️ Column 4 is `3V3_EN` (pin 37), immediately beside `3V3(OUT)` at
> column 5.** It is an enable *input*: pulling it low switches the Pico's
> regulator off. Nothing may draw current through it — which is why the
> verification circuit below is built out in the empty columns 21–30
> rather than bridging 5 → 4 → 3.

#### The verification circuit

Run before wiring the motor, to prove the column map rather than assume
it. Confirmed working 2026-08-08.

```text
   col 5          col 23        col 24       col 25        col 3
   3V3(OUT) ─jumper─> ● ─[resistor]─> ● ─[LED + -> -]─> ● ─jumper─> GND
                     23i/23j       24j/24i        25i/25j
```

- Jumper `5i` → `23i`; resistor `23j` → `24j`; LED long leg `24i`, short
  leg `25i`; jumper `25j` → `3i`.
- **The LED must be red.** Blue and white need ~3.2 V forward and the rail
  is 3.3 V, so a correct circuit can read as dead.
- Lit ⇒ column 5 is 3V3, column 3 is GND, and the `f`–`j` half is the
  pins-21–40 side. All three were confirmed this way before the encoder
  was connected.

#### What lights and what does not

The onboard LED is **`WL_GPIO0` on the Infineon 43439**, per the Pico 2 W
datasheet — it is not on the 40-pin header at all. `pico-encoder`'s
heartbeat drives GP25, which on a W board is the radio's chip-select, so
**it blinks nothing and that is not a fault**. The sign of life is the USB
serial port appearing. `firmware/pico-led` is the firmware that does light
it, and it boots the entire radio to do so.

**Whether it actually bites depends on what drives the pin.** A magnetic
encoder with a push-pull output drives both high and low itself, so the
internal pull is only there to define a *disconnected* line — E9 may never
show. An open-drain or floating source is where it hurts.

**So (decided before the encoders arrived, and settled by the 2026-08-08
measurement above): do not pre-emptively rewrite the code. Test it.** Spin a
wheel slowly by hand and watch the tick count. Ticks that
stick, or counts that only ever increase, are the signature.

**The fix if it does bite**, cheapest first:
1. **External pull-down resistor ≤4.7 kΩ** on each encoder line — the
   starter kit has resistors, so this costs nothing but four joints.
2. Or switch those inputs to `Pull::Up` and invert the logic, *if* the
   encoder output is push-pull.

**For any future board purchase:** ask the seller for A4, or check
`picotool info -a` before wiring anything.

## The board as it stands, 2026-08-14 — two motors, TB6612, battery

The map above is the **2026-08-08 single-motor bench**: one N20, one
encoder, no driver chip, no battery. The car built on 2026-08-13 replaced
it and **was never written down**, which is how an afternoon of tracing
wires with a finger becomes the only copy of the wiring.

⚠️ **This section records what has been confirmed hole-by-hole and marks
what has not.** An inferred entry is worth less than a measured one and
saying which is which is the whole point — a map that quietly guesses is
worse than no map, because it gets trusted.

### The rails

```text
   + rail  ──  3.3 V     jumpered from 5j  (column 5 = physical pin 36,
                          the Pico's 3V3(OUT) regulator output)
   battery ──  ~6.4 V    4x AA alkaline, fresh, off-load
```

### Confirmed holes

**Every occupied hole, as of 2026-08-14 after the camera and the encoder
move.** Anything not listed is empty.

| hole | what is in it | net / GPIO |
|---|---|---|
| `4a` | **green**, left encoder `C1` | GP2 ⚠️ `4i` is `3V3_EN` — different half |
| `5a` | **yellow**, left encoder `C2` | GP3 |
| `5i` | **black**, left motor | encoder VCC ⚠️ black is *power* here, see the colour box above |
| `5j` | jumper to **+ rail** | 3V3 out |
| `6a` | camera `SDA` | GP4 |
| `7a` | camera `SCL` | GP5 |
| `8i` | jumper to **− rail** | ground |
| `9i` | right encoder `C2` | GP27 ⚠️ `9a` is TB6612 `PWMA` — different half |
| `10i` | right encoder `C1` | GP26 ⚠️ `10a` is TB6612 `AIN1` — different half |
| `14i` | camera `XLK` | GP21 ⚠️ `14a` is TB6612 `PWMB` — different half |
| `18i` | **blue**, left motor | encoder GND ⚠️ blue is *ground* here |
| `18j` | **blue**, right motor | encoder GND — same net, both wheels share it |
| `29i` | jumper to **+ rail** | TB6612 `VCC`, 3.3 V logic |
| `30i` | battery **red** | TB6612 `VM`, ~6.4 V motor supply |
| + rail | camera `3.3V`, camera `RET` | 3.3 V |
| − rail | camera `DGND`, camera `PWDN` | ground |

**Freed by the encoder move and now empty:** `16i`, `17i`, `19i`, `20i`.

⚠️ **Four columns carry different signals in their two halves** — `4`, `9`,
`10`, `14`. The centre channel joins nothing, so these are separate nets,
but they share a column number and read alike at a glance. **Read the
letter, not just the number.**

### ⚠️ Columns 29 and 30 are 3.3 V and 6 V, side by side

They are adjacent strips. A jumper that slips one column, or a stripped
end that bridges them, **puts 6 V onto the Pico's 3V3 rail** — which is
the regulator's *output*, so the damage runs backwards into the board and
into anything else sharing that rail. On this bench that is the camera.

The pairing is not a mistake: a TB6612 wants motor voltage on `VM` and
logic voltage on `VCC`, and those pins are next to each other on the
module. It is the correct wiring and a permanent hazard, which is exactly
the combination worth writing down rather than remembering.

**The check, before every power-on:** battery connected, USB out, the
+ rail must read **0 V**. Any reading near 6 V means the two have met.

### The TB6612, derived from one read-back and cross-checked twice

The module occupies **columns 23–30**, straddling the channel, with its
header rows in **`d` (control)** and **`h` (power and motor outputs)** —
0.6" apart, the only spacing that fits, exactly as the Pico's own rows sit
0.7" apart in `c` and `h`.

So `30d` and `30h` are *different nets* despite sharing a column number,
and `30h` reaches `30i`/`30j` because `f`–`j` is one strip.

**Read off the board: `30d` is `PWMA` and `30h` is `VM`.** Column 30 is
the last column, so the module can only extend downward, which fixes every
remaining pin:

```text
   column      30    29    28    27    26    25    24    23
   ─────────────────────────────────────────────────────────
   row d      PWMA  AIN2  AIN1  STBY  BIN1  BIN2  PWMB  GND
   row h       VM   VCC   GND   AO1   AO2   BO1   BO2   GND
                ^     ^
                │     └── 29i jumpers to the + rail   = 3.3 V logic  ✓
                └──────── 30i takes the battery red   = ~6.4 V motor ✓
```

⚠️ **Why this is stronger than the guess it replaces.** Three holes were
read back independently — `30d`, `30h`, and the two power jumpers — and
all of them land exactly where this ordering predicts. A wrong orientation
or a different module variant would have put a motor output or a ground
under the battery wire. Three independent agreements is evidence; the
earlier version of this section had none, and said so.

**Which Pico pin each control line comes from**, per
`firmware/pico-odom/src/main.rs`:

| TB6612 | GPIO | physical pin | Pico column | jumper runs to |
|---|---|---|---|---|
| `PWMA` | GP6 | 9 | 9 (`a`/`b`) | `30` |
| `AIN1` | GP7 | 10 | 10 (`a`/`b`) | `28` |
| `AIN2` | GP8 | 11 | 11 (`a`/`b`) | `29` |
| `STBY` | GP9 | 12 | 12 (`a`/`b`) | `27` |
| `PWMB` | GP10 | 14 | 14 (`a`/`b`) | `24` |
| `BIN1` | GP11 | 15 | 15 (`a`/`b`) | `26` |
| `BIN2` | GP12 | 16 | 16 (`a`/`b`) | `25` |

⚠️ **The jumper table is derived, not read back.** The GPIO column is
certain — it comes from the source. Which physical jumper reaches which
module pin has not been traced, and `AIN1`/`AIN2` in particular could be
swapped without anything looking wrong: a reversed pair simply drives that
motor backwards, which is the fault
[`firmware/support/src/motor.rs`](../firmware/support/src/motor.rs) already
carries two measured sign constants for.

**The cheapest spot-check** is `27d`: this table says `STBY`. If it is
anything else, the whole row is shifted and the rest of this section is
wrong.

### 2026-08-14 — the encoders moved, to make room for camera pixels

**Rewired and verified on the bench.** The firmware was remapped first, so
the change could be built and reviewed before a single wire moved.

**Why.** PIO parallel capture reads a **contiguous** pin group, so the
camera's `D0`–`D7` need **eight consecutive GPIOs**. The board had none —
the longest free run was four. Quadrature decoding has no such
requirement, so the encoders move and the camera gets the run.

**The final allocation**, 25 of 26 pins:

| what | pins | moved? |
|---|---|---|
| TB6612 | GP6–GP12 | no |
| I2C (camera SCCB, future PCA9685) | GP4, GP5 | no |
| camera `D0`–`D7` | GP13–GP20 | new |
| camera `XCLK` | GP21 | no |
| camera `PCLK`, `VSYNC` | GP0, GP1 | new |
| camera `HREF` | GP22 | new |
| **left encoder** `C1`,`C2` | **GP2, GP3** | ⚠️ **was GP16, GP17** |
| **right encoder** `C1`,`C2` | **GP26, GP27** | ⚠️ **was GP18, GP19** |
| spare | GP28 | — |

⚠️ **Why the camera, not the encoders, gets GP0/GP1.** Those are UART0,
which `pico-odom`'s default build uses as its transport for the emulator.
Encoders there would collide *unconditionally* and break that build. The
camera is behind a feature flag, so `camera` and the UART transport are
never both live — the collision cannot happen. Verified by building all
five variants including RP2040/UART.

**The four wires that moved**, using the column formula (`pin N` → column
`N` on the `c` side for N ≤ 20, column `41 − N` on the `h` side for N ≥ 21):

| wire | was | now | side |
|---|---|---|---|
| left `C1` (green) | `20i` | **`4a`** | crossed to the `a`/`b` half |
| left `C2` (yellow) | `19i` | **`5a`** | crossed to the `a`/`b` half |
| right `C1` | `17i` | **`10i`** | stayed on `i`/`j` |
| right `C2` | `16i` | **`9i`** | stayed on `i`/`j` |

`16i`, `17i`, `19i` and `20i` are now **free**.

⚠️ **Columns are shared between halves, and this map leans on it.**
`4a`/`5a` are GP2/GP3 while `4i`/`5i` are `3V3_EN` and `3V3(OUT)`;
`9i`/`10i` are GP26/GP27 while `9a`/`10a` are the TB6612's `PWMA`/`AIN1`.
Same column number, different net, one hole apart across the channel.
**Read the letter, not just the number.**

⚠️ **`LEFT_ENCODER_SIGN` and `DRIVETRAIN_SIGN` must be re-verified after
this.** Both are measured facts about *this wiring*, and the wiring just
changed. The test is the one already written down: command a pure spin and
check the two encoders move in opposite directions; command forward and
check the chassis goes forward.

### Still not confirmed

- **Where the battery's black wire lands.** Grounds must be common; that
  they *are* is inferred only from the robot having driven.
- **Where the right motor's encoder lands.** The firmware reads GP18/GP19
  (physical pins 24/25, so columns 17 and 16 on the `i`/`j` side), and the
  robot reports both wheels, so something is there. Not read back.
- **The left motor's `M1`/`M2` leads** — `AO1`/`AO2` at `27i`/`26i` by the
  table above, untraced.

Filling those in is one pass with a finger and five minutes; as of
2026-08-14 it was due before the board was next disturbed.

### ⚠️ The PCA9685's screw terminal is DEAD — V+ feeds through the pins

Found 2026-08-15, by elimination with every other suspect proven: two
battery packs live at their own leads, `30j`↔− rail live on the board
(an LED without its resistor died proving it — one bright flash at 6 V),
the servo alive the moment power AND signal reached it together — and
still nothing through the terminal. The green screw terminal's path to
the board's V+ rail conducts nothing; likely its solder joints.

**The permanent wiring bypasses it.** The channel pin rows ARE the V+
rail — feeding any one channel feeds all sixteen:

```text
   30j     ──jumper──▶  channel 15 middle pin (red row)    V+ 6 V
   − rail  ──jumper──▶  channel 15 bottom pin (black row)  GND
   green screw terminal: NOTHING — leave it empty forever
```

⚠️ Channel 15 is thereby the power tap, not a servo slot. Servos occupy
0–14.

Two debug lessons paid for that night (2026-08-15), written so they stay paid:
- **An LED never touches a supply without its resistor.** At 6 V a bare
  LED gives one bright flash and is dead forever — which at least
  certified the rail as live on its way out.
- **A servo with power but no signal proves nothing by staying still.**
  No PWM means the amplifier idles: no hold, no hum, often no twitch.
  Only power + signal together test a servo, and a limp horn condemns
  the *pair*, never one of them.

### Free for the camera

Everything `firmware/pico-camera` needs is unoccupied:

```text
   OV7670          hole        why
   ──────          ────        ───
   3V3     ──────  + rail      already at 3.3 V via 5j
   GND     ──────  - rail      see the note below
   SIOD    ──────  6a          GP4
   SIOC    ──────  7a          GP5
   XCLK    ──────  14i         GP21   <- NOT 14a
   RESET   ──────  + rail      active-low; tie HIGH
   PWDN    ──────  - rail      active-high; tie LOW
```

### ⚠️ Only `a`/`b` and `i`/`j` are reachable — `d`,`e`,`f`,`g` are under the board

The Pico's pin rows are `c` and `h`, and its **body covers rows `d`, `e`,
`f` and `g` for its whole length**. Those holes are electrically part of
their strip and physically unusable — no wire fits under the board.

This is stated at the top of the 2026-08-08 map and was still got wrong
here on 2026-08-14: an earlier version of this table sent the camera's
`GND` and `PWDN` to `18f` and `18g`, which cannot be wired at all. Kept as
a note because "electrically correct, physically impossible" is a failure
mode a schematic never shows.

**Consequence for ground: column 18 is FULL.** It is physical pin 23, so
the whole `f`–`j` strip is ground — but `18h` is the Pico's own pin and
`18i`/`18j` hold the two encoder grounds. Nothing reachable is left.

**So ground needs a rail.** The board already jumpers 3.3 V to the + rail
via `5j`; ground never got the same treatment, and this is where that
shows.

**Decided 2026-08-14: `8i` → − rail**, on the same edge as the + rail, and
every future ground comes from there.

⚠️ **Why `8i` and not `3i`.** Column 3 is ground and would work
electrically, but it sits immediately beside **column 4, `3V3_EN`** — the
regulator enable, which switches the Pico off if it is pulled low — and
one column from `5i`/`5j`, already holding the motor's VCC and the + rail
jumper. Column 8 is clear of that whole cluster. The 2026-08-08 map chose
column 18 over column 3 for the motor ground on exactly this reasoning;
this is the same call made twice, so it is worth stating as a rule:
**keep ground jumpers away from columns 3–5.**

⚠️ **`14i`, never `14a`.** Column 14's `a`/`b` half is **GP10, a TB6612
motor PWM pin**. The centre channel joins nothing so they are separate
nets, but they carry the same column number and read alike at a glance.

## What was ready to run when the board arrived

These existed before the board landed and were UF2-ready
(rebuild with `rp235xa` feature + `thumbv8m.main-none-eabihf` target —
see the port table in [hardware-sim.md](hardware-sim.md)):

- `firmware/pico-blink` — two async tasks (H0)
- `firmware/pico-button` — button + software PWM (H1)
- `firmware/pico-imu` — MPU6050 over I2C via our driver (H2)
- `firmware/pico-encoder` — quadrature decoding (H3)
