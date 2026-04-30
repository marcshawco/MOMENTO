import SwiftUI
import SwiftData
import os

struct ShelfView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CollectionItem.updatedAt, order: .reverse) private var items: [CollectionItem]
    @AppStorage(AppConstants.UserDefaultsKeys.preferredSortOrder) private var preferredSortOrderRaw = SortOrder.recentFirst.rawValue

    @State private var searchText = ""
    @State private var showingSettings = false
    @State private var showingAddItem = false
    @State private var sortOrder: SortOrder = .recentFirst
    @State private var filterTag: String?
    @State private var filterCollection: String?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momento", category: "Shelf")

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
                    filterMenu
                }
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
                ItemDetailView(itemId: itemId)
            }
            .onAppear {
                if let stored = SortOrder(rawValue: preferredSortOrderRaw) {
                    sortOrder = stored
                }
            }
            .onChange(of: sortOrder) {
                preferredSortOrderRaw = sortOrder.rawValue
            }
        }
    }

    // MARK: - Subviews

    private var shelfGrid: some View {
        ScrollView {
            activeFiltersView

            if filteredAndSortedItems.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Items", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Try clearing filters or adjusting your search.")
                } actions: {
                    Button("Clear Filters") {
                        clearFilters()
                    }
                }
                .padding(.top, 60)
            } else {
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
    }

    @ViewBuilder
    private var activeFiltersView: some View {
        if filterTag != nil || filterCollection != nil {
            HStack(spacing: 8) {
                if let filterTag {
                    filterPill(title: "Tag: \(filterTag)") {
                        self.filterTag = nil
                    }
                }

                if let filterCollection {
                    filterPill(title: "Collection: \(filterCollection)") {
                        self.filterCollection = nil
                    }
                }

                Button("Clear All") {
                    clearFilters()
                }
                .font(.caption.weight(.semibold))
            }
            .padding(.horizontal)
            .padding(.top, 10)
        }
    }

    private func filterPill(title: String, onClear: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)

            Button {
                onClear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
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

    private var filterMenu: some View {
        Menu {
            Section("Collections") {
                Button("All Collections") {
                    filterCollection = nil
                }
                ForEach(allCollectionNames, id: \.self) { collection in
                    Button {
                        filterCollection = collection
                    } label: {
                        if filterCollection == collection {
                            Label(collection, systemImage: "checkmark")
                        } else {
                            Text(collection)
                        }
                    }
                }
            }

            Section("Tags") {
                Button("All Tags") {
                    filterTag = nil
                }
                ForEach(allTags, id: \.self) { tag in
                    Button {
                        filterTag = tag
                    } label: {
                        if filterTag == tag {
                            Label(tag, systemImage: "checkmark")
                        } else {
                            Text(tag)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter items")
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

        if let filterCollection {
            result = result.filter { $0.collectionName == filterCollection }
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
        let fileNames = FileStorageService.shared.fileNames(for: item)
        modelContext.delete(item)
        do {
            try modelContext.save()
            fileNames.forEach { FileStorageService.shared.deleteFile(fileName: $0) }
        } catch {
            logger.error("Failed to delete item from SwiftData: \(error.localizedDescription)")
        }
    }

    private func clearFilters() {
        filterTag = nil
        filterCollection = nil
    }

    private var allTags: [String] {
        Array(Set(items.flatMap(\.tags)))
            .filter { !$0.isEmpty }
            .sorted()
    }

    private var allCollectionNames: [String] {
        Array(Set(items.map(\.collectionName)))
            .filter { !$0.isEmpty }
            .sorted()
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

#Preview {
    ShelfView()
        .modelContainer(SampleData.previewContainer)
}
