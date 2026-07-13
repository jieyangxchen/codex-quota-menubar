import Foundation

public struct QuotaDisplayColumn: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public enum QuotaFormatter {
    public static func menuTitle(
        for snapshot: QuotaSnapshot,
        showUsed: Bool,
        showTotalTokens: Bool
    ) -> String {
        var parts = statusColumns(
            for: snapshot,
            showUsed: showUsed,
            showTotalTokens: false
        )
        .map { "\($0.label) \($0.value)" }

        if showTotalTokens, let totalTokens = snapshot.totalTokens {
            parts.append(formatTokens(totalTokens))
        }

        return parts.joined(separator: " | ")
    }

    public static func stackedTitle(
        for snapshot: QuotaSnapshot,
        showUsed: Bool,
        showTotalTokens: Bool
    ) -> String {
        let columns = statusColumns(
            for: snapshot,
            showUsed: showUsed,
            showTotalTokens: showTotalTokens
        )
        return twoLineColumns(labels: columns.map(\.label), values: columns.map(\.value))
    }

    public static func statusColumns(
        for snapshot: QuotaSnapshot,
        showUsed: Bool,
        showTotalTokens: Bool
    ) -> [QuotaDisplayColumn] {
        var columns = [snapshot.primary, snapshot.secondary]
            .compactMap { $0 }
            .map { window in
                QuotaDisplayColumn(
                    label: label(for: window, fallback: "1w"),
                    value: formatValue(window, showUsed: showUsed)
                )
            }

        if columns.isEmpty {
            columns.append(QuotaDisplayColumn(label: "1w", value: "--"))
        }

        if showTotalTokens, let totalTokens = snapshot.totalTokens {
            columns.append(QuotaDisplayColumn(label: "TOK", value: formatTokens(totalTokens)))
        }

        return columns
    }

    public static func formatWindow(
        _ window: QuotaWindow?,
        fallbackLabel: String,
        showUsed: Bool
    ) -> String {
        guard let window else { return "\(fallbackLabel) --" }
        let value = showUsed ? window.usedPercent : window.remainingPercent
        return "\(label(for: window, fallback: fallbackLabel)) \(Int(value.rounded()))%"
    }

    public static func label(for window: QuotaWindow, fallback: String) -> String {
        guard let minutes = window.windowDurationMinutes else { return fallback }
        if minutes == 300 { return "5h" }
        if minutes == 10_080 { return "1w" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    private static func formatValue(_ window: QuotaWindow, showUsed: Bool) -> String {
        let value = showUsed ? window.usedPercent : window.remainingPercent
        return "\(Int(value.rounded()))%"
    }

    private static func twoLineColumns(labels: [String], values: [String]) -> String {
        let widths = zip(labels, values).map { max($0.count, $1.count) }
        let top = zip(labels, widths)
            .map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }
            .joined(separator: "  ")
            .trimmingCharacters(in: .whitespaces)
        let bottom = zip(values, widths)
            .map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }
            .joined(separator: "  ")
            .trimmingCharacters(in: .whitespaces)
        return "\(top)\n\(bottom)"
    }

    public static func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        if tokens >= 1_000 {
            return String(format: "%.1fK", Double(tokens) / 1_000)
        }
        return "\(tokens)"
    }

    public static func stableStatusValue(_ value: String) -> String {
        guard value.hasSuffix("%"), value.count < 4 else {
            return value
        }

        return String(repeating: " ", count: 4 - value.count) + value
    }
}
