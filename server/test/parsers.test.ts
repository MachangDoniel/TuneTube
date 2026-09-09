/**
 * These tests exist to catch YouTube changing its payload shape. When one fails,
 * refresh the fixtures (`node test/capture-fixtures.mjs`) and see whether the
 * parser or the shape actually changed.
 */
import { describe, expect, it } from 'vitest';
import {
  parseAnyItem, parseAnyShelf, parseCardShelf, sectionContents, unwrapItemSections,
} from '../src/innertube/parsers';
import type { MediaItem, Shelf } from '../src/types';

import category from './fixtures/category-feelgood.json';
import search from './fixtures/search-dojacat.json';
import artist from './fixtures/artist-dojacat.json';

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
