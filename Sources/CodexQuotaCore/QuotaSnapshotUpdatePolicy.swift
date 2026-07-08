import Foundation

public enum QuotaSnapshotUpdatePolicy {
    public static func shouldApply(_ incoming: QuotaSnapshot, over current: QuotaSnapshot) -> Bool {
        if incoming.source == .unavailable {
            return current.source == .unavailable
        }

        if incoming.source == .live {
            return true
        }

        if current.source == .live {
            return incoming.capturedAt >= current.capturedAt
        }

        return incoming.capturedAt >= current.capturedAt || current.source == .unavailable
    }
}
