import Foundation
import Observation

/// One saved test recording plus the results of running it through the
/// speech engines. Stored as JSON next to the audio files in Documents.
struct Recording: Identifiable, Codable, Equatable {
    var id: UUID
    var label: String
    var fileName: String
    var createdAt: Date
    var durationSeconds: Double

    var whisperModel: String?
    var whisperText: String?
    var whisperSeconds: Double?

    var fileURL: URL {
        RecordingFiles.directory.appendingPathComponent(fileName)
    }
}

/// Where the audio files and their index live: Documents/Recordings.
enum RecordingFiles {
    static let directory: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static var indexURL: URL {
        directory.appendingPathComponent("index.json")
    }
}

@MainActor
@Observable
final class RecordingStore {
    private(set) var recordings: [Recording] = []

    init() {
        load()
    }

    func newFileURL() -> URL {
        RecordingFiles.directory.appendingPathComponent(UUID().uuidString + ".wav")
    }

    func add(label: String, fileURL: URL, durationSeconds: Double) {
        let recording = Recording(
            id: UUID(),
            label: label.isEmpty ? "Recording \(recordings.count + 1)" : label,
            fileName: fileURL.lastPathComponent,
            createdAt: Date(),
            durationSeconds: durationSeconds
        )
        recordings.insert(recording, at: 0)
        save()
    }

    func update(_ recording: Recording) {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        recordings[index] = recording
        save()
    }

    func delete(_ recording: Recording) {
        try? FileManager.default.removeItem(at: recording.fileURL)
        recordings.removeAll { $0.id == recording.id }
        save()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            try? FileManager.default.removeItem(at: recordings[index].fileURL)
        }
        recordings.remove(atOffsets: offsets)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: RecordingFiles.indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        recordings = (try? decoder.decode([Recording].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(recordings) {
            try? data.write(to: RecordingFiles.indexURL, options: .atomic)
        }
    }
}
