//
//  OSCFloatingView.swift
//  iina
//
//  Created by Hechen Li on 2026-06-09.
//  Copyright © 2026 lhc. All rights reserved.
//

class OSCFloatingView: TranslucentView {
  private let width = FloatingOSCMetrics.preferredWidth
  private var preferredWidthConstraint: NSLayoutConstraint!
  private var paddingConstraints: [(constraint: NSLayoutConstraint, regular: CGFloat, compact: CGFloat)] = []
  private var updatingPosition = false
  weak var mainWindow: MainWindowController!
  private let prefObserver = Preference.Observer()

  var oscTopView: NSStackView!
  var oscBottomView: TimeLabelOverflowedStackView!

  private var xConstraint: NSLayoutConstraint!
  private var yConstraint: NSLayoutConstraint!

  var mousePosRelatedToView: CGPoint?

  // Manual placement belongs to this window session, never to preferences.
  private(set) var currentPosition: FloatingOSCPosition?
  private var windowSessionEnded = false

  var isDragging: Bool = false
  private var didDrag = false
  private var dragRequestedOrigin: CGPoint?
  private var dragStartLocation: CGPoint?
  private enum PositionMotion {
    case returning(from: CGPoint, startedAt: TimeInterval, duration: TimeInterval)
  }
  private var positionMotion: PositionMotion?
  private var positionTimer: Timer?
  private var backgroundClickTimer: Timer?
  var isReturningToDefault: Bool { positionMotion != nil }

  override var isHidden: Bool {
    didSet { if isHidden { cancelPositionAnimation(); cancelPendingBackgroundClick() } }
  }

  override var mouseDownCanMoveWindow: Bool {
    isReturningToDefault ? false : super.mouseDownCanMoveWindow
  }

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow

    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let cornerRadius: CGFloat = if #available(macOS 26.0, *) { 12 } else { 6 }
    super.init(liquidGlassCornerRadius: cornerRadius, vevCornerRadius: cornerRadius, padding: (0, 0))

    self.oscTopView = NSStackView()
    oscTopView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(oscTopView)
    let topPadding = oscTopView.topAnchor.constraint(equalTo: container.topAnchor, constant: FloatingOSCMetrics.topInset)
    let topLeading = oscTopView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: FloatingOSCMetrics.sideInset)
    let topTrailing = container.trailingAnchor.constraint(equalTo: oscTopView.trailingAnchor, constant: FloatingOSCMetrics.sideInset)

    self.oscBottomView = TimeLabelOverflowedStackView()
    oscBottomView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(oscBottomView)
    let bottomPadding = container.bottomAnchor.constraint(equalTo: oscBottomView.bottomAnchor, constant: FloatingOSCMetrics.bottomInset)
    let bottomLeading = oscBottomView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: FloatingOSCMetrics.timelineInset)
    let bottomTrailing = container.trailingAnchor.constraint(equalTo: oscBottomView.trailingAnchor, constant: FloatingOSCMetrics.timelineInset)
    let rowGap = oscBottomView.topAnchor.constraint(equalTo: oscTopView.bottomAnchor, constant: FloatingOSCMetrics.rowGap)
    paddingConstraints = [(topPadding, FloatingOSCMetrics.topInset, FloatingOSCMetrics.compactTopInset),
                          (topLeading, FloatingOSCMetrics.sideInset, FloatingOSCMetrics.sideInset),
                          (topTrailing, FloatingOSCMetrics.sideInset, FloatingOSCMetrics.sideInset),
                          (bottomPadding, FloatingOSCMetrics.bottomInset, FloatingOSCMetrics.compactBottomInset),
                          (bottomLeading, FloatingOSCMetrics.timelineInset, FloatingOSCMetrics.timelineInset),
                          (bottomTrailing, FloatingOSCMetrics.timelineInset, FloatingOSCMetrics.timelineInset),
                          (rowGap, FloatingOSCMetrics.rowGap, FloatingOSCMetrics.rowGap)]
    NSLayoutConstraint.activate(paddingConstraints.map { $0.constraint })

    preferredWidthConstraint = widthAnchor.constraint(equalToConstant: width)
    preferredWidthConstraint.priority = .init(300)
    preferredWidthConstraint.isActive = true

    setContent(container)

    prefObserver.add(.useLiquidGlassOSC, runNow: true) { [unowned self] _ in
      setStyle(Preference.liquidGlass(.osc) ? .liquidGlass : .visualEffect)
    }

    prefObserver.add(.compactUI, runNow: false) { [weak self] _ in
      self?.updatePosition()
    }


  }

  func setupConstraints() {
    guard let contentView = mainWindow.window?.contentView else { return }
    padding(.horizontal(greaterThan: 0), from: contentView)

    xConstraint = centerXAnchor.constraint(equalTo: contentView.leftAnchor)
    xConstraint.priority = .defaultLow
    xConstraint.isActive = true

    yConstraint = contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
    yConstraint.priority = .defaultHigh
    yConstraint.isActive = true
  }

  func beginWindowSession() {
    guard windowSessionEnded else { return }
    windowSessionEnded = false
    currentPosition = Preference.floatingOSCDefaultPosition
    updatePosition()
  }

  func endWindowSession() {
    cancelPendingBackgroundClick()
    cancelPositionAnimation()
    windowSessionEnded = true
    currentPosition = nil
    isDragging = false
    didDrag = false
    mousePosRelatedToView = nil
    dragRequestedOrigin = nil
  }

  private func safeTitlebarBottom(in contentView: NSView) -> CGFloat? {
    mainWindow.titleBarView.map {
      let frame = contentView.convert($0.bounds, from: $0)
      // The header's painted edge is 1 pt above its separator; align glass there to avoid a video seam.
      return mainWindow.fsState.isFullscreen ? frame.minY : min(frame.minY, contentView.bounds.maxY - frame.height) + 1
    }
  }

  private func verticalRange(in contentView: NSView, height: CGFloat,
                             margin: CGFloat = 0) -> ClosedRange<CGFloat> {
    return FloatingOSCPlacement.verticalRange(height: height,
                                             windowHeight: contentView.bounds.height,
                                             titlebarBottom: safeTitlebarBottom(in: contentView),
                                             margin: margin)
  }

  func updatePosition(animated: Bool = false) {
    guard !isDragging, !updatingPosition, let mainWindow, let contentView = mainWindow.window?.contentView,
          xConstraint != nil else { return }
    updatingPosition = true
    defer { updatingPosition = false }
    guard let target = positionTarget(in: contentView) else { return }
    if isReturningToDefault {
      // Resize can precede the next motion tick; clamp the displayed frame without changing session intent.
      applyPosition(CGPoint(x: xConstraint.constant, y: yConstraint.constant), in: contentView)
      return
    }
    if animated && !AccessibilityPreferences.motionReductionEnabled {
      xConstraint.animator().constant = target.x
      yConstraint.animator().constant = target.y
    } else {
      applyPosition(target, in: contentView)
    }
  }

  private func positionTarget(in contentView: NSView, position: FloatingOSCPosition? = nil) -> CGPoint? {
    let scale = FloatingOSCScale.factor(for: contentView.bounds.size)
    mainWindow.updateFloatingOSCScale(scale: scale)
    let windowWidth = contentView.bounds.width
    preferredWidthConstraint.constant = width * scale
    let compact = Preference.bool(for: .compactUI)
    for item in paddingConstraints {
      item.constraint.constant = (compact ? item.compact : item.regular) * scale
    }
    // AppKit may still have the previous control dimensions; lay out before clamping the panel.
    contentView.layoutSubtreeIfNeeded()
    let oscWidth = frame.width > 0 ? frame.width : min(width, windowWidth)
    let oscHeight = frame.height > 0 ? frame.height : fittingSize.height
    guard windowWidth > 0, contentView.bounds.height > 0 else { return nil }
    let titlebarBottom = safeTitlebarBottom(in: contentView)
    let placement = position ?? currentPosition ?? Preference.floatingOSCDefaultPosition
    // Late layout callbacks after close must not start a new session.
    if position == nil, !windowSessionEnded { currentPosition = placement }
    let requested = FloatingOSCPlacement.frame(position: placement,
      size: NSSize(width: oscWidth, height: oscHeight),
      contentSize: contentView.bounds.size, titlebarBottom: titlebarBottom)
    return CGPoint(x: requested.midX, y: requested.minY)
  }

  private func applyPosition(_ position: CGPoint, in contentView: NSView) {
    let xRange = FloatingOSCPlacement.horizontalRange(width: frame.width, windowWidth: contentView.bounds.width)
    xConstraint.constant = position.x.clamped(to: (xRange.lowerBound + frame.width / 2)...(xRange.upperBound + frame.width / 2))
    yConstraint.constant = position.y.clamped(to: verticalRange(in: contentView, height: frame.height))
    contentView.needsLayout = true
    contentView.layoutSubtreeIfNeeded()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard let hit = super.hitTest(point) else { return nil }
    // Returning controls must consume input so it cannot reach a moving control or seek the video.
    return isReturningToDefault ? self : hit
  }

  override func scrollWheel(with event: NSEvent) {
    guard !isReturningToDefault else { return }
    super.scrollWheel(with: event)
  }

  override func otherMouseDown(with event: NSEvent) {
    guard !isReturningToDefault else { return }
    super.otherMouseDown(with: event)
  }

  override func otherMouseUp(with event: NSEvent) {
    guard !isReturningToDefault else { return }
    super.otherMouseUp(with: event)
  }

  override func otherMouseDragged(with event: NSEvent) {
    guard !isReturningToDefault else { return }
    super.otherMouseDragged(with: event)
  }

  override func mouseDown(with event: NSEvent) {
    cancelPendingBackgroundClick()
    guard !isReturningToDefault else { return }
    if event.clickCount == 2 && isBackgroundEvent(event) {
      isDragging = false
      didDrag = false
      dragRequestedOrigin = nil
      mousePosRelatedToView = nil
      performBackgroundAction(Preference.OSCClickAction(key: .oscDoubleClickAction) ?? .none)
      return
    }
    didDrag = false
    dragRequestedOrigin = nil
    guard let contentView = mainWindow.window?.contentView else { return }
    let pointer = contentView.convert(event.locationInWindow, from: nil)
    dragStartLocation = pointer
    mousePosRelatedToView = CGPoint(x: pointer.x - frame.minX, y: pointer.y - frame.minY)
    mainWindow.hideSeekPreview()
    isDragging = true
  }

  override func mouseDragged(with event: NSEvent) {
    guard !isReturningToDefault, isDragging, let mousePos = mousePosRelatedToView else { return }
    guard let contentView = mainWindow.window?.contentView else { return }
    let windowFrame = contentView.bounds
    let currentLocation = contentView.convert(event.locationInWindow, from: nil)
    if !didDrag, let start = dragStartLocation,
       hypot(currentLocation.x - start.x, currentLocation.y - start.y) <= 3 { return }
    var newOrigin = CGPoint(
      x: currentLocation.x - mousePos.x,
      y: currentLocation.y - mousePos.y
    )
    let xRange = FloatingOSCPlacement.horizontalRange(width: frame.width, windowWidth: windowFrame.width)
    newOrigin.x = newOrigin.x.clamped(to: xRange)
    newOrigin.y = newOrigin.y.clamped(to: verticalRange(in: contentView, height: frame.height, margin: 0))
    dragRequestedOrigin = newOrigin
    // A background press alone must not persist temporary minimum-window placement.
    didDrag = didDrag || abs(newOrigin.x - frame.minX) > 0.01 || abs(newOrigin.y - frame.minY) > 0.01
    let newConstraint = newOrigin.x + frame.width / 2
    xConstraint.constant = newConstraint
    yConstraint.constant = newOrigin.y
    contentView.layoutSubtreeIfNeeded()
  }

  override func mouseUp(with event: NSEvent) {
    guard !isReturningToDefault, isDragging else { return }
    isDragging = false
    mousePosRelatedToView = nil
    guard didDrag else {
      updatePosition()
      return
    }
    didDrag = false
    guard let requestedOrigin = dragRequestedOrigin else { return }
    dragRequestedOrigin = nil
    guard let contentView = mainWindow.window?.contentView else { return }
    guard contentView.bounds.width > 0, contentView.bounds.height > 0 else { return }
    // Temporary manual placement uses percentages; saved defaults retain their units.
    let titlebarBottom = safeTitlebarBottom(in: contentView)
    let previous = currentPosition ?? Preference.floatingOSCDefaultPosition
    func relativeFallback(_ axis: FloatingOSCPosition.Axis) -> CGFloat {
      // Preserve percent intent on a collapsed axis; point offsets fall back to center.
      guard axis.unit == .percent else { return 0.5 }
      return axis.edge == .near ? axis.value : 1 - axis.value
    }
    let position = FloatingOSCPlacement.capturing(
      frame: NSRect(origin: requestedOrigin, size: frame.size),
      keeping: .percentages(relativeFallback(previous.horizontal), relativeFallback(previous.vertical)),
      contentSize: contentView.bounds.size, titlebarBottom: titlebarBottom)
    currentPosition = position
  }

  override func rightMouseDown(with event: NSEvent) {}

  override func rightMouseUp(with event: NSEvent) {
    guard !isReturningToDefault, !isDragging, isBackgroundEvent(event) else { return }
    performBackgroundAction(Preference.OSCClickAction(key: .oscRightClickAction) ?? .none)
  }

  func resetPosition() {
    guard !isReturningToDefault, !windowSessionEnded else { return }
    isDragging = false
    didDrag = false
    mousePosRelatedToView = nil
    dragRequestedOrigin = nil
    guard let contentView = mainWindow?.window?.contentView, xConstraint != nil else { return }
    updatingPosition = true
    defer { updatingPosition = false }
    let savedPosition = Preference.floatingOSCDefaultPosition
    guard let target = positionTarget(in: contentView, position: savedPosition) else { return }
    currentPosition = savedPosition
    let origin = CGPoint(x: xConstraint.constant, y: yConstraint.constant)
    let distance = hypot(target.x - origin.x, target.y - origin.y)
    let duration = AccessibilityPreferences.adjustedDuration(FloatingOSCReturnCurve.duration(for: distance))
    guard !isHidden, !AccessibilityPreferences.motionReductionEnabled, duration > 0 else {
      applyPosition(target, in: contentView)
      return
    }
    if abs(origin.x - target.x) < 0.25 && abs(origin.y - target.y) < 0.25 {
      applyPosition(target, in: contentView)
      return
    }
    positionMotion = .returning(from: origin,
                                startedAt: ProcessInfo.processInfo.systemUptime, duration: duration)
    startPositionTimer()
  }

  private func returnPath(from origin: CGPoint, to target: CGPoint, in contentView: NSView) -> FloatingOSCReturnPath {
    let horizontal = FloatingOSCPlacement.horizontalRange(width: frame.width, windowWidth: contentView.bounds.width)
    let xRange = (horizontal.lowerBound + frame.width / 2)...(horizontal.upperBound + frame.width / 2)
    let yRange = verticalRange(in: contentView, height: frame.height)
    return FloatingOSCReturnPath(from: origin, to: target, horizontalRange: xRange, verticalRange: yRange)
  }

  private func startPositionTimer() {
    mainWindow.hideSeekPreview()
    if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: self) {
      window?.makeFirstResponder(nil)
    }
    guard positionTimer == nil else { return }
    let timer = Timer(timeInterval: 1 / 120, repeats: true) { [weak self] _ in
      self?.advancePositionAnimation()
    }
    positionTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func advancePositionAnimation() {
    guard let motion = positionMotion, !updatingPosition else { return }
    guard !windowSessionEnded, !isHidden, let contentView = mainWindow?.window?.contentView,
          window != nil else {
      cancelPositionAnimation()
      return
    }
    updatingPosition = true
    defer { updatingPosition = false }
    guard let target = positionTarget(in: contentView) else { return }
    let now = ProcessInfo.processInfo.systemUptime
    if AccessibilityPreferences.motionReductionEnabled || AccessibilityPreferences.adjustedDuration(1) == 0 {
      applyPosition(target, in: contentView)
      finishPositionAnimation()
      return
    }
    switch motion {
    case let .returning(origin, startedAt, duration):
      let t = CGFloat(min(1, (now - startedAt) / duration))
      applyPosition(returnPath(from: origin, to: target, in: contentView).position(at: t), in: contentView)
      if t == 1 {
        applyPosition(target, in: contentView)
        finishPositionAnimation()
      }
    }
  }

  private func finishPositionAnimation() {
    stopPositionTimer()
    mainWindow?.updateTimer()
  }

  func cancelPositionAnimation() {
    stopPositionTimer()
  }

  private func stopPositionTimer() {
    positionTimer?.invalidate()
    positionTimer = nil
    positionMotion = nil
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil { cancelPositionAnimation(); cancelPendingBackgroundClick() }
  }

  deinit {
    backgroundClickTimer?.invalidate()
    positionTimer?.invalidate()
  }

  func cancelPendingBackgroundClick() {
    backgroundClickTimer?.invalidate()
    backgroundClickTimer = nil
  }

  func performSingleBackgroundClick() {
    cancelPendingBackgroundClick()
    let action = Preference.OSCClickAction(key: .oscLeftClickAction) ?? .none
    guard action != .none else { return }
    // Defer a single click only while a configured double-click can supersede it.
    if (Preference.OSCClickAction(key: .oscDoubleClickAction) ?? .none) == Preference.OSCClickAction.none {
      performBackgroundAction(action)
    } else {
      backgroundClickTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.doubleClickInterval,
                                                  repeats: false) { [weak self] _ in
        guard let self else { return }
        backgroundClickTimer = nil
        guard window != nil, !isHidden, !windowSessionEnded, !isReturningToDefault, !isDragging else { return }
        performBackgroundAction(action)
      }
    }
  }

  private func performBackgroundAction(_ action: Preference.OSCClickAction) {
    switch action {
    case .none: break
    case .hideOSC: mainWindow.hideUIFromOSC()
    case .resetPosition: resetPosition()
    case .bringToFront: mainWindow.sidebars.bringPanelToFront(self)
    }
  }

  private func isBackgroundEvent(_ event: NSEvent) -> Bool {
    guard let superview,
          var hitView = hitTest(superview.convert(event.locationInWindow, from: nil)) else { return false }
    while hitView !== self {
      if hitView is NSControl || hitView is VolumeButton { return false }
      guard let parent = hitView.superview else { return false }
      hitView = parent
    }
    return true
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
