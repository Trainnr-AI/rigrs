# Roadmap: the staged plan, in detail

*Written July 2026 as the project's staged plan (Stages 0–5), with status notes added in August 2026; kept as the design record.*

*From 2026-08-31 the work moved on to robot learning, which continues in
[trainnr](https://github.com/Trainnr-AI/trainnr), the sibling robot-learning
toolchain; that later staging is recorded there. The ladder below is the
record of this repository's era.*

Goal: from software-only to autonomous VLA-driven machines, in Rust, learning the
whole ecosystem on the way. Every stage ships something that runs.

## Stage 0 — Robot on the laptop (pure software, $0)

Build a 2D simulated differential-drive robot (two independently driven wheels —
the Roomba/tank model) living in a world with walls and obstacles.

**Written by hand rather than taken from a library, because understanding them
was the point:**
- The fixed-rate control loop (the heartbeat of every robot, e.g. 50–100 Hz)
- Differential-drive kinematics (wheel speeds → robot motion, and the inverse)
- Odometry / dead reckoning (integrating wheel motion to estimate pose, and why
  the estimate drifts)
- PID control (the workhorse controller: go-to-heading, go-to-point)
- Simulated sensors: wheel encoders (with noise), distance rays (a fake lidar)
- Behavior state machines (WANDER → AVOID → GOTO_GOAL)

**Architecture (revised after red-teaming — see
[sim-design.md](sim-design.md)):** a pure, deterministic,
fully-tested `sim-core` crate (no game engine, no physics engine — we write the
kinematics ourselves, that's the point) + a thin runner logging to **Rerun**.
Motor lag + saturation modeled so PID is meaningful; noise injected at the
physical source (encoder quantization, slip, wheel-radius bias) so odometry
drift is realistic. Interactive/Bevy frontend is a later optional bolt-on.

**Milestone:** the simulated robot autonomously navigates to a goal while
avoiding obstacles, with a live view of its *believed* pose (odometry) vs its
*true* pose — watching them diverge is the lesson. (The plan: buy the Pico 2 W +
Debug Probe at the start of Stage 0 and blink an LED in parallel — Stages 0 and
2 overlap deliberately.)

## Stage 1 — Perception on the laptop (webcam, $0)

The laptop webcam becomes the robot's eye.

- Run an object-detection model (YOLO-class) in Rust via `ort` (ONNX Runtime) or
  `candle`
- Feed detections into the Stage 0 sim: the sim robot reacts to what the real
  camera sees (e.g. chases a detected object)
- Covers: model formats (ONNX), preprocessing, inference latency budgets, the
  perception→decision→action pipeline

**Milestone:** point the webcam at an object; the sim robot pursues it live.

## Stage 2 — First hardware: a microcontroller (~$10–30)

Not classic Arduino — the AVR chips have poor Rust support. The embedded-Rust
sweet spots are **Raspberry Pi Pico 2 (RP2350)** and **ESP32-class** boards with
the `embassy` async framework. (The final pick, after research: the Pico 2 W.)

Ladder of firsts, each one small:
1. Blink an LED (the "hello world" that proves the whole toolchain)
2. Read a sensor over I2C (IMU — accelerometer/gyro)
3. PWM-drive a motor through an H-bridge driver
4. Closed loop: hold a motor at target speed using encoder feedback
5. Talk to the laptop over serial/USB (this link becomes the robot's spinal cord)

**Covers:** voltage/current/ground, why grounding matters, reading datasheets,
wiring on a breadboard, not letting the magic smoke out.

## Stage 3 — First real robot (~$100–150)

2-wheel chassis + N20 or TT motors **with encoders** + motor driver + IMU + a
time-of-flight distance sensor (or cheap 2D lidar). Brain split:
- **Microcontroller (Rust/embassy):** real-time motor control, sensor reading
- **Laptop (Rust):** the "big brain" over WiFi/serial — teleop first, then
  autonomy

Port the Stage 0 controller onto real motors and meet reality: wheel slip,
sensor noise, battery sag, loose wires. This is also the right moment for the
**deliberate ROS 2 detour**: run the same robot once through vanilla ROS 2
(Python nodes) to learn the industry lingua franca, then return to the Rust
stack knowing both.

**Milestone:** the Stage 0 simulator behavior, running in the physical world —
obstacle avoidance + dead reckoning, untethered except for the radio link.

> **Status 2026-08-15: substantially met, differently than planned.** The
> car drives (phone teleop + on-chip watchdog, 2026-08-13), and beyond
> the milestone: an OV7670 feeds an on-chip brightness blob whose errors
> drive the wheels (`firmware/pico-odom`'s `chase` feature) *and* three arm
> servos (its `arm` feature) — the camera
> stage arrived early and on the chip rather than the laptop. Untethered
> radio telemetry exists (the `wifi` feature); wheel geometry (`wheel_radius`,
> `track_width`) is still unmeasured, so dead-reckoning is calibrated in
> ticks, not metres.

## Stage 4 — Onboard AI compute (~$250+)

A Jetson-class board replaces the laptop; perception runs *on* the robot. This
is the classic two-tier autonomy architecture (same shape as a self-driving
car):
- **Tier 1 (microcontroller):** hard-real-time motor/safety loop
- **Tier 2 (Jetson):** vision, mapping, planning — Rust + GPU-accelerated
  inference; tiers talk over serial/CAN

Add a camera and a cheap 2D lidar; do SLAM (map the room, localize in it).

**Milestone:** fully untethered robot that navigates the home and recognizes
objects with no laptop in the loop.

## Stage 5 — Arm + VLA (~$150+ for the arm)

Add a hobbyist arm (SO-101 class — the LeRobot ecosystem standard, which is
what the open VLA models are trained and fine-tuned on).

- Teleoperate (leader-follower) to record demonstrations
- Fine-tune an open VLA (SmolVLA-class) — Python/PyTorch territory
- Run inference on-robot in the Rust stack (`candle`/`ort`, or dora-rs nodes)

**Milestone:** a typed/spoken instruction — "pick up the red cube" — executed by
the arm. The self-driving-car-with-hands, in miniature.

> **Status 2026-08-15: the arm's first hardware phase started early** —
> 3× SG90 on a PCA9685, camera-tracked (pan/tilt/grip from the blob's
> three errors), hold-on-loss. No feedback yet, which is exactly the
> boundary the arm's design predicted: `Joint`-only hardware
> cannot run the safety layer, so nothing hangs on the horns until the
> AS5600s (or the SO-101) arrive.

## Beyond: the product ladder

toy → pet → inspection rover → delivery pod / autonomous service vehicle

All the same two-tier architecture, scaled: better actuators, redundant sensors,
safety cases, fleet monitoring (Rust→Wasm dashboards), and much more rigorous
engineering. The skills transfer 1:1; the certification/safety work is the new
material at that scale.
