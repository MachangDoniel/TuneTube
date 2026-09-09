import type { Env } from './types';

/** KV-backed JSON cache. Never lets a cache fault break a request. */
export async function cached<T>(
  env: Env,
  key: string,
  ttlSeconds: number,
  produce: () => Promise<T>,
  bypass = false,
): Promise<T> {
  if (!bypass) {
    try {
      const hit = await env.CACHE.get(key, 'json');
      if (hit) return hit as T;
    } catch {
      /* cache read failure is not fatal */
    }
  }

  const value = await produce();

  try {
    // KV requires a minimum TTL of 60s.
    await env.CACHE.put(key, JSON.stringify(value), {
      expirationTtl: Math.max(60, ttlSeconds),
    });
  } catch {
    /* cache write failure is not fatal */
  }
  return value;
}
