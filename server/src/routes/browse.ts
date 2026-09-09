import { InnerTube } from '../innertube/client';
import {
  parseAnyItem, parseAnyShelf, sectionContents, slug,
} from '../innertube/parsers';
import { CATEGORIES, type CategoryKey } from '../config';
import type { MediaItem, Shelf } from '../types';

const runs = (n: any) => (n?.runs ?? []).map((r: any) => r?.text ?? '').join('').trim();

/** Artist page: header + "Popular songs" + albums/singles shelves. */
export async function getArtist(yt: InnerTube, browseId: string) {
  const json = await yt.browse(browseId);

  const header =
    json?.header?.musicImmersiveHeaderRenderer ??
    json?.header?.musicVisualHeaderRenderer ??
    json?.header?.musicDetailHeaderRenderer;

  const thumbs =
    header?.thumbnail?.musicThumbnailRenderer?.thumbnail?.thumbnails ??
    header?.foregroundThumbnail?.musicThumbnailRenderer?.thumbnail?.thumbnails ??
    [];

  const shelves: Shelf[] = [];
  for (const section of sectionContents(json)) {
    const shelf = parseAnyShelf(section);
    if (shelf) shelves.push(shelf);
  }

  return {
    id: browseId,
    name: runs(header?.title) || 'Artist',
    description: runs(header?.description) || undefined,
    thumbnailUrl: thumbs.length ? thumbs[thumbs.length - 1].url : undefined,
    subscribers:
      runs(header?.subscriptionButton?.subscribeButtonRenderer?.subscriberCountText) ||
      undefined,
    shelves,
  };
}

/** Playlist or album detail with its full track list. */
export async function getPlaylist(yt: InnerTube, playlistId: string) {
  const browseId = playlistId.startsWith('VL') ? playlistId : `VL${playlistId}`;
  const json = await yt.browse(browseId);

  const header =
    json?.header?.musicDetailHeaderRenderer ??
    json?.header?.musicResponsiveHeaderRenderer ??
    json?.contents?.twoColumnBrowseResultsRenderer?.tabs?.[0]?.tabRenderer?.content
      ?.sectionListRenderer?.contents?.[0]?.musicResponsiveHeaderRenderer;

  const thumbs =
    header?.thumbnail?.musicThumbnailRenderer?.thumbnail?.thumbnails ??
    header?.thumbnail?.croppedSquareThumbnailRenderer?.thumbnail?.thumbnails ??
    [];

  // Tracks live either in the single-column section list or the two-column layout.
  let trackNodes: any[] = [];
  for (const section of sectionContents(json)) {
    const s = section?.musicPlaylistShelfRenderer ?? section?.musicShelfRenderer;
    if (s?.contents) trackNodes = trackNodes.concat(s.contents);
  }
  if (!trackNodes.length) {
    const twoCol =
      json?.contents?.twoColumnBrowseResultsRenderer?.secondaryContents
        ?.sectionListRenderer?.contents ?? [];
    for (const section of twoCol) {
      const s = section?.musicPlaylistShelfRenderer ?? section?.musicShelfRenderer;
      if (s?.contents) trackNodes = trackNodes.concat(s.contents);
    }
  }

  const tracks = trackNodes.map(parseAnyItem).filter(Boolean) as MediaItem[];

  return {
    id: playlistId.replace(/^VL/, ''),
    title: runs(header?.title) || 'Playlist',
    subtitle: runs(header?.subtitle) || undefined,
    description: runs(header?.description) || undefined,
    thumbnailUrl: thumbs.length ? thumbs[thumbs.length - 1].url : undefined,
    tracks,
  };
}

/** A mood/genre category page, returned as shelves. */
export async function getCategory(yt: InnerTube, key: CategoryKey) {
  const cat = CATEGORIES[key];
  const json = await yt.browse('FEmusic_moods_and_genres_category', cat.params);
  const shelves = sectionContents(json)
    .map(parseAnyShelf)
    .filter(Boolean) as Shelf[];
  return { id: slug(cat.name), title: cat.name, shelves };
}
