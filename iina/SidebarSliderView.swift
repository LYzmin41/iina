//
//  SidebarSliderView.swift
//  iina
//
//  Created by Hechen Li on 2026-06-15.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate let ui = UIHelper.shared


class SidebarSliderView: NSView {
  unowned let player: PlayerCore

  var notificationKey: Notification.Name { .init("") }
  var slider: NSSlider!
  var tickMarkTextFieldsConstraints: [NSLayoutConstraint] = []
  var input: NSTextField!
  private var inputContainer: ColoredView!
  var indicator: NSTextField!
  var indicatorConstraint: NSLayoutConstraint!

  var inputWidth: CGFloat { 50 }
  var titleImage: NSImage? { nil }
  var titleKey: String { "" }
  var showsTitle: Bool { true }
  var titleAccessory: NSView? { nil }
  var tickMarkLabels: [String] { [] }

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false

    self.slider = NSSlider()
    slider.translatesAutoresizingMaskIntoConstraints = false
    slider.controlSize = .small
    slider.tickMarkPosition = .below
    slider.target = self
    slider.action = #selector(sliderAction_)

    self.indicator = NSTextField(labelWithString: "")
    indicator.translatesAutoresizingMaskIntoConstraints = false
    indicator.font = .systemFont(ofSize: 10)
    indicator.setContentCompressionResistancePriority(.required, for: .horizontal)

    self.input = NSTextField()
    input.translatesAutoresizingMaskIntoConstraints = false
    input.usesSingleLineMode = true
    input.isBezeled = false
    input.isBordered = false
    input.drawsBackground = false
    input.backgroundColor = .clear
    input.target = self
    input.action = #selector(customEditFinishedAction_)

    inputContainer = ColoredView(color: .labelColor.withAlphaComponent(0.08), cornerRadius: 6)
    inputContainer.translatesAutoresizingMaskIntoConstraints = false
    inputContainer.addSubview(input)
    NSLayoutConstraint.activate([
      input.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 6),
      input.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -6),
      input.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
      inputContainer.heightAnchor.constraint(equalToConstant: 24)
    ])

    var titleViews = [
      ui.image(titleImage, size: 16, scaleUp: false) as NSView,
      ui.label(titleKey, font: .boldSystemFont(ofSize: 12)),
      ui.flexibleSpace(),
    ]
    if let titleAccessory { titleViews.append(titleAccessory) }
    let labelStack = ui.hStack(
      spacing: 8,
      titleViews
    )

    let tickMarkView = NSView()
    tickMarkView.translatesAutoresizingMaskIntoConstraints = false

    for (i, label) in tickMarkLabels.enumerated() {
      let label = NSTextField(labelWithString: label)
      label.translatesAutoresizingMaskIntoConstraints = false
      label.font = .systemFont(ofSize: 10)
      tickMarkView.addSubview(label)
      label.padding(.vertical)
      if i == 0 {
        label.leadingAnchor.constraint(equalTo: tickMarkView.leadingAnchor).isActive = true
      } else if i == tickMarkLabels.count - 1 {
        label.trailingAnchor.constraint(equalTo: tickMarkView.trailingAnchor).isActive = true
      } else {
        let constraint = label.centerXAnchor.constraint(equalTo: tickMarkView.leadingAnchor, constant: 0)
        constraint.isActive = true
        tickMarkTextFieldsConstraints.append(constraint)
      }
    }

    setup()

    if showsTitle { addSubview(labelStack) }
    addSubview(slider)
    addSubview(indicator)
    addSubview(inputContainer)
    addSubview(tickMarkView)

    indicator.padding(.horizontal(greaterThan: 0))
      .spacing(.bottom(2), to: slider)
    self.indicatorConstraint = indicator.centerXAnchor
      .constraint(equalTo: slider.leadingAnchor)
    indicatorConstraint.priority = .init(800)
    indicatorConstraint.isActive = true

    slider.padding(.leading, .bottom(16))
    if showsTitle {
      labelStack.padding(.horizontal, .top)
      slider.spacing(.top(18), to: labelStack)
      inputContainer.padding(.trailing)
    } else {
      slider.padding(.top(18))
      inputContainer.padding(.trailing)
    }
    inputContainer.spacing(.leading(8), to: slider).center(.y, with: slider).size(width: inputWidth)
    tickMarkView.padding(.leading, .bottom)

    tickMarkView.widthAnchor.constraint(equalTo: slider.widthAnchor, multiplier: 1).isActive = true

    player.observe(notificationKey) { [unowned self] _ in
      update_()
    }
  }

  override func viewDidMoveToSuperview() {
    update_()
  }

  override func layout() {
    super.layout()

    let numSpaces = CGFloat(tickMarkLabels.count - 1)
    for (i, constraint) in tickMarkTextFieldsConstraints.enumerated() {
      let xPos = xOffset(CGFloat(i + 1) / numSpaces)
      if constraint.constant != xPos {
        constraint.constant = xPos
      }
    }
    updateIndicator()
  }

  func xOffset(_ p: CGFloat) -> CGFloat {
    let knobWidth = slider.knobThickness
    return knobWidth / 2 + p * (slider.frame.size.width - knobWidth)
  }

  func updateIndicator() {
    /// Use `customSpeedTextField.stringValue` to take advantage of its formatter
    /// (e.g. `16` will be displayed instead of `16.0`)
    indicator.stringValue = indicatorLabel()

    let p = CGFloat((slider.doubleValue - slider.minValue) / (slider.maxValue - slider.minValue))
    let xPos = xOffset(p)
    if indicatorConstraint.constant != xPos {
      indicatorConstraint.constant = xPos
    }
  }

  private func update_() {
    guard player.info.state.active else { return }
    update()
  }

  @objc private func sliderAction_(_ sender: NSSlider) {
    sliderAction()
  }

  @objc private func customEditFinishedAction_(_ sender: NSTextField) {
    customEditFinishedAction()
  }

  func setup() {}
  func update() {}
  func indicatorLabel() -> String { input.stringValue }
  func sliderAction() {}
  func customEditFinishedAction() {}
  func resetButtonAction() {}

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

