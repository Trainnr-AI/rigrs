# Changelog

Notable changes to rigrs. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org).

## [Unreleased]

### Added

- The first public version: the shared `no_std` robot maths
  (`sim-core`) and arm control (`arm`), drivers on `embedded-hal` 1.0
  (MPU6050, quadrature encoder, PCA9685, OV7670, N20 joint), the
  hardware-in-the-loop protocol and host, the simulator, vision, phone
  teleoperation, reference firmware for the RP2040 and RP2350 on embassy
  (`pico-blink` through `pico-robot`) and the design notes in `docs/`.
- Licensed under MIT OR Apache-2.0.

### Known issues

- The emulator HIL run (`tools/verify.sh` without `--fast`) stops at
  about 14.6 s simulated on the RP2040 build; the same mission completes
  on real RP2350 silicon. See docs/testing.md.
