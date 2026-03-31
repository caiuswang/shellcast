import SwiftUI

struct SettingsView: View {
    @State private var settings = TerminalSettings.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // App header
                    appHeader

                    // TERMINAL section
                    sectionHeader("TERMINAL", icon: "terminal", color: .green)

                    VStack(spacing: 0) {
                        themeRow
                        divider
                        fontRow
                        divider
                        fontSizeRow
                        divider
                        cursorModeRow
                        divider
                        cursorBlinkRow
                        divider
                        scrollbackRow
                    }
                    .background(Color(white: 0.11))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )

                    // VOICE INPUT section
                    sectionHeader("VOICE INPUT", icon: "waveform", color: .orange)

                    VStack(spacing: 0) {
                        speechEngineRow
                        divider
                        whisperModelRow
                    }
                    .background(Color(white: 0.11))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )

                    // Version footer
                    HStack {
                        Spacer()
                        Text("v1.0")
                            .font(.caption2)
                            .foregroundStyle(.gray.opacity(0.25))
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding()
                .iPadContentWidth(600)
            }
            .background(Color(white: 0.04))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.gray.opacity(0.7))
        }
        .padding(.horizontal, 4)
    }

    // MARK: - App Header

    private var appHeader: some View {
        VStack(spacing: 16) {
            // App icon
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.1, blue: 0.1),
                                Color(red: 0.05, green: 0.05, blue: 0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 72, height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )

                Text(">_")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 4) {
                Text("ShellCast")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("SSH & Mosh Terminal")
                    .font(.caption)
                    .foregroundStyle(.gray.opacity(0.6))
            }

            // Theme color strip — shows all themes, highlights current
            HStack(spacing: 6) {
                ForEach(TerminalTheme.allCases, id: \.self) { theme in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.previewColor)
                        .frame(height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    settings.theme == theme ? .green : Color.white.opacity(0.08),
                                    lineWidth: settings.theme == theme ? 1.5 : 0.5
                                )
                        )
                        .onTapGesture {
                            settings.theme = theme
                        }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Rows

    private var themeRow: some View {
        NavigationLink {
            ThemePickerView(settings: settings)
        } label: {
            settingsRow(
                icon: "paintpalette.fill",
                iconColor: .purple,
                title: "Theme"
            ) {
                Text(settings.theme.rawValue)
                    .foregroundStyle(.gray)
            }
        }
    }

    private var fontRow: some View {
        NavigationLink {
            FontPickerView(settings: settings)
        } label: {
            settingsRow(
                icon: "textformat",
                iconColor: .blue,
                title: "Fonts"
            ) {
                Text(settings.font.rawValue)
                    .foregroundStyle(.gray)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.5))
            }
        }
    }

    private var fontSizeRow: some View {
        settingsRow(
            icon: "textformat.size",
            iconColor: .blue,
            title: "Font Size"
        ) {
            HStack(spacing: 0) {
                Button {
                    settings.fontSize -= 1
                } label: {
                    Image(systemName: "minus")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                }

                Text("\(settings.fontSize)pt")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 44)

                Button {
                    settings.fontSize += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                }
            }
            .background(Color(white: 0.18))
            .cornerRadius(8)
        }
    }

    private var cursorModeRow: some View {
        settingsRow(
            icon: "character.cursor.ibeam",
            iconColor: .cyan,
            title: "Cursor"
        ) {
            HStack(spacing: 2) {
                ForEach(CursorMode.allCases, id: \.self) { mode in
                    Button {
                        settings.cursorMode = mode
                    } label: {
                        cursorIcon(for: mode)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(settings.cursorMode == mode ? .white : .gray.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(settings.cursorMode == mode ? Color(white: 0.28) : Color.clear)
                            .cornerRadius(6)
                    }
                }
            }
            .background(Color(white: 0.18))
            .cornerRadius(8)
        }
    }

    private var cursorBlinkRow: some View {
        settingsRow(
            icon: "sparkles",
            iconColor: .yellow,
            title: "Cursor Blink"
        ) {
            Toggle("", isOn: $settings.cursorBlink)
                .tint(.green)
                .labelsHidden()
        }
    }

    private var scrollbackRow: some View {
        settingsRow(
            icon: "clock.arrow.circlepath",
            iconColor: .mint,
            title: "Scrollback"
        ) {
            HStack(spacing: 2) {
                ForEach(ScrollbackSize.allCases, id: \.self) { size in
                    Button {
                        settings.scrollbackSize = size
                    } label: {
                        Text(size.label)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(settings.scrollbackSize == size ? .white : .gray.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(settings.scrollbackSize == size ? Color(white: 0.28) : Color.clear)
                            .cornerRadius(6)
                    }
                }
            }
            .background(Color(white: 0.18))
            .cornerRadius(8)
        }
    }

    private var speechEngineRow: some View {
        settingsRow(
            icon: "waveform",
            iconColor: .orange,
            title: "Engine"
        ) {
            HStack(spacing: 2) {
                ForEach(SpeechEngine.allCases, id: \.self) { engine in
                    Button {
                        settings.speechEngine = engine
                    } label: {
                        Text(engine.displayName)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(settings.speechEngine == engine ? .white : .gray.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(settings.speechEngine == engine ? Color(white: 0.28) : Color.clear)
                            .cornerRadius(6)
                    }
                }
            }
            .background(Color(white: 0.18))
            .cornerRadius(8)
        }
    }

    private var whisperModelRow: some View {
        settingsRow(
            icon: "mic.fill",
            iconColor: .red,
            title: "Model"
        ) {
            Text("\(settings.whisperModel.displayName) · \(settings.whisperModel.sizeLabel)")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .opacity(settings.speechEngine == .whisper ? 1 : 0.4)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingsRow(
        icon: String,
        iconColor: Color,
        title: String,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(iconColor.gradient)
                .cornerRadius(7)

            Text(title)
                .foregroundStyle(.white)

            Spacer()

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 54)
    }

    @ViewBuilder
    private func cursorIcon(for mode: CursorMode) -> some View {
        switch mode {
        case .block:
            Image(systemName: "rectangle.fill")
                .font(.caption)
        case .underline:
            Text("_")
        case .bar:
            Text("|")
        }
    }
}

// MARK: - Theme Picker

struct ThemePickerView: View {
    let settings: TerminalSettings

    var body: some View {
        List {
            ForEach(TerminalTheme.allCases, id: \.self) { theme in
                Button {
                    settings.theme = theme
                } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.previewColor)
                            .frame(width: 40, height: 28)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                            )

                        Text(theme.rawValue)
                            .foregroundStyle(.white)

                        Spacer()

                        if settings.theme == theme {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Font Picker

struct FontPickerView: View {
    let settings: TerminalSettings

    var body: some View {
        List {
            ForEach(TerminalFont.allCases, id: \.self) { font in
                Button {
                    settings.font = font
                } label: {
                    HStack(spacing: 14) {
                        Text("Aa")
                            .font(.system(.body, design: font == .system ? .monospaced : .monospaced))
                            .foregroundStyle(.green)
                            .frame(width: 40)

                        Text(font.rawValue)
                            .foregroundStyle(.white)

                        Spacer()

                        if settings.font == font {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
        .navigationTitle("Fonts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
}
