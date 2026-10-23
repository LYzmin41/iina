# Sidebar setting feedback and Geometry Reset

Status: delivered. Sidebar-only EC09DA71 was subsequently superseded by accepted combined UUID 4A76C399-18DE-354D-86E8-5621B1896CA8 in /Applications/LYINA.app. All eleven OSD/Reset source hashes are preserved in its 2373 frozen inputs; live installed UUID and executable SHA match the adaptive installation manifest. See 2026-10-23-crop-adaptive-resolution.md for rendering acceptance and combined-delivery-receipt.json for cross-task verification.

## Requested behavior

Built-in sidebar parameter controls expose their values directly. Clicking, typing, dragging or resetting those controls should not add redundant setting OSD. Keyboard shortcuts retain their feedback with the sidebar open. Genuine seeking, errors, asynchronous operation outcomes and external plugin feedback remain visible.

Geometry Reset must update Aspect Ratio, Crop and Rotation after one click. The underlying rotation already reset; its observer was missing the video-parameters notification that refreshes the selected segment.

## Implementation

Explicit main-thread sidebar action scopes carry feedback provenance through deferred geometry operations. Typed mpv setters record expected property values before writing; property observers capture matching provenance before dispatching notifications to main. Ordered pending values handle continuous slider input, coalesced acknowledgements and failed writes. Ordinary commands supersede only their property. Unobserved, node and notification-only properties do not retain pending values.

Setting feedback alone is suppressed at PlayerCore delivery. The video/audio/subtitle/track/playlist parameter actions and group resets use the scope. Playback outcomes and errors keep their existing routes.

Filter graph rebuilds can cause native SEEK events without user navigation. Time/progress OSD now requires an explicit seek intent at the actual command boundary, with cancellation on failure and existing generation/restart handling. The command classifier mirrors bundled mpv token syntax without changing the text passed to execution.

## Verification

Focused extracted-production suites currently cover sidebar policy and typed callbacks, command routing, geometry seek lifecycle, Rotation Reset, Crop motion/window sizing/editor exit, track processing/EQ, subtitle controls and LUT handling. The extracted suites pass: sidebar policy/callbacks 211, command syntax 99, geometry seek lifecycle 115, Crop refresh 17, Rotation Reset 88, deferred delivery 4, geometry motion 295, crop-window frame 600, crop exit 124 plus routing 33, subtitle controls 52, aspect focus 12, track processing 119, LUT model 31 plus popup 59. Source snapshots and logs are retained alongside the build.

The sidebar-only immutable Release snapshot contains 2373 inputs and 11 changed production sources relative to installed B597F9A3. UUID EC09DA71-8F07-34DF-A7F6-6858BF8FFC68. Compilation and strict/deep QA signing passed. Native tests use the separate Crop Motion QA identity and a bounded nonmutating observer of actual built-in OSD delivery.

Nineteen native checkpoints pass: first-click canonical Geometry Reset on pause and active 4K (engine and selected 0° segment), quiet color slider bursts, speed/reset, Master EQ/preset/reset, per-track EQ and delay graph changes, primary/secondary subtitle selection/adjustments/typed Return/reset, and Playlist Repeat. Parameter values were independently read through the owned QA IPC socket. The playing 4K pass recorded zero video/decoder drops.

Visible shortcut feedback remains present with the sidebar open: Cmd+] shows Speed 2x, Shift+X shows Subtitle Delay 2s, and Right shows 00:10 / 00:30. Ordinary pause/resume and file-start messages also remain visible. No redundant parameter/time OSD appeared in the quiet control intervals. The native-checkpoints artifact records event bounds and actual values. These observations do not measure compositor frame cadence.

The initial Release candidate was discarded because concurrent adaptive-resolution changes reached the shared source tree during compilation. The two chats are coordinating a stable source snapshot and installation ownership. Evidence: `build/sidebar-osd-2026-10-23/`.


The real playing EQ pass also succeeds. Master filter replacement/reset and per-track graph creation/runtime gain changes produce no parameter or time OSD; Left immediately afterward still publishes deliberate seek feedback. The command-boundary integration suite adds 84 checks for actual array/raw dispatch, failed mutation/seek rollback and background queue ordering. Disabling cleanup in a test-only copy produces ten expected failures. Total focused checks: 1943.

A clean, uninstrumented 4K run confirms first-click Rotation Reset, quiet color/EQ actions and visible shortcut speed feedback. That mixed run included 2x playback and recorded 6 video/0 decoder drops. A separate clean 1x playing EQ run recorded 0/0. The cause of the earlier six drops was not isolated; this change makes no claim of improving playback FPS.

The adaptive rendering owner reported unresolved window-tick gaps and did not accept 996D6129. Delivery was therefore decoupled: install the tested sidebar-only source snapshot with the prior accepted two rendering files. The active shared checkout retains the adaptive experiment; its owner has the 11 preserved source hashes and the updated installed baseline for later combined delivery.

The installation changed only Contents/MacOS/IINA. Strict/deep signing passes, engine SHA256 remains 15882c42baa0176045a78e6b8dca8487a64e6476fd42e2f2c0fd21585d8d5572, and installed executable SHA256 is b34a9d6eddbe1c0ecf34c31d0bd1f67afff15a83e9578c92cb295a25d0e2e8c7. All 2373 frozen inputs and 11 current sidebar source hashes match. Personal PID 57266 is unchanged; owned QA is stopped. Normal player restart and user acceptance remain. No commit, push or public update.
