import Darwin
import Foundation

public struct AppServerProbeConfiguration: Equatable, Sendable {
    public let initializeWaitTimeoutSeconds: Double
    public let rateLimitReadTimeoutSeconds: Double
    public let terminationWaitSeconds: Double

    public init(
        initializeWaitTimeoutSeconds: Double,
        rateLimitReadTimeoutSeconds: Double,
        terminationWaitSeconds: Double
    ) {
        self.initializeWaitTimeoutSeconds = initializeWaitTimeoutSeconds
        self.rateLimitReadTimeoutSeconds = rateLimitReadTimeoutSeconds
        self.terminationWaitSeconds = terminationWaitSeconds
    }

    public static let `default` = AppServerProbeConfiguration(
        initializeWaitTimeoutSeconds: 0.75,
        rateLimitReadTimeoutSeconds: 2.5,
        terminationWaitSeconds: 0.5
    )
}

public enum AppServerQuotaProvider {
    public static func decodeResponse(from data: Data) throws -> AppServerRateLimitResponse {
        let decoder = JSONDecoder()
        return try decoder.decode(AppServerRateLimitResponse.self, from: data)
    }

    public static func normalize(
        _ response: AppServerRateLimitResponse,
        capturedAt: Date = Date()
    ) -> QuotaSnapshot {
        let aggregate = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits

        return QuotaSnapshot(
            source: .live,
            capturedAt: capturedAt,
            planType: aggregate.planType,
            primary: aggregate.primary?.quotaWindow,
            secondary: aggregate.secondary?.quotaWindow,
            totalTokens: nil,
            statusMessage: nil
        )
    }

    public static func fetchSnapshot(
        codexExecutable: String = "/Applications/Codex.app/Contents/Resources/codex",
        configuration: AppServerProbeConfiguration = .default
    ) throws -> QuotaSnapshot {
        let responseData = try runAppServerProbe(
            codexExecutable: codexExecutable,
            configuration: configuration
        )
        let responseText = String(data: responseData, encoding: .utf8) ?? ""

        for line in responseText.split(separator: "\n") where line.contains("rateLimits") {
            guard let data = line.data(using: .utf8) else { continue }
            if let envelope = try? JSONDecoder().decode(AppServerEnvelope.self, from: data) {
                return normalize(envelope.result)
            }
            if let response = try? decodeResponse(from: data) {
                return normalize(response)
            }
        }

        throw QuotaProviderError.noSnapshot
    }

    private static func runAppServerProbe(
        codexExecutable: String,
        configuration: AppServerProbeConfiguration
    ) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexExecutable)
        process.arguments = ["app-server", "--listen", "stdio://"]

        let input = Pipe()
        let output = Pipe()
        let reader = AppServerProbeOutputReader()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                reader.append(data)
            }
        }

        try process.run()

        let initialize = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-quota-menubar","title":"Codex Quota Menubar","version":"0.1.3"},"capabilities":{"experimentalApi":true,"requestAttestation":false,"optOutNotificationMethods":[]}}}"#
        let read = #"{"id":2,"method":"account/rateLimits/read"}"#
        input.fileHandleForWriting.write(Data((initialize + "\n").utf8))
        _ = reader.waitForInitialize(timeout: configuration.initializeWaitTimeoutSeconds)
        input.fileHandleForWriting.write(Data((read + "\n").utf8))
        guard let data = reader.waitForRateLimits(timeout: configuration.rateLimitReadTimeoutSeconds) else {
            stopAppServerProbe(process, input: input, output: output, configuration: configuration)
            throw QuotaProviderError.noSnapshot
        }

        stopAppServerProbe(process, input: input, output: output, configuration: configuration)
        return data
    }

    private static func stopAppServerProbe(
        _ process: Process,
        input: Pipe,
        output: Pipe,
        configuration: AppServerProbeConfiguration
    ) {
        output.fileHandleForReading.readabilityHandler = nil
        input.fileHandleForWriting.closeFile()

        guard process.isRunning else { return }
        process.terminate()

        let deadline = Date(timeIntervalSinceNow: configuration.terminationWaitSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }
}

public struct AppServerRateLimitResponse: Decodable, Sendable {
    public let rateLimits: AppServerRateLimitSnapshot
    public let rateLimitsByLimitId: [String: AppServerRateLimitSnapshot]?
}

public struct AppServerRateLimitSnapshot: Decodable, Sendable {
    public let primary: AppServerRateLimitWindow?
    public let secondary: AppServerRateLimitWindow?
    public let planType: String?
}

public struct AppServerRateLimitWindow: Decodable, Sendable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAtEpoch: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent
        case windowDurationMins
        case resetsAtEpoch = "resetsAt"
    }

    var quotaWindow: QuotaWindow {
        QuotaWindow(
            usedPercent: usedPercent,
            windowDurationMinutes: windowDurationMins,
            resetsAt: resetsAtEpoch.map(Date.init(timeIntervalSince1970:))
        )
    }
}

private struct AppServerEnvelope: Decodable {
    let result: AppServerRateLimitResponse
}

private final class AppServerProbeOutputReader: @unchecked Sendable {
    private let condition = NSCondition()
    private var buffer = Data()
    private var sawInitialize = false
    private var rateLimitsData: Data?

    func append(_ data: Data) {
        condition.lock()
        buffer.append(data)

        let text = String(data: buffer, encoding: .utf8) ?? ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let completeLines = lines.enumerated().compactMap { index, line -> Substring? in
            index < lines.count - 1 || text.hasSuffix("\n") ? line : nil
        }
        sawInitialize = sawInitialize || completeLines.contains { line in
            line.contains(#""id":1"#)
        }
        if rateLimitsData == nil, completeLines.contains(where: { $0.contains("rateLimits") }) {
            rateLimitsData = buffer
        }

        condition.broadcast()
        condition.unlock()
    }

    func waitForInitialize(timeout: TimeInterval) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return wait(until: { sawInitialize || rateLimitsData != nil }, timeout: timeout)
    }

    func waitForRateLimits(timeout: TimeInterval) -> Data? {
        condition.lock()
        defer { condition.unlock() }
        _ = wait(until: { rateLimitsData != nil }, timeout: timeout)
        return rateLimitsData
    }

    private func wait(until predicate: () -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !predicate() {
            if !condition.wait(until: deadline) {
                break
            }
        }
        return predicate()
    }
}
