# Adaptive crop transition resolution

Installed tested arm64 Release `4A76C399-18DE-354D-86E8-5621B1896CA8` in
`/Applications/LYINA.app`. Source worktree remains
`/Users/lyzmin41/.codex/worktrees/osc-position-reset-0042/IINA-modify`, branch
`codex/osc-position-reset`. Evidence and source backups are under
`build/crop-adaptive-resolution-2026-10-23/`.

## Behavior and limits

Custom Save previously enlarged the editor-sized native raster until canonical
crop output arrived. The new native owner plans physical raster coverage from
both projection endpoints, source detail and screen backing scale. Player crop
presets/None and Custom entry also plan their endpoint demand.

The selected implementation allocates larger fixed logical bounds at normal
Retina density and immediately reprojects the existing native layer inside its
atomic handoff. The bounds, density and renderer remain fixed during motion.
Save upgrades once before movement; layout is acquired and restored once. Normal
screen density, constraints, transform and mask return at canonical handoff or
cancellation. Backing-scale changes retire the transition before ownership moves
to a different screen.

Only InteractiveMode.swift and MainWindowController.swift change for this task.
No additional decoder, renderer, screenshot cover, CPU video image, engine option
write or per-tick raster allocation is introduced. The existing clock, readiness,
color/HDR pipeline, source-window scale and minimum geometry are retained.

New allocations are bounded by a 3840x2160 pixel-area budget and an 8192px edge
limit; already-larger legacy allocations are preserved. Source limiting considers
both axes, including anamorphic video and rotation. Extreme source/budget-limited
crops still cannot add source detail or guarantee identical canonical mpv scaling.

## Performance evidence

The before build is OSD-only `EC09DA71`, using the same 11 accepted sidebar sources
and the original two renderer sources. The supplied AV1 SDR 3840x2160/24fps video
and a HEVC HDR10 3840x2160/24fps fixture were tested on this Apple M4 Pro, Retina 2x.
Ordinary 2448x1291, strong 1223x974 and extreme 384x216 selections were exercised.

The first density-only variant was rejected after the broad matrix showed longer
window-motion gaps despite zero engine drops. A native stack sample also exposed
AX window enumeration synchronizing CA/WindowServer. The subsequent comparison
avoids reading the UI during Save and waits on native completion before observing
UI again. The earlier stress data remain separate exploratory evidence.

The selected allocation strategy's five-repeat HDR ordinary-crop comparison is
recorded in `perf/proper-hdr-comparison.{json,md}`. All 15 raw baseline/A/B repeats,
input comparability and per-repeat ranges are retained. These B prototype runs
precede the final layout-acquisition bookkeeping correction; the final installed
binary has separate SDR/HDR/strong-crop acceptance below.

| Metric, median across five repeats | Before | Selected allocation strategy |
| --- | ---: | ---: |
| Mean application callback gap |14.24ms |14.48ms |
| Maximum callback gap |33.34ms |32.33ms |
| p95 callback gap |24.35ms |28.32ms |
| Native draw callback wall time, p50 |7.31ms |7.95ms |
| One RGBA16F raster plane |6.45MiB |27.00MiB |
| Video/decoder/delayed counters |0/0/0 |0/0/0 |

The observed distributions overlap. No clear systematic cadence regression was
detected in this bounded comparison; tail impact remains possible. This is not
an equivalence test, compositor-FPS measurement or GPU-busy-time benchmark.
Native draw wall time includes mpv presentation waits. The driver advertises GPU
timestamps but returns invalid zeros; those measurements are excluded, and GPU
queries are disabled for the matched comparison. Raster storage is an estimate
for one color plane, not total GPU memory.

Final binary 4A76C399 separately covers all three crop sizes on playing SDR and
HDR. Regular source raster is 2508x1411; strong 3546x1995; extreme 3838x2160. All
case-end video, decoder and delayed counters are zero. The final strong HDR case
has additional three-repeat evidence, compared to two direct baseline strong
controls: baseline mean callback gaps24.83/24.09ms; final24.42/19.00/20.10ms.
The heavier existing window-resize cadence remains visible in both builds.

## Quality and regression acceptance

- 501 extracted-production adaptive sizing/ownership checks plus 13 integration
 wiring checks pass with warnings treated as errors. They cover 1x/2x physical
 coverage, SAR/rotation, source/area/edge caps, invalid metadata, unchanged image
 and aperture at reallocation, fixed bounds/density through 101 projection ticks,
 single layout acquire/restore and floating-point precision.
- 121 crop native ownership,33 routing,600 window geometry,17 crop refresh,
 586 Custom Crop,8 selector,295 geometry-motion and65 session checks pass. The sidebar peer repaired its selector
 mock for the new performSidebarChange helper; production sidebar inputs stay frozen.
- Separate pixel-readback HDR run: 782 PQ frames, zero black-center samples and
 zero GL errors; one ICC fingerprint, EDR enabled andRGBAh throughout. Maximum
 channel range stays below0.001. These quality probes are excluded from timing.
- Clean run without injected libraries covers paused Custom 1223x974 on the user's
 SDR video, playing presets/None, Custom cancellation, fullscreen and PiP with
 restored live video. Immediate/settled crop screenshots retain detail. Final
 video/decoder/delayed counters are 0/0/0. No claim covers every motion subframe,
 physical display FPS, Dolby Vision, other hardware or arbitrary filter graphs.

## Delivery and coordination

All 2373 frozen production inputs match the immutable source snapshot and final
build; all 11 OSD/Reset source hashes are preserved. Strict/deep signing passes,
only the installed executable changed, and engine SHA-256 remains
`15882c42baa0176045a78e6b8dca8487a64e6476fd42e2f2c0fd21585d8d5572`.
Signing changes the Mach-O signature, so installation verifies the tested UUID
and every file-backed Mach-O section against the built executable, in addition
to recording both complete executable hashes. The installed executable SHA-256
is `8a9acd76d5288234de77b0243831f968888c040c968eb55f5549520c0d989d0c`.

The previous executable/signing resources remain in `installed-before/`.
The personal player changed from 57266 to 85315 independently during work; the
installer re-audited actual processes and preserved 85315. Owned QA is stopped.
Normal LYINA restart and user visual acceptance remain. No commit, push, PR or
public release was made.
