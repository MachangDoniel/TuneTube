# TuneTube Architecture and System Design

A comprehensive technical reference for the architecture, playback pipelines, offline storage, caching layers, and design decisions in **TuneTube**.

---

## 1. System Architecture Overview

TuneTube uses a decoupled, privacy-respecting client-server architecture:
- **iOS Client (`TuneTube/`)**: Native SwiftUI application (iOS 17+) running a dual-engine player (`AVFoundation` for pure audio, `YouTubePlayerKit` for official video) with SwiftData and local file persistence.
- **Edge Backend (`server/`)**: Cloudflare Worker proxying YouTube Music's InnerTube API with global Cloudflare KV caching.

```mermaid
flowchart TB
    subgraph iOSClient ["iOS Client (TuneTube)"]
        UI["SwiftUI UI Layer\n(Home, Search, Library, Player)"]
        Nav["Navigator\n(Tab & Route Stack)"]
        Store["LibraryStore (SwiftData)\n+ StoreManager (Free Tier)"]
        
        subgraph EngineCore ["Player & Audio Core"]
            Engine["PlayerEngine\n(@Observable Orchestrator)"]
            ModeCheck{"Display Mode / State"}
            AVP["Native AVPlayer\n(High-Bitrate AAC / M4A)"]
            IFrame["YouTube IFrame Player\n(WKWebView Video)"]
        end
        
        subgraph StorageLayer ["Persistence & File Storage"]
            Cache["DiskCache\n(In-Memory NSCache + TTL File Storage)"]
            DM["DownloadManager\n(Documents/OfflineMusic)"]
            FilesApp["Apple Files App\n('On My iPhone' / TuneTube)"]
        end
    end

    subgraph EdgeBackend ["Cloudflare Workers Edge Network"]
        Worker["Hono API Gateway\n(/v1/home, /v1/search, /v1/artist, etc.)"]
        KV[("Cloudflare KV Cache\n(TTL: 10m - 24h)")]
    end

    subgraph Upstream ["YouTube Infrastructure"]
        InnerTube["music.youtube.com/youtubei/v1\n(Catalog & Metadata)"]
        CDN["googlevideo.com / CDN\n(Encrypted Media Streams)"]
        YTWeb["youtube.com/embed\n(Official IFrame Video)"]
    end

    UI --> Nav
    UI --> Engine
    UI --> Store
    
    Engine --> ModeCheck
    ModeCheck -- "Song Mode / Offline" --> AVP
    ModeCheck -- "Video Mode" --> IFrame
    
    AVP -. "Plays Local" .-> DM
    DM <-->|Two-Way Disk Sync| FilesApp
    
    UI --> Cache
    Cache --> Worker
    Worker <--> KV
    Worker --> InnerTube
    
    AVP -. "Stream Fetch" .-> CDN
    IFrame -. "Embed Stream" .-> YTWeb
```

---

## 2. Playback Architecture: The Dual-Engine Pipeline

TuneTube solves the historic YouTube background-audio restriction through an intelligent **Dual-Engine Architecture**:

1. **Song Mode (Default)**: Uses native Apple `AVPlayer` streaming high-bitrate AAC (`itag 140` @ 128kbps or `itag 139` @ 64kbps). Buffers in <200ms, consumes minimal battery, provides continuous lock-screen audio, and supports native system scrubbers and volume controls.
2. **Video Mode**: Renders the official YouTube web player inside a `WKWebView` with official branding, chapters, and video controls.
3. **Offline Mode**: Native `AVPlayer` streaming directly from local `file://` URLs with zero network activity.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Player as PlayerEngine
    participant DM as DownloadManager
    participant Stream as StreamResolver
    participant San as DASH Box Sanitizer
    participant AVP as AVPlayer
    participant Screen as Lock Screen (NowPlaying)

    User->>Player: Tap Song to Play
    Player->>DM: Check localAudioURL(for: videoId)
    
    alt Track Is Downloaded (Offline)
        DM-->>Player: Return local file:// URL
        Player->>AVP: Initialize AVPlayerItem(fileURL)
        Player->>Screen: Load Local Artwork (.jpg) & Track Metadata
        AVP-->>User: Instant Playback (<1ms, 0 Network)
    else Track Is Online (Song Mode)
        Player->>Stream: getCachedAudioFileURL(for: videoId)
        alt Audio Already Cached on Disk
            Stream-->>Player: Return cached .m4a URL
            Player->>AVP: Play local cached .m4a
        else Stream Resolution Needed
            Stream->>Stream: resolveStreamURL() via YouTubeKit
            Stream-->>Player: Return remote AAC CDN URL
            Player->>AVP: Stream CDN URL immediately (<200ms)
            Player->>Stream: Detached Task: downloadAudioFile()
            Stream->>San: sanitizeFragmentedMP4()
            Stream-->>Player: Swap AVPlayerItem to local disk seamlessly
        end
        Player->>Screen: Load Artwork via ImageLoader & Update MPNowPlayingInfo
    end
```

---

## 3. DASH Audio Fragmentation & Header Sanitization

YouTube DASH audio streams (itags 140 and 139) are packaged as **Fragmented MP4 (fMP4)**. In these streams:
- The initial Movie Box (`moov`) defines a duration $D$.
- The subsequent Movie Fragment Boxes (`moof` + `mdat`) contain audio chunks totaling duration $D$.

Without correction, Apple's `AVFoundation` engine parses both the `moov` header duration and sums all fragment durations, reporting **$2 \times D$** (e.g. `9:22` instead of `4:41`). This causes progress bars to halt at 50% and track auto-advance to break.

```mermaid
flowchart LR
    subgraph RawStream ["Raw YouTube DASH fMP4 Stream"]
        moov1["moov Box\n(Reports Duration: D)"]
        moof1["moof + mdat Fragments\n(Reports Duration: D)"]
    end

    subgraph AVFDefault ["AVFoundation Default Parser"]
        moov1 --> Sum["Sum Durations: D + D = 2D"]
        moof1 --> Sum
        Sum --> Bug["Bug: 2x Duration Displayed\nScrubber Halts at 50%"]
    end

    subgraph PatchedStream ["TuneTube Sanitized MP4"]
        direction TB
        Patch["StreamResolver.sanitizeFragmentedMP4()"]
        moov2["moov Box\n(mvhd / tkhd / mdhd Header Bytes)"]
        Zero["Zero Out Duration Bytes (0x00000000)"]
        moof2["moof Fragments\n(Real Duration: D)"]
        
        Patch --> moov2 --> Zero
        Zero --> Result["Result: AVFoundation computes\nExact Duration D (1x Single Length)"]
        moof2 --> Result
    end
```

### Binary Box Header Patch Offsets
`StreamResolver.sanitizeFragmentedMP4(at:)` directly inspects the binary MP4 box headers and zeros out the initial movie duration fields:

| MP4 Box | Version 0 Offset | Version 1 Offset | Zero Length |
| :--- | :--- | :--- | :--- |
| **`mvhd`** (Movie Header) | `offset + 16` | `offset + 24` | 4 bytes (v0) / 8 bytes (v1) |
| **`tkhd`** (Track Header) | `offset + 20` | `offset + 28` | 4 bytes (v0) / 8 bytes (v1) |
| **`mdhd`** (Media Header) | `offset + 16` | `offset + 24` | 4 bytes (v0) / 8 bytes (v1) |

---

## 4. Offline Storage & Files App Two-Way Synchronization

Downloaded media lives in `Documents/OfflineMusic/`, making it visible to the user and resilient to operating system cache purges.

```mermaid
flowchart TD
    subgraph Filesystem ["Documents/OfflineMusic/ (isExcludedFromBackup = true)"]
        AudioDir["audio/\n<videoId>.m4a / <fileName>.mp3"]
        ArtDir["artwork/\n<videoId>.jpg"]
        MetaFile["metadata.json\n[DownloadedTrack Registry]"]
    end

    subgraph SyncEngine ["DownloadManager (Two-Way Sync Engine)"]
        direction TB
        Trigger["Triggers: App Foreground\nor DownloadsView.onAppear"]
        WorkerTask["Task.detached(priority: .utility)"]
        
        Trigger --> WorkerTask
        
        subgraph Detection ["Non-Blocking File Reconciler"]
            Scan1["1. File Deletion Check:\nFilter tracks where file exists"]
            Scan2["2. New File Discovery:\nDetect .m4a, .mp3, .flac, .wav, .aac"]
            TagExtract["3. AVURLAsset Extraction:\nRead Title, Artist, Album, Artwork"]
        end
        
        WorkerTask --> Scan1
        WorkerTask --> Scan2
        Scan2 --> TagExtract
    end

    subgraph AppleFilesApp ["Apple iOS Files App ('On My iPhone')"]
        UIFiles["TuneTube Folder\n(UIFileSharingEnabled = true)"]
        UserAction["User drops MP3/FLAC\nor deletes unwanted track"]
    end

    subgraph AppUI ["TuneTube Library UI"]
        DLView["DownloadsView\n(Play All, Shuffle, Filter, File Sizes)"]
    end

    Filesystem <--> UIFiles
    UserAction --> UIFiles
    Filesystem --> SyncEngine
    Detection --> MetaFile
    SyncEngine -->|@MainActor Update| DLView
```

### Storage Characteristics

| Attribute | Temporary Cache (`Caches/AudioTracks`) | Permanent Downloads (`Documents/OfflineMusic`) |
| :--- | :--- | :--- |
| **Directory** | `Library/Caches/AudioTracks/` | `Documents/OfflineMusic/` |
| **Purgeable by iOS** | Yes (purged during storage pressure) | **No** (`isExcludedFromBackup = true`) |
| **Cap Limit** | FIFO queue capped at 50 tracks | **Unlimited** (bounded only by device flash) |
| **Files App Access** | Hidden | **Visible & Editable** under *On My iPhone* |
| **Artwork Format** | Memory / Transient Cache | Persistent JPEG (`artwork/<id>.jpg`) |

---

## 5. Network Architecture: Cache-First Strategy & Fallback Matrix

To prevent rate-limiting (HTTP 429) from edge gateways and provide instant screen transitions, `APIClient` and `DiskCache` operate a tiered cache:

```mermaid
flowchart TD
    Req["APIClient Request\n(e.g. /v1/home, /v1/search)"]
    Force{"forceRefresh == true?"}
    
    Req --> Force
    Force -- "Yes (Pull-to-refresh)" --> NetFetch["Send HTTP Request"]
    
    Force -- "No" --> RAM{"In-Memory NSCache Hit?"}
    RAM -- "Hit" --> ReturnRAM["Return Memory Object (<1ms)"]
    
    RAM -- "Miss" --> DiskCheck{"Disk Cache Hit & within TTL?"}
    DiskCheck -- "Valid TTL" --> ReturnDisk["Return Disk Cache (~5ms)"]
    
    DiskCheck -- "Expired or Miss" --> NetFetch
    
    subgraph NetworkExec ["Network Execution & Fallback"]
        NetFetch --> Target{"Target Base URL"}
        Target -- "Debug (Local Mac)" --> LocalTry["Try http://Doniels-MacBook-Air.local:8799"]
        LocalTry -- "Timeout > 5.0s or Connection Refused" --> CloudflareFallback["Switch Base URL to\nhttps://tunetube-api.tunetube-app.workers.dev"]
        Target -- "Release" --> Cloudflare["Direct to Cloudflare Edge Worker"]
        
        LocalTry -- "Success" --> SaveCache["Update NSCache & DiskCache"]
        CloudflareFallback --> SaveCache
        Cloudflare --> SaveCache
        
        CloudflareFallback -- "429 / 503 / Offline" --> StaleFallback["Serve Stale Disk Cache (Soft Degradation)"]
        Cloudflare -- "429 / 503 / Offline" --> StaleFallback
    end
```

### Cache TTL Windows

| Data Type | Cache TTL | Stale Fallback on Error | Force Refresh Option |
| :--- | :--- | :--- | :--- |
| **Home Shelves** (`/v1/home`) | 1 hour | Yes | Yes (Pull-to-refresh) |
| **Search Queries** (`/v1/search`) | 15 minutes | Yes (`search-last-loaded`) | Yes |
| **Artist Details** (`/v1/artist`) | 24 hours | Yes | Yes |
| **Playlists / Categories** | 6 hours | Yes | Yes |
| **Remote Config** (`/v1/config`) | 1 hour | Yes (Hardcoded defaults) | Yes |

---

## 6. Entity Relationship Model

```mermaid
erDiagram
    MediaItem ||--o{ DownloadedTrack : "mirrors"
    LocalPlaylist ||--o{ LocalTrack : "contains"
    LocalTrack }|--|| MediaItem : "serializes as"
    DownloadedTrack ||--|| LocalAudioFile : "points to"
    DownloadedTrack ||--o| LocalArtworkFile : "points to"

    MediaItem {
        string id PK "YouTube Video ID"
        string title
        string subtitle
        string artistName
        string albumName
        url thumbnailUrl
        int durationSeconds
        enum kind "song, video, playlist, artist"
    }

    DownloadedTrack {
        string id PK "Video ID or imported_hash"
        string title
        string artistName
        string albumName
        int durationSeconds
        date downloadedAt
        int64 fileSizeBytes
        string audioFileName "e.g. videoId.m4a"
        string artworkFileName "e.g. videoId.jpg"
    }

    LocalPlaylist {
        uuid id PK
        string name
        date createdAt
        bool isDefault "Permanent Favourites"
        string iconName
        string colorHex
    }

    LocalTrack {
        string videoId PK
        string title
        string artistName
        string albumName
        string thumbnailURLString
        int durationSeconds
        date addedAt
    }
```

---

## 7. Sleep Timer State Machine

The Sleep Timer in `PlayerEngine` runs a precise 1-second countdown task with automatic audio fade and shutdown:

```mermaid
stateDiagram-v2
    [*] --> Idle: App Launch (Timer = Off)
    
    Idle --> ActiveCountdown: User selects 15m / 30m / 45m / 60m
    Idle --> EndOfTrackWatch: User selects 'End of Track'
    
    state ActiveCountdown {
        [*] --> Ticking
        Ticking --> Ticking: 1-second timer tick (remainingSeconds--)
        Ticking --> FadingOut: remainingSeconds <= 3
        FadingOut --> Expired: remainingSeconds == 0
    }
    
    state EndOfTrackWatch {
        [*] --> Monitoring
        Monitoring --> Expired: trackDidFinish() fired
    }
    
    Expired --> Idle: Pause AVPlayer / YouTube, Reset Option to .off
    ActiveCountdown --> Idle: User cancels timer
    EndOfTrackWatch --> Idle: User cancels timer
```

---

## 8. Verification & Test Matrix

All architectural layers are covered by automated test suites and compiler verifications:

1. **InnerTube Payload Parsers**: Tested against checked-in YouTube Music JSON payloads (`server/test/`) using Vitest:
   ```bash
   cd server && npx vitest run
   ```
2. **Swift Client Build Integrity**: Verified using `xcodebuild` targeting iOS 17+ Simulator and physical devices:
   ```bash
   xcodebuild -project TuneTube.xcodeproj -scheme TuneTube -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
   ```
3. **Continuous Code Quality**: Verified via [CodeRabbit](https://coderabbit.ai) integration on all pull requests adhering to [`.coderabbit.yaml`](../.coderabbit.yaml).
