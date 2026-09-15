# Harvest Native for iOS

This directory contains the native SwiftUI edition of Harvest. It is independent
from Flutter and CocoaPods and targets iOS 17 or later.

Open `Harvest.xcodeproj` with Xcode 26 or later, choose a development team, and
run the `Harvest` scheme. The backend API is shared with the Flutter client.

The native target keeps the production bundle identifier `com.ptools.harvest`
and uses version `2026.0915.02` with build `292`, so it can be signed as the next
update of the existing iOS app. Do not install a Flutter and native archive with
the same bundle identifier side by side.

## 更新记录

后续每次版本更新均在此处按时间倒序记录，内容以用户可见的功能和修复为主，
不堆叠提交哈希或框架迁移明细。

### 2026.0915.02 (292) - 2026-09-15

- 执行详情改为结构化摘要，分开展示站点统计、流量、失败原因和成功站点，
  并移除原始 JSON 记录。
- 消息详情过滤重复的简略成功记录，保留耗时、部分数据未更新和失败原因。
- 更新页面重新设计版本摘要、更新内容和安装包区域；更新日志按新增、修复、
  优化和调整分类，并过滤 Markdown 空标题与提交哈希。
- 站点刷新、签到、辅种及任务手动执行优先显示服务端实际返回信息，后端未
  返回消息时才使用本地兜底文案。
- 服务端返回信息支持完整多行显示，操作结果在原停留时长基础上延长 2 秒。
- App、收割机助手 Safari 扩展和 CookieCloud Safari 扩展的版本统一同步至
  `2026.0915.02 (292)`。

### 2026.0915.01 (290) - 2026-09-15

- 对照 Flutter 版本完成增量审查；该批变更仅涉及 Flutter 组件兼容调整，
  原生端接口、数据模型和移动端工作流无需变更。
- App 与两个 Safari 扩展的版本统一同步至 `2026.0915.01 (290)`。

## Native stack

- SwiftUI navigation and forms
- Native iOS 26 Liquid Glass navigation with an ultra-thin-material fallback
- Swift Concurrency and URLSession networking
- Keychain token and credential storage
- Account-scoped persistent caches for dashboard, sites, media catalogs,
  downloads, scheduled tasks, and notices
- A separate memory/disk image cache for public artwork and site icons; signed
  image URLs remain memory-only
- Swift Charts dashboard visualizations
- WebKit site browsing with Cookie, host-aware LocalStorage/token injection,
  User-Agent switching, JavaScript dialogs, file inputs, recoverable loading
  errors, and persistent current-site cleanup
- SF Symbols plus a new, project-local AppIcon

## GitHub unsigned IPA

The `Build Unsigned IPA` workflow runs on `macos-26` and builds with code
signing disabled. Every push to `main` produces a 30-day Actions artifact named
`Harvest-unsigned-<run number>`. Tags matching `v*` also publish the IPA and its
SHA-256 checksum to a GitHub Release.

An unsigned IPA cannot be installed directly on a stock iPhone. Sign the
artifact with your own Apple ID, development certificate, enterprise
certificate, or a compatible sideloading service before installation.

## Migration status

The migration audit maps active Flutter workflows to native screens and service
calls, including first-run defaults, account-scoped cache restoration,
download-refresh, and site-history parity. It does not treat static source
coverage as proof of runtime 1:1 behavior. Runtime parity still requires an
Xcode build and an integration pass against a reachable Harvest server. See
[`MIGRATION_AUDIT.md`](MIGRATION_AUDIT.md) for the current evidence and limits.

## Implemented core workflows

- HTTP/HTTPS login, server-provided first-run database defaults, setup,
  Keychain credentials, token refresh, complete login-history restoration,
  direct account switching, logout, and complete local-data cleanup
- TMDB/Douban catalogs, details, search history, combined resource search over
  cancellable/deduplicated SSE, incremental results, advanced filtering,
  downloader push, and cached catalog restoration
- Site overview, ten editable feature flags, daily/monthly status history,
  separate mail/announcement state, complete filters and sorting, timeline,
  levels, imports, structured/raw TOML generation, bulk operations,
  cache-consistent mutations, authenticated browsing, credential sync,
  extraction, and pausable bonus tools
- Configurable dashboard modules, traffic/server charts, privacy mode, current
  page screenshot sharing, a dedicated dashboard long image, and cached
  dashboard/site data with visible timestamps and in-app refresh
- Downloader setup, persistent 1-60 second refresh settings, automatic-stop
  countdown, pause/resume, WebSocket recovery, cached startup snapshots,
  deduplicated live frames, precomputed torrent filtering, bulk and advanced
  controls, categories, tags, trackers, limits, and push workflows
- Scheduled-task lifecycle, Cron editing, migration-task assistance, Markdown
  execution results, termination, deletion, result-history management, and
  stale-while-revalidate list restoration
- Notice lifecycle, unread and app badges, local notifications, Markdown detail,
  cached list restoration, gap-free APP/server log pause/resume, updates, backup/import, users,
  paginated authorization management, and maintenance

Local notice polling and APP-package downloads currently run while the app is
active. The target does not declare remote-push or background-transfer
entitlements, so a terminated app cannot receive new notices or continue an IPA
download in the background.

## Performance and cache behavior

- Dashboard share images and log share text are generated only when the user
  requests them; automatic refresh no longer performs those expensive renders.
- Downloader and server countdowns update through localized `TimelineView`
  content instead of publishing an entire screen every second.
- Downloader snapshots are loaded concurrently, duplicate WebSocket frames are
  ignored, and site/torrent filters reuse precomputed indexes and sorted arrays.
- Persistent business caches are isolated by server and username, capped at 12
  MiB per entry and 48 MiB total, expire after 45 days, and are excluded from
  device backup. Legacy cache files are sanitized on first access.
- Passwords, Cookie/LocalStorage, authorization headers, API keys, tokens,
  passkeys, authkeys, RSS credentials, and signed image URLs are never written
  into the new persistent snapshots.
