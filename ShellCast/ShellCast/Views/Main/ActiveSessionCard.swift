import SwiftUI
import SwiftData

struct ActiveSessionCard: View {
    let session: SessionRecord
    var connectionName: String?

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var settings = TerminalSettings.shared

    private var palette: AppThemePalette { settings.appPalette }

    private var thumbWidth: CGFloat { sizeClass == .regular ? 240 : 180 }
    private var thumbHeight: CGFloat { sizeClass == .regular ? 160 : 120 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Terminal preview with live indicator
            ZStack(alignment: .topTrailing) {
                SnapshotThumbnail(imageData: session.snapshotImageData, width: thumbWidth, height: thumbHeight)

                if session.isActive {
                    HStack(spacing: 4) {
                        LiveDot()
                        Text("LIVE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.accent)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(palette.overlayBackground)
                    .cornerRadius(4)
                    .padding(6)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if session.aiToolType == "claude" {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundStyle(.purple)
                    }
                    Text(session.aiToolType == "claude" ? "Claude Code" : (session.tmuxSessionName ?? "Shell"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.primaryText)
                }

                if let connectionName {
                    Text(connectionName)
                        .font(.caption2)
                        .foregroundStyle(palette.accent.opacity(0.8))
                }

                Text((session.snapshotCapturedAt ?? session.lastActiveAt).relativeDescription)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(10)
        .background(palette.elevatedSurfaceBackground)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(session.isActive ? palette.accent.opacity(0.35) : palette.border, lineWidth: session.isActive ? 1 : 0.5)
        )
        .shadow(color: session.isActive ? palette.accent.opacity(0.08) : .clear, radius: 12, y: 4)
    }
}

/// Separate view so UIImage decoding only happens when imageData actually changes.
private struct SnapshotThumbnail: View {
    let imageData: Data?
    var width: CGFloat = 180
    var height: CGFloat = 120
    @State private var settings = TerminalSettings.shared

    private var palette: AppThemePalette { settings.appPalette }

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(palette.surfaceBackground)
            .frame(width: width, height: height)
            .overlay {
                if let imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "terminal")
                        .font(.largeTitle)
                        .foregroundStyle(palette.accent.opacity(0.3))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Isolated pulsing dot — animation stays contained, won't trigger parent re-renders.
private struct LiveDot: View {
    @State private var isPulsing = false
    @State private var settings = TerminalSettings.shared

    private var palette: AppThemePalette { settings.appPalette }

    var body: some View {
        Circle()
            .fill(palette.accent)
            .frame(width: 7, height: 7)
            .opacity(isPulsing ? 1.0 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
