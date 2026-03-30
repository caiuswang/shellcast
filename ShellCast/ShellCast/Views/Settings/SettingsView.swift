import SwiftUI

struct SettingsView: View {
    @State private var settings = TerminalSettings.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Terminal preview
                    terminalPreview

                    // TERMINAL section
                    Text("TERMINAL")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.gray)
                        .padding(.horizontal, 4)

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
                    .background(Color(white: 0.1))
                    .cornerRadius(12)

                    // VOICE INPUT section
                    Text("VOICE INPUT")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.gray)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        speechEngineRow
                        divider
                        whisperModelRow
                    }
                    .background(Color(white: 0.1))
                    .cornerRadius(12)
                }
                .padding()
                .iPadContentWidth(600)
            }
            .background(Color.black)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Terminal Preview

    private var terminalPreview: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(settings.theme.previewColor)
            .frame(height: 140)
            .overlay {
                VStack(alignment: .leading, spacing: 4) {
                    Text("$ echo \"Hello, ShellCast\"")
                    Text("Hello, ShellCast")
                        .foregroundStyle(.white.opacity(0.7))
                    Text("$ _")
                }
                .font(.system(size: CGFloat(settings.fontSize), design: .monospaced))
                .foregroundStyle(.white)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
    }

    // MARK: - Rows

    private var themeRow: some View {
        NavigationLink {
            ThemePickerView(settings: settings)
        } label: {
            settingsRow(
                icon: "paintpalette",
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
                title: "Fonts"
            ) {
                Text(settings.font.rawValue)
                    .foregroundStyle(.gray)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
    }

    private var fontSizeRow: some View {
        settingsRow(
            icon: "textformat.size",
            title: "Font Size"
        ) {
            HStack(spacing: 0) {
                Button {
                    settings.fontSize -= 1
                } label: {
                    Image(systemName: "minus")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }

                Text("\(settings.fontSize)pt")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 44)

                Button {
                    settings.fontSize += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
            }
            .background(Color(white: 0.2))
            .cornerRadius(8)
        }
    }

    private var cursorModeRow: some View {
        settingsRow(
            icon: "character.cursor.ibeam",
            title: "Cursor Mode"
        ) {
            HStack(spacing: 2) {
                ForEach(CursorMode.allCases, id: \.self) { mode in
                    Button {
                        settings.cursorMode = mode
                    } label: {
                        cursorIcon(for: mode)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(settings.cursorMode == mode ? .white : .gray)
                            .frame(width: 36, height: 36)
                            .background(settings.cursorMode == mode ? Color(white: 0.3) : Color.clear)
                            .cornerRadius(6)
                    }
                }
            }
            .background(Color(white: 0.2))
            .cornerRadius(8)
        }
    }

    private var cursorBlinkRow: some View {
        settingsRow(
            icon: "sparkles",
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
            title: "Scrollback"
        ) {
            HStack(spacing: 2) {
                ForEach(ScrollbackSize.allCases, id: \.self) { size in
                    Button {
                        settings.scrollbackSize = size
                    } label: {
                        Text(size.label)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(settings.scrollbackSize == size ? .white : .gray)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(settings.scrollbackSize == size ? Color(white: 0.3) : Color.clear)
                            .cornerRadius(6)
                    }
                }
            }
            .background(Color(white: 0.2))
            .cornerRadius(8)
        }
    }

    private var speechEngineRow: some View {
        settingsRow(
            icon: "waveform",
            title: "Engine"
        ) {
            HStack(spacing: 2) {
                ForEach(SpeechEngine.allCases, id: \.self) { engine in
                    Button {
                        settings.speechEngine = engine
                    } label: {
                        Text(engine.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(settings.speechEngine == engine ? .white : .gray)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(settings.speechEngine == engine ? Color(white: 0.3) : Color.clear)
                            .cornerRadius(6)
                    }
                }
            }
            .background(Color(white: 0.2))
            .cornerRadius(8)
        }
    }

    private var whisperModelRow: some View {
        settingsRow(
            icon: "mic",
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
        title: String,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.gray)
                .frame(width: 28)

            Text(title)
                .foregroundStyle(.white)

            Spacer()

            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(white: 0.18))
            .frame(height: 0.5)
            .padding(.leading, 56)
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
                    HStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.previewColor)
                            .frame(width: 40, height: 28)

                        Text(theme.rawValue)
                            .foregroundStyle(.white)

                        Spacer()

                        if settings.theme == theme {
                            Image(systemName: "checkmark")
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
                    HStack {
                        Text("Aa")
                            .font(.system(.body, design: font == .system ? .monospaced : .monospaced))
                            .foregroundStyle(.white)
                            .frame(width: 40)

                        Text(font.rawValue)
                            .foregroundStyle(.white)

                        Spacer()

                        if settings.font == font {
                            Image(systemName: "checkmark")
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
