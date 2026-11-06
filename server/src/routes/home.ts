import { InnerTube } from '../innertube/client';
import { CATEGORIES, HOME_MANIFEST, nearestChartCountry } from '../config';
import {
  chartCountries, continuationItems, continuationToken, parseAnyShelf,
  sectionContents, sectionListRenderer, slug,
} from '../innertube/parsers';
import type { MediaItem, Shelf } from '../types';

const SHELF_ITEM_LIMIT = 12;

/** Below this many shelves, Home looks broken, so the curated manifest tops it up. */
const MIN_SHELVES = 6;

/** FEmusic_home serves ~2 shelves per page. Bound the walk so one slow region
 *  can't hold the whole request open. */
const MAX_HOME_PAGES = 4;

/**
 * Build Home from YouTube Music's own region-scoped feeds.
 *
 * `FEmusic_charts` leads with Top artists / Video charts, then `FEmusic_home`
 * supplies the regional shelves (Indian Music, Ghazal & Sufi Essentials, New
 * releases, Trending community playlists...). Both honour the `gl` in the
 * client context, so switching region genuinely re-sources the feed.
 *
 * The curated HOME_MANIFEST is no longer the primary source — it is the
 * fallback for a region whose live feed comes back thin, so Home is never
 * near-empty.
 */
export async function buildHome(yt: InnerTube): Promise<Shelf[]> {
  const [charts, live] = await Promise.all([chartShelves(yt), homeShelves(yt)]);

  const out: Shelf[] = [];
  const taken = new Set<string>();
  for (const shelf of [...charts, ...live]) {
    if (taken.has(shelf.id)) continue;
    taken.add(shelf.id);
    out.push(capped(shelf));
  }

  if (out.length >= MIN_SHELVES) return out;

  // Thin region (or YouTube refused): pad from the curated categories.
  const filler = await manifestShelves(yt, MIN_SHELVES - out.length, taken);
  return [...out, ...filler];
}

function capped(shelf: Shelf): Shelf {
  if (shelf.items.length <= SHELF_ITEM_LIMIT) return shelf;
  return { ...shelf, items: shelf.items.slice(0, SHELF_ITEM_LIMIT) };
}

const shelvesFrom = (nodes: any[]): Shelf[] =>
  nodes.map(parseAnyShelf).filter(Boolean) as Shelf[];

/** This is a music app; a whole shelf of podcast shows is noise. */
const PODCAST_SHELF = /podcast/i;

/**
 * Top artists + Video charts for the region.
 *
 * The country comes from the page's own form control, not from `gl` — see
 * `browseWithForm`. A region YouTube does not chart (Bangladesh among them)
 * quietly yields the Global charts.
 */
async function chartShelves(yt: InnerTube): Promise<Shelf[]> {
  try {
    const wanted = yt.regionCode;
    let json = await yt.browseWithForm('FEmusic_charts', [wanted]);

    // The response carries the country menu, so one request tells us both the
    // charts and whether this region is charted at all.
    const supported = chartCountries(json);
    if (supported.size && !supported.has(wanted)) {
      const neighbour = nearestChartCountry(wanted, supported);
      // No neighbour reachable: keep the Global charts already in hand.
      if (neighbour) json = await yt.browseWithForm('FEmusic_charts', [neighbour]);
    }

    return shelvesFrom(sectionContents(json)).filter((s) => !PODCAST_SHELF.test(s.title));
  } catch {
    return [];
  }
}

/** The real home feed, followed through its continuations. */
async function homeShelves(yt: InnerTube): Promise<Shelf[]> {
  const out: Shelf[] = [];
  try {
    const first = await yt.browse('FEmusic_home');
    const sectionList = sectionListRenderer(first);
    const items = sectionList?.contents ?? [];
    out.push(...shelvesFrom(items));

    let token = continuationToken(sectionList, items);
    for (let page = 0; page < MAX_HOME_PAGES && token; page++) {
      const next = await yt.browseContinuation(token);
      const { items: more, sectionList: nextList } = continuationItems(next);
      if (!more.length) break;
      out.push(...shelvesFrom(more));
      token = continuationToken(nextList, more);
    }
  } catch {
    // Leave what we have; buildHome falls back to the manifest if it's thin.
  }
  return out;
}

/**
 * The previous Home, kept as a safety net. Composes display shelves out of the
 * mood/genre category pages, skipping any title the live feed already provided.
 *
 * Composition matches source shelves by English title, so under a non-English
 * `hl` nothing matches and it would return empty. That is why anything left
 * over from the pages we already fetched is appended afterwards: a thin Home is
 * recoverable, an empty one is not.
 */
async function manifestShelves(
  yt: InnerTube,
  need: number,
  taken: Set<string>,
): Promise<Shelf[]> {
  const specs = HOME_MANIFEST.filter((s) => !taken.has(slug(s.title))).slice(0, need);
  if (!specs.length) return [];

  const pages = await Promise.all(
    [...new Set(specs.map((s) => s.category))].map(async (key) => {
      try {
        const json = await yt.browse(
          'FEmusic_moods_and_genres_category',
          CATEGORIES[key].params,
        );
        return [key, shelvesFrom(sectionContents(json))] as const;
      } catch {
        return [key, [] as Shelf[]] as const;
      }
    }),
  );
  const byCategory = new Map(pages);

  const out: Shelf[] = [];
  for (const spec of specs) {
    const available = byCategory.get(spec.category) ?? [];
    const items: MediaItem[] = [];
    const seen = new Set<string>();
    const limit = spec.limit ?? SHELF_ITEM_LIMIT;

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
        if (items.length >= limit) break;
      }
      if (items.length >= limit) break;
    }

    // A shelf whose sources all vanished is dropped rather than shown empty.
    if (items.length) {
      out.push({ id: slug(spec.title), title: spec.title, items });
      taken.add(slug(spec.title));
    }
  }

  if (out.length >= need) return out;

  // Composition came up short — most likely a non-English `hl`, where the
  // English source titles never match. Use the category shelves as they came.
  for (const [, shelves] of byCategory) {
    for (const shelf of shelves) {
      if (out.length >= need) return out;
      if (taken.has(shelf.id)) continue;
      taken.add(shelf.id);
      out.push(capped(shelf));
    }
  }

  return out;
}
