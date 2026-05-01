import RealityKit
import SwiftData
import SwiftUI

/// Full-screen capture flow: device check → guided capture → reconstruction → save.
struct CaptureContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = CaptureViewModel()
    @State private var showCancelConfirmation = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            captureContent
        }
        .task {
            viewModel.configure(modelContext: modelContext)
            await viewModel.startSession()
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
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                viewModel.handleBackgroundTransition()
            }
        }
    }

    // MARK: - Content Router

    @ViewBuilder
    private var captureContent: some View {
        switch viewModel.flowState {
        case .idle:
            initializingView

        case .initializing, .ready, .detecting, .capturing, .finishing:
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
                    EmptyView()
                }

                captureTopBar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                captureBottomBar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                if case .initializing = viewModel.flowState {
                    VStack {
                        Spacer()
                        ProgressView("Initializing camera...")
                            .tint(.white)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.bottom, 24)
                    }
                }
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
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.5), in: Circle())
            }

            Spacer()

            HStack(spacing: 8) {
                // Shot counter
                if viewModel.numberOfShotsTaken > 0 {
                    Text("\(viewModel.numberOfShotsTaken) shots")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                }

                if viewModel.isTorchSupported {
                    Button {
                        viewModel.toggleTorch()
                    } label: {
                        Image(systemName: viewModel.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(viewModel.isTorchOn ? .yellow : .white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    .accessibilityLabel(viewModel.isTorchOn ? "Turn flashlight off" : "Turn flashlight on")
                }
            }
        }
        .padding()
    }

    private var captureBottomBar: some View {
        VStack(spacing: 12) {
            if viewModel.shouldShowStartScanButton {
                Button {
                    viewModel.beginUserScan()
                } label: {
                    Label(viewModel.startScanButtonTitle, systemImage: "viewfinder.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            (viewModel.canStartScan ? Color.blue : Color.gray)
                                .gradient,
                            in: Capsule()
                        )
                }
                .disabled(!viewModel.canStartScan)
                .opacity(viewModel.canStartScan ? 1 : 0.7)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if viewModel.shouldShowAreaModeButton {
                Button {
                    viewModel.startAreaModeCapture()
                } label: {
                    Label("Handheld Scan", systemImage: "rotate.3d")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.orange.gradient, in: Capsule())
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityHint("Use for small objects. Keep the object centered and rotate it slowly while capturing all sides.")
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Coverage")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(viewModel.estimatedCaptureProgressPercentText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                ProgressView(value: viewModel.estimatedCaptureProgress, total: 1)
                    .tint(viewModel.userCompletedScanPass ? .green : .blue)

                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.canRequestImageCapture ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(viewModel.planeStatusText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: viewModel.currentGuidance.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(guidanceAccentColor)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Next step: \(viewModel.currentGuidance.title)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(viewModel.currentGuidance.detail)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(guidanceAccentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))

            if viewModel.shouldShowResetDetectionButton || viewModel.shouldShowManualCaptureButton {
                HStack(spacing: 10) {
                    if viewModel.shouldShowResetDetectionButton {
                        Button {
                            viewModel.resetDetectionAndRetry()
                        } label: {
                            Label("Reset Detection", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.orange.gradient, in: Capsule())
                        }
                    }

                    if viewModel.shouldShowManualCaptureButton {
                        Button {
                            viewModel.requestSingleImageCapture()
                        } label: {
                            Label("Capture Shot", systemImage: "camera.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.blue.gradient, in: Capsule())
                        }
                    }
                }
            }

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
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
        .animation(.spring(duration: 0.3), value: viewModel.userCompletedScanPass)
        .animation(.spring(duration: 0.3), value: viewModel.shouldShowStartScanButton)
    }

    private var guidanceAccentColor: Color {
        switch viewModel.currentGuidance.severity {
        case .critical:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        case .success:
            return .green
        }
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
