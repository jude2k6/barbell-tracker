# TODO

Personal Flutter app (`src/barbell_app`) rebuilding the training core of
**Stance** (Stance Fitness, `com.stancefitness.android`). Reverse-engineering
notes: `notes/android-apk-decompiled.md`. Decompiled sources:
`targets/decompiled/` (not committed).

Feature items marked *(Stance)* are only known by their class names in the
decompiled app. Trace how Stance implements each one before building it.

## Features from Stance

- [x] **Load–velocity chart and same-weight history** *(Stance, notes
      §12)*: done, faithful port in `lib/workout/load_velocity.dart`, shown
      on the session feedback page. Stance has no regression or 1RM estimate.
      Optional own addition: a line fit plus a 1RM projection at a
      minimum velocity threshold.
- [x] **RPE learning** *(Stance, notes §13)*: done. Profile and window
      in `lib/workout/rpe_profile.dart`. Chart and suggested range in the
      RPE sheet (feedback page's RPE card). Manager (`RpeProfilePage`)
      opens from that sheet or the feedback page's menu.
- [x] **Readiness** *(Stance, notes §14)*: done. `lib/workout/readiness.dart`
      and `ReadinessCard`, opened from the feedback page's readiness card
      for the selected set. It only uses sessions of the same day type;
      history rows show the "Block… Week…" tag label.
- [x] **Set and session comparison** *(Stance, notes §15)*: done.
      `lib/workout/session_comparison.dart`. The feedback page has a
      Chart/Table/Reps comparison with a session picker. The rep speed
      sheet has a rep chart that can compare against another set.
- [x] **Workout flow and navigation** *(Stance, notes §16)*: done. Home
      lists exercises (device chip and menu in the top bar, no tabs) →
      `SessionsPage` (New Session; Continue/View per `activeSessionId`) →
      `WeightInputPage` (weight + required set type, unit from
      `PreferencesPage`) → `RecordSetPage` → `SessionFeedbackPage`, which
      replaces the old set result and session detail pages. Navigation
      rules live in `ui/workout_flow.dart`. No "finish session". Own
      additions kept: the live trace while recording, and the weight field
      prefilled with the last weight. Day type and session tags are the
      items below.
- [x] **Feedback extras** *(Stance, notes §17)*: done. Edit Set with
      Details (weight, set type, Copy Set ID, Report Issue, Delete Set) and
      Reps tabs (7-day edit timer, Recalculate to fewer reps by smallest
      ROM, Check Reps); `RepCheckPage` (move, delete, add rep markers with
      Stance's validation); Report Issue (the set note); the feedback
      walkthrough, the four guide tips and the rep edit guide, each shown
      once (seen flags in `Preferences`); the 60 s analysis countdown, and
      leaving the record page while it analyses. Logic in
      `workout/rep_editing.dart` and `workout/guide_tips.dart`. Differences:
      Rep Check uses sliders instead of draggable chart markers and has no
      synced video; a moved rep's ROM shows as unknown, not 0.
- [x] **Session day types** *(Stance, notes §18)*: done. `Day:` session
      tags (`workout/session_tags.dart`); day dropdown and the "What type of
      session are you doing today?" prompt on the feedback page; shown in
      the tags row on Sessions cards. Readiness and comparison only use
      sessions of the same type, and an untagged session gets no
      comparison (as Stance), so sessions recorded before this need a day
      type to compare.
- [x] **Session tag editor** *(Stance, notes §19)*: done.
      `ui/session_tag_editor.dart` (Block/Week with "more…", Day,
      Externals; one tag per section; Done or dismiss saves), rules in
      `workout/session_tags.dart`. Tags row on Sessions cards (replaces
      the day chip) and under the feedback page's day dropdown; readiness
      history shows the "Block… Week…" label. Stance never opens its
      editor; here "Add/Edit session tags" on the feedback page does. Own
      addition: Block/Week start with enough pages to show a selected tag.
- [x] **User profile and preferences** *(Stance, notes §20)*: done.
      Home menu "User Details" opens the profile sheet
      (`ui/user_details_sheet.dart`: names, gender, date of birth,
      bodyweight kg/lbs, height cm/ft-in, training age, RPE confidence,
      competition level, optional Instagram; completion bar; Save/Done or
      dismiss saves). Rules in `workout/user_profile.dart`; stored in
      `Preferences` (`preferences.json`). Preferences page gained Height
      Unit and now saves on Done (back discards), as Stance. Nothing uses
      the profile yet, same as Stance. Own change: the sheet's Hello/Save
      header stays pinned while the fields scroll.
- [x] **Signal-quality verdict per set** *(Stance, notes §21)*: done.
      Stance has no per-set verdict. Its live Good/Fair/Poor badge
      (`AssessSignalQualityUseCase`: last 200 samples, ≥ 95 % complete and
      no gap > 20 ms = Good, ≥ 80 % Fair) is dead UI, and its per-set
      `ImuQualityMetrics` (data loss, saturation, still periods, impacts)
      are only stored, synced and logged. Ported: the badge beside the
      record button (`workout/signal_quality.dart`; deviation: visible
      here) and metrics saved as `SetRecord.imuQuality`
      (`analysis/imu_quality.dart`).
- [x] **CSV import and reprocess** *(Stance, notes §24)*: done. Feedback
      page's reprocess banner (Stance's four messages; Reprocess /
      "Reprocessing…"; selected set only) for sets whose analysis failed or
      found no reps, re-run from the raw CSV (`workout/reprocess.dart`).
      Home "Import recording" card: picks our raw CSV or Stance's IMU
      export (`recording/recording_csv.dart`, Stance's errors), asks
      exercise + weight, saves a set in a new session; then "Imported: …"
      (opens Sessions), Export IMU CSV, Dismiss. New dep: `file_picker`.
      Deviations: Stance's import is debug-only and reads `.dat`; reprocess
      here works from disk any time (Stance: only until restart). IMU
      quality is not recomputed, as Stance.
- [x] **Video export** *(Stance, notes §26)*: done. Review page app bar:
      Share, and More → "Save to camera roll". Crop 10 s before the first
      rep to 10 s after the last (clamped; no reps = no export), silent,
      overlay burned in ("Bar Speed", weight x reps, rep number and mean
      m/s during each rep, eased fill bar with amber sticking band). Rules
      in `video/set_video_export_rules.dart`; Media3 Transformer via
      `SetVideoExportChannel.kt`; `share_plus` and `gal`. Falls back to the
      raw video if the export fails, and always on iOS (no encoder).
      **The Kotlin has never been compiled** (no Android SDK here).
- [x] **Pre-recording guide** *(Stance)*: done ("Setup Guide", once and
      from the top bar). Stance's three tracker-hardware steps are replaced
      by one generic connect step. Also one random tip per visit from
      `PreRecordingTips` (minus its internet-connection tip).
- [ ] *(Probably skip)* **Stance Encoder support**: Stance's own linear
      encoder; protocol already decoded in notes §2.
- [x] **Saved sensor and auto-reconnect** *(Stance, notes §22)*: done.
      `workout/saved_sensor.dart`: the sensor id is saved in `Preferences`
      once a connection streams (kept on disconnect). Home and the Device
      screen try to reconnect once per app run (`ui/auto_reconnect.dart`):
      scan up to 12 s for it, connect if seen, no retry, as Stance.
      Deviations: the Device screen has "Forget saved device" (disconnects
      and clears; Stance's string is unused and its only Forget is a
      Settings row that doesn't disconnect); saves on streaming, not on
      connect request.
- [x] **Deadlift tips on Home** *(Stance, notes §23)*: done. Stance's
      "Tips:" card with its five tips in its order, under the Deadlift
      exercises (`DeadliftTipsCard` in `ui/exercise_list.dart`). Always
      shown, no seen flag, as Stance. Difference: Stance shows it on the
      deadlift group's own screen; our Home is one flat list.
- [x] **Weight-performance tutorial** *(Stance, notes §23)*: done. "How
      do I use this?" (always available) under the rep speed sheet's "Sets
      at X" heading opens a "Weight Performance" sheet with Stance's
      subtitle and image (`assets/images/weight_performance_tutorial.webp`,
      from the APK). Difference: no close button or logo on the sheet.
- [x] **"Location is off" prompt** *(Stance, notes §22)*: done.
      `permissions/ble_readiness.dart` (Android SDK ≤ 30 and Location
      Services off) and `ensureLocationServices` in
      `ui/permission_prompts.dart`: "Turn on Location" + "Not now" before
      the Device screen's scan, "Continue anyway" on Sessions "New Session"
      when no sensor is connected. Permissions stay with `ensureAccess`
      (Stance folds them into the same dialog). New deps:
      `device_info_plus`, `android_intent_plus`.
- [x] **Settings and debug screens** *(Stance, notes §25)*: done. Home
      menu "Debug Menu" opens `ui/debug_menu_page.dart` with the rows that
      work without an account: File logging + "Share debug log"
      (`share_plus`), "Test device data stream", "Forget saved BLE devices"
      (also disconnects, unlike Stance). Logger `workout/file_log.dart`
      (`AppLog`, `debug_logs/stance-app.log`, Stance's line format, 5 MiB
      cap trimmed 10 lines at a time); logs app load, sensor, recording,
      analysis and save events, plus Stance's "SET COMPLETED" block with
      the IMU quality metrics (`workout/set_log.dart`). Device Stream (`ui/device_stream_page.dart`,
      `workout/device_stream.dart`): Start/Stop/Clear, acceleration,
      quaternion and global-acceleration plots, stationary/uncalibrated/
      streaming-issue badges. Skipped rows: Firebase ID, BLE stack switch,
      Recording/Calibration screens, sync diagnostics, Sign out; and
      per-screen lifecycle logging.
- [ ] **Visual style** *(Stance, `presentation/theme`)*: the theme is
      ported (`ui/stance_theme.dart`: dark-only colour scheme, Poppins
      type scale and fonts from the APK, shapes). Home matches
      `HomeScreen`: the top row with the settings circle and the
      `SmallDeviceStatusButton` pill (now used on every page), the 40 sp
      title, and group → exercise drill-down with `ExerciseCatalogRow` cards
      and the BETA badge. Other screens only get the theme so far; port
      each screen's own layout next (Sessions, Weight input, Record,
      Feedback). Own additions on Home: the Bluetooth card, and the
      Recordings menu item.

Deliberately out of scope: auth, onboarding and welcome screens, the
affiliate and WhatsApp prompts, "update required", cloud sync (Supabase),
server-side analysis (Vercel).

## Own gaps

- [ ] **Export and share** raw CSVs off the phone (videos: done via
      Video export).
- [ ] **kg/lb display**: the weight unit is now a preference used for
      input and the Sessions cards; the feedback page still shows each
      set's own unit.
- [ ] **Session delete** (feedback page menu; deleting a session's last
      set also deletes it): optionally remove its CSVs and videos too.
- [ ] **Drift-correction option**: an improved alternative alongside the
      faithful 5 s moving-average port, e.g. zero-velocity resets when the
      bar is still. Known issue: long pauses stretch reps and ROM reads
      10–20 % high (notes §11).
- [x] **Permissions on Android ≤ 11**: done with the Location prompt
      (notes §22). On SDK ≤ 30 the Bluetooth capability requires
      `locationWhenInUse`, asked through `PermissionService`.
- [ ] **README**: note that CocoaPods builds need permission_handler's
      Podfile macros (`PERMISSION_CAMERA`, `PERMISSION_MICROPHONE`,
      `PERMISSION_BLUETOOTH`). The current Swift Package Manager build
      needs none.
- [ ] **Simulated sensor**: a `SensorLink` that generates or replays sets,
      for end-to-end runs without hardware.
- [ ] **DIY sensor**: firmware speaking WitMotion `55 61` frames plus a
      sample counter, and a second `SensorLink` for it.

## Not yet verified on a device

- Bluetooth connect and the real delivered sample rate.
- Deadlift TFLite models loading and running. They use only standard ops,
  so they should.
- Camera recording and overlay sync.
- Video export: Media3 build, clip timestamps starting at 0, share and
  gallery save.
- Saved-sensor auto-reconnect, the Location prompt and the Android ≤ 11
  location permission.
- Share debug log and the Device Stream charts at 200 Hz.
- Permission prompts and the Settings round-trip.

## Environment

- **Tools:** Flutter 3.47.7 at `~/tools/flutter`, JDK 21 and Ghidra 12.1.4
  in `~/tools`, all wired into the REA MCP server.
- **APK strings:** apktool isn't installed. Use
  `python3 -I tools/arsc_strings.py <resources.arsc>`, with `resources.arsc`
  extracted from `targets/reference-android.apk` via Python `zipfile`. It
  prints the default-locale `name = value` string resources.
- **REA:** the MCP server's JADX/apktool providers aren't configured
  (`REA_JADX_MCP_JAR` unset); the `rea` CLI works after sourcing
  `~/.local/share/rea-tools/env.sh`, including JADX fallback mode for
  broken decompiles.
- **No Android SDK or Xcode** on this host: native code
  (`SetVideoExportChannel.kt`) can't be compiled here.
- **Checks:** run `~/tools/flutter/bin/flutter test` and `flutter analyze`
  in `src/barbell_app`. Last run (2026-10-17): 247 tests passing, analysis clean.
