import Foundation

public enum QuotaProviderError: Error, Equatable {
    case noSnapshot
}

public struct LocalLogReadConfiguration: Equatable, Sendable {
    public let maxFilesToScan: Int
    public let tailBytes: Int
    public let fullReadFallbackFiles: Int

    public init(maxFilesToScan: Int, tailBytes: Int, fullReadFallbackFiles: Int) {
        self.maxFilesToScan = maxFilesToScan
        self.tailBytes = tailBytes
        self.fullReadFallbackFiles = fullReadFallbackFiles
    }

    public static let `default` = LocalLogReadConfiguration(
        maxFilesToScan: 20,
        tailBytes: 128 * 1024,
        fullReadFallbackFiles: 3
    )
}

public enum LogQuotaProvider {
    public static func parseNewestSnapshot(from jsonl: String) throws -> QuotaSnapshot {
        let decoder = JSONDecoder()
        var newest: QuotaSnapshot?

        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(LogEvent.self, from: data),
                  event.type == "event_msg",
                  event.payload.type == "token_count",
                  let rateLimits = event.payload.rateLimits,
                  rateLimits.isAggregateCodexBucket
            else { continue }

            newest = QuotaSnapshot(
                source: .log,
                capturedAt: parseCodexTimestamp(event.timestamp) ?? Date(),
                planType: rateLimits.planType,
                primary: rateLimits.primary?.quotaWindow,
                secondary: rateLimits.secondary?.quotaWindow,
                totalTokens: event.payload.info?.totalTokenUsage?.totalTokens,
                statusMessage: nil
            )
        }

        guard let newest else { throw QuotaProviderError.noSnapshot }
        return newest
    }
}

public final class CachedLocalLogSnapshotReader: @unchecked Sendable {
    private let sessionsDirectory: URL
    private let configuration: LocalLogReadConfiguration
    private let minimumRefreshIntervalSeconds: TimeInterval
    private let lock = NSLock()
    private var cachedSnapshot: QuotaSnapshot?
    private var lastRefreshAt: Date?

    public init(
        sessionsDirectory: URL,
        configuration: LocalLogReadConfiguration = .default,
        minimumRefreshIntervalSeconds: TimeInterval = 5
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.configuration = configuration
        self.minimumRefreshIntervalSeconds = minimumRefreshIntervalSeconds
    }

    public func newestSnapshot() throws -> QuotaSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        if let cachedSnapshot,
           let lastRefreshAt,
           now.timeIntervalSince(lastRefreshAt) < minimumRefreshIntervalSeconds {
            return cachedSnapshot
        }

        do {
            let snapshot = try LocalLogSnapshotReader.newestSnapshot(
                in: sessionsDirectory,
                configuration: configuration
            )
            cachedSnapshot = snapshot
            lastRefreshAt = now
            return snapshot
        } catch {
            if let cachedSnapshot {
                return cachedSnapshot
            }
            throw error
        }
    }
}

public enum LocalLogSnapshotReader {
    public static func newestSnapshot(
        in sessionsDirectory: URL,
        configuration: LocalLogReadConfiguration = .default
    ) throws -> QuotaSnapshot {
        let files = FileManager.default
            .enumerator(at: sessionsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" } ?? []

        let sortedFiles = files.sorted {
            modificationDate(for: $0) > modificationDate(for: $1)
        }

        var newestSnapshot: QuotaSnapshot?
        for (index, file) in sortedFiles.prefix(configuration.maxFilesToScan).enumerated() {
            if let contents = try? trailingText(from: file, maxBytes: configuration.tailBytes),
               let snapshot = try? LogQuotaProvider.parseNewestSnapshot(from: contents) {
                newestSnapshot = newer(snapshot, than: newestSnapshot)
                continue
            }

            if index < configuration.fullReadFallbackFiles,
               let contents = try? String(contentsOf: file, encoding: .utf8),
               let snapshot = try? LogQuotaProvider.parseNewestSnapshot(from: contents) {
                newestSnapshot = newer(snapshot, than: newestSnapshot)
            }
        }

        guard let newestSnapshot else { throw QuotaProviderError.noSnapshot }
        return newestSnapshot
    }

    private static func newer(_ candidate: QuotaSnapshot, than current: QuotaSnapshot?) -> QuotaSnapshot {
        guard let current else { return candidate }
        return candidate.capturedAt > current.capturedAt ? candidate : current
    }

    private static func trailingText(from url: URL, maxBytes: Int) throws -> String {
        guard maxBytes > 0 else { return "" }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let readSize = min(UInt64(maxBytes), fileSize)
        let offset = fileSize - readSize

        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        handle.seek(toFileOffset: offset)
        return String(data: handle.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private static func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

private struct LogEvent: Decodable {
    let timestamp: String
    let type: String
    let payload: LogPayload
}

private struct LogPayload: Decodable {
    let type: String
    let info: TokenInfo?
    let rateLimits: LogRateLimits?

    enum CodingKeys: String, CodingKey {
        case type
        case info
        case rateLimits = "rate_limits"
    }
}

private struct TokenInfo: Decodable {
    let totalTokenUsage: TotalTokenUsage?

    enum CodingKeys: String, CodingKey {
        case totalTokenUsage = "total_token_usage"
    }
}

private struct TotalTokenUsage: Decodable {
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case totalTokens = "total_tokens"
    }
}

private struct LogRateLimits: Decodable {
    let limitId: String?
    let primary: LogWindow?
    let secondary: LogWindow?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case limitId = "limit_id"
        case primary
        case secondary
        case planType = "plan_type"
    }

    var isAggregateCodexBucket: Bool {
        limitId == nil || limitId == "codex"
    }
}

private struct LogWindow: Decodable {
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAtEpoch: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAtEpoch = "resets_at"
    }

    var quotaWindow: QuotaWindow {
        QuotaWindow(
            usedPercent: usedPercent,
            windowDurationMinutes: windowMinutes,
            resetsAt: resetsAtEpoch.map(Date.init(timeIntervalSince1970:))
        )
    }
}

private func parseCodexTimestamp(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) {
        return date
    }

    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: value)
}
