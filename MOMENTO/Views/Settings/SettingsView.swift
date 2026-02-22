import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppConstants.UserDefaultsKeys.isFaceIDEnabled) private var isFaceIDEnabled = false

    var body: some View {
        NavigationStack {
            List {
                Section("Security") {
                    Toggle(isOn: $isFaceIDEnabled) {
                        Label("Require Face ID", systemImage: "faceid")
                    }
                    // M4: AuthenticationService will enforce this on foreground entry.
                }

                Section("Data") {
                    Button {
                        // M4: Export functionality
                    } label: {
                        Label("Export Insurance Report", systemImage: "doc.text")
                    }

                    Button {
                        // M4: Export ZIP
                    } label: {
                        Label("Export All Data", systemImage: "square.and.arrow.up")
                    }
                }

                Section("Storage") {
                    let diskSpace = FileStorageService.shared.availableDiskSpaceMB()
                    LabeledContent("Available Space") {
                        Text(diskSpace >= 1024
                             ? String(format: "%.1f GB", Double(diskSpace) / 1024.0)
                             : "\(diskSpace) MB")
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
        }
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
}
