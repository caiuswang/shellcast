import SwiftUI

/// Custom keyboard accessory toolbar for terminal special keys.
/// Layout: Ctrl Alt | Esc Tab | ↑ ↓ → ← | | / \ ~ - _ |
///
/// This will be set as the inputAccessoryView of SwiftTerm's TerminalView.
/// For now, this is a SwiftUI representation of the toolbar design.

struct KeyboardToolbarKey: Identifiable {
    let id = UUID()
    let label: String
    let action: () -> Void
}

struct KeyboardToolbar: View {
    let onKey: (String) -> Void

    private var keyGroups: [[String]] {
        [
            ["Ctrl", "Alt"],
            ["Esc", "Tab"],
            ["\u{2191}", "\u{2193}", "\u{2192}", "\u{2190}"],  // ↑ ↓ → ←
            ["|", "/", "\\", "~", "-", "_"],
            ["\u{22EF}"]  // ⋯ (more)
        ]
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(keyGroups.enumerated()), id: \.offset) { groupIndex, group in
                    HStack(spacing: 3) {
                        ForEach(group, id: \.self) { key in
                            Button {
                                onKey(key)
                            } label: {
                                Text(key)
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color(white: 0.2))
                                    .cornerRadius(6)
                            }
                        }
                    }

                    if groupIndex < keyGroups.count - 1 {
                        Divider()
                            .frame(height: 20)
                            .background(Color(white: 0.3))
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Color(white: 0.1))
    }
}

#Preview {
    VStack {
        Spacer()
        KeyboardToolbar { key in
            print("Key: \(key)")
        }
    }
    .background(Color.black)
}
