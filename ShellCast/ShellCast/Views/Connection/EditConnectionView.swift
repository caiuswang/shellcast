import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct EditConnectionView: View {
    private enum Field: Hashable {
        case name
        case host
        case port
        case username
        case password
        case keyPassphrase
    }

    enum Mode {
        case add
        case edit(Connection)
    }

    let mode: Mode
    var onConnect: ((Connection) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = "22"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var authMethod: AuthMethod = .password
    @State private var connectionType: ConnectionType = .ssh
    @State private var keyFileName: String?
    @State private var keyFileData: Data?
    @State private var showKeyFilePicker = false
    @State private var keyPassphrase: String = ""
    @State private var validationError: String?
    @State private var settings = TerminalSettings.shared
    @FocusState private var focusedField: Field?

    init(mode: Mode, onConnect: ((Connection) -> Void)? = nil) {
        self.mode = mode
        self.onConnect = onConnect
    }

    private var portNumber: Int? { Int(port) }
    private var isPortValid: Bool { portNumber.map { (1...65535).contains($0) } ?? false }
    private var isHostValid: Bool {
        !host.isEmpty && !host.contains(" ") && !host.contains("\\")
    }
    private var canSave: Bool { isHostValid && !username.isEmpty && (port.isEmpty || isPortValid) }
    private var palette: AppThemePalette { settings.appPalette }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // SERVER section
                    sectionCard {
                        sectionHeader("SERVER", icon: "server.rack", color: .green)

                        VStack(spacing: 14) {
                            fieldRow(icon: "tag", title: "Name") {
                                TextField("My Server", text: $name)
                                    .textFieldStyle(DarkFieldStyle(palette: palette))
                                    .focused($focusedField, equals: .name)
                            }

                            HStack(spacing: 12) {
                            fieldRow(icon: "globe", title: "Host") {
                                TextField("hostname or IP", text: $host)
                                    .textFieldStyle(DarkFieldStyle(palette: palette))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .host)
                                    .accessibilityIdentifier("connection-host-field")
                                    if !host.isEmpty && !isHostValid {
                                        Text("Invalid hostname")
                                            .font(.caption2)
                                            .foregroundStyle(.red.opacity(0.8))
                                    }
                                }
                                fieldRow(icon: "number", title: "Port", width: 80) {
                                    TextField("22", text: $port)
                                        .textFieldStyle(DarkFieldStyle(palette: palette))
                                        .keyboardType(.numberPad)
                                        .focused($focusedField, equals: .port)
                                    if !port.isEmpty && !isPortValid {
                                        Text("1-65535")
                                            .font(.caption2)
                                            .foregroundStyle(.red.opacity(0.8))
                                    }
                                }
                            }

                            fieldRow(icon: "person", title: "Username") {
                                TextField("user", text: $username)
                                    .textFieldStyle(DarkFieldStyle(palette: palette))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .username)
                                    .accessibilityIdentifier("connection-username-field")
                            }
                        }
                    }

                    // AUTHENTICATION section
                    sectionCard {
                        sectionHeader("AUTHENTICATION", icon: "lock.shield", color: .blue)

                        VStack(alignment: .leading, spacing: 12) {
                            Picker("", selection: $authMethod) {
                                Text("Password").tag(AuthMethod.password)
                                Text("Key File").tag(AuthMethod.keyFile)
                                Text("Tailscale").tag(AuthMethod.tailscaleSSH)
                            }
                            .pickerStyle(.segmented)

                            if authMethod == .password {
                                SecureField("Password", text: $password)
                                    .textFieldStyle(DarkFieldStyle(palette: palette))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .password)
                                    .accessibilityIdentifier("connection-password-field")
                            } else if authMethod == .keyFile {
                                Button {
                                    showKeyFilePicker = true
                                } label: {
                                    HStack {
                                         Image(systemName: keyFileName != nil ? "key.fill" : "doc.badge.plus")
                                             .foregroundStyle(keyFileName != nil ? palette.accent : palette.secondaryText)
                                         Text(keyFileName ?? "Import Private Key")
                                             .foregroundStyle(keyFileName != nil ? palette.primaryText : palette.secondaryText)
                                        Spacer()
                                        if keyFileName != nil {
                                            Button {
                                                keyFileName = nil
                                                keyFileData = nil
                                            } label: {
                                                 Image(systemName: "xmark.circle.fill")
                                                     .foregroundStyle(palette.tertiaryText)
                                             }
                                         }
                                     }
                                     .padding(12)
                                     .background(palette.controlBackground)
                                     .cornerRadius(10)
                                 }

                                SecureField("Passphrase (optional)", text: $keyPassphrase)
                                    .textFieldStyle(DarkFieldStyle(palette: palette))
                                    .focused($focusedField, equals: .keyPassphrase)
                            }

                            if authMethod == .tailscaleSSH {
                                hintLabel("Tailscale handles authentication via ACLs at the network layer. No password or key needed.", icon: "info.circle")
                            } else if authMethod == .password {
                                hintLabel("Using Tailscale SSH? Select \"Tailscale\" auth instead.", icon: "lightbulb")
                            }
                        }
                    }

                    // CONNECTION TYPE section
                    sectionCard {
                        sectionHeader("PROTOCOL", icon: "antenna.radiowaves.left.and.right", color: .orange)

                        VStack(alignment: .leading, spacing: 12) {
                            Picker("", selection: $connectionType) {
                                Text("Auto").tag(ConnectionType.auto)
                                Text("SSH").tag(ConnectionType.ssh)
                                Text("Mosh").tag(ConnectionType.mosh)
                            }
                            .pickerStyle(.segmented)

                            hintLabel("Auto will use Mosh if available, otherwise SSH.", icon: "info.circle")
                        }
                    }

                    // Connect button
                    Button {
                        submit(connectAfterSave: true)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .font(.callout)
                            Text("Connect")
                                .font(.headline)
                        }
                        .foregroundStyle(.black)
                        .foregroundStyle(palette.accentForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(palette.accent.gradient)
                        .cornerRadius(14)
                        .shadow(color: palette.accent.opacity(canSave ? 0.25 : 0), radius: 12, y: 6)
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
                    .padding(.top, 4)
                    .accessibilityIdentifier("connection-connect-button")
                }
                .padding(20)
                .iPadContentWidth(600)
            }
            .background(palette.screenBackground)
            .navigationTitle(isEditing ? "Edit Connection" : "New Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(palette.secondaryText)
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        submit(connectAfterSave: false)
                    } label: {
                        Text("Save")
                            .fontWeight(.semibold)
                            .foregroundStyle(palette.accent)
                    }
                    .accessibilityIdentifier("connection-save-button")
                }
            }
            .onAppear {
                if case .edit(let connection) = mode {
                    name = connection.name
                    host = connection.host
                    port = String(connection.port)
                    username = connection.username
                    authMethod = connection.authMethod
                    connectionType = connection.connectionType
                    password = KeychainService.getPassword(for: connection.id) ?? ""
                    keyPassphrase = KeychainService.getKeyPassphrase(for: connection.id) ?? ""
                    keyFileName = connection.keyFilePath
                    if KeychainService.getPrivateKey(for: connection.id) != nil {
                        keyFileData = Data() // placeholder to show key is loaded
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert("Save Failed", isPresented: Binding(
            get: { validationError != nil },
            set: { if !$0 { validationError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationError ?? "Unknown error")
        }
        .fileImporter(
            isPresented: $showKeyFilePicker,
            allowedContentTypes: [.data, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    keyFileData = data
                    keyFileName = url.lastPathComponent
                }
            case .failure:
                break
            }
        }
    }

    // MARK: - UI Helpers

    private func sectionCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .background(palette.surfaceBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(palette.border, lineWidth: 0.5)
        )
    }

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(palette.primaryText)
                .frame(width: 24, height: 24)
                .background(color.gradient)
                .cornerRadius(6)

            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(palette.secondaryText)
                .tracking(0.5)
        }
    }

    @ViewBuilder
    private func fieldRow(icon: String, title: String, width: CGFloat? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(palette.tertiaryText)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            }
            content()
        }
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(width: width)
    }

    private func hintLabel(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(palette.tertiaryText)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
        }
    }

    // MARK: - Logic

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func submit(connectAfterSave: Bool) {
        focusedField = nil
        Task { @MainActor in
            await Task.yield()
            do {
                let connection = try saveConnection()
                dismiss()
                if connectAfterSave {
                    onConnect?(connection)
                }
            } catch {
                validationError = error.localizedDescription
            }
        }
    }

    @discardableResult
    private func saveConnection() throws -> Connection {
        let portNumber = Int(port) ?? 22

        if case .edit(let connection) = mode {
            connection.name = name
            connection.host = host
            connection.port = portNumber
            connection.username = username
            connection.authMethod = authMethod
            connection.connectionType = connectionType
            try saveCredentials(for: connection.id, keyFilePath: &connection.keyFilePath)
            try modelContext.save()
            return connection
        } else {
            let connection = Connection(
                name: name,
                host: host,
                port: portNumber,
                username: username,
                authMethod: authMethod,
                connectionType: connectionType
            )
            modelContext.insert(connection)
            try saveCredentials(for: connection.id, keyFilePath: &connection.keyFilePath)
            try modelContext.save()
            return connection
        }
    }

    /// Save all provided credentials regardless of selected auth method,
    /// so switching auth modes doesn't discard previously entered secrets.
    private func saveCredentials(for connectionId: UUID, keyFilePath: inout String?) throws {
        if !password.isEmpty {
            try KeychainService.savePassword(password, for: connectionId)
        }
        if let keyData = keyFileData, !keyData.isEmpty {
            try KeychainService.savePrivateKey(keyData, for: connectionId)
        }
        keyFilePath = keyFileName
        if !keyPassphrase.isEmpty {
            try KeychainService.saveKeyPassphrase(keyPassphrase, for: connectionId)
        }
    }
}

struct DarkFieldStyle: TextFieldStyle {
    let palette: AppThemePalette

    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .padding(12)
            .background(palette.controlBackground)
            .cornerRadius(10)
            .foregroundStyle(palette.primaryText)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(palette.border.opacity(0.8), lineWidth: 0.5)
            )
    }
}

#Preview {
    EditConnectionView(mode: .add)
        .modelContainer(for: Connection.self, inMemory: true)
}
