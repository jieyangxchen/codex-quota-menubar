import Foundation

public struct QuotaRefreshPolicy: Equatable, Sendable {
    public let automaticIntervalSeconds: Int
    public let menuOpenStaleIntervalSeconds: Int

    public init(
        automaticIntervalSeconds: Int,
        menuOpenStaleIntervalSeconds: Int
    ) {
        self.automaticIntervalSeconds = automaticIntervalSeconds
        self.menuOpenStaleIntervalSeconds = menuOpenStaleIntervalSeconds
    }

    public static let `default` = QuotaRefreshPolicy(
        automaticIntervalSeconds: 8,
        menuOpenStaleIntervalSeconds: 3
    )
}
