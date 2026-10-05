# Contributing to rigrs

Thank you for helping. Issues and pull requests are welcome, from a typo
to a new driver.

## Before you start

- Open an issue first for anything larger than a fix, so we can agree on
  the shape before you spend the time.
- Install the hooks once per clone: `tools/setup-hooks.sh`. They run
  formatting, clippy and the `unsafe` gate on every commit.
- Run `tools/verify.sh` before you open a pull request. `--fast` skips the
  emulator run; CI runs the rest.

## The rules the code keeps

- **No `unsafe`.** Every crate forbids it, and `forbid` cannot be lifted
  locally. If you believe a change genuinely needs it, argue for it in
  the issue first; it means changing the gate itself, in its own commit.
- **No panics in the loop.** Libraries that run in a control loop refuse
  `unwrap` and flag `expect`. Return an error, and decide in the
  caller what the robot does about it. Substituting a default for a
  failed measurement is worse than stopping.
- **One copy of each fact.** Robot maths lives in `sim-core` and is used
  by both the simulator and the firmware; the wire format lives in
  `hil-protocol` and is used by both ends. Extend those rather than
  copying them.
- **Tests on the host.** A driver gets unit tests against a mocked bus,
  so it is proved on the laptop before it meets a board.
- **Comments say why.** The code says what. Record a measurement with
  its date and the hardware it came from.

## Sign-off

Every commit carries a `Signed-off-by:` line (`git commit -s`), certifying
the [Developer Certificate of Origin](https://developercertificate.org).

## Licence

Unless you explicitly state otherwise, any contribution you intentionally
submit for inclusion in this work, as defined in the Apache-2.0 license,
is dual-licensed under MIT OR Apache-2.0, without any additional terms or
conditions.
