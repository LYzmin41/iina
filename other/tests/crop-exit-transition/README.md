# Crop exit rendering boundary

Run `bash other/tests/crop-exit-transition/run.sh` from the repository root.

The harness compiles the production crop overlay, MainWindow transition methods
and ViewLayer snapshot queue methods. A controlled rendering boundary releases
image continuations explicitly; native AppKit supplies views and image drawing.

Checks cover capture before mutation, duplicate Save, obsolete restart events,
selection-image mapping, bounded input blocking, new-frame readiness, frame and
animation completion in either order, unchanged/full-source exits, failed
filters/captures, media replacement and cancellation. Concurrent snapshot readers
share one draw; renderer shutdown releases pending and later requests.

The adjacent crop-window-frame suite verifies expansion starts before the native
window resize and uses its final bounds. These checks establish sequencing and
geometry, not full compositor acceptance on every macOS/display configuration.
