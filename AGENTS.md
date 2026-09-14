# AI Agent Guidelines

This repository uses [CodeRabbit](https://coderabbit.ai) for AI-driven code reviews and quality assurance (configured via [`.coderabbit.yaml`](.coderabbit.yaml)).

## 1. CodeRabbit Review Directive

Whenever any AI assistant (Antigravity, Cursor, Claude, Copilot, ChatGPT, or similar) works on this repository and finishes implementing a feature, fix, refactor, or prepares a branch/pull request:

1. **Ask the developer**:
   Always prompt the developer:
   > *"Would you like to go through a CodeRabbit review for these changes?"*

2. **Actions based on developer response**:
   - **If Yes**:
     - Push the changes to a branch and open/update a Pull Request so CodeRabbit can automatically review it.
     - Help the developer review and address any issues or suggestions flagged by CodeRabbit in accordance with [`.coderabbit.yaml`](.coderabbit.yaml).
   - **If No / Skip**:
     - Proceed directly with the developer's instructions without triggering or waiting for a CodeRabbit review.

---

## 2. Architectural Guardrails for AI Assistants

### A. Personal Use / 100% Free Tier
This app is for personal and shared-with-friends use.
- Do **not** re-introduce paywall popups, subscription locks, or playlist creation limits.
- `StoreManager.shared.isPro` is initialized to `true` by default.
- `LibraryStore.canCreatePlaylist` must always return `true`.

### B. Dual-Engine Playback & DASH Header Sanitization
- Song Mode streams native AAC (`itag 140` / `itag 139`) via `AVPlayer`. Video Mode uses `YouTubePlayerKit` in a `WKWebView`.
- **Critical Audio Invariant**: YouTube DASH audio files contain duplicate duration headers in the `moov` box. Whenever downloading or caching an audio file, you **must** invoke `StreamResolver.sanitizeFragmentedMP4(at: fileURL)`. Removing or bypassing this will cause the audio player scrubber to halt at 50% and report double duration.

### C. Concurrency & Performance
- All UI state and view models are `@MainActor` isolated.
- Disk I/O, directory scanning, and `AVURLAsset` metadata extraction **must** run on background utility tasks (`Task.detached(priority: .utility)`) to maintain 120Hz/60fps rendering without UI stutters.
- Memory caching uses `NSCache` wrapped in thread-safe `@unchecked Sendable` containers to comply with Swift 6 strict concurrency.

### D. Offline Storage & Files App Sync
- Permanent offline tracks live in `Documents/OfflineMusic/` (`audio/` and `artwork/`) with `isExcludedFromBackup = true`.
- Never store permanent user downloads in `CachesDirectory` (which iOS purges under storage pressure).
- Files app sharing is enabled via `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` in `TuneTube/Resources/Info.plist`.

### E. Build & Project Verification
- Before submitting any change or branch, always verify compilation:
  ```bash
  xcodebuild -project TuneTube.xcodeproj -scheme TuneTube \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -derivedDataPath ./build/DerivedData build
  ```
- If adding new Swift files to the codebase, ensure they are placed inside `TuneTube/` and registered in `project.yml` / `TuneTube.xcodeproj/project.pbxproj`.
