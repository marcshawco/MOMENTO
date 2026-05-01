import PhotosUI
import SwiftData
import SwiftUI

struct PhotoSetReconstructionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = PhotoSetReconstructionViewModel()
    @State private var requiredPickerItems: [PhotoSetViewpoint: PhotosPickerItem] = [:]
    @State private var optionalPickerItems: [PhotosPickerItem] = []

    private let columns = [
        GridItem(.adaptive(minimum: 142), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                content

                if viewModel.state.isBusy {
                    busyOverlay
                }
            }
            .navigationTitle("Photo Set")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        viewModel.cancel()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
        }
        .task {
            viewModel.configure(modelContext: modelContext)
        }
        .onChange(of: viewModel.createdItemId) {
            if viewModel.createdItemId != nil {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    dismiss()
                }
            }
        }
        .onChange(of: optionalPickerItems) {
            Task {
                await importOptionalImages()
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                guidanceHeader
                requiredViewsGrid
                optionalPhotosSection
                failureView
            }
            .padding()
            .padding(.bottom, 96)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var guidanceHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "photo.stack.fill")
                    .foregroundStyle(.orange)
                Text("Six required views")
                    .font(.headline)
            }

            Text("Use sharp, evenly lit photos with the object filling the frame. Add optional diagonal and close-up detail photos for stronger reconstruction.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private var requiredViewsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Required Views")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(PhotoSetViewpoint.allCases) { viewpoint in
                    requiredSlot(for: viewpoint)
                }
            }
        }
    }

    private func requiredSlot(for viewpoint: PhotoSetViewpoint) -> some View {
        let isSelected = viewModel.requiredImageData[viewpoint] != nil

        return PhotosPicker(
            selection: binding(for: viewpoint),
            matching: .images,
            photoLibrary: .shared()
        ) {
            PhotoSetRequiredSlotView(viewpoint: viewpoint, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .onChange(of: requiredPickerItems[viewpoint]) {
            Task {
                await importRequiredImage(for: viewpoint)
            }
        }
        .contextMenu {
            if viewModel.requiredImageData[viewpoint] != nil {
                Button(role: .destructive) {
                    viewModel.removeRequiredImage(for: viewpoint)
                    requiredPickerItems[viewpoint] = nil
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    private var optionalPhotosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Optional Detail Photos")
                        .font(.headline)
                    Text("\(viewModel.optionalImageData.count) added")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                PhotosPicker(
                    selection: $optionalPickerItems,
                    maxSelectionCount: 60,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if viewModel.optionalImageData.isEmpty {
                ContentUnavailableView(
                    "Add Overlap",
                    systemImage: "camera.metering.multispot",
                    description: Text("Diagonal, edge, label, and close-up photos help photogrammetry bridge the six main views.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(viewModel.optionalImageData.enumerated()), id: \.offset) { index, data in
                        optionalCell(data: data, index: index)
                    }
                }
            }
        }
    }

    private func optionalCell(data: Data, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 126)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.background)
                    .frame(height: 126)
            }

            Button {
                viewModel.removeOptionalImage(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var failureView: some View {
        if case .failed(let message) = viewModel.state {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Text(viewModel.readinessText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                viewModel.reconstruct()
            } label: {
                Label("Reconstruct 3D Model", systemImage: "cube.transparent.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canReconstruct)
        }
        .padding()
        .background(.regularMaterial)
    }

    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            switch viewModel.state {
            case .preparing:
                ReconstructionProgressView(progress: 0.02, statusText: "Preparing photos...")
            case .reconstructing(let progress):
                ReconstructionProgressView(progress: progress)
            case .saving:
                ReconstructionProgressView(progress: 1.0, statusText: "Saving item...")
            default:
                EmptyView()
            }
        }
    }

    private func binding(for viewpoint: PhotoSetViewpoint) -> Binding<PhotosPickerItem?> {
        Binding(
            get: { requiredPickerItems[viewpoint] },
            set: { requiredPickerItems[viewpoint] = $0 }
        )
    }

    private func importRequiredImage(for viewpoint: PhotoSetViewpoint) async {
        guard let item = requiredPickerItems[viewpoint],
              let data = try? await item.loadTransferable(type: Data.self) else {
            return
        }
        viewModel.setRequiredImage(data, for: viewpoint)
    }

    private func importOptionalImages() async {
        var imageData: [Data] = []
        for item in optionalPickerItems {
            if let data = try? await item.loadTransferable(type: Data.self) {
                imageData.append(data)
            }
        }
        viewModel.setOptionalImages(imageData)
    }
}

private struct PhotoSetRequiredSlotView: View {
    let viewpoint: PhotoSetViewpoint
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : viewpoint.systemImage)
                .font(.title2)
                .foregroundStyle(isSelected ? .green : .secondary)

            Text(viewpoint.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(isSelected ? "Selected" : "Choose photo")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 126)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.green.opacity(0.55) : Color.secondary.opacity(0.18))
        }
    }
}

#Preview {
    PhotoSetReconstructionView()
}
