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

const SESSION_KEY = 'innertube:session:v1';
const SESSION_TTL = 60 * 60 * 6;

// Only used if the homepage scrape fails; requests still work, continuations may not.
const FALLBACK_CLIENT_VERSION = '1.20260906.16.00';

export interface Session {
  clientVersion: string;
  visitorData: string;
}

export class InnerTube {
  private session: Session | null = null;

  constructor(
    private kv: KVNamespace,
    private lang = 'en',
    private region = 'US',
  ) {}

  /** Scrape clientVersion + visitorData from the YTM homepage, cached in KV. */
  async getSession(): Promise<Session> {
    if (this.session) return this.session;

    const cached = await this.kv.get(SESSION_KEY, 'json');
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
    await this.kv.put(SESSION_KEY, JSON.stringify(session), {
      expirationTtl: SESSION_TTL,
    });
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

  browse(browseId: string, params?: string) {
    return this.post('browse', params ? { browseId, params } : { browseId });
  }

  /** Continuation tokens go in the BODY. The ?continuation= query param is dead. */
  browseContinuation(token: string) {
    return this.post('browse', { continuation: token });
  }

  search(query: string, params?: string) {
    return this.post('search', params ? { query, params } : { query });
  }
}
