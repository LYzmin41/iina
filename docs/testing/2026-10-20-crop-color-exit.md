# Exact crop color and editor exit — 2026-10-20

The reported AV1 file decodes to NV12. Applying
`crop=2902:1421:535:53:exact=1` produces the reported blue shift: FFmpeg's exact
crop can start the interleaved chroma plane between U/V components at odd x.
Controlled probes reproduce the defect with odd NV12 x while even x and planar
input retain normal colors.

Odd exact rectangles now negotiate planar 4:4:4 before cropping, retaining input
precision and alpha options. Aligned rectangles retain the direct crop path.
The protected graph reads back as the same logical crop, so selection, Cancel,
watch-later and file-session restoration keep the original pixel coordinates.

The old editor exit removed preview constraints before the new output arrived,
exposing an expanded uncropped frame and then another geometry change. A bridge
made from the selected rendered region now covers that interval. Its expansion
shares the native window resize timing; removal requires both animation completion
and the new live frame's draw. Failed changes and stale/closed sessions discard
the bridge. Concurrent crop/Live Text snapshot requests share a rendered image,
and rendering shutdown releases pending requests.

## Verification

- 561 production-controller/editor checks: dimensions, source geometry, selection,
  presets, pan/zoom, modifiers, Reset, Escape, Save/Cancel, failures and scope.
- 549 native window/transform checks, including scheduling crop-image expansion
  before resizing and matching its final bounds within native pixel rounding.
- 19 production transition/snapshot checks, including concurrent readers,
  shutdown, stale media, failure recovery and render/animation completion order.
- Bundled libmpv: unsafe NV12 control reproduces the defect; six protected format
  cases retain normal colors and exact 31x21 output. The generated production
  graph also retains exact odd origin, adjacent HDR-tagged 16-bit luma values,
  and all 16-bit RGB/alpha components.
- 35 video-geometry session checks and the existing PiP lifecycle/render/transaction
  suite pass. Release arm64 builds successfully; the custom engine is unchanged.
- Final isolated full player, macOS 27.0.1, original AV1 file with auto-copy decoding
  and Live Text enabled: Save has normal colors, reopening restores 2902x1421,
  Cancel after an edit restores that crop, and Reset/Save returns 3840x2160.
  Playback stays paused at 49.542 seconds; no stuck input bridge or crash observed.

Evidence: `build/crop-color-diagnosis-2026-10-20/` and
`build/crop-fixes-2026-10-20/`. The native harnesses and snapshots do not establish
acceptance on older macOS, external displays or HDR compositor transitions.
Downloadable-asset provenance is recorded separately in the release's
`BUILD-INFO.json` and checksums.
