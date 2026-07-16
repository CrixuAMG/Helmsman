import SwiftUI

struct ConnectionFormView: View {
    @Bindable var viewModel: ConnectionWindowViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                generalSection
                serverSection
                authenticationSection
                supervisorSection
                optionsSection
                actionsBar
            }
            .padding(24)
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

    // MARK: - Server

    private var serverSection: some View {
        FormSection(title: "Server") {
            FormField(label: "Host") {
                TextField("192.168.1.100", text: $viewModel.host)
            }

            FormField(label: "Port") {
                TextField("22", value: $viewModel.port, format: .number)
                    .frame(width: 100)
            }

            FormField(label: "Connection Method") {
                Picker("", selection: $viewModel.connectionMethod) {
                    ForEach(ConnectionMethod.allCases, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }
        }
    }

    // MARK: - Authentication

    private var authenticationSection: some View {
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
                FormField(label: "Password") {
                    SecureField("Password", text: $viewModel.password)
                        .frame(width: 300)
                }
            }
        }
    }

    // MARK: - Supervisor

    private var supervisorSection: some View {
        FormSection(title: "Supervisor") {
            FormField(label: "supervisorctl Path") {
                TextField("/usr/bin/supervisorctl", text: $viewModel.supervisorctlPath)
            }

            FormField(label: "XML-RPC Endpoint") {
                TextField("http://localhost:9001/RPC2", text: $viewModel.xmlrpcEndpoint)
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
        HStack {
            Spacer()

            Button("Cancel") {
                viewModel.isEditing = false
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button("Save") {
                viewModel.save()
                viewModel.isEditing = false
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.name.isEmpty || viewModel.host.isEmpty)
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
