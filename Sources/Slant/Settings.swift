import Foundation
import Combine

enum Style: String, CaseIterable, Identifiable {
    case silk, shade, frost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .silk: return "Silk"
        case .shade: return "Shade"
        case .frost: return "Frost"
        }
    }

    /// Slider positions the style starts from. Sliders stay editable afterwards.
    var perspective: Double { self == .frost ? 0.85 : 1.0 }
    var blur: Double {
        switch self {
        case .silk: return 0.65
        case .shade: return 0.40
        case .frost: return 1.0
        }
    }
    var shadow: Double {
        switch self {
        case .silk: return 0.55
        case .shade: return 1.0
        case .frost: return 0.20
        }
    }
    /// White veil that builds toward the top of the screen; only Frost uses it.
    var frost: Double { self == .frost ? 1.0 : 0.0 }
}

/// Angle below which the display is considered closed. The panel is dark by then.
let closedAngle: Double = 15

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var followLid: Bool { didSet { defaults.set(followLid, forKey: "followLid") } }
    @Published var manualAngle: Double { didSet { defaults.set(manualAngle, forKey: "manualAngle") } }
    @Published var style: Style { didSet { defaults.set(style.rawValue, forKey: "style") } }
    @Published var perspective: Double { didSet { defaults.set(perspective, forKey: "perspective") } }
    @Published var blur: Double { didSet { defaults.set(blur, forKey: "blur") } }
    @Published var shadow: Double { didSet { defaults.set(shadow, forKey: "shadow") } }
    @Published var clearAngle: Double { didSet { defaults.set(clearAngle, forKey: "clearAngle") } }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: "soundEnabled") } }
    @Published var showAngleInMenuBar: Bool { didSet { defaults.set(showAngleInMenuBar, forKey: "showAngleInMenuBar") } }

    private init() {
        defaults.register(defaults: [
            "followLid": true,
            "manualAngle": 135.0,
            "style": Style.silk.rawValue,
            "perspective": Style.silk.perspective,
            "blur": Style.silk.blur,
            "shadow": Style.silk.shadow,
            "clearAngle": 115.0,
            "soundEnabled": true,
            "showAngleInMenuBar": false,
        ])
        followLid = defaults.bool(forKey: "followLid")
        manualAngle = defaults.double(forKey: "manualAngle")
        style = Style(rawValue: defaults.string(forKey: "style") ?? "") ?? .silk
        perspective = defaults.double(forKey: "perspective")
        blur = defaults.double(forKey: "blur")
        shadow = defaults.double(forKey: "shadow")
        clearAngle = defaults.double(forKey: "clearAngle")
        soundEnabled = defaults.bool(forKey: "soundEnabled")
        showAngleInMenuBar = defaults.bool(forKey: "showAngleInMenuBar")
    }

    func apply(_ newStyle: Style) {
        style = newStyle
        perspective = newStyle.perspective
        blur = newStyle.blur
        shadow = newStyle.shadow
    }

    /// 0 when the lid is at or past the clear angle, 1 when it is closed. Eased so the
    /// bend starts and finishes gently instead of snapping.
    func progress(forAngle angle: Double) -> Double {
        let span = max(clearAngle - closedAngle, 1)
        let t = min(max((clearAngle - angle) / span, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
