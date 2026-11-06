/**
 * Thin InnerTube (YouTube Music private API) client.
 *
 * Two things here are load-bearing and were verified against live responses:
 *   1. clientVersion must be CURRENT. A stale version silently degrades the
 *      response (continuations stop working entirely). We scrape it from the
 *      YTM homepage rather than hardcoding it.
 *   2. visitorData must be present and stable, or continuation tokens are
 *      ignored and the server just replays page 1.
 *
 * Both are cached in KV for 6h so we do at most one bootstrap per 6h per colo.
 */

const YTM_ORIGIN = 'https://music.youtube.com';
const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36';

// visitorData encodes a geolocation hint, so a session bootstrapped for one
// region must never be reused for another — the key carries the scope.
const SESSION_KEY_PREFIX = 'innertube:session:v2';
const SESSION_TTL = 60 * 60 * 6;

// Only used if the homepage scrape fails; requests still work, continuations may not.
const FALLBACK_CLIENT_VERSION = '1.20260906.16.00';

export interface Session {
  clientVersion: string;
  visitorData: string;
}

export class InnerTube {
  private session: Session | null = null;
  /** In-flight bootstrap, shared by concurrent callers. See `getSession`. */
  private pending: Promise<Session> | null = null;

  constructor(
    private kv: KVNamespace,
    private lang = 'en',
    private region = 'US',
  ) {}

  private get sessionKey(): string {
    return `${SESSION_KEY_PREFIX}:${this.lang}-${this.region}`;
  }

  /**
   * Scrape clientVersion + visitorData from the YTM homepage, cached in KV.
   *
   * Building Home issues a dozen browses in parallel on one instance. Without
   * sharing the in-flight bootstrap, every one of them would see no session and
   * scrape the homepage at the same time; YouTube throttles the burst and the
   * whole feed comes back empty on a cold region. Observed in production: the
   * first request for a new hl-gl fell all the way through to the fallback.
   */
  getSession(): Promise<Session> {
    if (this.session) return Promise.resolve(this.session);
    this.pending ??= this.bootstrap().finally(() => {
      this.pending = null;
    });
    return this.pending;
  }

  private async bootstrap(): Promise<Session> {
    const cached = await this.kv.get(this.sessionKey, 'json');
    if (cached) {
      this.session = cached as Session;
      return this.session;
    }

    let session: Session = {
      clientVersion: FALLBACK_CLIENT_VERSION,
      visitorData: '',
    };

    try {
      const res = await fetch(YTM_ORIGIN + '/', {
        headers: {
          'User-Agent': UA,
          'Accept-Language': `${this.lang}-${this.region},${this.lang};q=0.9`,
          // SOCS skips the EU consent interstitial, which otherwise returns a
          // consent page with no ytcfg at all.
          Cookie: 'SOCS=CAI; PREF=hl=' + this.lang + '&gl=' + this.region,
        },
      });
      const html = await res.text();
      const cv = html.match(/"INNERTUBE_CLIENT_VERSION":"(.*?)"/)?.[1];
      const vd = html.match(/"VISITOR_DATA":"(.*?)"/)?.[1];
      if (cv) session.clientVersion = cv;
      if (vd) session.visitorData = vd;
    } catch {
      // fall through to defaults
    }

    this.session = session;
    // Only persist a usable session. Caching a failed scrape (no visitorData)
    // would break continuations for the next six hours.
    if (session.visitorData) {
      await this.kv.put(this.sessionKey, JSON.stringify(session), {
        expirationTtl: SESSION_TTL,
      });
    }
    return session;
  }

  private async post(endpoint: string, body: Record<string, unknown>): Promise<any> {
    const { clientVersion, visitorData } = await this.getSession();

    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      Origin: YTM_ORIGIN,
      Referer: YTM_ORIGIN + '/',
      'User-Agent': UA,
      'X-Youtube-Client-Name': '67', // WEB_REMIX
      'X-Youtube-Client-Version': clientVersion,
      'Accept-Language': `${this.lang}-${this.region},${this.lang};q=0.9`,
    };
    if (visitorData) headers['X-Goog-Visitor-Id'] = visitorData;

    const payload = {
      context: {
        client: {
          clientName: 'WEB_REMIX',
          clientVersion,
          hl: this.lang,
          gl: this.region,
          ...(visitorData ? { visitorData } : {}),
        },
        user: { lockedSafetyMode: false },
      },
      ...body,
    };

    const res = await fetch(
      `${YTM_ORIGIN}/youtubei/v1/${endpoint}?prettyPrint=false`,
      { method: 'POST', headers, body: JSON.stringify(payload) },
    );

    if (!res.ok) {
      throw new Error(`InnerTube ${endpoint} failed: HTTP ${res.status}`);
    }
    return res.json();
  }

  /** The region this client is scoped to, for endpoints that select it explicitly. */
  get regionCode(): string {
    return this.region;
  }

  browse(browseId: string, params?: string) {
    return this.post('browse', params ? { browseId, params } : { browseId });
  }

  /**
   * Browse a page whose region/filter is chosen by its own form control rather
   * than by `gl`. The charts page is the one that matters: for signed-out
   * requests YouTube geolocates by IP and ignores the `gl` in the context, so
   * `formData.selectedValues` is the only thing that actually switches country.
   *
   * An unsupported code (Bangladesh is not among the ~69 offered) is not an
   * error — YouTube just returns the Global charts.
   */
  browseWithForm(browseId: string, selectedValues: string[]) {
    return this.post('browse', { browseId, formData: { selectedValues } });
  }

  /** Continuation tokens go in the BODY. The ?continuation= query param is dead. */
  browseContinuation(token: string) {
    return this.post('browse', { continuation: token });
  }

  search(query: string, params?: string) {
    return this.post('search', params ? { query, params } : { query });
  }

  /**
   * Watch-next panel for a track. With `RDAMVM<videoId>` as the playlist this is
   * the endless radio ("<Song> Mix") YouTube Music autoplays into.
   */
  next(videoId: string, playlistId?: string) {
    return this.post('next', {
      videoId,
      ...(playlistId ? { playlistId } : {}),
      isAudioOnly: true,
      enablePersistentPlaylistPanel: true,
    });
  }

  /** Continuation tokens here also go in the body, alongside the radio playlistId. */
  nextContinuation(token: string, playlistId: string) {
    return this.post('next', {
      continuation: token,
      playlistId,
      isAudioOnly: true,
      enablePersistentPlaylistPanel: true,
    });
  }
}
