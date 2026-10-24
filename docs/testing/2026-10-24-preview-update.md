# Preview distribution update — 2026-10-24

This update packages the accepted combined arm64 Release executable, UUID
`7351B2C8-E6CE-3D7F-8D57-06B4B5142BE8`. All 2406 recorded application/project
input entries match the source snapshot, including explicitly absent files.
Packaging introduces no new application behavior or untested rebuild.

## Included changes and earlier acceptance

The combined player contains the five dependent interface parts from proposal
#6540, separate screenshot feedback, the October 24 audit fixes, and the latest
OSC toolbar feedback. The public upstream drafts retain stock dependencies;
this LYINA distribution retains its existing custom engine, including persistent
audio mixing and independent secondary-subtitle styling.

The shared toolbar change passed 183 native AppKit checks, four wiring checks,
801 sidebar/window checks and 98 panel/titlebar/WebKit checks. Its accepted
combined Release executable was visually checked in an isolated application for
individual hover, Settings/Playlist selection and Escape closure. See
`2026-10-24-toolbar-feedback.md` for fixture and timing limits.

Accent colors, appearance callbacks and Settings restart flows were checked
with native AppKit, JavaScriptCore/WebKit and isolated player fixtures. Earlier
audit results and remaining engine/platform boundaries are recorded in
`2026-10-24-player-audit.md`. These bounded checks do not prove that every feature
works with every file or plugin.

## Distribution requirements

The package must retain every file-backed Mach-O code/data section from the
accepted executable and the exact bundled engine bytes. The engine SHA256 is
`15882c42baa0176045a78e6b8dca8487a64e6476fd42e2f2c0fd21585d8d5572`.
The source branch advances without rewriting the original release tag. The DMG
filename and existing direct download URL stay unchanged. BUILD-INFO and
SHA256SUMS identify the replacement bytes and source commit.

Package verification covers image integrity, strict/deep ad-hoc signing, mounted
application contents and an isolated playback/seek/geometry/screenshot smoke run.
BUILD-INFO and the release notes distinguish these package checks from earlier
implementation acceptance.

The distribution contains no personal profile, history, media or user-installed
plugins. The unfinished OpenSubtitles work is excluded; existing stock plugin
archives are unchanged. It retains the separate LYINA identity and disables the
official IINA update feed. It is ad-hoc signed, not notarized.

## Limits

Apple Silicon on macOS 27.0.1 is the locally checked environment. Intel, older
macOS, other hardware, arbitrary plugins, full compositor cadence and all HDR /
Dolby Vision paths remain unverified. Historical performance comparisons
predate this build. Native model checks and a short package smoke run do not
establish general stability or performance parity with stock IINA.
