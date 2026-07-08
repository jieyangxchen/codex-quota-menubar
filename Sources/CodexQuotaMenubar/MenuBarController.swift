import AppKit
import CodexQuotaCore
import Foundation

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private static let gridStyle = QuotaStatusGridStyle.default
    private static let refreshPolicy = QuotaRefreshPolicy.default
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusGridView = StatusGridView(
        frame: NSRect(
            x: 0,
            y: 0,
            width: CGFloat(2 * MenuBarController.gridStyle.columnWidth),
            height: CGFloat(MenuBarController.gridStyle.itemHeight)
        )
    )
    private let refreshQueue = DispatchQueue(label: "codex-quota-menubar.refresh", qos: .utility)
    private var showUsed = false
    private var showTotalTokens = false
    private var timer: Timer?
    private var isRefreshing = false
    private var latestSnapshot = QuotaSnapshot(
        source: .unavailable,
        capturedAt: Date(),
        planType: nil,
        primary: nil,
        secondary: nil,
        totalTokens: nil,
        statusMessage: "Loading"
    )

    func start() {
        statusItem.length = CGFloat(2 * Self.gridStyle.columnWidth)
        configureStatusButton()
        statusGridView.columns = [
            QuotaDisplayColumn(label: "5h", value: "--"),
            QuotaDisplayColumn(label: "1w", value: "--")
        ]
        rebuildMenu()
        refreshNow()
        timer = Timer.scheduledTimer(
            timeInterval: TimeInterval(Self.refreshPolicy.automaticIntervalSeconds),
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func timerFired() {
        refreshNow()
    }

    @objc private func refreshMenuAction() {
        refreshNow()
    }

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor [weak self] in
            self?.refreshIfMenuDataIsStale()
        }
    }

    private func refreshIfMenuDataIsStale() {
        let age = Date().timeIntervalSince(latestSnapshot.capturedAt)
        if age >= TimeInterval(Self.refreshPolicy.menuOpenStaleIntervalSeconds) {
            refreshNow()
        }
    }

    @objc private func toggleUsed() {
        showUsed.toggle()
        updateTitle()
        rebuildMenu()
    }

    @objc private func toggleTotalTokens() {
        showTotalTokens.toggle()
        updateTitle()
        rebuildMenu()
    }

    @objc private func openCodex() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Codex.app"))
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refreshNow() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshQueue.async {
            let snapshot = Self.makeService().refresh()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRefreshing = false
                guard QuotaSnapshotUpdatePolicy.shouldApply(snapshot, over: self.latestSnapshot) else {
                    return
                }
                self.latestSnapshot = snapshot
                self.updateTitle()
                self.rebuildMenu()
            }
        }
    }

    nonisolated private static func makeService() -> QuotaService {
        QuotaService(
            liveProvider: {
                try AppServerQuotaProvider.fetchSnapshot()
            },
            logProvider: {
                let sessions = FileManager.default
                    .homeDirectoryForCurrentUser
                    .appendingPathComponent(".codex/sessions")
                return try LocalLogSnapshotReader.newestSnapshot(in: sessions)
            }
        )
    }

    private func updateTitle() {
        let columns = QuotaFormatter.statusColumns(
            for: latestSnapshot,
            showUsed: showUsed,
            showTotalTokens: showTotalTokens
        )
        statusGridView.columns = columns
        statusItem.length = CGFloat(max(columns.count, 2) * Self.gridStyle.columnWidth)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(disabledItem("Source: \(sourceTitle(latestSnapshot.source))"))

        if let planType = latestSnapshot.planType {
            menu.addItem(disabledItem("Plan: \(planType)"))
        }

        menu.addItem(disabledItem(windowTitle("5h", latestSnapshot.primary)))
        menu.addItem(disabledItem(windowTitle("1w", latestSnapshot.secondary)))

        if let totalTokens = latestSnapshot.totalTokens {
            menu.addItem(disabledItem("Total tokens: \(QuotaFormatter.formatTokens(totalTokens))"))
        }

        if let statusMessage = latestSnapshot.statusMessage {
            menu.addItem(disabledItem(statusMessage))
        }

        menu.addItem(.separator())
        menu.addItem(toggleItem(title: "Show used", action: #selector(toggleUsed), isOn: showUsed))
        menu.addItem(toggleItem(title: "Show total tokens", action: #selector(toggleTotalTokens), isOn: showTotalTokens))
        menu.addItem(actionItem(title: "Refresh Now", action: #selector(refreshMenuAction), key: "r"))
        menu.addItem(actionItem(title: "Open Codex", action: #selector(openCodex), key: "o"))
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Quit", action: #selector(quit), key: "q"))

        statusItem.menu = menu
    }

    private func windowTitle(_ fallbackLabel: String, _ window: QuotaWindow?) -> String {
        let value = QuotaFormatter.formatWindow(window, fallbackLabel: fallbackLabel, showUsed: showUsed)
        guard let window, let resetsAt = window.resetsAt else { return value }
        return "\(value), resets \(Self.resetFormatter.string(from: resetsAt))"
    }

    private func sourceTitle(_ source: QuotaSource) -> String {
        switch source {
        case .live: return "Live"
        case .log: return "Log"
        case .unavailable: return "Unavailable"
        }
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func toggleItem(title: String, action: Selector, isOn: Bool) -> NSMenuItem {
        let item = actionItem(title: title, action: action, key: "")
        item.state = isOn ? .on : .off
        return item
    }

    private func actionItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        statusGridView.translatesAutoresizingMaskIntoConstraints = false
        statusGridView.wantsLayer = false
        statusGridView.identifier = NSUserInterfaceItemIdentifier("CodexQuotaStatusGrid")
        button.addSubview(statusGridView)
        NSLayoutConstraint.activate([
            statusGridView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            statusGridView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            statusGridView.topAnchor.constraint(equalTo: button.topAnchor),
            statusGridView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
