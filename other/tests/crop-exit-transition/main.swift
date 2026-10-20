import Cocoa

enum AccessibilityPreferences {
  static func adjustedDuration(_ value: TimeInterval) -> TimeInterval { 0 }
}
enum Preference { enum Key { case disableAnimations }; static func bool(for key: Key) -> Bool { false } }
enum MPVProperty { static let vf = "vf" }
final class MPVFixture {
  var options = ["vf": "", "lavfi-complex": ""]
  func getString(_ name: String) -> String? { options[name] }
}
final class PlayerFixture {
  struct State { var active = true }
  final class Info { var state = State(); var trackSelectionGeneration = 1 }
  let info = Info(), mpv = MPVFixture()
  var disableWindowAnimation = true
}
final class LayerFixture {
  var requests: [CheckedContinuation<NSImage?, Never>] = []
  func captureSnapshot() async -> NSImage? {
    await withCheckedContinuation { requests.append($0) }
  }
  func reply(_ image: NSImage?) { requests.removeFirst().resume(returning: image) }
}
final class VideoFixture: NSView { let videoLayer = LayerFixture() }
final class EditorFixture { var isActive = true }
// PRODUCTION_OVERLAY
final class MainWindowController {
  let player = PlayerFixture()
  let interactiveMode = EditorFixture()
  let videoView = VideoFixture()
  let videoViewContainer = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
  var cropExitOverlay: CropExitOverlay?
  var isCropExitInProgress: Bool { cropExitOverlay != nil }
  func startWindowAnimation(to frame: NSRect) { startCropExitAnimation(to: frame, duration: 0) }
  // PRODUCTION_TRANSITION
}
final class SnapshotFixture {
  let snapshotLock = NSLock()
  var pendingSnapshotHandlers: [(NSImage?) -> Void] = []
  var snapshotsClosed = false
  var updates = 0
  func update(force: Bool) { updates += 1 }
  func deliver(_ image: NSImage?) { takeSnapshotHandlers().forEach { $0(image) } }
  // PRODUCTION_SNAPSHOT
}
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  precondition(value(), message); checks += 1; print("PASS:", message)
}
func pump(_ predicate: () -> Bool) {
  let deadline = Date().addingTimeInterval(3)
  while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.001)) }
  precondition(predicate(), "asynchronous crop boundary timed out")
}
let image = NSImage(size: NSSize(width: 100, height: 60), flipped: false) { bounds in
  NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 50, height: 60).fill()
  NSColor.blue.setFill(); NSRect(x: 50, y: 0, width: 50, height: 60).fill()
  return true
}
let selection = NSRect(x: 50, y: 0, width: 50, height: 60)
let size = NSSize(width: 100, height: 60)
let initial = NSRect(x: 200, y: 20, width: 160, height: 192)
func start(_ main: MainWindowController, _ apply: @escaping () -> Bool) {
  main.prepareCropExit(selection: selection, sourceSize: size, initialFrame: initial, completion: apply)
  pump { !main.videoView.videoLayer.requests.isEmpty }
}
let main = MainWindowController()
var applied = 0
start(main) { applied += 1; main.player.mpv.options["vf"] = "new crop"; return true }
check(main.isCropExitInProgress && applied == 0, "source capture precedes filter mutation")
main.prepareCropExit(selection: selection, sourceSize: size, initialFrame: initial) { applied += 100; return true }
main.finishCropExitTransition()
check(main.videoView.videoLayer.requests.count == 1, "duplicate Save and an old playback restart cannot consume preparation")
main.videoView.videoLayer.reply(image)
pump { applied == 1 }
check(main.cropExitOverlay?.imageView.frame == initial, "bridge starts at the selected region in the editor")
let pixels = NSBitmapImageRep(data: main.cropExitOverlay!.imageView.image!.tiffRepresentation!)!
let color = pixels.colorAt(x: pixels.pixelsWide / 2, y: pixels.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
check(color.blueComponent > 0.9 && color.redComponent < 0.1, "bridge crops source pixels rather than stretching the uncropped frame")
check(main.cropExitOverlay?.hitTest(NSPoint(x: 10, y: 10)) === main.cropExitOverlay &&
      main.cropExitOverlay?.hitTest(NSPoint(x: -5, y: -5)) == nil, "bridge blocks playback clicks within its bounds only")
main.finishCropExitTransition()
pump { main.videoView.videoLayer.requests.count == 1 }
main.finishCropExitTransition()
check(main.cropExitOverlay != nil, "the live video remains covered until its first new draw completes")
main.videoView.videoLayer.reply(image)
pump { !main.isCropExitInProgress }
check(main.videoViewContainer.subviews.isEmpty, "the new rendered frame releases the bridge without a leftover overlay")

for failure in ["filter", "capture", "media", "cancel", "inactive"] {
  let fixture = MainWindowController(); var calls = 0
  start(fixture) { calls += 1; return failure != "filter" }
  if failure == "media" { fixture.player.info.trackSelectionGeneration += 1 }
  if failure == "cancel" { fixture.cancelCropExitTransition() }
  if failure == "inactive" { fixture.interactiveMode.isActive = false }
  fixture.videoView.videoLayer.reply(failure == "capture" ? nil : image)
  pump { !fixture.isCropExitInProgress }
  check(calls == (["media", "cancel", "inactive"].contains(failure) ? 0 : 1),
        "\(failure) preserves the editor/media boundary and removes the bridge")
}
let same = MainWindowController()
start(same) { true }
same.videoView.videoLayer.reply(image)
pump { !same.videoView.videoLayer.requests.isEmpty }
same.videoView.videoLayer.reply(image)
pump { !same.isCropExitInProgress }
check(same.videoViewContainer.subviews.isEmpty, "unchanged/full-source exits finish without waiting for a nonexistent reconfiguration")
let earlyAnimation = MainWindowController()
start(earlyAnimation) { earlyAnimation.player.mpv.options["vf"] = "new"; return true }
earlyAnimation.videoView.videoLayer.reply(image)
pump { earlyAnimation.cropExitOverlay?.isPreparing == false }
earlyAnimation.startWindowAnimation(to: earlyAnimation.videoViewContainer.bounds)
pump { earlyAnimation.cropExitOverlay?.animationComplete == true }
check(earlyAnimation.isCropExitInProgress, "a completed window animation cannot expose an old video frame")
earlyAnimation.finishCropExitTransition()
pump { !earlyAnimation.videoView.videoLayer.requests.isEmpty }
earlyAnimation.videoView.videoLayer.reply(image)
pump { !earlyAnimation.isCropExitInProgress }
check(earlyAnimation.videoViewContainer.subviews.isEmpty, "render readiness and window animation completion meet at one cleanup boundary")

let snapshots = SnapshotFixture()
var replies: [NSImage?] = []
for _ in 0..<2 { Task { @MainActor in replies.append(await snapshots.captureSnapshot()) } }
pump { snapshots.updates == 2 }
check(replies.isEmpty, "concurrent crop and Live Text captures remain pending until a draw")
snapshots.deliver(image)
pump { replies.count == 2 }
check(replies.allSatisfy { $0 === image }, "concurrent readers receive the same rendered image without cancelling one another")
Task { @MainActor in replies.append(await snapshots.captureSnapshot()) }
pump { snapshots.updates == 3 }
snapshots.cancelSnapshots()
pump { replies.count == 3 }
check(replies[2] == nil, "render shutdown releases pending image continuations")
Task { @MainActor in replies.append(await snapshots.captureSnapshot()) }
pump { replies.count == 4 }
check(replies[3] == nil && snapshots.updates == 3, "a capture after render shutdown completes without queueing a draw")
print("Completed \(checks) crop transition checks using production methods and the native overlay.")
