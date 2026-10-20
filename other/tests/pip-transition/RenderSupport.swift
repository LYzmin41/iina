import Cocoa
import OpenGL
import QuartzCore
class ReadLock { var value = false; func withReadLock<T>(_ body: (Bool) -> T) -> T { body(value) } }
class MPV { var hasFrame = false; var polls = 0; func shouldRenderUpdateFrame() -> Bool { polls += 1; return hasFrame } }
class Player { let mpv = MPV() }
class Video { let player = Player(); let uninitialized = ReadLock() }
class GeometryLayer: CAOpenGLLayer {
 let videoView = Video()
 var inLiveResize = false
 var forceDraw = false
 var lastRenderedPixelSize: CGSize?
// PRODUCTION_GEOMETRY

}
let app = NSApplication.shared
let ctx = CGLContextObj(bitPattern: 1)!
let pf = OpaquePointer(bitPattern: 2)!
var checks = 0
func check(_ value: Bool, _ message: String) { if !value { print("FAILED: " + message); exit(1) }; checks += 1 }
for scale: CGFloat in [1, 2] {
 let layer = GeometryLayer()
 layer.bounds = CGRect(x: 0, y: 0, width: 900, height: 507)
 layer.contentsScale = scale
 func canDraw() -> Bool { layer.canDraw(inCGLContext: ctx, pixelFormat: pf, forLayerTime: 0, displayTime: nil) }
 layer.forceDraw = true
 check(canDraw(), "first explicit frame needs a surface")
 layer.forceDraw = false
 layer.lastRenderedPixelSize = CGSize(width: 900 * scale, height: 507 * scale)
 check(!canDraw(), "same paused geometry does not render repeatedly")
 layer.bounds.size = CGSize(width: 328, height: 185)
 check(canDraw(), "paused PiP shrink must render without a new decoded frame")
 layer.lastRenderedPixelSize = CGSize(width: 328 * scale, height: 185 * scale)
 check(!canDraw(), "completed shrink does not repeat")
 layer.invalidatePIPDisplay()
 check(canDraw(), "new native surface at the same size must render")
 layer.lastRenderedPixelSize = CGSize(width: 328 * scale, height: 185 * scale)
 check(!canDraw(), "new surface does not render repeatedly")
 layer.bounds.size = CGSize(width: 900, height: 507)
 check(canDraw(), "paused flyback enlargement must render")
 layer.lastRenderedPixelSize = CGSize(width: 900 * scale, height: 507 * scale)
 layer.contentsScale = scale == 1 ? 2 : 1
 check(canDraw(), "Retina scale change must render")
 layer.lastRenderedPixelSize = CGSize(width: 900 * layer.contentsScale, height: 507 * layer.contentsScale)
 check(!canDraw(), "stable Retina geometry does not render repeatedly")
 layer.videoView.player.mpv.hasFrame = true
 check(canDraw(), "normal live playback still renders")
 layer.videoView.player.mpv.hasFrame = false
 layer.forceDraw = true
 check(canDraw(), "explicit handoff redraw still renders")
 layer.videoView.uninitialized.value = true
 check(!canDraw(), "teardown prevents forced render")
 layer.videoView.uninitialized.value = false
 layer.inLiveResize = true
 check(!canDraw(), "main-thread live resize still skips rendering")
 layer.inLiveResize = false
 layer.bounds.size = .zero
 check(!canDraw(), "empty surface never renders")
}
print("Passed \(checks) production geometry render checks")
