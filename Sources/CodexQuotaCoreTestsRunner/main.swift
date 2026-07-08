import CodexQuotaCore
import Foundation

@discardableResult
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) -> Bool {
    if actual == expected {
        return true
    }

    fputs("FAIL: \(message)\n  expected: \(expected)\n  actual:   \(actual)\n", stderr)
    return false
}

func makeSnapshot(totalTokens: Int? = nil) -> QuotaSnapshot {
    QuotaSnapshot(
        source: .live,
        capturedAt: Date(timeIntervalSince1970: 1_780_299_600),
        planType: "prolite",
        primary: QuotaWindow(
            usedPercent: 2,
            windowDurationMinutes: 300,
            resetsAt: Date(timeIntervalSince1970: 1_780_313_729)
        ),
        secondary: QuotaWindow(
            usedPercent: 2,
            windowDurationMinutes: 10_080,
            resetsAt: Date(timeIntervalSince1970: 1_780_849_465)
        ),
        totalTokens: totalTokens,
        statusMessage: nil
    )
}

var failures = 0
var checks = 0

if !expectEqual(
    QuotaFormatter.menuTitle(for: makeSnapshot(), showUsed: false, showTotalTokens: false),
    "5h 98% | 1w 98%",
    "default menu title shows remaining percentages"
) {
    failures += 1
}
checks += 1

if !expectEqual(
    QuotaFormatter.menuTitle(for: makeSnapshot(), showUsed: true, showTotalTokens: false),
    "5h 2% | 1w 2%",
    "menu title can show used percentages"
) {
    failures += 1
}
checks += 1

if !expectEqual(
    QuotaFormatter.menuTitle(
        for: makeSnapshot(totalTokens: 1_234_567),
        showUsed: false,
        showTotalTokens: true
    ),
    "5h 98% | 1w 98% | 1.2M",
    "menu title can append compact total tokens"
) {
    failures += 1
}
checks += 1

if !expectEqual(
    QuotaFormatter.stackedTitle(for: makeSnapshot(), showUsed: false, showTotalTokens: false),
    "5h   1w\n98%  98%",
    "stacked title puts 5h and 1w labels above their percentages"
) {
    failures += 1
}
checks += 1

let displayColumns = QuotaFormatter.statusColumns(
    for: makeSnapshot(),
    showUsed: false,
    showTotalTokens: false
)
if !expectEqual(
    displayColumns,
    [
        QuotaDisplayColumn(label: "5h", value: "98%"),
        QuotaDisplayColumn(label: "1w", value: "98%")
    ],
    "status columns keep each window label paired with its own centered percentage"
) {
    failures += 1
}
checks += 1

if !expectEqual(QuotaFormatter.stableStatusValue("89%"), " 89%", "two-digit percentages draw in a fixed four-character slot") {
    failures += 1
}
checks += 1
if !expectEqual(QuotaFormatter.stableStatusValue("100%"), "100%", "three-digit percentages fill the fixed four-character slot") {
    failures += 1
}
checks += 1
if !expectEqual(QuotaFormatter.stableStatusValue("--"), "--", "non-percent placeholders are not padded") {
    failures += 1
}
checks += 1

let gridStyle = QuotaStatusGridStyle.default
if !expectEqual(gridStyle.columnWidth, 42, "status grid column width leaves stable spacing between 5h and 1w") {
    failures += 1
}
checks += 1
if !expectEqual(gridStyle.labelFontSize, 9, "status grid label font size is one point smaller without moving its row") {
    failures += 1
}
checks += 1
if !expectEqual(gridStyle.valueFontSize, 11, "status grid value font size is one point smaller without moving its row") {
    failures += 1
}
checks += 1
if !expectEqual(gridStyle.labelOriginY, 11.5, "status grid nudges the label row upward to align with adjacent status items") {
    failures += 1
}
checks += 1
if !expectEqual(gridStyle.valueOriginY, -0.5, "status grid nudges the value row upward to align with adjacent status items") {
    failures += 1
}
checks += 1
if !expectEqual(gridStyle.horizontalAlignment, .center, "status grid keeps each label and percentage centered within its quota group") {
    failures += 1
}
checks += 1
if !expectEqual(gridStyle.lineGap, -3, "status grid leaves a more open gap between label and percentage rows") {
    failures += 1
}
checks += 1

let refreshPolicy = QuotaRefreshPolicy.default
if !expectEqual(refreshPolicy.automaticIntervalSeconds, 8, "quota refresh polls quickly now that live reads reuse one app-server connection") {
    failures += 1
}
checks += 1
if !expectEqual(refreshPolicy.menuOpenStaleIntervalSeconds, 3, "opening the menu refreshes shortly-stale quota data") {
    failures += 1
}
checks += 1

let logReadConfiguration = LocalLogReadConfiguration.default
if !expectEqual(logReadConfiguration.maxFilesToScan, 20, "log reader scans the most recently modified candidate files") {
    failures += 1
}
checks += 1
if !expectEqual(logReadConfiguration.tailBytes, 128 * 1024, "log reader reads only the tail of each candidate file by default") {
    failures += 1
}
checks += 1
if !expectEqual(logReadConfiguration.fullReadFallbackFiles, 3, "log reader only full-reads a small fallback set when tails miss quota data") {
    failures += 1
}
checks += 1

let probeConfiguration = AppServerProbeConfiguration.default
if !expectEqual(probeConfiguration.initializeWaitTimeoutSeconds, 0.75, "app-server probe waits only briefly for initialize before reading quota") {
    failures += 1
}
checks += 1
if !expectEqual(probeConfiguration.rateLimitReadTimeoutSeconds, 2.5, "app-server probe returns soon after the live quota response is available") {
    failures += 1
}
checks += 1
if !expectEqual(probeConfiguration.terminationWaitSeconds, 0.5, "app-server probe force-cleans child processes that do not exit promptly") {
    failures += 1
}
checks += 1

let responseBuffer = AppServerResponseBuffer()
let partialLine = #"{"id":7,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":3,"windowDurationMins":300},"secondary":{"usedPercent":5,"windowDurationMins":10080},"planType":"prolite"}}}"#
let midpoint = partialLine.index(partialLine.startIndex, offsetBy: partialLine.count / 2)
responseBuffer.append(Data(partialLine[..<midpoint].utf8))
if !expectEqual(responseBuffer.waitForResponse(id: 7, timeout: 0.01), nil, "app-server response buffer waits for complete JSON lines") {
    failures += 1
}
checks += 1
responseBuffer.append(Data((String(partialLine[midpoint...]) + "\n").utf8))
let bufferedResponse = responseBuffer.waitForResponse(id: 7, timeout: 0.01)
if !expectEqual(bufferedResponse.flatMap { String(data: $0, encoding: .utf8) }, partialLine, "app-server response buffer returns complete response by id") {
    failures += 1
}
checks += 1

let diagnosticsRows = QuotaDiagnosticsFormatter.rows(
    for: makeSnapshot(),
    liveDiagnostics: AppServerQuotaProviderDiagnostics(
        isProcessRunning: true,
        successfulReadCount: 2,
        restartCount: 1,
        lastSuccessAt: Date(timeIntervalSince1970: 1_780_299_600),
        lastFailureAt: nil,
        lastFailureDescription: nil
    ),
    cacheFileURL: URL(fileURLWithPath: "/tmp/codex-quota-cache.json")
)
if !expectEqual(diagnosticsRows.contains("Source: Live"), true, "diagnostics rows include the current source") {
    failures += 1
}
checks += 1
if !expectEqual(diagnosticsRows.contains("Live process: running"), true, "diagnostics rows include live process state") {
    failures += 1
}
checks += 1
if !expectEqual(diagnosticsRows.contains("Live reads: 2"), true, "diagnostics rows include live read count") {
    failures += 1
}
checks += 1
if !expectEqual(diagnosticsRows.contains("Cache: /tmp/codex-quota-cache.json"), true, "diagnostics rows include the cache path") {
    failures += 1
}
checks += 1

do {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-quota-cache-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let cache = QuotaSnapshotCache(fileURL: tempDirectory.appendingPathComponent("last-live.json"))
    try cache.store(makeSnapshot(totalTokens: 456_789))
    let loaded = try cache.load()

    if !expectEqual(loaded.source, .cache, "snapshot cache restores live data as cached source") {
        failures += 1
    }
    checks += 1
    if !expectEqual(loaded.primary?.usedPercent, 2, "snapshot cache preserves primary used percent") {
        failures += 1
    }
    checks += 1
    if !expectEqual(loaded.totalTokens, 456_789, "snapshot cache preserves total token count") {
        failures += 1
    }
    checks += 1
} catch {
    fputs("FAIL: snapshot cache round trips live quota\n  error: \(error)\n", stderr)
    failures += 1
    checks += 1
}

do {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-quota-cache-ignore-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let cacheURL = tempDirectory.appendingPathComponent("last-live.json")
    let cache = QuotaSnapshotCache(fileURL: cacheURL)
    let logOnlySnapshot = QuotaSnapshot(
        source: .log,
        capturedAt: Date(timeIntervalSince1970: 1_780_299_700),
        planType: "prolite",
        primary: QuotaWindow(usedPercent: 11, windowDurationMinutes: 300, resetsAt: nil),
        secondary: nil,
        totalTokens: nil,
        statusMessage: nil
    )

    try cache.store(logOnlySnapshot)
    if !expectEqual(FileManager.default.fileExists(atPath: cacheURL.path), false, "snapshot cache ignores non-live fallback data") {
        failures += 1
    }
    checks += 1
} catch {
    fputs("FAIL: snapshot cache ignores non-live quota\n  error: \(error)\n", stderr)
    failures += 1
    checks += 1
}

do {
    let jsonl = """
    {"timestamp":"2026-06-01T07:31:45.190Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":260882}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":1.0,"window_minutes":300,"resets_at":1780313729},"secondary":{"used_percent":2.0,"window_minutes":10080,"resets_at":1780849465},"plan_type":"prolite"}}}
    {"timestamp":"2026-06-01T07:33:56.870Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":984344}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":2.0,"window_minutes":300,"resets_at":1780313729},"secondary":{"used_percent":2.0,"window_minutes":10080,"resets_at":1780849465},"plan_type":"prolite"}}}
    """
    let snapshot = try LogQuotaProvider.parseNewestSnapshot(from: jsonl)

    if !expectEqual(snapshot.source, .log, "log parser marks source as log") {
        failures += 1
    }
    checks += 1

    if !expectEqual(snapshot.primary?.usedPercent, 2.0, "log parser uses newest primary percentage") {
        failures += 1
    }
    checks += 1

    if !expectEqual(snapshot.secondary?.windowDurationMinutes, 10_080, "log parser reads secondary window duration") {
        failures += 1
    }
    checks += 1

    if !expectEqual(snapshot.totalTokens, 984_344, "log parser reads total tokens") {
        failures += 1
    }
    checks += 1

    if !expectEqual(snapshot.planType, "prolite", "log parser reads plan type") {
        failures += 1
    }
    checks += 1
} catch {
    fputs("FAIL: log parser parses newest token_count event\n  error: \(error)\n", stderr)
    failures += 1
    checks += 1
}

do {
    let jsonl = """
    not-json
    {"timestamp":"2026-06-01T07:31:45.190Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":260882}},"rate_limits":{"primary":{"used_percent":1.0,"window_minutes":300,"resets_at":1780313729}}}}
    """
    let snapshot = try LogQuotaProvider.parseNewestSnapshot(from: jsonl)

    if !expectEqual(snapshot.primary?.usedPercent, 1.0, "log parser ignores malformed lines") {
        failures += 1
    }
    checks += 1
} catch {
    fputs("FAIL: log parser ignores malformed lines\n  error: \(error)\n", stderr)
    failures += 1
    checks += 1
}

do {
    let jsonl = """
    {"timestamp":"2026-06-26T01:20:02.711Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":6.0,"window_minutes":300,"resets_at":1782453903},"secondary":{"used_percent":52.0,"window_minutes":10080,"resets_at":1782786845},"plan_type":"prolite"}}}
    {"timestamp":"2026-06-26T01:20:18.888Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex_bengalfox","primary":{"used_percent":0.0,"window_minutes":300,"resets_at":1782454771},"secondary":{"used_percent":0.0,"window_minutes":10080,"resets_at":1783041571},"plan_type":"prolite"}}}
    """
    let snapshot = try LogQuotaProvider.parseNewestSnapshot(from: jsonl)

    if !expectEqual(snapshot.primary?.usedPercent, 6.0, "log parser ignores model-specific zero quota buckets") {
        failures += 1
    }
    checks += 1
    if !expectEqual(snapshot.secondary?.usedPercent, 52.0, "log parser keeps aggregate weekly quota bucket") {
        failures += 1
    }
    checks += 1
} catch {
    fputs("FAIL: log parser filters model-specific quota buckets\n  error: \(error)\n", stderr)
    failures += 1
    checks += 1
}

do {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-quota-log-reader-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let staleFile = tempDirectory.appendingPathComponent("stale.jsonl")
    let freshFile = tempDirectory.appendingPathComponent("fresh.jsonl")
    try """
    {"timestamp":"2026-06-26T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":80.0,"window_minutes":300},"secondary":{"used_percent":40.0,"window_minutes":10080},"plan_type":"prolite"}}}
    """.write(to: staleFile, atomically: true, encoding: .utf8)
    try """
    {"timestamp":"2026-06-26T01:30:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":7.0,"window_minutes":300},"secondary":{"used_percent":53.0,"window_minutes":10080},"plan_type":"prolite"}}}
    """.write(to: freshFile, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 1_780_300_000)],
        ofItemAtPath: staleFile.path
    )
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 1_780_200_000)],
        ofItemAtPath: freshFile.path
    )

    let snapshot = try LocalLogSnapshotReader.newestSnapshot(in: tempDirectory)
    if !expectEqual(snapshot.primary?.usedPercent, 7.0, "local log reader chooses newest aggregate token_count by event timestamp") {
        failures += 1
    }
    checks += 1
} catch {
    fputs("FAIL: local log reader chooses newest event timestamp across files\n  error: \(error)\n", stderr)
    failures += 1
    checks += 1
}

do {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-quota-log-tail-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let file = tempDirectory.appendingPathComponent("tail.jsonl")
    let largePrefix = String(repeating: #"{"type":"noise"}"# + "\n", count: 500)
    try """
    \(largePrefix)
    {"timestamp":"2026-06-26T02:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":12.0,"window_minutes":300},"secondary":{"used_percent":22.0,"window_minutes":10080},"plan_type":"prolite"}}}
    """.write(to: file, atomically: true, encoding: .utf8)

    let snapshot = try LocalLogSnapshotReader.newestSnapshot(
        in: tempDirectory,
        configuration: LocalLogReadConfiguration(maxFilesToScan: 5, tailBytes: 512, fullReadFallbackFiles: 0)
    )
    if !expectEqual(snapshot.primary?.usedPercent, 12.0, "local log reader can parse quota from a file tail") {
        failures += 1
    }
    checks += 1
} catch {
    fputs("FAIL: local log reader parses file tails\n  error: \(error)\n", stderr)
    failures += 1
    checks += 1
}

do {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-quota-log-full-fallback-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let file = tempDirectory.appendingPathComponent("fallback.jsonl")
    try """
    {"timestamp":"2026-06-26T02:15:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":13.0,"window_minutes":300},"secondary":{"used_percent":23.0,"window_minutes":10080},"plan_type":"prolite"}}}
    \(String(repeating: #"{"type":"noise"}"# + "\n", count: 500))
    """.write(to: file, atomically: true, encoding: .utf8)

    let snapshot = try LocalLogSnapshotReader.newestSnapshot(
        in: tempDirectory,
        configuration: LocalLogReadConfiguration(maxFilesToScan: 5, tailBytes: 128, fullReadFallbackFiles: 1)
    )
    if !expectEqual(snapshot.primary?.usedPercent, 13.0, "local log reader full-reads a small fallback set when tails miss") {
        failures += 1
    }
    checks += 1
} catch {
    fputs("FAIL: local log reader full-read fallback\n  error: \(error)\n", stderr)
    failures += 1
    checks += 1
}

do {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-quota-log-cache-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let file = tempDirectory.appendingPathComponent("cached.jsonl")
    try """
    {"timestamp":"2026-06-26T02:30:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":14.0,"window_minutes":300},"secondary":{"used_percent":24.0,"window_minutes":10080},"plan_type":"prolite"}}}
    """.write(to: file, atomically: true, encoding: .utf8)

    let reader = CachedLocalLogSnapshotReader(
        sessionsDirectory: tempDirectory,
        configuration: LocalLogReadConfiguration(maxFilesToScan: 5, tailBytes: 1024, fullReadFallbackFiles: 0),
        minimumRefreshIntervalSeconds: 60
    )
    let first = try reader.newestSnapshot()
    try """
    {"timestamp":"2026-06-26T02:31:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":15.0,"window_minutes":300},"secondary":{"used_percent":25.0,"window_minutes":10080},"plan_type":"prolite"}}}
    """.write(to: file, atomically: true, encoding: .utf8)
    let second = try reader.newestSnapshot()

    if !expectEqual(first.primary?.usedPercent, 14.0, "cached local log reader reads the initial snapshot") {
        failures += 1
    }
    checks += 1
    if !expectEqual(second.primary?.usedPercent, 14.0, "cached local log reader reuses a fresh cached snapshot") {
        failures += 1
    }
    checks += 1
} catch {
    fputs("FAIL: cached local log reader reuses fresh snapshots\n  error: \(error)\n", stderr)
    failures += 1
    checks += 1
}

do {
    let json = """
    {"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":4,"windowDurationMins":300,"resetsAt":1780382157},"secondary":{"usedPercent":7,"windowDurationMins":10080,"resetsAt":1780849465},"planType":"prolite","credits":null,"rateLimitReachedType":null},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":null,"primary":{"usedPercent":4,"windowDurationMins":300,"resetsAt":1780382157},"secondary":{"usedPercent":7,"windowDurationMins":10080,"resetsAt":1780849465},"planType":"prolite"},"codex_bengalfox":{"limitId":"codex_bengalfox","limitName":"GPT-5.3-Codex-Spark","primary":{"usedPercent":0,"windowDurationMins":300,"resetsAt":1780382267},"secondary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":1780969067},"planType":"prolite"}}}
    """.data(using: .utf8)!
    let response = try AppServerQuotaProvider.decodeResponse(from: json)
    let snapshot = AppServerQuotaProvider.normalize(
        response,
        capturedAt: Date(timeIntervalSince1970: 1_780_299_600)
    )

    if !expectEqual(snapshot.primary?.usedPercent, 4, "live normalization uses aggregate short-window bucket") {
        failures += 1
    }
    checks += 1
    if !expectEqual(snapshot.secondary?.usedPercent, 7, "live normalization uses aggregate long-window bucket") {
        failures += 1
    }
    checks += 1
} catch {
    fputs("FAIL: live mixed bucket normalization\n  error: \(error)\n", stderr)
    failures += 1
    checks += 1
}

let liveSnapshot = QuotaSnapshot(
    source: .live,
    capturedAt: Date(timeIntervalSince1970: 1_780_299_600),
    planType: "prolite",
    primary: QuotaWindow(usedPercent: 1, windowDurationMinutes: 300, resetsAt: nil),
    secondary: nil,
    totalTokens: nil,
    statusMessage: nil
)
let logSnapshot = QuotaSnapshot(
    source: .log,
    capturedAt: Date(timeIntervalSince1970: 1_780_299_600),
    planType: "prolite",
    primary: QuotaWindow(usedPercent: 9, windowDurationMinutes: 300, resetsAt: nil),
    secondary: nil,
    totalTokens: 123,
    statusMessage: nil
)

let liveFirstService = QuotaService(liveProvider: { liveSnapshot }, logProvider: { logSnapshot })
let liveFirstResult = liveFirstService.refresh()
if !expectEqual(liveFirstResult.source, .live, "quota service prefers live snapshot") {
    failures += 1
}
checks += 1
if !expectEqual(liveFirstResult.primary?.usedPercent, 1, "quota service keeps live quota values") {
    failures += 1
}
checks += 1

let fallbackService = QuotaService(
    liveProvider: { throw QuotaProviderError.noSnapshot },
    logProvider: { logSnapshot }
)
let fallbackResult = fallbackService.refresh()
if !expectEqual(fallbackResult.source, .log, "quota service falls back to log snapshot") {
    failures += 1
}
checks += 1
if !expectEqual(fallbackResult.totalTokens, 123, "quota service keeps log token count") {
    failures += 1
}
checks += 1

let cachedSnapshot = QuotaSnapshot(
    source: .cache,
    capturedAt: Date(timeIntervalSince1970: 1_780_299_580),
    planType: "prolite",
    primary: QuotaWindow(usedPercent: 5, windowDurationMinutes: 300, resetsAt: nil),
    secondary: QuotaWindow(usedPercent: 8, windowDurationMinutes: 10_080, resetsAt: nil),
    totalTokens: 456,
    statusMessage: "Cached live quota"
)
let cacheFallbackService = QuotaService(
    liveProvider: { throw QuotaProviderError.noSnapshot },
    logProvider: { throw QuotaProviderError.noSnapshot },
    cacheProvider: { cachedSnapshot }
)
let cacheFallbackResult = cacheFallbackService.refresh()
if !expectEqual(cacheFallbackResult.source, .cache, "quota service falls back to last-good live cache") {
    failures += 1
}
checks += 1
if !expectEqual(cacheFallbackResult.primary?.usedPercent, 5, "quota service keeps cached quota values") {
    failures += 1
}
checks += 1

let newerLiveSnapshot = QuotaSnapshot(
    source: .live,
    capturedAt: Date(timeIntervalSince1970: 2_000),
    planType: "prolite",
    primary: QuotaWindow(usedPercent: 58, windowDurationMinutes: 300, resetsAt: nil),
    secondary: QuotaWindow(usedPercent: 76, windowDurationMinutes: 10_080, resetsAt: nil),
    totalTokens: nil,
    statusMessage: nil
)
let olderLogSnapshot = QuotaSnapshot(
    source: .log,
    capturedAt: Date(timeIntervalSince1970: 1_900),
    planType: "prolite",
    primary: QuotaWindow(usedPercent: 36, windowDurationMinutes: 300, resetsAt: nil),
    secondary: QuotaWindow(usedPercent: 72, windowDurationMinutes: 10_080, resetsAt: nil),
    totalTokens: nil,
    statusMessage: nil
)
if !expectEqual(QuotaSnapshotUpdatePolicy.shouldApply(olderLogSnapshot, over: newerLiveSnapshot), false, "older log fallback does not replace newer live quota") {
    failures += 1
}
checks += 1

let newerLogSnapshot = QuotaSnapshot(
    source: .log,
    capturedAt: Date(timeIntervalSince1970: 2_100),
    planType: "prolite",
    primary: QuotaWindow(usedPercent: 60, windowDurationMinutes: 300, resetsAt: nil),
    secondary: QuotaWindow(usedPercent: 77, windowDurationMinutes: 10_080, resetsAt: nil),
    totalTokens: nil,
    statusMessage: nil
)
if !expectEqual(QuotaSnapshotUpdatePolicy.shouldApply(newerLogSnapshot, over: newerLiveSnapshot), true, "newer log fallback may replace older live quota") {
    failures += 1
}
checks += 1
if !expectEqual(QuotaSnapshotUpdatePolicy.shouldApply(newerLiveSnapshot, over: olderLogSnapshot), true, "live quota replaces log fallback") {
    failures += 1
}
checks += 1

do {
    let json = """
    {"rateLimits":{"limitId":"codex","primary":{"usedPercent":2,"windowDurationMins":300,"resetsAt":1780313729},"secondary":{"usedPercent":2,"windowDurationMins":10080,"resetsAt":1780849465},"planType":"prolite","credits":null,"limitName":null,"rateLimitReachedType":null},"rateLimitsByLimitId":null}
    """.data(using: .utf8)!
    let response = try AppServerQuotaProvider.decodeResponse(from: json)
    let snapshot = AppServerQuotaProvider.normalize(
        response,
        capturedAt: Date(timeIntervalSince1970: 1_780_299_600)
    )

    if !expectEqual(snapshot.source, .live, "live payload normalizes to live source") {
        failures += 1
    }
    checks += 1
    if !expectEqual(snapshot.primary?.usedPercent, 2, "live payload normalizes primary used percent") {
        failures += 1
    }
    checks += 1
    if !expectEqual(snapshot.secondary?.windowDurationMinutes, 10_080, "live payload normalizes secondary window duration") {
        failures += 1
    }
    checks += 1
    if !expectEqual(snapshot.planType, "prolite", "live payload normalizes plan type") {
        failures += 1
    }
    checks += 1
} catch {
    fputs("FAIL: live payload normalization\n  error: \(error)\n", stderr)
    failures += 1
    checks += 1
}

if failures > 0 {
    exit(1)
}

print("PASS: \(checks) checks")
