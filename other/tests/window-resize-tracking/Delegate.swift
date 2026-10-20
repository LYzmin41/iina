// AppKit window and pointer fixtures around the production resize delegate methods.
enum Preference {
  enum OSCPosition { case floating, bottom }
  static var unlockWindowAspectRatio = false
}
enum FullscreenState { case windowed, fullscreen }
class ResizeWindow: NSWindow {
  var live = true
  var flags: NSEvent.ModifierFlags = []
  override var inLiveResize: Bool { live }
  override var resizeFlags: NSEvent.ModifierFlags { flags }
}
class VideoLayer { var inLiveResize = false }
class Video { var videoLayer = VideoLayer() }
class LiveText { func clearAnalysis() {}; func requestAnalysis() {} }
class State { var active = true }
class Info { var state = State() }
class Player { var info = Info() }
class Panel { func updatePosition() {} }
class DelegateFixture {
  var loaded = true
  var isApplyingVideoTransformWindowFrame = false
  var finishedAspectTransitions = 0
  func finishVideoAspectTransition() { finishedAspectTransitions += 1 }
  func resetVideoTransformWindowArea() {}
  var window: NSWindow?
  var fsState = FullscreenState.windowed
  var windowResizeSession: WindowResizeSession?
  var testMouse = NSPoint.zero
  var oscPosition = Preference.OSCPosition.floating
  let minimumWindowSize = NSSize(width: 400, height: 225)
  var currentWindowAspectRatio: NSSize { window!.aspectRatio }
  let videoView = Video()
  let liveText = LiveText()
  let player = Player()
  let oscFloatingView = Panel()
  func invalidateFloatingOSCLayout() {}
  func updateWindowParametersForMPV() {}
  func windowFrameConstrainedToScreen(_ frame: NSRect, screenFrame: NSRect?) -> NSRect { frame }
  // PRODUCTION_METHODS
}
let app = NSApplication.shared
let window = ResizeWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 450),
                          styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
window.aspectRatio = NSSize(width: 16, height: 9)
let fixture = DelegateFixture()
fixture.window = window
let start = NSPoint(x: window.frame.maxX - 2, y: window.frame.maxY - 2)
let startNotification = Notification(name: NSWindow.willStartLiveResizeNotification, object: window)
let endNotification = Notification(name: NSWindow.didEndLiveResizeNotification, object: window)
let nativeProposal = NSSize(width: 550, height: 309.375)
var checks = 0
func check(_ result: @autoclosure () -> Bool, _ label: String) {
  precondition(result(), label)
  checks += 1
}
fixture.testMouse = start
fixture.windowWillStartLiveResize(startNotification)
check(fixture.windowResizeSession != nil, "Locked live resize captures its initial grip")
for dx: CGFloat in [-100, -50, 0, 50, 100, -50, 0] {
  for dy: CGFloat in [-200, 0, 200] {
    fixture.testMouse = NSPoint(x: start.x + dx, y: start.y + dy)
    let expected = NSSize(width: 800 + dx, height: (800 + dx) * 9 / 16)
    let size = fixture.windowWillResize(window, to: nativeProposal)
    check(size == expected, "Delegate must follow pointer displacement regardless of native aspect proposals")
    // Simulate intermediate native frames: subsequent calls must still use the initial grip.
    window.setFrame(NSRect(origin: window.frame.origin, size: size), display: false)
  }
}
fixture.testMouse = NSPoint(x: start.x - 600, y: start.y)
check(fixture.windowWillResize(window, to: nativeProposal) == fixture.minimumWindowSize,
      "Pointer-based corner resize still honors the existing proportional minimum")
window.maxSize = NSSize(width: 900, height: 600)
fixture.testMouse = NSPoint(x: start.x + 400, y: start.y)
check(fixture.windowWillResize(window, to: nativeProposal) == NSSize(width: 900, height: 506.25),
      "Pointer-based resize respects native maximum size without breaking the ratio")
window.live = false
check(fixture.windowWillResize(window, to: nativeProposal) == nativeProposal, "Programmatic resizing keeps its native proposal")
window.live = true
Preference.unlockWindowAspectRatio = true
check(fixture.windowWillResize(window, to: nativeProposal) == nativeProposal, "Unlocking the aspect ratio bypasses proportional pointer tracking")
fixture.windowWillStartLiveResize(startNotification)
check(fixture.windowResizeSession == nil, "Unlocked resize cannot retain a prior locked session")
Preference.unlockWindowAspectRatio = false
fixture.fsState = .fullscreen
fixture.windowWillStartLiveResize(startNotification)
check(fixture.windowResizeSession == nil, "Fullscreen transitions bypass windowed resize tracking")
fixture.fsState = .windowed
window.flags = .option
fixture.windowWillStartLiveResize(startNotification)
check(fixture.windowResizeSession == nil, "Option resizing retains the native symmetric resize policy")
window.flags = []
fixture.testMouse = NSPoint(x: window.frame.maxX, y: window.frame.maxY)
fixture.windowWillStartLiveResize(startNotification)
check(fixture.windowResizeSession != nil, "A later gesture captures a fresh grip")
fixture.isApplyingVideoTransformWindowFrame = true
let finishedBeforeAutomaticResize = fixture.finishedAspectTransitions
fixture.windowWillStartLiveResize(startNotification)
check(fixture.windowResizeSession == nil && fixture.finishedAspectTransitions == finishedBeforeAutomaticResize,
      "Automatic frame animation cannot capture pointer resize or cancel aspect fill")
fixture.isApplyingVideoTransformWindowFrame = false
fixture.player.info.state.active = false
fixture.windowDidEndLiveResize(endNotification)
check(fixture.windowResizeSession == nil, "Ending resize clears tracking even when playback has stopped")
print("Window resize delegate: \(checks) checks passed")
