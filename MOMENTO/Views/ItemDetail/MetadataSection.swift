import SwiftUI

/// Editable metadata fields for a collection item.
/// Auto-saves changes via the view model's debounce mechanism.
struct MetadataSection: View {

    @Bindable var viewModel: ItemDetailViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            titleField
            descriptionField
            collectionField
            tagsSection
            valuationSection
            provenanceSection
        }
        .onChange(of: viewModel.title) { viewModel.scheduleAutoSave() }
        .onChange(of: viewModel.itemDescription) { viewModel.scheduleAutoSave() }
        .onChange(of: viewModel.collectionName) { viewModel.scheduleAutoSave() }
        .onChange(of: viewModel.estimatedValue) { viewModel.scheduleAutoSave() }
        .onChange(of: viewModel.purchasePrice) { viewModel.scheduleAutoSave() }
        .onChange(of: viewModel.purchaseDate) { viewModel.scheduleAutoSave() }
        .onChange(of: viewModel.serialNumber) { viewModel.scheduleAutoSave() }
        .onChange(of: viewModel.provenanceNotes) { viewModel.scheduleAutoSave() }
    }

    // MARK: - Title

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Title")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Item name", text: $viewModel.title)
                .font(.title3.weight(.semibold))
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Description

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Describe your item...", text: $viewModel.itemDescription, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Collection

    private var collectionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Collection")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Collection name", text: $viewModel.collectionName)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Add tag", text: $viewModel.tagInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.addTag() }

                Button {
                    viewModel.addTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .disabled(viewModel.tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !viewModel.tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(viewModel.tags, id: \.self) { tag in
                        tagChip(tag)
                    }
                }
            }
        }
    }

    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text(tag)
            Button {
                viewModel.removeTag(tag)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.tint.opacity(0.15), in: Capsule())
    }

    // MARK: - Valuation

    private var valuationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Valuation")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Estimated Value")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    TextField(
                        "$0.00",
                        value: $viewModel.estimatedValue,
                        format: .currency(code: "USD")
                    )
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Purchase Price")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    TextField(
                        "$0.00",
                        value: $viewModel.purchasePrice,
                        format: .currency(code: "USD")
                    )
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                }
            }

            Toggle(
                "Include Purchase Date",
                isOn: Binding(
                    get: { viewModel.purchaseDate != nil },
                    set: { includeDate in
                        viewModel.purchaseDate = includeDate ? (viewModel.purchaseDate ?? .now) : nil
                    }
                )
            )
            .font(.subheadline)

            if viewModel.purchaseDate != nil {
                DatePicker(
                    "Purchase Date",
                    selection: Binding(
                        get: { viewModel.purchaseDate ?? .now },
                        set: { viewModel.purchaseDate = $0 }
                    ),
                    displayedComponents: .date
                )
                .font(.subheadline)

                Button("Clear Date", role: .destructive) {
                    viewModel.purchaseDate = nil
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    // MARK: - Provenance

    private var provenanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Provenance & Details")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Serial Number")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                TextField("Serial number", text: $viewModel.serialNumber)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Provenance Notes")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                TextField(
                    "Origin, history, authenticity details...",
                    text: $viewModel.provenanceNotes,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
            }
        }
    }
}
