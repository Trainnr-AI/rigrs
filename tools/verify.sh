#!/usr/bin/env bash
# Prove the whole system, end to end, in one command.
#
#   tools/verify.sh                  everything that needs no hardware
#   tools/verify.sh --fast           everything but the emulator run
#   tools/verify.sh --serial <port>  ALSO run against a real Pico
#
# Ordered cheapest-first, so a broken build fails in seconds rather than
# after the emulator run.
#
# ⚠️ `--fast` is a real gap, not just a slower/faster choice: the emulator
# is the ONLY step where firmware EXECUTES rather than merely compiling.
# Run the whole thing before a release.
set -uo pipefail
cd "$(dirname "$0")/.."
source "$HOME/.cargo/env" 2>/dev/null || true

SERIAL=""
FAST=""
[ "${1:-}" = "--serial" ] && SERIAL="${2:-}"
[ "${1:-}" = "--fast" ] && FAST=1

pass=0; fail=0
step() {                      # step "name" "command"
  printf "%-46s" "$1"
  if out=$(eval "$2" 2>&1); then
    echo "ok"; pass=$((pass+1))
  else
    echo "FAIL"; echo "$out" | tail -15; fail=$((fail+1))
  fi
}

PY="${PYTHON:-python3}"  # override where python3 is not the name
echo "=== rigrs end-to-end verification ==="
step "formatting"            "cargo fmt --all --check"
step "clippy (all targets)"  "! cargo clippy -q --workspace --all-targets 2>&1 | grep -qE '^error'"
step "tests"                 "cargo test -q --workspace"
step "unsafe forbidden everywhere" "\"$PY\" tools/check-unsafe-gates.py"
step "formatting (firmware)" "(cd firmware && cargo fmt --all --check)"

# The crates that must compile for the chip as well as the host.
# `cargo test` proves neither: it builds the std shape only, so an
# accidental `Vec`, `String` or `std::` in one would pass every test here
# and fail the moment the firmware tried to link it.
for target in thumbv6m-none-eabi thumbv8m.main-none-eabihf; do
  for c in sim-core arm n20-joint blob; do
    step "$c is still no_std ($target)" \
         "cargo build -q -p $c --no-default-features --target $target"
  done
done

# Firmware. pico-led and pico-selftest are RP2350-only by design.
for c in pico-arm pico-blink pico-button pico-encoder pico-imu pico-odom pico-robot; do
  step "firmware $c (RP2040)" "(cd firmware/$c && cargo build -q --release --target thumbv6m-none-eabi)"
done
for c in $(ls firmware | grep pico-); do
  step "firmware $c (RP2350)" "SKIP_UF2=1 tools/build-pico2.sh $c"
done
# The loop above builds each crate's DEFAULT transport, which for
# pico-encoder and pico-odom is the UART one the emulator speaks. Their USB
# builds are what run on a real board, and nothing else here compiles them.
step "firmware pico-encoder (RP2350, USB)" "SKIP_UF2=1 tools/build-pico2.sh pico-encoder usb"
step "firmware pico-odom (RP2350, USB)" "SKIP_UF2=1 tools/build-pico2.sh pico-odom usb"
# The arm joint's only telemetry path. Nothing else compiles its `link`
# module or the `J` messages it emits.
step "firmware pico-arm (RP2350, USB)" "SKIP_UF2=1 tools/build-pico2.sh pico-arm usb"
# `teleop` replaces the calibration sweep with a host command channel, so
# it compiles a different half of the file — the watchdog, the signed duty
# path and the H-bridge failsafe.
step "firmware pico-odom (RP2350, teleop)" "SKIP_UF2=1 tools/build-pico2.sh pico-odom teleop"
# The radio transport, and the tee that sends every line down BOTH wires.
# Built WITHOUT credentials on purpose: `WIFI_SSID` unset is a supported
# state (the firmware blinks a distinct pattern and never tries to join),
# so this step runs on a machine that has none.
step "firmware pico-odom (RP2350, wifi)" "SKIP_UF2=1 tools/build-pico2.sh pico-odom wifi"
step "firmware pico-odom (RP2350, usb+wifi)" "SKIP_UF2=1 tools/build-pico2.sh pico-odom usb,wifi"

# The teleop page is compiled into the binary with `include_str!`, so a
# missing file is a build error. This checks the thing that file is FOR:
# that the joystick handler keeps the `touch-action` rule iOS needs,
# without which the page silently does nothing on a phone.
step "teleop page still has its touch handlers" \
     "grep -q 'touch-action: none' crates/teleop-web/src/index.html && \
      grep -q touchcancel crates/teleop-web/src/index.html"

# Slowest, and needs npx plus the emulator checkout (tools/setup-emulator.sh).
# RERUN=0: the gate judges parsed counts, not pixels, so no viewer spawns.
#
# ⚠️ Known red since 2026-08-12: under rp2040js the RP2040 build stops
# answering at ~14.6 s simulated, at the same tick on every run, and the
# host waits for a motor command that never comes (docs/testing.md,
# "Known issue"). The same mission completes on real RP2350 silicon. The
# time limit turns that wait into a red step rather than a hung script.
if [ -z "$FAST" ]; then
  step "HIL on the emulator (RP2040)" \
       "tools/build-robot.sh && RERUN=0 timeout ${HIL_TIMEOUT:-900} cargo run -q -p hil-host | grep 'waypoints:   1/1' >/dev/null"
fi

if [ -n "$SERIAL" ]; then
  step "HIL on real silicon ($SERIAL)" \
       "RERUN=0 cargo run -q -p hil-host -- --serial $SERIAL | grep 'waypoints:   1/1' >/dev/null"
  # The failures a SUCCESSFUL mission never exercises: a corrupt command,
  # and a host that dies and reconnects.
  step "chip conformance (corrupt cmd, reconnect)" \
       "cargo run -q -p hil-host --example chip_probe -- $SERIAL"
else
  echo "HIL on real silicon                           skipped (pass --serial <port>)"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
