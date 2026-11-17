import UIKit
import Metal

// Build-host simulator only. Nothing from this type is linked into the tweak.
@objc(NGDockBaker)
final class NGDockBaker: NSObject {
    private static var host: UIView?
    private static var glass: TheseusView?
    private static var finished = false

    @objc(startIn:completion:) static func start(in root: UIView, completion: @escaping (Bool) -> Void) {
        let size = CGSize(width: 394, height: 100)
        let source = UIView(frame: CGRect(origin: .zero, size: size))
        source.backgroundColor = UIColor(white: 0.40, alpha: 1)
        source.isOpaque = true
        root.addSubview(source)
        let renderer = TheseusView(frame: CGRect(x: 1, y: 1, width: 392, height: 98))
        renderer.pauseRendering()
        let settings = TheseusSettings.shared
        let savedStyle = settings.glassStyle
        settings.glassStyle = .iOS27 // Same Clear preset selected on the user's iOS 17.
        var config = TheseusConfiguration.clear
        config.captureMethod = .layerRendering
        config.shape.cornerRadius = 32
        config.shape.padding = .zero
        config.shape.widthInset = 0
        config.shape.heightInset = 0
        config.shape.continuousCapsule = false
        renderer.configuration = config
        renderer.sourceView = source
        renderer.continuousUpdate = false
        renderer.providesCaptureSnapshot = true
        source.addSubview(renderer)
        renderer.metalLayer?.contentsScale = 3
        renderer.setNeedsLayout()
        renderer.layoutIfNeeded()
        host = source; glass = renderer; finished = false
        func finish(_ ok: Bool) {
            guard !finished else { return }
            finished = true
            renderer.pauseRendering()
            renderer.snapshotDidUpdate = nil
            settings.glassStyle = savedStyle
            source.removeFromSuperview()
            host = nil; glass = nil
            completion(ok)
        }
        renderer.snapshotDidUpdate = {
            guard let image = renderer.captureSnapshot, image.width == 1176, image.height == 294,
                  let png = UIImage(cgImage: image).pngData() else { return }
            let directory = NSProcessInfo.processInfo.environment["NG_TEST_OUTPUT"] ?? NSTemporaryDirectory()
            let url = URL(fileURLWithPath: directory).appendingPathComponent("DockClearStatic.png")
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try png.write(to: url, options: .atomic)
                finish(true)
            } catch { finish(false) }
        }
        renderer.resumeRendering()
        renderer.invalidateBackground()
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { finish(false) }
    }
}
