import SwiftUI
import SwiftData

/// Full detail screen for a collection item.
/// Composes 3D preview, AR Quick Look, editable metadata, and attachment tabs.
struct ItemDetailView: View {

    let itemId: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ItemDetailViewModel()
    @Query private var items: [CollectionItem]

    private var item: CollectionItem? {
        items.first { $0.id == itemId }
    }

    var body: some View {
        Group {
            if let item {
                detailContent(for: item)
            } else {
                ContentUnavailableView("Item Not Found", systemImage: "exclamationmark.triangle")
            }
        }
    }

    // MARK: - Detail Content

    private func detailContent(for item: CollectionItem) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // 3D Model Preview
                ModelPreviewView(modelURL: viewModel.modelURL)

                // AR Quick Look button (only when model exists)
                if viewModel.modelURL != nil {
                    Button {
                        viewModel.showingARQuickLook = true
                    } label: {
                        Label("View in AR", systemImage: "arkit")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                // Editable metadata
                MetadataSection(viewModel: viewModel)

                Divider()

                // Attachments (photos, voice memos, notes)
                AttachmentsSection(viewModel: viewModel)

                Divider()

                // Timestamps
                timestampsSection(for: item)

                // Delete button
                deleteButton
            }
            .padding()
        }
        .navigationTitle(viewModel.title.isEmpty ? "Untitled" : viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.exportAsPDF()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(viewModel.isExporting)
            }
        }
        .overlay {
            if viewModel.isExporting {
                ExportProgressView(message: "Generating PDF...")
            }
        }
        .sheet(isPresented: $viewModel.showingShareSheet) {
            if let url = viewModel.exportedFileURL {
                ShareSheetView(activityItems: [url])
            }
        }
        .onAppear {
            viewModel.configure(item: item, modelContext: modelContext)
        }
        .onDisappear {
            viewModel.saveIfNeeded()
        }
        .sheet(isPresented: $viewModel.showingARQuickLook) {
            if let url = viewModel.modelURL {
                ARQuickLookView(modelURL: url)
            }
        }
        .confirmationDialog(
            "Delete Item?",
            isPresented: $viewModel.showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                viewModel.deleteItem()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this item and all its attachments. This cannot be undone.")
        }
    }

    // MARK: - Timestamps

    private func timestampsSection(for item: CollectionItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Created") {
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            LabeledContent("Updated") {
                Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button(role: .destructive) {
            viewModel.showingDeleteConfirmation = true
        } label: {
            Label("Delete Item", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .padding(.top, 8)
        .padding(.bottom, 32)
    }
}

#Preview {
    NavigationStack {
        ItemDetailView(itemId: SampleData.sampleItem.id)
    }
    .modelContainer(SampleData.previewContainer)
}
