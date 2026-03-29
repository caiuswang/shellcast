import SwiftUI

struct ConnectionRow: View {
    let connection: Connection
    var onEdit: (() -> Void)?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(.gray)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(connection.name.isEmpty ? connection.host : connection.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)

                Text("\(connection.username)@\(connection.host):\(connection.port)")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            Spacer()

            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.body)
                        .foregroundStyle(.gray)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .padding(16)
        .background(Color(white: 0.1))
        .cornerRadius(12)
    }
}
