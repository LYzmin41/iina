import Cocoa
import Darwin
setbuf(stdout, nil)

// Playback, preferences and UI side effects are fixture boundaries. The native
// frame calculation, frame application, scale action and aspect lock are production.
enum Preference {
  enum Key { case resizeWindowTiming, resizeWindowOption, usePhysicalResolution, disableAnimations, edgeToEdgeVideo, dockedControlBarAndTitlebar }
  enum ResizeWindowTiming { case always, onlyWhenOpen, never }
  enum ResizeWindowOption { case fitScreen, normal; var ratio: Double { 1 } }
  enum OSCPosition { case floating, top, bottom }
  static var unlockWindowAspectRatio = false
  static var physical = false
  static var animationsDisabled = true
  static func bool(for key: Key) -> Bool { key == .usePhysicalResolution ? physical : (key == .disableAnimations && animationsDisabled) || key == .edgeToEdgeVideo }
  static func `enum`<T>(for key: Key) -> T {
    (key == .resizeWindowTiming ? ResizeWindowTiming.always as Any : ResizeWindowOption.normal as Any) as! T
  }
}
struct FullscreenState: Equatable {
  var isFullscreen = false
  var priorWindowedFrame: NSRect?
  static let windowed = FullscreenState()
}
class InteractiveFixture { var isActive = false; var resizes = 0; func resize() { resizes += 1 } }
struct TrackFixture { var id = 0; static let noneAudioTrack = TrackFixture() }
enum MPVTrack { enum TrackType { case video, audio, sub, secondSub } }
class InfoFixture {
 struct State { var active = true; var loaded = true }
 var state = State()
 var justStartedFile = false, justOpenedFile = false
 var trackSelectionGeneration = 0
 var unsureAspect = "Default"
 var displayWidth: Int? = 1280, displayHeight: Int? = 720
 var mixedAudioTrackIDs: Set<Int> = []
 var rotation = 0, aid = 1
 var videoWidth: Int? = 1280
 var cachedWindowScale = 0.0
 func currentTrack(_ type: MPVTrack.TrackType) -> TrackFixture? { nil }
 func orderedTrackList(_ type: MPVTrack.TrackType) -> [TrackFixture] { [] }
 func activeTrackIDs(_ type: MPVTrack.TrackType) -> Set<Int> { mixedAudioTrackIDs.isEmpty ? (aid > 0 ? [aid] : []) : mixedAudioTrackIDs }
}
enum MPVOption {
 enum Window { static let windowScale = "window-scale" }
 enum PlaybackControl { static let pause = "pause" }
 enum Video { static let panscan = "panscan"; static let videoAspectOverride = "video-aspect-override"; static let videoRotate = "video-rotate" }
 enum TrackSelection { static let aid = "aid", vid = "vid", sid = "sid" }
 enum Subtitles { static let secondarySid = "secondary-sid" }
 enum Miscellaneous { static let lavfiComplex = "lavfi-complex" }
}
enum MPVProperty { static let dwidth = "dwidth", dheight = "dheight", coreIdle = "core-idle" }
enum NotificationFixture { case iinaAIDChanged }
enum OSDFixture { case track(TrackFixture, position: Int? = nil), custom(String) }
struct Regex {
  static let aspect = Regex()
  func matches(_ value: String) -> Bool { value.range(of: #"\A\d+(\.\d+)?:\d+(\.\d+)?\Z"#, options: .regularExpression) != nil }
}
class MPVFixture {
  enum LogLevel { case verbose }
  var scaleWrites = 0
  func setDouble(_ name: String, _ value: Double, level: LogLevel) { scaleWrites += 1 }
  var mutation: ((String, String) -> Void)?
  var writes: [(String, String)] = []
  var integers: [String: Int] = [:]
  var idle = false
  var panscan = 0.0
  var stringResult: Int32 = 0
  func getInt(_ key: String) -> Int { integers[key] ?? 0 }
  func getString(_ key: String) -> String? { nil }
  func getFlag(_ key: String) -> Bool { key == "pause" || idle }
  func getDouble(_ key: String) -> Double { key == "panscan" ? panscan : -1 }
  @discardableResult func setString(_ name: String, _ value: String) -> Int32 {
    if stringResult < 0 { return stringResult }
    writes.append((name,value))
    if name == "file-local-options/panscan" { panscan = Double(value)! }
    mutation?(name,value)
    return 0
  }
  func setInt(_ name: String, _ value: Int) { writes.append((name, String(value))); mutation?(name, String(value)) }
}
class EventsFixture { enum Event { case windowSizeAdjusted }; var count = 0; func emit(_ event: Event, data: NSRect) { count += 1 } }
class PlayerFixture {
  weak var mainWindow: CropWindowFixture!
  let mpv = MPVFixture()
  private func reconcileTrackGraph() {}
  func setVideoTracks(_ ids: Set<Int>) -> Bool { mpv.setInt(MPVOption.TrackSelection.vid,ids.first ?? 0); getSelectedTracks(); return true }
  func setAudioTracks(_ ids: Set<Int>) -> Bool {
    mpv.setInt(MPVOption.TrackSelection.aid, ids.first ?? 0)
    getSelectedTracks()
    return true
  }
  // PRODUCTION_PLAYER_TRANSFORMS
  var videoSizeForDisplay = (3840, 924)
  var info = InfoFixture()
  var events = EventsFixture()
  var disableWindowAnimation = true
  func generateThumbnails() {}
  var notifications = 0, selectedRefreshes = 0
  func getSelectedTracks() { selectedRefreshes += 1 }
  func postNotification(_ name: NotificationFixture) { notifications += 1 }
  func sendOSD(_ message: OSDFixture) {}
  func notifyWindowVideoSizeChanged() { mainWindow.handleVideoSizeChange(keepWindowSize: false) }
}
class PIPFixture { var aspectRatio = NSSize.zero }
struct GeometryFixture { var hasExplicitSize = false }
struct MemoryUsage { static let shared = MemoryUsage(); func logUsage(_ text: String) {} }
extension NSWindow { func selectDefaultScreen() -> NSScreen { screen ?? NSScreen.main! } }
// PRODUCTION_CONSTANTS
// PRODUCTION_EXTENSIONS
class TransitionLayerFixture { var updates = 0; func update(force: Bool) { updates += 1 } }
class TransitionVideoFixture {
 var active = 0, idle = 0; let videoLayer = TransitionLayerFixture()
 func displayActive() { active += 1 }; func displayIdle() { idle += 1 }
}
class CropWindowFixture {
  var window: NSWindow?
  var loaded = true
  var interactiveMode = InteractiveFixture()
  var player = PlayerFixture()
  var fsState = FullscreenState.windowed
  var oscPosition = Preference.OSCPosition.floating
  private var isApplyingVideoTransformWindowFrame = false
  private var videoTransformWindowArea: CGFloat?
  private var videoTransformWindowSize: NSSize?
  private var videoAspectTransition: (panscan: Double, mediaGeneration: Int)?
  enum PIPStatus { case notInPIP, inPIP }
  var pipStatus = PIPStatus.notInPIP
  let videoView = TransitionVideoFixture()
  var pip = PIPFixture()
  var titleBarView = NSView()
  var muteButton = NSButton(), volumeSlider = NSSlider()
  var shouldApplyInitialWindowSize = false
  var cachedGeometry: GeometryFixture?
  var isVideoLoaded = true
  var scaleUpdates: Int { player.mpv.scaleWrites }
  func log(_ text: String) {}
  func notifyLiveResize() { resetVideoTransformWindowArea() }
  func determineScreenToUse(_ window: NSWindow) -> NSScreen { window.selectDefaultScreen() }
  func windowFrameFromGeometry(newSize: NSSize, screen: NSScreen) -> NSRect? { nil }
  func updateMinimumWindowSize() {}
  func updatePlayTime(withDuration: Bool, andProgressBar: Bool) {}
  // PRODUCTION_CONTROLLER_METHODS
}
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  precondition(value(),message); checks += 1; print("PASS: \(message)")
}
func near(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 1) -> Bool { abs(a-b) <= tolerance }
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let controller = CropWindowFixture()
let screen = NSScreen.main!.visibleFrame
let original = NSRect(x: screen.midX - 250, y: screen.midY - 150, width: 500, height: 300)
class ResizeNotifyingWindow: NSWindow {
 var onFrame: (() -> Void)?
 override func setFrame(_ rect: NSRect, display: Bool) { onFrame?(); super.setFrame(rect,display:display) }
 override func setFrame(_ rect: NSRect, display: Bool, animate: Bool) { onFrame?(); super.setFrame(rect,display:display,animate:animate) }
}
let window = ResizeNotifyingWindow(contentRect: original, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
controller.window = window
controller.player.mainWindow = controller
window.onFrame = { controller.notifyLiveResize() }
for unlocked in [false,true] {
  Preference.unlockWindowAspectRatio = unlocked
  for physical in [false,true] {
    Preference.physical = physical
    for size in [(3840,924), (1080,1920), (3840,2160), (2,1), (1,2)] {
      window.setFrame(original, display: false)
      controller.player.videoSizeForDisplay = size
      controller.handleVideoSizeChange(keepWindowSize: false)
      if unlocked {
        check(window.frame == original, "unlocked crop keeps the freely chosen frame (physical=\(physical))")
        check(window.aspectRatio == .zero, "unlocked window stays unlocked")
      } else {
        let ratio = CGFloat(size.0) / CGFloat(size.1)
        check(near(window.frame.width/window.frame.height, ratio, tolerance: 0.015),
              "locked window matches crop aspect without letterboxing for \(size) (physical=\(physical))")
        check(window.frame.width < 1000 && window.frame.height < 1000,
              "crop sizing derives from the 500pt window rather than source pixels")
        check(near(window.frame.midX, original.midX) && near(window.frame.midY, original.midY),
              "crop resize retains window center")
        check(near(window.aspectRatio.aspect, ratio, tolerance: 0.0001), "native Lock follows the crop aspect")
      }
      check(controller.pip.aspectRatio == NSSize(width:size.0,height:size.1), "PiP tracks crop display geometry independently")
      let settled = window.frame
      controller.handleVideoSizeChange(keepWindowSize: false)
      check(near(window.frame.width, settled.width) && near(window.frame.height, settled.height),
            "repeated reconfiguration is stable for \(size): \(settled) -> \(window.frame) (unlocked=\(unlocked))")
    }
  }
}
// Repeated aspect switches preserve the user's scale, including a minimum-size clamp.
Preference.unlockWindowAspectRatio = false
let roundTrip = NSRect(x: screen.midX-270, y: screen.midY-152, width:540, height:304)
window.setFrame(roundTrip, display:false)
for _ in 0..<4 {
  for size in [(1280,720), (960,720), (720,1280), (1280,720)] {
    controller.player.videoSizeForDisplay = size
    controller.handleVideoSizeChange(keepWindowSize:false)
    if size.0 == 720 {
      // Native titled windows may finish rounding one point after animation.
      let rounded = window.frame.centeredResize(to:NSSize(width:window.frame.width,height:window.frame.height+1))
      window.onFrame = nil
      window.setFrame(rounded,display:false)
      window.onFrame = { controller.notifyLiveResize() }
    }
  }
  check(near(window.frame.width,540) && near(window.frame.height,303.75),
        "landscape/4:3/portrait round trips preserve the original area through minimum constraints")
}
Preference.unlockWindowAspectRatio = false
Preference.physical = false
controller.player.videoSizeForDisplay = (80000,1000)
controller.handleVideoSizeChange(keepWindowSize:false)
controller.player.videoSizeForDisplay = (1280,720)
controller.handleVideoSizeChange(keepWindowSize:false)
check(near(window.frame.width,540) && near(window.frame.height,304), "return from a screen-constrained aspect restores the intended area")
controller.player.videoSizeForDisplay = (3840,2160)
window.setFrame(NSRect(x: original.minX, y: original.minY, width: 874, height: 525), display: false)
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width * window.frame.height, 874*525, tolerance: 2000) && near(window.frame.size.aspect, 16.0/9, tolerance: 0.005),
      "reported 874x525 window adopts 16:9 while retaining its area")
Preference.unlockWindowAspectRatio = false
Preference.physical = false
controller.player.videoSizeForDisplay = (3840,924)
controller.fsState = FullscreenState(isFullscreen: true, priorWindowedFrame: original)
window.setFrame(screen,display:false)
let fullscreenFrame = window.frame
controller.handleVideoSizeChange(keepWindowSize: false)
check(window.frame == fullscreenFrame && controller.fsState.priorWindowedFrame!.width < 1000 &&
      near(controller.fsState.priorWindowedFrame!.size.aspect, CGFloat(3840)/924, tolerance: 0.015),
      "fullscreen stays fullscreen while its prior window fits the crop at the user's scale")
controller.fsState = .windowed
window.setFrame(original,display:false)
controller.interactiveMode.isActive = true
controller.handleVideoSizeChange(keepWindowSize: false)
check(window.frame == original && controller.interactiveMode.resizes == 1,
      "uncropping while the editor is open only lays out its preview")
controller.interactiveMode.isActive = false
controller.handleVideoSizeChange(keepWindowSize: true)
check(window.frame.width < 1000 && near(window.frame.size.aspect, CGFloat(3840)/924, tolerance: 0.015),
      "full-source exit refresh can adapt the window from its current scale")
controller.player.info.justStartedFile = true
controller.player.info.justOpenedFile = true
controller.shouldApplyInitialWindowSize = true
controller.player.videoSizeForDisplay = (960,540)
controller.handleVideoSizeChange(keepWindowSize: false)
check(window.frame.size == NSSize(width:960,height:540),
      "a fresh window keeps explicit startup sizing")
// All subsequent loads share the established window scale, including manual open
// and repeated first-frame notifications before playback-restart clears flags.
for unlocked in [false, true] {
  Preference.unlockWindowAspectRatio = unlocked
  for manuallyOpened in [false, true] {
    window.aspectRatio = .zero
    window.setFrame(original, display: false)
    for source in [(3840,2160), (1080,1920), (3840,924), (3840,2160)] {
      controller.player.info.justStartedFile = true
      controller.player.info.justOpenedFile = manuallyOpened
      controller.player.videoSizeForDisplay = source
      controller.handleVideoSizeChange(keepWindowSize: false)
      let settled = window.frame
      controller.handleVideoSizeChange(keepWindowSize: false)
      check(near(window.frame.width, settled.width) && near(window.frame.height, settled.height),
            "repeated file-start geometry is stable")
      if unlocked {
        check(window.frame == original, "manual/playlist loads retain a freely sized window")
      } else {
        check(window.frame.width < 1000 && window.frame.height < 1000,
              "manual/playlist loads never expand an existing 500pt window to 4K pixels")
        check(near(window.frame.size.aspect, CGFloat(source.0)/CGFloat(source.1), tolerance: 0.015),
              "new media gets its display aspect at the existing scale")
      }
    }
    if !unlocked {
      check(near(window.frame.width * window.frame.height, original.width * original.height, tolerance: 2000),
            "playlist round trips retain the requested area across minimum-size clamps")
    }
  }
}
Preference.unlockWindowAspectRatio = false
controller.player.info.justStartedFile = false
controller.player.info.justOpenedFile = false
controller.player.videoSizeForDisplay = (960,540)
controller.setWindowScale(0.75)
check(window.frame.size == NSSize(width:720,height:405) && near(window.aspectRatio.aspect, window.frame.size.aspect, tolerance: 0.001),
      "explicit video scale still changes size with the video aspect locked")
check(controller.player.events.count > 0 && controller.scaleUpdates > 0,
      "geometry change still emits normal UI/MPV synchronization")
for physical in [false, true] {
  Preference.physical = physical
  controller.player.videoSizeForDisplay = (3840,924)
  let scaleFrame = NSRect(x:0,y:0,width:500,height:121)
  controller.updateWindowParametersForMPV(withFrame:scaleFrame)
  let width = physical ? window.convertToBacking(scaleFrame).width : scaleFrame.width
  check(abs(controller.player.info.cachedWindowScale - Double(width)/3840) < 0.000001,
        "MPV scale feedback uses transformed display pixels and the current Retina policy")
}
Preference.physical = false
controller.player.videoSizeForDisplay = (1280,720)
window.setFrame(original,display:false)
controller.setWindowScale(100)
check(near(window.frame.width,screen.width) || near(window.frame.height,screen.height),
      "an explicit oversized scale fits the requested video to the screen")
let beforeInvalidScale = window.frame
controller.setWindowScale(.nan); controller.setWindowScale(-1)
check(window.frame == beforeInvalidScale, "invalid explicit scales cannot damage window geometry")
// Exercise the actual user-facing setters through output-geometry notification.
// Geometry resolution is a fixture boundary; the setters and window handling are production.
for unlocked in [false, true] {
  Preference.unlockWindowAspectRatio = unlocked
  for physical in [false, true] {
    Preference.physical = physical
    for action in ["4:3", "Default", "invalid", "0", "90", "180", "270"] {
      var frames: [NSRect] = []
      for source in [(1280, 720), (3840, 2160)] {
        let prior = NSRect(x: screen.midX - 400, y: screen.midY - 225, width: 800, height: 450)
        window.aspectRatio = .zero
        window.setFrame(prior, display: false)
        controller.player.mpv.mutation = { name, value in
          if name == MPVOption.Video.videoRotate {
            let turn = Int(value)!
            controller.player.videoSizeForDisplay = (turn == 90 || turn == 270) ? (source.1, source.0) : source
          } else {
            controller.player.videoSizeForDisplay = value == "-1" ? source : (source.1 * 4 / 3, source.1)
          }
          controller.handleVideoSizeChange(keepWindowSize: false)
        }
        if let degrees = Int(action) { controller.player.setVideoRotate(degrees) }
        else { controller.player.setVideoAspect(action) }
        let actual = window.frame
        let output = controller.player.videoSizeForDisplay
        if unlocked {
          check(actual == prior && window.aspectRatio == .zero,
                "\(action) retains an unlocked frame independent of clip resolution")
        } else {
          check(actual.width < 1000 && actual.height < 1000,
                "\(action) starts from the 800pt window rather than clip pixels")
          check(near(actual.size.aspect, CGFloat(output.0) / CGFloat(output.1), tolerance: 0.005),
                "\(action) locks the window to the transformed image without bars")
          check(near(actual.midX, prior.midX) && near(actual.midY, prior.midY),
                "\(action) retains the current window center")
        }
        frames.append(actual)
        controller.handleVideoSizeChange(keepWindowSize: false)
        check(near(window.frame.width, actual.width) && near(window.frame.height, actual.height),
              "\(action) settles across repeated output notifications")
      }
      check(near(frames[0].width, frames[1].width) && near(frames[0].height, frames[1].height),
            "\(action) produces the same frame for 720p and 4K sources (unlocked=\(unlocked), physical=\(physical))")
    }
  }
}
controller.player.mpv.mutation = nil
let writes = controller.player.mpv.writes.count
controller.player.setVideoRotate(45)
check(controller.player.mpv.writes.count == writes,
      "unsupported rotation leaves MPV and the sizing policy unchanged")
check(controller.player.info.unsureAspect == "Default", "invalid aspect continues to select the existing Default behavior")
// Track selection can reconfigure video without ever passing through an aspect,
// rotation or crop setter. Exercise the actual track and reconfig methods.
for unlocked in [false, true] {
  Preference.unlockWindowAspectRatio = unlocked
  for physical in [false, true] {
    Preference.physical = physical
    for source in [(1280, 720), (3840, 2160), (1080, 1920)] {
      let prior = NSRect(x: screen.midX - 400, y: screen.midY - 225, width: 800, height: 450)
      window.aspectRatio = .zero
      window.setFrame(prior, display: false)
      controller.player.info.displayWidth = 1280
      controller.player.info.displayHeight = 720
      controller.player.mpv.mutation = { name, value in
        guard name == MPVOption.TrackSelection.vid else { return }
        let output = value == "0" ? (640, 360) : source
        controller.player.videoSizeForDisplay = output
        controller.player.mpv.integers[MPVProperty.dwidth] = output.0
        controller.player.mpv.integers[MPVProperty.dheight] = output.1
        controller.player.onVideoReconfig()
      }
      for id in [0, 1, 0, 1] {
        let before = window.frame
        controller.player.setTrack(id, forType: .video)
        let aspect = CGFloat(controller.player.videoSizeForDisplay.0) / CGFloat(controller.player.videoSizeForDisplay.1)
        if unlocked {
          check(window.frame == prior, "video track/None retains the freely chosen window")
        } else {
          check(window.frame.width < 1000 && window.frame.height < 1000,
                "video track/None stays at the current scale instead of clip pixels")
          check(near(window.frame.size.aspect, aspect, tolerance: 0.005), "video track/None updates locked aspect")
          check(near(window.frame.midX, before.midX) && near(window.frame.midY, before.midY),
                "video track/None retains the window center")
        }
        let settled = window.frame
        controller.player.onVideoReconfig()
        check(window.frame == settled, "repeated track output notifications do not change window scale")
      }
      // Direct MPV output changes use the same policy even without setTrack.
      window.aspectRatio = .zero; window.setFrame(prior, display: false)
      controller.player.videoSizeForDisplay = (3840, 2160)
      controller.player.mpv.integers[MPVProperty.dwidth] = 3840
      controller.player.mpv.integers[MPVProperty.dheight] = 2160
      controller.player.info.displayWidth = 0; controller.player.info.displayHeight = 0
      controller.player.onVideoReconfig()
      check(window.frame == prior, "direct video reconfig retains current frame at unchanged aspect")
    }
  }
}
controller.player.mpv.mutation = { name, value in
  if name == MPVOption.TrackSelection.aid {
    controller.player.mpv.integers[name] = Int(value)!
    controller.player.aidChanged()
  }
}
for unlocked in [false, true] {
  Preference.unlockWindowAspectRatio = unlocked
  let before = window.frame
  for id in [0, 1, 2, 0, 1] {
    controller.player.setTrack(id, forType: .audio)
    check(window.frame == before,
          "audio track/None leaves window geometry and video sizing policy unchanged")
    check(controller.muteButton.isHidden == (id == 0) && controller.volumeSlider.isHidden == (id == 0),
          "audio track/None still updates native volume control visibility")
  }
}
check(controller.player.notifications == 10, "audio selection retains all track-change notifications")
controller.player.mpv.mutation = nil
// Actual transition ownership across renderer/window completion and cancellation.
Preference.unlockWindowAspectRatio = false
Preference.animationsDisabled = false
controller.player.disableWindowAnimation = false
controller.player.info.justStartedFile = false
controller.player.mpv.panscan = 0.35
window.orderFrontRegardless()
check(controller.beginVideoAspectTransition() && controller.player.mpv.panscan == 1,
      "animated aspect change fills the viewport before changing the decoded output")
check(!controller.beginVideoAspectTransition(), "overlapping changes retain one original fill value")
controller.finishVideoAspectTransition()
check(controller.player.mpv.panscan == 0.35, "completion restores the exact prior pan-and-scan setting")
controller.beginVideoAspectTransition()
controller.player.mpv.panscan = 0.2
controller.finishVideoAspectTransition()
check(controller.player.mpv.panscan == 0.2, "a user's intervening fill change is preserved")
controller.player.mpv.panscan = 0.35
var filledDuringFrameApplication = false
window.onFrame = {
  filledDuringFrameApplication = filledDuringFrameApplication || controller.player.mpv.panscan == 1
  controller.notifyLiveResize()
}
controller.player.videoSizeForDisplay = (720,1280)
controller.beginVideoAspectTransition()
controller.handleVideoSizeChange(keepWindowSize:false)
check(filledDuringFrameApplication && controller.player.mpv.panscan == 0.35,
      "fill covers the animated frame application and is restored after it")
window.onFrame = { controller.notifyLiveResize() }
controller.player.mpv.stringResult = -4
check(!controller.beginVideoAspectTransition() && controller.player.mpv.panscan == 0.35,
      "failed temporary fill does not take ownership")
controller.player.mpv.stringResult = 0
for blocked in 0..<6 {
  Preference.unlockWindowAspectRatio = blocked == 0
  Preference.animationsDisabled = blocked == 1
  controller.player.disableWindowAnimation = blocked == 2
  controller.fsState = blocked == 3 ? FullscreenState(isFullscreen:true,priorWindowedFrame:window.frame) : .windowed
  controller.pipStatus = blocked == 4 ? .inPIP : .notInPIP
  controller.interactiveMode.isActive = blocked == 5
  let before = controller.player.mpv.writes.count
  check(!controller.beginVideoAspectTransition() && controller.player.mpv.writes.count == before,
        "free-aspect/disabled-animation/fullscreen/PiP/crop mode does not acquire temporary fill")
}
Preference.unlockWindowAspectRatio = false
Preference.animationsDisabled = false
controller.player.disableWindowAnimation = false
controller.fsState = .windowed
controller.pipStatus = .notInPIP
controller.interactiveMode.isActive = false
controller.beginVideoAspectTransition()
controller.player.info.trackSelectionGeneration += 1
controller.player.mpv.panscan = 0.7
controller.finishVideoAspectTransition()
check(controller.player.mpv.panscan == 0.7, "completion from an old file cannot restore its fill into a new file")
controller.beginVideoAspectTransition()
controller.finishVideoAspectTransition(restore:false)
controller.player.mpv.panscan = 0 // mpv automatically resets file-local options on unload
controller.beginVideoAspectTransition()
controller.finishVideoAspectTransition()
check(controller.player.mpv.panscan == 0, "a new-file cancellation cannot leak the prior file's saved fill")
window.close()
print("Completed \(checks) native crop/rotation/aspect/track window checks.")
