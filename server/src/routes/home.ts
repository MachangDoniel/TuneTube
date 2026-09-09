import { InnerTube } from '../innertube/client';
import { CATEGORIES, HOME_MANIFEST } from '../config';
import { parseAnyShelf, sectionContents, slug } from '../innertube/parsers';
import type { MediaItem, Shelf } from '../types';

const SHELF_ITEM_LIMIT = 12;

/**
 * Build home from the curated manifest: fetch each distinct category page once,
 * then compose our display shelves out of the source shelves it contains.
 */
export async function buildHome(yt: InnerTube): Promise<Shelf[]> {
  const neededCategories = [...new Set(HOME_MANIFEST.map((s) => s.category))];

  const pages = await Promise.all(
    neededCategories.map(async (key) => {
      try {
        const json = await yt.browse(
          'FEmusic_moods_and_genres_category',
          CATEGORIES[key].params,
        );
        const shelves = sectionContents(json)
          .map(parseAnyShelf)
          .filter(Boolean) as Shelf[];
        return [key, shelves] as const;
      } catch {
        return [key, [] as Shelf[]] as const;
      }
    }),
  );

  const byCategory = new Map(pages);

  const out: Shelf[] = [];
  for (const spec of HOME_MANIFEST) {
    const available = byCategory.get(spec.category) ?? [];
    const items: MediaItem[] = [];
    const seen = new Set<string>();

    // Take from each named source shelf in priority order until we fill up.
    for (const wanted of spec.sourceShelves) {
      const match = available.find(
        (s) => s.title.toLowerCase() === wanted.toLowerCase(),
      );
      if (!match) continue;
      for (const item of match.items) {
        if (seen.has(item.id)) continue;
        seen.add(item.id);
        items.push(item);
        if (items.length >= (spec.limit ?? SHELF_ITEM_LIMIT)) break;
      }
      if (items.length >= (spec.limit ?? SHELF_ITEM_LIMIT)) break;
    }

    // A shelf whose sources all vanished is dropped rather than shown empty.
    if (items.length) out.push({ id: slug(spec.title), title: spec.title, items });
  }

  return out;
}
