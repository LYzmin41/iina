extension AspectRatioView {
  var testedField: NSTextField { input }
  var hasFocusMonitor: Bool { inputFocusMonitor != nil }
  func checkClick(_ event: NSEvent) { dismissInputFocus(for: event) }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let player = PlayerCore()
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                      styleMask: [.titled], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
fileprivate let view = AspectRatioView(player: player)
window.contentView!.addSubview(view)
view.frame = window.contentView!.bounds
view.scrollView.frame = view.bounds
view.scrollView.documentView!.frame = view.bounds
let field = view.testedField
field.frame = NSRect(x: 240, y: 40, width: 40, height: 24)
var checks = 0
func check(_ condition: Bool, _ message: String) {
  precondition(condition, message)
  checks += 1
  print("PASS: \(message)")
}
func click(_ point: NSPoint, in targetWindow: NSWindow = window) -> NSEvent {
  NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                    timestamp: 0, windowNumber: targetWindow.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
}
func focusField() {
  check(window.makeFirstResponder(field) && field.currentEditor() != nil,
        "native field editor accepts focus")
}
check(field.focusRingType == .exterior, "aspect input keeps its native exterior focus ring")
check(view.hasFocusMonitor, "attaching the view installs outside-click routing")
focusField()
let inside = field.convert(NSPoint(x: 10, y: 10), to: nil)
view.checkClick(click(inside))
check(field.currentEditor() != nil, "click inside the input preserves editing")
let otherWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                           styleMask: [.titled], backing: .buffered, defer: false)
otherWindow.isReleasedWhenClosed = false
view.checkClick(click(NSPoint(x: 5, y: 5), in: otherWindow))
check(field.currentEditor() != nil, "click in a different window leaves this editor alone")
view.checkClick(click(NSPoint(x: 5, y: 5)))
check(field.currentEditor() == nil && window.firstResponder === window,
      "outside label/background click ends editing and returns focus to the window")
let nextField = NSTextField(frame: NSRect(x: 10, y: 100, width: 50, height: 24))
window.contentView!.addSubview(nextField)
focusField()
view.checkClick(click(NSPoint(x: 20, y: 110)))
check(window.makeFirstResponder(nextField) && nextField.currentEditor() != nil,
      "outside click still allows another input to take focus")
window.makeFirstResponder(nil)
view.removeFromSuperview()
check(!view.hasFocusMonitor, "detaching the view removes its event monitor")
window.contentView!.addSubview(view)
check(view.hasFocusMonitor, "reattaching restores one active monitor")
focusField()
view.checkClick(click(NSPoint(x: 5, y: 5)))
check(field.currentEditor() == nil, "outside dismissal works after reattachment")
view.removeFromSuperview()
print("Completed \(checks) production-view focus checks; native responder state, synthetic events and unrelated player/layout stubs.")
