# Preview distribution update — 2026-10-23

This update packages the accepted current arm64 Release executable, UUID
`D8822A42-64ED-393C-B833-27186376A65B`. All 2373 recorded application/project
inputs match the local source snapshot before packaging. No new production
source change or untested rebuild is introduced by distribution preparation.

## Existing acceptance for this executable and its included changes

- Final sidebar inputs: 55 native field lifecycle, 20 Aspect Ratio, 17 Color,
  23 slider layout, 211 OSD, 52 subtitle, 77 selector and 150 sidebar scrolling
  checks. Isolated player checks cover first/repeat-click replacement, Enter and
  background commits, decimal input and empty defaults for both subtitle roles,
  Audio Delay, Speed, Aspect Ratio and Color.
- Adaptive crop implementation: 501 extracted-production sizing/ownership and
  13 wiring checks, with further crop/window/geometry/session regressions.
  Playing SDR/HDR acceptance covers ordinary, strong and extreme crops; the
  case-end video/decoder/delayed counters are zero. A separate HDR pixel-readback
  probe recorded 782 frames without black-center samples or GL errors.
- Sidebar OSD and Geometry Reset: focused policy, callback and command-boundary
  checks, plus native controls/shortcut verification. A clean 1x playing EQ run
  recorded zero video/decoder drops. One separate mixed run including 2x playback
  recorded six video drops; the cause was not isolated.

Detailed component evidence:
`2026-10-23-crop-adaptive-resolution.md`, `2026-10-23-sidebar-osd.md`, and the
sidebar-input-fields task record. These checks were performed on this Apple
Silicon Mac running macOS 27.0.1. The distribution's BUILD-INFO records packaging
checks separately from this earlier implementation acceptance.

## Distribution requirements

Packaging must preserve every file-backed application Mach-O code/data section
and exact bundled-engine bytes. The engine SHA256 is
`15882c42baa0176045a78e6b8dca8487a64e6476fd42e2f2c0fd21585d8d5572`.
The source branch advances without rewriting the original release tag, and the
asset name remains stable for existing links. Exact source and asset hashes are
recorded in BUILD-INFO and SHA256SUMS with the download.

The bundle contains no personal profile, media, installed third-party plugins or
OpenSubtitles integration. It retains the separate LYINA application identity
and disables the official IINA update feed. It is ad-hoc signed, not notarized.

## Limits

This is an experimental preview. Neither these component checks nor a package
smoke test establish general stability, equivalence to stock IINA performance,
compositor FPS, every animation subframe, Dolby Vision correctness or behavior
on Intel, older macOS, another Mac, arbitrary plugins or arbitrary filter graphs.
The bounded crop performance comparison has overlapping distributions and
possible tail costs; adaptive raster allocation consumes additional memory.
Historical October 19 performance comparisons predate this build.
