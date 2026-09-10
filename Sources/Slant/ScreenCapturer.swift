import Foundation
import CoreGraphics
import CoreMedia
import ScreenCaptureKit

/// Streams the built-in display with ScreenCaptureKit and keeps the newest frame.
/// The overlay window is excluded from the capture so the bent picture never
/// contains itself.
final class ScreenCapturer: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let outputQueue = DispatchQueue(label: "slant.capture", qos: .userInteractive)
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var frameCount = 0

    var isRunning: Bool { stream != nil }

    var hasFrame: Bool {
        lock.lock(); defer { lock.unlock() }
        return latest != nil
    }

    /// Newest complete frame, or nil before the first one arrives.
    func takeLatestFrame() -> CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// Captures `rect` (display points, origin top-left) of `displayID`, excluding the
    /// given window numbers.
    func start(displayID: CGDirectDisplayID, rect: CGRect, pixelScale: CGFloat, excludingWindows windowIDs: [CGWindowID]) async throws {
        guard stream == nil else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let excluded = content.windows.filter { windowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect
        configuration.width = Int(rect.width * pixelScale)
        configuration.height = Int(rect.height * pixelScale)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 4
        configuration.showsCursor = false
        configuration.capturesAudio = false

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        Task { try? await stream.stopCapture() }
        lock.lock()
        latest = nil
        frameCount = 0
        lock.unlock()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              statusValue == SCFrameStatus.complete.rawValue,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        latest = pixelBuffer
        frameCount += 1
        lock.unlock()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.stream = nil
        lock.lock()
        latest = nil
        lock.unlock()
    }

    enum CaptureError: Error { case displayNotFound }
}
