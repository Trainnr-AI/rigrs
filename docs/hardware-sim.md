# Hardware simulation for Stage 2 (state of the tools, July 2026)

*Researched 2026-07-29 for the firmware stage (Stage 2); kept as the research record.*

Research date: 2026-07-29. Question: can we learn microcontroller hardware
sim-first, like we learned the vehicle in Stage 0?

> **Answer: yes — Wokwi (simulated RP2040 Pico) + local embassy toolchain,
> with Falstad CircuitJS for electrical intuition and embedded-hal-mock for
> host tests. Caveat: NO simulator runs the RP2350/Pico 2 as of July 2026 —
> we learn on the simulated Pico 1 and port (a Cargo feature swap) to the
> physical Pico 2 W. Explicitly a sound path.**

## Wokwi — the embedded "Stage 0"

Browser (free) + VS Code extension/CLI simulator, instruction-level, with a
visual breadboard: wire a virtual MCU to LEDs, buttons, sensors, displays;
runs **your locally-compiled Rust ELF**.

- **Boards:** RP2040/Pico 1 ✔ (open-source rp2040js emulator; single-core
  only, PIO simulated, USB-CDC only). **RP2350/Pico 2 ✘** (issue open since
  Jan 2025, no roadmap; community fork covers only the RISC-V core, not the
  Cortex-M33 embassy targets). **Pico W WiFi ✘** (CYW43 unsimulated).
  **ESP32 family ✔✔ — deepest support** (S3/C3/C6/P4-beta, incl. simulated
  WiFi with internet gateway) — good news for our later ESP32 step.
- **Rust workflow (2026) — CORRECTED after field-testing 2026-07-29:**
  online Rust compilation was removed, and **the browser Pico simulator has
  NO custom-firmware upload at all** (its F1 menu only *exports* UF2 to
  physical boards — verified against docs.wokwi.com/parts/wokwi-pi-pico
  after an evening of fruitless clicking). The one supported Rust path is
  the **Wokwi for VS Code extension**: build the ELF locally, `wokwi.toml`
  points at it, extension simulates (F1 → "Wokwi: Start Simulator").
  License requested in-extension against a free Wokwi account.
- **Pricing:** browser free but Rust-irrelevant (see above). VS Code
  extension license: request via free account; paid tiers (Hobby+ ~$8/mo,
  Pro $20) exist — actual gating discovered on first request.
- **Robotics-relevant virtual parts:** MPU6050 IMU ✔ (settable values),
  HC-SR04 ultrasonic ✔ (distance slider), micro servo ✔, KY-040 rotary
  encoder ✔, WS2812 ✔, A4988+stepper ✔. **DC motor + H-bridge + quadrature
  encoder ✘ native** — community custom chip (drf5n L298N) or write our own
  Wokwi Custom Chip (C or Rust→WASM); but motor *physics* (inertia, load)
  would be ours to fake — limited PID-tuning transfer.
- **Honest limits:** digital logic + protocols only. No voltage/current/
  brown-out/stall — not SPICE. Timing approximate. No dual-core, no BLE.

## THE CHOSEN PATH (settled 2026-07-29, after the deep search): local rp2040js

The Wokwi VS Code detour ended when a deep GitHub sweep found the better
answer: **run the emulator core itself, locally.** `wokwi/rp2040js` is the
MIT-licensed engine inside Wokwi's Pico sim — Node ≥18, bundles the real
RP2040 bootrom, loads UF2s, exposes `gpio[n].addListener(...)`.

- Cloned at `tools/rp2040js` by `tools/setup-emulator.sh` (upstream code, so
  never committed); the harness `tools/harness/watch-blink.ts`, copied into
  the clone's `demo/`, boots our UF2 and logs every LED-pin transition with simulated timestamps + measured
  periods. One-command loop: **`tools/sim-blink.sh`** (build → UF2 → run).
- **Verified working:** blink periods measured at exactly 500.0 ms and
  800.0 ms — embassy tasks, timer driver, GPIO all correct in emulation.
- **Two real bugs found on the way (both fixed):**
  1. *Our firmware:* embassy `#[task]` pools default to size 1 — spawning
     `blink` twice made the second spawn's `unwrap()` panic before any LED
     toggled. Fix: `#[embassy_executor::task(pool_size = 2)]`. The emulator
     caught a bug that would have shipped to real hardware.
  2. *The emulator:* rp2040js's SEV instruction only logged — never set
     `eventRegistered` — so embassy's WFE/SEV executor wake protocol
     deadlocked (C/MicroPython never hit it; they wake via interrupts).
     One-line patch to the Cortex-M0 core module, kept as
     `tools/patches/rp2040js-sev-fix.patch` and applied to the git-ignored
     rp2040js clone by `tools/setup-emulator.sh`; **worth upstreaming as a
     PR to wokwi/rp2040js**.
- Known emulator gaps to respect: PWM incomplete (issue #84), flash writes
  stubbed, USB partial, single-core, no RP2350. H1's PWM milestone may need
  adaptation (servo-style timing via GPIO toggling, or move PWM learning to
  the real board).

Other findings from the sweep (for later):
- **Wokwi browser F1 → "Load HEX File" IS free and real — but only for
  ESP32-family** (accepts .bin/.elf/.uf2). Excellent for our later ESP32
  step; the Pico browser sim has no such path.
- **Wokwi VS Code license nuance:** free for open-source projects +
  renewable 30-day personal licenses (account-gated) — friction, not
  strictly paid.
- **Velxio** (velxio.dev, 2026): new AGPL open-source browser sim (Pico via
  rp2040js, ESP32 via QEMU, SPICE co-sim!) — no custom-UF2 upload yet;
  watch it.
- **Renode + nRF52840** remains the strongest free option for *simulated
  I2C sensors* (its flagship visual board is the IMU-bearing Nano 33 BLE
  Sense) — a candidate for the H2 milestone if Wokwi-free I2C sim is
  wanted; nRF52840 dongle ~$10 keeps sim and silicon matched.
- Dead ends confirmed: QEMU (no RP2040 machine anywhere), picoem (timers
  stubbed), probe-rs (no sim targets).

## The supporting cast

- **Falstad CircuitJS** (falstad.com/circuit, free, browser): animated
  current-flow circuit sim — THE tool for building volts/amps intuition:
  LED + resistor sizing, PWM into an RC filter, MOSFET switching, H-bridge
  topology, flyback diodes. Doesn't run code; use alongside Wokwi.
- **embedded-hal-mock 0.11 (`eh1` feature):** expectation-based host mocks
  for I2C/SPI/pins/PWM — unit-test driver logic with plain `cargo test`,
  our tests-first culture intact. Best practice: logic/driver crates
  (no_std, host-testable) + thin embassy binary.
- **embassy on the host:** `embassy-executor` has an `arch-std` feature —
  async task logic, channels, timers run on the Mac (no HALs though).
- **embedded-test 0.7.1 (Mar 2026):** on-target `cargo test` via probe-rs —
  becomes relevant once a physical board is on the bench.
- **Renode 1.16.1** (Feb 2026): serious multi-node emulator (nRF52840 BLE
  is first-class) but no official RP2040/RP2350, no visual parts —
  learning-unfriendly for our path; revisit for CI later. **QEMU 11:** CPU-
  level only for MCUs; skip (Espressif's QEMU fork is the ESP32 CI option).
- **AI-era adjacents:** Cirkit Designer (AI circuit design + sim, no Rust),
  Flux.ai (AI PCB design — relevant when we design robot boards, much
  later).

## The RP2040 → RP2350 port (why sim-first still works)

Same `embassy-rp` crate ("HAL for RP2040 or RP235x", 0.10.0):

| | Sim (Wokwi) | Physical board |
|---|---|---|
| Chip | RP2040 (Pico 1) | RP2350 (Pico 2 W) |
| Cargo feature | `rp2040` | `rp235xa` |
| Target triple | `thumbv6m-none-eabi` | `thumbv8m.main-none-eabihf` |
| Boot | boot2 blob section | IMAGE_DEF `.start_block` |
| API for GPIO/PWM/I2C/SPI/UART/PIO | **identical** | **identical** |

Upstream embassy keeps parallel `examples/rp` and `examples/rp23` dirs —
diffs for peripheral code are tiny.

## Stage 2 milestone ladder (revised for sim-first)

| Milestone | Where | Parts |
|---|---|---|
| H0 blink + async tasks | Wokwi free | onboard LED, external LED + resistor |
| H1 button + PWM brightness | Wokwi | button, LED; Falstad: PWM + RC intuition |
| H2 I2C IMU | Wokwi | MPU6050 (native part); driver crate host-tested with embedded-hal-mock |
| H3 encoder logic | Wokwi | KY-040 quadrature decoding; servo via PWM |
| H4 motor + PID | **physical Pico 2 W** | real DC motor + TB6612 + encoder — physics can't be faked |
| H5 the wire | physical | postcard-rpc over USB to the Mac |

**When hardware becomes unavoidable:** real motor dynamics (H4), anything
WiFi/BLE, real ADC noise, current/power — and on-target testing
(Debug Probe + embedded-test). Ordering early means zero waiting.

Key sources: [Wokwi supported hardware](https://docs.wokwi.com/getting-started/supported-hardware),
[Wokwi pricing](https://wokwi.com/pricing),
[rp2040js RP2350 issue](https://github.com/wokwi/rp2040js/issues/142),
[embassy-rp](https://crates.io/crates/embassy-rp),
[embedded-hal-mock](https://crates.io/crates/embedded-hal-mock),
[embedded-test](https://crates.io/crates/embedded-test),
[Renode](https://github.com/renode/renode/releases),
[Falstad CircuitJS](https://www.falstad.com/circuit/),
[impl Rust for RP2350](https://pico.implrust.com/).
