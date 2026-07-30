import SwiftUI

struct ConnectionFormView: View {
    @Bindable var viewModel: ConnectionWindowViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                generalSection
                Divider()
                serverSection

                if showsAuthenticationSection {
                    Divider()
                    authenticationSection
                }

                if showsSupervisorSection {
                    Divider()
                    supervisorSection
                }

                Divider()
                optionsSection
                Divider()
                actionsBar
            }
            .padding(32)
        }
        .background(.background)
    }

    private var showsAuthenticationSection: Bool {
        viewModel.connectionMethod == .ssh || viewModel.connectionMethod == .docker || viewModel.connectionMethod == .xmlrpc
    }

    private var showsSupervisorSection: Bool {
        viewModel.connectionMethod != .docker
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

    // MARK: - Server

    private var serverSection: some View {
        FormSection(title: "Server") {
            FormField(label: "Connection Method") {
                Picker("", selection: $viewModel.connectionMethod) {
                    ForEach(ConnectionMethod.allCases, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }

            if viewModel.connectionMethod == .docker {
                FormField(label: "Container") {
                    TextField("container-name", text: $viewModel.dockerContainer)
                }

                FormField(label: "Supervisor URL") {
                    TextField("http://127.0.0.1:9001/RPC2", text: $viewModel.xmlrpcEndpoint)
                }
            }

            if viewModel.connectionMethod == .ssh {
                FormField(label: "Host") {
                    TextField("192.168.1.100", text: $viewModel.host)
                }

                FormField(label: "Port") {
                    TextField("22", value: $viewModel.port, format: .number)
                        .frame(width: 100)
                }
            }


        }
    }

    // MARK: - Authentication

    @ViewBuilder
    private var authenticationSection: some View {
        if viewModel.connectionMethod == .ssh {
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
                                let panel = NSOpenPanel()
                                panel.allowsMultipleSelection = false
                                panel.canChooseDirectories = false
                                panel.canChooseFiles = true
                                if panel.runModal() == .OK, let url = panel.url {
                                    viewModel.sshKeyPath = url.path
                                }
                            }
                        }
                    }
                } else {
                    passwordField
                }
            }
        } else if viewModel.connectionMethod == .docker || viewModel.connectionMethod == .xmlrpc {
            FormSection(title: "Authentication") {
                FormField(label: "Username") {
                    TextField("Optional username", text: $viewModel.username)
                }

                passwordField
            }
        }
    }

    private var passwordField: some View {
        FormField(label: "Password") {
            SecureField("Optional password", text: $viewModel.password)
                .frame(width: 300)
        }
    }

    // MARK: - Supervisor

    @ViewBuilder
    private var supervisorSection: some View {
        if viewModel.connectionMethod != .docker {
            FormSection(title: "Supervisor") {
                if viewModel.connectionMethod == .local || viewModel.connectionMethod == .ssh {
                    FormField(label: "supervisorctl Path") {
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

                if viewModel.connectionMethod == .local {
                    FormField(label: "Local XML-RPC URL") {
                        TextField("http://127.0.0.1:9001/RPC2", text: $viewModel.localEndpoint)
                    }
                }

                if viewModel.connectionMethod == .xmlrpc {
                    FormField(label: "XML-RPC Endpoint") {
                        TextField("http://127.0.0.1:9001/RPC2", text: $viewModel.xmlrpcEndpoint)
                    }
                }

                if viewModel.connectionMethod == .local || viewModel.connectionMethod == .ssh {
                    FormField(label: "Config File Path") {
                        HStack {
                            TextField("supervisord.conf (optional)", text: $viewModel.supervisorConfigPath)

                            if viewModel.connectionMethod == .local {
                                Button("Browse") {
                                    let panel = NSOpenPanel()
                                    panel.allowsMultipleSelection = false
                                    panel.canChooseDirectories = false
                                    panel.canChooseFiles = true
                                    if panel.runModal() == .OK, let url = panel.url {
                                        viewModel.supervisorConfigPath = url.path
                                    }
                                }
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
        if viewModel.name.isEmpty { return false }

        switch viewModel.connectionMethod {
        case .local:
            return !viewModel.localEndpoint.isEmpty && !viewModel.supervisorctlPath.isEmpty
        case .docker:
            return !viewModel.dockerContainer.isEmpty && !viewModel.xmlrpcEndpoint.isEmpty
        case .ssh:
            return !viewModel.host.isEmpty && !viewModel.username.isEmpty && !viewModel.supervisorctlPath.isEmpty
        case .xmlrpc:
            return !viewModel.xmlrpcEndpoint.isEmpty
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
