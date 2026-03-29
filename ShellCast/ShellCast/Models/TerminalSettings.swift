import Foundation
import SwiftUI
import UIKit

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

@Observable
final class TerminalSettings {
    static let shared = TerminalSettings()

    var theme: TerminalTheme {
        get { TerminalTheme(rawValue: UserDefaults.standard.string(forKey: "terminal_theme") ?? "Default") ?? .default }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "terminal_theme") }
    }

    var font: TerminalFont {
        get { TerminalFont(rawValue: UserDefaults.standard.string(forKey: "terminal_font") ?? "JetBrains Mono") ?? .jetBrainsMono }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "terminal_font") }
    }

    var fontSize: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: "terminal_font_size")
            return stored == 0 ? 14 : stored
        }
        set { UserDefaults.standard.set(max(8, min(32, newValue)), forKey: "terminal_font_size") }
    }

    var cursorMode: CursorMode {
        get { CursorMode(rawValue: UserDefaults.standard.string(forKey: "terminal_cursor_mode") ?? "block") ?? .block }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "terminal_cursor_mode") }
    }

    var cursorBlink: Bool {
        get {
            if UserDefaults.standard.object(forKey: "terminal_cursor_blink") == nil { return true }
            return UserDefaults.standard.bool(forKey: "terminal_cursor_blink")
        }
        set { UserDefaults.standard.set(newValue, forKey: "terminal_cursor_blink") }
    }

    var scrollbackSize: ScrollbackSize {
        get { ScrollbackSize(rawValue: UserDefaults.standard.integer(forKey: "terminal_scrollback")) ?? .k10 }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "terminal_scrollback") }
    }

    private init() {}
}
