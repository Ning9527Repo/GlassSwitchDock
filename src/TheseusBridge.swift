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

// A fixed image baked by the original Clear shader at BUILD time. This class
// never creates TheseusView, Metal, a display link, a timer or a backdrop source.
@objc(NGClearDockView)
final class NGClearDockView: UIView {
    private let imageView = UIImageView()
    @objc var hasStaticImage: Bool { imageView.image != nil }
    private static let fixedImage: UIImage? = {
        var path = NGBundleResources()?.path(forResource: "DockClearStatic", ofType: "png")
        #if NG_TESTING
        if path == nil, let output = ProcessInfo.processInfo.environment["NG_TEST_OUTPUT"] {
            path = (output as NSString).appendingPathComponent("DockClearStatic.png")
        }
        #endif
        guard let path = path, let raw = UIImage(contentsOfFile: path), let cg = raw.cgImage else { return nil }
        let image = UIImage(cgImage: cg, scale: 3, orientation: .up)
        let cap = min(32, (image.size.width - 1) / 2)
        return image.resizableImage(withCapInsets: UIEdgeInsets(top: cap, left: cap, bottom: cap, right: cap), resizingMode: .stretch)
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        isOpaque = false
        backgroundColor = .clear
        imageView.image = Self.fixedImage
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = false
        imageView.isAccessibilityElement = false
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)
    }
    required init?(coder: NSCoder) { return nil }
    @objc(setStaticRadius:)
    func setStaticRadius(_ value: CGFloat) {
        let radius = min(max(value, 0.01), min(bounds.width, bounds.height) / 2)
        if layer.cornerRadius != radius { layer.cornerRadius = radius }
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
    }
}
