import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { InnerTube } from './innertube/client';
import { cached } from './cache';
import { buildHome } from './routes/home';
import { getArtist, getCategory, getPlaylist } from './routes/browse';
import { doSearch } from './routes/search';
import { CATEGORIES, MOOD_CHIPS, TRENDING_SEARCHES, type CategoryKey } from './config';
import type { Env } from './types';

const app = new Hono<{ Bindings: Env }>();
app.use('*', cors());

const TTL = {
  home: 60 * 60,        // 1h
  search: 60 * 10,      // 10m
  artist: 60 * 60 * 24, // 24h
  playlist: 60 * 60 * 6,
  category: 60 * 60 * 6,
} as const;

function client(c: any) {
  return new InnerTube(
    c.env.CACHE,
    c.req.query('hl') || c.env.YTM_LANG || 'en',
    c.req.query('gl') || c.env.YTM_REGION || 'US',
  );
}

/** Region/lang participate in every cache key so feeds never cross-contaminate. */
/** `?nocache=1` forces a refetch. Used in dev and to flush a bad cached feed. */
function noCache(c: any): boolean {
  return c.req.query('nocache') === '1';
}

function scope(c: any) {
  const gl = c.req.query('gl') || c.env.YTM_REGION || 'US';
  const hl = c.req.query('hl') || c.env.YTM_LANG || 'en';
  return `${hl}-${gl}`;
}

app.get('/', (c) => c.json({ service: 'tunetube-api', ok: true }));

app.get('/v1/home', async (c) => {
  const key = `home:${scope(c)}:v2`;
  try {
    const shelves = await cached(c.env, key, TTL.home, () => buildHome(client(c)), noCache(c));
    return c.json({ shelves });
  } catch (err) {
    return c.json({ shelves: [], error: String(err) }, 502);
  }
});

app.get('/v1/search', async (c) => {
  const q = (c.req.query('q') ?? '').trim();
  if (!q) return c.json({ shelves: [] });
  const type = c.req.query('type') ?? undefined;
  const key = `search:${scope(c)}:${type ?? 'all'}:${q.toLowerCase()}`;
  try {
    const shelves = await cached(c.env, key, TTL.search, () =>
      doSearch(client(c), q, type), noCache(c),
    );
    return c.json({ shelves });
  } catch (err) {
    return c.json({ shelves: [], error: String(err) }, 502);
  }
});

app.get('/v1/artist/:browseId', async (c) => {
  const browseId = c.req.param('browseId');
  const key = `artist:${scope(c)}:${browseId}`;
  try {
    const artist = await cached(c.env, key, TTL.artist, () =>
      getArtist(client(c), browseId), noCache(c),
    );
    return c.json(artist);
  } catch (err) {
    return c.json({ error: String(err) }, 502);
  }
});

app.get('/v1/playlist/:playlistId', async (c) => {
  const playlistId = c.req.param('playlistId');
  const key = `playlist:${scope(c)}:${playlistId}`;
  try {
    const playlist = await cached(c.env, key, TTL.playlist, () =>
      getPlaylist(client(c), playlistId), noCache(c),
    );
    return c.json(playlist);
  } catch (err) {
    return c.json({ error: String(err) }, 502);
  }
});

app.get('/v1/category/:key', async (c) => {
  const key = c.req.param('key') as CategoryKey;
  if (!(key in CATEGORIES)) return c.json({ error: 'unknown category' }, 404);
  const cacheKey = `category:${scope(c)}:${key}`;
  try {
    const data = await cached(c.env, cacheKey, TTL.category, () =>
      getCategory(client(c), key), noCache(c),
    );
    return c.json(data);
  } catch (err) {
    return c.json({ error: String(err) }, 502);
  }
});

/**
 * Remote config. This is the kill-switch: mood chips, trending searches and
 * hiddenShelfIds are all editable without an App Store release.
 */
app.get('/v1/config', (c) =>
  c.json({
    moodChips: MOOD_CHIPS,
    trendingSearches: TRENDING_SEARCHES,
    hiddenShelfIds: [] as string[],
    minSupportedBuild: 1,
    freePlaylistLimit: 1,
    paywall: {
      title: 'Unlock Pro',
      subtitle:
        'Access your full library without limits and keep your music experience uninterrupted.',
      lifetimeProductId: 'com.tunetube.pro.lifetime',
      weeklyProductId: 'com.tunetube.pro.weekly',
      highlightedProductId: 'com.tunetube.pro.lifetime',
      termsUrl: 'https://example.com/terms',
      privacyUrl: 'https://example.com/privacy',
    },
  }),
);

export default app;
