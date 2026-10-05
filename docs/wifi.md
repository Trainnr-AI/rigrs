# WiFi on the microcontroller — what it can do, and where it belongs

*Researched 2026-08-10, with the radio measured on 2026-08-11; kept as the research record.*

Researched 2026-08-10 along three lines in parallel, against primary
sources only: the embassy repo and crates.io/docs.rs, Raspberry Pi and
Infineon datasheets, OASIS/IETF specs, and vendor architecture
documentation. **Web search was unavailable throughout**, so everything
below came from direct fetches of known URLs. Broad discovery
was impossible — treat "no example exists" claims as "none found by
targeted search of the obvious places", which is strong but not proof.

A fourth line of research — measured WiFi latency/jitter and the
functional-safety treatment of wireless links — **could not be completed**
and is not represented here. It is the open question, recorded in §7.

---

## The recommendation, first

**Tether the RP2350 to a Linux compute node that owns WiFi, TLS, the
broker connection, recording and OTA.** Keep the radio on the chip as an
optional bench side-channel, not the production path.

**This is not a bandwidth decision.** All three fields agree the 50 Hz
telemetry stream is a rounding error on any link. It is a decision about
security surface, OTA safety, debuggability and jitter.

### ✅ Now measured, not argued (2026-08-11)

Built and run: `firmware/pico-odom --features usb,wifi` sends every status
line down **both** wires, carrying the same `Status::seq`, so the
difference measured is the transport's and not the robot's.

Board #2 joining a domestic 2.4 GHz AP, stationary, two runs:

| run | usb delivered | usb lost | wifi delivered | wifi lost | wifi loss |
|-----|---------------|----------|----------------|-----------|-----------|
| 60 s | 2992 | 0 | 2876 | 116 | **3.88%** |
| 45 s | 2243 | 0 | 2184 |  62 | **2.76%** |

Lag of the radio behind the cable, for reports **both** delivered:

```text
   60 s run    median 66.0 ms   p95 119.2   p99 128.1   worst 134.4
   45 s run    median 69.2 ms   p95 119.7   p99 127.8   worst 131.6
```

**The verdict the numbers support:** fine for watching a robot, logging a
run, or curating training data. Not fine for steering one. 66 ms median is
over three control periods at 50 Hz, and `CommandWatchdog`'s 200 ms
timeout has only ~70 ms of headroom above the p99 — so a burst of loss
becomes a robot that halts mid-manoeuvre.

⚠️ Measured with **no motors turning and the robot stationary**. A moving
robot with brushed motors drawing current on the same 2.4 GHz band is
likely worse, not better. The power-save default was already disabled
(`CYW43_NONE_PM`); leaving it on would add up to 200 ms more.

The reproducibility is the load-bearing part: two runs agreeing to within
3 ms of median is a measurement, one run is an anecdote.

---

## 1. The three findings that decide it

### 1.1 ⚠️ `cyw43` cannot join WPA2-Enterprise

`JoinAuth` is `Open | Wpa | Wpa2 | Wpa3 | Wpa2Wpa3`. There is no EAP,
no 802.1X, no identity or credential plumbing
(`cyw43/src/control.rs`, main, fetched 2026-08-10).

Corporate and campus networks are frequently Enterprise-only. **This is
not something firmware work can fix.** For a project whose premise is
access to a commercial site, it is the first question to ask their
network administrator, and the answer can end the discussion before any
code is written.

A Linux supplicant does EAP without difficulty.

### 1.2 ⚠️ Secure boot is bypassable on the silicon we have

The RP2350 hacking challenge (closed 2024-12-31, five successful attacks)
produced numbered datasheet errata:

| Erratum | Attack | Affects | Fixed in |
|---|---|---|---|
| E16 | OTP guard-word read corruption | A2 | A3 |
| E20 | Glitch reboot API → unsigned code | A2 | A3 bootrom |
| E21 | Glitch → OTP extraction in BOOTSEL | A2 | A3 bootrom |
| **E24** | **Swap QSPI + timed glitch → arbitrary unsigned code on a secured chip** | **A2, A3** | **A4 bootrom. Workaround: None** |
| E17 | Guarded-read fault, bricking risk | A2, A3, A4 | **unfixed** |

**Our board is A2** — established when the E9 input erratum was confirmed
on the bench and `Pull::Up` measured as the fix (see
[bench-rig.md](bench-rig.md)). So signed boot on the hardware in
front of us is defeatable by someone with physical access.

Two further constraints: signed boot uses **secp256k1, not P-256**, so a
standard PKI cannot be reused; and **the RISC-V cores get no secure boot
at all** — Cortex-M33 only if this matters.

⚠️ **Which stepping ships today was NOT established.** Verify with the
distributor before betting on signed boot.

### 1.3 ⚠️ `embedded-tls` fails open

```rust
if let Ok(verifier) = crypto_provider.verifier() {
    verifier.verify_certificate(transcript, certificate)?;
} else {
    debug!("Certificate verification skipped due to no verifier!");
}
```

The default `verifier()` returns `Err(TlsError::Unimplemented)`. A
`CryptoProvider` that does not override it gets **zero server-certificate
validation, announced only by a debug log** — no compile error, no
type-level nudge. `UnsecureProvider` is re-exported from the crate root
and appears in the crate's own doc example.

Compare `embassy-boot`, whose signature check **fails closed**: with no
signature feature enabled, verification always errors. Same ecosystem,
opposite defaults, and the difference is the whole security posture.

---

## 2. What works, with versions

All fetched 2026-08-10 from crates.io/docs.rs and the embassy repo.

| Crate | Version | Published | Note |
|---|---|---|---|
| `cyw43` | 0.7.0 | 2026-03-20 | Pico 2 W listed as supported |
| `cyw43-pio` | 0.10.0 | 2026-03-20 | ⚠️ see below |
| `embassy-net` | 0.9.1 | 2026-04-16 | TCP, UDP, DHCPv4, DNS, ICMP in-tree |
| `embassy-boot` | 0.7.0 | 2026-03-20 | Ed25519 signing, fails closed |
| `embassy-boot-rp` | 0.10.0 | 2026-03-20 | description still says "RP2040", stale |
| `embedded-tls` | 0.19.0 | 2026-06-01 | TLS 1.3 client only; mTLS new in 0.19 |
| `rust-mqtt` | 0.5.1 | 2026-04-10 | MQTT 5 only; composes with `embassy-net` |
| `reqwless` | 0.14.0 | 2026-01-12 | needs a git pin — see below |
| `mcap` | 0.25.0 | 2026-06-11 | **std-only**, will not build for the MCU |

### ⚠️ You must pin embassy to git, for two independent reasons

**One.** `cyw43-pio` 0.10.0 drives TX and RX over a single DMA channel,
which corrupts the last bit of a read on RP2350. It surfaces as a hard
panic — `firmware checksum mismatch`. The fix (PR #6001) merged
**2026-05-09** and **has never been released**. The PR notes release
builds are sometimes fast enough to dodge the race, so debug builds fail
reliably and release builds fail intermittently — the worst shape a bug
can take.

**Two.** The RP2350 bootloader examples landed **2026-06-01**, after the
0.10.0 release of 2026-03-20.

Because the DMA `Channel` API changed, pinning one crate means pinning
all of them together.

### ⚠️ Tested on our hardware 2026-08-10 — and it did not bite

The claim above is that published `cyw43-pio` 0.10.0 corrupts RP2350
reads. **We tested it**, because the repo already pins exactly that
version from crates.io in `firmware/pico-led`, and because an unexplained
"the LED did not blink" was sitting in the log from earlier in the week.

Board #2 — RP2350 **revision A2**, QFN60,
**flash 4096K** — flashed with the release build via `picotool load -x`:

```text
    radio brought up, LED blinking     6 of 6 power cycles
```

So the race does not bite this configuration, and **embassy does not need
pinning to git for our purposes today.**

Two honest qualifications:

**6 of 6 rules out a frequent failure, not a rare one.** If the race bit
half the time, six clean boots would occur about 1.6% of the time — so a
common failure is excluded. Zero failures in six trials leaves the upper
bound on a *rare* failure loose. Before anything ships on this stack,
either run it far longer or pin to git anyway.

**The failure shape is the benign one.** The documented corruption hits
*initialisation* — the firmware checksum fails and the radio never comes
up. That is loud: nothing works and you power-cycle. It is not silent
corruption during operation, which would be far worse and much harder to
attribute. A rare init failure costs a replug, not a wrong measurement.

Incidentally this settles §3's flash-size ambiguity empirically: the Pico
2 W datasheet contradicts itself between 2 MB and 4 MB, and the silicon
reports **4096K**.

⚠️ Still unexplained: `pico-led` did not blink when first tried earlier in
the week, on the other board. Different board, and possibly a different
flashing path — [parts.md](parts.md) records drag-and-drop UF2 stalling
where `picotool load -x` works. Recorded as unexplained
rather than attributed to this bug, because one working board is not
evidence about a different one.

### There is no RP2350 networking example

`examples/rp235x/` has 69 examples and exactly one touches the radio:
`blinky_wifi`, which drives the LED and never calls `join()`. Every
networking example — `wifi_tcp_server`, `wifi_scan`, `wifi_webrequest` —
is RP2040-only. The port is mechanical, but it is not a path the
maintainers CI-test on our chip.

**And no OTA-over-WiFi example exists for RP2350 anywhere.** Targeted
search across GitHub repos, code, crates.io and embassy issues returned
zero. The closest working precedent is `embassy-supervisor` 0.4.3
(2026-08-04): a complete RP2350 OTA pipeline — HTTP GET → flash scratch →
zstd decode → DFU → `mark_updated()` → reset → swap → `mark_booted()`
with watchdog rollback — where **only the link layer differs**, being USB
CDC-NCM rather than cyw43.

---

## 3. The silicon already does A/B, and embassy ignores it

The RP2350 boot ROM has a capable native update system: partition tables
with **first-class A/B pairing**, version comparison with automatic
fallback to the valid slot, **try-before-you-buy trial boot** under a
16.7 s watchdog with automatic revert, OTP anti-rollback on secured
parts, and **QMI address translation** so both slots appear at
`0x10000000` — meaning A and B images can be byte-identical, with no
relocation and no copying.

`embassy-boot` bypasses all of it. It ends in a raw `bootload()` jump and
performs its own page-by-page swap.

```text
    embassy-boot costs   128 kB flash for the bootloader
                         a full 512 kB image copy per update
    for a capability     the ROM already provides for free
```

The ROM validates only the *bootloader's* image; the application's
metadata is emitted by `embassy-rp` and never read.

**For plain "two slots, newest wins, revert on failure", RP2350 arguably
needs no second-stage bootloader at all** — but no Rust crate drives the
ROM's native path, so that route means writing it. Recorded as an
opportunity, not a recommendation.

⚠️ Two gotchas in the shipped example: it hardcodes **2 MB** of flash
where Pico 2 and Pico 2 W both have **4 MB**, and it blinks `PIN_25`,
which on a Pico 2 W is the radio's chip-select rather than an LED.

---

## 4. Hardware constraints

### ⚠️ The 4×AA pack is out of spec for the Pico

```text
    VSYS maximum                     5.5 V
    Raspberry Pi's recommendation    THREE AA cells (~3.0–4.8 V)
    4× fresh alkaline                ~6.0 V nominal, 6.4 V open-circuit
```

**Currently harmless** — the pack feeds `VM` on the TB6612 (2.5–13.5 V)
and the Pico runs from USB. **It becomes a real problem the moment the
robot goes untethered**, because feeding the Pico from that same pack is
the obvious move and it is ~1 V over the absolute maximum. 4×NiMH at
4.8 V nominal is in range; straight off the charger at ~5.6 V is still
marginal.

### The link, not the radio, is the bottleneck

The host interface is **gSPI at ~33 MHz**, and on the Pico 2 W
**DIN, DOUT and IRQ share GPIO24**. So an inbound interrupt can only be
noticed when no SPI transaction is in progress — jitter injected before
any code sees a packet. 802.11n's 96 Mbps PHY is not the constraint.

Radio: **2.4 GHz only**, 802.11n, 1×1, 20 MHz channels. Bluetooth 5.2,
LE and Classic, sharing one antenna via in-chip coexistence.

### The latency/power trade is forced

Default power-save is **PM2 with a 200 ms interval**, and Raspberry Pi's
own documentation says it "might lead it to being less responsive".
Teleop would need `CYW43_NONE_PM` — meaning the radio never sleeps, which
lands straight in the power budget. **Low latency and low idle draw are
not both available.**

⚠️ **No current-consumption figures could be established.** Infineon
gates the CYW43439 datasheet behind a login and Raspberry Pi publishes
none. This is the largest gap in the research and it is closable in an
afternoon with an inline ammeter on VSYS: measure idle-connected,
`NONE_PM` vs `PERFORMANCE_PM`, and during a transfer.

### Pins, and one collision

The radio takes GPIO 23, 24, 25 and 29 — **none of which are on the
header on any Pico variant**, so the cost in usable pins is zero. No
conflict with our PWM slices 3/5 or GPIO 6–12 and 16–19.

⚠️ But **GPIO29 is both the WiFi SPI clock and the VSYS ADC.** Battery
voltage can only be read when no SPI transaction is in progress, wrapped
in `cyw43_thread_enter`/`exit`. On a WiFi robot, battery telemetry is not
a plain `adc_read()` — which lands directly on the still-pending work to
sense the motor supply, `VM`.

### Antenna, and an asymmetry worth remembering

Onboard PCB antenna at the bottom edge with a **14 × 9 mm keep-out**. The
guidance is asymmetric: **metal underneath or in front is bad; grounded
metal to the sides is mildly good.** Do not enclose it in metal.

Our battery holder and motor cans are both steel. Mount so the antenna
edge overhangs the chassis, pointing away from both.

⚠️ **No EMI guidance exists** for motors versus the radio — genuinely
absent from every primary source, not merely un-found. The plausible
coupling path is *conducted*, motor transients on the shared rail
disturbing the SPI link, rather than radiated at 2.4 GHz. There is a
documented lever if it bites: `WL_GPIO1` forces the SMPS into PWM mode
for better ripple, at a real efficiency cost.

---

## 5. Telemetry is a non-problem, and that is the point

Our 50 Hz pose + encoders + duty payload is **36 bytes**.

| encoding | per hour | 3 robots, 8 h |
|---|---|---|
| raw packed binary | 6.5 MB | 155 MB |
| MCAP + message index | 14.9 MB | 359 MB |
| MQTT + JSON + TCP/IP | 32.6 MB | 782 MB |

Three robots at the worst encoding is **~0.22 Mbit/s** — roughly 46×
inside a deliberately pessimistic 2.4 GHz budget.

Framing dominates the payload — 31 B of MCAP record, 16 B of index, 38 B
of MQTT on a 36 B payload is 2.4× overhead — **and it still does not
matter.** Optimising this stream is not where effort goes. **Batching ten
samples per publish** drops the inflation from ~4× to ~1.3×, which is the
one cheap win worth taking.

Add one camera and the arithmetic inverts by three orders of magnitude:
1080p30 H.264 at 4–8 Mbit/s is 14–29 GB per shift.

⚠️ **The "15–20 GB/robot/shift" figure in trainnr's
[`25-deployment-and-fleet-ops.md`](https://github.com/Trainnr-AI/trainnr/blob/main/docs/e2e-research/25-deployment-and-fleet-ops.md)
could not be sourced.** Two independent attempts failed. Inverting it gives
4.2–5.6 Mbit/s, which is consistent with one compressed camera plus 2D
lidar and odometry — so it is a plausible order-of-magnitude anchor for a
compressed-video AMR, and **it should be labelled as a decomposition
rather than a measurement.**

### No visualisation stack has an embedded path

`mcap` 0.25.0 is std-only — zero `no_std` in the repo, `num_cpus` as a
dependency. `rerun` and the `foxglove` SDK likewise. **So a Linux-side
bridge has to exist regardless**, which is itself an argument for the
tethered architecture: the chip emits compact frames, something with an
OS turns them into MCAP.

---

## 6. Every reference architecture tethers the MCU

| | |
|---|---|
| **micro-ROS** | XRCE *Client* on the MCU, *Agent* on Linux. The MCU never speaks DDS. Most supported boards are **UART-only** |
| **PX4** | "Communications with the ground stations and the cloud are usually routed via the companion computer" |
| **ArduPilot** | Same split, MAVLink over serial or Ethernet |
| **TurtleBot 4** | A Raspberry Pi 4B runs the software; WiFi lives there |
| **ros2_control** | `controller_manager` owns the real-time loop; the plugin boundary is where the serial/CAN link sits |

micro-ROS is the strongest evidence precisely because it is *the*
MCU-on-ROS-2 project, and it still will not let the chip own the network.

### The trade, with mechanisms rather than adjectives

| | MCU on WiFi | MCU tethered |
|---|---|---|
| Control-loop latency | same — the loop is local either way | same |
| **Jitter** | worse: TLS handshake burns CPU synchronously, retransmits contend | better: network jitter quarantined |
| **Security surface** | TLS + supplicant + TCP/IP + cert parser in the same address space as motor control | one framed serial protocol you define |
| **OTA** | you build the whole client; no RP2350 precedent exists | RAUC/Mender mature; MCU firmware ships as a payload the Linux node flashes |
| **Enterprise WiFi** | ❌ impossible | ✅ supplicant does EAP |
| **Debuggability** | no shell, no logs, no packet capture | ssh, journald, tcpdump |
| Power | lower — no 1–3 W SBC. Decisive on battery | higher |

---

## 7. Open questions

1. **Measured WiFi latency and jitter, and what functional-safety
   practice says about wireless links carrying safety-relevant
   commands.** The research on this could not be completed. It is the
   one question that would turn a well-supported architectural argument
   into a quantified one, and trainnr's
   [`26-safety-and-regulation.md`](https://github.com/Trainnr-AI/trainnr/blob/main/docs/e2e-research/26-safety-and-regulation.md)
   is where the answer belongs.
2. **CYW43439 current draw.** Not publishable — Infineon gates it.
   Measure it.
3. **Which RP2350 stepping ships today**, given E24 is unpatchable on
   A2/A3.
4. **Real TCP/UDP throughput on this module.** No primary source exists.
   Raspberry Pi ships an `iperf` example; run it rather than quote
   anyone.
5. **Is the customer's site WPA2-Enterprise?** One question, and it can
   settle §1.1 before any code is written.

---

## What this changes about the plan

Nothing that has been built. The `CommandWatchdog` on the chip, the
`StuckMonitor`, the shared `hil-protocol` — all of those are Tier 0/1
work that is *more* clearly correct if the chip stays a real-time I/O
node behind a wire.

What it changes is the shape of the next tier: the thing on the other end
of the tether is a Linux computer, not a laptop that happens to be
plugged in, and it is the piece that owns the network, the recording and
the updates. That is the same conclusion trainnr's
[`19-the-system.md`](https://github.com/Trainnr-AI/trainnr/blob/main/docs/e2e-research/19-the-system.md) reached from
the latency budget, arrived at independently from security, OTA and
tooling.
