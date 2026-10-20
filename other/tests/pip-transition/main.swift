let app = NSApplication.shared
var count=0
func check(_ value: @autoclosure () -> Bool, _ name: String) {
 precondition(value(),name);count += 1
}
for behavior in [Preference.WindowBehaviorWhenPip.hide,.minimize,.doNothing] {
 for fullscreen in [false,true] {
  for paused in [false,true] {
   Preference.behavior=behavior
   let c=MainWindowController();let w=c.window as! Window
   c.fsState.isFullscreen=fullscreen
   w.simulatedFullscreen=fullscreen
   c.player.info.state=paused ? .paused : .playing
   w.alphaValue=0.85
   c.enterPIP()
   check(c.pipStatus == .inPIP,"entered"); check(c.videoView.videoLayer.isHostedInPIP,"native transaction owned")
   check(c.pipVideo.view === c.videoView,"same live surface")
   check(c.pip.playing == !paused,"playback preserved")
   c.enterPIP();check(c.pip.presented == 1,"duplicate entry suppressed")
   check(c.isWindowHidden == (behavior == .hide && !fullscreen),"hide policy")
   check(w.minimized == (behavior == .minimize && !fullscreen),"minimize policy")
   check(c.pipOverlayView.isHidden == (behavior == .hide && !fullscreen),"placeholder only in retained player")
   if c.isWindowHidden { check(w.orderOutAnimations.last == NSWindow.AnimationBehavior.none,"hide has no fade"); check(w.animationBehavior == .default,"source animation restored") }
   let hidden=c.isWindowHidden
   c.exitPIP()
   check(c.pipStatus == .intermediate,"returning")
   check(c.pip.dismissed == 1,"one native dismissal")
   check(c.pip.replacementWindow === w,"return window")
   check(c.pip.replacementRect == c.videoViewContainer.convert(c.videoViewContainer.bounds,to:nil),"video destination")
   if hidden {
    check(w.alphaValue == 0,"destination concealed")
    check(c.oscFloatingView.isHidden,"OSC hidden during return")
    c.showUI();check(c.oscFloatingView.isHidden,"tracking cannot reveal early")
   }
   c.enterPIP();check(c.pip.presented == 1,"entry blocked during return")
   c.pipWillClose(c.pip);check(c.pipReturnWindowAlpha == (hidden ? 0.85 : nil),"duplicate closure does not overwrite alpha")
   c.pipDidClose(c.pip)
   check(c.pipStatus == .notInPIP,"returned"); check(!c.videoView.videoLayer.isHostedInPIP,"native transaction released")
   check(c.videoView.superview === c.videoViewContainer,"live surface reattached")
   check(abs(w.alphaValue-0.85) < 0.001,"opacity restored")
   check(c.pipReturnWindowAlpha == nil,"return flag cleared")
   if hidden {
    check(!c.oscFloatingView.isHidden,"OSC revealed")
    check(c.titleBarView.revealCalls.contains { $0.0 && $0.1 },"header uses normal animation")
   }
  }
 }
}
PiP.modern = true
for behavior in [Preference.WindowBehaviorWhenPip.hide,.minimize,.doNothing] {
 Preference.behavior=behavior
 let c=MainWindowController();let w=c.window as! Window
 let expected=w.convertToScreen(c.videoViewContainer.convert(c.videoViewContainer.bounds,to:nil))
 c.videoView.beforeHandoff = { check(w.testVisible, "entry drawn before hiding source") }
 c.enterPIP()
 check(w.testVisible && !w.minimized,"source remains until preparation")
 let callback=c.pip.completion!
 c.videoViewContainer.frame.size = NSSize(width: 640,height: 360)
 callback()
 check(c.isWindowHidden == (behavior == .hide),"prepared hide policy")
 check(w.minimized == (behavior == .minimize),"prepared minimize policy")
 if behavior == .hide {
  check(c.pip.window.contentRect(forFrameRect:c.pip.window.frame) == expected,"native launch uses source video geometry")
 }
 check(c.pip.window.frontCalls == 0,"no forced local host presentation")
 check(c.pip.window.animationBehavior == .default,"host animation restored")
 let draws=c.videoView.handoffs
 check(draws == 1, "one preparation draw")
 let frame=c.pip.window.frame
 callback();check(c.videoView.handoffs == draws,"duplicate preparation does not draw")
 c.videoView.beforeHandoff = {
  check(c.videoView.superview === c.videoViewContainer,"return layout owns live view before draw")
  if behavior == .hide { check(w.alphaValue == 0,"return drawn before reveal") }
 }
 callback();check(c.pip.window.frame == frame,"duplicate callback ignored")
 c.exitPIP();c.pipDidClose(c.pip)
 check(c.videoView.handoffs == draws + 1,"one final return draw")
 c.videoView.beforeHandoff = nil
 callback();check(w.testVisible,"late callback cannot hide restored source")
 c.enterPIP()
 callback();check(w.testVisible,"previous presentation callback cannot hide new source")
 c.pip.completion?()
 c.exitPIP();c.pipDidClose(c.pip)
}
Preference.behavior = .hide
let cancelled=MainWindowController();let sourceWindow=cancelled.window as! Window
cancelled.enterPIP();let stale=cancelled.pip.completion!
cancelled.exitPIP();stale()
check(sourceWindow.testVisible,"return before preparation cannot hide source")
cancelled.pipDidClose(cancelled.pip)
print("Native PiP production-method checks passed: \(count)")
