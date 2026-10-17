# barbell_app

A personal Flutter app for a BLE barbell sensor. It rebuilds the training
core of the reference app analysed in `notes/android-apk-decompiled.md`.
Auth, onboarding, cloud sync and video are left out on purpose.

## Features

- **Device:** scan for and connect to a WitMotion IMU, with auto-reconnect.
  Shows battery, the delivered sample rate and packet loss, a live trace,
  and a 5 s flat calibration.
- **Sessions:**
  1. Pick an exercise from the reference app's 13-exercise catalogue.
  2. Enter weight and set type.
  3. Record the set; the raw CSV is saved first.
  4. Results: reps, mean/peak velocity, ROM, velocity loss, a velocity chart
     with rep windows, and per-rep sticking bands (orange 75 %, red 32.5 %).
     Add RPE and a note, then go to the next set or finish.
- **Video:**
  - Optionally record each set with the phone camera. Settings: back/front
    lens, 720p/1080p/4K, 30/60 fps, sound on or off.
  - The camera start is timestamped against the first sensor sample, so the
    overlay is synced without assuming both start at the same moment, which
    the reference app does.
  - The player shows a metrics panel (weight, rep count, rep mean velocity,
    live velocity, sticking band), the velocity chart with a playhead, rep
    jump chips, and a ±50 ms sync nudge you can save.
  - Videos are stored in `<docs>/videos/<setId>.mp4`.
- **History:** sessions with per-set best velocity and expandable set cards,
  including "Watch video".
- **Analysis** (`lib/analysis/`, ported from the reference app):
  - Squat and bench use a port of the MATLAB native library
    (notes §5–8, §11). `PipelineOptions.matchNativeVerticalBand` switches
    between the native fixed 100 Hz vertical band-pass and one designed from
    the measured rate.
  - Deadlift uses the TCN pipeline with the bundled U-Net and TCN TFLite
    models (§4, §10). If they fail it falls back to the native thresholds,
    as the reference app does.

## Layout

- `lib/sensor/` — sensor interface, WitMotion protocol and BLE link, rate
  monitor.
- `lib/analysis/` — `analyzeSet` contract, motion mapper, DSP primitives
  with MATLAB semantics, squat/bench and deadlift pipelines, model loading.
- `lib/video/` — video settings, camera recorder, overlay timeline (video
  ↔ sensor time).
- `lib/workout/` — sensor controller, session models, JSON store,
  background analysis runner.
- `lib/ui/` — app shell, home, device, set flow, results, history, charts.
- `assets/models/deadlift/` — the reference app's models. Personal use
  only; don't redistribute.

## Run

```sh
flutter test            # 59 unit and widget tests (no device needed)
flutter run             # needs a phone; BLE does not work in emulators
```

Uses `flutter_blue_plus` 2.x, whose license is free for personal use and
requires a commercial license for for-profit use. `connect()` passes
`License.nonprofit`.
