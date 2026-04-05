import Foundation
import SwiftUI
import UIKit

private extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

struct AppThemePalette {
    let accent: Color
    let accentForeground: Color
    let screenBackground: Color
    let surfaceBackground: Color
    let elevatedSurfaceBackground: Color
    let controlBackground: Color
    let selectedControlBackground: Color
    let border: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let overlayBackground: Color
}

extension AppThemePalette {
    var accentUIColor: UIColor { UIColor(accent) }
    var accentForegroundUIColor: UIColor { UIColor(accentForeground) }
    var surfaceBackgroundUIColor: UIColor { UIColor(surfaceBackground) }
    var elevatedSurfaceBackgroundUIColor: UIColor { UIColor(elevatedSurfaceBackground) }
    var controlBackgroundUIColor: UIColor { UIColor(controlBackground) }
    var selectedControlBackgroundUIColor: UIColor { UIColor(selectedControlBackground) }
    var borderUIColor: UIColor { UIColor(border) }
    var overlayBackgroundUIColor: UIColor { UIColor(overlayBackground) }
}

enum AppTheme: String, CaseIterable {
    case graphite = "Graphite"
    case emerald = "Emerald"
    case sapphire = "Sapphire"
    case amethyst = "Amethyst"
    case sunset = "Sunset"

    var previewColor: Color { palette.accent }

    var palette: AppThemePalette {
        switch self {
        case .emerald:
            AppThemePalette(
                accent: Color(hex: 0x38D27D),
                accentForeground: .black,
                screenBackground: Color(hex: 0x070B09),
                surfaceBackground: Color(hex: 0x0E1511),
                elevatedSurfaceBackground: Color(hex: 0x131C16),
                controlBackground: Color(hex: 0x1A251E),
                selectedControlBackground: Color(hex: 0x254432),
                border: Color.white.opacity(0.06),
                primaryText: .white,
                secondaryText: Color(hex: 0xB6C2BA),
                tertiaryText: Color(hex: 0x7F8B84),
                overlayBackground: Color.black.opacity(0.72)
            )
        case .sapphire:
            AppThemePalette(
                accent: Color(hex: 0x52A8FF),
                accentForeground: .white,
                screenBackground: Color(hex: 0x060A10),
                surfaceBackground: Color(hex: 0x0D1420),
                elevatedSurfaceBackground: Color(hex: 0x121B29),
                controlBackground: Color(hex: 0x182233),
                selectedControlBackground: Color(hex: 0x233A59),
                border: Color.white.opacity(0.06),
                primaryText: .white,
                secondaryText: Color(hex: 0xB1BED2),
                tertiaryText: Color(hex: 0x79879B),
                overlayBackground: Color.black.opacity(0.74)
            )
        case .amethyst:
            AppThemePalette(
                accent: Color(hex: 0xB181FF),
                accentForeground: .white,
                screenBackground: Color(hex: 0x0A0810),
                surfaceBackground: Color(hex: 0x141021),
                elevatedSurfaceBackground: Color(hex: 0x1B152B),
                controlBackground: Color(hex: 0x251D38),
                selectedControlBackground: Color(hex: 0x413064),
                border: Color.white.opacity(0.06),
                primaryText: .white,
                secondaryText: Color(hex: 0xC3BAD6),
                tertiaryText: Color(hex: 0x8A809B),
                overlayBackground: Color.black.opacity(0.76)
            )
        case .sunset:
            AppThemePalette(
                accent: Color(hex: 0xFF8A4C),
                accentForeground: .black,
                screenBackground: Color(hex: 0x100905),
                surfaceBackground: Color(hex: 0x1A110C),
                elevatedSurfaceBackground: Color(hex: 0x231813),
                controlBackground: Color(hex: 0x31211A),
                selectedControlBackground: Color(hex: 0x5B3727),
                border: Color.white.opacity(0.06),
                primaryText: .white,
                secondaryText: Color(hex: 0xD0B7A8),
                tertiaryText: Color(hex: 0x997B69),
                overlayBackground: Color.black.opacity(0.74)
            )
        case .graphite:
            AppThemePalette(
                accent: Color(hex: 0xA7B0BE),
                accentForeground: .black,
                screenBackground: Color(hex: 0x060708),
                surfaceBackground: Color(hex: 0x101214),
                elevatedSurfaceBackground: Color(hex: 0x16191C),
                controlBackground: Color(hex: 0x202429),
                selectedControlBackground: Color(hex: 0x343A42),
                border: Color.white.opacity(0.06),
                primaryText: .white,
                secondaryText: Color(hex: 0xC0C6CE),
                tertiaryText: Color(hex: 0x838A94),
                overlayBackground: Color.black.opacity(0.78)
            )
        }
    }
}

enum CursorMode: String, CaseIterable {
    case block
    case underline
    case bar
}

enum ScrollbackSize: Int, CaseIterable {
    case k1 = 1000
    case k5 = 5000
    case k10 = 10000
    case k50 = 50000

    var label: String {
        switch self {
        case .k1: "1K"
        case .k5: "5K"
        case .k10: "10K"
        case .k50: "50K"
        }
    }
}

enum TerminalTheme: String, CaseIterable {
    case `default` = "Default"
    case solarizedDark = "Solarized Dark"
    case monokai = "Monokai"
    case dracula = "Dracula"
    case nord = "Nord"

    var previewColor: Color {
        switch self {
        case .default: Color(red: 1.0, green: 0.3, blue: 0.2)
        case .solarizedDark: Color(red: 0.0, green: 0.17, blue: 0.21)
        case .monokai: Color(red: 0.15, green: 0.16, blue: 0.13)
        case .dracula: Color(red: 0.16, green: 0.16, blue: 0.21)
        case .nord: Color(red: 0.18, green: 0.20, blue: 0.25)
        }
    }

    var backgroundColor: UIColor {
        switch self {
        case .default: UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
        case .solarizedDark: UIColor(red: 0.0, green: 0.17, blue: 0.21, alpha: 1)
        case .monokai: UIColor(red: 0.15, green: 0.16, blue: 0.13, alpha: 1)
        case .dracula: UIColor(red: 0.16, green: 0.16, blue: 0.21, alpha: 1)
        case .nord: UIColor(red: 0.18, green: 0.20, blue: 0.25, alpha: 1)
        }
    }

    var foregroundColor: UIColor {
        switch self {
        case .default: UIColor(red: 0.9, green: 0.95, blue: 0.9, alpha: 1)
        case .solarizedDark: UIColor(red: 0.51, green: 0.58, blue: 0.59, alpha: 1)
        case .monokai: UIColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1)
        case .dracula: UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
        case .nord: UIColor(red: 0.85, green: 0.87, blue: 0.91, alpha: 1)
        }
    }

    var caretColor: UIColor {
        switch self {
        case .default: .green
        case .solarizedDark: UIColor(red: 0.58, green: 0.63, blue: 0.0, alpha: 1)
        case .monokai: UIColor(red: 0.66, green: 0.88, blue: 0.07, alpha: 1)
        case .dracula: UIColor(red: 0.94, green: 0.47, blue: 0.68, alpha: 1)
        case .nord: UIColor(red: 0.53, green: 0.75, blue: 0.82, alpha: 1)
        }
    }
}

enum TerminalFont: String, CaseIterable {
    case system = "System Mono"
    case jetBrainsMono = "JetBrains Mono"
    case sfMono = "SF Mono"
    case menlo = "Menlo"
    case courier = "Courier"

    func uiFont(size: CGFloat) -> UIFont {
        switch self {
        case .system:
            return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .jetBrainsMono:
            return UIFont(name: "JetBrainsMonoNF-Regular", size: size)
                ?? UIFont(name: "JetBrainsMono-Regular", size: size)
                ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .sfMono:
            return UIFont(name: "SFMono-Regular", size: size)
                ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .menlo:
            return UIFont(name: "Menlo-Regular", size: size)
                ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .courier:
            return UIFont(name: "Courier", size: size)
                ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }
}

enum ImagePasteQuality: String, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var maxDimension: CGFloat {
        switch self {
        case .low: 800
        case .medium: 1600
        case .high: 2048
        }
    }

    var maxBytes: Int {
        switch self {
        case .low: 300_000
        case .medium: 1_000_000
        case .high: 2_000_000
        }
    }

    var description: String {
        switch self {
        case .low: "Save data (~100KB)"
        case .medium: "Balanced (~500KB)"
        case .high: "Best quality (~2MB)"
        }
    }
}

enum SpeechEngine: String, CaseIterable {
    case apple = "apple"
    case whisper = "whisper"

    var displayName: String {
        switch self {
        case .apple: "Apple Speech"
        case .whisper: "WhisperKit"
        }
    }

    var description: String {
        switch self {
        case .apple: "Built-in, requires network"
        case .whisper: "Local AI model, fully offline"
        }
    }
}

enum WhisperModel: String, CaseIterable {
    case base = "openai_whisper-base"

    var displayName: String {
        switch self {
        case .base: "Base"
        }
    }

    var sizeLabel: String {
        switch self {
        case .base: "~140 MB"
        }
    }

    var description: String {
        switch self {
        case .base: "Good balance of speed and accuracy"
        }
    }

    /// The variant name used by WhisperKit for downloading from HuggingFace
    var whisperKitVariant: String {
        switch self {
        case .base: "base"
        }
    }

    /// Check if this model is bundled with the app
    var isBundled: Bool {
        Bundle.main.path(forResource: rawValue, ofType: nil, inDirectory: "WhisperModels") != nil
    }
}

enum HistoryLimit: Int, CaseIterable {
    case h5 = 5
    case h10 = 10
    case h20 = 20

    var label: String {
        switch self {
        case .h5: "5"
        case .h10: "10"
        case .h20: "20"
        }
    }
}

@Observable
final class TerminalSettings {
    static let shared = TerminalSettings()

    var appTheme: AppTheme {
        didSet { UserDefaults.standard.set(appTheme.rawValue, forKey: "app_theme") }
    }

    var terminalTheme: TerminalTheme {
        didSet { UserDefaults.standard.set(terminalTheme.rawValue, forKey: "terminal_theme") }
    }

    var font: TerminalFont {
        didSet { UserDefaults.standard.set(font.rawValue, forKey: "terminal_font") }
    }

    var fontSize: Int {
        didSet {
            let clamped = max(8, min(32, fontSize))
            if fontSize != clamped { fontSize = clamped }
            UserDefaults.standard.set(clamped, forKey: "terminal_font_size")
        }
    }

    var cursorMode: CursorMode {
        didSet { UserDefaults.standard.set(cursorMode.rawValue, forKey: "terminal_cursor_mode") }
    }

    var cursorBlink: Bool {
        didSet { UserDefaults.standard.set(cursorBlink, forKey: "terminal_cursor_blink") }
    }

    var scrollbackSize: ScrollbackSize {
        didSet { UserDefaults.standard.set(scrollbackSize.rawValue, forKey: "terminal_scrollback") }
    }

    var speechEngine: SpeechEngine {
        didSet { UserDefaults.standard.set(speechEngine.rawValue, forKey: "speech_engine") }
    }

    var whisperModel: WhisperModel {
        didSet { UserDefaults.standard.set(whisperModel.rawValue, forKey: "whisper_model") }
    }

    var imagePasteQuality: ImagePasteQuality {
        didSet { UserDefaults.standard.set(imagePasteQuality.rawValue, forKey: "image_paste_quality") }
    }

    var historyLimit: HistoryLimit {
        didSet { UserDefaults.standard.set(historyLimit.rawValue, forKey: "history_limit") }
    }

    var appPalette: AppThemePalette { appTheme.palette }

    private init() {
        let ud = UserDefaults.standard
        self.appTheme = AppTheme(rawValue: ud.string(forKey: "app_theme") ?? "") ?? .graphite
        self.terminalTheme = TerminalTheme(rawValue: ud.string(forKey: "terminal_theme") ?? "") ?? .default
        self.font = TerminalFont(rawValue: ud.string(forKey: "terminal_font") ?? "") ?? .jetBrainsMono
        let storedSize = ud.integer(forKey: "terminal_font_size")
        self.fontSize = storedSize == 0 ? 14 : storedSize
        self.cursorMode = CursorMode(rawValue: ud.string(forKey: "terminal_cursor_mode") ?? "") ?? .block
        self.cursorBlink = ud.object(forKey: "terminal_cursor_blink") == nil ? true : ud.bool(forKey: "terminal_cursor_blink")
        self.scrollbackSize = ScrollbackSize(rawValue: ud.integer(forKey: "terminal_scrollback")) ?? .k10
        self.speechEngine = SpeechEngine(rawValue: ud.string(forKey: "speech_engine") ?? "") ?? .apple
        self.whisperModel = WhisperModel(rawValue: ud.string(forKey: "whisper_model") ?? "") ?? .base
        self.imagePasteQuality = ImagePasteQuality(rawValue: ud.string(forKey: "image_paste_quality") ?? "") ?? .high
        let storedLimit = ud.object(forKey: "history_limit") == nil ? -1 : ud.integer(forKey: "history_limit")
        self.historyLimit = storedLimit == -1 ? .h10 : (HistoryLimit(rawValue: storedLimit) ?? .h10)
    }
}
