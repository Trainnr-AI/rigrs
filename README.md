# rigrs

Memory-safe robot firmware in Rust. A robot's brain runs on a Raspberry Pi
Pico, the same source runs in a simulator on your laptop, and none of the
code in this repository uses `unsafe`.

[![CI](https://github.com/Trainnr-AI/rigrs/actions/workflows/ci.yml/badge.svg)](https://github.com/Trainnr-AI/rigrs/actions/workflows/ci.yml)
[![License: MIT OR Apache-2.0](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue.svg)](#licence)

When robot firmware crashes, the robot crashes too. A dangling pointer in
a control loop leaves a motor running on whatever duty it last had. rigrs
gets that whole class of bug refused by the compiler: every crate forbids
`unsafe` code, and the bugs that are left get caught by tests on the
laptop, before the firmware reaches the board.

It began as one bench rig, a two-wheeled robot and a one-joint arm. The
goal is to grow it into a general firmware stack for robots in Rust.

## What is in it

- **Firmware for the RP2040 and RP2350** (Pico, Pico 2, Pico 2 W) on
  [embassy](https://embassy.dev). It goes from `pico-blink` up to
  `pico-robot`, a complete autonomy stack on the chip: odometry,
  an occupancy map, an A* planner and a controller.
- **One copy of the robot's maths** (`sim-core`). It is `no_std` and
  compiles for both the chip and the laptop from the same source, so the
  simulator and the firmware cannot drift apart.
- **A hardware-in-the-loop protocol** (`hil-protocol`). Every 20 ms the
  chip decides what to do and the host simulates the physics. The
  messages go over UART or USB, telemetry can also go over Wi-Fi, and any
  session can be recorded and replayed.
- **Drivers for the sensors and actuators**, each unit-tested against a
  mocked bus:
  - an MPU6050 IMU;
  - quadrature wheel encoders;
  - PCA9685 servo PWM;
  - an OV7670 camera;
  - an N20 gearmotor joint.
- **Tools that run on the host**:
  - a simulator;
  - a host for hardware-in-the-loop runs, against an emulator or a real
    board;
  - vision: camera capture, a detector and blob tracking;
  - phone teleoperation;
  - [Rerun](https://rerun.io) viewers for all of the above.
- **Emulated silicon.** Firmware runs on
  [rp2040js](https://github.com/wokwi/rp2040js) with no board attached.

## The safety rules

- **No `unsafe`, enforced by the compiler.** Every host crate inherits
  `unsafe_code = "forbid"` from the workspace, and every firmware crate
  root declares `#![forbid(unsafe_code)]`. Unlike `deny`, `forbid` cannot
  be switched off with a local `#[allow]`. `tools/check-unsafe-gates.py`
  makes sure none of those declarations has been deleted.
- **Panics are counted as failures.** On a chip, a panic stops the robot
  with its motors in whatever state they were in. In the libraries that
  run in the control loop, clippy refuses `unwrap` and flags `expect`.
- **Failsafes are decided in advance.** Each firmware chooses what to do
  when its commander goes quiet: the drive base stops, the arm joint
  holds its position. A watchdog makes sure that choice is carried out.
- **The fine print.** The dependencies (embassy, `cortex-m-rt`, the HALs)
  do contain `unsafe` code, because something has to write to the
  hardware registers. The rules above cover the code in this repository.
  Nothing here is safety-certified. Treat it as a bench project, not a
  product.

## Quick start

```sh
git clone https://github.com/Trainnr-AI/rigrs
cd rigrs
cargo test --workspace      # the host crates; no hardware needed
cargo run -p sim-run        # the simulator, drawn in a Rerun viewer
tools/verify.sh --fast      # every gate except the emulator run
```

`rust-toolchain.toml` pins Rust 1.97.1. rustup installs that version
and both ARM targets the first time you run cargo. The viewers need the
Rerun 0.35 viewer on your `PATH`: `cargo install rerun-cli --locked
--version '~0.35'`.

Building firmware:

```sh
tools/build-pico2.sh pico-blink                  # Pico 2 (RP2350); needs picotool for the .uf2
(cd firmware/pico-blink && cargo build --release) # Pico (RP2040)
tools/setup-emulator.sh && tools/sim-blink.sh    # run it on the emulator (needs Node.js)
```

## Layout

| Path | What it holds |
|---|---|
| `firmware/` | the firmware workspace: `pico-*` firmwares, `support`, `build-support` |
| `crates/sim-core` | the shared `no_std` robot maths, plus the simulator core |
| `crates/sim-run` | the simulator's mission and its viewer |
| `crates/hil-protocol` | the wire protocol between the host and the chip, one definition for both ends |
| `crates/hil-host` | the host side of hardware-in-the-loop: emulator, serial, replay |
| `crates/arm`, `crates/n20-joint` | joint-space arm control; a gearmotor joint |
| `crates/blob` | finds a coloured object in a frame, on the chip |
| `crates/*-driver`, `crates/quad-encoder` | sensor and actuator drivers |
| `crates/vision` | perception on the host: camera, detection, chase |
| `crates/teleop-web` | drive the robot from a phone |
| `crates/belief-viz` | draws where the robot thinks it is |
| `tools/` | build, emulator and verification scripts |
| `docs/` | the design notes |

## Docs

- [Roadmap](docs/roadmap.md)
- [Simulator design](docs/sim-design.md)
- [Hardware simulation](docs/hardware-sim.md)
- [HIL protocol](docs/hil-protocol.md)
- [Perception](docs/perception.md)
- [Choosing a vision model](docs/vision-model-choice.md)
- [Detector landscape](docs/detector-landscape.md)
- [Wi-Fi on the chip](docs/wifi.md)
- [Testing and coverage](docs/testing.md)
- [Architecture review](docs/architecture-review.md)
- [The bench rig](docs/bench-rig.md)
- [Parts list](docs/parts.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues as described
in [SECURITY.md](SECURITY.md).

## Licence

rigrs is licensed under either of

- the Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE)), or
- the MIT license ([LICENSE-MIT](LICENSE-MIT)),

at your option. [NOTICE](NOTICE) lists the third-party files in this
repository. One of them is the Wi-Fi radio's board settings, which are
under their own licence.

Unless you explicitly state otherwise, any contribution you intentionally
submit for inclusion in this work, as defined in the Apache-2.0 license,
is dual-licensed as above, without any additional terms or conditions.
