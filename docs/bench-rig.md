# The bench rig — everything, in one page

*Written 2026-08-08 as the bench rig was built, with additions on 2026-08-09; kept as the hardware record (the later board of 2026-08-14 is mapped in [parts.md](parts.md)).*

**As built 2026-08-08.** If the desk gets cleared, this page rebuilds it
from parts without re-deriving anything. Every symbol is defined where it
appears; nothing here needs another page open.

---

## 0. THE BOARD AS IT STOOD

**Last updated 2026-08-08, after the TB6612 went on.** This section was the
live map; everything below it is the reasoning behind it.

Numbering on this board runs **30 on the left → 1 on the right**, USB at
the column-1 end.

```text
   ┌───────────────────────────────────────────────────────────────────────┐
   │ +  ●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●  3V3      │
   │ −  ●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●  GND      │
   ├───────────────────────────────────────────────────────────────────────┤
   │ col  30  29  28  27  26  25  24  23 │22 21│ 20 19 18 17 16 …13…  9..5 │
   │                                     │     │                           │
   │  a    ·   ·   ·   ·   ·   ·   ·   · │ ·  ·│  ·  ·  ·  ·  ·   ·  ▲▲▲▲  │
   │  b    ·   ·   ·   ·   ·   ·   ·   · │ ·  ·│  ·  ·  ·  ·  ·   ·   ·    │
   │  c   ◆PWM ◆AI2 ◆AI1 ◆STB  ·   ·   · ◆GND│ ·  ·│ ╞════ PICO 2 W ══════╡ │
   │  d   ▣▣▣▣▣▣▣▣ TB6612 pads ▣▣▣▣▣▣▣▣ │ ·  ·│  ░░░ Pico body ░░░        │
   │  e    ░░ under the TB6612 ░░        │ ·  ·│  ░░░              ░░░     │
   │ ══════════════════ CENTRE CHANNEL ════════════════════════════════════│
   │  f    ░░ under the TB6612 ░░        │ ·  ·│  ░░░ Pico body ░░░        │
   │  g    ░░                  ░░        │ ·  ·│  ░░░              ░░░     │
   │  h   ▣▣▣▣▣▣▣▣ TB6612 pads ▣▣▣▣▣▣▣▣ │ ·  ·│ ╞════ PICO 2 W ══════╡ │
   │  i   ◆VM ◆VCC ◆GND ◆AO1 ◆AO2  ·   · │ ·  ·│  ▼  ▼  ▼  ▼  ▼  ◆GND ◆3V3 │
   │  j    ·   ·   ·   ·   ·   ·   ·   · │ ·  ·│  ·  ·  ▼  ·  ·   ·    ▼   │
   └───────────────────────────────────────────────────────────────────────┘
      ◆ = a wire goes here      ▣ = a board's own pins
      ▲ = motor-driver control jumpers      ▼ = encoder wires
```

### Every wire currently on the board

| Hole | Wire | Connects |
|---|---|---|
| `5i` | motor ① **black** | 3V3(OUT), pin 36 |
| `5j` | jumper | → **`+` rail** |
| `+` rail | motor ② **black** | 3V3 |
| `18i` | motor ① **blue** | GND, pin 23 |
| `18j` | motor ② **blue** | GND |
| `13i` | jumper | → **`−` rail** (GND, pin 28) |
| `20i` | motor ① **green** | GP16 — encoder ① A |
| `19i` | motor ① **yellow** | GP17 — encoder ① B |
| `17i` | motor ② **green** | GP18 — encoder ② A |
| `16i` | motor ② **yellow** | GP19 — encoder ② B |
| `9a` → `30c` | jumper | GP6 → `PWMA` |
| `11a` → `29c` | jumper | GP8 → `AIN2` |
| `10a` → `28c` | jumper | GP7 → `AIN1` |
| `12a` → `27c` | jumper | GP9 → `STBY` |
| `−` rail → `23c` | jumper | `GND` (control side) |
| `+` rail → `29i` | jumper | `VCC` (3.3 V logic) |
| `−` rail → `28i` | jumper | `GND` (power side) |
| `27i` | motor ① **white** | `AO1` |
| `26i` | motor ① **red** | `AO2` |
| `30i` | **battery +** | `VM` — connect **last** |
| `−` rail | **battery −** | common ground |

### The TB6612, columns 30 → 23

Pads in rows **`d`** and **`h`** (a 0.6″ board, so it sits toward the `a`
side). Wire into **`c`** for the `d` row and **`i`** for the `h` row —
nearest free hole, same column, same net.

```text
   col:    30    29    28    27    26    25    24    23
   row d  PWMA  AIN2  AIN1  STBY  BIN1  BIN2  PWMB  GND
   ══════════════════ CHANNEL ══════════════════════════
   row h   VM   VCC   GND   AO1   AO2   BO2   BO1   GND
```

⚠️ The silkscreen order is **`PWMA, AIN2, AIN1, STBY`** — `AIN1` and
`AIN2` are *not* in numeric order, which is why the two jumpers from the
Pico cross over.

Columns 25 and 24 (`BIN1 BIN2 PWMB` / `BO2 BO1`) are the **second motor**
and stayed empty at this point.

### GPIO allocation

| GPIO | Column | Use |
|---|---|---|
| GP6 | 9 (`a` side) | `PWMA` — PWM slice 3 A |
| GP7 | 10 | `AIN1` |
| GP8 | 11 | `AIN2` |
| GP9 | 12 | `STBY` |
| GP16 | 20 (`i` side) | encoder ① A |
| GP17 | 19 | encoder ① B |
| GP18 | 17 | encoder ② A |
| GP19 | 16 | encoder ② B |
| *GP4* | *6* | *reserved — I2C0 SDA for the MPU-6050* |
| *GP5* | *7* | *reserved — I2C0 SCL* |

> ⚠️ **`5a` and `5i` are different nets.** Same column, opposite sides of
> the channel: `5a` is GP3, `5i` is 3V3(OUT). The channel separates them,
> and this is the easiest mistake on the board.

### Verifying the driver before a battery goes near it

**Every functional pad on the TB6612 was proven on 2026-08-09 without
connecting the battery at all**, by substituting two things:

```text
   VM        battery 6 V   ──▶   the + rail, 3.3 V   (TB6612 accepts 2.5–13.5 V)
   AO1/AO2   the motor     ──▶   a red LED and a resistor
```

Then the ordinary duty sweep runs and the LED steps through five
brightness levels — at ~30 kHz the eye integrates PWM, so brightness *is*
duty. **Five distinct levels proves the whole chain by function rather
than by eye:** `VCC`, `GND`, `STBY`, `AIN1`, `AIN2`, `PWMA`, `AO1`, `AO2`.

Build the LED and resistor as one part — twist a resistor leg around the
LED's **long** leg — because `AO1` and `AO2` are adjacent columns and two
components will not fit between two adjacent holes. Long leg toward `AO1`,
which is the positive side when `AIN1` is high.

**Two things this catches that inspection cannot:**

- **A solder bridge.** `VM`, `VCC` and `GND` are adjacent at columns 30,
  29, 28, and a blob across `VM`–`GND` is a dead short across four AA
  cells. Powered from 3V3 instead, the Pico's regulator simply
  current-limits and the **USB port disappears** — a diagnosis, at 4 mA,
  with nothing hot.
- **A joint that looks fine.** Cold joints wet the pad enough to pass a
  glance and still not conduct.

#### Testing channel B without touching the firmware

Channel B's seven pads carry no current in the test above, so they stay
unproven. Rather than write a second sweep, **tie B's inputs to A's** and
let one sweep drive both:

```text
   30b → 24c     PWMB → PWMA
   29b → 25c     BIN2 → AIN2
   28b → 26c     BIN1 → AIN1
```

Second LED assembly across `24i` (`BO1`) and `25i` (`BO2`), long leg
toward `BO1`. Both LEDs then step in unison — confirmed 2026-08-09.

Because B is following A's *inputs*, a dark second LED cannot be firmware
or a Pico pin. It is a joint or one of those three jumpers, and the fault
is localised before any searching starts.

⚠️ **Remove those three jumpers before connecting motor ②**, or it
runs in lockstep with ①.

The two `GND` pads at column 23 stay unproven either way — they are
redundant, and the chip works while `28h` is good. To cover them, ground
only through `23i` (or `23c`) and confirm the sweep still runs.

### ⚠️ Tin the wire ends

The motors' stranded ends fray a little every time they are pushed into a
breadboard, and by the end of the first evening they would not seat at
all. Worse, a marginal one **counts intermittently** — a run on 2026-08-08
climbed to 93 decode errors mid-measurement and implied a tick count 20%
low, which looked entirely plausible.

Fix it once: heat the wire with the iron for 2–3 seconds, touch solder to
the **wire** on the far side from the tip so it wicks in, and keep it
thin — a coating, not a bead, or it will not fit a 0.8 mm hole. Snip the
tip square if it blobs.

---

## 1. The whole thing at a glance

```text
        ┌── USB cable ──────────────────────────┐
        │   power + serial, to the Mac          │
        ▼                                        │
   ┌─────────────────────────────────────┐       │
   │  Pico 2 W  on a 400-point breadboard│       │
   │                                     │       │
   │   3V3(OUT) col 5  ──────── BLACK ───┼───┐   │
   │   GND      col 18 ──────── BLUE  ───┼───┤   │
   │   GP16     col 20 ──────── GREEN ───┼───┤   │
   │   GP17     col 19 ──────── YELLOW ──┼───┤   │
   └─────────────────────────────────────┘   │   │
                                              ▼   │
                            ┌──────────────────────────┐
                            │  GA12-N20 gearmotor      │
                            │  + rear magnetic encoder │
                            │                          │
                            │  WHITE (M1) ── unconnected│
                            │  RED   (M2) ── unconnected│
                            └──────────────────────────┘
                                    ▲            ▲
                          output shaft      black magnet disc
                          (can't turn        (turns freely —
                           by hand yet)       this is the ROTOR)
```

Four wires. No battery, no motor driver, nothing soldered.

---

## 2. How a breadboard conducts

The one fact that makes every hole number below meaningful:

```text
   ┌─ + −  ┃  a b c d e  ┃  f g h i j  ┃  + − ─┐
   │       ┃             ┃             ┃       │
   │   1   ┃  ●─●─●─●─●  ┃  ●─●─●─●─●  ┃       │   ← row 1 left half is ONE wire.
   │   2   ┃  ●─●─●─●─●  ┃  ●─●─●─●─●  ┃       │     Row 1 right half is a
   │  ...  ┃             ┃             ┃       │     DIFFERENT wire.
   │  30   ┃  ●─●─●─●─●  ┃  ●─●─●─●─●  ┃       │
   └───────┸─────────────┸─────────────┸───────┘
                         ▲
              the centre channel. Nothing crosses it.
```

> **Holes sharing a number *and* a half are the same electrical point.**

The outer `+` / `−` strips are power rails running the full length. **This
first layout does not use them.**

---

## 3. Where the Pico sits, and how to find any pin

The Pico straddles the channel across **columns 1–20**, **USB at the
column-1 end**. Its two pin rows land in letters **`c`** and **`h`** —
the only spacing that fits, because the header rows are 0.7 inches apart
and `c`→`h` is exactly 0.7.

```text
                  USB (points off the column-1 end)
                        │
        col:  1   2   3   4   5  ...  18  19  20 │ 21..30 free
             ─────────────────────────────────────────────
        j     ·   ·   ·   ·   ·        ·   ·   ·  │
        i     ·   ·   ·   ·   ●        ●   ●   ●  │   ← the four wires
        h    [═══════ Pico pins 40..21 ════════]  │
             ══════════ centre channel ═════════  │
        c    [═══════ Pico pins  1..20 ════════]  │
        b     ·   ·   ·   ·   ·        ·   ·   ·  │
        a     ·   ·   ·   ·   ·        ·   ·   ·  │
```

Because the pin numbers run **down one edge and back up the other**, the
two edges count in opposite directions:

```text
   letter c  (pins  1..20, GP0..GP15)   pin N  →  column N
   letter h  (pins 21..40, GP16..VBUS)  pin N  →  column 41 − N
```

Worked, for the four pins that matter:

| Signal | Physical pin | Column | Free hole used |
|---|---:|---:|---|
| `GP16` | 21 | 41−21 = **20** | `20i` |
| `GP17` | 22 | 41−22 = **19** | `19i` |
| `GND` | 23 | 41−23 = **18** | `18i` |
| `3V3(OUT)` | 36 | 41−36 = **5** | `5i` |

**Self-check that catches an off-by-one:** `GND` lands on columns
**3, 8, 13, 18** — and on *both* halves, because the edges count opposite
ways over the same spacing. If the grounds don't fall there, the Pico is
seated wrong.

`j` substitutes for `i` anywhere. `a`/`b` are the free holes on the other
half.

---

## 4. The encoder, and its wire colours

The board on the back of the motor is silkscreened. **Read it, don't
assume:**

```text
   ┌──────────┐
   │ M1   ●   │  white    motor terminal      ─┐ motor pair sits at the
   │ GND  ●   │  blue     encoder ground       │ OUTER ends, deliberately,
   │ C1   ●   │  green    encoder channel A    │ to keep high current away
   │ C2   ●   │  yellow   encoder channel B    │ from the signal lines
   │ VCC  ●   │  black    encoder power        │
   │ M2   ●   │  red      motor terminal      ─┘
   └──────────┘
```

> ### 🚨 BLACK IS POWER. BLUE IS GROUND. RED IS A MOTOR LEAD.
>
> All three are backwards from convention. Black-to-ground and blue-to-3V3
> puts the supply across the Hall sensor in reverse and **kills it
> silently and permanently**.
>
> The colours are self-checking: down the connector they run white, blue,
> green, yellow, black, red — matching the silkscreen order exactly. If
> they don't line up like that, stop and re-trace.

### The wiring

```text
   BLACK  (VCC) ────▶ 5i      3V3(OUT), pin 36
   BLUE   (GND) ────▶ 18i     GND,      pin 23
   GREEN  (C1)  ────▶ 20i     GP16,     pin 21
   YELLOW (C2)  ────▶ 19i     GP17,     pin 22

   WHITE  (M1) ─────▶ ✗ nothing
   RED    (M2) ─────▶ ✗ nothing
```

**Why VCC comes from 3V3 and not 5 V:** the C1/C2 outputs swing to
whatever VCC is. Feed the encoder 5 V and it presents 5 V logic to a
3.3 V input, which is out of spec. This is a signal-level requirement,
not a wiring convenience.

**Why the motor leads stay loose:** the encoder draws milliamps; a stalled
N20 draws ~500 mA. That current near the Pico's 3.3 V rail browns the chip
out mid-tick, which reads exactly like a firmware bug.

**C1 vs C2 doesn't matter** — swapping them only makes the count run
negative when the shaft turns forward, a sign flip in software. **VCC vs
GND matters permanently.**

---

## 5. Proving the pin map before trusting it

Run this *before* connecting the motor. It confirms three things at once:
which column is 3V3, which is GND, and that the `f`–`j` half really is the
pins-21–40 side.

```text
   col 5          col 23        col 24        col 25         col 3
   3V3(OUT) ─jump─▶  ● ─[resistor]─▶ ● ─[LED + → −]─▶ ● ─jump─▶ GND
                   23i/23j        24j/24i        25i/25j
```

- jumper `5i`→`23i`; resistor `23j`→`24j`; LED **long leg** `24i`, short
  leg `25i`; jumper `25j`→`3i`
- **The LED must be RED.** Blue and white need ~3.2 V forward against a
  3.3 V rail, so a *correct* circuit reads as dead.
- Built in the empty columns 21–30 on purpose — see the `3V3_EN` trap
  below.

Lights up ⇒ the map is proved. Confirmed working 2026-08-08.

---

## 6. Firmware and commands

```sh
tools/build-pico2.sh pico-encoder usb     # RP2350 + USB CDC serial
```

Then hold **BOOTSEL**, plug USB in, release — an `RP2350` drive appears:

```sh
picotool load -x firmware/pico-encoder/pico-encoder-pico2.uf2
ls /dev/cu.usbmodem*
screen /dev/cu.usbmodem11 115200          # quit: Ctrl-A, then K, then y
```

Output, four lines a second:

```text
count=     38  fwd        4 ticks/s  errors=0
           │    │              │            │
           │    │              │            └─ missed transitions.
           │    │              │               ANY non-zero value means
           │    │              │               `count` is an UNDERCOUNT.
           │    │              └─ rate, from the measured elapsed time
           │    └─ fwd / rev / ---
           └─ cumulative, signed, survives until reflash
```

`picotool` **cannot** reboot the board — embassy doesn't expose
the reset interface — so the BOOTSEL dance is always manual.

**No LED will blink.** On a Pico 2 W the onboard LED is `WL_GPIO0` on the
radio, not a header pin. The USB port appearing is the sign of life.
`firmware/pico-led` is the one that lights it, and it boots the whole
radio to do so.

### Both motors, both encoders, and a live picture

`pico-encoder` reads one channel and prints. `pico-odom` is the rig that
does everything at once: it drives **both** TB6612 channels through a duty
sweep, reads **both** encoders, integrates `sim-core`'s odometry on the
chip, and reports 50 times a second.

```sh
tools/build-pico2.sh pico-odom usb
picotool load -x firmware/pico-odom/pico-odom-pico2-usb.uf2   # after BOOTSEL
```

⚠️ **Nothing moves until the port is opened.** The firmware waits on the
USB `DTR` line — the signal a host raises when a program opens
`/dev/cu.usbmodem…`. A board on a charger, or plugged into a laptop with
no terminal running, stays inert. That started as a way to make an
18-second sweep catchable and stayed because it is the better safety
property.

So opening either of these **starts the motors**:

```sh
screen /dev/cu.usbmodem11 115200                              # the text
cargo run -p hil-host --example odom_view -- /dev/cu.usbmodem11   # the picture
```

One report line, with every symbol defined:

```text
pose x=-0.001 y=+0.003 th=-0.863  ticks L=-37793 R=38304  errL=235 errR=207  duty=0%
       │        │         │              │         │            │      │           │
       │        │         │              │         │            │      │           └─ what the sweep is
       │        │         │              │         │            │      │              commanding, 0–100
       │        │         │              │         │            │      │
       │        │         │              │         │            │      └─ RIGHT wheel missed transitions
       │        │         │              │         │            └──────── LEFT  wheel missed transitions
       │        │         │              │         │                      Split per wheel on purpose: a
       │        │         │              │         │                      miss is an UNDERCOUNT, so a
       │        │         │              │         │                      summed figure cannot say which
       │        │         │              │         │                      wheel reads low — and that is
       │        │         │              │         │                      the exact confound when the two
       │        │         │              │         │                      wheels' speeds are compared.
       │        │         │              │         │
       │        │         │              │         └─ right encoder count, signed, cumulative
       │        │         │              └─────────── left  encoder count, signed, cumulative
       │        │         │                           OPPOSITE SIGNS ARE CORRECT: the motors face
       │        │         │                           opposite ways, so "both forward" counts one
       │        │         │                           up and the other down.
       │        │         │
       │        │         └─ heading in radians, from the chip's own dead reckoning
       │        └─────────── believed y position, metres
       └──────────────────── believed x position, metres
```

And when the commanded duty and the encoders disagree:

```text
… duty=25%  *** STALLED: commanded but not moving — check power ***
```

That banner exists because on 2026-08-09 the battery pack's switch was
off, the firmware ran a textbook-looking 0→100% sweep, and **nothing
anywhere said the wheels never turned.** The firmware now stops driving
and says so — a commanded motor that is not turning is either
disconnected, which is harmless, or stalled and heating, which is not.

### Driving the motors from the laptop

A third build swaps the calibration sweep for a **command channel**. The
laptop sends twists; the chip converts them to wheel duty with the same
kinematics the simulator uses, and stops the motors when the laptop goes
quiet.

```sh
tools/build-pico2.sh pico-odom teleop
picotool load -x firmware/pico-odom/pico-odom-pico2-teleop.uf2   # after BOOTSEL

# creep forward for 2 s, then go silent on purpose
cargo run -p hil-host --example twist_send -- /dev/cu.usbmodem11 0.10 0.0 2
```

```text
      what the host sends           what the chip does with it
   ┌────────────────┐            ┌──────────────────────────────┐
   │ 0.10  forward  │  T v w     │ DiffDrive::inverse   → wheels │
   │       m/s      │ ─────────▶ │ fit_wheels           → clamp  │
   │ 0.00  turn     │   USB      │ RobotSpec::duty      → ±1000  │
   │       rad/s    │            │ CommandWatchdog::gate         │
   └────────────────┘            │ TB6612  AIN/BIN + PWM         │
                                 └──────────────────────────────┘
```

**The test is what happens when the commands stop.** `twist_send` deliberately
falls silent at the end rather than sending a zero — it is imitating a
host that crashed. The wheels must stop **within 200 ms without being
told to**, because an H-bridge holds its last command indefinitely: a
robot whose laptop dies does not coast, it drives into the wall at
whatever it was last given.

If they keep turning, the watchdog is not wired up, and that is a bug that
is completely invisible while everything is working.

⚠️ Commands below about **4.3% duty do nothing at all** — the measured
deadband. At `max_wheel_speed` 7.77 rad/s and a placeholder wheel radius,
that is roughly `v < 0.02 m/s`. Not a fault; the motor genuinely cannot
overcome its own friction there.

⚠️ The metres are **wrong by ~4.2×** and will stay wrong until
`RobotSpec::REAL_BOT` is filled in — it still holds the `1024.0`
placeholder where the bench measured 4290 ticks per wheel revolution. The
*shape* is right, which is what the viewer is for: two wheels the same way
draws a straight line, opposite ways spins on the spot, one wheel arcs.

---

## 7. Measured so far

| Quantity | Value | How |
|---|---|---|
| Encoder resolution | **28 ticks / motor revolution** | 1 rev back then 1 forward; round trip closed exactly |
| **`ticks_per_revolution`** | **≈ 4290 ± 0.9%** | two clean single output revolutions: 4327 and 4253, both `errors=0` |
| Gear ratio | **≈ 153 : 1** | 4290 ÷ 28. No listing stated it |
| Hall output type | **push-pull** | `Pull::Down` produced counts at all, so they drive high |
| Pin pull | **`Pull::Up` required** | E9 — see traps |
| **`max_wheel_speed`** | **≈ 7.77 rad/s** (74.2 output RPM) | driven sweep on 4×AA; placeholder 30.0 is **3.9× too fast** |
| Motor deadband | **≈ 4.6% duty** | fitted from the four sweep points |

### The speed–duty curve, measured 2026-08-09

```text
   duty    ticks/s   output rev/s    RPM
    25%      1128       0.263        15.8
    50%      2522       0.588        35.3
    75%      3906       0.910        54.6
   100%      5302       1.236        74.2

   fit:  speed = 55.6 x (duty - 4.6%)     within 6 ticks/s everywhere
```

Linear above a **~4.6% deadband** — the duty needed just to overcome
friction and cogging before anything turns.

⚠️ **The 100% point sits on the sampling ceiling.** The loop polls at
10 kHz and can therefore track transitions below 5 kHz; 5302 ticks/s is
past that. Errors were 50 in 38,507 (0.13%), so the figure is a slight
*under*-estimate rather than noise.

`SIM_BOT`'s placeholder for `ticks_per_revolution` is `1024.0`, called "a
round number" in its own docstring. **Reality is 4.2× finer.**

**Not yet measured (as first written, 2026-08-08):** `wheel_radius`, `track_width`, `max_wheel_speed`.

### Getting a tighter number later

The remaining ±0.9% is **one stopping judgement per run** — the flag on
the output shaft parked by eye to about ±3°. Turning more revolutions per
run divides that error, because there is still only one stop:

```text
   1 revolution per run    ±0.9%     ← where it stood
   3 revolutions per run   ±0.3%
   50 revolutions per run  ±0.02%    ← needs the motor driving itself
```

Three ways to do better, in increasing order of what they need:

**1. More revolutions per run, by hand.** Free, and 3 revolutions costs
~2 minutes. The risk is the one that voided an earlier attempt: turn fast
and `errors` climbs.

**2. Drive the motor and count 50+ output revolutions.** Needs the TB6612
and a battery. A steady slow spin is far easier to count than hand-turning
— and it is the same rig `max_wheel_speed` requires anyway.

**3. Calibrate metres-per-tick end to end.** Once there are wheels and a
chassis: drive a **measured straight line** — 2 m against a tape measure —
and count ticks. This is what real robots do, and it is strictly better
than measuring the parts separately, because it absorbs the effect
`spec.rs` calls the largest single source of odometry drift: a loaded tyre
has a smaller effective radius than a free one, and no caliper measurement
catches that.

The order matters. **Do not tighten this number before `wheel_radius` is
measured under load** — the bigger unknown sits upstream, and precision in
the smaller one is wasted until then.

### Measuring the gear ratio, when the output shaft can be turned

Wrap electrical tape tightly round the output shaft until it's
pencil-thick, leaving 3 cm folded sticky-to-sticky as a stiff tab. That
fixes both problems at once — **leverage** (torque is force × radius, and
1.5 mm of radius against ~50:1 gearing is hopeless) and **grip** — and the
tab doubles as the reference flag.

```text
        motor                    ╭── stiff folded tab: flag + crank handle
     ┌────────┐                 ╱
     │        ├──▓▓▓▓▓▓▓▓▓─────╯
     └────────┘   ↑ tape wrapped tight
```

Then one output revolution, tab realigned, and back again:

```text
   delta        =  ticks_per_revolution   ← the RobotSpec field
   delta ÷ 28   =  the TRUE gear ratio    ← which no listing states
```

Expect 840 (1:30), 1400 (1:50) or 2800 (1:100). A large count is good
news: sloppy alignment barely moves the answer, unlike the 28-tick magnet
where every degree mattered.

---

## 8. The traps, all of them

Each of these cost real time, and each looks like something else.

**1. `Pull::Down` silently undercounts — RP2350-E9.** On A2 silicon an
input with an internal pull-down can latch high. Measured on this rig:

```text
   Pull::Down   44 counts,  15 errors     ~25% of steps lost
   Pull::Up     53 counts,   0 errors
```

Nothing looked broken. [parts.md](parts.md) predicted this before
the motors were ordered. **Do not "tidy" `Pull::Up` back.**

**2. Column 4 is `3V3_EN`, right beside `3V3(OUT)` at column 5.** It is
an *enable input*; drawing current through it switches the Pico's
regulator off. Build test circuits out in columns 21–30.

**3. `GP16` is physical pin 21, not pin 16.** Counting sixteen pins from
the corner lands on GP12. GP numbers and physical pin numbers diverge
immediately.

**4. Black is VCC, blue is GND.** See §4.

**5. A blue or white test LED reads as dead** on a 3.3 V rail. Use red.

**6. Bulk-counting revolutions by hand does not work.** "10 rounds" of the
magnet gave 40.5 ticks/rev; the truth is 28. It rolls further than it
feels like, and **40.5 is a completely plausible wrong answer.** Use one
revolution with the mark realigned, in both directions, and check the
count returns to where it started. Closure beats repetition — it rules out
slipping, miscounting and lost transitions simultaneously.

**7. The listing lied twice.** Claimed 3 PPR (would be 12 ticks/rev;
actually 28), and states no gear ratio at all. `spec.rs` exists because of
exactly this.

---

## 9. Not built yet (as of 2026-08-08)

**TB6612FNG motor driver** — identified from the package: 8+8 pads and a
24-pin SSOP (a DRV8833 would be 6+6 in a 16-pin package). Headers
unsoldered. Needed for `max_wheel_speed`, which
`crates/sim-core/src/spec.rs` insists be measured on the real battery
rather than taken from a datasheet.

```text
   POWER / MOTOR side               CONTROL side
   VM    motor supply ← battery     PWMA   speed, motor A
   VCC   logic supply ← Pico 3V3    AIN2   direction A
   GND                              AIN1   direction A
   AO1   ← RED   (M2)               STBY   ⚠️ must be driven HIGH
   AO2   ← WHITE (M1)               BIN1   direction B
   BO2   (second motor)             BIN2   direction B
   BO1   (second motor)             PWMB   speed, motor B
   GND                              GND
```

⚠️ **`STBY` low means nothing moves**, and it looks exactly like broken
firmware. ⚠️ **`VM` and `VCC` are different supplies** — tying them
together puts battery volts into the Pico.

**MPU-6050 (GY-521)** — headers unsoldered. `crates/mpu6050-driver` and
`firmware/pico-imu` already exist and are unit-tested against a mocked
bus, but have never met the real chip. Only `VCC`, `GND`, `SCL`, `SDA`
matter; `AD0` selects the I2C address (`0x68`, or `0x69` pulled high).

**Wheels, hubs, brackets** — not ordered. They block `wheel_radius` and
`track_width`, and therefore `REAL_BOT` as a whole.
