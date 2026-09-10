import AppKit
import Combine
import QuartzCore

/// Turns lid angles into the bend on screen: starts the capture as the lid approaches
/// the clear angle, shows the overlay once frames flow, eases the effect toward the
/// current angle every frame, and clears it (with a click) when the lid opens again.
@MainActor
final class OverlayController: ObservableObject {
    static let shared = OverlayController()

    @Published private(set) var lidAngle: Double?
    @Published private(set) var sensorAvailable = false
    @Published private(set) var isBending = false
    @Published private(set) var hasScreenPermission = ScreenCapturer.hasPermission
    /// Set from the menu bar; nothing bends until it is cleared.
    @Published var isPaused = false { didSet { evaluate() } }
    /// Set by Esc or a click on the overlay; clears itself once the lid opens past the clear angle.
    @Published private(set) var isSuspended = false

    let settings = AppSettings.shared
    private let sensor = LidSensor()
    private let capturer = ScreenCapturer()
    private let click = ClickSound()

    private var window: OverlayWindow?
    private var metalView: OverlayMetalView?
    private var previousApp: NSRunningApplication?
    private var didActivate = false

    private var current: Double = 0
    private var target: Double = 0
    private var lastTick: CFTimeInterval = 0
    private var peak: Double = 0
    private var isStartingCapture = false
    private var didRequestPermission = false
    private var stopCaptureWork: DispatchWorkItem?
    private var screenLocked = false
    private var displayAsleep = false
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func start() {
        sensor.onAngle = { [weak self] angle in
            self?.lidAngle = angle
            self?.evaluate()
        }
        sensor.onAvailabilityChange = { [weak self] available in
            self?.sensorAvailable = available
            if !available { self?.lidAngle = nil }
            self?.evaluate()
        }
        sensor.start()

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screenLocked = true; self?.evaluate() }
        }
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screenLocked = false; self?.evaluate() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.displayAsleep = true; self?.evaluate() }
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.displayAsleep = false; self?.evaluate() }
        }
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hideOverlay(silent: true); self?.stopCapture() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuildWindowIfNeeded() }
        }
    }

    // MARK: - State

    /// The angle the effect follows right now: the sensor, or the slider in manual mode.
    var effectiveAngle: Double? {
        settings.followLid ? lidAngle : settings.manualAngle
    }

    var currentProgress: Double { current }

    func refreshPermission() {
        hasScreenPermission = ScreenCapturer.hasPermission
    }

    func requestPermission() {
        didRequestPermission = true
        ScreenCapturer.requestPermission()
        refreshPermission()
    }

    /// Esc or a click: hide until the lid opens past the clear angle again.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        evaluate()
    }

    private func evaluate() {
        let blocked = isPaused || isSuspended || screenLocked || displayAsleep
        let angle = effectiveAngle
        let progress = angle.map(settings.progress(forAngle:)) ?? 0

        if isSuspended, progress == 0 { isSuspended = false }

        target = blocked ? 0 : progress
        let approaching = !blocked && angle.map { $0 < settings.clearAngle + 10 } == true

        if approaching || target > 0 {
            stopCaptureWork?.cancel()
            stopCaptureWork = nil
            startCaptureIfNeeded()
        } else if capturer.isRunning, window?.isVisible != true, stopCaptureWork == nil {
            let work = DispatchWorkItem { [weak self] in self?.stopCapture() }
            stopCaptureWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        }

        if target > 0, window?.isVisible != true {
            showOverlayWhenReady()
        }
    }

    // MARK: - Capture

    private func startCaptureIfNeeded() {
        guard !capturer.isRunning, !isStartingCapture else { return }
        refreshPermission()
        guard hasScreenPermission else {
            if !didRequestPermission {
                didRequestPermission = true
                NSLog("Slant: waiting for Screen Recording permission")
                ScreenCapturer.requestPermission()
            }
            return
        }
        guard let screen = builtInScreen() else { return }
        rebuildWindowIfNeeded()
        guard let window else { return }
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let rect = CGRect(x: 0, y: menuBarHeight, width: screen.frame.width, height: screen.frame.height - menuBarHeight)
        isStartingCapture = true
        Task {
            defer { isStartingCapture = false }
            do {
                try await capturer.start(displayID: displayID, rect: rect, pixelScale: screen.backingScaleFactor,
                                         excludingWindows: [CGWindowID(window.windowNumber)])
                NSLog("Slant: capture started \(Int(rect.width * screen.backingScaleFactor))x\(Int(rect.height * screen.backingScaleFactor))")
            } catch {
                NSLog("Slant: capture failed: \(error)")
            }
            evaluate()
        }
    }

    private func stopCapture() {
        stopCaptureWork = nil
        capturer.stop()
        metalView?.reset()
    }

    // MARK: - Window

    private func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
            return CGDisplayIsBuiltin(id) != 0
        } ?? NSScreen.main
    }

    private func rebuildWindowIfNeeded() {
        guard let screen = builtInScreen() else { return }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: screen.frame.height - menuBarHeight)
        if let window, window.frame == frame, window.screen == screen { return }
        let wasVisible = window?.isVisible == true
        window?.orderOut(nil)
        if capturer.isRunning { stopCapture() }

        let window = OverlayWindow(frame: frame)
        window.onDismiss = { [weak self] in self?.suspend() }
        let view = OverlayMetalView(frame: NSRect(origin: .zero, size: frame.size))
        view.frameProvider = { [weak self] in self?.capturer.takeLatestFrame() }
        view.paramsProvider = { [weak self] in
            guard let self else { return BendParams(progress: 0, style: .silk) }
            return BendParams(progress: self.current, settings: self.settings)
        }
        view.onFrame = { [weak self] in self?.tick() }
        window.contentView = view
        self.window = window
        self.metalView = view
        if wasVisible { evaluate() }
    }

    private func showOverlayWhenReady() {
        guard let window, !window.isVisible else { return }
        guard capturer.hasFrame else {
            guard capturer.isRunning || isStartingCapture else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, self.target > 0 else { return }
                self.showOverlayWhenReady()
            }
            return
        }
        lastTick = CACurrentMediaTime()
        peak = 0
        if settings.followLid {
            previousApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            didActivate = true
        } else {
            window.orderFrontRegardless()
            didActivate = false
        }
        metalView?.isPaused = false
        isBending = true
        NSLog("Slant: overlay shown at \(Int(effectiveAngle ?? -1))°")
    }

    private func hideOverlay(silent: Bool = false) {
        guard let window, window.isVisible else { return }
        window.orderOut(nil)
        metalView?.isPaused = true
        isBending = false
        current = 0
        if didActivate {
            didActivate = false
            if let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                previousApp.activate()
            }
        }
        previousApp = nil
        if peak > 0.3, settings.soundEnabled, !silent { click.play() }
        NSLog("Slant: overlay hidden, peak \(Int(peak * 100))%")
        peak = 0
        evaluate()
    }

    /// Runs once per rendered frame while the overlay is visible.
    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastTick, 0), 0.1)
        lastTick = now
        let rate = 1 - exp(-dt * 9)
        current += (target - current) * rate
        if abs(target - current) < 0.0015 { current = target }
        peak = max(peak, current)
        if current == 0, target == 0 {
            hideOverlay()
        }
    }
}
