//
//  InteractiveMode.swift
//  iina
//
//  Created by Hechen Li on 2026-06-22.
//  Copyright © 2026 lhc. All rights reserved.
//

import Cocoa

fileprivate let ui = UIHelper.shared

class InteractiveModeController: NSObject, NSTextFieldDelegate, NSPopoverDelegate {
  enum Mode {
    case crop, delogo
  }

  weak var mainWindow: MainWindowController!

  private var cropx = 0
  private var cropy = 0
  private var cropw = 0
  private var croph = 0
  private var presetAspects: [CGFloat] = []
  private var selectedPreset: Int?
  private var videoGeometry = CropVideoGeometry(sourceSize: .zero, displaySize: .zero, rotation: 0)
  private var originalCropFilter: MPVFilter?
  private var originalCropDescription = ""
  private var dimensionEditCenter: NSPoint?
  private var isUpdatingDimension = false
  private var controlBarWidth: NSLayoutConstraint?
  private var controlBarBottom: NSLayoutConstraint?
  private var pinchStartZoom: CGFloat?
  private var pinchAnchor: NSPoint?
  private var originalVideoTransform = CATransform3DIdentity
  private var originalVideoMask: CALayer?
  private let previewMask = CALayer()
  private var editorEventMonitor: Any?
  private var isTrackingEditorMenu = false
  private var aspectPopover: NSPopover?

  private var readableCropString: String {
    "(\(cropx), \(cropy)) (\(cropw)\u{d7}\(croph))"
  }

  private var isFullFrameSelected: Bool {
    cropBoxView.selectedRect == NSRect(origin: .zero, size: cropBoxView.videoSize)
  }

  private(set) var isActive = false
  private(set) var currentMode: Mode?
  private var isPausedPriorToInteractiveMode = false

  private lazy var cropTargetLabel: NSTextField = {
    let label = NSTextField(labelWithString: "")
    label.font = .systemFont(ofSize: 11)
    label.textColor = .secondaryLabelColor
    label.lineBreakMode = .byTruncatingMiddle
    label.translatesAutoresizingMaskIntoConstraints = false
    label.widthAnchor.constraint(lessThanOrEqualToConstant: 110).isActive = true
    label.isHidden = true
    return label
  }()
  private lazy var widthInput = dimensionInput(label: "crop.width")
  private lazy var heightInput = dimensionInput(label: "crop.height")

  private func dimensionInput(label: String) -> NSTextField {
    let input = NSTextField()
    input.translatesAutoresizingMaskIntoConstraints = false
    input.bezelStyle = .roundedBezel
    input.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    input.alignment = .right
    input.delegate = self
    input.target = self
    input.action = #selector(dimensionInputAction)
    input.setAccessibilityLabel(ui.localized(label))
    input.widthAnchor.constraint(equalToConstant: 58).isActive = true
    return input
  }

  private lazy var aspectSelector: ScrollSelectionControl = {
    let selector = ScrollSelectionControl()
    selector.translatesAutoresizingMaskIntoConstraints = false
    selector.segmentCount = 1
    selector.trackingMode = .momentary
    selector.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    selector.shrinkDelay = 0.25
    selector.animatesDigits = true
    selector.setImage(NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil), forSegment: 0)
    selector.setLabel("—", forSegment: 0)
    selector.maximumWidth = 140
    selector.target = self
    selector.action = #selector(showAspectMenu)
    selector.switchSelection = { [weak self] direction in
      self?.switchAspect(direction: direction)
    }
    return selector
  }()

  private lazy var saveButton: NSButton = {
    let button = ui.button("crop.save", target: self, action: #selector(doneAction))
    button.keyEquivalent = "\r"
    return button
  }()

  private lazy var zoomControl: NSPopUpButton = {
    let control = CropZoomPopUpButton(frame: .zero, pullsDown: true)
    control.menuTrackingChanged = { [weak self] in self?.isTrackingEditorMenu = $0 }
    control.translatesAutoresizingMaskIntoConstraints = false
    control.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    control.addItem(withTitle: "100%")
    for percent in [100, 125, 150, 200, 300, 400, 800] {
      let title = percent == 100 ? ui.localized("crop.zoom_fit") : "\(percent)%"
      let item = NSMenuItem(title: title, action: #selector(zoomMenuAction), keyEquivalent: "")
      item.target = self
      item.tag = percent
      control.menu?.addItem(item)
    }
    control.setAccessibilityLabel(ui.localized("crop.zoom"))
    control.toolTip = ui.localized("crop.zoom")
    return control
  }()

  private lazy var controlBar: CropControlBar = {
    let widthLabel = NSTextField(labelWithString: "W")
    let heightLabel = NSTextField(labelWithString: "H")
    [widthLabel, heightLabel].forEach { $0.textColor = .secondaryLabelColor }
    let dimensions = ui.hStack(spacing: 6, cropTargetLabel, widthLabel, widthInput, heightLabel, heightInput)
    let resetButton = ui.button("crop.reset", target: self, action: #selector(resetAction))
    let cancelButton = ui.button("general.cancel", target: self, action: #selector(cancelAction))
    cancelButton.keyEquivalent = "\u{1b}"
    let buttons = ui.hStack(spacing: 8, cancelButton, saveButton)
    let keyViews: [NSView] = [cropBoxView, widthInput, heightInput, aspectSelector, resetButton, zoomControl, cancelButton, saveButton]
    for (index, view) in keyViews.enumerated() { view.nextKeyView = keyViews[(index + 1) % keyViews.count] }
    return CropControlBar(dimensions: dimensions, selector: aspectSelector,
                          reset: resetButton, zoom: zoomControl, buttons: buttons)
  }()

  private lazy var cropBoxView: CropBoxView = {
    let view = CropBoxView { [weak self] in self?.selectedRectUpdated() }
    view.previewUpdatedCallback = { [weak self] in self?.updatePreviewTransform() }
    return view
  }()

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow
    super.init()
  }

  deinit {
    if let editorEventMonitor { NSEvent.removeMonitor(editorEventMonitor) }
  }

  func enter(mode: Mode, selectWholeVideoByDefault: Bool = false) {
    guard !isActive, let window = mainWindow.window else { return }
    reloadAspectPresets()
    let player = mainWindow.player
    videoGeometry = (mode == .crop ? player.scopedCropPreview?.geometry : nil) ?? player.interactiveVideoGeometry(uncropped: mode == .crop)
    guard videoGeometry.sourceSize.width > 0 && videoGeometry.sourceSize.height > 0 else {
      Utility.showAlert("no_video_track")
      return
    }
    let cropFilter = mode == .crop ? (player.scopedCropPreview?.filter ?? player.info.cropFilter) : nil
    let cropDescription = player.scopedCropPreview?.originalTrack.cropDescription ?? player.info.unsureCrop
    if cropFilter != nil && player.scopedCropPreview == nil {
      player.removeCropFilter()
      guard player.info.cropFilter == nil else { return }
    }

    window.backgroundColor = .windowBackgroundColor
    mainWindow.standardWindowButtons.forEach { $0.isEnabled = false }
    isPausedPriorToInteractiveMode = player.info.state == .paused
    if mode == .delogo { player.pause() }
    isActive = true
    currentMode = mode
    originalVideoTransform = mainWindow.videoView.layer?.transform ?? CATransform3DIdentity
    originalVideoMask = mainWindow.videoView.layer?.mask
    cropBoxView.allowsZoom = mode == .crop
    zoomControl.isHidden = mode != .crop
    cropBoxView.resetPreview()
    mainWindow.oscFloatingView.cancelPositionAnimation()
    mainWindow.hideUI(force: true)
    mainWindow.hideOSD()
    mainWindow.liveText.clearAnalysis()
    originalCropFilter = cropFilter
    originalCropDescription = cropDescription

    cropTargetLabel.isHidden = player.scopedCropPreview == nil
    if let preview = player.scopedCropPreview {
      let track = player.info.videoTracks.first(where: { $0.id == preview.id })
      let position = player.info.orderedTrackList(.video).firstIndex { $0.id == preview.id }.map { $0 + 1 } ?? preview.id
      cropTargetLabel.stringValue = "#\(position) \(track?.title ?? "")"
      cropTargetLabel.toolTip = "#\(position) \(track?.readableString() ?? "")"
    }
    saveButton.title = ui.localized(mode == .crop ? "crop.save" : "general.done")
    mainWindow.videoViewContainer.addSubview(controlBar)
    let barWidth = controlBar.widthAnchor.constraint(equalToConstant: 1)
    barWidth.priority = .defaultLow
    controlBarWidth = barWidth
    let barBottom = controlBar.bottomAnchor.constraint(equalTo: mainWindow.videoViewContainer.bottomAnchor)
    controlBarBottom = barBottom
    NSLayoutConstraint.activate([
      controlBar.centerXAnchor.constraint(equalTo: mainWindow.videoViewContainer.centerXAnchor),
      barBottom,
      barWidth
    ])

    let shadow = NSShadow()
    shadow.shadowBlurRadius = 10
    shadow.shadowColor = .black.withAlphaComponent(0.5)
    mainWindow.videoView.shadow = shadow
    resize()

    mainWindow.videoViewContainer.addSubview(cropBoxView)
    cropBoxView.previewInset = 10
    NSLayoutConstraint.activate([
      cropBoxView.leadingAnchor.constraint(equalTo: mainWindow.videoView.leadingAnchor, constant: -10),
      cropBoxView.trailingAnchor.constraint(equalTo: mainWindow.videoView.trailingAnchor, constant: 10),
      cropBoxView.topAnchor.constraint(equalTo: mainWindow.videoView.topAnchor, constant: -10),
      cropBoxView.bottomAnchor.constraint(equalTo: mainWindow.videoView.bottomAnchor, constant: 10)
    ])
    cropBoxView.videoSize = videoGeometry.selectionSize
    let fullFrame = NSRect(origin: .zero, size: cropBoxView.videoSize)
    let selected = originalCropFilter.flatMap { selectionRect(for: $0) } ??
      (selectWholeVideoByDefault ? fullFrame : .zero)
    cropBoxView.setSelectedRect(to: selected)
    mainWindow.videoView.layoutSubtreeIfNeeded()
    updatePreviewTransform()
    window.makeFirstResponder(cropBoxView)
    player.postNotification(.iinaTrackSettingsChanged)
    if mode == .crop {
      editorEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
        guard let self else { return event }
        return self.handleEditorEvent(event)
      }
    }
  }

  func handleEditorEvent(_ event: NSEvent) -> NSEvent? {
    guard isActive, currentMode == .crop else { return event }
    let parentModifierEvent = event.type == .flagsChanged && event.window == nil && mainWindow.window?.isKeyWindow == true
    guard event.window === mainWindow.window || parentModifierEvent else { return event }
    guard !isTrackingEditorMenu else {
      // A transient popover can leave keyboard focus on its parent window.
      (aspectPopover?.contentViewController as? CropAspectPresetListController)?
        .setOptionHeld(event.modifierFlags.contains(.option))
      return event
    }
    guard event.type == .keyDown else { return event }
    guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
          [UInt16(53), 36, 76].contains(event.keyCode) else { return event }
    guard !event.isARepeat else { return nil }
    if event.keyCode == 53 {
      mainWindow.window?.makeFirstResponder(cropBoxView)
      if isFullFrameSelected {
        cancelAction(self)
      } else {
        resetAction(self)
      }
    } else if let input = [widthInput, heightInput].first(where: { $0.currentEditor() != nil }) {
      input.validateEditing()
      commitDimension(input)
      mainWindow.window?.makeFirstResponder(cropBoxView)
    } else {
      doneAction(self)
    }
    return nil
  }

  func resize() {
    guard isActive else { return }
    mainWindow.window?.contentView?.layoutSubtreeIfNeeded()
    let containerSize = mainWindow.videoViewContainer.bounds.size
    let insets = CropEditorInsets(size: containerSize)
    controlBarBottom?.constant = -insets.bottom
    let maxSize = NSSize(width: max(1, containerSize.width - 2 * insets.side),
                        height: max(1, containerSize.height - insets.top - insets.gap - insets.bottom))
    let newSize = controlBar.arrange(availableSize: maxSize,
                                   previewAspect: videoGeometry.displaySize.width / videoGeometry.displaySize.height)
    controlBarWidth?.constant = controlBar.layoutWidth
    let horizontalPadding = (containerSize.width - newSize.width) / 2
    // Insets from the previous size must not constrain AppKit's next resize proposal.
    mainWindow.updateVideoViewConstraints([
      .top: insets.top, .bottom: containerSize.height - insets.top - newSize.height,
      .leading: horizontalPadding, .trailing: horizontalPadding
    ], priority: .defaultLow)
    mainWindow.videoViewContainer.layoutSubtreeIfNeeded()
    updatePreviewTransform()
    mainWindow.forceDraw("interactive cropping")
  }

  func handleMagnifyGesture(_ recognizer: NSMagnificationGestureRecognizer) {
    guard isActive, currentMode == .crop else { return }
    switch recognizer.state {
    case .began:
      pinchStartZoom = nil
      pinchAnchor = nil
      let point = recognizer.location(in: cropBoxView)
      guard cropBoxView.previewRect.contains(point), !cropBoxView.isDragging else { return }
      pinchStartZoom = cropBoxView.previewTransform.zoom
      pinchAnchor = point
    case .changed, .ended:
      break
    default:
      pinchStartZoom = nil
      pinchAnchor = nil
      return
    }
    if let pinchStartZoom, let pinchAnchor {
      cropBoxView.setZoom(pinchStartZoom * max(0, 1 + recognizer.magnification), at: pinchAnchor)
    }
    if recognizer.state == .ended {
      pinchStartZoom = nil
      pinchAnchor = nil
    }
  }

  @objc private func zoomMenuAction(_ sender: NSMenuItem) {
    mainWindow.window?.makeFirstResponder(cropBoxView)
    cropBoxView.setZoom(CGFloat(sender.tag) / 100)
  }

  private func updatePreviewTransform() {
    guard isActive, let layer = mainWindow.videoView.layer else { return }
    let zoom = cropBoxView.previewTransform.zoom
    let viewport = cropBoxView.previewRect
    let image = cropBoxView.imageRect
    guard viewport.width > 0, viewport.height > 0 else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    var transform = CATransform3DMakeScale(zoom, zoom, 1)
    // AppKit-backed video layers can use a bottom-left anchor instead of the center.
    transform.m41 = image.minX - viewport.minX - (1 - zoom) * layer.bounds.width * layer.anchorPoint.x
    transform.m42 = image.minY - viewport.minY - (1 - zoom) * layer.bounds.height * layer.anchorPoint.y
    layer.transform = CATransform3DConcat(originalVideoTransform, transform)
    if zoom > 1 {
      previewMask.backgroundColor = NSColor.white.cgColor
      previewMask.frame = NSRect(x: layer.bounds.minX + (viewport.minX - image.minX) / zoom,
                                 y: layer.bounds.minY + (viewport.minY - image.minY) / zoom,
                                 width: viewport.width / zoom, height: viewport.height / zoom)
      layer.mask = previewMask
    } else {
      layer.mask = originalVideoMask
    }
    CATransaction.commit()
    let percent = Int((zoom * 100).rounded())
    zoomControl.item(at: 0)?.title = "\(percent)%"
    zoomControl.setAccessibilityValue("\(percent)%")
    for item in zoomControl.itemArray.dropFirst() {
      item.state = abs(zoom * 100 - CGFloat(item.tag)) < 0.5 ? .on : .off
    }
  }

  func canDragWindow(at point: NSPoint) -> Bool {
    let containerPoint = mainWindow.videoViewContainer.convert(point, from: nil)
    guard cropBoxView.hitTest(containerPoint) == nil else { return false }
    let controlHit = controlBar.hitTest(containerPoint)
    return controlHit == nil || controlHit === controlBar
  }

  private func selectionRect(for filter: MPVFilter) -> NSRect? {
    guard let params = filter.params,
          let width = params["w"].flatMap(Int.init), let height = params["h"].flatMap(Int.init),
          width > 0, height > 0 else { return nil }
    let x = params["x"].flatMap(Int.init) ?? Int((videoGeometry.sourceSize.width - CGFloat(width)) / 2)
    let y = params["y"].flatMap(Int.init) ?? Int((videoGeometry.sourceSize.height - CGFloat(height)) / 2)
    return videoGeometry.selectionRect(forFilterRect: NSRect(x: x, y: y, width: width, height: height))
  }

  func exit(applyingCrop: Bool = false, discardingCrop: Bool = false, then: @escaping () -> Void = {}) {
    guard isActive, let window = mainWindow.window else { return }
    let popover = aspectPopover
    aspectPopover = nil
    isTrackingEditorMenu = false
    popover?.delegate = nil
    popover?.performClose(nil)
    let player = mainWindow.player
    let wasCropping = currentMode == .crop
    let shouldResume = currentMode == .delogo && !isPausedPriorToInteractiveMode
    if let editorEventMonitor { NSEvent.removeMonitor(editorEventMonitor) }
    editorEventMonitor = nil
    window.makeFirstResponder(nil)
    isActive = false
    currentMode = nil
    pinchStartZoom = nil
    pinchAnchor = nil
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    mainWindow.videoView.layer?.transform = originalVideoTransform
    mainWindow.videoView.layer?.mask = originalVideoMask
    CATransaction.commit()
    originalVideoMask = nil
    cropBoxView.removeFromSuperview()
    controlBar.removeFromSuperview()
    controlBarWidth?.isActive = false
    controlBarWidth = nil
    controlBarBottom?.isActive = false
    controlBarBottom = nil
    window.backgroundColor = .black
    mainWindow.standardWindowButtons.forEach { $0.isEnabled = true }
    mainWindow.videoView.shadow = nil
    mainWindow.updateVideoViewConstraints([.top: 0, .bottom: 0, .leading: 0, .trailing: 0])
    if !discardingCrop, player.scopedCropPreview == nil, !applyingCrop, let originalCropFilter, player.setCrop(fromFilter: originalCropFilter) {
      player.info.unsureCrop = originalCropDescription
    }
    originalCropFilter = nil
    player.postNotification(.iinaTrackSettingsChanged)
    then()
    if !discardingCrop, player.scopedCropPreview != nil { player.finishScopedCustomCrop() }
    // A restored/applied filter will refresh geometry once mpv reports its output.
    if wasCropping, player.info.cropFilter == nil {
      mainWindow.handleVideoSizeChange(keepWindowSize: true)
    }
    if shouldResume {
      player.resume()
    } else if player.info.state == .paused {
      mainWindow.liveText.requestAnalysis()
    }
  }

  private func selectedRectUpdated() {
    guard isActive else { return }
    let rect = cropBoxView.selectedRect
    let filterRect = videoGeometry.filterRect(for: rect)
    cropx = Int(filterRect.minX)
    cropy = Int(filterRect.minY)
    cropw = Int(filterRect.width)
    croph = Int(filterRect.height)
    if widthInput.currentEditor() == nil { widthInput.integerValue = Int(rect.width) }
    if heightInput.currentEditor() == nil { heightInput.integerValue = Int(rect.height) }
    saveButton.isEnabled = cropw > 0 && croph > 0
    selectedPreset = matchingPreset(for: rect)
    if !cropBoxView.isDragging && !isUpdatingDimension { updateAspectLabel() }
    aspectSelector.setToolTip(ui.localized("crop.aspect"), forSegment: 0)
  }

  private func updateAspectLabel() {
    aspectSelector.setLabel(aspectTitle, forSegment: 0)
  }

  private var aspectTitle: String {
    if let selectedPreset, presetAspects.indices.contains(selectedPreset) {
      return CropVideoGeometry.aspectTitle(forRatio: presetAspects[selectedPreset])
    }
    return videoGeometry.aspectTitle(for: cropBoxView.selectedRect)
  }

  private func matchingPreset(for rect: NSRect) -> Int? {
    guard !rect.isEmpty else { return nil }
    return presetAspects.firstIndex { aspect in
      let pixelAspect = aspect / videoGeometry.pixelAspectRatio
      return abs(rect.width - rect.height * pixelAspect) <= min(max(1, pixelAspect) / 2, rect.width * 0.001)
    }
  }

  private func switchAspect(direction: Int) {
    guard isActive, direction != 0 else { return }
    reloadAspectPresets()
    let count = presetAspects.count
    guard count > 0 else { return }
    let index = selectedPreset.map { ($0 + (direction > 0 ? 1 : -1) + count) % count } ?? (direction > 0 ? 0 : count - 1)
    applyPreset(index, direction: direction)
  }

  private func applyPreset(_ index: Int, direction: Int = 0) {
    guard !cropBoxView.isAnimatingSelection else { return }
    let previousTitle = aspectSelector.label(forSegment: 0) ?? ""
    aspectSelector.animatesDigits = false
    defer { aspectSelector.animatesDigits = true }
    mainWindow.window?.makeFirstResponder(cropBoxView)
    let videoSize = cropBoxView.videoSize
    guard presetAspects.indices.contains(index) else { return }
    let size = videoSize.crop(withAspect: Aspect(size: NSSize(width: presetAspects[index] / videoGeometry.pixelAspectRatio, height: 1)))
    cropBoxView.setSelectedRect(to: CropSelectionGeometry.resized(
      NSRect(origin: .zero, size: videoSize), to: size, in: videoSize))
    // Pixel rounding can make a small source match several ratios; retain the chosen preset.
    selectedPreset = index
    aspectSelector.setLabel(aspectTitle, forSegment: 0)
    if direction != 0 {
      aspectSelector.roll(through: [previousTitle, aspectTitle], direction: direction)
    }
  }

  private func reloadAspectPresets() {
    let stored = Preference.array(for: .customCropAspectPresets) ?? []
    var aspects: [CGFloat] = []
    for value in stored {
      guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue.isFinite, number.doubleValue > 0 else { continue }
      let aspect = CGFloat(number.doubleValue)
      if !aspects.contains(where: { abs($0 / aspect - 1) < 1e-10 }) { aspects.append(aspect) }
    }
    guard aspects != presetAspects else { return }
    presetAspects = aspects
    selectedPreset = matchingPreset(for: cropBoxView.selectedRect)
  }

  func makeAspectMenu() -> NSMenu {
    reloadAspectPresets()
    let menu = NSMenu()
    menu.autoenablesItems = false
    let font = menu.font ?? NSFont.menuFont(ofSize: 0)
    menu.minimumWidth = ["crop.add_preset", "crop.delete_selected_preset"].map {
      (ui.localized($0) as NSString).size(withAttributes: [.font: font]).width + 56
    }.max() ?? 100
    for (index, aspect) in presetAspects.enumerated() {
      let item = NSMenuItem(title: CropVideoGeometry.aspectTitle(forRatio: aspect),
                            action: #selector(aspectMenuAction), keyEquivalent: "")
      item.target = self
      // Keep the value on the item so another player cannot invalidate its index.
      item.representedObject = Double(aspect)
      item.state = selectedPreset == index ? .on : .off
      menu.addItem(item)
    }
    if !presetAspects.isEmpty { menu.addItem(.separator()) }
    let add = NSMenuItem(title: ui.localized("crop.add_preset"), action: #selector(addAspectPreset), keyEquivalent: "")
    add.target = self
    add.isEnabled = !cropBoxView.selectedRect.isEmpty && matchingPreset(for: cropBoxView.selectedRect) == nil
    menu.addItem(add)
    return menu
  }

  func deleteAspectPreset(_ sender: NSMenuItem) {
    guard isActive, currentMode == .crop, let aspect = sender.representedObject as? Double else { return }
    reloadAspectPresets()
    guard let index = presetAspects.firstIndex(of: CGFloat(aspect)) else { return }
    aspectPopover?.performClose(nil)
    presetAspects.remove(at: index)
    Preference.set(presetAspects.map { Double($0) }, for: .customCropAspectPresets)
    selectedPreset = matchingPreset(for: cropBoxView.selectedRect)
    aspectSelector.animatesDigits = false
    updateAspectLabel()
    aspectSelector.animatesDigits = true
  }

  @objc private func showAspectMenu(_ sender: NSSegmentedControl) {
    // Publish pending W/H edits before taking the menu's selection snapshot.
    mainWindow.window?.makeFirstResponder(cropBoxView)
    let menu = makeAspectMenu()
    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = false
    popover.delegate = self
    let content = CropAspectPresetListController(menu: menu)
    content.cancel = { [weak self] in self?.aspectPopover?.performClose(nil) }
    content.select = { [weak self] item in
      self?.aspectPopover?.performClose(nil)
      guard let action = item.action else { return }
      NSApp.sendAction(action, to: item.target, from: item)
    }
    content.deletePreset = { [weak self] item in self?.deleteAspectPreset(item) }
    content.setOptionHeld(NSEvent.modifierFlags.contains(.option))
    let buttonFrame = sender.convert(sender.bounds, to: mainWindow.videoViewContainer)
    content.maximumHeight = max(44, mainWindow.videoViewContainer.bounds.maxY - buttonFrame.maxY - 28)
    popover.contentViewController = content
    aspectPopover = popover
    isTrackingEditorMenu = true
    popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: sender.isFlipped ? .minY : .maxY)
    content.focusList()
  }

  func popoverDidClose(_ notification: Notification) {
    guard let popover = notification.object as? NSPopover, popover === aspectPopover else { return }
    aspectPopover = nil
    isTrackingEditorMenu = false
    if isActive { mainWindow.window?.makeFirstResponder(cropBoxView) }
  }

  @objc private func aspectMenuAction(_ sender: NSMenuItem) {
    guard isActive, currentMode == .crop, let aspect = sender.representedObject as? Double else { return }
    reloadAspectPresets()
    guard let index = presetAspects.firstIndex(of: CGFloat(aspect)) else { return }
    applyPreset(index)
  }

  @objc private func addAspectPreset(_ sender: NSMenuItem) {
    guard isActive, currentMode == .crop else { return }
    mainWindow.window?.makeFirstResponder(cropBoxView)
    reloadAspectPresets()
    let rect = cropBoxView.selectedRect
    guard !rect.isEmpty, matchingPreset(for: rect) == nil else { return }
    // Preserve the display ratio across videos with different pixel aspects and rotations.
    let aspect = rect.width / rect.height * videoGeometry.pixelAspectRatio
    guard aspect.isFinite, aspect > 0 else { return }
    presetAspects.append(aspect)
    Preference.set(presetAspects.map { Double($0) }, for: .customCropAspectPresets)
    selectedPreset = presetAspects.count - 1
    updateAspectLabel()
  }

  @objc private func resetAction(_ sender: AnyObject) {
    let animatesDigits = aspectSelector.animatesDigits
    aspectSelector.animatesDigits = currentMode == .crop
    defer { aspectSelector.animatesDigits = animatesDigits }
    mainWindow.window?.makeFirstResponder(cropBoxView)
    cropBoxView.setSelectedRect(to: NSRect(origin: .zero, size: cropBoxView.videoSize), animated: currentMode == .crop)
  }

  func controlTextDidChange(_ notification: Notification) {
    guard let input = notification.object as? NSTextField,
          let value = Int(input.stringValue), value > 0 else { return }
    updateDimension(input, value: value)
  }

  func controlTextDidBeginEditing(_ notification: Notification) {
    guard let input = notification.object as? NSTextField, input === widthInput || input === heightInput else { return }
    let rect = cropBoxView.selectedRect
    dimensionEditCenter = rect.isEmpty ? nil : NSPoint(x: rect.midX, y: rect.midY)
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    guard let input = notification.object as? NSTextField else { return }
    commitDimension(input)
    dimensionEditCenter = nil
  }

  @objc private func dimensionInputAction(_ sender: NSTextField) {
    commitDimension(sender)
  }

  private func commitDimension(_ input: NSTextField) {
    guard isActive, input === widthInput || input === heightInput else { return }
    if let value = Int(input.stringValue) { updateDimension(input, value: max(1, value)) }
    input.integerValue = Int(input === widthInput ? cropBoxView.selectedRect.width : cropBoxView.selectedRect.height)
    updateAspectLabel()
  }

  private func updateDimension(_ input: NSTextField, value: Int) {
    guard isActive, input === widthInput || input === heightInput else { return }
    let current = cropBoxView.selectedRect
    guard !cropBoxView.isAnimatingSelection else {
      input.integerValue = Int(input === widthInput ? current.width : current.height)
      return
    }
    let size = NSSize(width: input === widthInput ? CGFloat(value) : max(1, current.width),
                       height: input === heightInput ? CGFloat(value) : max(1, current.height))
    isUpdatingDimension = true
    defer { isUpdatingDimension = false }
    cropBoxView.setSelectedRect(to: CropSelectionGeometry.resized(
      current, to: size, in: cropBoxView.videoSize, center: dimensionEditCenter))
  }

  @objc private func doneAction(_ sender: AnyObject) {
    mainWindow.window?.makeFirstResponder(nil)
    guard cropw > 0 && croph > 0 else { return }
    switch currentMode {
    case .crop: cropAction()
    case .delogo: delogoAction()
    case nil: break
    }
  }

  private func cropAction() {
    let player = mainWindow.player
    let isFullFrame = isFullFrameSelected
    if player.scopedCropPreview != nil {
      let crop = isFullFrame ? nil : TrackVideoCrop(x: cropx, y: cropy, width: cropw, height: croph)
      guard player.finishScopedCustomCrop(crop: crop, applying: true) else { return }
      exit(applyingCrop: true)
      return
    }
    if !isFullFrame {
      let filter = MPVFilter.crop(w: cropw, h: croph, x: cropx, y: cropy, exact: true)
      guard player.setCrop(fromFilter: filter) else { return }
    }
    exit(applyingCrop: true) {
      if isFullFrame {
        player.removeCropFilter()
        return
      }
      player.info.unsureCrop = ""
      player.sendOSD(.crop(self.readableCropString))
    }
  }

  private func delogoAction() {
    let player = mainWindow.player
    exit {
      let filter = MPVFilter(lavfiName: "delogo", label: Constants.FilterName.delogo, paramDict: [
        "x": String(self.cropx), "y": String(self.cropy), "w": String(self.cropw), "h": String(self.croph)
      ])
      if let existingFilter = player.info.delogoFilter { let _ = player.removeVideoFilter(existingFilter) }
      if !player.addVideoFilter(filter) {
        Utility.showAlert("filter.incorrect")
        return
      }
      player.info.delogoFilter = filter
    }
  }

  @objc private func cancelAction(_ sender: AnyObject) {
    exit()
  }
}

// NSMenu's tracking loop consumes secondary clicks before a row can delete its saved ratio.
private final class CropAspectPresetListController: NSViewController {
  let presetMenu: NSMenu
  var maximumHeight: CGFloat = 400
  var select: ((NSMenuItem) -> Void)?
  var cancel: (() -> Void)?
  var deletePreset: ((NSMenuItem) -> Void)?
  private let actionItem: NSMenuItem?
  private let addTitle: String
  private let addEnabled: Bool
  private var optionHeld = false
  private weak var actionRow: CropAspectPresetMenuView?

  init(menu: NSMenu) {
    presetMenu = menu
    actionItem = menu.items.last
    addTitle = menu.items.last?.title ?? ui.localized("crop.add_preset")
    addEnabled = menu.items.last?.isEnabled ?? false
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func loadView() {
    let menu = presetMenu
    let font = menu.font ?? NSFont.menuFont(ofSize: 0)
    let list = CropAspectPresetListView()
    list.select = { [weak self] in self?.activate($0) }
    list.optionChanged = { [weak self] in self?.setOptionHeld($0) }
    list.cancel = { [weak self] in self?.cancel?() }
    let width = max(menu.minimumWidth, menu.items.map { ($0.title as NSString).size(withAttributes: [.font: font]).width + 56 }.max() ?? 100)
    list.frame.size.width = width
    var y: CGFloat = 4
    for item in menu.items {
      if item.isSeparatorItem {
        let separator = NSBox(frame: NSRect(x: 10, y: y + 3, width: width - 20, height: 1))
        separator.boxType = .separator
        list.addSubview(separator)
        y += 9
      } else {
        let row = CropAspectPresetMenuView(item: item, font: font)
        row.frame = NSRect(x: 0, y: y, width: width, height: row.frame.height)
        row.select = { [weak self] in self?.activate($0) }
        if item === actionItem { actionRow = row }
        if item.representedObject != nil { row.deletePreset = { [weak self] in self?.deletePreset?(item) } }
        list.rows.append(row)
        list.addSubview(row)
        y += row.frame.height
      }
    }
    list.frame = NSRect(x: 0, y: 0, width: width, height: y + 4)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: min(y + 4, maximumHeight)))
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.documentView = list
    list.autoresizingMask = [.width]
    view = scroll
    preferredContentSize = scroll.frame.size
    setOptionHeld(optionHeld)
  }

  func setOptionHeld(_ held: Bool) {
    optionHeld = held
    guard let actionItem else { return }
    actionItem.title = held ? ui.localized("crop.delete_selected_preset") : addTitle
    actionItem.isEnabled = held ? checkedPreset != nil : addEnabled
    actionRow?.refreshAccessibility()
  }

  private var checkedPreset: NSMenuItem? {
    presetMenu.items.first { $0.representedObject != nil && $0.state == .on }
  }

  private func activate(_ item: NSMenuItem) {
    guard item.isEnabled else { return }
    if item === actionItem && optionHeld {
      if let checkedPreset { deletePreset?(checkedPreset) }
    } else {
      select?(item)
    }
  }

  func focusList() {
    guard let list = (view as? NSScrollView)?.documentView else { return }
    view.window?.makeFirstResponder(list)
  }
}

private final class CropAspectPresetListView: NSView {
  var rows: [CropAspectPresetMenuView] = []
  var select: ((NSMenuItem) -> Void)?
  var cancel: (() -> Void)?
  var optionChanged: ((Bool) -> Void)?
  private var keyboardIndex: Int?
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func flagsChanged(with event: NSEvent) {
    optionChanged?(event.modifierFlags.contains(.option))
  }

  override func keyDown(with event: NSEvent) {
    let enabled = rows.indices.filter { rows[$0].item.isEnabled }
    switch event.keyCode {
    case 125, 126:
      guard !enabled.isEmpty else { return }
      let direction = event.keyCode == 125 ? 1 : -1
      let index = keyboardIndex.flatMap { enabled.firstIndex(of: $0) }
      keyboardIndex = enabled[index.map { ($0 + direction + enabled.count) % enabled.count } ?? (direction > 0 ? 0 : enabled.count - 1)]
      for (index, row) in rows.enumerated() { row.keyboardHighlight = index == keyboardIndex }
      rows[keyboardIndex!].scrollToVisible(rows[keyboardIndex!].bounds)
    case 36, 76:
      if let keyboardIndex, rows[keyboardIndex].item.isEnabled { select?(rows[keyboardIndex].item) }
    case 53:
      cancel?()
    default: super.keyDown(with: event)
    }
  }
}

private final class CropAspectPresetMenuView: NSView {
  let item: NSMenuItem
  private let font: NSFont
  private var hoverArea: NSTrackingArea?
  private var isHovered = false
  private var isContextClick = false
  var keyboardHighlight = false { didSet { needsDisplay = true } }
  var select: ((NSMenuItem) -> Void)?
  var deletePreset: (() -> Void)?

  init(item: NSMenuItem, font: NSFont) {
    self.item = item
    self.font = font
    let size = (item.title as NSString).size(withAttributes: [.font: font])
    super.init(frame: NSRect(x: 0, y: 0, width: ceil(size.width) + 56, height: max(22, ceil(size.height) + 8)))
    autoresizingMask = [.width]
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    refreshAccessibility()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(area)
    hoverArea = area
  }

  func refreshAccessibility() {
    setAccessibilityLabel(item.title)
    setAccessibilityEnabled(item.isEnabled)
    needsDisplay = true
  }

  override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
  override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

  override func draw(_ dirtyRect: NSRect) {
    let highlighted = item.isEnabled && (isHovered || keyboardHighlight)
    if highlighted {
      NSColor.selectedContentBackgroundColor.setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
    let color = item.isEnabled ? (highlighted ? NSColor.selectedMenuItemTextColor : NSColor.labelColor) : NSColor.disabledControlTextColor
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let title = item.title as NSString
    let y = (bounds.height - title.size(withAttributes: attributes).height) / 2
    title.draw(at: NSPoint(x: 30, y: y), withAttributes: attributes)
    if item.state == .on { ("✓" as NSString).draw(at: NSPoint(x: 12, y: y), withAttributes: attributes) }
  }

  override func mouseDown(with event: NSEvent) {
    isContextClick = event.modifierFlags.contains(.control)
    if isContextClick { rightMouseDown(with: event) }
  }

  override func mouseUp(with event: NSEvent) {
    guard !isContextClick else { isContextClick = false; return }
    if bounds.contains(convert(event.locationInWindow, from: nil)) { activatePreset() }
  }

  override func rightMouseDown(with event: NSEvent) { _ = accessibilityDeletePreset() }

  override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
    guard deletePreset != nil else { return nil }
    return [NSAccessibilityCustomAction(name: ui.localized("crop.delete_preset"), target: self, selector: #selector(accessibilityDeletePreset))]
  }

  @objc func accessibilityDeletePreset() -> Bool {
    guard item.isEnabled, let deletePreset else { return false }
    deletePreset()
    return true
  }

  override func accessibilityPerformPress() -> Bool { activatePreset() }

  @discardableResult private func activatePreset() -> Bool {
    guard item.isEnabled else { return false }
    select?(item)
    return select != nil
  }
}

private final class CropZoomPopUpButton: NSPopUpButton {
  var menuTrackingChanged: ((Bool) -> Void)?

  override func mouseDown(with event: NSEvent) { showMenuAbove() }
  override func performClick(_ sender: Any?) { showMenuAbove() }
  override func accessibilityPerformPress() -> Bool {
    guard isEnabled else { return false }
    showMenuAbove()
    return true
  }

  override func keyDown(with event: NSEvent) {
    if [UInt16(49), 125, 126].contains(event.keyCode) { showMenuAbove() }
    else { super.keyDown(with: event) }
  }

  private func showMenuAbove() {
    guard isEnabled, let menu, let titleItem = menu.items.first else { return }
    // The first item supplies the pull-down title and is not a zoom choice.
    let wasHidden = titleItem.isHidden
    titleItem.isHidden = true
    menuTrackingChanged?(true)
    defer {
      titleItem.isHidden = wasHidden
      menuTrackingChanged?(false)
    }
    let top = isFlipped ? bounds.minY - menu.size.height - 4 : bounds.maxY + menu.size.height + 4
    menu.popUp(positioning: nil, at: NSPoint(x: bounds.minX, y: top), in: self)
  }
}

struct CropEditorInsets {
  let top: CGFloat
  let side: CGFloat
  let gap: CGFloat
  let bottom: CGFloat

  init(size: NSSize) {
    let shortSide = min(size.width, size.height)
    top = min(48, max(28, shortSide * 0.075))
    side = min(24, max(12, shortSide * 0.04))
    gap = min(20, max(10, shortSide * 0.03))
    bottom = side
  }
}

private final class CropControlBar: NSView {
  private let adjustments: NSStackView
  private let utilities: NSStackView
  private let buttons: NSView
  private let adjustmentWidth: CGFloat
  private var utilityLeading: NSLayoutConstraint!
  private var buttonsTrailing: NSLayoutConstraint!
  private var adjustmentBottom: NSLayoutConstraint!
  private var reservedHeight: CGFloat = 0
  private(set) var layoutWidth: CGFloat = 0

  init(dimensions: NSView, selector: ScrollSelectionControl, reset: NSView, zoom: NSView, buttons: NSView) {
    adjustments = ui.hStack(spacing: 8, dimensions, selector)
    utilities = ui.hStack(spacing: 8, reset, zoom)
    self.buttons = buttons
    // Reserve the longest possible ratio, independent of the current title animation.
    adjustmentWidth = dimensions.fittingSize.width + 8 + selector.fittingWidth(forTitle: "99:99")
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    [adjustments, utilities, buttons].forEach { addSubview($0) }
    utilityLeading = utilities.leadingAnchor.constraint(equalTo: leadingAnchor)
    buttonsTrailing = buttons.trailingAnchor.constraint(equalTo: trailingAnchor)
    adjustmentBottom = adjustments.bottomAnchor.constraint(equalTo: bottomAnchor)
    NSLayoutConstraint.activate([
      utilityLeading, buttonsTrailing, adjustmentBottom,
      utilities.bottomAnchor.constraint(equalTo: bottomAnchor),
      buttons.bottomAnchor.constraint(equalTo: bottomAnchor),
      adjustments.centerXAnchor.constraint(equalTo: centerXAnchor)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: reservedHeight)
  }

  func arrange(availableSize: NSSize, previewAspect: CGFloat) -> NSSize {
    let utilityWidth = utilities.fittingSize.width
    let buttonWidth = buttons.fittingSize.width
    let actionWidth = utilityWidth + 8 + buttonWidth
    let minimumWidth = max(adjustmentWidth, actionWidth)
    let actionHeight = max(utilities.fittingSize.height, buttons.fittingSize.height)
    let adjustmentHeight = adjustments.fittingSize.height
    let singleHeight = max(actionHeight, adjustmentHeight)
    let rowOffset = actionHeight + 8
    let twoRowHeight = actionHeight + 8 + adjustmentHeight
    let aspectSize = NSSize(width: previewAspect, height: 1)
    // Measure with both rows reserved to avoid a preview-height/layout-width feedback loop.
    let footprint = aspectSize.shrink(toSize:
      NSSize(width: availableSize.width, height: max(1, availableSize.height - twoRowHeight)))
    let clearWidth = adjustmentWidth + 2 * max(utilityWidth, buttonWidth) + 16
    let spread = smoothProgress((footprint.width - minimumWidth) / max(1, clearWidth - minimumWidth))
    let mergeWidth = max(36, 0.65 * rowOffset * previewAspect)
    let merge = smoothProgress((footprint.width - clearWidth) / mergeWidth)
    let offset = rowOffset * (1 - merge)
    let height = singleHeight + offset
    if height != reservedHeight {
      reservedHeight = height
      invalidateIntrinsicContentSize()
    }
    let preview = aspectSize.shrink(toSize:
      NSSize(width: availableSize.width, height: max(1, availableSize.height - height)))
    layoutWidth = min(availableSize.width, max(minimumWidth, preview.width))
    let sideInset = max(0, (layoutWidth - actionWidth) / 2) * (1 - spread)
    utilityLeading.constant = sideInset
    buttonsTrailing.constant = -sideInset
    adjustmentBottom.constant = -offset
    return preview
  }

  private func smoothProgress(_ value: CGFloat) -> CGFloat {
    let progress = max(0, min(1, value))
    return progress * progress * (3 - 2 * progress)
  }
}

struct CropVideoGeometry {
  let sourceSize: NSSize
  let selectionSize: NSSize
  let displaySize: NSSize
  let rotation: Int

  var pixelAspectRatio: CGFloat {
    guard selectionSize.width > 0, selectionSize.height > 0 else { return 1 }
    return (displaySize.width / displaySize.height) / (selectionSize.width / selectionSize.height)
  }

  init(sourceSize: NSSize, displaySize: NSSize, rotation: Int) {
    self.sourceSize = sourceSize
    self.rotation = ((rotation % 360) + 360) % 360
    let display = displaySize.width > 0 && displaySize.height > 0 ? displaySize : sourceSize
    if self.rotation == 90 || self.rotation == 270 {
      selectionSize = NSSize(width: sourceSize.height, height: sourceSize.width)
      self.displaySize = NSSize(width: display.height, height: display.width)
    } else {
      selectionSize = sourceSize
      self.displaySize = display
    }
  }

  func aspectTitle(for rect: NSRect) -> String {
    guard !rect.isEmpty else { return "—" }
    return Self.aspectTitle(forRatio: rect.width / rect.height * pixelAspectRatio)
  }

  static func aspectTitle(forRatio ratio: CGFloat) -> String {
    guard ratio.isFinite, ratio > 0 else { return "—" }
    for (width, height) in [(4, 3), (16, 9), (16, 10), (21, 9), (3, 2), (5, 4)] {
      if abs(ratio - CGFloat(width) / CGFloat(height)) < 1e-10 { return "\(width):\(height)" }
      if abs(ratio - CGFloat(height) / CGFloat(width)) < 1e-10 { return "\(height):\(width)" }
    }
    let portrait = ratio < 1
    let target = min(99, portrait ? 1 / ratio : ratio)
    var numerator = 1, denominator = 1
    var smallestError = CGFloat.greatestFiniteMagnitude
    for height in 1...99 {
      let width = min(99, max(1, Int((target * CGFloat(height)).rounded())))
      let error = abs(CGFloat(width) / CGFloat(height) - target)
      if error < smallestError - 1e-12 {
        numerator = width
        denominator = height
        smallestError = error
      }
    }
    return portrait ? "\(denominator):\(numerator)" : "\(numerator):\(denominator)"
  }

  // Selection uses bottom-left coordinates after rotation; filters use top-left source coordinates.
  func filterRect(for rect: NSRect) -> NSRect {
    guard !rect.isEmpty else { return .zero }
    switch rotation {
    case 90:
      return NSRect(x: sourceSize.width - rect.maxY, y: sourceSize.height - rect.maxX,
                    width: rect.height, height: rect.width)
    case 180:
      return NSRect(x: sourceSize.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
    case 270:
      return NSRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width)
    default:
      return NSRect(x: rect.minX, y: sourceSize.height - rect.maxY, width: rect.width, height: rect.height)
    }
  }

  func selectionRect(forFilterRect rect: NSRect) -> NSRect {
    switch rotation {
    case 90:
      return NSRect(x: sourceSize.height - rect.maxY, y: sourceSize.width - rect.maxX,
                    width: rect.height, height: rect.width)
    case 180:
      return NSRect(x: sourceSize.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
    case 270:
      return NSRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width)
    default:
      return NSRect(x: rect.minX, y: sourceSize.height - rect.maxY, width: rect.width, height: rect.height)
    }
  }
}

enum CropSelectionGeometry {
  static func bounded(_ rect: NSRect, in size: NSSize) -> NSRect {
    guard size.width >= 1, size.height >= 1,
          [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite),
          !rect.isEmpty else { return .zero }
    let x = min(max(0, rect.minX.rounded()), size.width - 1)
    let y = min(max(0, rect.minY.rounded()), size.height - 1)
    let maxX = min(max(x + 1, rect.maxX.rounded()), size.width)
    let maxY = min(max(y + 1, rect.maxY.rounded()), size.height)
    return NSRect(x: x, y: y, width: maxX - x, height: maxY - y)
  }

  static func resized(_ rect: NSRect, to requested: NSSize, in size: NSSize, center: NSPoint? = nil) -> NSRect {
    guard size.width >= 1, size.height >= 1 else { return .zero }
    let width = min(size.width, max(1, requested.width.rounded()))
    let height = min(size.height, max(1, requested.height.rounded()))
    let center = center ?? (rect.isEmpty ? NSPoint(x: size.width / 2, y: size.height / 2) : NSPoint(x: rect.midX, y: rect.midY))
    return NSRect(x: min(max(0, (center.x - width / 2).rounded()), size.width - width),
                   y: min(max(0, (center.y - height / 2).rounded()), size.height - height),
                   width: width, height: height)
  }
}

struct CropPreviewTransform: Equatable {
  static let maximumZoom: CGFloat = 8
  private(set) var zoom: CGFloat = 1
  private(set) var center = NSPoint(x: 0.5, y: 0.5)

  func imageRect(in viewport: NSRect) -> NSRect {
    let size = NSSize(width: viewport.width * zoom, height: viewport.height * zoom)
    return NSRect(x: viewport.midX - center.x * size.width,
                  y: viewport.midY - center.y * size.height, width: size.width, height: size.height)
  }

  mutating func setZoom(_ value: CGFloat, at point: NSPoint, in viewport: NSRect) {
    guard value.isFinite, point.x.isFinite, point.y.isFinite,
          viewport.width > 0, viewport.height > 0 else { return }
    let image = imageRect(in: viewport)
    let source = NSPoint(x: (point.x - image.minX) / image.width,
                         y: (point.y - image.minY) / image.height)
    zoom = min(Self.maximumZoom, max(1, value))
    center = NSPoint(x: source.x - (point.x - viewport.midX) / (viewport.width * zoom),
                     y: source.y - (point.y - viewport.midY) / (viewport.height * zoom))
    clampCenter()
  }

  mutating func pan(by delta: NSPoint, in viewport: NSRect) {
    guard delta.x.isFinite, delta.y.isFinite, viewport.width > 0, viewport.height > 0 else { return }
    center.x -= delta.x / (viewport.width * zoom)
    center.y -= delta.y / (viewport.height * zoom)
    clampCenter()
  }

  private mutating func clampCenter() {
    let inset = 0.5 / zoom
    center.x = min(1 - inset, max(inset, center.x))
    center.y = min(1 - inset, max(inset, center.y))
  }
}

final class CropBoxView: NSView {
  private static let resetDuration: TimeInterval = 0.28
  private let handleHitRadius: CGFloat = 9
  var rectUpdatedCallback: (() -> Void)?
  var previewUpdatedCallback: (() -> Void)?
  var allowsZoom = false
  private(set) var previewTransform = CropPreviewTransform()
  var videoSize = NSSize() {
    didSet {
      finishSelectionAnimation()
      setSelectedRect(to: selectedRect)
    }
  }
  var previewInset: CGFloat = 0
  var previewRect: NSRect { bounds.insetBy(dx: previewInset, dy: previewInset) }
  var imageRect: NSRect { previewTransform.imageRect(in: previewRect) }
  private(set) var selectedRect = NSRect()
  private var presentedSelection: NSRect?
  private var selectionTimer: Timer?
  var isAnimatingSelection: Bool { selectionTimer != nil }
  var boxRect: NSRect {
    guard videoSize.width > 0, videoSize.height > 0 else { return .zero }
    let image = imageRect
    let rect = presentedSelection ?? selectedRect
    return NSRect(x: image.minX + rect.minX * image.width / videoSize.width,
                   y: image.minY + rect.minY * image.height / videoSize.height,
                   width: rect.width * image.width / videoSize.width,
                   height: rect.height * image.height / videoSize.height)
  }

  private struct Edges: OptionSet {
    let rawValue: Int
    static let minX = Edges(rawValue: 1)
    static let maxX = Edges(rawValue: 2)
    static let minY = Edges(rawValue: 4)
    static let maxY = Edges(rawValue: 8)
  }

  private enum Drag {
    case resize(Edges, NSRect, NSPoint, centered: Bool, proportional: Bool, lastPoint: NSPoint)
    case move(NSRect, NSPoint)
    case select(NSPoint)
  }
  private var drag: Drag?
  var isDragging: Bool { drag != nil }

  override var acceptsFirstResponder: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  init(callback: (() -> Void)?) {
    rectUpdatedCallback = callback
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel(ui.localized("crop.selection"))
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit { selectionTimer?.invalidate() }

  private var canAnimateSelection: Bool {
    window != nil && !isHiddenOrHasHiddenAncestor && !AccessibilityPreferences.motionReductionEnabled &&
      AccessibilityPreferences.adjustedDuration(Self.resetDuration) > 0
  }

  func setSelectedRect(to rect: NSRect, animated: Bool = false) {
    guard !isAnimatingSelection else { return }
    let target = CropSelectionGeometry.bounded(rect, in: videoSize)
    let from = presentedSelection ?? selectedRect
    finishSelectionAnimation()
    selectedRect = target
    if animated { drag = nil }
    if animated, canAnimateSelection, !from.isEmpty, from != target {
      // Save and aspect digits use the final crop while only the outline interpolates.
      presentedSelection = from
      let start = CACurrentMediaTime()
      let duration = AccessibilityPreferences.adjustedDuration(Self.resetDuration)
      let timer = Timer(timeInterval: 1 / 60.0, repeats: true) { [weak self] timer in
        guard let self else { timer.invalidate(); return }
        guard self.canAnimateSelection else { self.finishSelectionAnimation(); return }
        let progress = min(1, (CACurrentMediaTime() - start) / duration)
        let eased = CGFloat(1 - pow(1 - progress, 3))
        self.presentedSelection = NSRect(x: from.minX + (target.minX - from.minX) * eased,
                                         y: from.minY + (target.minY - from.minY) * eased,
                                         width: from.width + (target.width - from.width) * eased,
                                         height: from.height + (target.height - from.height) * eased)
        self.needsDisplay = true
        self.window?.invalidateCursorRects(for: self)
        if progress >= 1 { self.finishSelectionAnimation() }
      }
      selectionTimer = timer
      RunLoop.main.add(timer, forMode: .common)
    }
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
    setAccessibilityValue("\(Int(selectedRect.width)) × \(Int(selectedRect.height))")
    rectUpdatedCallback?()
  }

  private func finishSelectionAnimation() {
    guard selectionTimer != nil || presentedSelection != nil else { return }
    selectionTimer?.invalidate()
    selectionTimer = nil
    presentedSelection = nil
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
  }

  func resetPreview() {
    previewTransform = CropPreviewTransform()
    previewDidChange()
  }

  func setZoom(_ zoom: CGFloat, at anchor: NSPoint? = nil) {
    guard allowsZoom, !isDragging, !isAnimatingSelection else { return }
    let previous = previewTransform
    previewTransform.setZoom(zoom, at: anchor ?? NSPoint(x: previewRect.midX, y: previewRect.midY), in: previewRect)
    if previewTransform != previous { previewDidChange() }
  }

  private func previewDidChange() {
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
    previewUpdatedCallback?()
  }

  override func scrollWheel(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard allowsZoom, !isDragging, !isAnimatingSelection, previewRect.contains(point) else { return }
    let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
    if event.modifierFlags.contains(.option) {
      let delta = event.scrollingDeltaY == 0 ? event.scrollingDeltaX : event.scrollingDeltaY
      guard delta.isFinite else { return }
      let exponentLimit = 2 * log(CropPreviewTransform.maximumZoom)
      let exponent = min(exponentLimit, max(-exponentLimit, delta * multiplier * 0.01))
      setZoom(previewTransform.zoom * exp(exponent), at: point)
      return
    }
    let delta: NSPoint
    if event.modifierFlags.contains(.shift) {
      // macOS may already remap Shift+wheel from the vertical axis to the horizontal axis.
      let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
      delta = NSPoint(x: horizontal * multiplier, y: 0)
    } else {
      delta = NSPoint(x: event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : 0,
                      y: -event.scrollingDeltaY * multiplier)
    }
    let previous = previewTransform
    previewTransform.pan(by: delta, in: previewRect)
    if previewTransform != previous { previewDidChange() }
  }

  override func layout() {
    super.layout()
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil {
      drag = nil
      finishSelectionAnimation()
    }
  }

  private func videoPoint(from point: NSPoint) -> NSPoint {
    let image = imageRect
    return NSPoint(x: min(videoSize.width, max(0, (point.x - image.minX) * videoSize.width / image.width)),
                   y: min(videoSize.height, max(0, (point.y - image.minY) * videoSize.height / image.height)))
  }

  private var cornerLength: CGFloat { min(14, min(boxRect.width, boxRect.height) / 3) }

  private var cornerHitAreas: [(rect: NSRect, edges: Edges)] {
    let rect = boxRect
    let insetX = min(cornerLength + 3, rect.width / 2)
    let insetY = min(cornerLength + 3, rect.height / 2)
    return [
      (NSRect(x: rect.minX - handleHitRadius, y: rect.minY - handleHitRadius,
              width: insetX + handleHitRadius, height: insetY + handleHitRadius), [.minX, .minY]),
      (NSRect(x: rect.maxX - insetX, y: rect.minY - handleHitRadius,
              width: insetX + handleHitRadius, height: insetY + handleHitRadius), [.maxX, .minY]),
      (NSRect(x: rect.minX - handleHitRadius, y: rect.maxY - insetY,
              width: insetX + handleHitRadius, height: insetY + handleHitRadius), [.minX, .maxY]),
      (NSRect(x: rect.maxX - insetX, y: rect.maxY - insetY,
              width: insetX + handleHitRadius, height: insetY + handleHitRadius), [.maxX, .maxY])
    ]
  }

  private func edges(at point: NSPoint) -> Edges {
    guard !selectedRect.isEmpty,
          (previewRect.minX - handleHitRadius...previewRect.maxX + handleHitRadius).contains(point.x),
          (previewRect.minY - handleHitRadius...previewRect.maxY + handleHitRadius).contains(point.y) else { return [] }
    if let corner = cornerHitAreas.first(where: { $0.rect.contains(point) }) { return corner.edges }
    let rect = boxRect
    guard (rect.minX - handleHitRadius...rect.maxX + handleHitRadius).contains(point.x),
          (rect.minY - handleHitRadius...rect.maxY + handleHitRadius).contains(point.y) else { return [] }
    var result: Edges = []
    let left = abs(point.x - rect.minX), right = abs(point.x - rect.maxX)
    let bottom = abs(point.y - rect.minY), top = abs(point.y - rect.maxY)
    if left <= handleHitRadius && left <= right { result.insert(.minX) }
    else if right <= handleHitRadius { result.insert(.maxX) }
    if bottom <= handleHitRadius && bottom <= top { result.insert(.minY) }
    else if top <= handleHitRadius { result.insert(.maxY) }
    return result
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard !isHidden else { return nil }
    let localPoint = convert(point, from: superview)
    return previewRect.contains(localPoint) || !edges(at: localPoint).isEmpty ? self : nil
  }

  override func mouseDown(with event: NSEvent) {
    guard !isAnimatingSelection, previewRect.width > 0, previewRect.height > 0,
          videoSize.width > 0, videoSize.height > 0 else { return }
    let point = convert(event.locationInWindow, from: nil)
    guard previewRect.contains(point) || !edges(at: point).isEmpty else { return }
    window?.makeFirstResponder(self)
    let anchor = videoPoint(from: point)
    let hitEdges = edges(at: point)
    if !hitEdges.isEmpty {
      drag = .resize(hitEdges, selectedRect, anchor, centered: event.modifierFlags.contains(.option),
                     proportional: event.modifierFlags.contains([.option, .shift]), lastPoint: anchor)
    } else if !selectedRect.isEmpty && boxRect.contains(point) {
      drag = .move(selectedRect, anchor)
      NSCursor.closedHand.set()
    } else {
      drag = .select(anchor)
      NSCursor.crosshair.set()
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard let drag, previewRect.width > 0, previewRect.height > 0 else { return }
    let point = videoPoint(from: convert(event.locationInWindow, from: nil))
    let rect: NSRect
    switch drag {
    case let .select(anchor):
      rect = NSRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                    width: max(1, abs(point.x - anchor.x)), height: max(1, abs(point.y - anchor.y)))
    case let .move(initial, anchor):
      rect = NSRect(x: min(max(0, initial.minX + point.x - anchor.x), videoSize.width - initial.width),
                    y: min(max(0, initial.minY + point.y - anchor.y), videoSize.height - initial.height),
                    width: initial.width, height: initial.height)
    case let .resize(edges, initial, anchor, wasCentered, wasProportional, lastPoint):
      let centered = event.modifierFlags.contains(.option)
      let proportional = event.modifierFlags.contains([.option, .shift])
      // Rebase modifier changes at the visible frame to avoid a jump.
      let sameMode = centered == wasCentered && proportional == wasProportional
      let base = sameMode ? initial : selectedRect
      let origin = sameMode ? anchor : lastPoint
      self.drag = .resize(edges, base, origin, centered: centered, proportional: proportional, lastPoint: point)
      var minX = base.minX, maxX = base.maxX, minY = base.minY, maxY = base.maxY
      let dx = point.x - origin.x, dy = point.y - origin.y
      if proportional {
        // Project corners onto their displayed diagonal; edge drags use only their own axis.
        let halfX: CGFloat = edges.contains(.minX) ? -base.width / 2 :
          (edges.contains(.maxX) ? base.width / 2 : 0)
        let halfY: CGFloat = edges.contains(.minY) ? -base.height / 2 :
          (edges.contains(.maxY) ? base.height / 2 : 0)
        let pixelX = imageRect.width / videoSize.width
        let pixelY = imageRect.height / videoSize.height
        let denominator = pow(halfX * pixelX, 2) + pow(halfY * pixelY, 2)
        let requested = 1 + (dx * halfX * pixelX * pixelX + dy * halfY * pixelY * pixelY) / denominator
        let maximum = min(2 * min(base.midX, videoSize.width - base.midX) / base.width,
                          2 * min(base.midY, videoSize.height - base.midY) / base.height)
        // Preserve integer edges and the exact center, including odd sizes.
        let minimumWidth: CGFloat = Int(base.width) % 2 == 0 ? 2 : 1
        let minimumHeight: CGFloat = Int(base.height) % 2 == 0 ? 2 : 1
        let minimum = max(minimumWidth / base.width, minimumHeight / base.height)
        let scale = min(maximum, max(minimum, requested))
        let changeX = ((scale - 1) * base.width / 2).rounded()
        let changeY = ((scale - 1) * base.height / 2).rounded()
        minX -= changeX
        maxX += changeX
        minY -= changeY
        maxY += changeY
      } else if centered {
        // Whole source-pixel steps preserve the exact center, including at image boundaries.
        func inset(_ delta: CGFloat, length: CGFloat, margin: CGFloat) -> CGFloat {
          min(floor((length - 1) / 2), max(-margin, delta.rounded()))
        }
        if !edges.intersection([.minX, .maxX]).isEmpty {
          let change = inset(edges.contains(.minX) ? dx : -dx, length: base.width,
                             margin: min(base.minX, videoSize.width - base.maxX))
          minX += change
          maxX -= change
        }
        if !edges.intersection([.minY, .maxY]).isEmpty {
          let change = inset(edges.contains(.minY) ? dy : -dy, length: base.height,
                             margin: min(base.minY, videoSize.height - base.maxY))
          minY += change
          maxY -= change
        }
      } else {
        if edges.contains(.minX) { minX = min(maxX - 1, max(0, minX + dx)) }
        if edges.contains(.maxX) { maxX = max(minX + 1, min(videoSize.width, maxX + dx)) }
        if edges.contains(.minY) { minY = min(maxY - 1, max(0, minY + dy)) }
        if edges.contains(.maxY) { maxY = max(minY + 1, min(videoSize.height, maxY + dy)) }
      }
      rect = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    setSelectedRect(to: rect)
  }

  override func mouseUp(with event: NSEvent) {
    guard isDragging else { return }
    drag = nil
    window?.invalidateCursorRects(for: self)
    rectUpdatedCallback?()
  }

  override func keyDown(with event: NSEvent) {
    let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
    let delta: NSPoint
    switch event.keyCode {
    case 123: delta = NSPoint(x: -step, y: 0)
    case 124: delta = NSPoint(x: step, y: 0)
    case 125: delta = NSPoint(x: 0, y: -step)
    case 126: delta = NSPoint(x: 0, y: step)
    default: super.keyDown(with: event); return
    }
    guard !isAnimatingSelection, !selectedRect.isEmpty else { return }
    var rect = selectedRect
    rect.origin.x = min(max(0, rect.minX + delta.x), videoSize.width - rect.width)
    rect.origin.y = min(max(0, rect.minY + delta.y), videoSize.height - rect.height)
    setSelectedRect(to: rect)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let rect = boxRect
    let outside = NSBezierPath(rect: previewRect)
    let visibleSelection = rect.intersection(previewRect)
    if !visibleSelection.isEmpty { outside.appendRect(visibleSelection) }
    outside.windingRule = .evenOdd
    NSColor.black.withAlphaComponent(0.52).setFill()
    outside.fill()
    guard !selectedRect.isEmpty else { return }

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: previewRect.insetBy(dx: -3, dy: -3)).addClip()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
    shadow.shadowBlurRadius = 2
    shadow.set()
    NSColor.white.withAlphaComponent(0.85).setStroke()
    let outline = NSBezierPath(rect: rect)
    outline.lineWidth = 1
    outline.stroke()
    let corners = NSBezierPath()
    let length = cornerLength
    for (x, dx) in [(rect.minX, CGFloat(1)), (rect.maxX, CGFloat(-1))] {
      for (y, dy) in [(rect.minY, CGFloat(1)), (rect.maxY, CGFloat(-1))] {
        corners.move(to: NSPoint(x: x, y: y + dy * length))
        corners.line(to: NSPoint(x: x, y: y))
        corners.line(to: NSPoint(x: x + dx * length, y: y))
      }
    }
    NSColor.white.setStroke()
    corners.lineWidth = 3
    corners.lineJoinStyle = .miter
    corners.stroke()
    NSGraphicsContext.restoreGraphicsState()
  }

  override func resetCursorRects() {
    guard !isAnimatingSelection else { addCursorRect(bounds, cursor: .arrow); return }
    guard !selectedRect.isEmpty else { addCursorRect(previewRect, cursor: .crosshair); return }
    func addVisibleCursorRect(_ area: NSRect, cursor: NSCursor) {
      let visible = area.intersection(bounds)
      guard !visible.isEmpty else { return }
      addCursorRect(visible, cursor: cursor)
    }
    let rect = boxRect
    let visibleSelection = rect.intersection(previewRect)
    addVisibleCursorRect(visibleSelection, cursor: drag == nil ? .openHand : .closedHand)
    let edgeRects: [(NSRect, NSCursor)] = [
      (NSRect(x: rect.minX, y: rect.minY - handleHitRadius, width: rect.width, height: 2 * handleHitRadius), ResizeCursor.vertical),
      (NSRect(x: rect.minX, y: rect.maxY - handleHitRadius, width: rect.width, height: 2 * handleHitRadius), ResizeCursor.vertical),
      (NSRect(x: rect.minX - handleHitRadius, y: rect.minY, width: 2 * handleHitRadius, height: rect.height), ResizeCursor.horizontal),
      (NSRect(x: rect.maxX - handleHitRadius, y: rect.minY, width: 2 * handleHitRadius, height: rect.height), ResizeCursor.horizontal)
    ]
    for (area, cursor) in edgeRects { addVisibleCursorRect(area, cursor: cursor) }
    for corner in cornerHitAreas {
      let cursor = corner.edges.contains(.minX) == corner.edges.contains(.minY) ? ResizeCursor.rising : ResizeCursor.falling
      addVisibleCursorRect(corner.rect, cursor: cursor)
    }
  }
}
