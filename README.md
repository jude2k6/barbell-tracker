# barbell-tracker

Reverse engineering a commercial barbell velocity tracker with REA, to
understand how its features work and rebuild similar ones.

## Layout

- `targets/` — app artifacts and raw REA output under analysis (APK, native libraries, decompiled sources). Untrusted; not committed.
- `evidence/` — curated captures backing each finding.
- `notes/` — write-ups of how each feature works.
- `src/` — our own reimplementation.
