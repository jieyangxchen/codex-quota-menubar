# Codex Quota Menubar

Small macOS menu bar utility for Codex quota visibility.

## Run

```bash
swift run codex-quota-menubar
```

The app appears as a compact macOS menu bar item. By default it shows remaining quota:

```text
5h
76%

1w
94%
```

The menu includes:

- Current source: `Live`, `Log`, or `Unavailable`
- 5 hour quota window
- 1 week quota window
- Total token count when available
- Toggle for used versus remaining percentage
- Toggle for appending total tokens to the menu bar title
- Refresh, Open Codex, and Quit actions

## Test

The project uses a lightweight executable test runner so the same command works even when XCTest or Swift Testing modules are not available through the installed Command Line Tools:

```bash
swift run codex-quota-core-tests
```

## Data Sources

The app tries live Codex account quota first via local Codex app-server:

```text
account/rateLimits/read
```

If live quota is unavailable, it reads the newest local `token_count` event from:

```text
~/.codex/sessions/**/*.jsonl
```

The live source exposes `primary` and `secondary` quota windows, which correspond to the short window, usually 5 hours, and the long window, usually 1 week. Local logs contain the same bucket shape from the last observed Codex token event and may include total token usage for the current thread.

## Build

```bash
scripts/build-app.sh
```

The built app is written to:

```text
dist/CodexQuotaMenubar.app
```

## Package

Create a local `.dmg`, `.zip`, and checksum file:

```bash
scripts/package-release.sh
```

Artifacts are written to:

```text
release/
```

## Release

GitHub Actions builds release assets when a `v*` tag is pushed:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The release workflow builds from source on macOS, runs the core test runner, packages `CodexQuotaMenubar.app`, and uploads:

- `CodexQuotaMenubar-macOS.dmg`
- `CodexQuotaMenubar-macOS.zip`
- `checksums.txt`

The app is currently unsigned, so macOS Gatekeeper may require approving the first launch manually.

## Repository Hygiene

The repository intentionally excludes local build output, release artifacts, app bundles, SwiftPM build caches, local Codex session logs, and machine-specific state. Release assets are rebuilt in GitHub Actions from tracked source files.
