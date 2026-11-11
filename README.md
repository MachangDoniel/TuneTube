# TuneTube V2

TuneTube searches YouTube and browses public channels and playlists directly from iOS. YouTube videos play in the embedded YouTube player while it is visible. Files imported into the offline library play with AVPlayer, including in the background.

## Run V2

1. Enable YouTube Data API v3 in a Google Cloud project and create an API key restricted to that API and the app’s iOS bundle identifier.
2. Supply the key as the `YOUTUBE_DATA_API_KEY` user-defined build setting or as a launch environment variable in your local Xcode scheme. Keep your key out of version control.
3. If the Xcode project is absent, run `xcodegen generate` at the repository root. Open `TuneTube.xcodeproj` and run the TuneTube scheme.

The key uses the project's YouTube Data API quota. The app requires no Worker or custom API URL. Public YouTube search and charts replace the YouTube Music feed. The Data API has no equivalent for YouTube Music lyrics, albums, or song radio.

The V1 branch retains the original app and backend setup. V2 leaves previous offline files and playlists on disk. It routes legacy YouTube downloads to the embedded player when opened and keeps playback of imported files available offline.
