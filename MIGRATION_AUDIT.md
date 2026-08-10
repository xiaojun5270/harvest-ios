# iOS Native Migration Audit

Audit date: 2026-08-11

Reference implementation: the Flutter source in the parent repository.

## Conclusion

The native iOS app is not yet a complete functional port. It covers the primary
daily workflows, but several advanced administration, import, downloader, media,
and maintenance workflows still exist only in the Flutter client.

A static scan resolved about 86 distinct Flutter API base paths. The native app
references 47 `APIPath` constants plus two setup endpoints, for about 49 paths.
This is only a coverage indicator: some features use alternative endpoints, and
sharing an endpoint does not mean that every operation on that endpoint has
been ported.

## Implemented And Corrected

- Native SwiftUI shell with an iOS 26 Liquid Glass tab bar and an iOS 17-25
  material fallback.
- HTTP and HTTPS login, nested access/refresh token parsing, Keychain storage,
  refresh retry, account history, and first-run database/admin setup.
- Dashboard totals, monthly traffic trend, privacy masking, and server-resource
  SSE updates.
- Site list, search, add/edit/delete, refresh, sign-in, repeat, status parsing,
  all account/sort fields from the Flutter form, and authenticated WebKit
  browsing with Cookie, LocalStorage, and User-Agent injection.
- Downloader add/edit/delete/enable, preferences JSON, repeat, polling, torrent
  filtering, basic qBittorrent/Transmission controls, torrent detail, and manual
  push options.
- Task create/edit/delete/enable/run, editable five-field Cron schedules, result
  detail, active-result termination, individual result deletion, and
  result-history clearing.
- TMDB/Douban search, normalized posters, media detail, resource-search SSE, and
  pushing a search result to a downloader.
- Notice list/detail, individual/all read operations, individual/all deletion,
  and notice links.
- Backend option editing, user credentials/status management, authorization
  records, token reset/email, invite reset, logs, cache clear, notification test,
  service restart, appearance, logout, and dynamic app version display.

## Partially Ported

### Sites

- Missing custom TOML upload and site-config generation/editing.
- Missing PTPP, PT-depiler, and CookieCloud import flows.
- Missing bulk field upgrade, drag sorting, status timeline/chart, level details,
  and sign-in history details.
- Basic authenticated browsing is present, but the Flutter browser's configured
  page shortcuts, credential synchronization, profile/torrent extraction,
  download interception, and bonus-exchange tools are not ported.

### Downloaders And Torrents

- Uses polling rather than the Flutter WebSocket lifecycle and reconnect logic.
- Missing speed-limit mode, connectivity test, category and tag CRUD, tracker
  replacement, and batch monkey push.
- Missing bulk selection and advanced torrent actions such as recheck,
  reannounce, queue priority, move data, category/tag changes, tracker editing,
  force start, auto management, super seeding, and share limits.
- Preferences are editable as JSON, not with the full qBittorrent and
  Transmission native forms.

### News And Search

- Popular TMDB movies/TV and basic details are present.
- Missing the Flutter catalog views for playing, upcoming, airing today,
  on-the-air, top-rated, and latest media.
- Missing Douban hot tags, rank lists, Top 250, richer detail presentation,
  search history, site filters, result limits, and the complete advanced push
  form.

### Tasks

- Core schedules and results are supported.
- Missing the specialized torrent-migration task editor and its downloader/path
  assistance.

### Administration And Maintenance

- Missing update logs, site-definition update logs, Docker/program update UI,
  speed test, Telegram webhook, and WeChat QR binding.
- Missing full backup export/import, legacy Harvest import, and legacy SQLite
  import.
- Logs are a snapshot list; the Flutter streaming log source and its richer
  controls are not ported.
- The Flutter-only screenshot/share, app-upgrade, and persistent-data cleanup
  controls are not ported.

## Verification Limits

The source is currently being edited on Windows, where Xcode and the Apple Swift
SDK are unavailable. Tree-sitter syntax parsing, plist validation, project-file
checks, and API-path checks can run locally, but an authoritative compile and
runtime test still requires Xcode 26 on macOS.
