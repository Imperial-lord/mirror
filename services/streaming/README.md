# Mirror playback service

Node 22+, WebTorrent 3.0.21 (pinned), HTTP byte-range delivery to AVPlayer.

## Local

```
cp .env.example .env # fill deployment settings locally
npm ci --omit=optional
npm test
npm run dev:start # macOS: survives closing the terminal/chat
```

`npm run dev:status` checks the local launchd job; `npm run dev:stop` stops it.
Logs live in `.runtime/service.log`. Run `npm start` for a foreground process on
other platforms. The local job lasts until stopped or logout; run `dev:start` again
after login.

Listens on `127.0.0.1:8787`. iOS Simulator uses that address by default.
No authentication bypass is permitted when binding to a public interface.

## Deploy

Build the Dockerfile, set `HOST=0.0.0.0`, `FIREBASE_PROJECT_ID` to the app's Firebase
project, and supply Firebase Admin application-default credentials using your hosting
platform's workload identity or mounted credentials (never commit service keys).
Place behind an HTTPS reverse proxy; disable proxy response buffering and allow long
streaming responses. Allow outbound TCP and UDP for peers/trackers/DHT. Expose only
the HTTP service through the proxy. Limit POST requests per user/IP at the gateway.

Set `PLAYBACK_SERVICE_URL` in `apps/ios/Config/Local.xcconfig` before a device build. For Simulator development, `UserDefaults` key `PlaybackServiceURL` also works.
Device builds intentionally require configuration; no hosted server is assumed.

POST `/v1/sessions` with Firebase Bearer ID token and JSON `{"hash":"40 hex chars"}`.
Returns a random session ID and relative MP4 path. The media URL is a temporary
capability: keep URLs out of proxy access logs. GET/HEAD accepts single byte ranges,
including suffixes for MP4 tail metadata. DELETE the session when playback ends.
Health probe: GET `/health`. Creation errors use 400/401/413/422/502/503/504.

## Download and storage policy

No full-file selection, disk movie downloads, or persistent movie storage.
Each session has its own client, largest MP4 file, 128 MiB in-memory LRU piece cache,
and at most four concurrent media requests. Each response selects a 4 MiB window,
then advances only as HTTP backpressure permits. Cancelling a seek destroys its
read stream and selection. Complete torrent pieces surrounding requested bytes
are unavoidable; MP4 metadata may be read from the tail. Watching the entire movie
will transfer it over time, but older pieces are evicted. Four-session admission
limit bounds cache storage to 512 MiB plus protocol/read buffers. Idle sessions
expire after ten minutes; explicit DELETE frees resources immediately. Restarts
discard all sessions and cached bytes. A player must open a fresh session afterward.

The pinned adapter calls WebTorrent's private `_markUnverified(index)` when a stored
piece is evicted; otherwise its bitfield would advertise bytes that no longer exist.
A real local seeder/leecher test covers seek-away, eviction, seek-back and refetch.
Re-run that integration test before changing WebTorrent versions.

Only compatible MP4 content is selected. This service does not transcode unsupported
video/audio codecs; choose an AVC/AAC source for broad iOS compatibility. Moving the
engine server-side cannot make an unseeded torrent available. Server failures remain
in service logs; the viewer sees a generic playback error and retry action.

The Swift app no longer builds or invokes the old `Core/Torrent` implementation or
SwiftTorrent dependency. Legacy code/tests remain in the repository for reference;
the backend integration tests replace the former in-app transport tests.

## Subtitles

GET `/v1/subtitles/{imdb}/{en|it|es|fr}` uses the same Firebase authentication as
session creation. The provider adapter reads YTS subtitle listings, follows only
allowlisted HTTPS download hosts, and extracts SRT in memory with compressed and
uncompressed size limits. Missing/unusable requested-language releases fall back
to English; responses identify the actual language. If English is also unavailable,
it returns 404 and playback continues without captions. The bounded 32-track cache
expires after six hours. No subtitle ZIP contents are written to disk.
The iOS player renders timed cues against AVPlayer time, including after seeking;
Off clears captions and cancels the in-flight subtitle request.

## Year-filtered catalog

GET `/v1/catalog?year=1999&page=1&sort_by=like_count` (plus optional `genre`,
`minimum_rating`, `query_term`) follows the YTS.GG website's year-filtered browse
route. Its JSON list API currently ignores `year`; do not replace this adapter
with a query parameter without validating results. Same Firebase authentication
as session creation. Results include real YTS API movie records and `hasMore`.
The adapter validates every movie year, resolves ambiguous search titles by the
website's catalog ID, preserves source ordering, limits concurrent lookups to
four, and caches 64 pages/512 titles for one hour. HTML changes/provider blocks
return retryable errors rather than empty or unfiltered results. Deployed
servers must allow HTTPS access to yts.gg and movies-api.accel.li.

Offline downloads use the same bounded range endpoint; full files live on the device,
not this server. Media request slots are released immediately on socket close, even
if a stalled upstream iterator never finishes. Capacity returns HTTP 503 rather than
silently dropping the connection. `media.test.mjs` covers cancellation cleanup,
bounded windows, and HEAD/capacity handling. See `../docs/downloads.md` for the iOS
queue, resume behavior, and local-player integration.

## Movie credits

GET `/v1/credits/{tt IMDb ID}` uses the existing Firebase authentication.
Set `OMDB_API_KEY` in the server environment to activate OMDb actor, director,
and writer names. The key stays on the server. Successful responses are cached
for seven days with 256 entries and four concurrent provider requests.
Concurrent requests for the same movie share a provider lookup. A rolling
24-hour budget of 900 provider calls leaves headroom under the 1,000-call plan.
Cache hits remain available after the budget is exhausted. Quota responses
suspend provider calls for 24 hours, invalid keys for one hour, and transient
failures for one minute. Missing titles are cached for one hour. These counters
and caches live in memory and reset when the service restarts.
Absent configuration, exhausted quota, and provider failures return 503 so the
app continues with Wikidata credits. Unexpected adapter errors return 502.

The current app uses Wikidata/Wikimedia alone for credits, biographies, and
portraits. It publishes one completed credits list, caches metadata for seven
days, and links portrait license/source pages. The OMDb endpoint remains for
older installed app versions. Filmography lists only Wikimedia-linked titles
available in the movie catalog. Missing biography fields and unavailable
filmographies are omitted. Pull to refresh retries person metadata.
