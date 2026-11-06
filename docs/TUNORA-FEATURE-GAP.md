# Tunora — Feature Inventory (from screen recording, 2026-11-06)

Extracted frame-by-frame from `ScreenRecording_11-06-2026 10-12-22_1.MP4` (2m31s).
This is **what Tunora shows**, not yet a comparison with TuneTube — the codebase survey
was not finished in this session.

Tunora v1.0.6. App Store name: "Offline Music Player: Tunora". Accent colour: mint green
on pure black. Support site hosted on a Cloudflare Workers domain (`*.workers.dev`).

---

## Tab bar (4 tabs)

`Home` · `Library` · `Search` · `Favorite`

TuneTube currently has Home / Search / Library / Profile — note Tunora promotes
**Favorites to a top-level tab** and has no account/profile tab at all (no sign-in).

---

## 1. Home

Header: logo + "Tunora", tagline "Music for every mood", a **Pro (diamond)** button and a
**Settings (gear)** button.

### Horizontal genre/mood chip bar (pinned under the header)
Scrolls horizontally, stays visible while the feed scrolls. Chips seen:
`All`, `Chill`, `Commute`, `Energize`, `Feel good`, … `Classical`, `Country & Americana`,
`Dance & …`, `Pop`, `Punjabi`, `R&B & soul`, `Reggae & caribbean`, `Rock`, `Tamil`, `Telugu`.
Selecting a chip reloads the whole feed (observed: tapping `Reggae & caribbean` emptied the
feed and showed an animated logo spinner).

### Shelves (region = Bangladesh)
| Shelf | Item type | Notes |
|---|---|---|
| Top Artists | artist cards, tall portrait | has `See all`; placeholder mic icon when no image |
| Video charts | chart playlists | "Daily Top Music Videos - Global", "Top 100 Music Videos Global" |
| Indian Music | playlists | "Uncut Bollywood", "00s Bollywood Romance", "10s Bollywood Dance" |
| Trending community playlists | user playlists | shows **author name + view count** ("Rudra Dj Tarapur · 1…") |
| Fresh drops | tracks/videos | |
| Ghazal & Sufi Essentials | playlists | |
| New releases | albums/singles | subtitle shows `Album • Passenger`, `Single • Kumaar, Amit…` |

### Shelves (region = Brazil, after switching)
Feed is genuinely region-driven, not just relabelled:
| Shelf | Notes |
|---|---|
| Top Artists | Henrique & J…, MC Ryan SP, Marília Mend… (Brazilian artists) |
| Video charts | "Trending 20 Brazil", "Daily Top Music Videos - Brazil", "Top 100 Music Videos Brazil" |
| Indian Music | still present (appears to be a fixed shelf) |
| Quick picks | **compact track list** with per-row `…` overflow menu, horizontally paged |
| Featured playlists | "Tollywood Hitlist", "New Music Telugu", "Tollywood Dance Essential" |
| Community playlists | |
| Music videos | large 16:9 cards, subtitle `2 min 23 sec • Ahmed Khan Du…` |
| Albums | subtitle `EP • Anirudh`, `Album • Anirudh` |

So: roughly **8–10 distinct shelf types**, each with `See all`, sourced from
YouTube Music's region-scoped home feed.

---

## 2. Library ("Your Library")

- Header: `+` (new playlist), Pro, Settings.
- Two big tiles: **Playlists** (`1 playlist`) and **Local** (`None yet`).
- **Recently Played** horizontal row with `See all`.
- **Your Playlists** list with per-row `…` menu, plus a `New Playlist` row.
- **Local** screen: own nav bar, `Search in library` field, an **import (download-arrow)
  button**, empty state "No songs on your device yet. Import your own music to see it here."
  → Tunora supports **importing the user's own files** (privacy policy mentions
  Files, Apple Music picker, and **Wi-Fi transfer**).

---

## 3. Search

- Search field with a **rotating placeholder** — cycles "Search artists" → "Search playlists"
  → "Search music".
- **Browse by mood** grid, 2 columns, photographic cards:
  `Chill / Commute`, `Energize / Feel good`, `Focus / Gaming`, `Party / Romance`,
  `Sad / Sleep`, `Workout / African` — each with a one-line subtitle
  ("Relax & unwind", "Deep concentration", "Power up your play", …).

---

## 4. Favorites (own tab)

- **Play all favorites** hero card with artwork collage + big play button, "3 songs".
- Sections: **Songs**, **Artists** ("Follow artists to see them here"),
  **Playlists** ("Favorite playlists to see them here").
  → implies **artist following** and **favouriting playlists**, not just tracks.

---

## 5. Player

Top bar is a **segmented three-tab player**: `Now Playing` · `Lyrics` · `Related`,
with a chevron-down to dismiss. Background is tinted from the artwork.

- Large rounded artwork.
- Title + subtitle `artist • 21M views • album/film`.
- Three pill buttons: **Favorite**, **Playlist** (add to), **Sleep timer**.
- Scrubber with elapsed / remaining.
- Controls: shuffle · previous · large circular play/pause (glowing mint) · next · **queue**.

### Queue sheet
- "Queue", current track highlighted mint, then a **"Shuffling from:"** section header.
- Rows are **drag-reorderable** (grab handles).
- Bottom bar inside the sheet: **Shuffle** and **Timer**.

### Sleep timer sheet
`Off` (checked) · `5 min` · `10 min` · `30 min` · `End of this track` · `Current playlist` · Close.

### Mini player
Artwork, title, `artist • views • album`, play button, thin progress line. Sits above the tab bar.

---

## 6. Settings

| Section | Item | Detail |
|---|---|---|
| — | **Upgrade to Pro** banner | "Unlimited playlists, equalizer & more" |
| GENERAL | Language | `English` |
| AUDIO | **Equalizer** | gated `PRO` |
| AUDIO | **Region** | `🇧🇩 Bangladesh` → switched to `🇧🇷 Brazil`, whole home feed changed |
| AUDIO | **Gapless playback** | toggle, on |
| AUDIO | **Sleep timer** | toggle, off |
| SUPPORT & FEEDBACK | Report a bug | opens prefilled mail to `tunora.support@gmail.com` with app version `1.0.6 (010006005)`, device, iOS version |
| SUPPORT & FEEDBACK | Send feedback | mail |
| SUPPORT & FEEDBACK | Rate Tunora | App Store review |
| ABOUT | Privacy policy | in-app browser → hosted support site |
| ABOUT | Terms of service | same |
| ABOUT | Version | `1.0.6` |

---

## 7. Monetization

Tunora **does** have a paywall ("Tunora Pro", Halloween Special, Monthly / Lifetime with a
"Halloween Deal" badge, Restore button, "Help us keep Tunora ad-free for all",
"Thank you for supporting indie development"). Gated: Unlimited Playlists & Favourites,
Studio Equalizer, "More Coming Soon".

**TuneTube deliberately does not do this** — `AGENTS.md` §2A says the app is free,
`isPro` is always `true`, and no playlist limits. That difference is a product decision,
not a gap to close.

---

## What the user called out explicitly

1. Many more home shelves, and **region-driven** ones.
2. Genre/mood chip bar on Home.
3. Top artists for the region; artist following.
4. Video charts shelf.
5. Trending **community** playlists (with author + view count).
6. Browse-by-mood grid in Search.
7. **Search results should be cached** — "in the browser search there is no cache,
   there should be a cache".
8. Player: Lyrics tab, Related tab, Queue with reorder, Sleep timer presets.
9. Settings: Language, Equalizer, Region, Gapless playback, Sleep timer,
   Report a bug, Send feedback, Rate, Privacy policy, Terms of service, Version.
10. Local music import.

---

---
---

# Part 2 — Gap table: TuneTube vs Tunora

Based on a read of all 45 Swift files and the Cloudflare Worker in `server/`.

**Headline: the gap is much smaller than the recording suggests.** TuneTube's backend
already exposes home, search (with type filters), artist, playlist, category, radio,
lyrics and remote config, all region-scoped and KV-cached. Most of what looks missing is
either (a) an endpoint the app never calls, or (b) a hardcoded constant.

Legend: ✅ have · 🟡 partial · ❌ missing · ➖ deliberate difference

## Shell & navigation

| Feature | Tunora | TuneTube | Where |
|---|---|---|---|
| Tab bar | Home / Library / Search / **Favorite** | Home / Search / Library / **Profile** | [RootView.swift:116](TuneTube/App/RootView.swift:116) |
| Favorites as a top-level tab | ✅ | ❌ — Favourites is a seeded SwiftData playlist inside Library | [LibraryStore.swift:8](TuneTube/Features/Library/LibraryStore.swift:8) |
| Sign-in / account | none at all | ✅ Sign in with Apple + delete account | [ProfileView.swift](TuneTube/Features/Profile/ProfileView.swift) |
| Settings screen | ✅ dedicated, grouped | 🟡 six stub rows in Profile, **all with empty `{}` actions** | [ProfileView.swift:156](TuneTube/Features/Profile/ProfileView.swift:156) |

## Home

| Feature | Tunora | TuneTube | Notes |
|---|---|---|---|
| Shelf count | ~8–10, region-specific | 8, fixed | `HOME_MANIFEST` in [config.ts:58](server/src/config.ts:58) |
| Greeting header | ❌ (logo + tagline) | ✅ "Good morning, {name}" | — |
| Recently played | ✅ | ✅ | [RecentStore.swift](TuneTube/Core/RecentStore.swift) |
| **Genre/mood chip bar on Home** | ✅ pinned, reloads feed | ❌ | chips exist, but only on Search |
| **`See all` per shelf** | ✅ every shelf | ❌ | no destination route exists |
| Region-specific shelves | ✅ (BD→BR changed everything) | ❌ | see "Region" below |
| Video charts shelf | ✅ | ❌ | not in the manifest |
| Top Artists shelf | ✅ | ❌ | manifest has no artist shelf |
| Community playlists w/ author + views | ✅ | 🟡 shelf exists, but `Shelf`/`MediaItem` carry no author or view count | [Models.swift:95](TuneTube/Core/Models.swift:95) |
| Albums / New releases | ✅ typed (`Album • Passenger`) | 🟡 `MediaKind.album` exists, no dedicated shelf | — |
| Pull to refresh | — | ✅ | [HomeView.swift:43](TuneTube/Features/Home/HomeView.swift:43) |

## Search

| Feature | Tunora | TuneTube |
|---|---|---|
| Text search | ✅ | ✅ debounced 450ms |
| **Response caching** | unknown | ✅ **three layers** — in-memory dict, `DiskCache` 15min TTL, Worker KV 10min, plus a `search-last-loaded` fallback when rate-limited |
| Browse-by-mood | ✅ 12 photographic cards | 🟡 8 emoji **text chips** |
| Mood chip opens a category page | ✅ | ❌ — chip just runs a text search for its label ([SearchView.swift:104](TuneTube/Features/Search/SearchView.swift:104)) while `/v1/category/:key` sits unused |
| Trending searches | ❌ | ✅ remote-configured |
| **Search history / recents** | — | ❌ |
| Typed filters (songs/albums/artists) | ✅ implied | 🟡 server has `SEARCH_FILTERS`, app never sends `type` |

> On the "no cache in search" note: TuneTube's search caching is actually strong. What it
> lacks is a **recent-searches list**, which is probably what felt missing.

## Library

| Feature | Tunora | TuneTube |
|---|---|---|
| Create playlists | ✅ | ✅ unlimited, with custom icon + colour |
| Playlist edit/delete | ✅ `…` menu | ✅ swipe actions |
| Recently played row | ✅ | ❌ in Library (it's on Home) |
| Playlists / Local summary tiles | ✅ | ❌ flat list |
| **Local file import** | ✅ Files + Apple Music + Wi-Fi transfer | 🟡 `fileImporter` in Downloads ([DownloadsView.swift:76](TuneTube/Features/Library/DownloadsView.swift:76)) — Files only |
| Offline downloads | not shown | ✅ full manager, `Documents/OfflineMusic/`, backup-excluded |
| Search within library | ✅ | ❌ |

## Player

| Feature | Tunora | TuneTube |
|---|---|---|
| Lyrics | ✅ inline tab | ✅ sheet, RTL-aware, 7-day cached |
| Related / radio | ✅ inline tab | 🟡 "Start mix" exists but is queue-only, no browsable Related view |
| Queue | ✅ reorder | ✅ reorder + swipe-delete + **Autoplay toggle** |
| Sleep timer | ✅ 6 presets | ✅ same, in the `…` menu and a chip |
| Shuffle | ✅ | ✅ |
| **Repeat** | ❌ not seen | ✅ off/all/one |
| Favourite / Add to playlist | ✅ | ✅ |
| AirPlay | ❌ not seen | ✅ |
| **Video mode** | ❌ audio only | ✅ dual-engine AVPlayer + YouTubePlayerKit |
| Artwork swipe to change track | ❌ not seen | ✅ |
| **Three-tab player layout** | ✅ Now Playing / Lyrics / Related | ❌ sheets instead |

## Settings — the biggest real gap

Every row below is a stub or absent in TuneTube.

| Row | Tunora | TuneTube | Effort |
|---|---|---|---|
| **Region** | ✅ picker, drives the whole feed | ❌ `AppConfig.region = "US"` is a **`let` constant** ([AppConfig.swift:39](TuneTube/Core/AppConfig.swift:39)) | **Small** — it's already sent as `gl` on every request and is already part of the Worker's cache key |
| **Language** | ✅ | ❌ same, `hl` hardcoded `"en"` | **Small** |
| **Equalizer** | ✅ (Pro) | ❌ nothing in `PlayerEngine` | Large — needs `AVAudioEngine`/`AVAudioUnitEQ` |
| **Gapless playback** | ✅ toggle | ❌ | Medium |
| Sleep timer in Settings | ✅ | ➖ lives in the player instead |
| Report a bug | ✅ prefilled mail | ❌ stub row | Small |
| Send feedback | ✅ | ❌ stub row | Small |
| Rate app | ✅ | ❌ stub row (`{}`) | Small — `SKStoreReviewController` |
| Privacy policy / Terms | ✅ hosted pages | ❌ stub rows | Small — needs hosting |
| Version | ✅ | ✅ shown at the bottom |

## Deliberate differences — not gaps

| | Tunora | TuneTube |
|---|---|---|
| Paywall | Pro tier, playlist limit, gated equalizer | ➖ free by policy (`AGENTS.md` §2A) |
| Accounts | none | ➖ Sign in with Apple |

⚠️ **Inconsistency to fix:** the Worker still serves `freePlaylistLimit: 1` and a full
`paywall` block ([index.ts:145](server/src/index.ts:145)), and `LibraryView` still reads
`config.freePlaylistLimit` into `freeLimit` even though the check is commented out. Dead
config contradicting the stated policy.

---

# Build order

### Tier 1 — high impact, small change
1. **Region + Language picker.** Move `AppConfig.region`/`language` to `@AppStorage`,
   add a Settings picker, clear `DiskCache` on change. The Worker, cache keys and
   `gl`/`hl` plumbing already exist. This alone produces the "everything changes"
   effect from the recording.
2. **Wire up the stub Settings rows** — Rate, Report a bug, Send feedback (prefilled
   `mailto:` with version/device like Tunora's), Privacy, Terms.
3. **Mood chips → category pages.** Call the existing unused `/v1/category/:key`
   instead of text-searching the chip label.
4. **Recent searches list.**

### Tier 2 — structural, medium
5. **`See all` per shelf** — needs a `Route.shelf`/`.category` destination.
6. **Genre chip bar on Home**, reloading the feed per chip.
7. **Richer `HOME_MANIFEST`** — add Top Artists, Video charts, New releases, Albums.
   Note the manifest matches source shelves by **English title**, so it must become
   region-aware or match on browseId before region switching gives good shelves.
8. **Favorites as its own tab**, with Songs / Artists / Playlists sections.
9. **Photographic mood cards** in Search instead of emoji chips.

### Tier 3 — larger
10. **Three-tab player** (Now Playing / Lyrics / Related) replacing the sheets.
11. **Artist following** — needs a new model, store and a Favorites section.
12. **Equalizer** — `AVAudioEngine` rework of `PlayerEngine`.
13. **Gapless playback.**
14. Richer local import (Apple Music picker, Wi-Fi transfer).

### Cleanup
15. Remove the dead paywall config from the Worker and the `freeLimit` read in
    `LibraryView`, per `AGENTS.md` §2A.
