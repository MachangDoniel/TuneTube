# TuneTube Architecture

The complete, illustrated architecture documentation with interactive Mermaid diagrams, playback state machines, DASH fMP4 patching diagrams, and two-way file synchronization flows has been moved to:

👉 **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**

---

## Quick Visual Architecture Map

```mermaid
flowchart LR
    subgraph Client ["iOS App (SwiftUI)"]
        UI["Views & Navigation"]
        DualPlayer["Dual Player Engine\n(AVPlayer & YouTubeKit)"]
        Offline["DownloadManager & Files Sync\n(Documents/OfflineMusic)"]
    end

    subgraph Edge ["Cloudflare Workers Edge"]
        Worker["Hono Gateway Proxy\n+ Cloudflare KV Cache"]
    end

    subgraph Upstream ["YouTube Infrastructure"]
        InnerTube["InnerTube Private API\n(music.youtube.com)"]
        CDN["Google Video CDN\n(googlevideo.com)"]
    end

    UI --> DualPlayer
    DualPlayer <--> Offline
    UI --> Worker
    Worker <--> InnerTube
    DualPlayer --> CDN
```

For full details, please refer to [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
