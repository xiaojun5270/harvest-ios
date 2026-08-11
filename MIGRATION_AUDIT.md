# iOS Native Migration Audit

Audit date: 2026-08-11

Reference: the Flutter implementation in the parent repository and its active
UI/service call sites.

## Scope and Current Status

This audit maps the active Flutter mobile workflows to native iOS screens and
service calls. It is a living source-level checklist, not a certification that
the two clients are already identical at runtime. The native target currently
uses 86 `APIPath` entries, including all three first-run setup endpoints.
Flutter constants not mirrored as product screens are interceptor-only auth
routes, inactive feature constants, or alternate trailing-slash forms.

The confirmed gaps found in the latest comparison have been implemented below.
An authoritative 1:1 result still requires an Xcode 26 build, API integration
pass, and device testing against a reachable Harvest server.

## Latest Corrections

- WebKit LocalStorage injection now follows the configured site's base,
  `www`, and mobile host aliases. Token-backed M-Team/Rousi sessions install
  the same narrowly scoped fetch/XHR authorization bridge as Flutter, while a
  per-origin cleared marker prevents the configured credentials from being
  silently restored after the user clears current-site browser data.
- Bonus exchange now exposes completed/total progress, remaining balance, the
  inter-submit countdown, pause/resume, and stop controls throughout a batch.
  Cancellation exits without reporting a request failure and reloads the page
  so the displayed balance can be refreshed.
- Transmission settings now expose and submit only the writable fields used by
  Flutter instead of echoing version, free-space, and other read-only session
  status values. Known qBittorrent and Transmission enums use typed pickers
  while booleans, numbers, text, and structured values retain their native
  editors.
- Browser profile extraction is now available when `page_user` supplies only a
  `{}` UID placeholder, matching Flutter's URL-based UID fallback even when no
  explicit `my_uid_rule` exists.
- Single browser/manual pushes now include a parsed `ids` value just like
  Flutter; the field is no longer deferred until the monkey-push batch branch.
  This preserves the torrent identity needed by generated-link workflows even
  when only one detail URL was intercepted or extracted.
- First-run setup now consumes `database_defaults` from `/api/setup/status`,
  recognizes PostgreSQL aliases, reapplies the correct values when switching
  database type, validates the full TCP port range, and sends the same minimal
  administrator payload as Flutter.
- Dashboard, site-list, and TMDB/Douban catalog responses now use persistent,
  account-scoped session caches. Cached content appears immediately with its
  timestamp, refreshes in the background, survives partial endpoint failures,
  and is removed by the matching local-data cleanup actions.
- The login form now restores the latest matching server, username, and
  Keychain password. History selection restores all three fields before direct
  login, while deleting a history entry also deletes its saved password.
- Download refresh now persists the enabled state, 1-60 second interval, and
  1-60 minute automatic-stop duration. The page exposes its countdown, manual
  pause/resume, immediate refresh, and reconnects WebSockets when settings
  change instead of using hard-coded subscription intervals.
- Site detail now edits all ten Flutter feature flags with optimistic rollback
  and a complete-site PUT. Its full status view covers daily and monthly
  totals, deltas, activity, share ratio, seeding volume/days, bonus per hour,
  and expandable history records.
- IPA fallback links now resolve to the native repository at
  `xiaojun5270/harvest-ios` when the update payload supplies a release file name
  without an absolute URL.
- Downloader listeners now reconcile after refresh, external list changes,
  enable/disable, editing, and deletion. Cancelled listeners cannot clear the
  connection state of their replacements, and one unavailable downloader no
  longer discards the others' torrent data.
- TMDB and Douban searches fail independently and discard stale query results,
  matching the Flutter search serial behavior.
- Search submissions now cancel the previous URLSession/SSE task on resubmit,
  clear, mode change, explicit stop, and view dismissal. Resource batches appear
  while the stream is active and duplicate rows are discarded by stable
  site/torrent identity.
- Site mail and announcements remain separate, the full active Flutter
  condition/sort set is available, and keep-account/graduation filters use the
  loaded site-level configuration.
- Site availability, condition, sort field, and direction now persist with the
  same default-direction rules as Flutter and are included in local UI-data
  cleanup.
- Authorization management now provides the same 20-1000 row page-size choices,
  result ranges, and previous/next paging as Flutter.
- Pausing logs now stops the active poll/SSE task instead of silently discarding
  frames. Resuming reloads a current snapshot before reconnecting, so entries
  produced during the pause are recovered.
- Starting a new media search now clears the previous media result set before
  loading, matching Flutter's submitted-search state. Local UI-data cleanup also
  resets live site/search screens and removes persisted search scope settings.
- TMDB and Douban now use Flutter's disabled-by-default entry behavior, including
  hiding the News tab when both sources are disabled. Site-timeline title mode
  and all seven optional fields now persist with Flutter's defaults and grouping.
- M-Team pushes now lock download-link generation on, and qBittorrent's default
  advanced push parameters are submitted even when the editor section is folded.
- Site decoding now follows Flutter's false defaults for absent availability,
  info, and freeleech flags, while the create form still enables a new site by
  default as Flutter does.
- The site-config generator now offers grouped structured fields, switches, and
  add/edit/delete level controls while retaining a raw TOML mode. Fallback TOML
  generation supports nested tables.
- Site detail, site creation support data, task data, and downloader tool data
  load independently so one optional endpoint cannot erase successful sibling
  results.
- Task-result actions now match Flutter's complete state table: queued results
  can be terminated, only completed results expose record deletion, and status
  aliases share the same waiting/running/success/failure labels.
- Missing managed-user activation flags now default to disabled, and server log
  warning filters send `WARN` while still matching native `WARNING` app records.

## Performance and Persistent Cache Pass (2026-08-11)

- Removed eager dashboard long-image rendering from startup, pull-to-refresh,
  automatic refresh, cache clearing, and quick actions. The image is now
  rendered only after the share command is selected.
- Replaced downloader and server-monitor one-second `@Published` countdowns
  with deadline-based tasks and localized `TimelineView` labels, preventing the
  full dashboard/download hierarchy from being diffed every second.
- Downloader list data now restores from an account-scoped safe snapshot,
  loads enabled clients concurrently, pre-indexes site domains, caches filtered
  and sorted results, batches speed updates, and ignores unchanged torrent
  WebSocket frames. Live snapshot persistence is throttled.
- Site filtering/sorting is recomputed only after data or filter changes. Log
  filtering is evaluated once per render, while complete log text is built only
  when copy/share is requested.
- Replaced all `AsyncImage` use with a shared public-image cache backed by
  `NSCache` and bounded `URLCache`. URLs containing token, passkey, authkey,
  API-key, signature, secret, or credential query fields use an ephemeral
  memory-only session.
- Added stale-while-revalidate snapshots for downloads, scheduled tasks, and
  notices. Task arguments/result bodies and notice bodies are intentionally
  excluded from those snapshots.
- Persistent business cache entries are isolated by server and username,
  limited to 12 MiB each and 48 MiB total, expire after 45 days, and are
  excluded from backups. Existing cache files are sanitized on first access;
  passwords, Cookie/LocalStorage, authorization data, keys, tokens, passkeys,
  authkeys, and credential-bearing feed URLs are removed without changing the
  original cache timestamp.
- This pass is statically verified on Windows. It does not claim measured frame
  time, memory, energy, or network improvements until Instruments and device
  testing are run from Xcode.

## Verified Functional Coverage

- HTTP and HTTPS authentication, nested token response parsing, refresh retry,
  server-provided first-run database defaults, database/admin setup, Keychain
  credentials, full login-history restoration, direct account switching,
  logout, and complete persistent-data cleanup.
- A single root `NavigationStack`, native system `TabView`, iOS 26 Liquid Glass,
  a material fallback on iOS 17-25, plus persisted appearance, accent, density,
  and type-size controls. Modal sheets own only their independent navigation
  stacks.
- Dashboard overview, trends, server resources, distributions, privacy masking,
  configurable module visibility, refresh settings, current-screen sharing, and
  a dedicated long dashboard image. Dashboard, sites, and news restore
  account-scoped cached data before their live refresh completes.
- Site status, ten editable feature flags, daily/monthly status charts and
  history, separate mail/announcement counts, timeline, level progress, sign-in
  history, add/edit/delete, refresh/sign/repeat, full filtering/sorting, bulk
  upgrade, PTPP/PT-depiler/CookieCloud imports, TOML import, and structured or
  source-mode site-configuration generation. The add flow includes the
  not-yet-added catalog and browser-extracted profile fields.
- Authenticated WebKit browsing with Cookie, LocalStorage, complete custom
  User-Agent handling, configured page shortcuts, credential synchronization,
  torrent/profile extraction, intercepted torrent downloads, current-site
  cleanup, and bonus exchange.
- Downloader lifecycle, connectivity tests, configurable real-time refresh,
  countdown and pause/resume, WebSocket recovery, speed mode, category/tag
  management, tracker replacement, preferences, torrent detail, selection,
  file-directory trees, virtual Tracker filtering, bulk controls, advanced
  qBittorrent actions, share limits, manual push, advanced push, and monkey
  push.
- Scheduled-task lifecycle, Cron editing, task results, Markdown result detail,
  active-result termination, history deletion, and torrent-migration assistance.
- TMDB movie/TV/person catalogs and details, Douban hot/rank/Top 250/tags/detail,
  search history, combined media/resource search, filters, limits, cancellable
  and deduplicated incremental SSE results, and downloader push.
- Notice read/delete lifecycle, Markdown detail, unread toolbar badge, iOS app
  badge, local notifications, foreground presentation, and notification-tap
  routing to the notice list.
- APP and server log sources, SSE reconnect, gap-free pause/resume,
  level/search filters, follow mode, font sizing, top/bottom navigation, copy,
  clear, reload, and share.
- Backend options, Telegram/WeChat tools, users, invitations, authorization,
  authorization paging, update logs, program/site updates, speed test, backup
  export/import, legacy import, cache clear, service restart, and APP version
  history.
- APP update payloads in `downloadLinks`, `download_links`, `downloads`, and
  `assets` map/list forms, iOS/IPA filtering, public update-service fallback,
  Markdown release notes, and TestFlight installation.

## Intentional Platform Differences

- Desktop sidebars, window controls, and floating log windows are not applicable
  to iOS. Their underlying workflows remain available in native screens.
- The Flutter client's multiple visual site-card styles are replaced by one new
  native design. All card modules use the requested 24-point continuous radius.
- iOS cannot silently install an unsigned IPA. The app opens an IPA/download
  address or TestFlight; signing and installation remain external operations.
- Native system navigation and controls replace Flutter widget-level styling, so
  visual structure follows iOS conventions while preserving behavior and data.

## Endpoint Notes

- `TOKEN_VERIFY` and `LOGIN_URL` are referenced only by Flutter authentication
  interception, not by a user-facing workflow.
- `AUTH_INFO` only controls visibility of a special-email authorization entry.
- `push_torrent/` versus `push_torrent` is a trailing-slash spelling difference.
- Subscription/resource-management/Flower and several TMDB constants have no
  active Flutter UI call site and therefore are not migration gaps.

## Verification Limits

Tree-sitter syntax parsing, `git diff --check`, plist validation, Xcode project
references, API path use, and asset metadata can be checked on Windows.
SwiftUI/WebKit/UserNotifications type checking, signing, Liquid Glass rendering,
and end-to-end device behavior require Xcode 26 and an iOS 17-26 runtime. The
verification section must therefore not be read as a successful Apple SDK build.
