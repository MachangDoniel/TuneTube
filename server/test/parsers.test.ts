/**
 * These tests exist to catch YouTube changing its payload shape. When one fails,
 * refresh the fixtures (`node test/capture-fixtures.mjs`) and see whether the
 * parser or the shape actually changed.
 */
import { describe, expect, it } from 'vitest';
import {
  lyricsBrowseId, parseAnyItem, parseAnyShelf, parseCardShelf, parseLyrics, parseWatchPlaylist,
  chartCountries, sectionContents, slug, unwrapItemSections,
} from '../src/innertube/parsers';
import { nearestChartCountry, serviceableRegion } from '../src/config';
import type { MediaItem, Shelf } from '../src/types';

import category from './fixtures/category-feelgood.json';
import search from './fixtures/search-dojacat.json';
import artist from './fixtures/artist-dojacat.json';
import radio from './fixtures/radio-bazi.json';
import radioContinuation from './fixtures/radio-bazi-continuation.json';
import lyricsBazi from './fixtures/lyrics-bazi.json';
import lyricsUnavailable from './fixtures/lyrics-unavailable.json';

const shelvesOf = (json: any): Shelf[] =>
  sectionContents(json).map(parseAnyShelf).filter(Boolean) as Shelf[];

describe('mood/genre category page', () => {
  const shelves = shelvesOf(category);

  it('parses multiple carousel shelves', () => {
    expect(shelves.length).toBeGreaterThan(5);
  });

  it('still contains the shelves the home manifest depends on', () => {
    const titles = shelves.map((s) => s.title);
    // If these disappear, HOME_MANIFEST rows go empty — that is the real risk.
    expect(titles).toContain('Feeling happy');
    expect(titles).toContain('Feel-good pop');
  });

  it('gives every card an id, title and thumbnail', () => {
    const items = shelves.flatMap((s) => s.items);
    expect(items.length).toBeGreaterThan(20);
    for (const i of items) {
      expect(i.id).toBeTruthy();
      expect(i.title).toBeTruthy();
      expect(i.thumbnailUrl).toMatch(/^https:\/\//);
    }
  });

  it('strips YouTube boilerplate out of subtitles', () => {
    const subs = shelves.flatMap((s) => s.items.map((i) => i.subtitle ?? ''));
    expect(subs.some((s) => s.includes('YouTube Music'))).toBe(false);
    expect(subs.some((s) => s === 'Playlist')).toBe(false);
  });
});

describe('search', () => {
  const sections =
    (search as any).contents.tabbedSearchResultsRenderer.tabs[0].tabRenderer.content
      .sectionListRenderer.contents;

  it('parses the top-result card', () => {
    const node = sections.find((s: any) => s.musicCardShelfRenderer);
    const shelf = parseCardShelf(node);
    expect(shelf?.items[0].title).toBe('Doja Cat');
    expect(shelf?.items[0].kind).toBe('artist');
  });

  it('drops podcast episodes, which YouTube mixes in with songs', () => {
    // The fixture genuinely contains 6 Episode rows. Before the filter they
    // were parsed as songs and shown under "Songs" in the app.
    const raw = JSON.stringify(search);
    expect(raw).toContain('"Episode"');

    const items = unwrapItemSections(
      sections.filter((s: any) => s.itemSectionRenderer),
    )
      .map(parseAnyItem)
      .filter(Boolean) as MediaItem[];

    const leaked = items.filter((i) =>
      /Episode|Podcast/.test(i.subtitle ?? ''),
    );
    expect(leaked).toEqual([]);
  });

  it('flattens itemSection-wrapped rows and classifies their kinds', () => {
    const items = unwrapItemSections(
      sections.filter((s: any) => s.itemSectionRenderer),
    )
      .map(parseAnyItem)
      .filter(Boolean) as MediaItem[];

    expect(items.length).toBeGreaterThan(10);
    const kinds = new Set(items.map((i) => i.kind));
    expect(kinds.has('song')).toBe(true);
    expect(kinds.has('artist')).toBe(true);
  });
});

describe('artist page', () => {
  const shelves = shelvesOf(artist);

  it('exposes a top-songs shelf', () => {
    expect(shelves.length).toBeGreaterThan(2);
    expect(shelves[0].items.length).toBeGreaterThan(3);
  });

  it('separates artist and album so the client can pick a subtitle', () => {
    const first = shelves[0].items[0];
    expect(first.artistName).toBeTruthy();
    expect(first.albumName).toBeTruthy();
    expect(first.artistName).not.toBe(first.albumName);
  });

  it('resolves song rows to a playable videoId', () => {
    const songs = shelves[0].items.filter((i) => i.kind === 'song');
    expect(songs.length).toBeGreaterThan(0);
    for (const s of songs) expect(s.id).toMatch(/^[\w-]{11}$/);
  });
});

describe('radio (watch-next queue)', () => {
  const first = parseWatchPlaylist(radio);
  const more = parseWatchPlaylist(radioContinuation);

  it('parses the first page with its "Mix" title and a continuation', () => {
    expect(first.title).toMatch(/Mix$/);
    expect(first.tracks.length).toBeGreaterThan(20);
    expect(first.continuation).toBeTruthy();
    // The seed track leads the queue.
    expect(first.tracks[0].id).toBe('RObj2xcWuP0');
  });

  it('parses continuation pages', () => {
    expect(more.tracks.length).toBeGreaterThan(10);
    expect(more.tracks[0].id).not.toBe(first.tracks[0].id);
  });

  it('splits the byline into artist and album, and drops views/likes', () => {
    const bazi = first.tracks[0];
    expect(bazi).toMatchObject({
      title: 'Bazi', kind: 'song', artistName: 'Fazel Deriss', albumName: 'Bazi', durationSeconds: 158,
    });
    for (const t of [...first.tracks, ...more.tracks]) {
      expect(t.id).toMatch(/^[\w-]{11}$/);
      expect(t.artistName ?? '').not.toMatch(/views|likes|•/);
      expect(t.thumbnailUrl).toMatch(/^https:\/\//);
    }
  });

  it('marks music videos as video and album tracks as song', () => {
    const kinds = new Set(first.tracks.map((t) => t.kind));
    expect(kinds.has('song')).toBe(true);
    expect(kinds.has('video')).toBe(true);
  });

  it('finds the lyrics page id', () => {
    expect(lyricsBrowseId(radio)).toMatch(/^MPLY/);
  });
});

describe('lyrics', () => {
  it('parses lyrics text and strips the "Source:" prefix', () => {
    const lyrics = parseLyrics(lyricsBazi);
    expect(lyrics?.text.split('\n').length).toBeGreaterThan(5);
    expect(lyrics?.source).toBe('LyricFind');
  });

  it('returns null for the "Lyrics not available" page', () => {
    expect(parseLyrics(lyricsUnavailable)).toBeNull();
  });
});

describe('slug', () => {
  it('slugifies Latin titles readably', () => {
    expect(slug('Trending community playlists')).toBe('trending-community-playlists');
    expect(slug('Ghazal & Sufi Essentials')).toBe('ghazal-sufi-essentials');
  });

  it('gives non-Latin titles distinct, stable ids', () => {
    // Regression: these all stripped to the same '' and fell back to one shared
    // id, so a Bengali or Japanese feed deduplicated down to a single shelf.
    const bengali = ['ভিডিও চার্ট', 'সেরা শিল্পী', 'ভারতীয় মিউজিক', 'নতুন রিলিজ'];
    const ids = bengali.map(slug);
    expect(new Set(ids).size).toBe(bengali.length);
    expect(ids).not.toContain('shelf');
    // Stable across calls — the id is a cache key and a list identity.
    expect(bengali.map(slug)).toEqual(ids);
  });

  it('still has a defined result for an empty title', () => {
    expect(slug('')).toBe('shelf');
  });
});

/** Build a charts-menu option the way YouTube encodes it. */
const countryOption = (code: string) => ({
  musicMultiSelectMenuItemRenderer: {
    formItemEntityKey: encodeURIComponent(
      btoa(`\u0012'explore_charts_country_menu_316766567${code} \u0001(\u0001`),
    ),
  },
});

describe('chartCountries', () => {
  it('reads the offered country codes out of the menu', () => {
    const json = { a: { b: [countryOption('BR'), countryOption('IN')] }, c: countryOption('ZZ') };
    expect(chartCountries(json)).toEqual(new Set(['BR', 'IN', 'ZZ']));
  });

  it('returns an empty set rather than throwing on junk', () => {
    expect(chartCountries({ musicMultiSelectMenuItemRenderer: { formItemEntityKey: 'not base64!' } }).size).toBe(0);
    expect(chartCountries(null).size).toBe(0);
  });
});

describe('nearestChartCountry', () => {
  const supported = new Set(['IN', 'NG', 'ZA', 'US', 'BR']);

  it('sends uncharted South Asian regions to India', () => {
    // The case that matters: Bangladesh is not charted, and Global is a far
    // worse answer for those listeners than India.
    expect(nearestChartCountry('BD', supported)).toBe('IN');
    expect(nearestChartCountry('PK', supported)).toBe('IN');
    expect(nearestChartCountry('LK', supported)).toBe('IN');
  });

  it('follows the chain when the first hop is itself uncharted', () => {
    // CY -> IT, and with IT unavailable there is nowhere further to go.
    expect(nearestChartCountry('CY', supported)).toBeUndefined();
    expect(nearestChartCountry('GH', supported)).toBe('NG');
  });

  it('gives up rather than looping', () => {
    expect(nearestChartCountry('ZZ', supported)).toBeUndefined();
    expect(nearestChartCountry('XX', supported)).toBeUndefined();
  });
});

describe('serviceableRegion', () => {
  it('maps regions YouTube refuses onto ones it serves', () => {
    // These return HTTP 400 for every endpoint, not just charts, so the whole
    // screen came back empty until the request was made in these terms.
    expect(serviceableRegion('AF')).toBe('IN');
    expect(serviceableRegion('BT')).toBe('IN');
    expect(serviceableRegion('CU')).toBe('MX');
    expect(serviceableRegion('AL')).toBe('RS');
    expect(serviceableRegion('FJ')).toBe('AU');
    expect(serviceableRegion('MN')).toBe('KR');
  });

  it('resolves through a chain to a terminal country', () => {
    // HT -> DO, and DO is charted, so it terminates there.
    expect(serviceableRegion('HT')).toBe('DO');
  });

  it('falls back to US for anything unmapped', () => {
    expect(serviceableRegion('US')).toBe('US');
    expect(serviceableRegion('ZZ')).toBe('US');
    expect(serviceableRegion('QQ')).toBe('US');
  });
});
