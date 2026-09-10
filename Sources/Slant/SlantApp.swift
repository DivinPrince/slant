import SwiftUI
import Combine

@main
struct SlantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var controller = OverlayController.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra {
            Text(statusLine)
            Divider()
            Button(controller.isPaused ? "Resume" : "Pause") { controller.isPaused.toggle() }
                .keyboardShortcut("p")
            Button("Settings…") { SettingsWindowController.shared.show(pane: .appearance) }
                .keyboardShortcut(",")
            Divider()
            Button("About Slant") { SettingsWindowController.shared.show(pane: .about) }
            Button("Quit Slant") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            HStack(spacing: 4) {
                Image(systemName: controller.isPaused ? "laptopcomputer.slash" : "laptopcomputer")
                if settings.showAngleInMenuBar, let angle = controller.lidAngle {
                    Text("\(Int(angle.rounded()))°").monospacedDigit()
                }
            }
        }
    }

    private var statusLine: String {
        if controller.isPaused { return "Paused" }
        if !controller.hasScreenPermission { return "Needs Screen Recording access" }
        if !controller.sensorAvailable { return "Lid sensor not found" }
        if let angle = controller.lidAngle { return "Lid at \(Int(angle.rounded()))°" }
        return "Waiting for the lid"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        OverlayController.shared.start()
        if !ScreenCapturer.hasPermission {
            OverlayController.shared.requestPermission()
            SettingsWindowController.shared.show(pane: .general)
        }
    }
}

/// One settings window, styled after System Settings. While the desktop is bending it
/// rides above the overlay so the sliders stay usable during a manual demo.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var cancellable: AnyCancellable?

    func show(pane: SettingsPane) {
        if window == nil {
            let view = SettingsView(initialPane: pane)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 640),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Slant"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.setFrameAutosaveName("SlantSettings")
            self.window = window
            cancellable = OverlayController.shared.$isBending.sink { [weak window] bending in
                window?.level = bending ? NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1) : .normal
            }
        } else {
            SettingsView.paneRequest.send(pane)
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
