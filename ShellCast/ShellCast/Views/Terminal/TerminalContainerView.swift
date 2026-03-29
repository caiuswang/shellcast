import SwiftUI

/// Container for the SwiftTerm TerminalView.
/// Once SwiftTerm SPM dependency is added in Xcode, this will use UIViewRepresentable
/// to wrap SwiftTerm's TerminalView with a custom keyboard toolbar.
struct TerminalContainerView: View {
    let transport: TransportSession

    @Environment(\.dismiss) private var dismiss
    @State private var showMenu = false

    var body: some View {
        ZStack {
            // Placeholder until SwiftTerm is integrated
            Color.black
                .ignoresSafeArea()

            VStack {
                Text("Terminal View")
                    .foregroundStyle(.green)
                    .font(.system(.body, design: .monospaced))

                Text("SwiftTerm will render here")
                    .foregroundStyle(.green.opacity(0.5))
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            Button {
                showMenu.toggle()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding()
        }
        .overlay(alignment: .topTrailing) {
            Button {
                Task { await transport.disconnect() }
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding()
        }
    }
}
