# Hardware-in-the-loop (HIL) protocol

*Written July 2026 as "Level 3" of the firmware stage and extended through August 2026 (the arm's `J` message, the status line, the notes channel); kept as the protocol record.*

The firmware drives a simulated robot and cannot tell the difference.

## Why this exists

Stage 0 built a robot brain on the laptop. Stage 2 built firmware on a
(emulated) chip. Level 1 made them share code. Level 3 makes them share a
**loop**: the chip runs the real-time controller, the laptop runs the
physics, and they exchange messages every control tick.

This is how automotive and aerospace teams test firmware before hardware
exists — and it is the same split the real robot will use in Stage 3:

```
  real-time control  |  everything else
  (microcontroller)  |  (big computer)
```

With a physical Pico, the emulator is swapped out and the host side does
not change a line.

## The three processes

```
┌───────────────────────────────────────────────────────────┐
│ crates/hil-host  (Rust, std)                              │
│   • spawns the emulator as a child process                 │
│   • runs sim-core PHYSICS: motor lag, wheels, slip,        │
│     collision, quantized encoders                          │
│   • logs truth + belief + walls to Rerun                   │
└───────────────────────────────────────────────────────────┘
        ▲ stdout (S lines)          stdin (M/P lines) ▼
┌───────────────────────────────────────────────────────────┐
│ tools/harness/hil-bridge.ts  (Node + rp2040js)            │
│   • boots the firmware UF2 on an emulated RP2040           │
│   • firmware UART TX ──▶ stdout   (protocol only)          │
│   • stdin ──▶ uart.feedByte()     (into the firmware)      │
│   • emulator's own logs go to stderr, never stdout         │
└───────────────────────────────────────────────────────────┘
        ▲ UART0                              UART0 ▼
┌───────────────────────────────────────────────────────────┐
│ firmware/pico-robot  (embassy, no_std)                     │
│   emulated Cortex-M0+, or a real RP2350 Cortex-M33 on USB   │
│   • the CONTROLLER, on the chip:                            │
│       sim-core Odometry        (belief from encoder ticks)  │
│       sim-core GotoController  (the steering law)           │
│       sim-core CommandWatchdog (stop if the planner dies)   │
│       sim-core StuckMonitor    (back out if it stops moving)│
│   • knows nothing about walls, physics, maps, or Rerun      │
│   • holds NO waypoint list: it has no allocator, so no map  │
│     and no A*. The host plans; this controls.               │
└───────────────────────────────────────────────────────────┘
```

## The wire protocol

Deliberately ASCII, newline-delimited — so the traffic can be read by eye. (A production link would use `postcard` binary
framing; that's Level 2's job, and swapping it in later changes only the
encode/decode functions.)

| Direction | Message | Meaning |
|---|---|---|
| host → chip | `I <x> <y> <th>` | **begin a session here.** Adopt this pose, drop all accumulated state |
| host → chip | `G <x> <y> <budget>` | steer at this point, at most this fast (m/s) |
| host → chip | `R <x> <y> <budget>` | the same, but **reset** the controller first |
| host → chip | `T <v> <w>` | apply this body twist verbatim — a host-side reflex |
| host → chip | `S <dl> <dr>` | encoder ticks since the previous `S` |
| chip → host | `P <x> <y> <th>` | believed pose (m, rad) — visualization, and the `I` acknowledgement |
| chip → host | `M <duty_l> <duty_r>` | motor command, ±`DUTY_FULL` (1000) = full reverse/forward |
| chip → host | `H <worst_us>` | a NEW worst-case control-loop compute time, µs |
| chip → host | `J <i> <ticks> <mrad> <duty> <phase>` | one **arm joint's** state for one tick |

`G` and `R` are one message with one bit of difference. The reset rides in
the **tag** rather than as a field for a reason — see the byte budget
below, where ` 1` cost two bytes it turned out we did not have.

### `J` — the arm on the same wire

Added 2026-08-12, when `firmware/pico-arm` needed telemetry. It is on
**this** wire rather than a format of its own, and that is the whole
point: one vocabulary, one parser, one set of round-trip tests, and
`--record`/`--replay` for free.
[`bench-two-joint.wire`](https://github.com/Trainnr-AI/trainnr/blob/main/recordings/bench-two-joint.wire)
(kept in trainnr's `recordings/`) is a real session of two motors — 414
reports, 88 `held` and 326 `holding` — and a step of the verify gate
replayed it (the recordings stayed in trainnr when rigrs was split out, so
rigrs's `tools/verify.sh` has no replay step).

⚠️ The alternative was tried and is written up in this crate's own source:
a status line that WAS a `write!` in the firmware grew **two independent
host parsers**, one of which silently dropped every line and **drew an
empty screen while the gate stayed green at 25/25**. The fix was a third
parser.

| field | meaning |
|---|---|
| `i` | joint index, matching `ArmSpec` order |
| `ticks` | raw encoder count, cumulative and signed |
| `mrad` | angle in **milliradians** from the calibrated zero |
| `duty` | what the position loop actually asked for, ±`DUTY_FULL` |
| `phase` | `homing` \| `homed` \| `holding` \| `held` \| `nozero` |

**Milliradians, not radians**, because the chip formats this and `f64`
formatting drags a float formatter into a binary that has none. 1 mrad is
~0.057°, far finer than a 4290-count encoder resolves.

**`ticks` rides beside `mrad` deliberately.** They are the same fact
through two conversions — the zero and the gear ratio — so when they
disagree, one of those two is wrong. That disagreement is exactly what a
homing bug looks like.

**`phase` is a word, not a number.** A `2` would need a table somewhere to
read, and that table is the kind of thing that lives in one place and rots
in another. Six extra bytes buys a line anybody can read without a decoder
ring — the same argument `arm::Verdict` makes one layer up.

⚠️ `held` and `nozero` are different failures and must not be collapsed:
**`held`** means the guard refused and the joints are keeping their last
target — the calibration is fine and the *commander* is not. **`nozero`**
means no zero was ever adopted, so the angle field is meaningless and the
outputs are off.

`H` is sent only when the record is beaten, so a healthy run costs a
handful of lines instead of one per tick. The host holds it against the
control period and **exits non-zero** if the chip missed its deadline.

### ⚠️ The byte budget is a protocol rule, not a guideline

The chip reads host → chip messages straight out of the RP2040/RP2350's
**32-byte UART RX FIFO**. The host writes `S` and then the next command
back to back, so those two share it. Go over and bytes are silently
dropped, the command line corrupts, the chip never sees a valid directive,
and the host waits forever for an `M` that cannot come.

**It presents as a hang.** Adding a four-byte ` <fresh>` field to `G` took
the burst from 31 to 33 bytes and cost hours: the chip was provably fast
in isolation, the host was provably fast in isolation, and together they
managed three ticks in seventy seconds.

Two tests in `hil-protocol` hold the line — one asserts the worst-case
`S`+`G` burst fits in 32 bytes, the other records that negative
coordinates would *not* fit, so the limit is met as a number rather than
as a mystery. `BufferedUart` would remove the constraint entirely and does
not work on our emulator (it storms rp2040js's interrupt controller).

### Lock-step timing

Once, at the start:

1. host sends `I` — where this session begins
2. chip adopts it, clears pose, controller and timing stats, replies `P`
3. host **waits** for that `P`

That wait is load-bearing twice over. Without the `I` the chip carries its
previous run's belief into this one (measured: 0/1 waypoints, 4.97 m
drift, 2036 wall bumps — a board left powered between runs). Without the
wait, `I` and the first `G` land in the FIFO together, 46 bytes into 32.

Then every control tick:

1. host sends `G`/`R`/`T` — the planner's decision
2. chip replies `P`, then `M`, and `H` if it has a new worst case
3. chip **blocks** until an `S` arrives
4. host reads `M`, advances physics by exactly `DT`, replies `S`

The chip stops reading the moment it has an `M`, so an `H` emitted just
after one is not seen until the next tick's read. A recording — which logs
in the order the *host* acts — shows it there.

Lock-step means the run is **deterministic** — same seed, identical
trajectory, every time — and neither side can outrun the other. It also
means simulated time is decoupled from wall-clock time: the loop runs as
fast as both sides can manage.

Real hardware is not lock-step (the physical world does not wait for the
firmware), so the plan for Stage 3 was free-running with timestamps. The
lesson that transfers is the message *shape*, not the synchronisation.

## What is honest here, and what is not

**Honest:** the firmware is the real binary, running on an emulated
Cortex-M0+ core, doing its own integer/float math, its own PID, its own
state machine. Bugs in it are real bugs. The physics comes from the same
`sim-core` that Stage 0 validated against closed-form truth.

**Not honest:** motor dynamics are a first-order lag model, not a real
motor — no back-EMF, no cogging, no stall current, no battery sag. PID
gains tuned here are a *starting point*, not a final answer. Wheel slip is
a random multiplier, not physics. This is why H4 still wants a real motor.

## Running it

```sh
tools/sim-hil.sh                                    # emulator + Rerun
cargo run -p hil-host -- --serial /dev/cu.usbmodem11 # a REAL Pico over USB

# record a session, then replay it with no hardware at all
cargo run -p hil-host -- --serial /dev/cu.usbmodem11 --record run.wire
cargo run -p hil-host -- --replay run.wire
```

Replay is a **regression test**, not a viewer: every line the host would
now send is compared against the recording, and a behaviour change prints
both sides and exits non-zero.
[`rp2350-utrap.wire`](https://github.com/Trainnr-AI/trainnr/blob/main/recordings/rp2350-utrap.wire)
is a committed session from real silicon, kept with the other recordings
in [trainnr's `recordings/`](https://github.com/Trainnr-AI/trainnr/tree/main/recordings) (see its README).

---

## The status line — `hil_protocol::Status`

The tagged messages above are byte-budgeted for a 32-byte UART FIFO.
`firmware/pico-odom` also emits a **human-readable** line 50 times a
second, meant to be read with `screen` open:

```text
pose x=-0.001 y=+0.003 th=-0.863  ticks L=-37793 R=38304  errL=235 errR=207  duty=0%
```

Every field, and why it is shaped that way:

| field | meaning |
|---|---|
| `x` `y` `th` | the chip's OWN dead reckoning, metres and radians |
| `L` `R` | encoder counts, signed, cumulative |
| `errL` `errR` | missed transitions, **per wheel** |
| `duty` | magnitude of the applied duty, 0–100 |
| `*** STALLED …` | appended when commanded motion produced none |

The errors are split per wheel because a decode error is a *missed*
transition and therefore an **undercount** — a combined figure cannot say
which wheel reads low, which is exactly the confound that made a
left/right speed comparison untrustworthy until they were separated.

### ⚠️ Why it lives in this crate

It was a `write!` in the firmware, and each host that needed it grew its
own parser. On 2026-08-09 the firmware split the error counter per wheel;
one parser kept looking for the old key, **dropped every line, and drew an
empty viewer while `tools/verify.sh` stayed green** — a parser that agrees
with itself compiles fine. Pinning that parser to a captured line fixed
the instance. Hours later a second host needed the same data and got a
second parser with its own copy of the same fixture: three
implementations of one format, two of them added in response to a bug
caused by having two.

So writer and parser are one type here, and
`a_status_line_survives_the_round_trip` puts them in the same assertion. A
renamed field is now a failing test rather than a blank screen.

**It is deliberately not a [`Message`] variant.** `Message` is terse
because the wire has a hard byte budget; this is verbose because a person
reads it. Different constraints, different types.

## The notes channel — prose and pictures on the same wire (2026-08-15)

Everything above is the 50 Hz machine vocabulary. Alongside it rides the
**notes channel**: lines beginning `# `, queued by any subsystem through
`diag::NOTES` (drop-if-full, so diagnostics can never block the thing
they diagnose) and drained into the same serial stream. `Status::parse`
rejects them by construction, so a host that only wants poses never sees
them.

Three formats ride the notes, and each lives in `hil-protocol` so its
producers and parsers cannot drift:

| Format | Wire shape | Module |
|---|---|---|
| camera announce | `# camera pid=0x76 … \| px 0..233 \| 4 fps \| com7=… format confirmed \| blob x+0.12 y-0.30 area 708` | prose; identity via `ov7670-driver`'s one `Display` |
| thumbnail | `# IMG 30 30 rgb565` then 30 hex rows | `thumbnail` — `write_header`/`parse_header`/`parse_row`, and **`Assembly`**, which owns the one definition of "complete" after two readers grew two |
| arm pulses | `# servo us 1500 1620 1100` — pan, tilt, grip, **commanded** (the servos measure nothing) | `arm_pulses` — `write_note`/`parse_note`, round-trip tested across the `# ` framing seam |

Two consumers: `rig_view` (draws all of it on one clock, `--record`
captures the raw lines) and `rig_replay` (headless, reduces a recording
to exact counts). The verify gate pinned two real recordings —
`chase-brightness.wire` and `track-and-stall.wire`, now in
[trainnr's `recordings/`](https://github.com/Trainnr-AI/trainnr/tree/main/recordings)
— so a change that broke any of these formats was a red build, not a
blank panel.

⚠️ Two lessons the formats carry from their bring-up: a note said once
is a note nobody hears (opening the port drains the queue — boot-time
facts must be re-announced), and a mid-stream attach may truncate its
first line (the fixtures are curated accordingly; `rig_replay` stays
strict).
