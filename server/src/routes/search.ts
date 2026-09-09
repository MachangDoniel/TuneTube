import { InnerTube } from '../innertube/client';
import { SEARCH_FILTERS } from '../config';
import {
  parseAnyItem, parseAnyShelf, parseCardShelf, sectionContents, unwrapItemSections,
} from '../innertube/parsers';
import type { MediaItem, MediaKind, Shelf } from '../types';

/** Display order and labels for grouped results. */
const GROUPS: Array<{ kind: MediaKind; title: string }> = [
  { kind: 'song',     title: 'Songs' },
  { kind: 'video',    title: 'Videos' },
  { kind: 'artist',   title: 'Artists' },
  { kind: 'album',    title: 'Albums' },
  { kind: 'playlist', title: 'Playlists' },
];

export async function doSearch(
  yt: InnerTube,
  query: string,
  type?: string,
): Promise<Shelf[]> {
  const params = type ? SEARCH_FILTERS[type] : undefined;
  const json = await yt.search(query, params);

  const sections =
    json?.contents?.tabbedSearchResultsRenderer?.tabs?.[0]?.tabRenderer?.content
      ?.sectionListRenderer?.contents ?? sectionContents(json);

  const out: Shelf[] = [];

  // "Top result" card comes first, before the flat list.
  const topSection = (sections ?? []).find((s: any) => s?.musicCardShelfRenderer);
  const top = topSection ? parseCardShelf(topSection) : null;
  if (top) out.push(top);

  // Real shelves, if YouTube happens to group them for this query.
  const grouped = (sections ?? [])
    .filter((s: any) => !s?.musicCardShelfRenderer && !s?.itemSectionRenderer)
    .map(parseAnyShelf)
    .filter(Boolean) as Shelf[];

  // Otherwise results arrive one-per-itemSection; group them ourselves by kind.
  const flat = unwrapItemSections(
    (sections ?? []).filter((s: any) => s?.itemSectionRenderer),
  )
    .map(parseAnyItem)
    .filter(Boolean) as MediaItem[];

  if (grouped.length) {
    out.push(...grouped);
  }

  if (flat.length) {
    const seen = new Set(out.flatMap((s) => s.items.map((i) => i.id)));
    for (const g of GROUPS) {
      const items = flat.filter((i) => i.kind === g.kind && !seen.has(i.id));
      if (!items.length) continue;
      items.forEach((i) => seen.add(i.id));
      out.push({ id: g.kind, title: g.title, items });
    }
  }

  return out;
}
