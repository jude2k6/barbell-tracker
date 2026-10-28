# Own orientation (clock mode): hand-off

Status 28 Oct 2026: built and unit-tested, **not verified on real lifts**.
Background: `notes/sensor-clock-problems.md` (why the stock sensor has no
clock, probe results for register 0x96).

## What it is

Stock WT9011DCL frames carry either roll/pitch/yaw angles (0x96 = 0) or a
uint32 ms counter (0x96 = 2) in the last 6 bytes, never both. Clock mode
takes the counter and works out orientation in the app instead.

- `WitClockMode` (`lib/sensor/witmotion/witmotion_mode.dart`): sends
  `WitCommands.outputClock` after the unlock at connect (it isn't saved;
  the sensor reverts on power cycle). It turns the counter into
  `sensorTimeMs` and feeds each frame to the filter.
  - dt = counter step if 0 < step ≤ 100 ms, else 1 / nominalHz (200).
  - hostTimeUs = notification arrival (no spreading; the counter is the clock).
- `TiltFilter` (`lib/sensor/orientation.dart`): 6-axis Mahony filter.
  1. The first sample within 0.1 g of 1 g sets roll/pitch from gravity
     (yaw 0) via `eulerToQuaternion` (ZYX, body→world).
  2. Integrates the gyro (deg/s → rad/s) each sample.
  3. Only while | |a| − 1 g | < `accelGate` (0.1): corrects toward the
     accelerometer's down, kp 2.0, ki 0.1. Mid-rep it runs on gyro alone.
  4. Yaw drifts (no magnetometer). That's fine: analysis only uses the
     quaternion for world-vertical (`SensorSample.worldZ`, third row).
- To enable: Debug Menu → Sensor diagnostics → Clock. It switches the
  connected sensor live (`WitMotionLink.setMode`, no reconnect) and is
  saved (`Preferences.clockMode`), so later connects use it too. Default is
  still `WitAnglesMode`. Gains are `Preferences.tiltGains`.
- 30-byte (Stance-firmware) frames bypass the filter in both modes.

Tests: `test/witmotion_mode_test.dart`, group `WitClockMode`: counter as
time, starting tilt, 90° roll tracked from the gyro, accel gate holding the
tilt while |a| ≈ 1.26 g.

## Sensor diagnostics screen (28 Oct 2026)

`lib/ui/sensor_diagnostics_page.dart`, logic in
`lib/workout/sensor_diagnostics.dart`. Not on a phone yet.

- **What arrives** (question 1): notifications/s, samples/s, MTU, frames
  per notification and notification byte histograms
  (`WitLinkStats`, `lib/sensor/witmotion/witmotion_stats.dart`), arrival
  gap mean/p95/max, and in clock mode the counter-step histogram. The link
  now asks Android for high connection priority at connect.
- **App filter vs sensor** (question 2): in angles mode a second
  `TiltFilter` runs on the same accel/gyro; the screen shows the tilt
  difference to the sensor's fusion (yaw ignored), its RMS while still, the
  still gyro bias, and traces. Each movement (|a| off 1 g by 0.15 g or
  > 30 °/s, ends after 0.5 s still) gets a row: duration, peak and end tilt
  difference, peak vertical velocity, and the peak velocity and
  displacement gap between the two filters. So one set in angles mode
  answers question 2; no need to record twice. Caveat: the shadow filter's
  dt comes from the rebuilt host times there, not the sensor clock.
- **Gains** (question 3): sliders for kp, ki and the gate apply live to
  the comparison and to a clock-mode stream, and are saved.
- Every movement and a 10 s timing summary go to the debug log
  (tag `Diagnostics`), so "Share debug log" carries the numbers.

## Open questions (do these next)

1. **Delivered rate on the phone.** Laptop got ~25 frames/s, counter steps
   of exactly 40 ms (one sample per notification, no packing). If the phone
   also gets 25/s, gyro integration at 40 ms steps may be too coarse for
   fast reps. Check notification lengths (multiples of 20 = packed) and the
   counter step in the debug log.
2. **Tilt error during a rep.** No gravity correction while the bar
   accelerates, so gyro bias builds up over the 1–2 s of a rep. Measure:
   record the same reps in both modes (or one set per mode, same lift and
   load) and compare world-Z velocity/displacement and rep detection.
3. **Gains untuned.** kp 2.0, ki 0.1 and the 0.1 g gate are textbook
   defaults. Tune against the angles-mode reference from step 2. Too high
   a kp lets bar acceleration leak into the tilt; too low recovers slowly
   between reps.
4. ~~**Mode switch.**~~ Done: the diagnostics screen above.

## Decision to make after testing

Keep angles mode (sensor's own fusion, rebuilt timestamps) or clock mode
(real per-sample clock, our fusion) as the default. Clock mode wins only if
its tilt is as good as the sensor's during reps; real timestamps alone are
worth less than the notes once assumed, because nothing is lost in transit.

## Don't

- Don't send save (`FF AA 00 00 00`) or reset (`FF AA 00 01 00`).
- Don't expect a 30-byte frame from any setting; it needs Stance's firmware.
