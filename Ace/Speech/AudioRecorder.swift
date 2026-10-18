import AVFoundation
import Foundation
import Observation

/// Records the microphone to a 16 kHz mono WAV file, which is the format the
/// speech engines want. Nothing is uploaded; the file stays on the device.
@MainActor
@Observable
final class AudioRecorder {
    enum State: Equatable {
        case idle
        case recording
        case denied
        case failed(String)
    }

    private(set) var state: State = .idle
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?

    var isRecording: Bool { state == .recording }

    /// Asks for microphone permission the first time. Returns false if denied.
    func requestPermission() async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        if !granted { state = .denied }
        return granted
    }

    func start(to url: URL) {
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            #endif

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16_000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            guard newRecorder.record() else {
                state = .failed("The microphone did not start.")
                return
            }
            recorder = newRecorder
            startedAt = Date()
            state = .recording
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Stops recording and returns how long it was, in seconds.
    func stop() -> Double {
        let duration = recorder?.currentTime ?? (startedAt.map { Date().timeIntervalSince($0) } ?? 0)
        recorder?.stop()
        recorder = nil
        startedAt = nil
        state = .idle

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        return duration
    }
}
