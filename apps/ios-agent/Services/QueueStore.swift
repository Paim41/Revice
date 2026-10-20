import Foundation

@MainActor protocol QueueStoring { func load() throws -> QueueState; func save(_ state: QueueState) throws }
@MainActor struct QueueStore: QueueStoring {
    let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Revice", isDirectory: true)
    }
    private var file: URL { directory.appendingPathComponent("battery-queue.json") }
    func load() throws -> QueueState {
        guard FileManager.default.fileExists(atPath: file.path) else { return QueueState() }
        return try JSONDecoder().decode(QueueState.self, from: Data(contentsOf: file))
    }
    func save(_ state: QueueState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var location = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try location.setResourceValues(values)
        try JSONEncoder().encode(state).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
