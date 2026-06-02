import Foundation

public enum QuotaSource: String, Sendable {
    case live
    case log
    case unavailable
}

public struct QuotaWindow: Equatable, Sendable {
    public let usedPercent: Double
    public let windowDurationMinutes: Int?
    public let resetsAt: Date?

    public init(usedPercent: Double, windowDurationMinutes: Int?, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

public struct QuotaSnapshot: Equatable, Sendable {
    public let source: QuotaSource
    public let capturedAt: Date
    public let planType: String?
    public let primary: QuotaWindow?
    public let secondary: QuotaWindow?
    public let totalTokens: Int?
    public let statusMessage: String?

    public init(
        source: QuotaSource,
        capturedAt: Date,
        planType: String?,
        primary: QuotaWindow?,
        secondary: QuotaWindow?,
        totalTokens: Int?,
        statusMessage: String?
    ) {
        self.source = source
        self.capturedAt = capturedAt
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
        self.totalTokens = totalTokens
        self.statusMessage = statusMessage
    }
}
