import SwiftUI

struct ConnectionRow: View {
    let connection: Connection
    var onEdit: (() -> Void)?
    @State private var settings = TerminalSettings.shared

    private var palette: AppThemePalette { settings.appPalette }

    private var protocolLabel: String {
        switch connection.connectionType {
        case .ssh: return "SSH"
        case .mosh: return "MOSH"
        case .auto: return "AUTO"
        }
    }

    private var protocolColor: Color {
        switch connection.connectionType {
        case .ssh: return .green
        case .mosh: return .orange
        case .auto: return .cyan
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Icon with colored background
            Image(systemName: "server.rack")
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(palette.primaryText)
                .frame(width: 38, height: 38)
                .background(palette.accent.gradient)
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(connection.name.isEmpty ? connection.host : connection.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(palette.primaryText)

                    Text(protocolLabel)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(protocolColor.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(protocolColor.opacity(0.15))
                        .cornerRadius(4)
                }

                Text("\(connection.username)@\(connection.host):\(connection.port)")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer()

            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.callout)
                        .foregroundStyle(palette.tertiaryText)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(palette.tertiaryText.opacity(0.8))
        }
        .padding(14)
        .background(palette.surfaceBackground)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(palette.border, lineWidth: 0.5)
        )
    }
}
