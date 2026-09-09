export type MediaKind = 'song' | 'video' | 'album' | 'playlist' | 'artist';

export interface MediaItem {
  id: string;               // videoId (song/video) | browseId (album/artist) | playlistId (playlist)
  kind: MediaKind;
  title: string;
  subtitle?: string;
  thumbnailUrl?: string;
  durationSeconds?: number;
  playlistId?: string;      // for playlist/album cards: the id to enqueue
  artistName?: string;      // list rows only; lets the client choose the subtitle
  albumName?: string;       // list rows only (artist pages show album, not artist)
}

export interface Shelf {
  id: string;
  title: string;
  items: MediaItem[];
}

export interface Env {
  CACHE: KVNamespace;
  YTM_REGION: string;
  YTM_LANG: string;
}
