/**
 * The fragile layer. Everything that knows about YouTube's payload shape lives
 * here so a breakage is a `wrangler deploy`, not a two-week App Store review.
 *
 * Contract: every parser returns a value, never throws. A shelf we cannot parse
 * becomes an empty shelf and gets filtered out, so one YouTube-side change can
 * never take down the whole feed.
 */
import type { MediaItem, MediaKind, Shelf } from '../types';

/* ---------- small helpers ---------- */

const runsText = (node: any): string =>
  (node?.runs ?? []).map((r: any) => r?.text ?? '').join('').trim();

/** Drop YTM's boilerplate subtitle chrome ("Playlist • YouTube Music"). */
function cleanSubtitle(node: any): string | undefined {
  const parts: string[] = (node?.runs ?? [])
    .map((r: any) => (r?.text ?? '').trim())
    .filter((t: string) => t && t !== '•' && t !== '•');

  const noise = new Set(['Playlist', 'Album', 'Single', 'EP', 'Artist', 'Song', 'Video']);
  const kept = parts.filter(
    (p) => !noise.has(p) && p !== 'YouTube Music' && !/^[\d.]+[KMB]? views?$/i.test(p),
  );
  // If EVERY run was boilerplate ("Playlist • YouTube Music"), there is no real
  // subtitle to show. Returning the raw parts here would put YouTube's chrome on
  // the card, which is exactly what we are stripping.
  const out = kept.join(' • ');
  return out || undefined;
}

/** YTM serves tiny thumbs; ask for a larger square. */
export function upscaleThumb(url: string | undefined, size = 544): string | undefined {
  if (!url) return undefined;
  if (/=w\d+-h\d+/.test(url)) return url.replace(/=w\d+-h\d+/, `=w${size}-h${size}`);
  if (/=s\d+/.test(url)) return url.replace(/=s\d+/, `=s${size}`);
  return url;
}

function pickThumb(node: any): string | undefined {
  const list =
    node?.thumbnailRenderer?.musicThumbnailRenderer?.thumbnail?.thumbnails ??
    node?.thumbnail?.musicThumbnailRenderer?.thumbnail?.thumbnails ??
    node?.thumbnail?.thumbnails ??
    node?.thumbnails;
  if (!Array.isArray(list) || !list.length) return undefined;
  return upscaleThumb(list[list.length - 1]?.url);
}

function kindFromPageType(pageType?: string): MediaKind | undefined {
  switch (pageType) {
    case 'MUSIC_PAGE_TYPE_PLAYLIST':      return 'playlist';
    case 'MUSIC_PAGE_TYPE_ALBUM':         return 'album';
    case 'MUSIC_PAGE_TYPE_ARTIST':
    case 'MUSIC_PAGE_TYPE_USER_CHANNEL':  return 'artist';
    default:                              return undefined;
  }
}

/** "3:07" / "1:02:11" -> seconds */
export function parseDuration(text: string | undefined): number | undefined {
  if (!text) return undefined;
  const parts = text.split(':').map((p) => parseInt(p, 10));
  if (parts.some(Number.isNaN)) return undefined;
  return parts.reduce((acc, p) => acc * 60 + p, 0);
}

/* ---------- item parsers ---------- */

/** Carousel card: playlists, albums, artists, and video "Quick picks" tiles. */
export function parseTwoRowItem(node: any): MediaItem | null {
  const r = node?.musicTwoRowItemRenderer;
  if (!r) return null;

  const title = runsText(r.title);
  if (!title) return null;

  const nav = r.navigationEndpoint ?? {};
  const browse = nav.browseEndpoint;
  const watch = nav.watchEndpoint;

  // The play button carries the playlistId we need to actually enqueue a card.
  const playEndpoint =
    r.thumbnailOverlay?.musicItemThumbnailOverlayRenderer?.content
      ?.musicPlayButtonRenderer?.playNavigationEndpoint ?? {};
  const playlistId =
    playEndpoint.watchPlaylistEndpoint?.playlistId ??
    playEndpoint.watchEndpoint?.playlistId ??
    browse?.browseId?.replace(/^VL/, '');

  let kind: MediaKind | undefined;
  let id: string | undefined;

  if (browse) {
    kind = kindFromPageType(
      browse.browseEndpointContextSupportedConfigs?.browseEndpointContextMusicConfig?.pageType,
    );
    id = browse.browseId;
    // Playlist browseIds are prefixed VL; strip it for the canonical id.
    if (kind === 'playlist' && id) id = id.replace(/^VL/, '');
  } else if (watch) {
    kind = 'video';
    id = watch.videoId;
  }

  if (!id) return null;

  return {
    id,
    kind: kind ?? 'playlist',
    title,
    subtitle: cleanSubtitle(r.subtitle),
    thumbnailUrl: pickThumb(r),
    ...(playlistId && playlistId !== id ? { playlistId } : {}),
    ...(kind === 'playlist' ? { playlistId: playlistId ?? id } : {}),
  };
}

/** List row: songs in search results, artist "Popular songs", playlist tracks. */
/** Search rows lead their subtitle with the type: "Song • Doja Cat • 3:28". */
function kindFromTypeRun(node: any): MediaKind | undefined {
  const first = (node?.runs?.[0]?.text ?? '').trim();
  switch (first) {
    case 'Song':     return 'song';
    case 'Video':    return 'video';
    case 'Album':
    case 'Single':
    case 'EP':       return 'album';
    case 'Artist':   return 'artist';
    case 'Playlist': return 'playlist';
    default:         return undefined;
  }
}

/** Search returns podcast episodes and shows alongside music. This is a music
 *  app, so we drop them rather than mislabelling them as songs. */
const NON_MUSIC_TYPES = new Set(['Episode', 'Podcast', 'Show']);

function isNonMusic(node: any): boolean {
  const first = (node?.runs?.[0]?.text ?? '').trim();
  return NON_MUSIC_TYPES.has(first);
}

export function parseResponsiveListItem(node: any): MediaItem | null {
  const r = node?.musicResponsiveListItemRenderer;
  if (!r) return null;

  const cols = (r.flexColumns ?? []).map(
    (c: any) => c?.musicResponsiveListItemFlexColumnRenderer?.text,
  );
  const title = runsText(cols[0]);
  if (!title) return null;

  const videoId =
    r.playlistItemData?.videoId ??
    r.overlay?.musicItemThumbnailOverlayRenderer?.content?.musicPlayButtonRenderer
      ?.playNavigationEndpoint?.watchEndpoint?.videoId;

  const browse = r.navigationEndpoint?.browseEndpoint;

  // Column layouts vary by page (search rows lead with a type token, artist
  // pages carry a play count and an album). Classify rather than index blindly.
  const DURATION_RE = /^\d+:\d{2}(:\d{2})?$/;
  const COUNT_RE = /^[\d.,]+[KMB]?\s+(plays|views|songs|subscribers)$/i;

  const tail: string[] = cols.slice(1).map(runsText).filter(Boolean);
  const names = tail.filter(
    (t) => !DURATION_RE.test(t) && !COUNT_RE.test(t) && !kindFromTypeRun({ runs: [{ text: t }] }) && t !== '•',
  );
  const artistName = names[0];
  const albumName = names.length > 1 ? names[names.length - 1] : undefined;

  const durationText =
    runsText(r.fixedColumns?.[0]?.musicResponsiveListItemFixedColumnRenderer?.text) ||
    (tail.find((t: string) => DURATION_RE.test(t)) ?? '');

  if (isNonMusic(cols[1])) return null;

  const declaredKind = kindFromTypeRun(cols[1]);

  let id = videoId;
  let kind: MediaKind = declaredKind ?? 'song';
  // An artist/album row has a browseId and no videoId; prefer the browse target.
  if (declaredKind === 'artist' || declaredKind === 'album' || declaredKind === 'playlist') {
    id = browse?.browseId?.replace(/^VL/, '') ?? id;
  }
  if (!id && browse) {
    id = browse.browseId?.replace(/^VL/, '');
    kind = kindFromPageType(
      browse.browseEndpointContextSupportedConfigs?.browseEndpointContextMusicConfig?.pageType,
    ) ?? 'playlist';
  }
  if (!id) return null;

  return {
    id,
    kind,
    title,
    subtitle: cleanSubtitle(cols[1]) ?? artistName,
    thumbnailUrl: pickThumb(r),
    durationSeconds: parseDuration(durationText),
    ...(artistName ? { artistName } : {}),
    ...(albumName ? { albumName } : {}),
  };
}

export function parseAnyItem(node: any): MediaItem | null {
  return parseTwoRowItem(node) ?? parseResponsiveListItem(node);
}

/* ---------- shelf / page parsers ---------- */

export function parseCarouselShelf(node: any): Shelf | null {
  const r = node?.musicCarouselShelfRenderer;
  if (!r) return null;
  const title =
    runsText(r.header?.musicCarouselShelfBasicHeaderRenderer?.title) || 'More';
  const items = (r.contents ?? []).map(parseAnyItem).filter(Boolean) as MediaItem[];
  if (!items.length) return null;
  return { id: slug(title), title, items };
}

/** Some pages use a plain shelfRenderer/musicShelfRenderer instead of a carousel. */
export function parseMusicShelf(node: any): Shelf | null {
  const r = node?.musicShelfRenderer;
  if (!r) return null;
  const title = runsText(r.title) || 'Results';
  const items = (r.contents ?? []).map(parseAnyItem).filter(Boolean) as MediaItem[];
  if (!items.length) return null;
  return { id: slug(title), title, items };
}

/**
 * Search "Top result" card. Different renderer from everything else: the nav
 * endpoint hangs off the card itself rather than off a list item.
 */
export function parseCardShelf(node: any): Shelf | null {
  const r = node?.musicCardShelfRenderer;
  if (!r) return null;

  const title = runsText(r.title);
  if (!title) return null;

  const nav = r.title?.runs?.[0]?.navigationEndpoint ?? r.onTap ?? {};
  const browse = nav.browseEndpoint;
  const watch = nav.watchEndpoint;

  let id: string | undefined;
  let kind: MediaKind = 'song';
  if (browse) {
    id = browse.browseId?.replace(/^VL/, '');
    kind =
      kindFromPageType(
        browse.browseEndpointContextSupportedConfigs?.browseEndpointContextMusicConfig
          ?.pageType,
      ) ?? 'playlist';
  } else if (watch) {
    id = watch.videoId;
    kind = 'song';
  }
  if (!id) return null;

  const item: MediaItem = {
    id,
    kind,
    title,
    subtitle: cleanSubtitle(r.subtitle),
    thumbnailUrl: pickThumb(r),
  };
  return { id: 'top-result', title: 'Top result', items: [item] };
}

/**
 * Search wraps each result in its own itemSectionRenderer, so the section list
 * is one-item-per-section rather than grouped shelves. Flatten those out.
 */
export function unwrapItemSections(sections: any[]): any[] {
  const out: any[] = [];
  for (const s of sections ?? []) {
    const inner = s?.itemSectionRenderer?.contents;
    if (Array.isArray(inner)) out.push(...inner);
    else out.push(s);
  }
  return out;
}

export function parseAnyShelf(node: any): Shelf | null {
  return parseCarouselShelf(node) ?? parseMusicShelf(node) ?? parseCardShelf(node);
}

/** Walk the standard browse envelope down to the section list contents. */
export function sectionContents(json: any): any[] {
  const tabs = json?.contents?.singleColumnBrowseResultsRenderer?.tabs;
  const sl = tabs?.[0]?.tabRenderer?.content?.sectionListRenderer;
  return sl?.contents ?? [];
}

export function sectionListRenderer(json: any): any {
  return json?.contents?.singleColumnBrowseResultsRenderer?.tabs?.[0]?.tabRenderer
    ?.content?.sectionListRenderer;
}

/** Both the legacy and modern continuation-token shapes. */
export function continuationToken(sectionList: any, items?: any[]): string | undefined {
  const legacy = sectionList?.continuations?.[0]?.nextContinuationData?.continuation;
  if (legacy) return legacy;
  const source = items ?? sectionList?.contents ?? [];
  const modern = source.find((c: any) => c?.continuationItemRenderer);
  return modern?.continuationItemRenderer?.continuationEndpoint?.continuationCommand?.token;
}

export function continuationItems(json: any): { items: any[]; sectionList: any } {
  const cc = json?.continuationContents?.sectionListContinuation;
  if (cc) return { items: cc.contents ?? [], sectionList: cc };
  const appended =
    json?.onResponseReceivedActions?.[0]?.appendContinuationItemsAction?.continuationItems;
  if (appended) return { items: appended, sectionList: null };
  return { items: [], sectionList: null };
}

export function slug(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'shelf';
}
