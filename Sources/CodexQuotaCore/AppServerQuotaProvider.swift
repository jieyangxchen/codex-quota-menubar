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

public struct AppServerQuotaProviderDiagnostics: Equatable, Sendable {
    public let isProcessRunning: Bool
    public let successfulReadCount: Int
    public let restartCount: Int
    public let lastSuccessAt: Date?
    public let lastFailureAt: Date?
    public let lastFailureDescription: String?

    public init(
        isProcessRunning: Bool,
        successfulReadCount: Int,
        restartCount: Int,
        lastSuccessAt: Date?,
        lastFailureAt: Date?,
        lastFailureDescription: String?
    ) {
        self.isProcessRunning = isProcessRunning
        self.successfulReadCount = successfulReadCount
        self.restartCount = restartCount
        self.lastSuccessAt = lastSuccessAt
        self.lastFailureAt = lastFailureAt
        self.lastFailureDescription = lastFailureDescription
    }
}

public final class AppServerResponseBuffer: @unchecked Sendable {
    private let condition = NSCondition()
    private var buffer = Data()
    private var responses: [Int: Data] = [:]

    public init() {}

    public func append(_ data: Data) {
        condition.lock()
        defer {
            condition.broadcast()
            condition.unlock()
        }

        buffer.append(data)

        while let newlineIndex = buffer.firstIndex(of: 10) {
            var lineData = Data(buffer[buffer.startIndex..<newlineIndex])
            buffer.removeSubrange(buffer.startIndex...newlineIndex)

            if lineData.last == 13 {
                lineData.removeLast()
            }

            guard !lineData.isEmpty, let id = Self.responseID(in: lineData) else {
                continue
            }

            responses[id] = lineData
        }
    }

    public func waitForResponse(id: Int, timeout: TimeInterval) -> Data? {
        condition.lock()
        defer { condition.unlock() }

        if let data = responses.removeValue(forKey: id) {
            return data
        }

        let deadline = Date(timeIntervalSinceNow: timeout)
        while responses[id] == nil {
            if !condition.wait(until: deadline) {
                break
            }
        }

        return responses.removeValue(forKey: id)
    }

    private static func responseID(in data: Data) -> Int? {
        (try? JSONDecoder().decode(AppServerResponseIDEnvelope.self, from: data))?.id
    }
}

private struct AppServerResponseIDEnvelope: Decodable {
    let id: Int?
}

public final class PersistentAppServerQuotaProvider: @unchecked Sendable {
    private let codexExecutable: String
    private let configuration: AppServerProbeConfiguration
    private let lock = NSLock()
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var responses = AppServerResponseBuffer()
    private var nextRequestID = 1
    private var successfulReadCount = 0
    private var restartCount = 0
    private var lastSuccessAt: Date?
    private var lastFailureAt: Date?
    private var lastFailureDescription: String?

    public init(
        codexExecutable: String = "/Applications/Codex.app/Contents/Resources/codex",
        configuration: AppServerProbeConfiguration = .default
    ) {
        self.codexExecutable = codexExecutable
        self.configuration = configuration
    }

    deinit {
        close()
    }

    public var diagnostics: AppServerQuotaProviderDiagnostics {
        lock.lock()
        defer { lock.unlock() }

        return AppServerQuotaProviderDiagnostics(
            isProcessRunning: process?.isRunning == true,
            successfulReadCount: successfulReadCount,
            restartCount: restartCount,
            lastSuccessAt: lastSuccessAt,
            lastFailureAt: lastFailureAt,
            lastFailureDescription: lastFailureDescription
        )
    }

    public func fetchSnapshot() throws -> QuotaSnapshot {
        lock.lock()
        defer { lock.unlock() }

        do {
            try ensureStartedLocked()
            guard let input else { throw QuotaProviderError.noSnapshot }

            let requestID = nextIDLocked()
            let read = #"{"id":\#(requestID),"method":"account/rateLimits/read"}"#
            input.fileHandleForWriting.write(Data((read + "\n").utf8))

            guard let data = responses.waitForResponse(
                id: requestID,
                timeout: configuration.rateLimitReadTimeoutSeconds
            ) else {
                throw QuotaProviderError.noSnapshot
            }

            let snapshot = try AppServerQuotaProvider.snapshot(fromResponseData: data)
            successfulReadCount += 1
            lastSuccessAt = snapshot.capturedAt
            lastFailureDescription = nil
            return snapshot
        } catch {
            lastFailureAt = Date()
            lastFailureDescription = String(describing: error)
            closeLocked()
            throw error
        }
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        closeLocked()
    }

    private func ensureStartedLocked() throws {
        if process?.isRunning == true {
            return
        }

        closeLocked()

        let newProcess = Process()
        newProcess.executableURL = URL(fileURLWithPath: codexExecutable)
        newProcess.arguments = ["app-server", "--listen", "stdio://"]

        let newInput = Pipe()
        let newOutput = Pipe()
        let newResponses = AppServerResponseBuffer()
        newProcess.standardInput = newInput
        newProcess.standardOutput = newOutput
        newProcess.standardError = Pipe()
        newOutput.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                newResponses.append(data)
            }
        }

        do {
            try newProcess.run()
        } catch {
            stop(newProcess, input: newInput, output: newOutput)
            throw error
        }

        let initializeID = nextIDLocked()
        let initialize = #"{"id":\#(initializeID),"method":"initialize","params":{"clientInfo":{"name":"codex-quota-menubar","title":"Codex Quota Menubar","version":"0.2.0"},"capabilities":{"experimentalApi":true,"requestAttestation":false,"optOutNotificationMethods":[]}}}"#
        newInput.fileHandleForWriting.write(Data((initialize + "\n").utf8))

        guard newResponses.waitForResponse(
            id: initializeID,
            timeout: configuration.initializeWaitTimeoutSeconds
        ) != nil else {
            stop(newProcess, input: newInput, output: newOutput)
            throw QuotaProviderError.noSnapshot
        }

        process = newProcess
        input = newInput
        output = newOutput
        responses = newResponses
        restartCount += 1
    }

    private func nextIDLocked() -> Int {
        let id = nextRequestID
        nextRequestID += 1
        return id
    }

    private func closeLocked() {
        guard process != nil || input != nil || output != nil else {
            return
        }

        stop(process, input: input, output: output)
        process = nil
        input = nil
        output = nil
        responses = AppServerResponseBuffer()
    }

    private func stop(_ process: Process?, input: Pipe?, output: Pipe?) {
        output?.fileHandleForReading.readabilityHandler = nil
        input?.fileHandleForWriting.closeFile()

        guard let process, process.isRunning else { return }
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

    public static func snapshot(
        fromResponseData data: Data,
        capturedAt: Date = Date()
    ) throws -> QuotaSnapshot {
        let responseLines = candidateResponseLines(in: data)

        for responseLine in responseLines {
            if let envelope = try? JSONDecoder().decode(AppServerEnvelope.self, from: responseLine) {
                let snapshot = normalize(envelope.result, capturedAt: capturedAt)
                if snapshot.primary != nil || snapshot.secondary != nil {
                    return snapshot
                }
            }

            if let response = try? decodeResponse(from: responseLine) {
                let snapshot = normalize(response, capturedAt: capturedAt)
                if snapshot.primary != nil || snapshot.secondary != nil {
                    return snapshot
                }
            }
        }

        throw QuotaProviderError.noSnapshot
    }

    public static func fetchSnapshot(
        codexExecutable: String = "/Applications/Codex.app/Contents/Resources/codex",
        configuration: AppServerProbeConfiguration = .default
    ) throws -> QuotaSnapshot {
        let responseData = try runAppServerProbe(
            codexExecutable: codexExecutable,
            configuration: configuration
        )
        return try snapshot(fromResponseData: responseData)
    }

    private static func candidateResponseLines(in data: Data) -> [Data] {
        guard let responseText = String(data: data, encoding: .utf8) else {
            return [data]
        }

        let lines = responseText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.contains("rateLimits") }
            .compactMap { $0.data(using: .utf8) }

        return lines.isEmpty ? [data] : lines
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

        let initialize = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-quota-menubar","title":"Codex Quota Menubar","version":"0.2.0"},"capabilities":{"experimentalApi":true,"requestAttestation":false,"optOutNotificationMethods":[]}}}"#
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
