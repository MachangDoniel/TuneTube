import { InnerTube } from '../innertube/client';
import {
  lyricsBrowseId, parseLyrics, parseWatchPlaylist,
  type Lyrics, type WatchPlaylist,
} from '../innertube/parsers';

const radioPlaylistId = (videoId: string) => `RDAMVM${videoId}`;

/** "<Song> Mix": the radio YouTube Music autoplays into when a queue runs out. */
export async function getRadio(
  yt: InnerTube,
  videoId: string,
  continuation?: string,
): Promise<WatchPlaylist> {
  const json = continuation
    ? await yt.nextContinuation(continuation, radioPlaylistId(videoId))
    : await yt.next(videoId, radioPlaylistId(videoId));
  const radio = parseWatchPlaylist(json);
  // The first page leads with the seed track itself; the client already has it.
  if (!continuation) radio.tracks = radio.tracks.filter((t) => t.id !== videoId);
  return radio;
}

/** Plain (unsynced) lyrics. Two hops: `next` names the lyrics page, `browse` fetches it. */
export async function getLyrics(yt: InnerTube, videoId: string): Promise<Lyrics | null> {
  const browseId = lyricsBrowseId(await yt.next(videoId));
  if (!browseId) return null;
  return parseLyrics(await yt.browse(browseId));
}
