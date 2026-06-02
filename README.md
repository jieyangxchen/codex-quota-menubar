<p align="center">
  <img src="docs/images/app-icon.png" width="128" alt="Codex Quota Menubar icon" />
</p>

<h1 align="center">Codex Quota Menubar</h1>

<p align="center">
  A tiny macOS menu bar app for watching your Codex 5-hour and 1-week quota at a glance.
</p>

<p align="center">
  <a href="#中文">中文</a> ·
  <a href="#english">English</a> ·
  <a href="https://github.com/jieyangxchen/codex-quota-menubar/releases/latest">Download</a>
</p>

---

## 中文

Codex Quota Menubar 是一个轻量 macOS 菜单栏工具，用来显示当前 Codex 额度剩余情况。它会优先读取本机 Codex 的实时账户级用量；如果实时数据暂时不可用，再降级读取本机 Codex 会话日志中的最近一次用量状态。

### 主要特性

| 功能 | 说明 |
| --- | --- |
| 菜单栏双行显示 | 上排显示 `5h` / `1w`，下排显示各自剩余额度百分比 |
| 实时优先 | 优先通过本机 Codex app-server 读取账户级 `account/rateLimits/read` |
| 日志降级 | 实时读取失败时，读取 `~/.codex/sessions/**/*.jsonl` 中最近的 `token_count` |
| 数字稳定 | 刷新时保留旧数字直到新数字返回，百分比使用固定槽位避免跳动 |
| 展示切换 | 可切换显示已用百分比或剩余百分比 |
| Token 总量 | 可选择在菜单中显示当前线程 total tokens |
| 一键操作 | 菜单内提供 Refresh、Open Codex、Quit |

### 菜单栏效果

```text
5h    1w
58%   87%
```

实际显示为紧凑的两列布局，每列内部保持独立中心线；`89% -> 80%` 这类变化不会让整列左右抖动。

### 安装

从 [Releases](https://github.com/jieyangxchen/codex-quota-menubar/releases/latest) 下载：

- `CodexQuotaMenubar-macOS.dmg`
- 或 `CodexQuotaMenubar-macOS.zip`

打开后将 `CodexQuotaMenubar.app` 放到 `/Applications`，再启动即可。当前版本未签名，首次启动时 macOS 可能需要在 System Settings 里手动允许。

### 数据来源

应用的数据链路按优先级分为两层：

1. **Live**

   通过本机 Codex app-server 调用：

   ```text
   account/rateLimits/read
   ```

   应用读取账户级 `codex` aggregate 桶里的 `primary` 和 `secondary`：

   - `primary`：短周期窗口，通常是 5 小时
   - `secondary`：长周期窗口，通常是 1 周

2. **Log fallback**

   当 live 读取失败时，应用读取最近的本机会话日志：

   ```text
   ~/.codex/sessions/**/*.jsonl
   ```

   它只解析其中的 `token_count` 事件，不上传、不修改日志文件。

### 刷新策略

- 默认每 15 秒自动刷新一次
- 打开菜单时，如果当前数据已超过 5 秒，也会触发一次后台刷新
- 菜单中的 Refresh Now 可立即刷新
- 刷新中不会显示 `...`，而是保留旧数字直到新数据返回
- 若 live 不可用，会在菜单里显示当前 source 为 `Log`

### 本地开发

运行菜单栏 app：

```bash
swift run codex-quota-menubar
```

运行核心测试：

```bash
swift run codex-quota-core-tests
```

构建 `.app`：

```bash
scripts/build-app.sh
```

构建结果：

```text
dist/CodexQuotaMenubar.app
```

### 本地打包

生成 `.dmg`、`.zip` 和 checksum：

```bash
scripts/package-release.sh
```

构建产物会输出到：

```text
release/
```

### 发布

推送 `v*` tag 会触发 GitHub Actions Release workflow：

```bash
git tag v0.1.0
git push origin v0.1.0
```

Workflow 会在 macOS runner 上完成：

1. 生成 app icon
2. 运行核心测试
3. 构建 `CodexQuotaMenubar.app`
4. 打包 `.dmg` / `.zip`
5. 上传到 GitHub Release

### 隐私与仓库卫生

仓库不会包含：

- 本机 `.build/` 缓存
- 本地 `dist/` / `release/` 产物
- Codex 本机会话日志
- 本机绝对路径
- 个人 token、API key、cookie、session state

Release 安装包由 GitHub Actions 从源码重新构建。

---

## English

Codex Quota Menubar is a small macOS menu bar utility for monitoring your remaining Codex quota. It prefers live account-level quota from the local Codex app-server and falls back to the newest local Codex session log when live data is unavailable.

### Highlights

| Feature | Details |
| --- | --- |
| Two-line menu bar display | Shows `5h` / `1w` labels on top and remaining percentages below |
| Live-first data | Reads account-level quota through local Codex `account/rateLimits/read` |
| Local log fallback | Falls back to the newest `token_count` event in local Codex logs |
| Stable digits | Keeps old values during refresh and uses fixed-width percentage slots |
| Display modes | Toggle used percentage versus remaining percentage |
| Token total | Optionally show total token usage in the menu |
| Quick actions | Refresh, Open Codex, and Quit from the menu |

### Menu Bar Shape

```text
5h    1w
58%   87%
```

The menu bar item uses two compact columns with independent centers. Percentage values are drawn in stable slots so updates like `89% -> 80%` do not cause the whole column to shift.

### Installation

Download from [Releases](https://github.com/jieyangxchen/codex-quota-menubar/releases/latest):

- `CodexQuotaMenubar-macOS.dmg`
- or `CodexQuotaMenubar-macOS.zip`

Move `CodexQuotaMenubar.app` into `/Applications` and launch it. The app is currently unsigned, so macOS Gatekeeper may require manual approval on first launch.

### Data Sources

The app uses a two-layer data flow:

1. **Live**

   It calls the local Codex app-server method:

   ```text
   account/rateLimits/read
   ```

   The app reads the account-level `codex` aggregate bucket:

   - `primary`: short window, usually 5 hours
   - `secondary`: long window, usually 1 week

2. **Log fallback**

   If live quota is unavailable, the app reads the newest local Codex session log:

   ```text
   ~/.codex/sessions/**/*.jsonl
   ```

   It only parses `token_count` events. It does not upload or modify local logs.

### Refresh Behavior

- Auto-refreshes every 15 seconds
- Opening the menu triggers a background refresh when the current data is more than 5 seconds old
- Refresh Now triggers an immediate refresh
- Existing values stay visible while a refresh is running
- The menu shows `Log` as the source when fallback data is used

### Local Development

Run the app:

```bash
swift run codex-quota-menubar
```

Run tests:

```bash
swift run codex-quota-core-tests
```

Build the `.app` bundle:

```bash
scripts/build-app.sh
```

Output:

```text
dist/CodexQuotaMenubar.app
```

### Local Packaging

Create a `.dmg`, `.zip`, and checksum file:

```bash
scripts/package-release.sh
```

Artifacts are written to:

```text
release/
```

### Release

GitHub Actions builds release assets when a `v*` tag is pushed:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow runs on macOS and:

1. Generates the app icon
2. Runs the core test runner
3. Builds `CodexQuotaMenubar.app`
4. Packages `.dmg` / `.zip`
5. Uploads assets to GitHub Release

### Privacy and Repository Hygiene

The repository excludes:

- Local `.build/` cache
- Local `dist/` / `release/` artifacts
- Local Codex session logs
- Machine-specific absolute paths
- Personal tokens, API keys, cookies, or session state

Release artifacts are rebuilt from tracked source files in GitHub Actions.
