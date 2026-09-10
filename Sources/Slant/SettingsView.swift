import SwiftUI
import Combine
import ServiceManagement

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "circle.lefthalf.filled"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .appearance: return .blue
        case .about: return .gray
        }
    }
}

struct SettingsView: View {
    static let paneRequest = PassthroughSubject<SettingsPane, Never>()

    @State private var pane: SettingsPane
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var controller = OverlayController.shared

    init(initialPane: SettingsPane = .appearance) {
        _pane = State(initialValue: initialPane)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 190)
                .background(.thinMaterial)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, minHeight: 560)
        .onReceive(SettingsView.paneRequest) { pane = $0 }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer().frame(height: 34)
            sidebarRow(.general)
            sectionLabel("Settings")
            sidebarRow(.appearance)
            sectionLabel("Slant")
            sidebarRow(.about)
            Spacer()
        }
        .padding(.horizontal, 10)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }

    private func sidebarRow(_ item: SettingsPane) -> some View {
        Button { pane = item } label: {
            HStack(spacing: 10) {
                PaneIcon(pane: item, size: 24)
                Text(item.title).font(.system(size: 15))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(pane == item ? Color.primary.opacity(0.1) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    PaneIcon(pane: pane, size: 30)
                    Text(pane.title).font(.system(size: 20, weight: .semibold))
                }
                switch pane {
                case .general: GeneralPane(settings: settings, controller: controller)
                case .appearance: AppearancePane(settings: settings, controller: controller)
                case .about: AboutPane(controller: controller)
                }
            }
            .padding(28)
            .padding(.top, 8)
        }
    }
}

struct PaneIcon: View {
    var pane: SettingsPane
    var size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28)
            .fill(pane.tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: pane.symbol)
                    .font(.system(size: size * 0.55, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: OverlayController

    private var previewAngle: Double {
        (settings.followLid ? controller.lidAngle : settings.manualAngle) ?? settings.manualAngle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            MacBookPreview(params: BendParams(progress: settings.progress(forAngle: previewAngle), settings: settings))
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)

            HStack(spacing: 14) {
                Text("\(Int(previewAngle.rounded()))°")
                    .font(.system(size: 17)).monospacedDigit()
                    .frame(width: 44, alignment: .leading)
                Slider(value: Binding(get: { previewAngle }, set: { settings.manualAngle = $0 }), in: 0...140)
                    .disabled(settings.followLid)
                Toggle("Follow lid", isOn: $settings.followLid)
                    .toggleStyle(.switch)
                    .font(.system(size: 17))
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 10) {
                Text("Style").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 20) {
                    ForEach(Style.allCases) { style in
                        StyleSwatch(style: style, selected: settings.style == style) { settings.apply(style) }
                    }
                }
            }
            .padding(.horizontal, 4)

            GroupBox {
                VStack(spacing: 0) {
                    percentRow("Perspective", value: $settings.perspective)
                    Divider()
                    percentRow("Variable blur", value: $settings.blur)
                    Divider()
                    percentRow("Shadow", value: $settings.shadow)
                    Divider()
                    HStack {
                        Text("Clears at").font(.system(size: 17))
                        Spacer()
                        Slider(value: $settings.clearAngle, in: 60...140, step: 1).frame(maxWidth: 300)
                        Text("\(Int(settings.clearAngle))°").font(.system(size: 17)).monospacedDigit()
                            .frame(width: 56, alignment: .trailing).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12).padding(.horizontal, 6)
                }
            }
            Text("Above the clear angle nothing happens. Below it the desktop tilts back, blurs and shades until the lid closes.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func percentRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).font(.system(size: 17))
            Spacer()
            Slider(value: value, in: 0...1).frame(maxWidth: 300)
            Text("\(Int((value.wrappedValue * 100).rounded()))%").font(.system(size: 17)).monospacedDigit()
                .frame(width: 56, alignment: .trailing).foregroundStyle(.secondary)
        }
        .padding(.vertical, 12).padding(.horizontal, 6)
    }
}

struct StyleSwatch: View {
    var style: Style
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                BendPreview(params: BendParams(progress: 0.55, style: style), animates: false)
                    .aspectRatio(1.54, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: selected ? 2.5 : 1))
                HStack(spacing: 5) {
                    Text(style.title).font(.system(size: 16))
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).font(.system(size: 13))
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - General

struct GeneralPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: OverlayController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox {
                VStack(spacing: 0) {
                    Toggle(isOn: $launchAtLogin) {
                        settingLabel("Launch at login", "Slant starts with your Mac and waits in the menu bar.")
                    }
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                    Divider().padding(.vertical, 10)
                    Toggle(isOn: $settings.soundEnabled) {
                        settingLabel("Sound", "A soft click when the lid opens and the desktop clears.")
                    }
                    Divider().padding(.vertical, 10)
                    Toggle(isOn: $settings.showAngleInMenuBar) {
                        settingLabel("Show angle in menu bar", "Displays the hinge angle next to the icon.")
                    }
                }
                .toggleStyle(.switch)
                .padding(8)
            }

            GroupBox {
                VStack(spacing: 0) {
                    HStack {
                        settingLabel("Screen Recording", controller.hasScreenPermission
                                     ? "Granted. The desktop is captured on device and never stored."
                                     : "Needed to capture the desktop. Frames are processed on your Mac and never saved.")
                        Spacer()
                        if controller.hasScreenPermission {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                        } else {
                            Button("Open Settings") {
                                controller.requestPermission()
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                            }
                        }
                    }
                    Divider().padding(.vertical, 10)
                    HStack {
                        settingLabel("Lid sensor", controller.sensorAvailable
                                     ? "Found. Reading \(controller.lidAngle.map { "\(Int($0.rounded()))°" } ?? "…") from the hinge."
                                     : "Not found. This Mac may not expose its lid angle sensor; you can still drive the angle by hand in Appearance.")
                        Spacer()
                        Image(systemName: controller.sensorAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(controller.sensorAvailable ? .green : .orange).font(.title3)
                    }
                }
                .padding(8)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshPermission()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func settingLabel(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 15))
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - About

struct AboutPane: View {
    @ObservedObject var controller: OverlayController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Slant").font(.system(size: 22, weight: .semibold))
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                        .foregroundStyle(.secondary)
                }
            }
            Text("Your desktop bends as you close the lid. It tilts, blurs and settles as the lid comes down, then clears with a click when you open it again.")
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    aboutRow("Lid sensor", "Reads the hinge angle from the Mac's own sensor. No polling, no accessibility access.")
                    aboutRow("Live desktop", "Captures the screen and renders the tilt with Metal, so windows and wallpaper move together.")
                    aboutRow("Private by design", "Frames are processed on your Mac. Nothing is recorded, saved or uploaded.")
                    aboutRow("Pause", "Press Esc or click the bent desktop to clear it until the lid opens again.")
                }
                .padding(8)
            }
            Text("Requires an Apple silicon MacBook with a lid angle sensor and macOS 14 or later.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func aboutRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.system(size: 14, weight: .semibold)).frame(width: 120, alignment: .leading)
            Text(detail).font(.system(size: 14)).foregroundStyle(.secondary)
        }
    }
}
