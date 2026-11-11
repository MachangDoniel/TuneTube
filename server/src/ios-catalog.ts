// Entry point bundled for JavaScriptCore. The shared parsers and routes are
// also used by the Worker. Swift provides the HTTPS transport.
import { CATEGORIES, MOOD_CHIPS, TRENDING_SEARCHES, serviceableRegion } from './config';
import { InnerTube } from './innertube/client';
import { getArtist, getCategory, getPlaylist } from './routes/browse';
import { buildHome } from './routes/home';
import { doSearch } from './routes/search';
import { getLyrics, getRadio } from './routes/watch';

declare function nativeFetch(id: number, url: string, options: string): void;
declare function nativeComplete(id: string, result: string, error: string): void;

const pending = new Map<number, {
  resolve: (response: Response) => void;
  reject: (error: Error) => void;
}>();
let nextFetchID = 0;

globalThis.fetch = (input, options) => new Promise((resolve, reject) => {
  const id = ++nextFetchID;
  pending.set(id, { resolve, reject });
  nativeFetch(id, String(input), JSON.stringify(options ?? {}));
});

const sessions = new Map<string, { value: unknown; expiresAt: number }>();
const sessionCache = {
  async get(key: string) {
    const cached = sessions.get(key);
    if (cached && cached.expiresAt > Date.now()) return cached.value;
    sessions.delete(key);
    return null;
  },
  async put(key: string, json: string, options: { expirationTtl: number }) {
    if (sessions.size >= 64) sessions.delete(sessions.keys().next().value!);
    sessions.set(key, {
      value: JSON.parse(json),
      expiresAt: Date.now() + options.expirationTtl * 1000,
    });
  },
} as unknown as KVNamespace;

const bootstrapRequests = new Map<string, ReturnType<InnerTube['getSession']>>();

class CatalogClient extends InnerTube {
  constructor(private readonly scope: string, lang: string, region: string) {
    super(sessionCache, lang, region, serviceableRegion(region));
  }

  override getSession(): ReturnType<InnerTube['getSession']> {
    const key = this.scope + ':' + this.regionCode;
    const existing = bootstrapRequests.get(key);
    if (existing) return existing;
    const request = super.getSession().finally(() => bootstrapRequests.delete(key));
    bootstrapRequests.set(key, request);
    return request;
  }
}

type Query = Record<string, string>;

async function run(path: string, query: Query) {
  const { gl = 'US', hl = 'en' } = query;
  const client = new CatalogClient(hl, hl, gl);
  const [, operation, id] = path.split('/');
  switch (operation) {
    case 'home': return { shelves: await buildHome(client) };
    case 'search': return { shelves: await doSearch(client, query.q ?? '', query.type) };
    case 'artist': return getArtist(client, id);
    case 'playlist': return getPlaylist(client, id);
    case 'category': {
      if (!Object.hasOwn(CATEGORIES, id)) throw new Error('Unknown category');
      return getCategory(client, id as keyof typeof CATEGORIES);
    }
    case 'radio': return getRadio(client, id, query.continuation);
    case 'lyrics': return { lyrics: await getLyrics(client, id) };
    case 'config': return {
      moodChips: MOOD_CHIPS,
      trendingSearches: TRENDING_SEARCHES,
    };
    default: throw new Error('Unknown catalog operation');
  }
}

Object.assign(globalThis, {
  completeFetch(id: number, status: number, body: string, error: string) {
    const request = pending.get(id);
    pending.delete(id);
    if (!request) return;
    if (error) {
      request.reject(new Error(error));
    } else {
      // InnerTube uses only these fields of the fetch Response.
      request.resolve({
        status, ok: status >= 200 && status < 300,
        text: async () => body,
        json: async () => JSON.parse(body),
      } as Response);
    }
  },
  startCatalogRequest(id: string, path: string, query: string) {
    Promise.resolve()
      .then(() => run(path, JSON.parse(query)))
      .then(
        value => nativeComplete(id, JSON.stringify(value), ''),
        error => nativeComplete(id, '', String(error)),
      );
  },
});
