import SwiftUI

struct TmuxBrowserView: View {
    let sessions: [TmuxSession]
    let onSelect: (TmuxSession?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tmux Sessions")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                ForEach(sessions) { session in
                    Button {
                        onSelect(session)
                    } label: {
                        TmuxSessionRow(session: session)
                    }

                    if session.id != sessions.last?.id {
                        Divider()
                            .background(Color(white: 0.2))
                    }
                }
            }
            .background(Color(white: 0.1))
            .cornerRadius(12)

            Button {
                onSelect(nil)
            } label: {
                Text("Connect without tmux")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(Color(white: 0.15))
                    .cornerRadius(12)
            }
        }
        .padding(20)
        .background(Color.black)
    }
}

struct TmuxSessionRow: View {
    let session: TmuxSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)

                    if session.isInUse {
                        if session.attachedClients > 0 {
                            Text("Connected")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text("\(session.windowCount) windows")
                        .font(.caption)
                        .foregroundStyle(.gray)

                    if let lastAttached = session.lastAttached {
                        Text("  \(lastAttached.relativeDescription)")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
            }

            Spacer()

            if session.isInUse && session.attachedClients > 0 {
                Circle()
                    .fill(.yellow)
                    .frame(width: 8, height: 8)
                Text("in use")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
        .padding(16)
    }
}
