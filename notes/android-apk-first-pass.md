# Reference Android APK — first pass

Target: `targets/reference-android.apk`
sha256 37b2643f96dd822d6625cbdd22894c8c04205083608ba3debd7a81f63513f215
Source: shared by the user via Google Drive (12 Oct 2026). Pre-release build.

Method: static only — zip inventory, binary manifest strings, APK v2 signing
certificate, ELF dynamic symbols of the native library, string scan of dex.
No decompilation yet (REA's Android tools need Java + jadx-headless-mcp 0.7.1).
Nothing was executed.

## Identity (observed)

- versionName 0.0.26. Kotlin + Jetpack Compose, Hilt, Gradle 8.13.
- Signed with a self-signed v2 certificate valid from 2026-05-28. Not
  compared against an official release (none exists yet).
- Permissions: BLE scan/connect, location, camera, read media video, internet.

## Architecture (observed from package/class names)

- `data/ble`, `data/ble/nativestack` — sensor link.
- `data/algorithm` — `LocalSquatBenchAlgorithm` calls native
  `nativeProcess` in the bundled native algorithms library.
- `domain/deadlift`, `data/ml` — deadlift uses TFLite models (below).
- `presentation/calibration` — a calibration flow exists.
- `data/camera`, `data/video`, `domain/video` — records video of sets.
- Storage: Realm (local), Supabase (backend), Vercel (some API).
- Large `sessionfeedback` UI.

## Bluetooth (observed UUIDs; device identity inferred)

- Service-ish UUIDs `0000ffe5-…-00805f9a34fb`, write `0000ffe9-…`,
  notify `0000ffe4-…`, plus CCCD `00002902`.
- Note the non-standard base `…805f9a34fb` (standard is `…805f9b34fb`).
  **Inference:** this exact UUID set matches WitMotion's BLE IMU modules
  (WT901BLE / BWT901 family), which stream acceleration, gyro, angle and
  quaternion. Unconfirmed until the parsing code is decompiled.
- Three custom UUIDs (`08cf27ed-…`, `4be1123a-…`, `681236cc-…`) — role unknown.
- `258EAFA5-E914-47DA-95CA-C5AB0DC85B11` is the WebSocket handshake GUID, not BLE.

## Squat / bench algorithm (observed symbols; flow inferred)

The native algorithms library is MATLAB Coder output (b_/c_ prefixes, eml_,
rt*, emxArray, CSparse). Top-level MATLAB functions:

- `preprocessing_thilina_V4` (~14 KB code)
- `postprocessing2` (~43 KB code)

Helpers used: `quat2rotm`, `butter`, `filtfilt`, `cumtrapz`, `detrend`,
`movmean`, `median`, `interp1`, `diff`, `sparse` + `mldivide`/`qrsolve`, `eig`.

Inferred pipeline: sensor quaternions → rotation matrices → rotate
acceleration into world frame → remove gravity → Butterworth zero-phase
filter → integrate (cumtrapz) to velocity → detrend/drift removal (sparse
least-squares) → rep segmentation and per-rep metrics in postprocessing.

## Deadlift (observed model metadata)

Two TFLite models in `assets/deadlift/`, both at 200 Hz:

- `unet_detrend_2026-04-26` — input 2000 samples of vertical velocity (m/s),
  output reconstructed velocity (m/s). Learned drift correction.
- `tcn_rep_seg_2026-04-28` — input 1000 samples of velocity
  (`velocity_mode: nina_corrected_new_model`), output per-sample lift
  probability. Learned rep segmentation.

Matches the vendor's published account (deadlift shock spikes,
encoder-calibrated).

## Next

1. Decompile Kotlin (Java + jadx-headless-mcp) → BLE packet format,
   calibration, how `nativeProcess` inputs/outputs are shaped.
2. Decompile the native algorithms library (Ghidra) → exact preprocessing
   steps and constants.
