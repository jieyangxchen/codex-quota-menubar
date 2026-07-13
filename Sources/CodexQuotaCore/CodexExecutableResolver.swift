import Foundation

public enum CodexExecutableResolver {
    public static let defaultCandidates = [
        "/Applications/ChatGPT.app/Contents/Resources/codex",
        "/Applications/Codex.app/Contents/Resources/codex",
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex"
    ]

    public static func resolve(candidates: [String] = defaultCandidates) -> String {
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return candidates.first ?? "codex"
    }
}
