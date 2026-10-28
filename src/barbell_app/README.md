# barbell_app

A personal Flutter app for a BLE barbell sensor. It rebuilds the training
core of the reference app analysed in `notes/android-apk-decompiled.md`,
with the same flow and look. Accounts, onboarding and cloud sync are left
out on purpose. `TODO.md` at the repo root tracks what is done and what
is left.

## Features

- **Device:** scan for a stock WitMotion IMU (WT9011DCL / WT901BLE) and
  connect, remembering it and reconnecting at launch. Shows battery,
  delivered sample rate, packet loss and a live trace. Calibration is a
  10 s flat hold.
- **Workout flow:**
  1. Pick an exercise from the reference app's 13-exercise catalogue.
  2. Open or continue a session, then enter weight and set type.
  3. Record the set, optionally with video. The raw CSV is saved first.
  4. Feedback page: reps, mean/peak velocity, ROM, velocity loss, the
     velocity chart with rep windows and sticking bands, RPE and notes.
- **Feedback page extras:**
  - Load–velocity chart and same-weight history.
  - Readiness against the last session and the average for the same day
    type.
  - Set and session comparison as chart, table or reps.
  - RPE learning: a suggested RPE range from your profile, plus a profile
    manager.
  - Session tags (block, week, day type, externals).
  - Edit Set: weight, set type, Recalculate, Check Reps with draggable
    markers over synced video, and Report Issue.
  - Reprocess sets whose analysis failed.
  - Delete a set, or a session, optionally with its recordings and
    videos.
- **Video:**
  - Full-screen capture mode with lens, quality (720p, 1080p or 4K) and
    30/60 fps pills.
  - The camera start is timestamped against the first sensor sample, so
    the overlay stays in sync without assuming both start together.
  - Review with a metrics panel, a playhead on the velocity chart, rep
    chips and a ±50 ms sync nudge.
  - Export a clip from 10 s before the first rep to 10 s after the last,
    then share it or save it to the camera roll. Android burns the
    overlay in. iOS has no encoder, so it shares the raw video.
- **Units and data:**
  - Every weight shows in the preferred unit (kg or lb), as the reference
    app does.
  - The Recordings page shares raw CSVs off the phone, one at a time or
    all at once.
  - Old CSVs can be imported and analysed.
- **Debug Menu** (Home menu):
  - Share debug log, test the device data stream, Calibration, and forget
    the saved sensor.
  - **Sensor diagnostics:** switch the sensor between its own angles and
    its ms clock (orientation then comes from the app's tilt filter).
    Shows what arrives per BLE notification, compares the app's filter
    with the sensor's fusion per rep, and tunes the filter gains. See
    `notes/own-orientation-clock-mode.md`.
- **Analysis** (`lib/analysis/`, ported from the reference app):
  - Squat and bench use a port of the MATLAB native library
    (notes §5–8, §11). `PipelineOptions.matchNativeVerticalBand` switches
    between the native fixed 100 Hz vertical band-pass and one designed
    from the measured rate.
  - Deadlift uses the TCN pipeline with the bundled U-Net and TCN TFLite
    models (§4, §10). If they fail it falls back to the native thresholds,
    as the reference app does.

## Sensor notes

The stock sensor sends 20-byte frames carrying either the sensor's angles
or a millisecond counter, set by register 0x96. It never sends the
reference app's 30-byte frame, which needs that app's own firmware. Angles
mode is the default. Details are in `notes/sensor-clock-problems.md`.

## Layout

- `lib/sensor/` — sensor interface, WitMotion protocol, stream modes and
  BLE link, tilt filter, rate monitor.
- `lib/analysis/` — `analyzeSet` contract, motion mapper, DSP primitives
  with MATLAB semantics, squat/bench and deadlift pipelines, model loading.
- `lib/recording/` — raw-sample CSV recordings.
- `lib/video/` — video settings, camera recorder, overlay timeline (video
  ↔ sensor time), export rules and the Android export channel.
- `lib/workout/` — sensor controller, session models and JSON store,
  preferences, load–velocity, readiness, RPE, comparison, diagnostics,
  background analysis runner.
- `lib/ui/` — app shell, theme and shared widgets, and every screen and
  chart.
- `assets/models/deadlift/` — the reference app's models. Personal use
  only; don't redistribute.

## Run

```sh
flutter test            # ~300 unit and widget tests (no device needed)
flutter analyze
flutter run             # needs a phone; BLE does not work in emulators
```

GitHub CI builds the APK.

iOS builds use Swift Package Manager and need no extra setup. A CocoaPods
build would need permission_handler's Podfile macros
(`PERMISSION_CAMERA`, `PERMISSION_MICROPHONE`, `PERMISSION_BLUETOOTH`).

Uses `flutter_blue_plus` 2.x, whose license is free for personal use and
requires a commercial license for for-profit use. `connect()` passes
`License.nonprofit`.
