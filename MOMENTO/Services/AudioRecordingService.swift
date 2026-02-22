import AVFoundation
import os

/// Manages audio recording and playback for voice memos.
/// MainActor-isolated (default) because it drives UI state and uses timers.
@Observable
final class AudioRecordingService {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momento", category: "Audio")

    // MARK: - Observable State

    var isRecording = false
    var isPlaying = false
    var recordingDuration: TimeInterval = 0
    var playbackProgress: Double = 0
    var currentPlaybackTime: TimeInterval = 0
    var totalPlaybackDuration: TimeInterval = 0
    var currentlyPlayingFileName: String?

    // MARK: - Internal State

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timerTask: Task<Void, Never>?
    private var currentRecordingURL: URL?

    // MARK: - Recording

    /// Starts recording a voice memo. Creates a new file in the VoiceMemos temp area.
    func startRecording() throws {
        stopPlayback()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)

        let url = try FileStorageService.shared.voiceMemosDirectory()
            .appendingPathComponent("\(UUID().uuidString).\(AppConstants.Audio.fileExtension)")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: AppConstants.Audio.sampleRate,
            AVNumberOfChannelsKey: AppConstants.Audio.numberOfChannels,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: AppConstants.Audio.bitRate,
        ]

        let audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder.record()

        recorder = audioRecorder
        currentRecordingURL = url
        isRecording = true
        recordingDuration = 0

        startRecordingTimer()
        logger.info("Recording started: \(url.lastPathComponent)")
    }

    /// Stops the current recording. Returns the file URL and duration, or nil if not recording.
    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard let recorder, let url = currentRecordingURL else { return nil }

        let duration = recorder.currentTime
        recorder.stop()

        timerTask?.cancel()
        timerTask = nil
        self.recorder = nil
        isRecording = false

        deactivateSession()
        logger.info("Recording stopped. Duration: \(String(format: "%.1f", duration))s")

        return (url, duration)
    }

    // MARK: - Playback

    /// Plays audio from the given file URL.
    func play(url: URL) throws {
        stopPlayback()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)

        let audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer.play()

        player = audioPlayer
        isPlaying = true
        totalPlaybackDuration = audioPlayer.duration

        startPlaybackTimer()
        logger.info("Playback started: \(url.lastPathComponent)")
    }

    /// Stops any current playback.
    func stopPlayback() {
        player?.stop()
        player = nil
        timerTask?.cancel()
        timerTask = nil
        isPlaying = false
        playbackProgress = 0
        currentPlaybackTime = 0
        currentlyPlayingFileName = nil
        deactivateSession()
    }

    // MARK: - Timers

    private func startRecordingTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled else { return }
                self.recordingDuration = self.recorder?.currentTime ?? 0
            }
        }
    }

    private func startPlaybackTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { return }
                guard let player = self.player else { return }

                if player.isPlaying {
                    self.currentPlaybackTime = player.currentTime
                    self.playbackProgress = player.duration > 0
                        ? player.currentTime / player.duration
                        : 0
                } else {
                    // Playback finished naturally
                    self.stopPlayback()
                    return
                }
            }
        }
    }

    // MARK: - Helpers

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Formatted recording duration string (M:SS).
    static func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
