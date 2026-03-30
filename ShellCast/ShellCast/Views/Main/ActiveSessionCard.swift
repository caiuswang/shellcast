import SwiftUI
import SwiftData

struct ActiveSessionCard: View {
    let session: SessionRecord
    var connectionName: String?

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var thumbWidth: CGFloat { sizeClass == .regular ? 240 : 180 }
    private var thumbHeight: CGFloat { sizeClass == .regular ? 160 : 120 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Terminal preview with live indicator
            ZStack(alignment: .topTrailing) {
                SnapshotThumbnail(imageData: session.snapshotImageData, width: thumbWidth, height: thumbHeight)

                // Live dot — isolated so its animation doesn't re-render the thumbnail
                if session.isActive {
                    LiveDot()
                        .padding(6)
                }
            }

            Text(session.tmuxSessionName ?? "Shell")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)

            if let connectionName {
                Text(connectionName)
                    .font(.caption2)
                    .foregroundStyle(.green.opacity(0.7))
            }

            Text((session.snapshotCapturedAt ?? session.lastActiveAt).relativeDescription)
                .font(.caption2)
                .foregroundStyle(.gray)
        }
        .padding(8)
        .background(Color(white: 0.08))
        .cornerRadius(12)
        .overlay(content: {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.green.opacity(session.isActive ? 0.25 : 0), lineWidth: 1)
        })
    }
}

/// Separate view so UIImage decoding only happens when imageData actually changes.
private struct SnapshotThumbnail: View {
    let imageData: Data?
    var width: CGFloat = 180
    var height: CGFloat = 120

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(white: 0.1))
            .frame(width: width, height: height)
            .overlay {
                if let imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "terminal")
                        .font(.largeTitle)
                        .foregroundStyle(.green.opacity(0.5))
                }
            }
            .clipped()
    }
}

/// Isolated pulsing dot — animation stays contained, won't trigger parent re-renders.
private struct LiveDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 8, height: 8)
            .opacity(isPulsing ? 0.9 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
