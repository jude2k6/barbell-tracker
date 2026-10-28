# Sensor clock and frame-format problems

Found on 24 Oct 2026 with the user's real sensor, a WitMotion **WT9011DCL**
(advertises as `WT901BLE67`). **Status (25 Oct 2026):** fix plan steps 1–4
and 6 are done (see "Implementation" below); 5, 7 and 8 are open.

## Symptoms (Device page, real device)

- Loss 60.1 %, Rate 0 Hz while "Streaming".
- 65,556 received, ~98,585 "missing", 51,355 clock jumps (~78 % of samples).
- Debug Menu → Test device data stream, sensor lying flat: acceleration ≈ 0
  on all axes (should be ~1 g on Z), quaternion ≈ 0 with one line at 0.06.

## Problem 1: we only decode Stance's 30-byte frame

`lib/sensor/witmotion/witmotion_protocol.dart` treats every `55 61` frame
as 30 bytes (`_imuLength = 30`): date/time at bytes 2–9, accel ×16 g and
gyro ×2000 °/s at 10–21, quaternion /32768 at 22–29. The user's sensor
sends WitMotion's **stock 20-byte frame**: accel, gyro, roll/pitch/yaw
angles, and **no timestamp**.

Feeding stock frames from a still, flat sensor into our decoder reproduces
the screenshot exactly:

| | Should read | Our decoder gets |
|---|---|---|
| Acceleration | ~1 g on Z | ~0 on all axes (really gyro + angles) |
| Quaternion | length 1 | ~0, one value 0.06 (really next frame's accel) |
| Chip timestamp | — | missing on every frame |
| Frames decoded | 50 sent | 25 (each read eats 1⅓ frames, rest skipped) |

Consequences:

- **All sets recorded with this sensor were analysed from garbage.** The
  misread bytes were never saved, so they can't be reprocessed.
- About half the frames really are discarded, which is part of the 60 %.

## Problem 2: no clock, so timing falls apart

With no chip time, `chipTimeMs` falls back to the phone's arrival time.
Several frames arrive in each BLE notification and share one arrival time,
so timestamps repeat or go backwards. The rate monitor
(`lib/sensor/rate_monitor.dart`) trusts them blindly:

- **Clock jumps:** a repeated/earlier/>2 s timestamp counts as a jump.
- **Fake loss:** gaps between bad timestamps are counted as missing samples.
- **0 Hz:** rate over the last 2 s of timestamps has a zero or negative span.

Set analysis uses the same timestamps, so it needs the same guard.

## Why Stance doesn't have this problem

Stance's trackers are most likely the same WT9011DCL hardware running
**custom WitMotion firmware** that streams the 30-byte frame out of the box:

- Stance never sends the unlock (`FF AA 69 88 B5`) or writes register 0x02
  or 0x96. It only sets rate (`FF AA 03 0B 00`, 200 Hz), bandwidth
  (`FF AA 1F 02 00`), calibration, save, battery read (`0x64`) and a
  firmware-version read (`FF AA 27 2E 00`).
- The WitMotion SDK bundled in Stance's APK
  (`com/wit/witsdk/Device/DeviceModel.java`, line 466: `!= 97 ? 20 : 30`)
  is rewritten to accept only the 30-byte frame, and adds
  `WitSdkDiagnostics`, CSV export and BLE retry logic.
- In WitMotion's public protocol, time (`55 50`) and quaternion (`55 59`)
  are separate packets, and BLE uploads are capped at 20 bytes. No stock
  mode produces Stance's frame.

There is no published command that makes the user's sensor send it.

## Ways to get a clock

1. **Rebuild timing from the sample rate (recommended base fix).** Keep the
   stock frame with angles. Stamp each frame at previous time + one period,
   nudged toward notification arrival (what ehartmann/witmotion-ble does).
   Measured rates elsewhere are steady: ~198.4 Hz at the 200 Hz setting,
   zero dropped frames.
2. **ms-counter mode, register 0x96 = 2 (undocumented).** Send unlock,
   wait 100 ms, then `FF AA 96 02 00`. Not saved to flash; reverts on power
   cycle (the library writes 0x96 = 0 on connect to restore). Frame is
   `55 61` + accel (6) + gyro (6) + uint32 LE ms counter at byte 14; 18 or
   20 bytes, unconfirmed. **Costs the angles**, so we'd need our own
   orientation filter from gyro + accel. Not vendor-confirmed; no accuracy
   figure published. 0x96 = 3 ("displacement + velocity + timestamp") is
   reported once with a non-monotonic counter.
3. **Time registers 0x30–0x33** by polling only. Fine for an occasional
   sync, useless per sample.
4. **DIY sensor** (TODO.md): firmware sending `55 61` frames plus a sample
   counter fixes this properly.

## What we lose without timestamps (option 1)

- **Integration step:** fixed step at the measured per-set rate; error well
  under 1 %. Deadlift already assumes exactly 200 Hz.
- **Dropped-sample detection:** the real loss. Only an estimate from count
  vs. elapsed time and long arrival gaps; BLE retransmits, so true loss is
  rare. An undetected lost packet shortens one rep and lowers its velocity
  by a few percent.
- **Signal-quality badge:** becomes an estimate, not exact.
- **Video sync:** unaffected, it already uses the phone clock.

## Fix plan

1. Detect frame size from the stream: after `55 61`, check whether the next
   header is 20 or 30 bytes later. Keep 30-byte (Stance-format) support.
2. Decode the stock frame; convert roll/pitch/yaw to the quaternion the
   analysis expects. Mount with Z roughly vertical or along the bar to stay
   clear of gimbal lock at pitch ±90°.
3. Spread each notification's samples evenly in time (option 1).
4. Rate monitor and set analysis: check timestamps actually advance; fall
   back to phone time when they don't.
5. Check the 200 Hz command is accepted; newer firmware may need the unlock
   first. The Device page rate will show 200 Hz vs. the factory 10 Hz.
6. Log the detected frame format in the debug log.
7. Optional: a debug toggle for 0x96 = 2 that logs frame length and counter
   steps (expect 5 ms at 200 Hz), to evaluate option 2.
8. Side fix: the sensor name `WT901BLE67` wraps onto two lines on the
   Device page next to battery and Disconnect.

## Probe results (25 Oct 2026, laptop BlueZ + gatttool)

Sensor `DA:EB:82:85:8B:0F` (random address). GATT: write `ffe9` value
handle 0x000d, notify `ffe4` value handle 0x000f, CCCD 0x0010.

- **Frames are stock 20-byte `55 61`, one per notification.** Flat and
  still: accel Z raw 0x080d ≈ 1.006 g. Confirms problem 1.
- **MTU 247 negotiated fine; frames stay 20 bytes.** A bigger MTU is not
  what switches on Stance's 30-byte frame.
- **Writes work:** unlock + `FF AA 03 06 00` (10 Hz) dropped the stream to
  9.9/s; `FF AA 03 0B 00` (200 Hz) brought it back. Not saved.
- **~25 notifications/s ceiling on the laptop** at 200 Hz: one notification
  per ~40 ms connection event (BlueZ default interval). The sensor's 200 Hz
  doesn't get through a slow link. On the phone the delivered rate depends on
  the negotiated connection interval too; ask Android for high connection
  priority (7.5 ms) and measure.
- **Register reads (`FF AA 27 reg 00`) get no `55 71` reply**, with or
  without unlock, with or without response. Battery/version/0x02/0x96 can't
  be read on this firmware this way.

Setting experiments (unlock, write, watch 6 s; MTU 247; nothing saved):

| Write | Frame (always 20 bytes, `55 61`) |
|---|---|
| 0x96 = 0 | stock: accel, gyro, angles |
| 0x96 = 1 | all zeros (displacement mode, sensor still) |
| **0x96 = 2** | accel, gyro, **uint32 LE ms counter at byte 14**, bytes 18–19 = 0 |
| 0x96 = 3 | accel/gyro zeroed, ms counter at byte 14, 2 slowly varying bytes |
| 0x96 = 4…8 | the same constant junk (`b4 3c 00 20` looks like a RAM address): invalid modes |
| 0x02 (RSW) = 0x0201, 0x020F, 0x001E | no change at all: the BLE firmware ignores RSW |

- **No 30-byte frame from any setting.** No MTU, RSW or 0x96 value made the
  frame grow or added `55 50`/`55 59` packets. Stance's frame needs their
  firmware.
- **0x96 = 2 clock is real and confirmed:** it counts ms since power-on
  (~150 s at test time), stepping **exactly 40 ms per frame**, and its span
  matched phone time within 1 %. So at the 200 Hz setting only one sample
  per 40 ms leaves the sensor, with no gaps: nothing is lost in transit.
  **Correction:** ehartmann/witmotion-ble's README says that from 50 Hz up
  the sensor sends one notification about every 40 ms and **packs the
  frames sampled meanwhile into it** (2 at 50 Hz, 4 at 100 Hz), using the
  MTU 247 the sensor itself requests. About 4 s after connecting, the sensor
  also sets a 30 ms connection interval, overriding Android's
  `CONNECTION_PRIORITY_HIGH`. Others measured 198 Hz (RGu0) and ~195 Hz
  (FreecityDong, macOS) at 200 Hz on a WT901BLE67. Our laptop run got no
  packing (one 20-byte frame per notification, even after a client MTU 247
  exchange), so the sensor kept only the latest sample. Not yet understood:
  maybe gatttool doesn't answer the sensor's own MTU request. Check on the
  phone: notification lengths should be multiples of 20 bytes, and our
  stream parser must split them (it buffers already, so it should). Restoring 0x96 = 0 brings the angles back.

## Implementation (25 Oct 2026)

- `WitFrameDecoder` (`witmotion_protocol.dart`) detects the `55 61` frame
  length from where the next header falls (confirmed by the one after when
  buffered), locks it, and re-detects if the stream stops lining up. It
  emits raw `WitImuFrame`s: 20-byte ones carry the 6-byte tail, 30-byte
  ones their chip time and quaternion.
- `WitStreamMode` (`witmotion_mode.dart`) turns one notification's frames
  into `SensorSample`s and names its setup write:
  - `WitAnglesMode` (default): 0x96 = 0, angles → quaternion
    (`eulerToQuaternion`, ZYX), host times from `NotificationClock`
    (frames spread between arrivals; late notifications leave a hole), no
    `sensorTimeMs`.
  - `WitClockMode`: 0x96 = 2, counter → `sensorTimeMs`, orientation from
    `TiltFilter` (6-axis Mahony, accel trusted only within 0.1 g of 1 g).
  - 30-byte frames pass through unchanged in both.
- `WitMotionLink(device, mode: …)` picks the mode; every write goes after
  the unlock, 100 ms apart; the detected frame length is logged.
- `RateMonitor` restarts its window on a clock jump; the stale frames sent
  before 0x96 = 2 takes effect had pinned it at 0 Hz.
- Replaying the laptop captures: angles mode mean world-Z 1.003 g, 24.7 Hz;
  clock mode 0.995 g, 25.0 Hz, 0 missing.

## Sources

- [ehartmann/witmotion-ble](https://github.com/ehartmann/witmotion-ble)
  and [PR #2 (bandwidth + clock check)](https://github.com/ehartmann/witmotion-ble/pull/2)
- [RGu0/WT901 protocol notes](https://github.com/RGu0/WT901)
- [FreecityDong/WT9011DCL](https://github.com/FreecityDong/WT9011DCL)
- [ctroncozo/witmotion_ble](https://github.com/ctroncozo/witmotion_ble)
- [WitBluetooth_BWT901BLE5_0 issue #6 (0x96 write)](https://github.com/WITMOTION/WitBluetooth_BWT901BLE5_0/issues/6)
- [WitMotion BLE 5.0 communication protocol](https://wit-motion.gitbook.io/witmotion-sdk/ble-5.0-protocol/bluetooth-5.0-communication-protocol)
- [WIT standard communication protocol](https://wit-motion.gitbook.io/witmotion-sdk/wit-standard-protocol/wit-standard-communication-protocol)
- [WT9011DCL datasheet](https://www.sensor-test.de/assets/Fairs/2025/ProductNews/PDFs/WT9011DCL-Datasheet.pdf)
