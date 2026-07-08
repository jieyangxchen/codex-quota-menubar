import Foundation

public struct QuotaService: Sendable {
    public typealias Provider = @Sendable () throws -> QuotaSnapshot
    public typealias SnapshotHandler = @Sendable (QuotaSnapshot) -> Void

    private let liveProvider: Provider
    private let logProvider: Provider
    private let cacheProvider: Provider?
    private let liveSnapshotHandler: SnapshotHandler?

    public init(
        liveProvider: @escaping Provider,
        logProvider: @escaping Provider,
        cacheProvider: Provider? = nil,
        liveSnapshotHandler: SnapshotHandler? = nil
    ) {
        self.liveProvider = liveProvider
        self.logProvider = logProvider
        self.cacheProvider = cacheProvider
        self.liveSnapshotHandler = liveSnapshotHandler
    }

    public func refresh() -> QuotaSnapshot {
        do {
            let snapshot = try liveProvider()
            liveSnapshotHandler?(snapshot)
            return snapshot
        } catch {
            do {
                return try logProvider()
            } catch {
                if let cacheProvider, let snapshot = try? cacheProvider() {
                    return snapshot
                }

                return QuotaSnapshot(
                    source: .unavailable,
                    capturedAt: Date(),
                    planType: nil,
                    primary: nil,
                    secondary: nil,
                    totalTokens: nil,
                    statusMessage: "No Codex quota data available"
                )
            }
        }
    }
}
