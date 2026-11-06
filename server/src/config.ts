/**
 * Curated home manifest.
 *
 * The raw FEmusic_home feed is IP-geolocated and unstable (it returns a
 * different set of shelves per request, per colo). The app in the reference
 * recording shows a FIXED shelf order with recognisable titles, so we build
 * home ourselves from YTM mood/genre categories and relabel the shelves.
 *
 * Every `sourceShelves` entry below was verified to exist in the live category
 * response. Unknown titles are skipped silently, so YouTube renaming a shelf
 * degrades one row rather than breaking the screen.
 */

export interface CategoryRef {
  name: string;
  params: string;
}

/** browseId is always FEmusic_moods_and_genres_category; only params vary. */
export const CATEGORIES = {
  chill:      { name: 'Chill',              params: 'ggMPOg1uX1JOQWZFeDByc2Jm' },
  commute:    { name: 'Commute',            params: 'ggMPOg1uX044Z2o5WERLckpU' },
  energize:   { name: 'Energize',           params: 'ggMPOg1uX2lRZUZiMnNrQnJW' },
  feelGood:   { name: 'Feel good',          params: 'ggMPOg1uXzZQbDB5eThLRTQ3' },
  focus:      { name: 'Focus',              params: 'ggMPOg1uX0NvNGNhWThMYWRh' },
  party:      { name: 'Party',              params: 'ggMPOg1uX0pmQ0s2V0JRclZs' },
  romance:    { name: 'Romance',            params: 'ggMPOg1uX0FzQ2FhZWtUY211' },
  sleep:      { name: 'Sleep',              params: 'ggMPOg1uX1MxaFQ3Z0JMZkN4' },
  workout:    { name: 'Workout',            params: 'ggMPOg1uX09LWkhnTjRGRUJh' },
  decades:    { name: 'Decades',            params: 'ggMPOg1uX253QXk4VXN5NGdj' },
  hipHop:     { name: 'Hip-hop',            params: 'ggMPOg1uX0M2dmRieXNxTW1s' },
  pop:        { name: 'Pop',                params: 'ggMPOg1uX1lLQkxHbHhWQUUy' },
  rnb:        { name: 'R&B & soul',         params: 'ggMPOg1uX2JxQ2hxc2J5UFhR' },
  electronic: { name: 'Dance & electronic', params: 'ggMPOg1uX1NPTld3SDN3WGs4' },
  indie:      { name: 'Indie & alternative',params: 'ggMPOg1uX21NWWpBbU01SDgy' },
  jazz:       { name: 'Jazz',               params: 'ggMPOg1uX3lPcDFRaE9wM1BS' },
  rock:       { name: 'Rock',               params: 'ggMPOg1uXzJKTm5jUEZ5Uzlu' },
  latin:      { name: 'Latin',              params: 'ggMPOg1uX29wWTRjMHV1dWN5' },
  country:    { name: 'Country & Americana',params: 'ggMPOg1uX1RXcFlyZEpRb1d3' },
  metal:      { name: 'Metal',              params: 'ggMPOg1uXzdlSXhKZ0hMV1Z4' },
} as const;

export type CategoryKey = keyof typeof CATEGORIES;

export interface ShelfSpec {
  /** Display title shown in the app. */
  title: string;
  /** Which mood/genre category page to pull from. */
  category: CategoryKey;
  /** Shelf titles within that category to merge, in priority order. */
  sourceShelves: string[];
  limit?: number;
}

/** Mirrors the shelf order in the reference recording.
 *  Every sourceShelves title below was verified present in the live category
 *  response on 2026-09-09 (see server/test/fixtures). */
export const HOME_MANIFEST: ShelfSpec[] = [
  {
    title: 'Trending community playlists',
    category: 'pop',
    sourceShelves: ['Community playlists', 'Featured playlists'],
  },
  {
    title: 'Pump it up',
    category: 'energize',
    sourceShelves: ['Pop bangers', 'Hip-hop energy', 'Beast mode', 'Power boost'],
  },
  {
    title: 'Throwbacks',
    category: 'decades',
    sourceShelves: ['1980s', '1990s', '2000s', '1970s'],
  },
  {
    title: 'All-time essentials',
    category: 'pop',
    sourceShelves: ['Featured playlists', 'Albums'],
  },
  {
    title: 'Irresistible sing-alongs',
    category: 'party',
    sourceShelves: ['Pop party', 'Throwback party', 'Party today'],
  },
  {
    title: 'Feeling happy',
    category: 'feelGood',
    sourceShelves: ['Feeling happy', 'Feel-good pop', 'Fun throwbacks'],
  },
  {
    title: 'Late night drive',
    category: 'commute',
    sourceShelves: ['Hip-hop drive', 'Relaxing commute', 'Classic hits'],
  },
  {
    title: 'Wind down',
    category: 'chill',
    sourceShelves: ['Chill pop', 'Laidback + acoustic', 'Time to relax'],
  },
];

/** Mood chips on the Search tab — matches the recording's eight chips. */
export const MOOD_CHIPS: Array<{ id: CategoryKey; label: string; emoji: string }> = [
  { id: 'hipHop',     label: 'Hip-Hop',    emoji: '🎤' },
  { id: 'pop',        label: 'Pop',        emoji: '✨' },
  { id: 'rnb',        label: 'R&B',        emoji: '💛' },
  { id: 'electronic', label: 'Electronic', emoji: '🎛️' },
  { id: 'indie',      label: 'Indie',      emoji: '🌸' },
  { id: 'jazz',       label: 'Jazz',       emoji: '🎷' },
  { id: 'rock',       label: 'Rock',       emoji: '🔥' },
  { id: 'chill',      label: 'Lo-Fi',      emoji: '🌙' },
];

export const TRENDING_SEARCHES = [
  { label: 'Kendrick Lamar', emoji: '🏆' },
  { label: 'Sabrina Carpenter', emoji: '📝' },
  { label: 'Chappell Roan', emoji: '✨' },
  { label: 'Tyler the Creator', emoji: '🔥' },
  { label: 'Billie Eilish', emoji: '🌙' },
];

/** Search filter params (InnerTube `params` for typed search). */
export const SEARCH_FILTERS: Record<string, string> = {
  songs:     'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D',
  videos:    'EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D',
  albums:    'EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D',
  artists:   'EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D',
  playlists: 'EgWKAQIoAWoKEAkQChAFEAMQBA%3D%3D',
};

/**
 * Nearest charted neighbour for a country YouTube Music does not chart.
 *
 * YouTube charts ~69 countries. For everyone else the charts page silently
 * returns the Global list, which for a Bangladeshi or Pakistani listener is a
 * far worse answer than their regional neighbour's chart. Each entry points at
 * the closest country by shared music market, not merely by distance.
 *
 * Values may themselves be unlisted, so lookups follow the chain (see
 * `nearestChartCountry`). The real supported set is read from the live charts
 * response, so an entry here is a preference, never an assumption.
 */
export const CHART_REGION_FALLBACK: Record<string, string> = {
  // South Asia -> India
  BD: 'IN', PK: 'IN', LK: 'IN', NP: 'IN', BT: 'IN', MV: 'IN', AF: 'IN',

  // Sub-Saharan Africa
  GH: 'NG', CI: 'NG', SN: 'NG', CM: 'NG', ML: 'NG', BF: 'NG',
  ET: 'KE', RW: 'KE', SS: 'KE', SO: 'KE',
  ZM: 'ZA', MZ: 'ZA', BW: 'ZA', NA: 'ZA', MW: 'ZA', LS: 'ZA', SZ: 'ZA',

  // Middle East & North Africa
  QA: 'AE', KW: 'AE', BH: 'AE', OM: 'AE', JO: 'AE', LB: 'AE', SY: 'AE',
  IQ: 'SA', YE: 'SA', LY: 'EG', TN: 'EG', DZ: 'EG', MA: 'EG', SD: 'EG',

  // South-East & East Asia
  MM: 'TH', KH: 'TH', LA: 'TH', BN: 'MY', MO: 'HK', MN: 'KR',

  // Europe
  SK: 'CZ', BG: 'RO', MD: 'RO',
  SI: 'RS', HR: 'RS', BA: 'RS', MK: 'RS', AL: 'RS', ME: 'RS', XK: 'RS',
  GR: 'IT', CY: 'IT', MT: 'IT',
  LT: 'PL', LV: 'EE',
  BY: 'RU', KZ: 'RU', UZ: 'RU', KG: 'RU', TJ: 'RU', TM: 'RU', AM: 'RU',
  GE: 'TR', AZ: 'TR',

  // Americas & Caribbean
  CU: 'MX', BZ: 'MX', HT: 'DO', JM: 'US', TT: 'US', BS: 'US', PR: 'US',
  VE: 'CO', GY: 'BR', SR: 'BR',

  // Oceania
  FJ: 'AU', PG: 'AU', NC: 'AU', WS: 'NZ', TO: 'NZ',
};

/**
 * Walk `CHART_REGION_FALLBACK` until it reaches a country the live charts page
 * actually offers. Returns undefined when nothing suitable is reachable, in
 * which case the caller keeps the Global charts it already has.
 */
export function nearestChartCountry(
  code: string,
  supported: Set<string>,
): string | undefined {
  const seen = new Set<string>([code]);
  let next = CHART_REGION_FALLBACK[code];
  while (next && !seen.has(next)) {
    if (supported.has(next)) return next;
    seen.add(next);
    next = CHART_REGION_FALLBACK[next];
  }
  return undefined;
}
