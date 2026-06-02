import Foundation

public enum QuotaProviderError: Error, Equatable {
    case noSnapshot
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
                  let rateLimits = event.payload.rateLimits
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

public enum LocalLogSnapshotReader {
    public static func newestSnapshot(in sessionsDirectory: URL) throws -> QuotaSnapshot {
        let files = FileManager.default
            .enumerator(at: sessionsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" } ?? []

        let sortedFiles = files.sorted {
            modificationDate(for: $0) > modificationDate(for: $1)
        }

        for file in sortedFiles.prefix(20) {
            if let contents = try? String(contentsOf: file, encoding: .utf8),
               let snapshot = try? LogQuotaProvider.parseNewestSnapshot(from: contents) {
                return snapshot
            }
        }

        throw QuotaProviderError.noSnapshot
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
    let primary: LogWindow?
    let secondary: LogWindow?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case planType = "plan_type"
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
