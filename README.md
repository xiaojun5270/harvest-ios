# Harvest Native for iOS

This directory contains the native SwiftUI edition of Harvest. It is independent
from Flutter and CocoaPods and targets iOS 17 or later.

Open `Harvest.xcodeproj` with Xcode 26 or later, choose a development team, and
run the `Harvest` scheme. The backend API is shared with the Flutter client.

The native target keeps the production bundle identifier `com.ptools.harvest`
and uses build `291`, so it can be signed as the next update of the existing iOS
app. Do not install a Flutter and native archive with the same bundle identifier
side by side.

## Native stack

- SwiftUI navigation and forms
- Native iOS 26 Liquid Glass navigation with an ultra-thin-material fallback
- Swift Concurrency and URLSession networking
- Keychain token and credential storage
- Account-scoped persistent caches for dashboard, sites, and media catalogs
- Swift Charts dashboard visualizations
- WebKit site browsing with Cookie, LocalStorage, and User-Agent injection
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
  authenticated browsing, credential sync, extraction, and bonus tools
- Configurable dashboard modules, traffic/server charts, privacy mode, current
  page screenshot sharing, a dedicated dashboard long image, and cached
  dashboard/site data with visible timestamps and background refresh
- Downloader setup, persistent 1-60 second refresh settings, automatic-stop
  countdown, pause/resume, WebSocket recovery, torrent filtering, bulk and
  advanced controls, categories, tags, trackers, limits, and push workflows
- Scheduled-task lifecycle, Cron editing, migration-task assistance, Markdown
  execution results, termination, deletion, and result-history management
- Notice lifecycle, unread and app badges, local notifications, Markdown detail,
  gap-free APP/server log pause/resume, updates, backup/import, users,
  paginated authorization management, and maintenance
