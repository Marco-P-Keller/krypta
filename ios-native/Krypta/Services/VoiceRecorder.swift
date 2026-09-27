import AVFoundation
import Foundation
import Observation

/// Sprachnachrichten aufnehmen: AAC, mono, 32 kbit/s, höchstens fünf Minuten.
/// Die Aufnahme liegt nur so lange als Datei vor, bis sie verschickt oder
/// verworfen ist (im Ordner, den AttachmentPreparer beim Sperren leert).
@MainActor
@Observable
final class VoiceRecorder {
    static let maxDuration: TimeInterval = 5 * 60

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var denied = false
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var url: URL?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// Mikrofon erlauben (einmalig) und aufnehmen.
    func start() async {
        guard !isRecording else { return }
        let session = AVAudioApplication.shared
        if session.recordPermission == .undetermined {
            // Die Frage des Systems ist kein Verlassen der App.
            let granted = await SystemPrompt.during { await AVAudioApplication.requestRecordPermission() }
            guard granted else { denied = true; return }
        }
        guard session.recordPermission == .granted else { denied = true; return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
            let target = try AttachmentPreparer.temporaryURL(ext: "m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
            ]
            let recorder = try AVAudioRecorder(url: target, settings: settings)
            guard recorder.record(forDuration: Self.maxDuration) else { return }
            self.recorder = recorder
            url = target
            isRecording = true
            elapsed = 0
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard let self, let r = self.recorder else { return }
                    self.elapsed = r.currentTime
                    if !r.isRecording { return }
                }
            }
        } catch {
            cancel()
        }
    }

    /// Aufnahme beenden: Datei und Dauer, oder `nil`, wenn nichts da ist.
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard let recorder, let url else { return nil }
        let duration = max(recorder.currentTime, elapsed)
        recorder.stop()
        finish()
        return duration >= 0.5 ? (url, duration) : nil
    }

    /// Verwerfen: die Datei ist sofort weg.
    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        if let url { try? FileManager.default.removeItem(at: url) }
        finish()
    }

    private func finish() {
        ticker?.cancel()
        ticker = nil
        recorder = nil
        url = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Spielt eine Sprachnachricht direkt aus dem Speicher ab, ohne Datei.
@MainActor
@Observable
final class VoicePlayer {
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    func toggle(_ data: Data) {
        if isPlaying { return pause() }
        do {
            if player == nil {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
                player = try AVAudioPlayer(data: data)
            }
            guard let player else { return }
            player.play()
            isPlaying = true
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard let self, let p = self.player else { return }
                    self.progress = p.duration > 0 ? p.currentTime / p.duration : 0
                    if !p.isPlaying {
                        self.isPlaying = false
                        if self.progress > 0.98 || p.currentTime == 0 { self.progress = 0 }
                        return
                    }
                }
            }
        } catch {
            isPlaying = false
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        ticker?.cancel()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        progress = 0
        ticker?.cancel()
    }
}
