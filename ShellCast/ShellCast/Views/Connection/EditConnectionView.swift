import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct EditConnectionView: View {
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

    init(mode: Mode, onConnect: ((Connection) -> Void)? = nil) {
        self.mode = mode
        self.onConnect = onConnect
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    field("Name") {
                        TextField("My Server", text: $name)
                            .textFieldStyle(DarkFieldStyle())
                    }

                    HStack(spacing: 12) {
                        field("Host") {
                            TextField("hostname or IP", text: $host)
                                .textFieldStyle(DarkFieldStyle())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        field("Port", width: 80) {
                            TextField("22", text: $port)
                                .textFieldStyle(DarkFieldStyle())
                                .keyboardType(.numberPad)
                        }
                    }

                    field("Username") {
                        TextField("user", text: $username)
                            .textFieldStyle(DarkFieldStyle())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    // Authentication
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Authentication")
                                .font(.subheadline)
                                .foregroundStyle(.gray)
                            Spacer()
                            Picker("", selection: $authMethod) {
                                Text("Password").tag(AuthMethod.password)
                                Text("Key File").tag(AuthMethod.keyFile)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }

                        if authMethod == .password {
                            SecureField("Password", text: $password)
                                .textFieldStyle(DarkFieldStyle())
                        } else if authMethod == .keyFile {
                            Button {
                                showKeyFilePicker = true
                            } label: {
                                HStack {
                                    Image(systemName: keyFileName != nil ? "key.fill" : "doc.badge.plus")
                                        .foregroundStyle(keyFileName != nil ? .green : .gray)
                                    Text(keyFileName ?? "Import Private Key")
                                        .foregroundStyle(keyFileName != nil ? .white : .gray)
                                    Spacer()
                                    if keyFileName != nil {
                                        Button {
                                            keyFileName = nil
                                            keyFileData = nil
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.gray)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(Color(white: 0.12))
                                .cornerRadius(8)
                            }

                            SecureField("Passphrase (optional)", text: $keyPassphrase)
                                .textFieldStyle(DarkFieldStyle())
                        }
                    }

                    Text("Using Tailscale SSH? You can leave the password empty since Tailscale handles authentication via ACLs.")
                        .font(.caption)
                        .foregroundStyle(.gray)

                    // Connection Type
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Connection Type")
                                .font(.subheadline)
                                .foregroundStyle(.gray)
                            Spacer()
                            Picker("", selection: $connectionType) {
                                Text("Auto").tag(ConnectionType.auto)
                                Text("SSH").tag(ConnectionType.ssh)
                                Text("Mosh").tag(ConnectionType.mosh)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }

                        Text("Auto will use Mosh if available, otherwise SSH.")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }

                    // Connect button
                    Button {
                        saveAndConnect()
                    } label: {
                        Text("Connect")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(12)
                    }
                    .disabled(host.isEmpty || username.isEmpty)
                    .padding(.top, 8)
                }
                .padding(20)
                .iPadContentWidth(600)
            }
            .background(Color.black)
            .navigationTitle(isEditing ? "Edit Connection" : "New Connection")
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.green)
                    }
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
                    if connection.authMethod == .keyFile {
                        keyFileName = connection.keyFilePath
                        if KeychainService.getPrivateKey(for: connection.id) != nil {
                            keyFileData = Data() // placeholder to show key is loaded
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
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

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func saveAndConnect() {
        let connection = saveConnection()
        dismiss()
        onConnect?(connection)
    }

    private func save() {
        _ = saveConnection()
        dismiss()
    }

    @discardableResult
    private func saveConnection() -> Connection {
        let portNumber = Int(port) ?? 22

        if case .edit(let connection) = mode {
            connection.name = name
            connection.host = host
            connection.port = portNumber
            connection.username = username
            connection.authMethod = authMethod
            connection.connectionType = connectionType
            if authMethod == .password && !password.isEmpty {
                try? KeychainService.savePassword(password, for: connection.id)
            }
            if authMethod == .keyFile {
                connection.keyFilePath = keyFileName
                if let keyData = keyFileData, !keyData.isEmpty {
                    try? KeychainService.savePrivateKey(keyData, for: connection.id)
                }
                if !keyPassphrase.isEmpty {
                    try? KeychainService.saveKeyPassphrase(keyPassphrase, for: connection.id)
                } else {
                    try? KeychainService.deleteKeyPassphrase(for: connection.id)
                }
            }
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
            if authMethod == .password && !password.isEmpty {
                try? KeychainService.savePassword(password, for: connection.id)
            }
            if authMethod == .keyFile {
                connection.keyFilePath = keyFileName
                if let keyData = keyFileData, !keyData.isEmpty {
                    try? KeychainService.savePrivateKey(keyData, for: connection.id)
                }
                if !keyPassphrase.isEmpty {
                    try? KeychainService.saveKeyPassphrase(keyPassphrase, for: connection.id)
                }
            }
            return connection
        }
    }

    @ViewBuilder
    private func field(_ title: String, width: CGFloat? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.gray)
            content()
        }
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(width: width)
    }
}

struct DarkFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .padding(12)
            .background(Color(white: 0.12))
            .cornerRadius(8)
            .foregroundStyle(.white)
    }
}

#Preview {
    EditConnectionView(mode: .add)
        .modelContainer(for: Connection.self, inMemory: true)
}
