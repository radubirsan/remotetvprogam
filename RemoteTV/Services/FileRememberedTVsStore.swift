import Foundation

/// JSON-file-backed ``RememberedTVsStore`` that writes to `URL.documentsDirectory` by default.
///
/// Isolated as an `actor` so concurrent connect flows writing new records don't race on the file.
actor FileRememberedTVsStore: RememberedTVsStore {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL = URL.documentsDirectory.appending(path: "remembered-tvs.json")) {
        self.url = url
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func all() async -> [RememberedTV] {
        readAll()
    }

    func get(ip: String) async -> RememberedTV? {
        readAll().first { $0.ip == ip }
    }

    func upsert(_ tv: RememberedTV) async throws {
        var records = readAll()
        if let index = records.firstIndex(where: { $0.ip == tv.ip }) {
            records[index] = merge(existing: records[index], incoming: tv)
        } else {
            records.append(tv)
        }
        try write(records)
    }

    func delete(ip: String) async throws {
        var records = readAll()
        records.removeAll { $0.ip == ip }
        try write(records)
    }

    // MARK: - Private

    private func readAll() -> [RememberedTV] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([RememberedTV].self, from: data)) ?? []
    }

    private func write(_ records: [RememberedTV]) throws {
        let data = try encoder.encode(records)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Preserves fields that the new record doesn't explicitly set — e.g. if a REST probe refreshes
    /// `name`/`model` on reconnect, we shouldn't blow away a previously captured `mac` or `udn`.
    private func merge(existing: RememberedTV, incoming: RememberedTV) -> RememberedTV {
        var merged = incoming
        if merged.mac == nil { merged.mac = existing.mac }
        if merged.udn == nil { merged.udn = existing.udn }
        if merged.friendlyName.isEmpty { merged.friendlyName = existing.friendlyName }
        if merged.modelName.isEmpty { merged.modelName = existing.modelName }
        return merged
    }
}
