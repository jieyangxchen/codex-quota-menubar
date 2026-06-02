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
