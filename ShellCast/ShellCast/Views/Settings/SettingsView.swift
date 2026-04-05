import SwiftUI

struct SettingsView: View {
    @State private var settings = TerminalSettings.shared

    private var palette: AppThemePalette { settings.appPalette }

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
                    .background(palette.surfaceBackground)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(palette.border, lineWidth: 0.5)
                    )

                    // IMAGE PASTE section
                    sectionHeader("IMAGE PASTE", icon: "photo.on.rectangle.angled", color: .teal)

                    VStack(spacing: 0) {
                        imagePasteQualityRow
                    }
                    .background(palette.surfaceBackground)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(palette.border, lineWidth: 0.5)
                    )

                    // VOICE INPUT section
                    sectionHeader("VOICE INPUT", icon: "waveform", color: .orange)

                    VStack(spacing: 0) {
                        speechEngineRow
                        divider
                        whisperModelRow
                    }
                    .background(palette.surfaceBackground)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(palette.border, lineWidth: 0.5)
                    )

                    // DATA section
                    sectionHeader("DATA", icon: "externaldrive", color: .gray)

                    VStack(spacing: 0) {
                        historyLimitRow
                    }
                    .background(palette.surfaceBackground)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(palette.border, lineWidth: 0.5)
                    )

                    // Version footer
                    HStack {
                        Spacer()
                        Text("v1.0")
                            .font(.caption2)
                            .foregroundStyle(palette.tertiaryText.opacity(0.5))
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding()
                .iPadContentWidth(600)
            }
            .background(palette.screenBackground)
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
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - App Header

    private var appHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 38, height: 38)
                    .background(palette.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text("App appearance")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.primaryText)

                    Text("Current: \(settings.appTheme.rawValue)")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }

                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        appThemeHeaderChip(theme)
                    }
                }
                .padding(.horizontal, 1)
            }

            Text("Choose ShellCast's app color theme here. Terminal colors are configured separately below.")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 2)
        }
        .padding(16)
        .background(palette.elevatedSurfaceBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(palette.border, lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Rows

    private var themeRow: some View {
        NavigationLink {
            ThemePickerView(settings: settings)
        } label: {
            settingsRow(
                icon: "paintpalette.fill",
                iconColor: .purple,
                title: "Terminal Theme"
            ) {
                Text(settings.terminalTheme.rawValue)
                    .foregroundStyle(palette.secondaryText)
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
                    .foregroundStyle(palette.secondaryText)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(palette.tertiaryText)
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
                        .foregroundStyle(palette.primaryText)
                        .frame(width: 32, height: 32)
                }

                Text("\(settings.fontSize)pt")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(palette.primaryText)
                    .frame(width: 44)

                Button {
                    settings.fontSize += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(palette.primaryText)
                        .frame(width: 32, height: 32)
                }
            }
            .background(palette.controlBackground)
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
                            .foregroundStyle(settings.cursorMode == mode ? palette.primaryText : palette.secondaryText)
                            .frame(width: 32, height: 32)
                            .background(settings.cursorMode == mode ? palette.selectedControlBackground : Color.clear)
                            .cornerRadius(6)
                    }
                }
            }
            .background(palette.controlBackground)
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
                .tint(palette.accent)
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
                            .foregroundStyle(settings.scrollbackSize == size ? palette.primaryText : palette.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(settings.scrollbackSize == size ? palette.selectedControlBackground : Color.clear)
                            .cornerRadius(6)
                    }
                }
            }
            .background(palette.controlBackground)
            .cornerRadius(8)
        }
    }

    private var imagePasteQualityRow: some View {
        settingsRow(
            icon: "photo",
            iconColor: .teal,
            title: "Quality"
        ) {
            HStack(spacing: 2) {
                ForEach(ImagePasteQuality.allCases, id: \.self) { quality in
                    Button {
                        settings.imagePasteQuality = quality
                    } label: {
                        Text(quality.rawValue)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(settings.imagePasteQuality == quality ? palette.primaryText : palette.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(settings.imagePasteQuality == quality ? palette.selectedControlBackground : Color.clear)
                            .cornerRadius(6)
                    }
                }
            }
            .background(palette.controlBackground)
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
                            .foregroundStyle(settings.speechEngine == engine ? palette.primaryText : palette.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(settings.speechEngine == engine ? palette.selectedControlBackground : Color.clear)
                            .cornerRadius(6)
                    }
                }
            }
            .background(palette.controlBackground)
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
                .foregroundStyle(palette.secondaryText)
        }
        .opacity(settings.speechEngine == .whisper ? 1 : 0.4)
    }

    private var historyLimitRow: some View {
        settingsRow(
            icon: "clock.arrow.circlepath",
            iconColor: .gray,
            title: "History per Host"
        ) {
            HStack(spacing: 2) {
                ForEach(HistoryLimit.allCases, id: \.self) { limit in
                    Button {
                        settings.historyLimit = limit
                    } label: {
                        Text(limit.label)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(settings.historyLimit == limit ? palette.primaryText : palette.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(settings.historyLimit == limit ? palette.selectedControlBackground : Color.clear)
                            .cornerRadius(6)
                    }
                }
            }
            .background(palette.controlBackground)
            .cornerRadius(8)
        }
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
                .foregroundStyle(palette.primaryText)
                .frame(width: 28, height: 28)
                .background(iconColor.gradient)
                .cornerRadius(7)

            Text(title)
                .foregroundStyle(palette.primaryText)

            Spacer()

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.border)
            .frame(height: 0.5)
            .padding(.leading, 54)
    }

    private func headerBadge(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)

            Text(text)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(palette.primaryText.opacity(0.88))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(palette.controlBackground)
        .clipShape(Capsule())
    }

    private func appThemeHeaderChip(_ theme: AppTheme) -> some View {
        let isSelected = settings.appTheme == theme

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.appTheme = theme
            }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.previewColor)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.palette.accentForeground.opacity(0.75))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(isSelected ? "Active" : "Tap to apply")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? theme.previewColor.opacity(0.95) : palette.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.previewColor.opacity(0.95))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 170, height: 56, alignment: .leading)
            .background(isSelected ? palette.selectedControlBackground.opacity(0.9) : palette.controlBackground.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? theme.previewColor.opacity(0.95) : palette.border,
                        lineWidth: isSelected ? 1.2 : 0.8
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
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
    private var palette: AppThemePalette { settings.appPalette }

    var body: some View {
        List {
            ForEach(TerminalTheme.allCases, id: \.self) { theme in
                Button {
                    settings.terminalTheme = theme
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
                            .foregroundStyle(palette.primaryText)

                        Spacer()

                        if settings.terminalTheme == theme {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(palette.accent)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.screenBackground)
        .navigationTitle("Terminal Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Font Picker

struct FontPickerView: View {
    let settings: TerminalSettings
    private var palette: AppThemePalette { settings.appPalette }

    var body: some View {
        List {
            ForEach(TerminalFont.allCases, id: \.self) { font in
                Button {
                    settings.font = font
                } label: {
                    HStack(spacing: 14) {
                        Text("Aa")
                            .font(.system(.body, design: font == .system ? .monospaced : .monospaced))
                            .foregroundStyle(palette.accent)
                            .frame(width: 40)

                        Text(font.rawValue)
                            .foregroundStyle(palette.primaryText)

                        Spacer()

                        if settings.font == font {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(palette.accent)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.screenBackground)
        .navigationTitle("Fonts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
}
