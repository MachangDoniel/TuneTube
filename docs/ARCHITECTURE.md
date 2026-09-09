# Architecture and decisions

Why TuneTube is built the way it is, and what was measured rather than assumed.
Read [../README.md](../README.md) first for the overview.

---

## 1. What this app is a clone of

TuneTube reproduces a shipping App Store app of the same shape (the reference
build identifies itself as `MuseTube 2.0.1`). Its architecture was determined by
frame-by-frame analysis of a screen recording, then confirmed against live APIs.

**Evidence that playback is the YouTube IFrame embed:**

The reference player screen shows YouTube's own chrome — channel avatar, video
title, channel name (`dojacatVEVO`), CC button, settings gear, red scrubber,
share, and the "Watch on YouTube" logo — with the app's own transport controls
drawn *below* it. The two clocks disagree (`5:16` in the embed, `5:15` on the app
slider), so the app keeps independent state and drives the iframe rather than
owning the timeline.

Our build reproduces the same one-second discrepancy, which is a good sign we
matched the mechanism rather than the appearance.

**Evidence that metadata is YouTube Music, passed through:**

- Shelf titles are verbatim YTM shelves: `Quick picks`, `New releases`,
  `Feeling happy`, `Throwbacks`, `Pump it up`, `All-time essentials`,
  `Irresistible sing-alongs`.
- Card subtitles follow YTM's `playlist — artist` form.
- Track titles are raw video titles, truncated mid-parenthesis
  (`Kiss Me More (Offi…`, `Boots (feat. Shani…`). A real music catalog would say
  "Kiss Me More".
- Artwork is `i.ytimg.com` thumbnails cropped square — the letterboxing bleed is
  visible on the cards.

Confirmation: the live `FEmusic_home` response's first shelf is literally
`Trending community playlists`, and `/v1/artist` returns Doja Cat's songs in the
recording's exact order with the recording's exact album subtitles
(`Woman / Planet Her`, `Streets / Hot Pink`, `Paint The Town Red / Scarlet`).
`Kiss Me More (Official Video)` comes back at 316 seconds — 5:16, matching the
video.

---

## 2. The InnerTube layer

`server/src/innertube/client.ts`

### Two things that are load-bearing

Both were found by measurement, and both fail *silently* when wrong:

**1. `clientVersion` must be current.** A stale version does not error — the API
returns 200 with plausible data, but continuation tokens stop working entirely
and you get page 1 forever. A hardcoded version from 2024 produced exactly this.
The client now scrapes `INNERTUBE_CLIENT_VERSION` from the YTM homepage and
caches it in KV for 6 hours.

**2. `visitorData` must be present and stable.** Without it, continuation tokens
are ignored and the server replays the first page. Also scraped from the homepage
and cached alongside the client version.

A third, smaller one: **continuation tokens go in the POST body**
(`{ continuation: "<token>" }`). The `?continuation=` query parameter is
deprecated and silently ignored — the server just returns a fresh first page.

### Region is decided by IP, not by parameters

`context.client.gl` does **not** override YouTube's IP geolocation for the home
feed. Neither does hand-crafting a `visitorData` protobuf with a different
country code — both were tried; the feed stayed geolocated to the requesting IP.

This is why home is curated rather than proxied directly. See below.

---

## 3. Why the home feed is curated

`server/src/config.ts`

The raw `FEmusic_home` feed is unusable as a product surface: it is
IP-geolocated, and it returns a *different set of shelves per request*. The
reference app shows a fixed shelf order with recognisable titles, which the raw
feed cannot produce.

So `HOME_MANIFEST` composes home from YouTube Music **mood and genre category
pages** and relabels the shelves:

| Display shelf | Source category | Source shelves |
|---|---|---|
| Trending community playlists | Pop | Community playlists, Featured playlists |
| Pump it up | Energize | Pop bangers, Hip-hop energy, Beast mode, Power boost |
| Throwbacks | Decades | 1980s, 1990s, 2000s, 1970s |
| Feeling happy | Feel good | Feeling happy, Feel-good pop, Fun throwbacks |
| … | | |

Every `sourceShelves` title was verified present in a live category response, and
is asserted by a fixture test. A category page is fetched once and reused across
every display shelf that draws from it.

This mapping is not arbitrary — the reference recording's cards were traced back
to their source categories. `Bubble Pop` and `Feelin' Good in the 80s` live in
*Feel good*; `The Hits: '80s` in *Decades*; `Beast Mode Hip-Hop` in *Energize*.

Benefits beyond fidelity: region-stable, deterministic ordering, and cacheable.

---

## 4. The parser layer

`server/src/innertube/parsers.ts` — the only file that knows YouTube's payload
shapes. Everything else is shape-agnostic.

**Contract: every parser returns a value, never throws.** A shelf that cannot be
parsed becomes an empty shelf and is filtered out, so one YouTube-side change
degrades a single row rather than a whole screen.

Renderers handled:

| Renderer | Where it appears |
|---|---|
| `musicTwoRowItemRenderer` | Carousel cards (playlists, albums, artists, video tiles) |
| `musicResponsiveListItemRenderer` | List rows (search results, artist top songs, playlist tracks) |
| `musicCarouselShelfRenderer` | Horizontal shelves |
| `musicShelfRenderer` | Vertical shelves |
| `musicCardShelfRenderer` | Search "Top result" card |
| `itemSectionRenderer` | Search wraps each result in its own section — flattened, then regrouped by kind |

### Column classification, not indexing

List-row layouts vary by page. An artist top-songs row is
`[title, artist, "1.3B plays", album]`; a search row is
`[title, "Song • Doja Cat • 3:28"]`. Rather than indexing blindly, columns are
classified — durations by pattern, play counts by pattern, type tokens by
vocabulary, and what remains are names. The first name is the artist, the last is
the album.

This is why `artistName` and `albumName` are returned *separately* alongside
`subtitle`: artist pages display the album under a track, everywhere else the
artist reads better. The client picks via `MediaItem.displaySubtitle(preferring:)`
rather than the server guessing.

### Podcasts are dropped

YouTube mixes podcast episodes into music search results. Rows whose type token
is `Episode`, `Podcast` or `Show` return `nil`. Before this filter they were
parsed as songs and shown under "Songs" — the fixture contains six such rows, and
a regression test asserts none leak through.

---

## 5. The player

`TuneTube/Player/PlayerEngine.swift`

**One `YouTubePlayer` for the app's lifetime.** Track changes call
`load(source:)` on the existing instance. Recreating it per track tears down and
reloads the whole iframe, which flashes and re-buffers.

**Polling, not publishers.** Playback position is polled at 0.5s rather than
subscribed. The iframe bridge's state publishers are chatty and version-sensitive;
a half-second poll is more than enough to drive a scrubber and is far less likely
to break on a library update.

**Seek on release only.** Seeking on every slider frame thrashes the iframe.

**The volume slider is `MPVolumeView`, not the player.** iOS makes the HTML5
`volume` property read-only — setting it is a no-op and reads always return 1. A
slider bound to the embed would look functional and do nothing, so it drives
system volume instead.

**Queue auto-advance** watches for `currentTime >= duration - 1`. The embed
reports a duration about a second longer than the audio in practice, which is the
same discrepancy visible in the reference app.

---

## 6. Background audio investigation

**Status: unresolved.** This is the one thing the app does not do that the
reference app does.

### What was measured

iPhone 17 Pro simulator, playing, then Home pressed, then foregrounded and the
elapsed position compared against wall-clock time:

| Configuration | Playback after backgrounding |
|---|---|
| `AVAudioSession(.playback)` + `UIBackgroundModes: audio` | ~10s, then stopped |
| \+ silent looping `AVAudioPlayer` keep-alive | ~14s, then stopped |

### What each result rules out

**The audio session is configured correctly.** Audio continued at all, which it
would not with a misconfigured session.

**Keeping the app alive is not sufficient.** The silent-keeper hypothesis was
that iOS suspends the app because audio from the WebKit content process isn't
credited to us. Adding a genuinely-running silent audio route bought only ~4
seconds. The WAV generator was verified valid with `afinfo`, so the keeper did
run. Conclusion: WebKit suspends the `<video>` element itself, independently of
the app's lifecycle.

**`.mixWithOthers` is actively harmful.** It makes the app a *secondary* audio
session, which forfeits background-audio privileges entirely. Do not set it.

### Picture in Picture does not close the gap

`allowsPictureInPictureMediaPlayback` is enabled (correct, and a precondition for
any PiP path), but:

- **PiP does not auto-engage on backgrounding.** Measured: no PiP window appeared.
- **PiP cannot be triggered programmatically.** The host page's origin is
  `https://com.tunetube.app` (`YouTubePlayer.Parameters.defaultOriginURL`) while
  the player is an iframe on `youtube.com`. Cross-origin — no JS reach into the
  `<video>` element.

Setting the page's `baseURL` to `https://www.youtube.com` would make the iframe
same-origin and allow `webkitSetPresentationMode('picture-in-picture')`. This is
**deliberately not done**: it defeats the same-origin policy and would break
whenever YouTube changes anything.

That leaves PiP reachable only through YouTube's own fullscreen control — poor
UX, and not reproducible in the simulator.

### Important caveat

**Every measurement above is from the simulator**, which is not authoritative for
WebKit media suspension or background process assertions. Shipping apps in this
category suggest the embed *may* survive backgrounding on real hardware.

**Re-test on a physical device before concluding the embed cannot do this.** Play
a track, lock the screen, and check whether audio continues past ~15 seconds.
That single data point decides the whole question.

### If the device test fails

The remaining option is native `AVPlayer` playback against a resolved audio
stream URL. That delivers true background audio, a real volume slider and gapless
queueing — and moves the app squarely into guideline 5.2.3 territory, where
rejection appeals require rights documents. It is a business decision, not a
technical one.

A remote-config boolean switching playback engines is a legitimate kill-switch
and rollout control. Using one to show App Store reviewers different behaviour
than users get is guideline 2.3.1 (hidden features), and the downside is app
removal or account termination rather than a rejection you can iterate on.

---

## 7. Library and entitlements

**One gate, one place.** `LibraryStore.canCreatePlaylist(isPro:freeLimit:)` is
the only thing that decides whether a playlist can be created. Both entry points
— the Library tab's `+` and the "New Playlist" row in the Add-to-Playlist sheet —
call it. Duplicating the rule is how a paywall ends up leaking.

**`Favourites` is structural, not a convention.** It carries `isDefault = true`,
is seeded idempotently on every launch, and `LibraryStore.delete` refuses to
remove it. Deleting it would leave a free user with no library at all.

**Entitlement is cached.** `StoreManager` mirrors `isPro` into `UserDefaults`, so
a launch with no network is never a silent downgrade. StoreKit remains the source
of truth once it answers.

**`Transaction.updates` is observed from launch**, not from paywall presentation.
That is how renewals, Ask-to-Buy approvals and refunds that happen offscreen are
picked up.

### A gotcha worth knowing

StoreKit configuration files **only apply when the app is launched from Xcode's
scheme**. A `simctl launch` gets zero products. This is easy to miss because the
paywall still renders prices — those are the hardcoded fallbacks. `StoreManager`
now reports a visible error when a product id is missing, precisely so this looks
like a failure instead of a success.

---

## 8. Client design notes

**Offline-first reads.** `APIClient` writes every successful response through
`DiskCache` and falls back to it on failure, so a cold launch with no network
shows the last known feed rather than a spinner.

**Cards crop to square deliberately.** YouTube serves 16:9 thumbnails; the
`.fill` + `.clipped()` pairing in `MediaCard` produces the cropped-video look
with visible bleed, which is what the reference design does.

**The mini player uses `tabViewBottomAccessory` on iOS 26.** A `safeAreaInset` on
the `TabView` renders *over* the floating tab bar on iOS 26; moving the inset
inside a tab's `NavigationStack` stops it re-evaluating when the player goes from
"nothing loaded" to "playing", and the bar silently never appears. The accessory
slot is purpose-built for this; the inset remains as the pre-26 fallback.

---

## 9. Artwork caching

`AsyncImage` was replaced by `CachedImage` / `ImageLoader`
(`TuneTube/Core/ImageCache.swift`) because it has three properties that read as
flicker in a shelf-based UI: no cache at all (every instance refetches), every
instance starts in its `.empty` phase, and N views showing the same thumbnail
issue N requests.

The replacement fixes each:

- **Synchronous memory peek.** `CachedImage.init` seeds its state from the cache,
  so a warm image is on screen for the very first frame — no placeholder, no
  fade. This is the part that actually removes the flicker.
- **Disk cache**, so artwork survives relaunch and works offline, matching the
  offline-first behaviour of `DiskCache` for API responses.
- **Request coalescing** via an in-flight task map, so simultaneous requests for
  one URL share a single fetch.

`NSCache` is thread-safe but not `Sendable`, so it is boxed in a small
`@unchecked Sendable` wrapper rather than marked `nonisolated` on the actor —
the latter is an error under the Swift 6 language mode.

Everything routes through one `Artwork` view, so the fix covers cards, list
rows, the mini player and detail headers at once. `PlayerEngine` uses the same
loader for lock-screen artwork, which usually means no extra request.

## 10. Known rough edges

- Playlist cards whose YTM subtitle is pure boilerplate (`Playlist • YouTube
  Music`) show no subtitle at all. The reference app shows a sample artist there,
  which would require fetching each playlist's contents.
- No playlist import yet, despite the reference app's "Import Playlists" button.
