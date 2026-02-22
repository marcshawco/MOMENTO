import SwiftUI

struct ShelfItemCard: View {
    let item: CollectionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailView
                .frame(height: 160)
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

                if !item.collectionName.isEmpty {
                    Text(item.collectionName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let value = item.formattedEstimatedValue {
                    Text(value)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tint)
                }
            }
            .padding(10)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailFileName = item.thumbnailFileName,
           let url = try? FileStorageService.shared.resolveURL(for: thumbnailFileName),
           FileStorageService.shared.fileExists(fileName: thumbnailFileName) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholderView
                default:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        ZStack {
            Color.accentColor.opacity(0.08)
            Image(systemName: "cube.transparent")
                .font(.system(size: 36))
                .foregroundStyle(.tint.opacity(0.4))
        }
    }

    private var accessibilityDescription: String {
        var parts = [item.title]
        if !item.collectionName.isEmpty {
            parts.append("in \(item.collectionName)")
        }
        if let value = item.formattedEstimatedValue {
            parts.append("valued at \(value)")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 16) {
        ShelfItemCard(item: SampleData.sampleItem)
        ShelfItemCard(item: SampleData.sampleItemNoThumbnail)
    }
    .padding()
}
