import SwiftUI
import SwiftData

struct ShelfView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CollectionItem.updatedAt, order: .reverse) private var items: [CollectionItem]

    @State private var searchText = ""
    @State private var showingSettings = false
    @State private var showingAddItem = false
    @State private var sortOrder: SortOrder = .recentFirst
    @State private var filterTag: String?

    private let columns = [
        GridItem(.adaptive(minimum: AppConstants.Limits.gridItemMinWidth), spacing: AppConstants.Limits.gridSpacing)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    EmptyShelfView()
                } else {
                    shelfGrid
                }
            }
            .navigationTitle("Momento")
            .searchable(text: $searchText, prompt: "Search items")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    sortMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                addButton
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: $showingAddItem) {
                CaptureContainerView()
            }
            .navigationDestination(for: CollectionItem.ID.self) { itemId in
                ItemDetailPlaceholderView(itemId: itemId)
            }
        }
    }

    // MARK: - Subviews

    private var shelfGrid: some View {
        ScrollView {
            if let filterTag {
                HStack {
                    Text("Filtered: \(filterTag)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Clear") {
                        self.filterTag = nil
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            LazyVGrid(columns: columns, spacing: AppConstants.Limits.gridSpacing) {
                ForEach(filteredAndSortedItems) { item in
                    NavigationLink(value: item.id) {
                        ShelfItemCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteItem(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var addButton: some View {
        Button {
            showingAddItem = true
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.tint, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .accessibilityLabel("Add new item")
        .padding(24)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort items")
    }

    // MARK: - Logic

    private var filteredAndSortedItems: [CollectionItem] {
        var result = items

        // Search filter
        if !searchText.isEmpty {
            result = result.filter { item in
                item.title.localizedCaseInsensitiveContains(searchText)
                || item.collectionName.localizedCaseInsensitiveContains(searchText)
                || item.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }

        // Tag filter
        if let filterTag {
            result = result.filter { $0.tags.contains(filterTag) }
        }

        // Sort
        switch sortOrder {
        case .recentFirst:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .nameAZ:
            result.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .valueHighLow:
            result.sort { ($0.estimatedValue ?? 0) > ($1.estimatedValue ?? 0) }
        case .valueLowHigh:
            result.sort { ($0.estimatedValue ?? 0) < ($1.estimatedValue ?? 0) }
        }

        return result
    }

    private func deleteItem(_ item: CollectionItem) {
        FileStorageService.shared.deleteFiles(for: item)
        modelContext.delete(item)
    }
}

// MARK: - Sort Order

enum SortOrder: String, CaseIterable, Identifiable {
    case recentFirst
    case nameAZ
    case valueHighLow
    case valueLowHigh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recentFirst: "Recent First"
        case .nameAZ: "Name A-Z"
        case .valueHighLow: "Value: High to Low"
        case .valueLowHigh: "Value: Low to High"
        }
    }
}

// MARK: - Placeholder Views (replaced in M3)

/// Temporary detail view. Replaced by full ItemDetailView in M3.
struct ItemDetailPlaceholderView: View {
    let itemId: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var items: [CollectionItem]

    private var item: CollectionItem? {
        items.first { $0.id == itemId }
    }

    var body: some View {
        if let item {
            List {
                Section("Info") {
                    LabeledContent("Title", value: item.title)
                    LabeledContent("Collection", value: item.collectionName)
                    if let value = item.formattedEstimatedValue {
                        LabeledContent("Estimated Value", value: value)
                    }
                }

                Section("Description") {
                    Text(item.itemDescription.isEmpty ? "No description" : item.itemDescription)
                        .foregroundStyle(item.itemDescription.isEmpty ? .secondary : .primary)
                }

                Section("Tags") {
                    if item.tags.isEmpty {
                        Text("No tags")
                            .foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(item.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(.tint.opacity(0.15), in: Capsule())
                            }
                        }
                    }
                }

                Section("3D Model") {
                    Label(
                        item.modelFileName ?? "No model yet",
                        systemImage: item.modelFileName != nil ? "cube.fill" : "cube"
                    )
                    .foregroundStyle(item.modelFileName != nil ? .primary : .secondary)
                }

                Section("Metadata") {
                    LabeledContent("Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Updated", value: item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Photos", value: "\(item.photoAttachments.count)")
                    LabeledContent("Voice Memos", value: "\(item.voiceMemos.count)")
                    LabeledContent("Notes", value: "\(item.textMemories.count)")
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Item Not Found", systemImage: "exclamationmark.triangle")
        }
    }
}

/// Simple horizontal flow layout for tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { break }
            let position = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}

#Preview {
    ShelfView()
        .modelContainer(SampleData.previewContainer)
}
