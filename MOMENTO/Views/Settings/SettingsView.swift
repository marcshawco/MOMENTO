import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppConstants.UserDefaultsKeys.isFaceIDEnabled) private var isFaceIDEnabled = false
    @AppStorage(AppConstants.UserDefaultsKeys.enableOnDeviceSuggestions) private var enableOnDeviceSuggestions = true
    @AppStorage(AppConstants.UserDefaultsKeys.enableCloudSuggestions) private var enableCloudSuggestions = false
    @AppStorage(AppConstants.UserDefaultsKeys.cloudSuggestionEndpoint) private var cloudSuggestionEndpoint = ""
    @Query private var items: [CollectionItem]

    @State private var isExporting = false
    @State private var exportMessage = ""
    @State private var shareURL: URL?
    @State private var showingShareSheet = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Security") {
                    Toggle(isOn: $isFaceIDEnabled) {
                        Label("Require Face ID", systemImage: "faceid")
                    }
                }

                Section("AI Assist") {
                    Toggle(isOn: $enableOnDeviceSuggestions) {
                        Label("On-Device Object Suggestions", systemImage: "cpu")
                    }

                    Toggle(isOn: $enableCloudSuggestions) {
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
                if let shareURL {
                    ShareSheetView(activityItems: [shareURL])
                }
            }
            .alert("Export Error", isPresented: .constant(exportError != nil)) {
                Button("OK") { exportError = nil }
            } message: {
                if let exportError {
                    Text(exportError)
                }
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
                shareURL = url
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
                shareURL = url
                isExporting = false
                showingShareSheet = true
            } catch {
                isExporting = false
                exportError = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

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
