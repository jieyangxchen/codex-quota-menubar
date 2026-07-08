import Foundation

public final class QuotaSnapshotCache: @unchecked Sendable {
    public let fileURL: URL

    public init(fileURL: URL = QuotaSnapshotCache.defaultFileURL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return baseURL
            .appendingPathComponent("CodexQuotaMenubar", isDirectory: true)
            .appendingPathComponent("last-live-quota.json")
    }

    public func store(_ snapshot: QuotaSnapshot) throws {
        guard snapshot.source == .live else { return }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let payload = CachedQuotaSnapshot(snapshot: snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() throws -> QuotaSnapshot {
        let data = try Data(contentsOf: fileURL)
        let payload = try JSONDecoder().decode(CachedQuotaSnapshot.self, from: data)
        return payload.snapshot
    }
}

private struct CachedQuotaSnapshot: Codable {
    let capturedAt: Date
    let planType: String?
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let totalTokens: Int?

    init(snapshot: QuotaSnapshot) {
        capturedAt = snapshot.capturedAt
        planType = snapshot.planType
        primary = snapshot.primary
        secondary = snapshot.secondary
        totalTokens = snapshot.totalTokens
    }

    var snapshot: QuotaSnapshot {
        QuotaSnapshot(
            source: .cache,
            capturedAt: capturedAt,
            planType: planType,
            primary: primary,
            secondary: secondary,
            totalTokens: totalTokens,
            statusMessage: "Cached live quota"
        )
    }
}
