/**
 * Refresh the parser fixtures from live InnerTube.
 * Run manually when a parser test starts failing:  node test/capture-fixtures.mjs
 */
import { writeFileSync } from 'node:fs';
const UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36';
const html = await (await fetch('https://music.youtube.com/', {headers:{'User-Agent':UA,'Cookie':'SOCS=CAI'}})).text();
const CV = html.match(/"INNERTUBE_CLIENT_VERSION":"(.*?)"/)[1];
const VD = html.match(/"VISITOR_DATA":"(.*?)"/)[1];
async function call(endpoint, body) {
  const r = await fetch(`https://music.youtube.com/youtubei/v1/${endpoint}?prettyPrint=false`, {
    method:'POST',
    headers:{'Content-Type':'application/json','Origin':'https://music.youtube.com','Referer':'https://music.youtube.com/',
      'User-Agent':UA,'X-Youtube-Client-Name':'67','X-Youtube-Client-Version':CV,'X-Goog-Visitor-Id':VD,
      'Accept-Language':'en-US,en;q=0.9'},
    body: JSON.stringify({context:{client:{clientName:'WEB_REMIX',clientVersion:CV,hl:'en',gl:'US',visitorData:VD}},...body}),
  });
  return r.json();
}
const dir = new URL('./fixtures/', import.meta.url);
const save = (n, j) => writeFileSync(new URL(n, dir), JSON.stringify(j));
save('category-feelgood.json', await call('browse', {browseId:'FEmusic_moods_and_genres_category', params:'ggMPOg1uXzZQbDB5eThLRTQ3'}));
save('search-dojacat.json',    await call('search', {query:'Doja Cat'}));
save('artist-dojacat.json',    await call('browse', {browseId:'UCwgX_dLqGYna_7Fm8ecf4Ng'}));

// Radio + lyrics: "Bazi" (Fazel Deriss) has LyricFind lyrics; Rick Astley's OMV has none.
const lyricsId = (next) => next.contents.singleColumnMusicWatchNextResultsRenderer.tabbedRenderer
  .watchNextTabbedResultsRenderer.tabs.map((t) => t.tabRenderer.endpoint?.browseEndpoint)
  .find((b) => b?.browseEndpointContextSupportedConfigs?.browseEndpointContextMusicConfig?.pageType === 'MUSIC_PAGE_TYPE_TRACK_LYRICS')?.browseId;
const watch = { isAudioOnly: true, enablePersistentPlaylistPanel: true };
const radio = await call('next', { videoId: 'RObj2xcWuP0', playlistId: 'RDAMVMRObj2xcWuP0', ...watch });
save('radio-bazi.json', radio);
const token = radio.contents.singleColumnMusicWatchNextResultsRenderer.tabbedRenderer.watchNextTabbedResultsRenderer
  .tabs[0].tabRenderer.content.musicQueueRenderer.content.playlistPanelRenderer.continuations[0].nextRadioContinuationData.continuation;
save('radio-bazi-continuation.json', await call('next', { continuation: token, playlistId: 'RDAMVMRObj2xcWuP0', ...watch }));
save('lyrics-bazi.json', await call('browse', { browseId: lyricsId(radio) }));
const rick = await call('next', { videoId: 'dQw4w9WgXcQ', ...watch });
save('lyrics-unavailable.json', await call('browse', { browseId: lyricsId(rick) }));
console.log('fixtures written (clientVersion', CV + ')');
