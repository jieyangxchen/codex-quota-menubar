import Foundation

public struct QuotaService {
    public typealias Provider = () throws -> QuotaSnapshot

    private let liveProvider: Provider
    private let logProvider: Provider

    public init(liveProvider: @escaping Provider, logProvider: @escaping Provider) {
        self.liveProvider = liveProvider
        self.logProvider = logProvider
    }

    public func refresh() -> QuotaSnapshot {
        do {
            return try liveProvider()
        } catch {
            do {
                return try logProvider()
            } catch {
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
