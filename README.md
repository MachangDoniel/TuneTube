# TuneTube

A YouTube-backed music app for iOS. Browse, search and play music with a native
music-app interface — the catalog, artwork and audio all come from YouTube.

Two pieces:

- **`TuneTube/`** — a SwiftUI iOS app (~2,400 lines)
- **`server/`** — a Cloudflare Worker that proxies and caches YouTube Music
  metadata (~1,000 lines TypeScript)

```
iOS app  ──►  Cloudflare Worker  ──►  music.youtube.com/youtubei/v1
   │           (parse + KV cache)
   │
   └────────►  youtube.com/embed  (playback, in a WKWebView)
```

---

## How it works

### Playback

The player is the **official [YouTube IFrame Player API](https://developers.google.com/youtube/iframe_api_reference)**
running inside a `WKWebView`, via [YouTubePlayerKit](https://github.com/SvenTiigi/YouTubePlayerKit).
TuneTube draws its own transport controls and drives the embed over
`postMessage`; the embed stays visible with YouTube's branding and ads intact.

Nothing is extracted, downloaded, or re-hosted. That is a deliberate design
constraint, not an accident — see [Legal and review posture](#legal-and-review-posture).

### Metadata

All catalog data comes from YouTube Music's private **InnerTube** API, proxied by
the Worker. The app never talks to YouTube's API directly, so when YouTube
changes a payload shape the fix is a `wrangler deploy` rather than an App Store
release.

### Library and accounts

Playlists are stored on-device with SwiftData. There is no account system yet;
`Favourites` is seeded locally on first launch.

---

## Screens

| Tab | What it does |
|---|---|
| **Home** | Curated shelves of playlists and tracks, composed from YouTube Music mood/genre categories |
| **Search** | Live search grouped by songs / videos / artists / albums / playlists, plus mood chips and trending searches |
| **Library** | User playlists. `Favourites` is seeded and permanent; more playlists require Pro |
| **Profile** | Account placeholder, restore purchases, legal links |

Plus artist pages, playlist detail, a full-screen player, and a mini player that
persists across tabs.

---

## Quick start

**1. Start the Worker** (the app points at it):

```bash
cd server && npm install && npx wrangler dev --ip 0.0.0.0 --port 8799
```

`--ip 0.0.0.0` matters. Wrangler binds to `127.0.0.1` by default, which a
physical iPhone can never reach.

**2. Generate and open the Xcode project:**

```bash
xcodegen generate && open TuneTube.xcodeproj
```

Run on any iOS 17+ simulator or device.

### Running on a physical device

`localhost` does **not** work on a real iPhone — the phone resolves it to
itself, which shows up as `NSURLErrorCannotConnectToHost (-1004)` with
"Connection refused" on `127.0.0.1`. Two things are needed:

1. Start the Worker with `--ip 0.0.0.0` (above).
2. Point the app at your Mac's Bonjour name rather than localhost. This is the
   `API_BASE_URL` build setting in `project.yml`:

   ```yaml
   API_BASE_URL: http://Your-Mac-Name.local:8799
   ```

   Find yours with `scutil --get LocalHostName`. The `.local` name is used
   rather than a LAN IP because it survives DHCP changes, and because
   `NSAllowsLocalNetworking` in `Info.plist` covers it without weakening ATS.
   The same URL works in the Simulator too, so there is only one setting.

Resolution order at runtime: `TUNETUBE_API` environment variable →
`TuneTubeAPIBaseURL` from Info.plist → `http://localhost:8799`. In DEBUG builds
the connection-failure message names the URL it actually tried.

> **Run from Xcode, not `simctl`**, if you need to test purchases — StoreKit
> configuration files only apply when launched through the scheme.

---

## Project layout

```
TuneTube/
├── App/            TuneTubeApp, RootView (tabs + mini player), Navigator
├── Core/           APIClient, DiskCache, Models, Theme, AppConfig
├── Player/         PlayerEngine, PlayerView, MiniPlayerView
├── Features/
│   ├── Home/       HomeView, MediaCard, ShelfRow
│   ├── Search/     SearchView, SearchViewModel
│   ├── Library/    LibraryView, LibraryStore, LibraryModels (SwiftData)
│   ├── Artist/     ArtistView, PlaylistView
│   └── Profile/    ProfileView
├── Monetization/   StoreManager (StoreKit 2), PaywallView
└── Resources/      Info.plist, TuneTube.storekit

server/src/
├── index.ts              Hono routes
├── config.ts             Curated home manifest, mood chips, search filters
├── cache.ts              KV wrapper
├── innertube/client.ts   Session bootstrap + POST helper
├── innertube/parsers.ts  ⚠️ The fragile layer — all payload-shape knowledge
└── routes/               home, browse (artist/playlist/category), search
```

---

## Worker API

| Route | Returns | Cache |
|---|---|---|
| `GET /v1/home` | Curated shelves | 1 h |
| `GET /v1/search?q=&type=` | Results grouped by kind | 10 m |
| `GET /v1/artist/:browseId` | Header, top songs, albums | 24 h |
| `GET /v1/playlist/:playlistId` | Full track list | 6 h |
| `GET /v1/category/:key` | One mood/genre page | 6 h |
| `GET /v1/config` | Mood chips, trending, kill-switches | 5 m |

All routes accept `gl` and `hl` (region/language), and `?nocache=1` to bypass KV.

`/v1/config` is the remote control surface: mood chips, trending searches,
`freePlaylistLimit`, `hiddenShelfIds` (hide a broken shelf without a release) and
paywall copy.

---

## Library and monetization

Free users get exactly **one** playlist: the seeded, undeletable **Favourites**.
Creating a second playlist opens the paywall.

The limit comes from `/v1/config` as `freePlaylistLimit`, so it's tunable without
a release, and the gate lives in exactly one place —
`LibraryStore.canCreatePlaylist` — so the Library tab and the "Add to Playlist"
sheet can never disagree.

| Product ID | Type | Reference price |
|---|---|---|
| `com.tunetube.pro.lifetime` | Non-consumable | £14.99 |
| `com.tunetube.pro.weekly` | Auto-renewable, 1 week | £1.99 |

Billing is **StoreKit 2**, no third-party SDK. `Transaction.updates` is observed
from launch (catching renewals, Ask-to-Buy and refunds), restore uses
`AppStore.sync()`, and the entitlement is cached so an offline launch is never a
silent downgrade.

Prices always come from `Product.displayPrice`. The hardcoded strings in
`PaywallView` are fallbacks only — hardcoding `£14.99` would show the wrong
currency to every user outside the UK.

**Testing the Pro paths from the command line** (where StoreKit config is
unavailable), DEBUG builds honour an override:

```bash
SIMCTL_CHILD_TUNETUBE_FORCE_PRO=1 xcrun simctl launch booted com.tunetube.app
```

---

## Known constraints

### 1. Background audio is unresolved

Playback currently stops shortly after the app is backgrounded. Now Playing
metadata, artwork and remote commands are all wired up, so the lock screen will
look correct the moment audio survives backgrounding — but it does not yet.

Measured, and the options that remain, are documented in
**[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#6-background-audio-investigation)**.

**Next step: re-test on a physical device.** All measurements so far are from the
simulator, which is not authoritative for WebKit media suspension.

### 2. InnerTube is unofficial and will break

YouTube changes payload shapes without notice. Everything shape-aware is confined
to `server/src/innertube/parsers.ts`, covered by fixture tests, and every parser
returns a value instead of throwing — so one YouTube-side change degrades a
single row rather than taking down a screen.

### 3. Accounts are identity-only

**Sign in with Apple** is implemented natively (no third-party SDK) and persists
the identity in the Keychain — necessary because Apple returns the user's name
and email *only on first authorization*.

**Google sign-in** is not wired up. It needs an OAuth client id that only the
project owner can issue. The button is present and reports exactly what is
missing rather than failing silently. To enable it: add the `GoogleSignIn`
package, set `GIDClientID` in `Info.plist`, add the reversed-client-id URL
scheme, and implement `AuthService.signInWithGoogle()`.

Either way this establishes identity only — playlists stay device-local until
there is a backend to sync them to.

---

## Testing

```bash
cd server && npx vitest run     # 10 tests over real InnerTube fixtures
```

The tests run the parsers against checked-in InnerTube responses, including
assertions that the shelves the home manifest depends on still exist. When one
fails, refresh the fixtures and check whether the parser or the payload changed:

```bash
node server/test/capture-fixtures.mjs
```

App build:

```bash
xcodebuild -project TuneTube.xcodeproj -scheme TuneTube \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

---

## Code Review & AI Guidelines

This project uses [CodeRabbit](https://coderabbit.ai) for automated PR reviews configured via [`.coderabbit.yaml`](.coderabbit.yaml).

> **Instruction for AI Assistants**: Whenever an AI assistant completes changes, prepares a commit, or opens a pull request, **always ask the developer whether they want to go through a CodeRabbit review** before finalizing or merging. See [`AGENTS.md`](AGENTS.md) for details.

---

## Legal and review posture

Worth being clear-eyed about, because it shapes the architecture:

- **Playback uses the sanctioned embed**, visible, with ads and branding intact.
  This is the defensible position under App Store guideline 5.2.3. Apps that
  stream YouTube via extraction libraries get rejected, and appeals require
  documentary proof of rights.
- **The paywall gates our own features** (playlists), never access to content.
  Selling access to a third-party catalog is what gets apps pulled.
- **Metadata comes from InnerTube**, which is not a public API and is outside
  YouTube's terms. This is the part of the stack most exposed if YouTube objects;
  the proxy design means it can be swapped for the official Data API without an
  app release.

Do not "fix" background audio by extracting stream URLs without understanding
that it moves the app squarely into 5.2.3 territory.

---

## Status

**Working:** Worker (6 endpoints, KV caching, remote config, 10 tests), Home,
Search, Artist, Playlist, Player, mini player, Library with SwiftData, StoreKit 2
paywall, Now Playing metadata and artwork, Sign in with Apple, cached artwork.

**Open:** background playback, Google sign-in, cross-device sync, playlist
import, Profile row actions (Rate/Privacy/Terms/Support are not yet wired).
