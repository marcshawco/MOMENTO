import SwiftUI

/// Voice memo tab: record, list with playback progress, delete.
struct VoiceMemosTabView: View {

    @Bindable var viewModel: ItemDetailViewModel
    @State private var audioService = AudioRecordingService()
    @State private var recordingError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            recordingControls
            memoList
        }
    }

    // MARK: - Recording Controls

    private var recordingControls: some View {
        HStack {
            if audioService.isRecording {
                // Red pulsing indicator + duration
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                        .opacity(audioService.recordingDuration.truncatingRemainder(dividingBy: 1) > 0.5 ? 1 : 0.4)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: audioService.isRecording)

                    Text(AudioRecordingService.formatDuration(audioService.recordingDuration))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.red)
                }

                Spacer()

                Button {
                    finishRecording()
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.red)
                }
            } else {
                Button {
                    startRecording()
                } label: {
                    Label("Record Memo", systemImage: "mic.circle.fill")
                        .font(.subheadline.weight(.medium))
                }

                if let recordingError {
                    Text(recordingError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.leading, 8)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Memo List

    @ViewBuilder
    private var memoList: some View {
        if let memos = viewModel.item?.voiceMemos.sorted(by: { $0.createdAt > $1.createdAt }),
           !memos.isEmpty
        {
            ForEach(memos) { memo in
                voiceMemoRow(memo)
            }
        } else if !audioService.isRecording {
            ContentUnavailableView {
                Label("No Voice Memos", systemImage: "waveform")
            } description: {
                Text("Tap Record to add a voice memo.")
            }
            .frame(height: 120)
        }
    }

    private func voiceMemoRow(_ memo: VoiceMemo) -> some View {
        HStack(spacing: 12) {
            // Play/stop toggle
            Button {
                togglePlayback(for: memo)
            } label: {
                Image(systemName: isPlaying(memo) ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(memo.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)

                if isPlaying(memo) {
                    ProgressView(value: audioService.playbackProgress)
                        .tint(.accentColor)
                } else {
                    Text(memo.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(role: .destructive) {
                audioService.stopPlayback()
                viewModel.deleteVoiceMemo(memo)
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func startRecording() {
        recordingError = nil
        do {
            try audioService.startRecording()
        } catch {
            recordingError = "Mic unavailable"
        }
    }

    private func finishRecording() {
        guard let result = audioService.stopRecording() else { return }
        do {
            try viewModel.addVoiceMemo(fileURL: result.url, duration: result.duration)
        } catch {
            recordingError = "Save failed"
        }
    }

    private func togglePlayback(for memo: VoiceMemo) {
        if isPlaying(memo) {
            audioService.stopPlayback()
        } else {
            guard let url = try? FileStorageService.shared.resolveURL(for: memo.fileName) else { return }
            do {
                audioService.currentlyPlayingFileName = memo.fileName
                try audioService.play(url: url)
            } catch {
                audioService.stopPlayback()
            }
        }
    }

    private func isPlaying(_ memo: VoiceMemo) -> Bool {
        audioService.isPlaying && audioService.currentlyPlayingFileName == memo.fileName
    }
}
