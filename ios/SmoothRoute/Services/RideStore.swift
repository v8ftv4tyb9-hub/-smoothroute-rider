import Foundation

final class RideStore {
    enum StoreError: Error {
        case noActiveRide
        case invalidJournalLine
    }

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let directoryURL: URL
    private let stateURL: URL
    private let journalURL: URL
    private let exportsURL: URL
    private var journalHandle: FileHandle?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        decoder = JSONDecoder()

        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        directoryURL = applicationSupport.appendingPathComponent("SmoothRoute", isDirectory: true)
        stateURL = directoryURL.appendingPathComponent("active-ride.json")
        journalURL = directoryURL.appendingPathComponent("active-samples.jsonl")
        exportsURL = directoryURL.appendingPathComponent("Exports", isDirectory: true)
    }

    deinit {
        try? journalHandle?.close()
    }

    var hasActiveRide: Bool {
        fileManager.fileExists(atPath: stateURL.path)
    }

    func prepareNewRide(_ state: ActiveRideState) throws {
        try createDirectories()
        try journalHandle?.close()
        journalHandle = nil
        try? fileManager.removeItem(at: journalURL)
        fileManager.createFile(atPath: journalURL.path, contents: nil)
        try saveActive(state)
        journalHandle = try FileHandle(forWritingTo: journalURL)
        try journalHandle?.seekToEnd()
    }

    func append(_ sample: RideSample) throws {
        if journalHandle == nil {
            try createDirectories()
            if !fileManager.fileExists(atPath: journalURL.path) {
                fileManager.createFile(atPath: journalURL.path, contents: nil)
            }
            journalHandle = try FileHandle(forWritingTo: journalURL)
            try journalHandle?.seekToEnd()
        }

        var data = try encoder.encode(sample)
        data.append(0x0A)
        try journalHandle?.write(contentsOf: data)
    }

    func checkpoint(_ state: ActiveRideState) throws {
        try saveActive(state)
        try journalHandle?.synchronize()
    }

    func loadActive() throws -> ActiveRideState? {
        guard fileManager.fileExists(atPath: stateURL.path) else { return nil }
        return try decoder.decode(ActiveRideState.self, from: Data(contentsOf: stateURL))
    }

    func loadSamples() throws -> [RideSample] {
        guard fileManager.fileExists(atPath: journalURL.path) else { return [] }
        let data = try Data(contentsOf: journalURL)
        guard !data.isEmpty else { return [] }

        return try data
            .split(separator: 0x0A)
            .map { line in
                guard !line.isEmpty else { throw StoreError.invalidJournalLine }
                return try decoder.decode(RideSample.self, from: Data(line))
            }
    }

    func finish(_ payload: RidePayload) throws -> URL {
        try createDirectories()
        try journalHandle?.synchronize()
        try journalHandle?.close()
        journalHandle = nil

        let exportEncoder = JSONEncoder()
        exportEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let timestamp = ISO8601DateFormatter.smoothRoute
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "smoothroute-native-\(payload.ride.profile)-\(timestamp).json"
        let exportURL = exportsURL.appendingPathComponent(filename)
        try exportEncoder.encode(payload).write(to: exportURL, options: .atomic)
        try clearActiveRide()
        return exportURL
    }

    func clearActiveRide() throws {
        try journalHandle?.close()
        journalHandle = nil
        if fileManager.fileExists(atPath: stateURL.path) {
            try fileManager.removeItem(at: stateURL)
        }
        if fileManager.fileExists(atPath: journalURL.path) {
            try fileManager.removeItem(at: journalURL)
        }
    }

    private func saveActive(_ state: ActiveRideState) throws {
        try createDirectories()
        try encoder.encode(state).write(to: stateURL, options: .atomic)
    }

    private func createDirectories() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: exportsURL,
            withIntermediateDirectories: true
        )
    }
}
