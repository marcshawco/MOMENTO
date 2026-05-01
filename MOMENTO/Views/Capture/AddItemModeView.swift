import SwiftUI

struct AddItemModeView: View {
    let startGuidedScan: () -> Void
    let startPhotoSet: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        startGuidedScan()
                    } label: {
                        modeRow(
                            title: "Guided LiDAR Scan",
                            subtitle: "Best for objects sitting still on a table. Uses Apple's Object Capture guidance.",
                            systemImage: "viewfinder.circle.fill",
                            tint: .blue
                        )
                    }

                    Button {
                        startPhotoSet()
                    } label: {
                        modeRow(
                            title: "Photo Set Reconstruction",
                            subtitle: "Upload front, back, left, right, top, bottom, then add optional detail photos.",
                            systemImage: "photo.stack.fill",
                            tint: .orange
                        )
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
        tint: Color
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
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
