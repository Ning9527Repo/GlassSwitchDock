import UIKit

// No geometry, material, animation, colour or physics override is applied to
// this instance. Only the existing UISwitch's value and enabled state are bound.
@objc(NGTheseusSwitch)
final class NGTheseusSwitch: UIView {
    private let toggle = TheseusSwitch()
    @objc var onChanged: ((Bool) -> Void)?
    @objc var on: Bool {
        get { toggle.isOn }
        set { toggle.isOn = newValue }
    }
    @objc(isOn) func isOn() -> Bool { toggle.isOn }

    override init(frame: CGRect) {
        super.init(frame: CGRect(origin: frame.origin, size: CGSize(width: 63, height: 28)))
        backgroundColor = .clear
        clipsToBounds = false
        isOpaque = false
        addSubview(toggle)
        toggle.frame = bounds
        toggle.onValueChanged = { [weak self] value in self?.onChanged?(value) }
    }
    required init?(coder: NSCoder) { return nil }
    override var intrinsicContentSize: CGSize { toggle.intrinsicContentSize }
    override func layoutSubviews() { super.layoutSubviews(); toggle.frame = bounds }
    @objc(setOn:animated:) func setOn(_ value: Bool, animated: Bool) {
        toggle.setOn(value, animated: animated)
    }
    @objc(setControlEnabled:) func setControlEnabled(_ enabled: Bool) { toggle.isEnabled = enabled }
    override var accessibilityLabel: String? {
        get { toggle.accessibilityLabel }
        set { toggle.accessibilityLabel = newValue }
    }
    override func accessibilityActivate() -> Bool { toggle.accessibilityActivate() }
}

@objc(NGClearDockView)
final class NGClearDockView: TheseusView {
    @objc var onReady: (() -> Void)?
    private var lastRadius: CGFloat = -1
    private var lastSize: CGSize = .zero
    private var active = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        providesCaptureSnapshot = true
        continuousUpdate = false
        isOpaque = false
        onPresent = { [weak self] in self?.onReady?() }
    }
    required init?(coder: NSCoder) { return nil }

    @objc(configureWithRadius:source:excluded:)
    func configure(radius: CGFloat, source: UIView, excluded: [UIView]) {
        sourceView = source
        setCaptureExcludedViews(excluded)
        if radius != lastRadius || lastSize != bounds.size {
            lastRadius = radius
            lastSize = bounds.size
            var config = TheseusConfiguration.clear
            config.captureMethod = TheseusCapability.isDeviceSupported ? .layerRendering : .surfaceBased
            config.shape.cornerRadius = min(max(radius, 0.01), min(bounds.width, bounds.height) / 2)
            // Clear has no external drop shadow. The Dock uses the system's
            // exact bounds; no padded drawable is compressed into those bounds.
            config.shape.padding = .zero
            config.shape.widthInset = 0
            config.shape.heightInset = 0
            // Only capsule-shaped hosts take the original continuous capsule ends.
            config.shape.continuousCapsule = config.shape.cornerRadius >= min(bounds.width, bounds.height) / 2 - 0.5
            configuration = config
            setNeedsLayout()
        }
        invalidateBackground()
    }
    @objc(invalidateBackdrop) func invalidateBackdrop() { invalidateBackground() }
    @objc(setRenderingActive:) func setRenderingActive(_ value: Bool) {
        active = value
        if value && window != nil { resumeRendering(); invalidateBackground() }
        else { pauseRendering() }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        setRenderingActive(active)
        if window != nil, metalLayer == nil { onReady?() }
    }
}
