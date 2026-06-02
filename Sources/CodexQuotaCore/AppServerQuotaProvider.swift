import Foundation

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
        codexExecutable: String = "/Applications/Codex.app/Contents/Resources/codex"
    ) throws -> QuotaSnapshot {
        let responseData = try runAppServerProbe(codexExecutable: codexExecutable)
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

    private static func runAppServerProbe(codexExecutable: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexExecutable)
        process.arguments = ["app-server", "--listen", "stdio://"]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        try process.run()

        let initialize = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-quota-menubar","title":"Codex Quota Menubar","version":"0.1.1"},"capabilities":{"experimentalApi":true,"requestAttestation":false,"optOutNotificationMethods":[]}}}"#
        let read = #"{"id":2,"method":"account/rateLimits/read"}"#
        input.fileHandleForWriting.write(Data((initialize + "\n").utf8))
        Thread.sleep(forTimeInterval: 1.0)
        input.fileHandleForWriting.write(Data((read + "\n").utf8))
        Thread.sleep(forTimeInterval: 3.0)
        input.fileHandleForWriting.closeFile()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
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
