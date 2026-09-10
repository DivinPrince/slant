import AppKit
import MetalKit
import CoreVideo

/// Sits above the Dock and every app window, under the menu bar, on the built-in
/// display. It is excluded from screen sharing so the capture never sees itself.
/// Level 23 is one below the menu bar (24), so the status item stays clickable.
final class OverlayWindow: NSWindow {
    var onDismiss: (() -> Void)?

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(frame, display: false)
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        sharingType = .none
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDismiss?() }
    }

    override func mouseDown(with event: NSEvent) { onDismiss?() }
    override func rightMouseDown(with event: NSEvent) { onDismiss?() }
}

/// Draws the latest captured frame through the bend shader, once per display refresh
/// while the overlay is on screen.
final class OverlayMetalView: MTKView, MTKViewDelegate {
    var frameProvider: (() -> CVPixelBuffer?)?
    var paramsProvider: (() -> BendParams)?
    var onFrame: (() -> Void)?

    private let renderer = Renderer.shared
    private var mipTexture: MTLTexture?
    private var lastPixelBuffer: CVPixelBuffer?

    init(frame: CGRect) {
        super.init(frame: frame, device: renderer.device)
        renderer.configure(self)
        preferredFramesPerSecond = 60
        delegate = self
    }

    required init(coder: NSCoder) { fatalError() }

    func reset() {
        lastPixelBuffer = nil
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        onFrame?()
        guard let commandBuffer = renderer.queue.makeCommandBuffer() else { return }
        var retained: CVMetalTexture?
        if let pixelBuffer = frameProvider?(), pixelBuffer !== lastPixelBuffer, let (frame, cvTexture) = renderer.wrap(pixelBuffer) {
            lastPixelBuffer = pixelBuffer
            if mipTexture == nil || mipTexture!.width != frame.width || mipTexture!.height != frame.height {
                mipTexture = renderer.makeMipTexture(width: frame.width, height: frame.height)
            }
            renderer.encodeUpload(of: frame, into: mipTexture!, using: commandBuffer)
            retained = cvTexture
        }
        guard let mipTexture, let params = paramsProvider?(), let drawable = view.currentDrawable else {
            commandBuffer.commit()
            return
        }
        renderer.encodeDraw(source: mipTexture, params: params, in: view, using: commandBuffer)
        commandBuffer.addCompletedHandler { _ in _ = retained }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
