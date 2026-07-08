import Foundation

public enum QuotaDiagnosticsFormatter {
    public static func rows(
        for snapshot: QuotaSnapshot,
        liveDiagnostics: AppServerQuotaProviderDiagnostics,
        cacheFileURL: URL
    ) -> [String] {
        var rows = [
            "Source: \(sourceTitle(snapshot.source))",
            "Updated: \(formatDate(snapshot.capturedAt))",
            "Live process: \(liveDiagnostics.isProcessRunning ? "running" : "stopped")",
            "Live reads: \(liveDiagnostics.successfulReadCount)",
            "Live restarts: \(liveDiagnostics.restartCount)"
        ]

        if let lastSuccessAt = liveDiagnostics.lastSuccessAt {
            rows.append("Last live success: \(formatDate(lastSuccessAt))")
        }

        if let lastFailureAt = liveDiagnostics.lastFailureAt {
            rows.append("Last live failure: \(formatDate(lastFailureAt))")
        }

        if let lastFailureDescription = liveDiagnostics.lastFailureDescription {
            rows.append("Live error: \(lastFailureDescription)")
        }

        rows.append("Cache: \(cacheFileURL.path)")
        return rows
    }

    public static func sourceTitle(_ source: QuotaSource) -> String {
        switch source {
        case .live: return "Live"
        case .log: return "Log"
        case .cache: return "Cached Live"
        case .unavailable: return "Unavailable"
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
