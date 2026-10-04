import SwiftUI

struct AddItemModeView: View {
    let startGuidedScan: () -> Void
    let startPhotoSet: () -> Void

    private let supportsGuidedScan = DeviceCapability.supportsGuidedObjectCapture
    private let supportsReconstruction = DeviceCapability.supportsOnDeviceReconstruction

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        startGuidedScan()
                    } label: {
                        modeRow(
                            title: "Guided LiDAR Scan",
                            subtitle: supportsGuidedScan
                                ? "Best for objects sitting still on a table. Uses Apple's Object Capture guidance."
                                : "Needs a LiDAR-equipped iPhone or iPad. Not available on this device.",
                            systemImage: "viewfinder.circle.fill",
                            tint: .blue,
                            isEnabled: supportsGuidedScan && supportsReconstruction
                        )
                    }
                    .disabled(!supportsGuidedScan || !supportsReconstruction)

                    Button {
                        startPhotoSet()
                    } label: {
                        modeRow(
                            title: "Photo Set Reconstruction",
                            subtitle: supportsReconstruction
                                ? "Upload front, back, left, right, top, bottom, then add optional detail photos."
                                : "On-device 3D reconstruction is not available on this device.",
                            systemImage: "photo.stack.fill",
                            tint: .orange,
                            isEnabled: supportsReconstruction
                        )
                    }
                    .disabled(!supportsReconstruction)
                } footer: {
                    Text(DeviceCapability.recommendedHardwareSummary)
                }

                if !supportsReconstruction {
                    Section {
                        Text("You can still add items by hand and attach photos, notes, voice memos, valuations, and exports. Only 3D model creation needs supported hardware.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Small Object Tip") {
                    Text("For jewelry, pins, brooches, cans, cards, and reflective pieces, use a textured background and add many optional angle/detail photos. Six photos can start a reconstruction, but more overlap usually means better geometry.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Item")
        }
    }

    private func modeRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        isEnabled: Bool
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    (isEnabled ? tint : Color.secondary).gradient,
                    in: RoundedRectangle(cornerRadius: 8)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    AddItemModeView(
        startGuidedScan: {},
        startPhotoSet: {}
    )
}
