# Security policy

rigrs is pre-1.0. Fixes land on `main`; there are no maintained older
lines.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use GitHub's
private vulnerability reporting on this repository ("Report a
vulnerability" under the Security tab). If you cannot use it, email
trainnrai@gmail.com with "security" in the subject and no details, and a
maintainer will reply with a private channel. Include the commit, the
steps to reproduce and what an attacker gains. You will get an
acknowledgement within a week.

## In scope

- The firmware in `firmware/` and the `no_std` crates it links.
- The parsers on both ends of the wire (`hil-protocol`, `hil-host`): a
  line from a chip or a recording is untrusted input.
- The host tools in `crates/`, including `teleop-web`.

## Things to know

- **`teleop-web` has no authentication.** It listens on every interface
  so that a phone on the same network can reach it, and anyone who can
  reach the port can drive the robot. Run it on a network you trust.
- **Wi-Fi credentials are compiled into the image.** `WIFI_SSID` and
  `WIFI_PASSWORD` are read at build time (`option_env!`), so a `.uf2`
  built with them carries the password in plain text. Do not share such
  an image. Built without them, the firmware never tries to join.
- **Wi-Fi telemetry is a plain UDP broadcast** on the local network,
  unauthenticated and unencrypted.
- Nothing here is safety-certified. A robot driven by this code can move
  unexpectedly; keep a hand near its power.
