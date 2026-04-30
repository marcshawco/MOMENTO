import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppConstants.UserDefaultsKeys.isFaceIDEnabled) private var isFaceIDEnabled = false
    @AppStorage(AppConstants.UserDefaultsKeys.enableOnDeviceSuggestions) private var enableOnDeviceSuggestions = true
    @AppStorage(AppConstants.UserDefaultsKeys.enableCloudSuggestions) private var enableCloudSuggestions = false
    @AppStorage(AppConstants.UserDefaultsKeys.cloudSuggestionEndpoint) private var cloudSuggestionEndpoint = ""
    @Query private var items: [CollectionItem]

    @State private var authService = AuthenticationService()
    @State private var isExporting = false
    @State private var exportMessage = ""
    @State private var shareURLs: [URL] = []
    @State private var showingShareSheet = false
    @State private var exportError: String?
    @State private var cleanupMessage: String?
    @State private var securityMessage: String?
    @State private var showingCloudConsent = false

    var body: some View {
        NavigationStack {
            List {
                Section("Security") {
                    Toggle(isOn: faceIDBinding) {
                        Label("Require Face ID", systemImage: "faceid")
                    }
                }

                Section("AI Assist") {
                    Toggle(isOn: $enableOnDeviceSuggestions) {
                        Label("On-Device Object Suggestions", systemImage: "cpu")
                    }

                    Toggle(isOn: cloudSuggestionsBinding) {
                        Label("Cloud Suggestions (Optional)", systemImage: "icloud")
                    }

                    if enableCloudSuggestions {
                        TextField(
                            "Cloud endpoint URL",
                            text: $cloudSuggestionEndpoint,
                            prompt: Text("https://example.com/suggest")
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    }

                    Text(enableCloudSuggestions
                         ? "If enabled, Momento sends one downsampled image to your endpoint for metadata suggestions."
                         : "All object suggestions stay on-device unless cloud suggestions are explicitly enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Data") {
                    Button {
                        exportPDF()
                    } label: {
                        Label("Export Insurance Report", systemImage: "doc.text")
                    }
                    .disabled(items.isEmpty || isExporting)

                    Button {
                        exportCSV()
                    } label: {
                        Label("Export as CSV", systemImage: "tablecells")
                    }
                    .disabled(items.isEmpty || isExporting)

                    Button {
                        exportDataArchive()
                    } label: {
                        Label("Export Data + Assets", systemImage: "archivebox")
                    }
                    .disabled(items.isEmpty || isExporting)

                    if items.isEmpty {
                        Text("Add items to enable export")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Storage") {
                    let diskSpace = FileStorageService.shared.availableDiskSpaceMB()
                    LabeledContent("Available Space") {
                        Text(diskSpace >= 1024
                             ? String(format: "%.1f GB", Double(diskSpace) / 1024.0)
                             : "\(diskSpace) MB")
                    }

                    LabeledContent("Items") {
                        Text("\(items.count)")
                    }

                    Button {
                        cleanupTemporaryFiles()
                    } label: {
                        Label("Remove Temporary Files", systemImage: "trash")
                    }

                    Button {
                        cleanupUnreferencedFiles()
                    } label: {
                        Label("Clean Unreferenced Assets", systemImage: "externaldrive.badge.xmark")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if isExporting {
                    ExportProgressView(message: exportMessage)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if !shareURLs.isEmpty {
                    ShareSheetView(activityItems: shareURLs)
                }
            }
            .alert("Export Error", isPresented: .constant(exportError != nil)) {
                Button("OK") { exportError = nil }
            } message: {
                if let exportError {
                    Text(exportError)
                }
            }
            .alert("Storage Cleanup", isPresented: .constant(cleanupMessage != nil)) {
                Button("OK") { cleanupMessage = nil }
            } message: {
                if let cleanupMessage {
                    Text(cleanupMessage)
                }
            }
            .alert("Security", isPresented: .constant(securityMessage != nil)) {
                Button("OK") { securityMessage = nil }
            } message: {
                if let securityMessage {
                    Text(securityMessage)
                }
            }
            .alert("Enable Cloud Suggestions?", isPresented: $showingCloudConsent) {
                Button("Cancel", role: .cancel) {
                    enableCloudSuggestions = false
                }
                Button("Enable") {
                    enableCloudSuggestions = true
                }
            } message: {
                Text("Momento will send one downsampled image from a scan to your configured HTTPS endpoint when on-device suggestions are unavailable or low-confidence.")
            }
        }
    }

    // MARK: - Export Actions

    private func exportPDF() {
        isExporting = true
        exportMessage = "Generating PDF report..."

        Task {
            do {
                let url = try ExportService.shared.generatePDFReport(items: Array(items))
                shareURLs = [url]
                isExporting = false
                showingShareSheet = true
            } catch {
                isExporting = false
                exportError = error.localizedDescription
            }
        }
    }

    private func exportCSV() {
        isExporting = true
        exportMessage = "Generating CSV catalog..."

        Task {
            do {
                let url = try ExportService.shared.generateCSV(items: Array(items))
                shareURLs = [url]
                isExporting = false
                showingShareSheet = true
            } catch {
                isExporting = false
                exportError = error.localizedDescription
            }
        }
    }

    private func exportDataArchive() {
        isExporting = true
        exportMessage = "Preparing JSON manifest and assets..."

        Task {
            do {
                let urls = try ExportService.shared.generateDataArchive(items: Array(items))
                shareURLs = urls
                isExporting = false
                showingShareSheet = true
            } catch {
                isExporting = false
                exportError = error.localizedDescription
            }
        }
    }

    private func cleanupTemporaryFiles() {
        ExportService.shared.cleanupExportFiles()
        let summary = FileStorageService.shared.cleanupAllCaptureTemp()
        cleanupMessage = formattedCleanupMessage(summary: summary, fallback: "Temporary export files were removed.")
    }

    private func cleanupUnreferencedFiles() {
        let summary = FileStorageService.shared.cleanupUnreferencedFiles(
            referencedFileNames: referencedFileNames
        )
        cleanupMessage = formattedCleanupMessage(summary: summary, fallback: "No unreferenced asset files were found.")
    }

    // MARK: - Helpers

    private var faceIDBinding: Binding<Bool> {
        Binding(
            get: { isFaceIDEnabled },
            set: { newValue in
                handleFaceIDToggle(newValue)
            }
        )
    }

    private var cloudSuggestionsBinding: Binding<Bool> {
        Binding(
            get: { enableCloudSuggestions },
            set: { newValue in
                if newValue {
                    showingCloudConsent = true
                } else {
                    enableCloudSuggestions = false
                }
            }
        )
    }

    private func handleFaceIDToggle(_ newValue: Bool) {
        guard newValue else {
            isFaceIDEnabled = false
            return
        }

        Task {
            if await authService.verifyBiometricBeforeEnabling() {
                isFaceIDEnabled = true
            } else {
                isFaceIDEnabled = false
                securityMessage = authService.authError ?? "Momento could not verify your identity."
            }
        }
    }

    private var referencedFileNames: Set<String> {
        var fileNames = Set<String>()
        for item in items {
            if let modelFileName = item.modelFileName {
                fileNames.insert(modelFileName)
            }
            if let thumbnailFileName = item.thumbnailFileName {
                fileNames.insert(thumbnailFileName)
            }
            item.photoAttachments.forEach { fileNames.insert($0.fileName) }
            item.voiceMemos.forEach { fileNames.insert($0.fileName) }
        }
        return fileNames
    }

    private func formattedCleanupMessage(summary: StorageCleanupSummary, fallback: String) -> String {
        guard summary.deletedFiles > 0 else { return fallback }
        return String(
            format: "Removed %d files and reclaimed %.1f MB.",
            summary.deletedFiles,
            summary.reclaimedMegabytes
        )
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

#Preview {
    SettingsView()
        .modelContainer(SampleData.previewContainer)
}
