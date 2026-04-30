import SwiftData
import SwiftUI
import os

// MARK: - Attachment Tab

enum AttachmentTab: String, CaseIterable, Identifiable {
    case photos
    case voiceMemos
    case notes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .photos: "Photos"
        case .voiceMemos: "Voice Memos"
        case .notes: "Notes"
        }
    }
}

// MARK: - ItemDetailViewModel

/// Central view model for the item detail screen.
/// Buffers editable fields and auto-saves to SwiftData after a debounce period.
@MainActor
@Observable
final class ItemDetailViewModel {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momento", category: "ItemDetail")

    // MARK: - Buffered Editing Fields

    var title: String = ""
    var itemDescription: String = ""
    var tags: [String] = []
    var collectionName: String = ""
    var purchaseDate: Date?
    var purchasePrice: Double?
    var estimatedValue: Double?
    var serialNumber: String = ""
    var provenanceNotes: String = ""

    // MARK: - UI State

    var showingARQuickLook = false
    var showingDeleteConfirmation = false
    var activeAttachmentTab: AttachmentTab = .photos
    var tagInput: String = ""

    // MARK: - Data References

    private(set) var item: CollectionItem?
    private var modelContext: ModelContext?
    private var autoSaveTask: Task<Void, Never>?

    // MARK: - Configuration

    /// Binds this view model to a SwiftData item. Must be called before use.
    func configure(item: CollectionItem, modelContext: ModelContext) {
        self.item = item
        self.modelContext = modelContext
        loadFromItem()
    }

    /// Copies SwiftData fields into the buffered editing fields.
    private func loadFromItem() {
        guard let item else { return }
        title = item.title
        itemDescription = item.itemDescription
        tags = item.tags
        collectionName = item.collectionName
        purchaseDate = item.purchaseDate
        purchasePrice = item.purchasePrice
        estimatedValue = item.estimatedValue
        serialNumber = item.serialNumber ?? ""
        provenanceNotes = item.provenanceNotes ?? ""
    }

    // MARK: - Auto-Save

    /// Schedules a debounced write-back of buffered fields to SwiftData.
    func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppConstants.Detail.autoSaveDebounce))
            guard let self, !Task.isCancelled else { return }
            self.saveToItem()
        }
    }

    /// Immediately saves buffered fields (e.g. on disappear).
    func saveIfNeeded() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        saveToItem()
    }

    private func saveToItem() {
        guard let item else { return }
        item.title = title.isEmpty ? "Untitled" : title
        item.itemDescription = itemDescription
        item.tags = tags
        item.collectionName = collectionName
        item.purchaseDate = purchaseDate
        item.purchasePrice = purchasePrice
        item.estimatedValue = estimatedValue
        item.serialNumber = serialNumber.isEmpty ? nil : serialNumber
        item.provenanceNotes = provenanceNotes.isEmpty ? nil : provenanceNotes
        item.touch()
        saveContextOrLog(operation: "save metadata")
        logger.info("Auto-saved item: \(item.title)")
    }

    // MARK: - Tags

    func addTag() {
        let tag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !tag.isEmpty, !tags.contains(tag) else {
            tagInput = ""
            return
        }
        tags.append(tag)
        tagInput = ""
        scheduleAutoSave()
    }

    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
        scheduleAutoSave()
    }

    // MARK: - Photos

    func addPhoto(data: Data) throws {
        guard let item else { return }
        let fileName = try PhotoImportService.shared.importPhoto(imageData: data)
        let attachment = PhotoAttachment(fileName: fileName, item: item)
        modelContext?.insert(attachment)
        item.touch()
        saveContextOrLog(operation: "add photo")
        logger.info("Photo added to item \(item.id)")
    }

    func deletePhoto(_ photo: PhotoAttachment) {
        FileStorageService.shared.deleteFile(fileName: photo.fileName)
        modelContext?.delete(photo)
        item?.touch()
        saveContextOrLog(operation: "delete photo")
    }

    func updatePhotoCaption(_ photo: PhotoAttachment, caption: String) {
        photo.caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        item?.touch()
        saveContextOrLog(operation: "update photo caption")
    }

    // MARK: - Voice Memos

    func addVoiceMemo(fileURL: URL, duration: TimeInterval) throws {
        guard let item else { return }
        let fileName = try FileStorageService.shared.moveFile(
            from: fileURL,
            directory: AppConstants.Storage.voiceMemosFolder,
            fileName: "\(UUID().uuidString).\(AppConstants.Audio.fileExtension)"
        )
        let memo = VoiceMemo(fileName: fileName, duration: duration, item: item)
        modelContext?.insert(memo)
        item.touch()
        saveContextOrLog(operation: "add voice memo")
        logger.info("Voice memo added: \(fileName)")
    }

    func deleteVoiceMemo(_ memo: VoiceMemo) {
        FileStorageService.shared.deleteFile(fileName: memo.fileName)
        modelContext?.delete(memo)
        item?.touch()
        saveContextOrLog(operation: "delete voice memo")
    }

    // MARK: - Notes

    func addNote(body: String) {
        guard let item else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = TextMemory(body: trimmed, item: item)
        modelContext?.insert(note)
        item.touch()
        saveContextOrLog(operation: "add note")
    }

    func updateNote(_ note: TextMemory, body: String) {
        note.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        item?.touch()
        saveContextOrLog(operation: "update note")
    }

    func deleteNote(_ note: TextMemory) {
        modelContext?.delete(note)
        item?.touch()
        saveContextOrLog(operation: "delete note")
    }

    // MARK: - Item Deletion

    func deleteItem() {
        guard let item, let modelContext else { return }
        FileStorageService.shared.deleteFiles(for: item)
        modelContext.delete(item)
        saveContextOrLog(operation: "delete item")
        logger.info("Item deleted: \(item.id)")
    }

    // MARK: - File URLs

    /// Resolved URL for the 3D model file, if it exists.
    var modelURL: URL? {
        guard let fileName = item?.modelFileName else { return nil }
        return try? FileStorageService.shared.resolveURL(for: fileName)
    }

    /// Resolved URL for the thumbnail image, if it exists.
    var thumbnailURL: URL? {
        guard let fileName = item?.thumbnailFileName else { return nil }
        return try? FileStorageService.shared.resolveURL(for: fileName)
    }

    // MARK: - Export

    /// Whether an export is currently in progress.
    var isExporting = false

    /// URL of the last exported file, used to present the share sheet.
    var exportedFileURL: URL?

    /// Whether to show the share sheet.
    var showingShareSheet = false

    /// Generates a single-item PDF and presents the share sheet.
    func exportAsPDF() {
        guard let item else { return }
        saveIfNeeded()
        isExporting = true

        Task {
            do {
                let url = try ExportService.shared.generateSingleItemPDF(item: item)
                exportedFileURL = url
                isExporting = false
                showingShareSheet = true
            } catch {
                isExporting = false
                logger.error("Export PDF failed: \(error.localizedDescription)")
            }
        }
    }

    private func saveContextOrLog(operation: String) {
        guard let modelContext else {
            logger.error("ModelContext unavailable during \(operation)")
            return
        }

        do {
            try modelContext.save()
        } catch {
            logger.error("SwiftData save failed during \(operation): \(error.localizedDescription)")
        }
    }
}
