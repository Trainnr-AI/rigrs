# rigrs

Robot firmware in Rust. rigrs gives you the parts a robot's software is
made of: the control loop, the drivers, the safety logic and the link to
a host computer. The same code runs on a microcontroller, in a simulator
on your laptop and in your unit tests. None of it uses `unsafe`.

[![CI](https://github.com/Trainnr-AI/rigrs/actions/workflows/ci.yml/badge.svg)](https://github.com/Trainnr-AI/rigrs/actions/workflows/ci.yml)
[![License: MIT OR Apache-2.0](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue.svg)](#licence)

## Why write robot firmware in Rust

A bug in robot firmware is more than a crash. A stray pointer in a 50 Hz
control loop can leave a motor running into a wall, and a race between
an interrupt and the main loop can show up only after hours of running.
C and C++ leave these bugs to the programmer to avoid. Rust turns most
of them into compile errors.

- **Memory safety with no garbage collector.** Use-after-free, buffer
  overflows, null pointers and dangling references do not compile. There
  is no garbage collector either, so the control loop never pauses for
  one.
- **Data races are compile errors.** The compiler checks what may be
  shared between tasks and interrupts (`Send` and `Sync`). With
  [embassy](https://embassy.dev)'s async executor, the motor loop, a
  sensor reader and the radio run as tasks on one core, with no RTOS and
  no hand-written locks.
- **Abstractions that cost nothing at run time.** Traits and generics
  compile to the code you would have written by hand. A driver can be
  generic over any I2C bus and still fit on a small chip.
- **The type system can hold your safety rules.** A rule written as a
  type is checked on every build, not only when someone remembers. See
  [Safety rules the compiler checks](#safety-rules-the-compiler-checks).
- **Errors you cannot ignore.** A fallible call returns a `Result`, and
  the compiler warns you if you drop it. There is no `errno` to forget to
  check, and no exception thrown from somewhere deep.
- **One codebase, from the chip to the laptop.** A `no_std` crate needs
  no operating system, so the control code that runs on a Cortex-M also
  builds for your laptop. You test it at desktop speed with `cargo test`,
  before it ever reaches a board.
- **Portable drivers.** A driver written against the
  [`embedded-hal`](https://github.com/rust-embedded/embedded-hal) traits
  runs on any chip that has a HAL (RP2040 and RP2350, STM32, nRF, ESP32
  and more), and its tests run against a mocked bus.
- **One tool for everything.** Cargo builds, tests, documents and
  cross-compiles (`--target thumbv6m-none-eabi`), and its lock file pins
  every dependency. No makefiles, no vendor IDE.

## What rigrs gives you

| Crate | What you get |
|---|---|
| `sim-core` | The robot's maths, `no_std`: differential-drive kinematics, odometry, PID and go-to-point control, a command watchdog, stuck detection and a robot description with measured parameters. With `std`: an occupancy grid, an A* planner and a simulated depth camera. |
| `arm` | Arm control: joint traits split by what the hardware can do, a guard that holds the arm when commands go quiet or a joint overheats, homing and motion plans. |
| `n20-joint`, `quad-encoder` | A DC gearmotor with an encoder that behaves like a servo joint, and quadrature decoding. |
| `mpu6050-driver`, `pca9685-driver`, `ov7670-driver` | Drivers for an IMU, a 16-channel servo PWM board and a camera, on `embedded-hal` 1.0, each tested against a mocked bus. |
| `blob` | Finds a coloured object in a camera frame, on the chip, with no heap. |
| `hil-protocol` | The messages between a host and a robot, defined once and compiled into both ends. It reads lines into a fixed-size buffer, with no heap. |
| `hil-host` | Hardware in the loop: the robot's brain runs on a real (or emulated) chip while the host simulates its body. Any session can be recorded and replayed. |
| `sim-run` | A simulator that runs the same maths as the firmware. |
| `vision`, `teleop-web`, `belief-viz` | Host tools: a camera, an object detector and a chase loop; driving the robot from a phone; and [Rerun](https://rerun.io) views of where the robot thinks it is. |
| `firmware/` | Reference firmware on embassy, from `pico-blink` up to `pico-robot`. In `pico-robot` the chip runs odometry, the steering controller and the watchdog every 20 ms, while the host plans the route and simulates the physics. |

## Safety rules the compiler checks

- **No `unsafe` code.** Every host crate inherits `unsafe_code = "forbid"`
  from the workspace, and every firmware crate declares
  `#![forbid(unsafe_code)]`. Unlike `deny`, `forbid` cannot be switched
  off locally with `#[allow]`. `tools/check-unsafe-gates.py` checks that
  none of those lines has been deleted.
- **A stale safety proof does not compile.** `Torque::release` switches
  a joint's motor off, so it asks for a `Parked` value as proof that the
  arm is resting. Only the arm's guard can make one, and it borrows from
  the guard, so a proof kept until after the guard has moved on is
  rejected by the borrow checker. A `compile_fail` test proves this.
- **Feedback is a capability, not a flag.** A cheap hobby servo can be
  told an angle but cannot report one. `Joint` and `SensingJoint` are
  separate traits, so closing a loop or recording demonstrations will
  not compile against hardware that cannot say where it is.
- **Every failsafe is named.** The arm's guard returns a `Verdict`:
  `Move`, or one of several reasons to hold (never commanded, commands
  stale, clocks disagree, too hot). The match must cover each one.
- **Hardware rules become types.** The Wi-Fi chip's firmware is loaded by
  DMA and must be 4-byte aligned, so it lives in an `Aligned` type
  rather than relying on a comment.
- **Panics are failures.** On a chip, a panic stops the robot with its
  motors in whatever state they were in. In the libraries that run in the
  control loop, clippy refuses `unwrap` and flags `expect`.

The fine print: the dependencies underneath (embassy, `cortex-m-rt`, the
HALs) do contain `unsafe` code, because something has to write to the
hardware registers. The rules above cover the code in this repository.
Nothing here is safety-certified, so treat it as a bench project, not a
product.

## Writing firmware for your robot

1. **Describe the robot.** Put its geometry and measured limits in a
   `RobotSpec` (a wheeled base) or an `ArmSpec` (an arm).
2. **Connect the hardware.** Implement a small trait for each part:
   `MotorPort` for a motor and its encoder, `Joint`, `SensingJoint` and
   `Torque` for an arm joint. For a sensor, use a driver here or any
   `embedded-hal` driver.
3. **Run the loop on your laptop first.** The controllers, odometry and
   guards are plain Rust. Unit-test them, and run them in the simulator.
4. **Run it in the loop.** Put the same control code on the chip, and let
   `hil-host` simulate the robot's body, on an emulator or on a real
   board.
5. **Flash it.** Build for the chip's target and copy the image across.
   The `firmware/` crates show the whole path.

## Hardware it runs on today

The reference firmware targets the Raspberry Pi RP2040 (Pico) and RP2350
(Pico 2, Pico 2 W) through embassy, and it runs on the
[rp2040js](https://github.com/wokwi/rp2040js) emulator with no board
attached. The robots behind it are a two-wheeled base with encoders, a
camera and a Wi-Fi link, an arm on hobby servos, and arm joints built
from gearmotors. The
`no_std` crates and the `embedded-hal` drivers are not tied to these
chips. Firmware for another chip needs that chip's HAL and its own
`firmware/` crate.

## Quick start

```sh
git clone https://github.com/Trainnr-AI/rigrs
cd rigrs
cargo test --workspace      # the host crates; no hardware needed
cargo run -p sim-run        # the simulator, drawn in a Rerun viewer
tools/verify.sh --fast      # every gate except the emulator run
```

`rust-toolchain.toml` pins Rust 1.97.1. The first time you run cargo,
rustup installs that version and both ARM targets. The viewers need the
Rerun 0.35 viewer on your `PATH`: `cargo install rerun-cli --locked
--version '~0.35'`.

Building firmware:

```sh
tools/build-pico2.sh pico-blink                  # RP2350; needs picotool for the .uf2
(cd firmware/pico-blink && cargo build --release) # RP2040
tools/setup-emulator.sh && tools/sim-blink.sh    # run it on the emulator (needs Node.js)
```

## Status

rigrs is early. It grew out of one bench, and its APIs will change as it
grows into firmware for more robots and more chips. Issues and pull
requests are welcome.

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
