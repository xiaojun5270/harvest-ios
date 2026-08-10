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

The primary workflows below are implemented, but this is not yet an
endpoint-for-endpoint port of the Flutter client. See
[`MIGRATION_AUDIT.md`](MIGRATION_AUDIT.md) for the verified gaps and test limits.

## Implemented core workflows

- Login history, Keychain credentials, access-token refresh, and first-run setup
- TMDB/Douban news, media details, and combined media/resource search with SSE
- Site overview, filtering, add/edit, authenticated browsing, refresh, sign-in,
  repeat, detail, and delete
- Dashboard totals, traffic chart, privacy mode, and server resource status
- Downloader setup, torrent push, live polling, filtering, and controls
- Scheduled task create/edit/enable/run/delete and execution-result management
- Notice detail/read/delete operations, users, authorization, logs, cache,
  notification test, service restart, appearance, account switching, and logout
