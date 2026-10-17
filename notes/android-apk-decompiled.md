# Reference Android app 0.0.26 — decompiled findings

Target: `targets/reference-android.apk` (sha256 37b2643f…3f215).
Decompiled with jadx 1.5.6 to `targets/decompiled/` (not committed).
Raw REA `inspect-android-package` output and the class list are kept locally
in `targets/rea-output/` (not committed).
All findings are static reading of shipped code; nothing was executed.
Paths below are relative to the app's main package under
`targets/decompiled/sources/`.

## 1. Sensor hardware — WitMotion BLE IMU (observed)

Source: `data/ble/nativestack/WitBleUuids.java`, `WitGattSession.java`,
`WitMotion61FrameToSensorData.java`, `WitMotion61FrameParser.java`,
`data/ble/WitMotionVendorCommands.java`, `WitMotionCalibrationCommands.java`.

- GATT: service `0000ffe5-0000-1000-8000-00805f9a34fb`, notify `…ffe4…`,
  write `…ffe9…` (same `…9a34fb` base), CCCD `00002902-…-00805f9b34fb`.
- Every device not identified as the in-house encoder is treated as WitMotion.
- Setup writes (WitMotion `FF AA <reg> <lo> <hi>` register protocol):
  - `FF AA 03 0B 00` — return rate 200 Hz (sent ~750 ms after connect)
  - `FF AA 1F 02 00` — bandwidth 188 Hz
  - `FF AA 01 01 00` — accelerometer "flat surface" calibration (user-triggered)
  - `FF AA 27 64 00` — read battery register 0x64, polled every 30 s
- Stream: bytes are buffered and resynced on header `0x55`. Frame types:
  - `55 61` — 30-byte data frame:
    | bytes | field | scale |
    |---|---|---|
    | 2–7 | chip time YY MM DD hh mm ss | |
    | 8–9 | milliseconds (uint16 LE) | |
    | 10–15 | accel x,y,z (int16 LE) | /32768 × 16 g |
    | 16–21 | gyro x,y,z (int16 LE) | /32768 × 2000 °/s |
    | 22–29 | quaternion w,x,y,z (int16 LE) | /32768 |
  - `55 71 64 …` — register reply; battery voltage = int16 LE at bytes 4–5 / 100,
    mapped to % by a step table (3.96 V → 100 %, 3.4 V → 5 %).
- **Inference:** a WitMotion BLE 5.0 9-axis module that emits 0x61 frames
  with timestamps and quaternions (e.g. WT901BLE / WT9011DCL family). The
  exact model is not named in the code.

## 2. In-house encoder — reference device (observed)

Source: the encoder's BLE UUID, GATT session and scanner classes in
`data/ble/nativestack/`, plus `TransducerReadingCodec.java`.

- Detected by advertised service `681236cc-6c02-4118-a610-a44f913fb61f` or a
  device name starting with the vendor's "… Encoder" prefix.
- Write `4be1123a-…` = isRecording (1 byte 0/1). Notify `08cf27ed-…` =
  readings: packed 5-byte records, signed 20-bit value + 20-bit timestamp
  (with wrap correction).
- **Inference:** this is the linear encoder the vendor describes building for
  deadlift calibration, used for ground-truth data collection. Consumer users
  get the WitMotion IMU.

## 3. Squat & bench — native MATLAB library

Source: `data/algorithm/LocalSquatBenchAlgorithm.java`; the native algorithms
library under `lib/*/` (MATLAB Coder output).

- `nativeProcess(accX, accY, accZ, q0, q1, q2, q3, timestampsMs, exercise, totalTimeNs)`
- Returns `RawResult`: rep count, per-rep `meanVelocities`, `peakVelocities`,
  `startTimesSec`, `endTimesSec`, `rom`, full `velocity` trace, plus 2 scalars.
- Inside (from symbols, flow inferred): `preprocessing_thilina_V4` →
  `postprocessing2`, using quat2rotm, butter/filtfilt, cumtrapz, detrend,
  movmean, median, interp1, sparse least squares. Exact constants need Ghidra.
- Kotlin preprocessing before the call: `domain/preprocessing/*`
  (chip-time parsing, timestamp rescaling, downsampling, axis mapping) — not
  yet read in detail.

## 4. Deadlift — Kotlin + two TFLite models (observed)

Source: `domain/deadlift/DeadliftTcnPipeline.java`,
`DeadliftSignalProcessing.java` (hand ports of SciPy uniform_filter1d,
gaussian_filter1d, find_peaks/prominence → designed in Python).

Constants: 200 Hz (dt 0.005 s), g = 9.81, min rep 0.3 s, max rep 8 s, rep
merge gap 2 s, min peak distance 0.5 s, prominence fraction 0.05, etc.

Pipeline (`process`):
1. **Vertical acceleration:** rotate the accelerometer vector by the sensor
   quaternion and take world-Z (third row of the rotation matrix), subtract
   1 g, × 9.81 → m/s².
2. **Bias removal:** subtract the mean of the first 20 samples (0.1 s).
3. **Integrate** (rectangular, dt 0.005) → raw vertical velocity.
4. **"Nina" U-Net detrend:** sliding windows of 2000 samples, stride 100,
   overlap-averaged → reconstructed velocity.
5. **Corrected velocity:** find rep regions on the reconstructed signal; in
   each, take the raw velocity and swap its linear endpoint trend for the
   reconstructed one's (keeps raw shape, borrows the model's drift).
6. **TCN rep segmentation:** normalise (mean 0.00815, std 0.2233), sliding
   1000-sample windows → per-sample lift probability; smooth (Gaussian
   0.05 s), take gradient, pair rise/fall events → rep start/end times.
7. **Per-rep metrics ("silver"):** on the raw integrated velocity between
   start and end, subtract the straight line joining the endpoints (assume
   bar is still at both ends), then mean |v| and peak |v|.

## Not yet examined

- Native library: fully traced. Preprocessing and filters are in §8, rep
  detection in §6, velocity-profile features in §7.
- `domain/preprocessing/*` detail, calibration screen, RPE learning,
  Supabase/Vercel backend calls, video recording.

## 5. Squat & bench native library — Ghidra pass (12 Oct 2026)

Ghidra 12.1.4 via REA `decompile --provider ghidra`, x86_64 copy of the
native algorithms library (sha256 0510706e…f4c3). Pseudocode saved in
`targets/native/{jni,preprocessing,postprocessing,butter,b_butter}.c`
(not committed). Addresses use Ghidra's 0x100000 image base.

Entry (`nativeProcess`, 0x15be50): compares the exercise string, then
`postprocessing2_initialize` → `preprocessing_thilina_V4` →
`postprocessing2`, and builds `RawResult(int, double[]×6, double, double)`.

Preprocessing (0x1477f0), observed call order:
1. `quat2rotm` — quaternion → rotation matrix (orientation of the bar).
2. Three rounds of `median` + `detrend` — remove per-axis offset/linear drift.
3. Sample-rate derived values; constants 1000 (ms→s), 3000, 9.81.
4. `butter` + `filtfilt` with cutoff `10.0 / (fs × 0.5)`. Coefficient pattern
   b ∝ [1 −6 15 −20 15 −6 1] → **6th-order Butterworth high-pass, 10 Hz**
   (observed). It feeds the spike gate in §8.
5. `b_butter` + `b_filtfilt` with band `[0.25, 4.0] / (fs × 0.5)`; b ∝
   [1 0 −4 0 6 0 −4 0 1] → **4th-order Butterworth band-pass 0.25–4 Hz**
   (observed). Applied to two signals.
6. A hard-coded 8th-order filter (b ≈ 1.44e-4·[1 0 −4 0 6 0 −4 0 1], a = [1,
   −7.370, 23.796, −43.960, 50.827, −37.665, 17.470, −4.637, 0.539]) next to
   `sparse`/`sparse_mldivide`. Confirmed in §8: it is the 0.25–4 Hz
   band-pass with its coefficients fixed for 100 Hz, applied to vertical
   acceleration through MATLAB `filtfilt`'s sparse initial-condition solve.
7. `movmean` smoothing (3 calls), `linspace` time base, then `cumtrapz` ×3 —
   trapezoidal integration to velocity.

Postprocessing (0x13b970, ~6.4k lines): rep detection and per-rep metrics.
Constants seen: 0.05 thresholds, 0.75/0.325 fractions of a peak, −0.85
weighting, −0.03 break condition, 500 / 100 sample-count guards, `diff`,
`interp1`, `cumtrapz`, `unique`. Rep rules traced in §6.

## 6. Squat & bench rep detection — `postprocessing2` traced (12 Oct 2026)

Static reading of the saved Ghidra pseudocode `targets/native/postprocessing.c`
(evidence `ev_d71a8cdc…8366`, function 0x13b970) and the JNI wrapper
`targets/native/jni.c` (`ev_a22f297e…3a91`, 0x15be50). Constant tables were
read straight from `libalgorithms_x86_64.so` (sha256 0510706e…). Ghidra is not
configured at first; the call site was checked in assembly later (see Inputs). Line numbers
below are in `postprocessing.c`. Nothing was executed.

### Inputs (call-site mapping: observed, with one caveat)

From the JNI call and the preprocessing signature:

- `v`: vertical bar velocity, the first `cumtrapz` output of
  `preprocessing_thilina_V4`. **Confirmed in assembly** (`ev_89ba9e5f…5a1b`,
  call at 0x15c4c8): `RDI = [rsp+0x10]`, then `MOV RSI, RDI`, so both
  velocity arguments are the same array. `XOR EDX, EDX` gives
  `targetReps = 0`. XMM0 = resample factor, XMM1 = `fs`, XMM2 = `totalTimeNs`.
- `fs`: sample rate from preprocessing (also returned as `meanFrequencyHz`).
- `T`: `totalTimeNs`, divided by 1e9 inside (line 4255).
- `exercise`: the string from Kotlin.
- `targetReps`: an int64 that JNI passes as a literal `0`.
- Two more `cumtrapz` outputs (the other axes) are used only for ROM and
  bar path.

### Exercise switch (observed)

`b_strcmp` compares `exercise` to four literals (inline byte compares at
0x1501a0): `Deadlift (conventional)`, `Deadlift (sumo)`, `Deadlift (trap bar)`
and `Deadlift (stiff legged)`. `any()` of those selects one of two constant
sets (tables at 0x1060e0, 0x106090, 0x105f80):

| constant | deadlift | squat / bench |
|---|---|---|
| `hi` — start threshold (m/s) | 0.10 | 0.06 |
| `lo` — release threshold (m/s) | 0.07 | 0.01 |
| `f` — min size vs. largest rep | 0.30 | 0.40 |

So this MATLAB code also supports deadlifts, but the app uses the Kotlin
TCN pipeline for those (§4).

### Algorithm (observed control flow; MATLAB 1-based indexing)

1. **Find candidate up-phases, with hysteresis** (lines 348–440). Scan `v`.
   When `v(i) > hi`, a phase starts. Its start is the last sample before `i`
   with `v < lo` (or 1). Its end is the first sample after `i` with `v < lo`
   (or `N` if none). Scanning resumes after the end. If there are no phases,
   the result is 0 reps.
2. **Drop incomplete phases** (lines 495–705). Phases whose end is `N`
   (still moving when the recording stopped) are removed, then
   `unique()` is applied to the starts and to the ends.
3. **Size filter** (lines 705–1090). For each phase, `S_k = sum(v(start:end))`
   (sum of samples; ×1/fs would make it displacement). A phase is kept only
   if `S_k > f · max(S)`. Squat/bench keeps phases at least 40 % the size of
   the largest; deadlift keeps 30 %.
4. **Require a descent first: squat/bench only** (lines 1090–1430).
   - Let `v⁻ = v` with every sample `> 0.05` set to 0.
   - For each kept phase, `D_k = sum(v⁻)` over the gap before it. For the
     first rep the gap is the last 500 samples before its start, or from
     sample 1 if the start is under 500. For later reps it runs from the
     previous rep's end to this start.
   - The rep is dropped when `D_k > max(−0.5 · max(S), −5)`.
   - In plain terms, an up-phase only counts if a downward phase at least
     half the size of the biggest rep preceded it (that requirement is capped
     at 5 sample-units). This rejects re-racking and lifting the bar out of
     the hooks.
5. **Match a target rep count**: inactive in this build (lines 2398–4250).
   If `targetReps > 0`, the code drops the rep with the smallest `S` while
   there are too many. While there are too few, it lowers `f` by 0.001 and
   reruns steps 1–4, giving up below 0. JNI passes 0, so the count is just
   the number of reps that survive step 4.
6. **Per-rep outputs** for each rep `[s, e]`:
   - `meanVelocities`: `mean(v(s:e))` (line 1639).
   - `peakVelocities`: `max(v(s:e))` (line 1572).
   - `startTimesSec`: `s / N · T`. `endTimesSec`: `e / N · T`
     (lines 4255–4420).
   - Eccentric start, used only for ROM (lines 4510–4595): from `s − 5`,
     walk back to where `v ≤ −0.1`, then on while `v < −0.03`, then on along
     a `movmean`-smoothed `v` while it keeps falling and stays negative.
     The walk never passes the previous rep's end.
   - `rom` (lines 4640–5100, re-read 12 Oct while porting): `cumtrapz` of
     the **raw** `v(ecc_start : e)` divided by `fs` gives position. Then
     ROM = position at `e` − position at the sample *just after* the
     minimum (the code reads `a68(argmin + 1)`). The endpoint-line-detrended
     copy of the segment is integrated too, but only feeds the bar path.
     ROM is only computed when the other-axis velocity arrays are
     non-empty; otherwise `rom` comes back empty.

### Computed but not returned to Kotlin (observed)

`postprocessing2` also produces outputs that the JNI wrapper discards:

- A per-rep 100×2 bar path from the other two axes, detrended the same way.
- The fraction of ROM spent below 50 % of peak velocity. This uses velocity
  resampled to 1 %-of-displacement steps, with `interp1` at line 1834 and
  `/100` at line 1977.
- The sticking-region features from the velocity profile, traced in §7.
- A constant output of 200.0 (line 6360).

### Confidence and gaps

- **Observed:** thresholds, exercise strings, step order, the comparison
  operators, which arrays feed which JNI output, and the call-site arguments
  (assembly).
- **Inferred:**
  - That `combineVectorElements` is `sum`. It is MATLAB Coder's helper for
    `sum`, and the code divides by the count separately to get the mean.
  - The physical reading of `S_k`/`D_k` as displacement.
  - The re-rack interpretation of step 4.
- **Unknown:**
  - Exact off-by-one details at segment edges.

## 7. Velocity-profile ("sticking region") features — traced (12 Oct 2026)

Source: `targets/native/postprocessing.c` lines 1700–2300, the same code
repeated at 3700–4240 for the retry loop. The window sizes come from fresh
Ghidra decompiles through REA: `movmean` 0x13b090 (`ev_af75524d…5a84`) and
`b_movmean` 0x13a7d0 (`ev_73a5bd87…755c`). All of this is static reading.
**None of these features reach Kotlin.** They are written to
`postprocessing2` outputs `param_13`–`param_21`, which the JNI wrapper
frees without reading.

### Profile built per rep (observed)

For rep `[s, e]`:

1. `d = cumsum(v(s:e))` gives cumulative displacement in sample units.
   `unique()` then drops flat stretches (lines 1690–1729).
2. Resample velocity onto a displacement axis:
   `P = interp1(d, v, (1:100)·d_end/100)`. `P(j)` is the bar velocity at
   j % of the rep's ROM (lines 1732–1834).
3. `Ps = movmean(P, 5)`, a centred 5-point window (±2 % ROM) that shrinks
   at the ends.
4. `D = sign_clip(movmean(diff(P), 5))`: each slope becomes `−1` where the
   smoothed profile is falling and `0` otherwise.

### Simple feature (observed)

- **`param_13`: fraction of ROM below half speed** =
  `count(P < 0.5·max(P)) / 100` (lines 1843–1977). It uses the profile
  maximum, not the raw sample peak.

### State machine over j = 1…100 (observed control flow, lines 2085–2296)

1. **Wait for the first deceleration.** At the first `j0` with `D(j0) = −1`,
   find the peak velocity before it in the raw samples:
   `M = max(v(s : s + L − 1))`. Here
   `L = min(round((j0+1)/100 · nRep) + 10, nRep)` and `nRep = e − s + 1`.
   That maps % of ROM to a sample count as if speed were uniform, plus a
   10-sample margin. Then set `hi = 0.75·M` and `lo = 0.325·M`.
2. From `j0` on, record these profile positions (as % ROM):
   - **`stickStart`** (`param_18`): first `j` where `Ps(j) < hi`, meaning
     velocity has dropped below 75 % of the pre-deceleration peak.
   - **`lowStart`** (`param_19`): after that, first `j` where `Ps(j) < lo`
     (below 32.5 %). This is only checked before `stickEnd` is found.
   - **`vMinPos`** (`param_16`): after `stickStart`, first `j` where
     `D(j) = 0`, meaning the profile stops falling (local velocity minimum,
     the classic sticking point). The same step also records
     **`midDecel`** (`param_17`) = `(j0 + vMinPos) / 2`, halfway between the
     onset of deceleration and the minimum.
   - **`lowEnd`** (`param_20`): if `lowStart` was set, the first `j` after
     `vMinPos` where `Ps(j) > lo` or `D(j) = −1`, meaning velocity climbs
     back above 32.5 % or starts falling again.
   - **`stickEnd`** (`param_21`): otherwise, the first `j` after `vMinPos`
     where `Ps(j) > hi` or `D(j) = −1`, meaning velocity regains 75 % or a
     second dip starts.
   - **`stickLen`** (`param_14`): `stickEnd − stickStart`, the length of the
     sticking region in % of ROM.
3. If `stickEnd` is never found, `stickStart` and `lowStart` are reset to 0.
   `param_15` is always 0, which looks like a placeholder.

**Inference:** this is a sticking-region detector in the style of the
powerlifting literature. The region runs from where velocity first falls
below 75 % of its early peak to where it recovers, with the minimum in
between. It also flags a severe slowdown band below 32.5 %. It is written
for squat/bench grinders. The app currently throws all of it away, so it is
probably an unreleased feature.

### Other constants placed (observed)

- **−0.85** (0x105f90, line 4811): in the bar-path block,
  `x ← x − 0.85 · linear(x_start → x_end)`. This removes 85 % of the
  endpoint-to-endpoint drift from the horizontal path. It has nothing to do
  with the profile.
- **`b_movmean`** = MATLAB `movmean(v, 20)` (window i−10…i+9). It is used
  only in the eccentric-start search (§6, step 6).

### Gaps

- Indices above are 1-based % positions as the code stores them. Edge cases,
  such as a phase that ends exactly at the last profile point, were not
  exercised.
- Whether the vendor plans to show these features is unknown. There are no
  Kotlin readers of them in 0.0.26.

## 8. Preprocessing filter chain — traced (12 Oct 2026)

Sources:
- `targets/native/preprocessing.c` (`preprocessing_thilina_V4`, 0x1477f0,
  `ev_3135a082…aadbe`).
- Assembly from `rea function` (saved to the session scratchpad, not
  committed).
- Fresh decompile of `c_movmean` 0x13a8f0 (`ev_a59d593f…ae3c`).
- Constants read from the `.so`.

All of it is static reading.

### Signal chain (observed; line numbers in `preprocessing.c`)

Inputs: accX/Y/Z (g), quaternion q0–q3, `timestampsMs`.

1. **Timing** (lines 231–282):
   - `t = timestampsMs − t₀`.
   - `fs = N / (t_end / 1000)`, the mean sample rate. It is returned as
     `meanFrequencyHz`.
   - `resampleFactor = N / 3000`. It is returned as is; its meaning is
     unknown.
2. **World frame** (lines 496–530): `quat2rotm(q)`, then rotate each
   accelerometer sample into the world frame (an N×3 array).
3. **Remove gravity and offsets** (lines 530–800):
   - Vertical `a_z = world_z − 1 g`.
   - Each axis has its median subtracted, then `detrend` (linear).
   - The other two axes are the horizontal `a_x`, `a_y`.
4. **Tilt value (unused)** (lines 856–910):
   `sqrt(median(world_x(1:200))² + median(world_y(1:200))²)`. This is
   leftover horizontal gravity over the first ≤200 samples, which tells you
   how well the orientation is aligned. It goes to an output (`param_16`)
   that JNI never reads.
5. **Filters, per axis** (lines 911–1173):
   - `HP` = 6th-order Butterworth high-pass at 10 Hz, designed at runtime
     from `fs`, run with zero-phase `filtfilt`.
   - `BP` = 4th-order Butterworth band-pass at 0.25–4 Hz, zero-phase.
   - Horizontal axes design `BP` at runtime (`b_butter`) from `fs`.
   - **Vertical axis uses hard-coded coefficients** (lines 976–1036):
     `b = 1.4412e-4·[1 0 −4 0 6 0 −4 0 1]`, `a = [1 −7.3703 … 0.5394]`.
     Computing the frequency response puts the −3 dB edges at exactly
     0.0025·fs and 0.04·fs. That is **0.25–4 Hz only when fs = 100 Hz**
     (0.5–8 Hz at 200 Hz). Inline `sparse`/`sparse_mldivide` is MATLAB
     `filtfilt`'s initial-condition solve. `ffOneChanCat` (N < 10000) and
     `ffOneChan` are its forward/backward passes.
6. **Spike gate** (lines 1219–1905), on each axis:

   ```
   E = movmean(|HP| − |BP|, 9)         % centred 9-sample window
   where E(i) > 0.1 g:  a(i−1), a(i), a(i+1) := 0
   ```

   This zeroes acceleration where high-frequency content (above 10 Hz)
   outweighs the movement band (0.25–4 Hz) by more than 0.1 g. **Inference:**
   it suppresses impacts such as plates clanging, the bar hitting the
   safeties or racking, and bounce at the bottom of a rep, so those don't
   turn into velocity drift. **The band-passed signals are used only here;
   they are never integrated.**
7. **Resample and integrate** (lines 1916–1927):
   - The gated `a_z`, `a_x`, `a_y` are interpolated onto a uniform grid
     (`linspace(min t, max t, N)`).
   - `cumtrapz` with unit step gives g·samples.
8. **Drift removal and units** (lines 1928–2200; window arguments read from
   assembly at 0x14a609–0x14abd8):
   - `W = round(fs)` (one second); `fs/9.81` is constant 0x105cb8.
   - Each velocity: `v = (∫a − movmean(∫a, k·W)) / (fs/9.81)`, in m/s.
   - The horizontal axes and the **vertical velocity returned to the app**
     use `k = 5`, a 5-second moving average.
   - Vertical variants with `k = 1, 2, 3` are also computed (`param_9`–`11`,
     multiplier 3.0 at 0x105df8). JNI frees them unused.

### What this means for squat/bench velocity (inference)

- **Drift handling** is a 5-s moving average subtracted from the integrated
  velocity. There is no zero-velocity update.
- The per-rep linear detrend in postprocessing (§6, ROM) and the "bar is
  still at rep boundaries" assumption do the rest.
- The 10 Hz high-pass doesn't filter the velocity at all. It is only a
  detector that tells the gate which acceleration samples to zero.
- **Likely bug:** Kotlin passes full-rate data, with no downsampling on the
  local path (§9). The sensor is configured for 200 Hz (§1), so the
  vertical gate's band-pass is really about 0.5–8 Hz while the horizontal
  axes get 0.25–4 Hz. The rate actually delivered over BLE is only known at
  runtime, since `fs` is estimated from timestamps.

### Gaps

- `resampleFactor = N/3000` is resolved: nothing in Kotlin reads it (§9).
- The rate reaching native code is full rate, with no downsampling (§9).
  The actual BLE rate needs a recording.
- The gate's exact neighbour handling on the horizontal axes, which looks
  like `i, i+1` (and possibly `i−1`) but wasn't fully unrolled.

## 9. Kotlin squat/bench path — which pipeline runs (12 Oct 2026)

Sources:
- `domain/usecase/CompleteSetAfterRecordingUseCase.java` (`processSquatBench`,
  around line 790).
- `domain/usecase/ProcessSquatBenchRecordingLocallyUseCase.java`.
- `domain/preprocessing/SquatBenchSensorMotionMapper.java`.
- `domain/preprocessing/SquatBenchMotionDownsampler.java`.

All static reading of jadx output.

### Server first, native as fallback (observed)

`processSquatBench`:

1. Estimates the mean sample rate (`RecordingSampleRateEstimator`).
2. Calls **`ProcessSquatBenchRecordingWithVercelUseCase`**, which processes
   the set on the vendor's server. A non-empty result is used as is
   (`VERCEL_OK`). An empty result is kept and persisted as `VERCEL_EMPTY`;
   the local fallback is **not** tried in that case.
3. **Only if the Vercel call throws** does it run
   `ProcessSquatBenchRecordingLocallyUseCase`, i.e. the native MATLAB library
   (§5–8). The outcome is tagged `VERCEL_FAILED` and the failure goes to the
   crash reporter.

So the native library traced in §5–8 is the **offline fallback**. The
primary squat/bench algorithm runs server-side and is not in the APK.
**Inference:** the server probably runs the same MATLAB code (same function
names, and the Vercel path reuses the same mapper), but that can't be
confirmed statically.

### What the local path feeds the native code (observed)

`SquatBenchSensorMotionMapper.map`:

- Drops samples whose quaternion or accelerometer is all zeros.
- Timestamps come from the WitMotion **chip time** (`SquatBenchChipTimeParser`)
  relative to the first valid sample, falling back to the phone timestamp.
- **Gap repair:** any step `≤ 0` or `> 2 s` is replaced by the median step,
  or 0.005 s (200 Hz) if no median is available.
- **Host-clock rescale:** `TimestampRescaler` stretches chip time to match
  the phone's span. If the factor is outside 0.5–2 and the rescale wasn't
  applied, it uses a uniform timeline over the host span instead.
- **No downsampling.** Kotlin passes `round(t·1000)` ms timestamps and
  `totalTimeNs = t_last · 1e9`.

`SquatBenchMotionDownsampler` (`TARGET_LENGTH = 12000`, linear resample,
factor `size/12000`) is used only by the Vercel path and
`BuildSetVelocityTraceUseCase`, and only when there are more than 12,000
samples (about 60 s at 200 Hz).

### What Kotlin keeps from `RawResult` (observed)

- **Kept:** `repCount`; per-rep `startTimesSec`/`endTimesSec`, converted to
  indices into the velocity trace (`round(t / t_last · (len−1))`);
  `meanVelocities`; `rom`; the `velocity` trace; and `meanFrequencyHz`
  (logged).
- **Not read anywhere:** `peakVelocities` on this path, and the native
  `resampleFactor`. The only reference is the `RawResult` constructor.
  `SquatBenchPreprocessResult` is built with a literal resample factor of
  `1.0`.

### Implications for our rebuild

- The local fallback defines the reference behaviour we can actually
  reproduce. The server version may differ, and this build gives no
  evidence either way.
- Native preprocessing sees full-rate (about 200 Hz) data, so the vertical
  gate's band-pass mismatch (§8) applies whenever the fallback runs.

## 10. Deadlift path — which pipeline runs (12 Oct 2026)

Sources: `domain/usecase/CompleteSetAfterRecordingUseCase.java`
(`processDeadlift`), `domain/usecase/ProcessDeadliftRecordingUseCase.java`,
and `domain/deadlift/DeadliftTcnPipeline.java`. All static reading of jadx
output. The algorithm itself is in §4.

### On-device first, native MATLAB as fallback (observed)

1. `ProcessDeadliftRecordingUseCase` runs the same
   `SquatBenchSensorMotionMapper.map` as squat/bench (§9). It then runs
   **`DeadliftTcnPipeline.process`** on the phone: the Nina U-Net
   detrend plus TCN rep segmentation (§4).
2. Outcomes:
   - Reps found: `DEADLIFT_TCN_OK`.
   - Empty result: `DEADLIFT_TCN_EMPTY`, kept as is with no fallback.
3. **If the TCN pipeline throws**, the code calls
   `ProcessSquatBenchRecordingLocallyUseCase` with the deadlift exercise
   string. That is the native MATLAB library (§5–8), which then uses the
   **deadlift constant set** from §6: start 0.10 m/s, release 0.07 m/s,
   30 % size filter, and no "descent first" check.
   - Reps found: `DEADLIFT_LOCAL_C_OK`.
   - Otherwise: `DEADLIFT_TCN_FAILED`, which is crash-reported as
     `both_pipelines_failed`.

**No server call is made for deadlifts.** Of the two flows this is the
opposite arrangement: squat/bench runs server-first, deadlift runs fully
on-device. This also explains why the MATLAB library carries deadlift
strings and thresholds.

### Timing assumptions in the TCN path (observed, with inferred consequence)

- `integrateRawVelocity` integrates with a **fixed `dt = 0.005 s`** and
  never looks at timestamps. The pipeline also returns
  `SAMPLE_RATE = 200`.
- Timestamps (after the mapper's gap repair and rescale) are only used to
  turn rep sample indices back into times (`resolveTimes`, with median
  delta and 0.005 fallback).
- There is no spike gate and no resampling. Bias is removed with the mean of
  the first 20 samples; drift is handled entirely by the Nina model.
- **Inference:** if the sensor delivers fewer than 200 samples per second
  (dropped BLE packets or a slower rate), deadlift velocities and the
  model inputs are scaled wrong in proportion: at 100 Hz, `v` comes out
  ×0.5. The rate actually delivered needs a recording to confirm.

## 11. Behaviour found while porting to Dart (12 Oct 2026)

The Dart port is in `src/barbell_app/lib/analysis/`, and synthetic-set
tests are in `test/`. Its DSP primitives were checked against known
constants: `butter(4,[0.25 4]/50)` reproduces the hard-coded native
coefficients to 1e-12. `d_movmean` was decompiled (`ev_ecfa37b9…94ae5`):
it is a plain MATLAB `movmean` (back `floor(k/2)`, forward one less for
even k).

- **Drift residual (inference, from synthetic data):** the 5-second
  moving average (§8) leaves a few cm/s of residual velocity next to
  large movements. Two consequences:
  - With a ~1.5 s standing pause between squat reps, the residual stays
    above the 0.01 m/s release threshold, so a rep's window runs on until
    the next descent.
  - With 0.5 s pauses, the window opens about 0.25 s early in the bottom
    pause, which inflates ROM by about 10–20 %.
  - The last rep of a set is unaffected.
- **Rounding in the sticking-region window:** the window uses `roundsd`
  with immediate `0b1010`, which rounds toward +∞ (ceil), not to nearest.
- **Not yet verified against the real library:** the port has never been
  run side by side with `libalgorithms`. Off-by-one details and the
  garbled first-rep descent sum (§6 step 4) are best-effort.

## 12. Load–velocity and 1RM — traced (12 Oct 2026)

Short version: Stance 0.0.26 has **no load–velocity regression and no
1RM estimate**. It plots raw points, and its 1RM records are sync plumbing
that nothing in the app creates or reads.

### Session weight–velocity chart (observed)

`SessionChartRules.buildChartData` (`domain/session`), called through
`BuildSessionChartUseCase` from `SessionFeedbackViewModel`, rendered by
`WeightVelocityChart` (`presentation/workout/sessionfeedback/components`).

- One point per set of the **current session**: x = set weight converted
  to the preferred unit (`WeightDisplayUtil.toPlotWeight`, 2.2046226218
  lb/kg), y = a mean concentric velocity picked by `SpeedChoice`:
  - `FASTEST` (default): the max of the reps' mean velocities;
  - `LAST`: the last rep's mean velocity.
- A set is dropped if `feedback` is non-empty (an analysis error/notice),
  if `setTypeTag` is `BACKOFF`, if the weight is null, or if it has no rep
  velocities.
- An optional **comparison session** goes through the same rules and is
  drawn as a second series (inference from colours: current = `Primary`
  with a selectable point, comparison = `SecondaryPrime`).
- Bounds: weight `[min·0.9 (≥0), max·1.1]`, velocity `[min·0.9 (≥0),
  max·1.1]` over both series together.
- Drawing: a polyline joining points **sorted by weight** (3 px), dots,
  and for the tapped set (nearest within 60 px Manhattan distance)
  dashed crosshairs plus `%.2f` m/s and weight labels. Tick spacing
  rounds to 1/2/5/10 × 10ⁿ (`niceTickValues`). **No fit line, no
  extrapolation, no MVT.**

### Same-weight history ("weight performance", observed)

`WeightPerformanceRules.buildPoints` via `BuildWeightPerformanceUseCase`;
the chart is `WeightMinMaxBarChart`.

- Takes every set of the same exercise (`getSessionsForExercise`) with
  **exactly the same weight** (`Double` equality) and the same canonical
  unit, a non-null start time, empty `feedback`, and ≥1 rep velocity.
- Sorts them by start time and keeps the **last 12** (`MAX_POINTS`).
- Each point is a min–max bar over that set's rep mean velocities, dated
  by the set's start. If min == max, max += 0.1 m/s (`EQUAL_RANGE_BUMP`)
  so the bar is visible.
- Shown only when the selected set has a weight; its label comes from
  `weightOrSetLabel`.

### Rep velocity lists (observed, `RealmSessionMappersKt`)

- `meanVelocitiesMps`: the reps' `meanConcentricVelocity` with nulls
  **skipped**. All the rules above use this list.
- `repMeanVelocitiesMps`: the same values with null → 0.0, aligned per
  rep. Used for rep-speed charts; `repSpeedYBounds` ignores values ≤ 0.

### 1RM (observed, bounded negative)

- `RemoteOneRepMax` / `OneRepMaxEntity` / `PendingOneRepMaxEntity` hold
  only `{id, exercise, weightKg, dateCreated}`. Supabase table
  `one_rep_maxes`: pull ordered by `date_created desc`, upsert on `id`,
  update `weight_kg`.
- References exist only in the Realm schema, the sync cache upsert, the
  offline-sync drain, the pull sync and the sync-diagnostics counter.
  Nothing outside the entity package constructs `PendingOneRepMaxEntity`,
  and no domain or UI class reads `OneRepMaxEntity`.
- **Inference:** 1RM is a user-entered value, probably set from another
  client (iOS or web) or planned for later. It is not computed on
  Android 0.0.26.
- Search boundary: jadx Java sources under `com/stancefitness`; searches
  for `OneRepMax`, `e1rm`, `estimat*1rm`, `regression`, `slope`,
  `intercept`, `mvt`, `velocityThreshold`. The native library was not
  searched for this, and the Vercel server pipeline is out of reach.

## 13. RPE learning ("Speed-Intensity Profile") — traced (12 Oct 2026)

Short version: there is no model. Stance groups the user's own RPE tags
by RPE and shows which RPEs past sets at a similar last-rep speed got.
`UpdatePredictedRpeUseCase` / `predictedRpeTag` exist, but nothing injects
the use case: a server-side or unfinished feature (bounded negative,
Java sources only).

### Profile (`BuildRpeIntensityProfileUseCase`, observed)

- Input: every set of the exercise (`getSessionsForExercise`) with
  `feedback == null` (null check, unlike §12's empty check), a numeric
  `rpeTag`, and a last `repMeanVelocitiesMps` entry > 0 (a null MCV maps
  to 0 there, so it is excluded).
- Grouped by RPE value; per group `RpeIntensityPoint(rpe, q1, q3, min,
  max, velocities)`. Quartiles: linear interpolation at `p·(n−1)`. One
  value → `(v, v+0.02)`; if q3 ≤ q1 → `(mid, mid+0.02)`. Sorted by RPE.
- Window (`buildWindow`) from the **selected set's last-rep speed** s
  (`SessionFeedbackViewModel.selectedSetLastRepSpeed`):
  `minSpeed = max(0, s−0.2s)`, `maxSpeed = s+0.2s`. A point overlaps when
  `q3 ≥ minSpeed && q1 ≤ maxSpeed`. `minRpe` = the first overlapping
  point's RPE (else 7), `maxRpe` = the last (else 9), clamped to
  [5, 10]. With no speed: window 0–1, RPE 7–9. With speed but no points:
  window ±20 %, RPE 7–9.

### Chart (`RpeIntensityProfileChart`, observed)

- x = RPE, y = speed. Zoomed in (default): x `[minRpe−0.2, maxRpe+0.2]`,
  y = the speed window (0–1 if empty). Zoomed out (animated toggle):
  x `[4.8, 10.2]`, y `[0, 1.2·max(absoluteMax)]`.
- Each logged speed is a 22 px-wide tick ±0.6 % of the y span at 70 %
  alpha. The IQR is an 8 dp rounded bar, clamped to the visible range.
  Colours come from `RpeColor` (5 → `#736984` … 10 → `#e85252`, 11
  half-step tokens in `StanceColorTokens`).
- x labels every 0.5 within 5–10. y ticks are the same 1/2/5 algorithm
  as §12. The rated set's last-rep speed is a horizontal primary line
  with a `%.2f` label. "No data to display" when empty.
- Strings (decoded from `resources.arsc`): "Speed-Intensity Profile",
  "Enter your Rate of Perceived Exertion for this set. Last rep is the
  best indicator of your RPE".

### Profile manager (`BuildRpeProfileGroupsUseCase`, observed)

- Rows: sets with `feedback == null` and a numeric RPE tag, **with or
  without** reps (lastRepSpeed may be null). Grouped by RPE, groups
  ascending. Rows are sorted by Date, Speed or Weight, all descending,
  nulls last; weight compares raw numbers across units.
- Delete clears the set's RPE tag ("Remove this RPE tag?"). Edit sets a
  new RPE ("Adjust the RPE for this set. Changes are saved
  automatically.").

## 14. Readiness — traced (12 Oct 2026)

"Today vs usual" for the **selected set** on the session feedback screen
(default: the last set). Only there; the recording screen's "Last
session" string belongs to an unrelated card.

### Query (`FetchSessionReadinessUseCase` → `HistoricalDataRepositoryImpl`, observed)

- Current speed: the selected set's **fastest** rep MCV
  (`currentSessionSpeedMps` → `maxMeanVelocityMps`). The query's
  `SpeedChoice` defaults to FASTEST and the view model never changes it.
- Defaults: `maxDaysBack = 90`, `maxResults = 12`. Empty if the set has
  no weight.
- Session filter: same `exerciseRaw`, date before the current session's,
  not the current session, and the **same session-type tag**
  (`SessionDayTypeExtractor.extractSessionType`: the first known type
  substring found in the tags, else ""). The jadx output of the
  `sets.any { compatible }` check is garbled, but the per-set match below
  re-applies it, so the result is the same.
- Per session, within 90 days: the **first** set with
  `exerciseWeight == current weight` (bare number, no unit check), blank
  feedback, and a compatible set type. Its speed is the max of its non-null
  rep MCVs. Sorted newest first, take 12.
- `SetTypeTagCompatibility`: {warm-up, last warm-up, top set} are mutually
  compatible; back-off only with back-off; otherwise equal types. An
  untagged current set matches only untagged sets.
- Result: `lastSessionSpeed` = newest; `historicAverage` = mean of all
  (including the newest), only with ≥ 2. `points` only with ≥ 2. The
  session label is "Block…" + "W…/Week…" tags joined.

### Verdict (`buildReadinessComparison`, observed)

- Needs current > 0 and last or average > 0. A difference is significant
  when `|Δ| ≥ 0.05 m/s` **or** `|Δ|/ref ≥ 5 %`.
- Last session first: significant and faster → "Last Session" (faster);
  significant and slower → "Last Session" (slower). Then the average is
  added only if it agrees with the last-session direction (or last wasn't
  added). Mixed directions → no verdict.
- No verdict for warm-up or back-off sets. Text:
  "Faster"/"Slower", "`<weight>` moved faster than Last Session and
  Historical Average."
- Numbers shown: This Session / Last Session / Average (`%.2f`, "--" when
  missing). "No historical data available". "See More" opens the history
  with `daysAgoText` (Today, Yesterday, n days ago, 1 week ago, n weeks
  ago < 30 d, 1 month ago < 60 d, else n/30 months ago).

### Strip chart (`ReadinessSpeedStripChart`, observed)

- x spans min–max of the history plus the positive current, last and
  average values, each rounded to 2 dp (span 0.1 if flat). A 24 dp track
  at 4 % white. History: grey 2 dp bars. Average: dashed 4 dp line.
  Last session: 4 dp bar. Current: 6 dp primary bar. Min and max labels
  `%.2f`.

## 15. Set and session comparison — traced (12 Oct 2026)

### Choosing the comparison session (observed)

- `getAvailableComparisonDates(exercise, currentId, currentDate, tags)`:
  returns **nothing unless the current session has a session-type tag**
  (`extractSessionType` non-empty). Otherwise: same-exercise sessions
  before the current date, not the current one, with the same session
  type, newest first, de-duplicated by local calendar day.
- `getSessionForComparison(exercise, day)`: the first Realm match whose
  date falls on that local day (Realm order, so probably the earliest
  stored).
- View model: the default is the newest date. A previous selection is kept
  if its day is still listed. An empty list means no comparison session.
- `getComparisonSession` (newest other session with ≥ 2 sets) exists but
  has no callers (bounded negative).

### Views (`ComparisonViewType` = CHART, TABLE, REPS; observed)

- **Chart**: the §12 weight–velocity chart with the comparison series.
- **Table** (`SessionComparisonTable`): for the current and the
  comparison session, every set as Set #, Type (short name or "--"),
  Weight, Reps (count), Speed (m/s) (`%.2f` of fastest or last rep MCV per
  `SpeedChoice`, "0.00" without reps), RPE ("-" when blank).
- **Reps** (`RepSpeedComparisonRow`): the current session only. One small
  card per set (weight label, start time, rep velocities) in a horizontal
  list, on a shared y range `repSpeedYBounds`: positive rep MCVs,
  `[max(0, min·0.9), max(max·1.1, lo+1e-9)]`, else 0–1.
- Controls: "Compare:" date picker ("Current session only", "No previous
  sessions to compare"), Fastest/Last, "No comparisons for rep speed",
  "No previous sessions available".

### Set rep chart (`buildRepChartUi`, `RepVelocityChart`, observed)

- The selected set's rep MCVs (null → 0) as a Catmull-Rom line with dots
  (primary). The optional compare set is drawn the same way underneath
  (secondary). Compare options are every other set of the session in
  reverse order ("None" to clear).
- y range: 10 % below the lowest positive value to 10 % above the max
  (unless given). x = rep 1…n. Insets 44 / 8 / 8 / 28. Labels "Reps",
  "m/s".
- Detail sheet: "Max speed" = max MCV, "Avg speed" = mean MCV (`%.2f`,
  "--" when 0); per-rep Rep / Mean / Peak.

## 16. Navigation and workout flow — traced (17 Oct 2026)

One Compose `NavHost` (`NavGraphKt.StanceNavHost`), start route `home`.
There is no bottom tab bar. Settings, Preferences and Device are pushed
screens with iOS-style push transitions. The `recording`, `calibration`
and `device_stream` routes exist in `MainRoutes`, but only Device Stream
is reachable (debug menu). Auth and onboarding sit above this graph in
`RootDestination` and are out of scope.

### Routes and transitions (observed, `NavGraphKt`, `WorkoutRoutes`)

| From | Action | To |
|---|---|---|
| `home` | tap exercise | `workout_sessions/{exerciseId}` |
| `home` | top-bar device button / menu | `device`, `preferences`, `settings` |
| sessions | "New Session" | `workout_weight/{ex}`; new session group id, `postSetReturnToExistingFeedback = false` |
| sessions | tap a card's button | `workout_session_feedback/{ex}/{session}?isActive={card is active}` |
| weight | "Continue" (weight + set type) | `workout_pre/{ex}`; draft carried in `WorkoutNavBridge.weightToPreDraft` |
| pre | set saved and analysed | first set: feedback with `isActive=true`, `popUpTo(sessions)` (back from feedback → sessions list). Later sets: pop back to the existing feedback, removing weight and pre. |
| pre | invalid context | back to `weight`, popping pre |
| feedback | "New set" (active only) | `workout_weight/{ex}`; group id = this session, `postSetReturnToExistingFeedback = true` |
| feedback | back | pops; when active, clears the session group id |

Every workout screen uses `WorkoutTopBar` (back + small device-status
button → `device`). `popBackStackOrHome` falls back to `home`.

### Active session (`ActiveSessionPolicy`, observed)

Stance has no "finish session" action. A session for an exercise is
active when it is the newest one, its last set ended on the same local
day, and less than 1 hour ago. The session list labels that card's
button "Continue" (opens feedback with `isActive=true`) and every other
card "View" (`isActive=false`).

### Screens (observed; strings from `resources.arsc`)

- **Home**: title "Exercise", subtitle "Select an exercise to start a
  workout.", then the exercise list (deadlift shows a tips block). Top bar
  has a menu (Preferences, Settings, user details, sign out) and the device
  status button. Also: an "Import recording" card (§ CSV import TODO).
- **Sessions** (per exercise): title "Sessions", "New Session" button,
  cards newest first. Each card shows the time range ("%s – %s"),
  "%d sets · %d reps", "Avg bar speed: %.2f m/s", a tags row, a sets
  table, and a "Continue"/"View" button. Empty state: "No sessions yet
  for this exercise." / "Tap new session to start collecting data."
- **Weight input**: "Input weight", subtitle "Choose Set Type to view your
  readiness before your Working set.", a Weight field (starts empty every
  time), a set-type choice (Warm up / Last Warmup / Top set / Backoff, no
  default), "This value is saved in kilograms (kg)" — the unit comes from
  Preferences and is not switchable here. "Continue" is enabled only with
  a valid weight and a set type.
- **Pre-recording**: camera preview with a pill to arm video, a guide
  ("Tips"), "Start Set" ↔ "Stop" with a running timer (1 s tick). After
  Stop: "Saving your set and preparing results…", then "Analysing your
  set" with a 60 s countdown bar ("%ds left", then "Taking longer than
  usual"; "You can leave this screen — your set will still be saved.").
  Errors: no data ("No sensor data was recorded…"), stream watchdog,
  "Reconnect sensor" (6 s scan timeout). On success it navigates on its
  own; there is no per-set results page.
- **Session feedback** (one screen for live and past sessions):
  `BottomSheetScaffold`.
  - Body: top bar (back, device, guide "?"), exercise title, day-type tag
    dropdown, comparison controls (Chart/Table/Reps, date, Fastest/Last),
    then the comparison section. Tapping a chart point selects that set.
  - Persistent bottom sheet (partially expanded, peek 214 dp + 40 when
    readiness shows a message + 50 when active + 70 when the set needs
    reprocessing), about the **selected set** (default: last):
    set selector (chips, plus Edit and Copy-ID actions) → reprocess
    banner → **"New set"** primary button (active only) → readiness mini
    card → video button → RPE card → rep-velocity mini card.
  - Each mini card opens a modal sheet: readiness detail, rep speed detail
    (with weight-performance), video player, RPE (slider + profile chart),
    RPE profile manager and edit, Edit Set (weight, set type, reps,
    delete, 7-day edit window), Rep Check, Report Issue.
  - RPE is never prompted automatically; the user opens the RPE card.
  - A "What type of session are you doing today?" tag overlay shows when
    the session has no day type (session tags TODO).

## 17. Feedback extras: edit, rep check, report, guides — traced (17 Oct 2026)

### Edit Set (`FeedbackEditSheet`, observed)

Tabs **Details** (Weight, Set Type or "Not set", Copy Set ID, Report
Issue, Delete Set) and **Reps**. The Reps tab has an edit-timer pill, a
"Total reps" field, "If the rep count isn't correct then edit and tap
recalculate.", "Recalculate" and "Check Reps".

- Edit window (`SetEditWindowRules`): 7 days (604 800 000 ms) from the
  set's end; `remainingMs = max(0, end + 7 d − now)`. Pill: "%s left to
  edit", where `formatRemaining` is "Under 1 min" below a minute, else the
  first two non-zero of `Nd`, `Nh`, `Nm` joined by a space. At 0: "Edit
  Expired" and rep edits show "Edit Window Expired — Sorry, you can no
  longer edit your reps. Sets can only be edited for 7 days after
  recording."
- **Recalculate** (`CorrectRepCountUseCase`): only fewer reps. Needs the
  stored velocity trace (else "Rep editing isn't available for this set…").
  If `desired <= 0 || desired >= current`: "Can't Find More Reps" ("Sorry,
  we can't find more reps. You can manually add more reps in the Check
  Reps view."; deadlift: without the second sentence). Otherwise removes
  the `current − desired` reps with the smallest ROM (stable sort by ROM
  ascending) and keeps the rest in order. Saved at once.

### Rep Check (`RepCheckSheet`, `EditRepMarkersUseCase`, observed)

"Check each rep against the velocity chart. Drag a marker to adjust its
start and end, or add and delete reps, then save your changes." Markers
are (startSec, endSec) per rep on the set's velocity trace.

- Add: move the scrubber, "Set start time", then "Set end time", then
  "Add Rep". Validation (`validateAddTime`), per existing rep N, in order:
  time strictly inside → "Start/End time cannot be inside Rep N"; for the
  end: start < rep.start and end > rep.end → "New rep cannot encompass Rep
  N"; start strictly inside → "New rep cannot overlap with Rep N". End ≤
  start → "End time must be after start time". Errors show in an "Error"
  dialog. Delete asks "Are you sure you want to delete Rep %d? This action
  cannot be undone." Add and delete are saved at once; moved markers on
  "Save". Closing with moved markers asks "Unsaved Changes" (Save /
  Discard).
- Commit: any marker with end ≤ start → invalid. Markers are sorted by
  start. Per marker: `mean` = average and `peak` = max of the trace slice
  `[indexAt(start), end ≥ duration ? n : indexAt(end))` (empty slice → 0);
  ROM and sticking region are kept only when start and end both equal an
  existing rep's, else ROM 0 and no sticking. `indexAt` on a uniform axis
  is `clamp(floor(sec / secondsPerIndex), 0, n − 1)`.

### Report Issue (`ReportIssueSheet`, observed)

"Feedback — Does the data look correct?" Yes / "No, something doesn't look
right" (No preselected when the set has a note). "Notes — Let us know what
you think isn't looking right." Buttons: with a note and Yes → "Delete
note"; with a note → "Update Note"; without → "Add Note" (only after No).
The note is the set's `feedback` field (synced to the server).

### Guides (observed)

- **Feedback walkthrough** (`FEEDBACK_WALKTHROUGH_STEPS`, 7 steps from
  "Congrats on your First Set!" to "Comparing Sessions"): once per user
  (`hasSeenFeedbackViewGuide`), 2 s after the feedback screen opens; the
  "?" header button reopens it.
- **Guide tips** (title "Readiness", one per screen visit, after the tip's
  delay, never while the tag guide shows), first unseen eligible of:
  READINESS (1 s; "You moved %s at %.2fm/s. Next time you lift %s in your
  Primary session, you'll be able to compare." or "Track your readiness by
  comparing your performance across sessions."), COMPARISON (1.5 s, needs
  a last-session speed; "You can compare This Session with last %s. You
  moved %s This Session %s vs. Last Session." with "<day type> session" or
  "session", and "%.2fm/s faster/slower" or "same speed" within 0.005),
  HISTORICAL_AVERAGE (2 s, needs several data points; "Historical Average
  unlocked! Based on your last 90 days, using up to 12 of your most
  relevant sessions. Use it as another comparison point."), TOP_SET (3 s,
  top set with several data points; "Your Top Set is your session's key
  measure. This gauge helps you compare Today's speed with past sessions
  objectively."). Dismissing marks the tip seen.
- **Rep edit guide** (6 steps, "Manually edit your reps." … "Adding
  reps"): auto-shown once, 1 s after Rep Check opens; toggle button.
- **Pre-recording guide** ("Setup Guide"; last button "Ready to Record"):
  once (`hasSeenPreRecordingGuide`) and from a button. Steps: "Get Set Up
  in 30 Seconds", "Tracker Attachment & Placement" (deadlift: "Tracker
  Attachment (Deadlift)"), then three Stance-tracker hardware steps
  (connecting, turning off, charging).

### Analysis wait (`PreRecordingScreen`, observed)

After Stop: "Saving your set and preparing results…", then "Analysing your
set" with a 60 s countdown bar (`ANALYSIS_COUNTDOWN_SECONDS`): "%ds left",
then "Taking longer than usual"; "You can leave this screen — your set
will still be saved."

## 18. Session day types — traced (17 Oct 2026)

- `SessionDayType`: PRIMARY, SECONDARY, TERTIARY, QUATERNARY (display
  "Primary"…"Quaternary"). Stored as the session tag `Day:<name>`;
  `fromTagList` takes the first `Day:` tag naming a type.
- `SessionDayTypeExtractor.extractSessionType` / `SessionTagRules.
  hasSessionTypeTag`: the first type name found as a **substring** of any
  tag, else "". Readiness (§14) and the comparison picker (§15) match on
  this string; an untagged session gets no comparison sessions.
- `updateDayType(type)`: drops every `Day:` tag, adds the new one (none
  for "None"), saves, and reloads comparisons.
- Feedback screen: `SessionDayTagDropdown` under the exercise title, with
  "None" plus the four types. `SessionTagGuideOverlay` ("Readiness" — "What
  type of session are you doing today?", one option per type, dismissable)
  shows whenever `!hasSessionTypeTag(tags)`; guide tips wait while it
  shows. The comparison tip names the type ("last Primary session").
- Tag editor: see §19.

## 19. Session tag editor, card tags, readiness label — traced (17 Oct 2026)

- `SessionTagEditorSheet(initialTags, onDismiss, onDone)`: modal sheet,
  title "Tags" + "Done", subtitle "Add tags to compare what matters to
  you. Tap to select or deselect." Sections in order **Block** (`Block:1`…,
  starts at 6, "more…" adds 6), **Week** (`Week:n`, same), **Day** (the four
  `Day:` tags), **Externals** (`Externals:1`–`5`). Chips show the raw wire
  tag. Tapping calls `SessionTagRules.toggleTag`: remove if present, else
  replace any tag with the same prefix (text before `:`) — one per section.
  Done and dismissing both call `onDone(edited)`.
- **Not reachable in the shipped app**: nothing calls the sheet. The view
  model has `beginTagEditor` / `applyTagsFromEditor` (sync tags, reload
  comparison sessions), and the strings `session_tag_editor_open` ("Edit
  session tags") and `session_tag_add_session_tags` ("Add session tags")
  are unused.
- Sessions card `SessionTagsRow` (shown when there are tags): tag icon,
  grey circle with the count, then horizontally scrolling pills.
  `SessionTagFormatter.toDisplayTags`: drop tags starting `//`, sort by
  prefix order Day, Week, Block, External(s), others, then tag creation
  date; `shortenTagText`: `Day:X` → `X`, Block/Week/Externals → `B:`/`W:`/
  `E:` + value.
- Readiness history label (`generateSessionLabel`): first tag starting
  with "B" (or "Block") and first starting with "W"/"Week", space-joined.
  Shown in the readiness detail history after "(days ago)".

## 20. User profile and preferences — traced (17 Oct 2026)

- Home menu: "User Details" → `UserDetailsSheet`; "Preferences" →
  `PreferencesScreen`. Both use `UserProfileEditorViewModel`; profile
  fields and both units live in `UserData` (Supabase-synced). **No
  analysis reads any of it** (bodyweight only appears in sync/DTO code).
- `UserProfileEditorRules`: genders Male/Female/Other; weight whole kg,
  input 40–150 kg or 88–330 lbs (`kgToLbs`/`lbsToKg` round with 2.20462);
  height whole cm 130–230, or ft-in 4'3"–7'6" (51–90 in, inches < 12,
  2.54 cm/in, rounded); training age 0–50. `CompetitionLevel` raw values
  No/Unsanctioned/Regional/National/International; `ConfidenceLevel`
  "I don't use RPE"/Not Confident/Quite Confident/Confident/Very
  Confident. Units stored as "kg"/"lb" and "cm"/"ft".
- Completion: 9 fields (first, last, gender, DOB, weight, height,
  training age, confidence, competition; Instagram excluded),
  `(int)(100·n/9)` + "%", and "Add <first missing> for better insights".
- Sheet: "Hello <first name>" + **Save** (if changed) or **Done**; both
  save and close, and dismissing saves too (`saveChanges(force = true)`).
  Order: Profile title/subtitle, completion bar, First/Last Name, Gender,
  Date of Birth, Weight (kg/lbs toggle), Height (cm/ft toggle; feet + In
  fields), Training Age, RPE Confidence Level, Competition Level,
  "Optional Information": Instagram Username (blank saved as null).
  The weight/height toggles change the same unit preferences.
- `ProfileNumericField`: keeps digits only; empty clears; a value is
  applied only when in range, else the range error shows.
- Preferences screen: "Customize your app experience", Weight Unit kg/lb
  ("This preference will be used for exercise weight input."), Height
  Unit cm/ft-in. **Done** saves (`saveChanges(false)`) and goes back;
  there is no other save, so back discards.

## 23. Deadlift tips and weight-performance tutorial — traced (17 Oct 2026)

(REA's JADX provider was not configured — `REA_JADX_MCP_JAR` unset — so
this was traced from the jadx sources in `targets/decompiled/sources/`.)

- Deadlift tips: `HomeScreenKt` adds a lazy item `home_deadlift_tips`
  (`ComposableSingletons$HomeScreenKt.lambda-3` → `DeadliftTipsCard`)
  after the exercise rows when the open catalogue group's id is
  `"deadlift"` (`DeadliftModelBundle.ASSET_DIR`). Always shown, no seen
  flag. Rounded card: title `home_deadlift_tips_title` "Tips:", then one
  "•" row per tip, in this order:
  1. "Pause between lifts (~1 second)"
  2. "Pause at the top of the lift (if possible ~ 1s)"
  3. "Stop the recording after you finished your lift (don't leave it recording)"
  4. "Move with intent"
  5. "Known limitation: This does not track tempo-based deadlifts."
- Weight-performance tutorial: `RepSpeedDetailSheet` keeps a
  `showTutorial` state; `WeightPerformanceSection` (shown when the set has
  weight-performance data, header "Comparison against previous Sets &
  Sessions at ...") contains `HowDoIUseThisButton` "How do I use this?" in
  all its variants, which sets it. Always available, not once-only.
  Opens `TutorialSheet("Weight Performance", "Compare recent sets at any
  weight as an indicator of progress.", R.drawable.weight_performance_tutorial,
  StanceScreen.FeedbackWeightPerformanceTutorial)`: a modal bottom sheet
  with close button, logo, title, subtitle and the image; dismissing
  returns to the rep speed sheet.
- Image: id 0x7f080155 → `res/Pt.webp` in the APK (WebP,
  120 KB); copied to `assets/images/weight_performance_tutorial.webp`.

## 22. Saved sensor, auto-reconnect, "Location is off" — traced (17 Oct 2026)

REA's Android providers (jadx, apktool) are not configured in this
environment, so this was traced in `targets/decompiled/` and the strings via
`tools/arsc_strings.py`.

**Saved device** (`data/ble/BleLastDeviceStore`, DataStore file
`ble_last_device`; keys `last_wit_address`, `last_stance_address`,
`last_connected_kind`):
- Saved by `lastDeviceStore.recordSuccessfulConnect(kind, address)`, which
  `SdkBleDeviceRepository.connect()` launches when a connect is *requested*
  (not on success).
- Kept across disconnects. Cleared by `clearAll()`, which only
  `SettingsViewModel.forgetSavedBleDevices()` calls (Settings row
  `settings_ble_forget_saved` "Forget saved BLE devices"; it does not
  disconnect). `forgetLastConnectedDevice()`, `clearWit/Stance` and
  `hasSavedLastDevice` exist but nothing calls them.
- `device_forget_saved` "Forget saved device" and `device_forget_saved_hint`
  "Disconnects and removes the last device from saved preferences so you can
  pair a different one." are in the string table, but no code references
  them: the Device-screen button is a leftover string. We build it anyway
  (it is on the TODO), with those strings.

**Auto-reconnect** (`domain/usecase/AutoReconnectToLastSavedBleDeviceUseCase`):
- Called from `HomeViewModel.onHomeScreenReadyForAutoConnect` and
  `DeviceViewModel.onDeviceScreenReady` (the Device screen then also starts
  its normal scan). Not at app start.
- Runs only if BLE permissions are granted and the connection state is
  Disconnected, and only once per process (`attempted` AtomicBoolean, set
  before the saved address is read).
- Reads the saved kind (falls back to WitMotion address, then Stance
  address); no saved address: nothing.
- Starts a normal BLE scan, waits up to `AUTO_RECONNECT_SCAN_MS = 12000` for
  the saved address (case-insensitive) to be discovered, connects if seen,
  then always stops the scan. No retry, no backoff, no extra UI: the Device
  screen/chip just show the normal scanning/connecting states.

**Location is off** (`domain/util/BleReadinessRules`,
`domain/model/BleReadiness(missingPermissions, locationServicesOff)`,
`presentation/common/BleReadinessDialog`):
- `locationServicesOff = sdkInt <= 30 && !LocationManager.isLocationEnabled()`;
  `missingPermissions = !all BLE permissions granted`.
- Shown (a) on Sessions when "New Session" is tapped and no sensor is
  Connected (`SessionListViewModel.readinessPromptForNewSession`); dismiss
  button is "Continue anyway" (closes and goes to weight input); tapping
  outside closes without going on. (b) On the Device screen when not ready
  (re-evaluated on ON_RESUME; becoming ready triggers the initial scan);
  dismiss button is "Not now".
- Title `ble_readiness_location_title` "Location is off" (or "Bluetooth
  access" when permissions are missing). Message
  `ble_readiness_location_message` "This Android version requires Location
  Services to be on for Bluetooth scanning. Turn it on to find your sensor."
  (both missing: `ble_readiness_both_message` "Stance needs Bluetooth and
  location permission, and Location Services turned on, to find your
  sensor."). Buttons: "Grant permissions" and "Open settings" (permissions
  missing), "Turn on Location" (opens `android.settings.LOCATION_SOURCE_SETTINGS`),
  then "Continue anyway" / "Not now".
- Permissions: `device_ble_permissions_rationale` "Stance needs Bluetooth
  and location permission to discover and connect to your WitMotion sensor."

## 21. Signal quality and IMU quality metrics — traced (17 Oct 2026)

Traced with the REA CLI (JADX 0.7.1 provider; the MCP server lacked
`REA_JADX_MCP_JAR`). `inspect_android_method` on
`AssessSignalQualityUseCase.invoke` (ev_6743b889…) and
`ImuQualityMetricsCalculator.butterworthLowPassFiltfilt` (ev_1317419f…);
`trace_android_references` on `SignalQualityBadgeKt` (ev_f59f9ce0…),
`RecordingScreenKt` (ev_777704e5…), `ImuQualityMetricsCalculator`
(ev_fd7f2350…). JADX `-m fallback` was used where the normal output was
wrong (see below). **Stance shows no per-set quality verdict anywhere
reachable.** There are two separate mechanisms.

### Live `SignalQuality` (Good / Fair / Poor badge)

- `AssessSignalQualityUseCase(window, expectedIntervalMs = 10)`, run on every
  `currentSessionDataPoints` update with `takeLast(200)` (only when the list
  has ≥ 2 samples). It uses `SensorData.timestampMs` =
  `System.currentTimeMillis()` at decode time (phone clock, not chip time).
  - intervals = consecutive timestamp differences; `gapCount` = intervals
    > 2·expected (> 20 ms).
  - `packetsPerSecond` = 1000 / mean interval (0 if the mean is 0).
  - `completenessPercent` = clamp((n − 1) / max(span / expected, 1) · 100,
    0, 100). The division is floating point (fallback bytecode shows both
    values cast to double; normal JADX output drops the casts).
  - Rating: **Good** if ≥ 95 % and gapCount == 0, **Fair** if ≥ 80 %, else
    **Poor**.
  - The sensor is set to 200 Hz (§1), so completeness saturates at 100 %
    unless delivery falls below 100 Hz. Good also requires no receive gap
    over 20 ms, which BLE notification batching may break (unverified).
- `SignalQualityBadge`: a small surface tinted 15 % with the rating colour
  (success green / amber / `colorScheme.error`), showing the rating text
  (labelMedium, coloured) over `"%.0f pkt/s"` (labelSmall). These strings
  are hard-coded; the APK string resources contain no quality strings.
- It sits in `RecordingScreen.RecordingControlsRow` (Row, spaceEvenly:
  `RecordButton`, then the badge when non-null). It resets to null on
  `startRecording`. **`RecordingScreenKt` has no incoming references other
  than its own inner classes** (the `recording` route is unreachable, §16).
  The shipped record flow (`PreRecordingScreen`) shows no quality UI. So the
  badge is dead UI.

### Per-set `ImuQualityMetrics` (no verdict)

- `CompleteSetAfterRecordingUseCase` (and `RecordingRepositoryImpl`'s sync
  path) calls `ImuQualityMetricsCalculator.compute(session.dataPoints)`
  once when the set is saved. The result goes into `SetSyncInput`; it is
  then stored embedded in the Realm `SetEntity` (`IMUQualityEntity`),
  queued for Supabase (`PendingIMUQualityEntity`), and written to the debug
  log by `CompletedSetLogReporter` (`imuDataLossPct=`,
  `gyroSaturationDurationS=`, `accelSaturationDurationS=`,
  `stillPeriodCount=`, `numberOfImpacts=`). **No presentation code reads
  it, and there are no thresholds or levels.**
- `RemoteImuQuality` is only the Supabase DTO mirror (same 14 fields),
  restored into `IMUQualityEntity` by `SyncCacheRepositoryImpl`. It is not
  computed server-side.
- `compute`: < 2 samples → null. It keeps samples with no transducer value
  whose `chipTime` ("yyyy-MM-dd HH:mm:ss.SSS", UTC) parses; t = seconds
  from the first. Then:
  - fs = 1 / median(positive dt), default 100.
  - `imuDataLossPct` = Σ(dt > 1.5/fs) / span · 100.
  - `gyro`/`accelSaturationDurationS` = samples with any |axis| > 1999 deg/s
    or > 15.9 g, divided by fs.
  - Still/impact detection uses the |a| magnitude through a first-order
    high-pass at 2 Hz (α = 1/(2π·2/fs + 1), y0 = α·x0, yᵢ = α(yᵢ₋₁ + xᵢ −
    xᵢ₋₁)).
  - Still periods: |hpf| < 0.02 for ≥ 1 s.
  - Impacts: mark settled spans (|hpf| < 0.25 for ≥ 0.5 s); each remaining
    span with any hpf > 2.0 (signed) counts once.
  - No still periods → nulls and empty lists, count 0.
  - Otherwise accel is rotated to the world frame by the raw quaternion;
    per period it takes the mean x/y/z and the sample std (after a 2 Hz
    4th-order Butterworth filtfilt as two biquads, Q = 1/(2 sin π/8) and
    1/(2 sin 3π/8), DF-II primed at x/(1+a1+a2), when the period has ≥ 12
    samples). Outputs are the means of the means and of the stds, the
    per-period std lists, and `stillPeriodCount` = all periods found.
  - The backward filtfilt pass starts from `forward.lastOrNull() ?: x0`.
    The normal JADX output wrongly shows x0; fallback bytecode confirms
    `lastOrNull()`.
- What the user can do: nothing in-app. There is no warning, retry prompt
  or re-record suggestion; the only related message is "No sensor data was
  recorded…" for an empty recording (already ported).

### Port

`analysis/imu_quality.dart` (`computeImuQuality`, stored as
`SetRecord.imuQuality` when a set is saved; it uses `sensorTimeMs`, the
WitMotion chip clock). `workout/signal_quality.dart` (`assessSignalQuality`,
`assessRecentSignal`). `SignalQualityBadge` sits beside the record button
while recording, as in Stance's dead `RecordingControlsRow`. That is the
deviation: we show it on the live record page.

## 25. Settings ("Debug Menu"), file logging and Device Stream — traced (17 Oct 2026)

**Reaching it.** Home top bar: settings icon (`home_settings_menu`) opens a
dropdown with Preferences, User details, **Debug Menu** (`debug_menu`), Sign
out. Debug Menu navigates to `MainRoutes.Settings` (`"settings"`, singleTop)
= `SettingsScreen`, whose header shows `debug_menu` ("Debug Menu"), not
`settings_screen_title`, with a back arrow and the device status button.
Rows, top to bottom: Firebase ID (+copy); **File logging** (`settings_file_logging_title`)
with hint `settings_file_logging_hint` "Logs are saved automatically (last 5
MB). Share to send for support."; **Share debug log** button
(`settings_share_debug_log`; only present when the log file exists); BLE
stack switch (`settings_ble_stack_*`, debug); buttons "Test device data
stream" (`device_stream_menu_button`, route `device_stream`, singleTop),
Recording (`recording_screen_title`), Calibration (`calibration_screen_title`);
**Forget saved BLE devices** (`settings_ble_forget_saved`); sync diagnostics
card; Sign out (red, confirm dialog).

**File logger** (`data/logging/`, `domain/logging/AppFileLogLimitsKt`):
- `StanceLog` (object, no-op until `StanceLog.init(AndroidAppLogger)` in
  `StanceApplication.onCreate`, right after `InitializeAppFileLogUseCase`
  opens the file). `d/i/w/e(tag, msg[, throwable])`; each calls `android.util.Log`
  and appends to the file; `w`/`e` also go to Crashlytics (`log`, `recordException`).
- File: `<filesDir>/debug_logs/stance-app.log`, one file, UTF-8, appended
  across runs (no rotation into several files). At start, legacy
  `stance-debug-*.log` files in that folder are deleted.
- Format: `yyyy-MM-dd HH:mm:ss.SSS L/tag: message`, local time; with a
  throwable, `\n` + trimmed stack trace.
- Writes on a single `DebugFileLogWriter` thread, flushed per line.
- Cap: `APP_FILE_LOG_MAX_BYTES = 5242880`. Every `APP_FILE_LOG_TRIM_CHECK_INTERVAL
  = 10` appended entries it checks the size; while over the cap it closes the
  writer, drops the oldest `APP_FILE_LOG_TRIM_LINES = 10` physical lines,
  rewrites the file, reopens.
- Logged: `AppLoad` block at start (`========== APP LOADED BEGIN ==========`,
  version, device, process id, user id, crash-on-previous-run, load time, timezone,
  END); `ScreenLifecycle` `event=screen_enter|screen_leave screen=<StanceScreen.logName>`;
  ~45 tags such as BleCoordinator, BleScanner, Wit/StanceGattSession,
  RecordingRepository, RecordingProtoWriter, SetCompletion, LocalSquatBench,
  ProcessDeadlift, DeadliftTcnPipeline, ReprocessSet, SetVideo*, OfflineSync,
  PullSync, ProcessExit.
- **Share**: `shareDebugLogFile` = `ACTION_SEND`, type `text/plain`, `EXTRA_STREAM`
  = FileProvider URI (`<package>.fileprovider`), read-grant flag, chooser titled
  `settings_share_debug_log_chooser` "Share debug log".

**Forget saved BLE devices**: `SettingsViewModel.forgetSavedBleDevices()`
(see §22); no confirmation, no disconnect.

**Device Stream** ("Test device stream", `device_stream_title`; Hilt
`DeviceStreamViewModel`):
- Top bar: back, title, device status button (opens Device screen).
- Message line under it: `device_stream_device_not_connected` when not
  connected; `device_stream_encoder_hint` when a Stance encoder is the
  connected kind (needs a WitMotion IMU). (`device_stream_connect_wit_first` is unused.)
- Buttons Start / Stop / Clear (`device_stream_start|stop|clear`). Start is
  enabled when connected to a WitMotion and not streaming; it calls
  `startStreaming()` on the BLE repository. Stop is enabled while streaming.
  Clear is always enabled. Losing the connection stops the stream. Stop keeps
  the data on screen.
- Every sensor reading is appended to two unbounded lists until Clear: plot
  point (time, acc x/y/z, q0..q3) and global acceleration. UI state is
  published at most every `UI_THROTTLE_MS = 66`.
- Badges: "Is Stationary" (green when stationary, else grey); "Uncalibrated"
  (red; only when stationary and not calibrated); "Streaming issue" (red;
  `requiresFirmwareUpdate`). Re-judged every 1000 ms from the last 10 points:
  stationary = |acc| magnitude changes ≤ 0.1 between consecutive points;
  calibrated = stationary and |mean x|, |mean y| ≤ 0.05 and |mean z − 1| ≤ 0.05;
  streaming issue = stationary and one axis moved < 0.05 across the window
  while another moved > 0.1. Calibrated and issue keep the previous value while
  not stationary or with < 2 points.
- Three charts, each a legend row then a card: Acceleration (Acc X/Y/Z),
  Quaternion (Q0..Q3), Global acceleration (`device_stream_chart_global_acceleration`;
  legend Global, Acc X/Y/Z). Plots, not numbers; there is no numeric readout.
  Y range fixed -3..3, 7 grid lines, 200 dp high, x = time with caption
  `device_stream_chart_time`. Streaming: last `LIVE_WINDOW = 200` points. Stopped:
  all points, thinned to ≤ `FULL_SERIES_MAX_VERTICES = 1000`, canvas
  `max(width, n*3 dp)` and horizontally scrollable when > 200.
- Global acceleration = R(q)·acc using the quaternion as given (no normalising).

## 26. Video export with burned-in overlay, save and share — traced (17 Oct 2026)

(REA's JADX provider is not configured, so traced from the jadx sources
in `targets/decompiled/sources/`.)

**Crop** (`domain/video/SetVideoExportRules.buildPlan`, `REP_BUFFER_MS =
10000`):
- Inputs: rep windows in seconds (`GetSetVelocityTraceUseCase` reps'
  `startSec`/`endSec`, recording time = video time; Stance has no sync
  offset), per-rep mean velocities (the rep chart's), orange sticking
  bands in % (`repOrangeStickingBandsPct`), video duration
  (`MediaMetadataRetriever`, w/h swapped for rotation 90/270).
- Null (no export, nothing happens) if there are no reps or duration ≤ 0.
  `buildOverlayInput` also returns null when the trace has no reps.
- Each window → ms (truncated) clamped to [0, duration]; crop start =
  max(0, min start − 10 000), end = min(duration, max end + 10 000); null
  if end ≤ start.
- `RepOverlayWindow(number = i+1, startMs/endMs = raw ms − cropStart, ≥ 0,
  not clamped to the end, meanVelocity = null if missing or ≤ 0,
  stickingBandFraction = %/100 clamped 0–1, null if end ≤ 0 or end ≤ start)`.

**Overlay** (`data/video/SetMetricsOverlay`, a Media3 `BitmapOverlay`;
geometry `SetVideoOverlayGeometry`):
- Panel 450×230 reference px, scale = min(max(W/720, H/1280), 3), anchored
  4 % from the left and 14 % from the bottom of the frame. Black 60 %
  rounded rect.
- Static: Stance logo (tinted grey), "Bar Speed" (white bold), weight icon +
  "`<weightLabel> x <repsCount>`" (grey), "Rep" (grey), a white 20 % bar
  track.
- Per frame (t = presentation time − offset 0, i.e. clip time): bar fill
  purple `#9357FF` = smoothstep((t − start)/(end − start)) during a rep;
  after it, full for 200 ms (`REVERSE_DELAY_MS`), then 1 − smoothstep over
  300 ms (`REVERSE_DURATION_MS`); after the last rep it stays full. The
  rep's orange band is drawn amber `#FF9900` from band start to
  min(fill, band end) once the fill passes the band start.
- Only while t is inside a rep window: the rep number (right of "Rep") and
  its mean velocity `%.2f` (grey "0.00" if null) + "m/s". No live velocity,
  no bar path, no rep count beyond the static "x N".

**Encode** (`data/video/SetVideoExporter.export`, mutex-serialised):
Media3 Transformer. `MediaItem` with `ClippingConfiguration(cropStart,
cropEnd)`, `EditedMediaItem.setRemoveAudio(true)` (exports are silent),
effects = [OverlayEffect(SetMetricsOverlay)] plus `Presentation` to
`REVIEW_SHORT_SIDE_PX = 1080` short side (even dims) for the review
variant. Output `filesDir/videos/overlay_set_<setId>[_4k].mp4` (`_4k` =
uncapped) with a `.sig` file (`overlaySignature` = Kotlin `hashCode` of
"uri|weightLabel|reps|windows %.3f|velocities %.3f" + "@1080" or
"@full"); a matching cached file is reused. Failure deletes the output and
returns null. `cancelActiveExport()` cancels the Transformer. No progress
reporting (a 500 ms ticker only logs memory). `VideoExportCleanup`: after
each export, trims `filesDir/videos` to 500 MB oldest-first, deleting an
`.mp4`/`.sig` pair together (`VideoExportDiskCapRules`); at app start
(throttled to 1 h) also deletes files > 24 h old there and in
`cache/share_videos`.

**Where** (`components/FeedbackVideoPlayerSheet`, the feedback page's video
player bottom sheet): top row has a Share icon (disabled while preparing)
and a More (⋮) menu: "Share video with Stance" (opens a tally.so form with
name/user/set/weight/RPE), "Save to camera roll", "Report" (video mismatch
crash report, with a confirm and "Reported" toast).
- Share → `prepareShareUri`: `sourceUriForSaveOrShare` = full-res export
  (`exportFullResOverlay`, uncapped, waits up to 3 s for the player to be
  released, `isExporting`), else the 1080 fallback overlay file, else the
  raw video; copied to `cache/share_videos/share_set_<ms>.mp4`, FileProvider
  URI, `ACTION_SEND` `video/mp4` chooser (no title). No source → toast
  "Could not prepare video".
- Save → same source, MediaStore `Movies/Stance/stance_set_<ms>.mp4`
  (`is_pending` 1→0); toast "Saved to gallery" / "Could not save video".
- While preparing: black 60 % scrim over the video with a white spinner and
  `video_preparing` "Preparing video…". No percentage, no cancel button;
  dismissing the sheet cancels the export (`onVideoPlayerDismissed`).
- The 1080 review export is only used as playback fallback when the
  player's live overlay effect fails (`onEffectsFallback`).

**Port**: rules in `lib/video/set_video_export_rules.dart` (tests
`test/set_video_export_test.dart`); `lib/video/set_video_exporter.dart`
(cache/signature, cap, share via share_plus, save via gal); native encoder
`android/.../SetVideoExportChannel.kt` (Media3 1.8.0 Transformer, Dart
passes the overlay state sampled every 10 ms so the timing rules stay in
Dart); Share + More → "Save to camera roll" in `VideoReviewPage`'s app bar.
Rep windows get the set's sync offset (Stance assumes 0). Not ported: the
1080 review variant (our player draws its own overlay), "Share video with
Stance", "Report", the logo and weight icon, the 24 h start-up sweep. No
encoder on iOS: save/share fall back to the raw video, as Stance does when
its export fails.

**Set-completed log** (`CompletedSetLogReporter`, tag `SetCompleted`): on set
completion Stance logs a block, one `StanceLog.i` per line, between
`========== SET COMPLETED BEGIN/END ==========`: event, recordingId,
sessionGroupId, firebaseUid, userEmail, exercise, weight, weightUnit, setType
(wire key or `none`), source, set start/end (UTC and local), setDurationMs,
deviceTimezone, dataPointCount, meanFrequencyHz (`%.2f`, else `unknown`),
preprocessing (+ preprocessingError), repCount, repMeanVelocitiesMps (`[a, b]`,
`%.4f`), WitMotion/transducer name, firmware and reading counts, then (only
when metrics exist) imuDataLossPct, gyroSaturationDurationS,
accelSaturationDurationS (`%.4f`), stillPeriodCount, numberOfImpacts, then
datFileWritten/Name/Error, videoLocalIdentifier (`N/A`), loggedAtUtc/Local.
Null lines are dropped. Ported as `lib/workout/set_log.dart`, called after a
successful save in `record_set_page.dart`; account, encoder and firmware
lines are omitted.

## 24. CSV import and reprocess — traced (17 Oct 2026)

Three separate things in Stance; only the reprocess banner ships in release.

**Home "Import recording"** (`HomeViewModel.onRecordingFilePicked`,
`RecordingImportUiState(isLoading, errorMessage, lastImported)`,
`LastImportedExercise(exerciseId, exerciseTitle, recordingStartedAtMs,
imuCsvFile)`). Debug builds only: in release the card's composables are
compiled out (the picker lambda `launch(arrayOf("*/*"))` in `HomeScreenKt`
has no caller) and `ProcessImportedRecordingUseCase.invoke` throws "Recording
import is only available in debug builds". Flow from what remains: tap →
`OpenDocument("*/*")` → state `(isLoading=true)` (previous import kept aside)
→ needs a signed-in user ("Sign in required to import a recording") → bytes
→ `ImportRecordingDatUseCase` parses Stance's protobuf `.dat` (errors "No
witmotion streams in recording", "Need at least 2 witmotion readings, got
N"), whose metadata carries exercise, weight and unit
(`RecordingProtoMetadata`; set type not visible) → completes it as a set in
a new session group (`CompleteSetAfterRecordingUseCase`, stripped) and writes
`recordings/<id>-imu.csv` (`ImuCsvFileWriter`). Success → label: "Imported:
%1$s" (exercise title), "Recorded: %1$s", "Tap to open Sessions for this
exercise" (tap = open that exercise's Sessions), X "Dismiss last import"
(`dismissLastImport`), OutlinedButton "Export IMU CSV" (share). Failure →
`errorMessage = e.message ?: e.toString()`, previous label restored;
`clearImportError` exists. Strings: `home_import_recording` "Import
recording", `_subtitle` "Import a .bin or .dat file from S3 to replay a
set.", `_loading` "Processing recording…". Card sits above the exercise list
(lambda order in `HomeScreen$5`).

**Recording screen "Import IMU CSV"** (Debug Menu → Recording;
`RecordingViewModel.onImuCsvPicked`, `ImportedCsvUiState(isLoading,
errorMessage, fileDisplayName, dataPoints)`): `GetContent("text/*")` →
`ImuCsvReader.parse` → card "Imported IMU file" with the file name, a
`PostRecordingVelocityChart` of the samples and "Clear import". Loading
"Loading CSV…". It only plots; nothing is saved. Errors: "Could not open
file", else `e.message ?: "Import failed"`.

**`ImuCsvReader`** (format = `ImuCsvWriter.HEADER_LINE`
`Timestamp,Gyroscope X (deg/s),Gyroscope Y (deg/s),Gyroscope Z (deg/s),Accelerometer X (g),Accelerometer Y (g),Accelerometer Z (g),Quaternion W,Quaternion X,Quaternion Y,Quaternion Z`;
timestamp = chip time `yyyy-MM-dd'T'HH:mm:ss.SSS` UTC; numbers via
`BigDecimal.stripTrailingZeros`, NaN/inf → `0`): first line trimmed, BOM
dropped, must equal the header exactly ("Unexpected CSV header. Expected
exact export header line."); "CSV is empty"; each non-blank row split on
`,`, trimmed, "Line N: expected 11 columns, got M" (N counts physical lines,
header = 1); "Line N: invalid Acc X value \"raw\"" (fields Acc X/Y/Z, Gyro
X/Y/Z, Q W/X/Y/Z); timestamps parse with `yyyy-MM-dd HH:mm:ss.SSS` or the
`T` form as UTC, else 0; "Need at least 2 data rows, got N".

**Reprocess** (`ReprocessSetUseCase`, `ReprocessSetResult`,
`ReprocessUiState`, `components/ReprocessBanner`). Shown on the feedback
sheet, between the set selector and "New set", when the **selected** set
`needsReprocessing` = `preprocessingStatus` ∈ {`VERCEL_FAILED`,
`VERCEL_EMPTY`, `DEADLIFT_TCN_FAILED`, `DEADLIFT_TCN_EMPTY`}
(`SessionFeedbackUiMapper`); sheet peek +70 dp. One state per page
(`IDLE` initially and on `selectSet`). Message by state:
`IDLE`/`IN_PROGRESS` "We couldn't finish processing this set. Your data is
safe and already backed up."; `FAILED` "Reprocessing didn't work this time.
You can try again."; `STILL_EMPTY` "We still couldn't find reps in this set.
Your data is backed up for review."; `UNAVAILABLE` "Reprocessing is
available right after recording. This set's data is backed up and can be
reprocessed by the team." Button only for IDLE/IN_PROGRESS/FAILED (confirmed
with JADX fallback mode): primary "Reprocess", or a spinner + "Reprocessing…"
while running. `reprocessSelectedSet`: ignored while IN_PROGRESS; exercise
from the session; → IN_PROGRESS → use case → `Success(repCount>0)` IDLE,
`Success(0)` STILL_EMPTY, `SourceDataUnavailable` UNAVAILABLE, `Failed`
FAILED. Per set only, no bulk, no progress beyond the spinner.
Use case: finds the recording in the **in-memory** `RecordingStore.sessions`
(not on disk; gone after an app restart → `SourceDataUnavailable`); empty
data → `Failed("No IMU data recorded — re-record the set")`; timestamps
rewritten (`SensorTimestampRewriter`, logged `imu_timestamp_rewrite …`);
deadlift: TCN (OK/EMPTY), on throw local C (`DEADLIFT_LOCAL_C_OK` or
`DEADLIFT_TCN_FAILED`); squat/bench: Vercel (OK/EMPTY), on throw local C
(`LOCAL_C_OK`). Empty reps → `updateSetAfterReprocess(id, [], [], outcome)`,
`Success(0)`; else velocity trace rebuilt and stored, reps persisted,
`updateSetAfterReprocess` = reps, repCount, velocity, `preprocessingStatus`,
marked for upload. IMU quality metrics are **not** recomputed. Errors logged
(tag `ReprocessSet`) and reported as `reprocess_failed`.

**Port.**
- `lib/recording/recording_csv.dart`: `parseRecordingCsv` reads our raw CSV
  (`# sensor=… started=…` comment, `Recording.csvHeader`, 12 columns) and
  Stance's IMU export (11 columns; sensor clock used for both clocks), with
  `ImuCsvReader`'s rules and messages; an unparseable Stance timestamp is an
  error ("Line N: invalid Timestamp value") instead of 0.
- `lib/workout/reprocess.dart`: `ReprocessState` (messages, `showsButton`),
  `needsReprocessing` (= `analysisError != null` or no reps), `reprocessSet`
  re-analyses from the set's **raw CSV** and returns the updated set
  (`SetRecord.withAnalysis`: reps, pipeline, warnings, rate, trace; error
  cleared; lifter data, video and `imuQuality` kept; a previously failed
  set's video offset moves from the first sample to the new analysis
  origin), `stateAfter`.
- `lib/ui/reprocess_banner.dart` replaces the feedback page's "Analysis
  failed" card (the stored error and raw file name stay as a detail line);
  `session_feedback_page.dart` keeps one state, reset on set selection,
  peek +70.
- `lib/workout/recording_import.dart` (`RecordingImportState`,
  `LastImportedRecording`, `importRecordingAsSet`: copy into
  `recordings/`, analysis, `imuQuality`, one set in a **new** session, saved
  even if analysis fails) and `lib/ui/recording_import_card.dart` on Home
  above the exercise list; `file_picker` dependency.
- Deviations: import is visible (Stance: debug builds only); CSV, not
  `.dat`, so a dialog asks exercise and weight (unit from Preferences, no set
  type); subtitle "Import a raw recording CSV to replay a set."; reprocess
  works from disk for any set with its CSV (UNAVAILABLE only when it's
  missing); no Vercel step. The Recording screen's plot-only CSV import is
  not ported (that screen is skipped).
