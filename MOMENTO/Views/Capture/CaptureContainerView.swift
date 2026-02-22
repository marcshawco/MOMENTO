import RealityKit
import SwiftData
import SwiftUI

/// Full-screen capture flow: device check → guided capture → reconstruction → save.
struct CaptureContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CaptureViewModel()
    @State private var showCancelConfirmation = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            captureContent
        }
        .task {
            viewModel.configure(modelContext: modelContext)
            viewModel.startSession()
        }
        .onChange(of: viewModel.createdItemId) {
            // Dismiss after successful save (small delay for user to see success)
            if viewModel.createdItemId != nil {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    dismiss()
                }
            }
        }
        .confirmationDialog(
            "Cancel Scan?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel Scan", role: .destructive) {
                viewModel.cancel()
                dismiss()
            }
            Button("Continue Scanning", role: .cancel) {}
        } message: {
            Text("Your captured data will be lost.")
        }
    }

    // MARK: - Content Router

    @ViewBuilder
    private var captureContent: some View {
        switch viewModel.flowState {
        case .idle, .initializing:
            initializingView

        case .ready, .detecting, .capturing, .finishing:
            objectCaptureContent

        case .completed:
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Preparing 3D reconstruction...")
                    .foregroundStyle(.white)
            }

        case .reconstructing(let progress):
            ReconstructionProgressView(progress: progress)

        case .generatingThumbnail:
            ReconstructionProgressView(
                progress: 1.0,
                statusText: "Generating preview..."
            )

        case .saved:
            captureSuccessView

        case .failed(let error):
            captureErrorView(error: error)

        case .unsupported(let reason):
            unsupportedDeviceView(reason: reason)
        }
    }

    // MARK: - Initializing View

    private var initializingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("Initializing camera...")
                .foregroundStyle(.white)
        }
    }

    // MARK: - Object Capture View

    @ViewBuilder
    private var objectCaptureContent: some View {
        if let session = viewModel.session {
            ZStack {
                // Apple's guided capture view
                ObjectCaptureView(session: session) {
                    // Camera feed overlay: feedback + controls
                    captureOverlay
                }

                // Top bar with cancel + shot count
                VStack {
                    captureTopBar
                    Spacer()
                    captureBottomBar
                }
            }
        }
    }

    private var captureOverlay: some View {
        VStack {
            Spacer()

            // Feedback messages
            if !viewModel.feedbackMessages.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(viewModel.feedbackMessages), id: \.self) { feedback in
                        HStack(spacing: 8) {
                            Image(systemName: feedback.systemImage)
                            Text(feedback.userMessage)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    private var captureTopBar: some View {
        HStack {
            Button {
                if viewModel.numberOfShotsTaken > 0 {
                    showCancelConfirmation = true
                } else {
                    viewModel.cancel()
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.5), in: Circle())
            }

            Spacer()

            // Shot counter
            if viewModel.numberOfShotsTaken > 0 {
                Text("\(viewModel.numberOfShotsTaken) shots")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5), in: Capsule())
            }
        }
        .padding()
    }

    private var captureBottomBar: some View {
        Group {
            if viewModel.userCompletedScanPass {
                Button {
                    viewModel.finishCapture()
                } label: {
                    Label("Finish Capture", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(.green.gradient, in: Capsule())
                }
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.userCompletedScanPass)
    }

    // MARK: - Success View

    private var captureSuccessView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Scan Complete!")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("Your 3D model has been saved.")
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Error View

    private func captureErrorView(error: CaptureError) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Something Went Wrong")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 32)

            HStack(spacing: 16) {
                Button("Dismiss") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(.white)

                Button("Retry") { viewModel.retry() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Unsupported Device View

    private func unsupportedDeviceView(reason: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Device Not Supported")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(reason)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 32)

            #if DEBUG
            // Development fallback: create test item without scanning
            Button("Create Test Item (Dev Only)") {
                createTestItem()
            }
            .buttonStyle(.borderedProminent)
            #endif

            Button("Dismiss") { dismiss() }
                .buttonStyle(.bordered)
                .tint(.white)
        }
    }

    #if DEBUG
    private func createTestItem() {
        let item = CollectionItem(
            title: "Test Item \(Int.random(in: 100...999))",
            itemDescription: "Created from unsupported device fallback.",
            tags: ["test"],
            collectionName: "Testing",
            estimatedValue: Double.random(in: 25...500).rounded()
        )
        modelContext.insert(item)
        dismiss()
    }
    #endif
}
