# Crop, transforms and track/output window sizing regression

Run `bash other/tests/crop-window-frame/run.sh` from the repository root.
The AppKit harness extracts the actual MainWindow video-size handler, aspect
setter, explicit scale action, screen/minimum clamp and NSSize/NSRect helpers.
It also extracts the actual PlayerCore Aspect Ratio/Rotation and track setters,
video reconfiguration handler and audio track-change handler.
Playback, preferences, UI refresh and MPV synchronization are fixture boundaries.

Locked windows fit the cropped display aspect starting from the current frame,
subject to existing minimum and screen limits. Unlocked windows retain their
freely chosen frame. Checks cover wide/portrait/tiny/uncropped output,
logical/physical resolution, centering, repeated reconfiguration, fullscreen
prior geometry, startup sizing of the next file and explicit scale commands.
A concrete 874×525 → 874×492 case protects against the rejected fixed-frame
letterboxing behavior. PiP receives the cropped display aspect independently.

`CROP_WINDOW_MAIN_SOURCE=/absolute/path/to/MainWindowController.swift` selects an
older source for causal comparison. The old fixed-frame implementation fails
the locked crop-aspect regression (its earlier flag name is normalized only in
the test fixture). Editor Save/Cancel and filter success/failure integration
remain in `custom-crop`; these harnesses do not replace physical acceptance.

Transform coverage includes every supported rotation, 4:3/Default/invalid aspect,
locked/unlocked and physical/logical resolution. The fixture invokes the native
size handler synchronously from MPV property writes to ensure the policy is
selected before output notification, and compares identical starting windows
with 720p and 4K sources. `TRANSFORM_PLAYER_SOURCE` selects a previous PlayerCore
source for the regression; `CROP_WINDOW_OUTPUT_DIR` isolates its binary output.


Track/output coverage starts without a transform-setter flag, switches video
between None and 720p/4K/portrait tracks, checks direct MPV video output changes,
and audits audio None/1/2 selection and native volume control visibility. Ordinary
new-file initialization and explicit scale actions remain covered separately.
