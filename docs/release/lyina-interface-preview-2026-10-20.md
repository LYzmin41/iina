# LYINA Interface Preview — updated 2026-10-23

An experimental build for trying the player interface proposal independently of
official IINA. This is not an official IINA release or an upstream-approved patch.
The application reports LYINA 1.5.1 (180).

## October 23 update

The existing download now contains the current locally checked interface build:

- Revised native-video transitions for Crop, Custom Crop, Aspect Ratio and
  Rotation, including preset restoration, cancellation, fullscreen and PiP.
- Adaptive crop-transition raster sizing to retain more detail during large
  zooms, with bounded allocations and the existing color/HDR pipeline.
- Sidebar parameter edits no longer produce redundant setting or seek OSD;
  keyboard shortcuts, deliberate seeking, errors and operation outcomes retain
  their feedback. Geometry Reset refreshes Rotation on its first click.
- Native sidebar fields have complete focus rings, select-all behavior, commits
  on Enter/focus loss, and empty-value defaults for Aspect Ratio, Speed, Audio
  Delay, Subtitle Delay and Color.

Earlier exact-crop color, drag lifecycle and screenshot-feedback fixes remain
included. OpenSubtitles plugin integration is deferred and is not bundled.
See `docs/testing/2026-10-23-preview-update.md` for verification and limits.
Asset filenames remain stable so existing download links receive this build.

## Download and installation

Download the Apple Silicon DMG from the
[preview release](https://github.com/LYzmin41/iina/releases/tag/v1.5.1-interface-preview.20261020).
Verify its checksum against the release's `SHA256SUMS.txt`, open the image and copy
`LYINA.app` to Applications. Open a test media file using File → Open.

- Apple Silicon only. Bundle deployment target: macOS 12. Runtime testing was
  performed on macOS 27.0.1; older macOS and other hardware remain unverified.
- Separate application identity and preferences: `org.lyzmin41.lyina`. No personal
  preferences, history, plugins or media are included in this download.
- Official IINA is not replaced. The preview registers document types as alternate
  handlers, and official automatic update checks/downloads are disabled.
- The bundle is ad-hoc signed, without a Developer ID certificate or Apple
  notarization. macOS may block first launch. See Apple's
  [instructions for opening downloaded applications](https://support.apple.com/102445).
  No quarantine-removal commands or system-wide security changes are required by
  these installation instructions.
- Existing LYINA users share the existing LYINA preference domain. This download
  does not make a new profile for each preview release.

## Scope and feedback

Try the floating controller and its return animation, title bar, small-window
layout, sidebar transitions, Custom Crop, visual geometry settings, track
selection and processing, subtitle roles, and screenshot feedback. Some features
are specialized; feedback on their usefulness and maintenance cost is welcome.
Multivideo composition and source color processing still need broader HDR testing.

In recorded short local comparisons, ordinary playback CPU and memory were in the
same broad range as IINA 1.5.0, without steady-phase engine frame drops. This does
not establish performance parity across all operations. Multitrack preparation
and connected mixer inputs have measurable costs. The measurements predate later
interface changes and are historical evidence, not fresh benchmarks of this DMG.

Please include macOS version, hardware, media characteristics and reproduction
steps when reporting an issue. The preview is intended to support discussion of
individual changes and smaller upstream patches.

## Source and reproducibility

The original release tag identifies the initial preview snapshot. The updated
asset's exact source commit is linked in the release notes and `BUILD-INFO.json`;
the preview source branch advances without rewriting that published tag.
The source contains the focused test harnesses, custom mpv patches and this
distribution note. See `other/patches/README.md` for the
engine baseline and build requirements. Do not build the engine from plain mpv
without IINA's compatibility patches.

The published DMG uses the already built and locally checked arm64 Release
executable. Its exact executable and engine hashes, source commit, architecture,
minimum OS and signature status are recorded in the attached `BUILD-INFO.json`.
The public source snapshot matches the recorded build inputs. Packaging changes
only bundle metadata and the ad-hoc signing envelope, using
`other/release/prepare-interface-preview.py`; the executable's file-backed code
and data sections and the engine bytes remain unchanged. Source attribution,
bundled acknowledgements and the
repository license are preserved.
