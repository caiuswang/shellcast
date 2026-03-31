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

                if session.isActive {
                    HStack(spacing: 4) {
                        LiveDot()
                        Text("LIVE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.6))
                    .cornerRadius(4)
                    .padding(6)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(session.tmuxSessionName ?? "Shell")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                if let connectionName {
                    Text(connectionName)
                        .font(.caption2)
                        .foregroundStyle(.green.opacity(0.7))
                }

                Text((session.snapshotCapturedAt ?? session.lastActiveAt).relativeDescription)
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.6))
            }
        }
        .padding(10)
        .background(Color(white: 0.09))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(session.isActive ? .green.opacity(0.3) : Color.white.opacity(0.05), lineWidth: session.isActive ? 1 : 0.5)
        )
        .shadow(color: session.isActive ? .green.opacity(0.06) : .clear, radius: 12, y: 4)
    }
}

/// Separate view so UIImage decoding only happens when imageData actually changes.
private struct SnapshotThumbnail: View {
    let imageData: Data?
    var width: CGFloat = 180
    var height: CGFloat = 120

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(white: 0.07))
            .frame(width: width, height: height)
            .overlay {
                if let imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "terminal")
                        .font(.largeTitle)
                        .foregroundStyle(.green.opacity(0.3))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Isolated pulsing dot — animation stays contained, won't trigger parent re-renders.
private struct LiveDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 7, height: 7)
            .opacity(isPulsing ? 1.0 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
