setbuf(stdout, nil)
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  precondition(value(), message); checks += 1; print("PASS: \(message)")
}
let a = URL(fileURLWithPath: "/tmp/video-A.mkv"), b = URL(fileURLWithPath: "/tmp/video-B.mkv")
check(Aspect(string:"0:1") == nil && Aspect(string:"1:0") == nil &&
      Aspect(string:String(repeating:"9",count:400)+":1") == nil,
      "invalid or overflowing proportions never create an unusable aspect object")
let p = PlayerFixture()
p.captureDefaults()
p.start(a)
p.mpv.options["video-aspect-override"] = "4:3"
p.mpv.options["video-rotate"] = "90"
p.mpv.options["video-zoom"] = "0.4"
p.info.unsureAspect = "4:3"; p.info.unsureCrop = "Custom"
let crop = MPVFilter.crop(w: 1000, h: 600, x: 100, y: 60); crop.label = Constants.FilterName.crop
p.info.cropFilter = crop
let unrelated = MPVFilter(rawString: "@plugin:negate")!
let unrelatedAfter = MPVFilter(rawString: "@after:hflip")!
p.mpv.videoFilters = [unrelated, crop, unrelatedAfter]
p.scopedTrackSettings.video[2] = VideoTrackProcessing(aspect: "16:9", rotation: 270)
p.scopedTrackSettings.setTarget(2, for: .videoGeometry)
p.info.videoTrackOrder = [2,1]; p.info.activeVideo = [2]
// A manual load updates currentURL before on_unload runs.
p.info.currentURL = b
p.save()
check(p.videoGeometrySession[a] != nil && p.videoGeometrySession[b] == nil,
      "early manual-open URL cannot save A's geometry under B")
p.start(b)
check(p.mpv.options["video-aspect-override"] == "-1" && p.info.rotation == 0,
      "unvisited B does not inherit A's aspect or rotation")
check(p.info.cropFilter == nil && p.info.unsureCrop == "None", "unvisited B has no stale crop")
check(p.mpv.videoFilters.contains { $0.label == "plugin" }, "unrelated plugin filters survive media geometry restoration")
check(p.scopedTrackSettings.video.isEmpty, "B does not inherit A's track profiles")
check(p.mpv.options["video-zoom"] == "0", "unvisited B resets A's video zoom")
p.save()
p.start(a)
check(p.info.unsureAspect == "4:3" && p.info.rotation == 90, "A restores its own aspect and rotation")
check(p.info.cropFilter?.isEqual(crop) == true && p.info.unsureCrop == "Custom", "A restores committed crop and its description")
check(p.mpv.videoFilters.map(\.label) == ["plugin",Constants.FilterName.crop,"after"],
      "restoration preserves crop order relative to unrelated filters")
check(p.mpv.options["video-zoom"] == "0.4", "A restores video zoom")
check(p.scopedTrackSettings.video[2]?.rotation == 270 && p.scopedTrackSettings.target(.videoColor) == 2,
      "A restores per-track settings and its shared editing target")
check(p.info.videoTrackOrder == [2,1] && p.refreshes.last == [2], "A restores selected video membership and order")
p.reloadSavedIINAfilters()
check(p.info.unsureCrop == "Custom", "playback restart does not erase the crop preset description")
// Reset/default is a meaningful state and must replace earlier saved edits.
p.mpv.options["video-aspect-override"] = "-1"; p.mpv.options["video-rotate"] = "0"
p.mpv.videoFilters = [unrelated]; p.info.unsureCrop = "None"
p.scopedTrackSettings.video = [:]; p.info.activeVideo = []
p.save(); p.start(b); p.save(); p.start(a)
check(p.info.unsureAspect == "Default" && p.info.cropFilter == nil && p.scopedTrackSettings.video.isEmpty,
      "Reset remains reset after A-B-A instead of resurrecting old edits")
check(p.refreshes.last == [], "explicit None video membership survives reopening")
// Cancel an editor before snapshotting the committed state.
p.mainWindow.interactiveMode.onExit = { p.mpv.videoFilters = [crop]; p.info.cropFilter = crop; p.info.unsureCrop = "Saved" }
p.save(); p.start(b); p.save(); p.start(a)
check(p.info.cropFilter?.isEqual(crop) == true, "leaving during crop editing saves the committed selection")
// Failed loads must not overwrite the saved state for a known item.
p.save(); let count = p.videoGeometrySession.count
p.start(a, loaded: false); p.mpv.videoFilters = []; p.save()
check(p.videoGeometrySession.count == count && p.videoGeometrySession[a]?.filters.isEmpty == false,
      "failed reopen cannot overwrite an earlier successful snapshot")
// UI references must follow the real filter list even after external commands.
p.info.flipFilter = MPVFilter.flip(); p.info.mirrorFilter = MPVFilter.mirror()
p.mpv.videoFilters = []; p.reloadSavedIINAfilters()
check(p.info.cropFilter == nil && p.info.flipFilter == nil && p.info.mirrorFilter == nil && p.info.unsureCrop == "None",
      "removed/watch-later filters cannot leave phantom crop/flip/mirror UI state")
check(MediaVideoGeometryState.aspectDescription(for: 16.0/9, preferred: "Default") == "16:9",
      "watch-later aspect is reflected accurately in the menu")
p.start(a); p.info.videoTracks = [.init(id: 1)]
p.videoGeometrySession[a]?.videoTarget = 2
p.restoreForTesting()
check(p.scopedTrackSettings.target(.videoGeometry) == 0 && p.scopedTrackSettings.video[2] == nil,
      "missing track IDs cannot restore profiles onto another source")
p.mpv.failWrites = true; p.start(b)
check(p.warnings > 0, "native restore failures are reported")
p.mpv.failWrites = false
// Source dimensions in file metadata must not determine presets after track switches.
for (source, display, rotation) in [
  (NSSize(width:1080,height:1920), NSSize(width:1080,height:1920), 0),
  (NSSize(width:720,height:576), NSSize(width:1024,height:576), 0),
  (NSSize(width:1920,height:1080), NSSize(width:1920,height:1080), 90)
] {
  p.geometry = CropVideoGeometry(sourceSize: source, displaySize: display, rotation: rotation)
  p.setCrop(fromString: "4:3")
  let filter = p.info.cropFilter!, rect = filter.params!
  let w = Double(rect["w"]!)!, h = Double(rect["h"]!)!
  check(w <= source.width && h <= source.height && w > 0 && h > 0,
        "crop preset stays inside the currently decoded rotated/anamorphic source")
  let selected = p.geometry.selectionRect(forFilterRect: NSRect(x:Double(rect["x"]!)!, y:Double(rect["y"]!)!, width:w,height:h))
  check(abs(selected.width/selected.height*p.geometry.pixelAspectRatio - 4.0/3) < 0.01,
        "crop preset uses display proportions rather than stale file pixels")
}
p.geometry = CropVideoGeometry(sourceSize:.zero,displaySize:.zero,rotation:0)
p.info.cropFilter = nil; p.setCrop(fromString:"16:9")
check(p.info.cropFilter == nil, "crop with no decoded video safely does nothing")
p.mpv.options["window-scale"] = "1"
for pending in 0..<3 {
  p.info.justStartedFile = pending == 0; p.info.justOpenedFile = pending == 1; p.info.state.loaded = pending != 2
  p.windowScaleChanged()
}
check(p.mainWindow.scales.isEmpty, "loading/watch-later window-scale notifications never resize a window")
p.info.justStartedFile = false; p.info.justOpenedFile = false; p.info.state.loaded = true
p.windowScaleChanged()
check(p.mainWindow.scales == [1], "explicit scale commands still reach the native resize action")
let stopped = PlayerFixture()
stopped.captureDefaults(); stopped.start(a)
stopped.mpv.options["panscan"] = "1"
stopped.mainWindow.videoAspectTransitionOriginalPanscan = 0.3
stopped.save()
check(stopped.videoGeometrySession[a]?.options["panscan"] == "0.3",
      "Stop during an animated transform never snapshots the temporary fill")
let cli = PlayerFixture()
cli.mpv.options["video-aspect-override"] = "16:9"
cli.start(a)
check(cli.info.unsureAspect == "16:9", "first-load defaults include CLI options applied after engine initialization")
cli.mpv.options["video-aspect-override"] = "4:3"; cli.save(); cli.start(b)
check(cli.info.unsureAspect == "16:9", "new media restores configured defaults without inheriting edits")
let configuredCrop = PlayerFixture()
configuredCrop.mpv.videoFilters = [crop]
configuredCrop.start(a)
check(configuredCrop.info.cropFilter != nil && configuredCrop.info.unsureCrop != "None",
      "a configured crop is never presented as None at the first load")
print("Completed \(checks) production video geometry session checks.")

extension PlayerFixture { func restoreForTesting() { restoreVideoTrackGeometryForCurrentMedia() } }
