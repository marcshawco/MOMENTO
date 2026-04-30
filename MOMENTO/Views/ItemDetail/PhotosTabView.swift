import PhotosUI
import SwiftUI

/// Photo gallery tab: grid of imported photos, PhotosPicker for adding, full-screen preview, delete.
struct PhotosTabView: View {

    @Bindable var viewModel: ItemDetailViewModel

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedPhotoForPreview: PhotoAttachment?
    @State private var captionPhoto: PhotoAttachment?
    @State private var captionText = ""
    @State private var isImporting = false
    @State private var importError: String?

    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("PhotoImportError")
            }

            photoGrid
            importButton
        }
        .fullScreenCover(item: $selectedPhotoForPreview) { photo in
            PhotoFullScreenView(photo: photo)
        }
        .sheet(item: $captionPhoto) { photo in
            PhotoCaptionEditorSheet(
                caption: $captionText,
                photo: photo
            ) {
                viewModel.updatePhotoCaption(photo, caption: captionText)
            }
        }
    }

    // MARK: - Photo Grid

    @ViewBuilder
    private var photoGrid: some View {
        if let photos = viewModel.item?.photoAttachments.sorted(by: { $0.createdAt > $1.createdAt }),
           !photos.isEmpty
        {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(photos) { photo in
                    photoCell(photo)
                }
            }
        } else {
            ContentUnavailableView {
                Label("No Photos", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("Add photos to document your item.")
            }
            .frame(height: 120)
        }
    }

    private func photoCell(_ photo: PhotoAttachment) -> some View {
        Group {
            if let url = try? FileStorageService.shared.resolveURL(for: photo.fileName) {
                DownsampledImageView(
                    url: url,
                    targetSize: CGSize(width: 100, height: 100)
                )
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            selectedPhotoForPreview = photo
        }
        .contextMenu {
            if !photo.caption.isEmpty {
                Text(photo.caption)
            }
            Button {
                beginEditingCaption(for: photo)
            } label: {
                Label(photo.caption.isEmpty ? "Add Caption" : "Edit Caption", systemImage: "text.bubble")
            }
            Button(role: .destructive) {
                viewModel.deletePhoto(photo)
            } label: {
                Label("Delete Photo", systemImage: "trash")
            }
        }
    }

    // MARK: - Import

    private var importButton: some View {
        HStack {
            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: 10,
                matching: .images
            ) {
                Label("Add Photos", systemImage: "photo.badge.plus")
                    .font(.subheadline.weight(.medium))
            }

            if isImporting {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 8)
            }
        }
        .onChange(of: selectedPhotoItems) {
            Task {
                await importSelectedPhotos()
            }
        }
    }

    private func importSelectedPhotos() async {
        guard !selectedPhotoItems.isEmpty else { return }
        isImporting = true
        importError = nil
        var didFail = false

        for pickerItem in selectedPhotoItems {
            do {
                guard let data = try await pickerItem.loadTransferable(type: Data.self) else {
                    didFail = true
                    continue
                }
                try viewModel.addPhoto(data: data)
            } catch {
                didFail = true
            }
        }

        selectedPhotoItems = []
        isImporting = false
        if didFail {
            importError = "Some photos could not be imported."
        }
    }

    private func beginEditingCaption(for photo: PhotoAttachment) {
        captionText = photo.caption
        captionPhoto = photo
    }
}

// MARK: - Full Screen Photo Preview

struct PhotoFullScreenView: View {
    let photo: PhotoAttachment

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let url = try? FileStorageService.shared.resolveURL(for: photo.fileName),
                   let uiImage = UIImage(contentsOfFile: url.path(percentEncoded: false))
                {
                    VStack(spacing: 16) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .gesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        scale = value.magnification
                                    }
                                    .onEnded { _ in
                                        withAnimation(.spring) {
                                            scale = 1.0
                                        }
                                    }
                            )

                        if !photo.caption.isEmpty {
                            Text(photo.caption)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                } else {
                    ContentUnavailableView("Photo Not Found", systemImage: "photo")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Photo Caption Editor

struct PhotoCaptionEditorSheet: View {

    @Binding var caption: String
    let photo: PhotoAttachment
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Caption") {
                    TextField("Caption", text: $caption, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($isFocused)
                }
            }
            .navigationTitle(photo.caption.isEmpty ? "Add Caption" : "Edit Caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium])
    }
}
