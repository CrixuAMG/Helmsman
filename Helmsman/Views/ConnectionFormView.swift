import SwiftUI

struct ConnectionFormView: View {
    @Bindable var viewModel: ConnectionWindowViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                generalSection
                Divider()
                serverSection
                Divider()
                authenticationSection
                Divider()
                supervisorSection
                Divider()
                optionsSection
                Divider()
                actionsBar
            }
            .padding(32)
        }
        .background(.background)
    }

    // MARK: - General

    private var generalSection: some View {
        FormSection(title: "General") {
            FormField(label: "Name") {
                TextField("Production Server", text: $viewModel.name)
            }

            FormField(label: "Accent Color") {
                HStack(spacing: 8) {
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: viewModel.accentColorHex) ?? .blue },
                        set: { viewModel.accentColorHex = $0.toHex() ?? "#007AFF" }
                    ))
                    .labelsHidden()
                    .frame(width: 40)

                    TextField("#007AFF", text: $viewModel.accentColorHex)
                        .frame(width: 100)
                }
            }

            FormField(label: "Notes") {
                TextField("Optional notes...", text: $viewModel.notes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
    }

    // MARK: - Connection

    private var serverSection: some View {
        FormSection(title: "Connection") {
            FormField(label: "Method") {
                Picker("", selection: $viewModel.connectionMethod) {
                    ForEach(ConnectionMethod.allCases, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: viewModel.connectionMethod) { _, _ in
                    viewModel.connectionMethodChanged()
                }
            }

            switch viewModel.connectionMethod {
            case .local:
                localEndpointField
            case .docker:
                dockerFields
            case .ssh:
                hostAndPortFields(defaultPort: 22)
            case .xmlrpc, .auto:
                xmlrpcEndpointField
            }
        }
    }

    private var dockerFields: some View {
        Group {
            FormField(label: "Docker Host") {
                TextField("127.0.0.1", text: $viewModel.host)
            }

            FormField(label: "Docker Port") {
                TextField("2375", value: $viewModel.port, format: .number.locale(Locale(identifier: "en_US")))
                    .frame(width: 100)
            }

            FormField(label: "Container") {
                TextField("my-supervisor-container", text: $viewModel.dockerContainer)
            }
        }
    }

    private func hostAndPortFields(defaultPort: Int) -> some View {
        Group {
            FormField(label: "Host") {
                TextField("192.168.1.100", text: $viewModel.host)
            }

            FormField(label: "Port") {
                TextField("\(defaultPort)", value: $viewModel.port, format: .number)
                    .frame(width: 100)
            }
        }
    }

    private var localEndpointField: some View {
        FormField(label: "XML-RPC URL") {
            TextField("http://127.0.0.1:9001/RPC2", text: $viewModel.localEndpoint)
        }
    }

    private var xmlrpcEndpointField: some View {
        FormField(label: "XML-RPC URL") {
            TextField("http://localhost:9001/RPC2", text: $viewModel.xmlrpcEndpoint)
        }
    }

    // MARK: - Authentication

    @ViewBuilder
    private var authenticationSection: some View {
        if viewModel.connectionMethod == .ssh {
            sshAuthenticationSection
        } else if viewModel.connectionMethod == .local || viewModel.connectionMethod == .xmlrpc || viewModel.connectionMethod == .auto {
            xmlrpcAuthenticationSection
        }
    }

    private var sshAuthenticationSection: some View {
        FormSection(title: "Authentication") {
            FormField(label: "Username") {
                TextField("root", text: $viewModel.username)
            }

            FormField(label: "Method") {
                Picker("", selection: $viewModel.authenticationMethod) {
                    ForEach(AuthenticationMethod.allCases, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }

            if viewModel.authenticationMethod == .sshKey {
                FormField(label: "SSH Key Path") {
                    HStack {
                        TextField("~/.ssh/id_rsa", text: $viewModel.sshKeyPath)
                        Button("Browse") {
                            chooseFile { url in
                                viewModel.sshKeyPath = url.path
                            }
                        }
                    }
                }
            } else {
                FormField(label: "Password") {
                    SecureField("Password", text: $viewModel.password)
                        .frame(width: 300)
                }
            }
        }
    }

    private var xmlrpcAuthenticationSection: some View {
        FormSection(title: "Authentication") {
            FormField(label: "Username") {
                TextField("Optional", text: $viewModel.username)
            }

            FormField(label: "Password") {
                SecureField("Optional", text: $viewModel.password)
                    .frame(width: 300)
            }
        }
    }

    // MARK: - Supervisor

    @ViewBuilder
    private var supervisorSection: some View {
        if viewModel.connectionMethod == .local || viewModel.connectionMethod == .docker || viewModel.connectionMethod == .ssh {
            FormSection(title: "Supervisor") {
                FormField(label: viewModel.connectionMethod == .docker ? "Path in Container" : "supervisorctl Path") {
                    HStack {
                        TextField("/usr/bin/supervisorctl", text: $viewModel.supervisorctlPath)

                        if viewModel.connectionMethod == .local {
                            Button("Detect") {
                                Task { await viewModel.detectSupervisorctlPath() }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        FormSection(title: "Options") {
            FormField(label: "Polling Interval") {
                HStack {
                    TextField("5", value: $viewModel.pollingInterval, format: .number)
                        .frame(width: 80)
                    Text("seconds")
                        .foregroundStyle(.secondary)
                }
            }

            FormField(label: "Timeout") {
                HStack {
                    TextField("30", value: $viewModel.timeout, format: .number)
                        .frame(width: 80)
                    Text("seconds")
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Auto Reconnect", isOn: $viewModel.autoReconnect)
            Toggle("Safe Mode", isOn: $viewModel.safeMode)
            Toggle("Touch ID for Production Stops", isOn: $viewModel.touchIDProtected)
                .help("Require Touch ID before stopping services marked as production.")
        }
    }

    // MARK: - Actions

    private var actionsBar: some View {
        VStack(spacing: 12) {
            if let result = viewModel.testResult {
                HStack {
                    switch result {
                    case .success(let message):
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(message)
                            .foregroundStyle(.green)
                    case .failure(let message):
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                }
                .font(.callout)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.regularMaterial)
                )
            }

            HStack {
                Button("Test Connection") {
                    Task { await viewModel.testConnection() }
                }
                .disabled(viewModel.isTesting || !isFormValid)

                if viewModel.isTesting {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button("Cancel") {
                    viewModel.isEditing = false
                    viewModel.testResult = nil
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Save") {
                    viewModel.save()
                    viewModel.isEditing = false
                    viewModel.testResult = nil
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!isFormValid)
            }
        }
    }

    private var isFormValid: Bool {
        viewModel.isFormValid
    }

    private func chooseFile(onPick: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            onPick(url)
        }
    }
}

// MARK: - Form Helpers

private struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(.leading, 4)
        }
    }
}

private struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .frame(width: 140, alignment: .trailing)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                content()
            }
        }
    }
}
