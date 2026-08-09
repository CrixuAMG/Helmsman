import SwiftUI

struct ProcessTagsSheetView: View {
    @Bindable var viewModel: MainWindowViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Process Tags")
                        .font(.title2.weight(.semibold))
                    Text("Group services into reusable start, stop, and restart actions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            HStack {
                TextField("New tag, e.g. api", text: $newTag)
                    .onSubmit(addTag)
                Button("Add", action: addTag)
                    .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if viewModel.tagNames.isEmpty {
                ContentUnavailableView(
                    "No Tags",
                    systemImage: "tag",
                    description: Text("Create a tag and assign one or more services to it.")
                )
            } else {
                List {
                    ForEach(viewModel.tagNames, id: \.self) { tag in
                        Section {
                            ForEach(viewModel.services) { service in
                                Toggle(isOn: Binding(
                                    get: { viewModel.tags(for: service.id).contains(tag) },
                                    set: { _ in viewModel.toggleTag(tag, for: service.id) }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(service.name)
                                        if service.group != service.name {
                                            Text(service.group)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Label(tag, systemImage: "tag.fill")
                                Spacer()
                                Button(role: .destructive) {
                                    viewModel.removeTag(tag)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 460)
    }

    private func addTag() {
        let name = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        viewModel.addTag(name)
        newTag = ""
    }
}
