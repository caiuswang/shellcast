import SwiftUI

struct TmuxBrowserView: View {
    let sessions: [TmuxSession]
    let onSelect: (TmuxSession?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !sessions.isEmpty {
                        // Terminal icon + title
                        HStack(spacing: 12) {
                            Image(systemName: "terminal")
                                .font(.title)
                                .foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text("Tmux Sessions")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s") found")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }
                        }

                        // Session list
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
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "terminal")
                                .font(.largeTitle)
                                .foregroundStyle(.gray)
                            Text("No tmux sessions found")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Start a new session or connect without tmux")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }

                    // New tmux session
                    Button {
                        onSelect(TmuxSession(name: "new", windowCount: 0, lastAttached: nil, attachedClients: 0))
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                            Text("New tmux session")
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(Color(white: 0.15))
                        .cornerRadius(12)
                    }

                    // Connect without tmux
                    Button {
                        onSelect(nil)
                    } label: {
                        Text("Connect without tmux")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(Color(white: 0.08))
                            .cornerRadius(12)
                    }
                }
                .padding(20)
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
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

                HStack(spacing: 8) {
                    Text("\(session.windowCount) windows")
                        .font(.caption)
                        .foregroundStyle(.gray)

                    if let lastAttached = session.lastAttached {
                        Text(lastAttached.relativeDescription)
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
            }

            Spacer()

            if session.attachedClients > 0 {
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
