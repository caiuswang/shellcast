import SwiftUI
import SwiftData

struct ActiveSessionCard: View {
    let session: SessionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Terminal preview placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.1))
                .frame(width: 180, height: 120)
                .overlay {
                    if let imageData = session.snapshotImageData,
                       let uiImage = UIImage(data: imageData) {
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

            Text(session.tmuxSessionName ?? "Shell")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)

            Text(session.lastActiveAt.relativeDescription)
                .font(.caption2)
                .foregroundStyle(.gray)
        }
        .padding(8)
        .background(Color(white: 0.08))
        .cornerRadius(12)
    }
}
