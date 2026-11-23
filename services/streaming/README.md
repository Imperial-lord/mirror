# Mirror playback service

Node 22+, WebTorrent 3.0.21 (pinned), HTTP byte-range delivery to AVPlayer.

The optional macOS [AI search prototype](../../docs/ai-search.md) uses
`GROQ_API_KEY` on this backend. Its authenticated `POST /v1/ai/search` endpoint
returns catalogue-verified movie recommendations; the key is never shipped in the app.

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

No full-file selection. The single-node default keeps video pieces in memory. A
worker with `MIRROR_CACHE_DIR` set keeps verified pieces on its own disk across
sessions and restarts. Mount a writable directory dedicated to that worker. The
cache caps writes at 12 GiB, reserves 5 GiB of filesystem free space, and evicts
the least recently used pieces across titles. It is rebuildable and should not
be backed up. WebTorrent rechecks stored pieces when a torrent is opened.

For two workers, use distinct eight-character hex `MIRROR_NODE_ID` values, the
other worker's ID as `MIRROR_PEER_ID`, its private HTTP origin as
`MIRROR_PEER_URL`, and the same randomly generated `MIRROR_PEER_KEY` (at least
32 characters). Serve public traffic over TLS and restrict the worker HTTP
ports to the VCN. Session IDs carry the owner's prefix without changing the API
shape. Either ingress worker can forward range requests or deletes to the
owner. New sessions prefer a deterministic worker for cache locality and can
spill to the other if capacity is exhausted. Existing sessions cannot migrate
after a worker loss; reconnect opens a new session.

Optionally set `MIRROR_OBJECT_SOURCES` in the private server environment to a JSON
map of exact video source hashes to object-specific OCI read URLs. Keep the
bucket private, use expiring read grants, and only map authorized copies
matching the requested quality. Mirror probes the object for byte-range support
and falls back to the original source if the initial probe fails. Public clients
receive Mirror session paths and never see the bucket credentials.
Each torrent session has its own client, largest MP4 file, a shared disk cache or 128 MiB in-memory LRU piece cache,
and at most four concurrent media requests. Each response selects a 4 MiB window,
then advances only as HTTP backpressure permits. Cancelling a seek destroys its
read stream and selection. Complete torrent pieces surrounding requested bytes
are unavoidable; MP4 metadata may be read from the tail. Watching the entire movie
will transfer it over time, but older pieces are evicted. Four-session admission
limit bounds in-memory cache storage to 512 MiB plus protocol/read buffers. Idle sessions
expire after ten minutes; explicit DELETE frees resources immediately. Restarts
discard all sessions and RAM-cached bytes. A player must open a fresh session afterward.

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

### Movie previews

The worker fetches Popular Now, Top Rated, and all 18 genre rows directly from
the catalog, using the same 15-title requests as Mac Home. It also includes
each account's latest authenticated Home report, which supplies Selected For
You and Continue Watching. The server returns ready clips only for IDs in the
app's request. iOS movie details use the authenticated
`GET /v1/home-previews?movie_id=<id>` lookup, which reads the same ready clips
and leaves Home reports intact. A title without a ready clip keeps its artwork.
Deploy the updated preview API before releasing the iOS client.

The worker stores MP4s under prefixes such as `home/v1/popular-now/`,
`home/v1/top-rated/`, and `home/v1/genres/action/`. Movies reported by an
account outside the shared rows use `home/v1/reported-home/`. The worker
encodes each title once and copies the clip into each matching folder.
Private indexes at `home/rows/v1/catalog.json` and
`home/rows/v1/<account-hash>.json` map the catalog rows and account reports to
those object names, including pending clips. The clip read URL only covers
`home/v1/`. If the catalog service fails, the worker keeps the last complete
catalog snapshot.

Run `previews/api.mjs` on one worker with a persistent, private `/state` directory.
Build its image with `previews/Dockerfile` and an existing streaming service image
as `STREAMING_IMAGE`. Set `FIREBASE_PROJECT_ID`, `PREVIEW_OCI_NAMESPACE`,
`PREVIEW_OCI_BUCKET`, and `PREVIEW_READ_URL`. The read URL must be an OCI read-only
pre-authenticated request for `home/v1/` with listing disabled, and include the
`home/v1/` suffix. Keep it out of logs and rotate it before expiry. Route only
`/v1/home-previews` from the HTTPS ingress to this worker's API.

Grant that compute instance permission to manage objects in the dedicated clip
bucket through an OCI instance principal. Schedule an isolated refresh container
every 12 hours. Mount the API's state directory at `/state` and use a host lock
to keep runs from overlapping. The worker needs host networking for the OCI
instance metadata service.

```cron
17 */12 * * * root /usr/bin/flock -n /run/lock/mirror-home-preview-refresh.lock /usr/bin/docker run --rm --network host --memory 320m --cpus .65 --env-file /path/to/preview.env -v /var/lib/mirror-home-previews:/state mirror-home-previews:local nice -n 10 node previews/refresh.mjs
```

Each run attempts every missing title from the current Home snapshots, one at a
time. It fetches a limited range of a catalog torrent, encodes a muted 10-second
clip, and releases the torrent before moving on. Unavailable titles are retried
on the next run. An overlapping cron invocation skips starting a second worker.
Each clip is capped at 2 MiB. The worker prunes clips outside the active Home
snapshots on the next run.

### Playback diagnostics

The streaming API, preview API and refresh job write schema-versioned JSON
events to stdout. Request events use normalized route names and millisecond
durations. Session events carry an opaque `playback_id`, returned to clients as
`diagnostic_id` in the session-create response. The ID is for log correlation
and grants no access to media. Use `request_id` to follow a request across
workers and `playback_id` to follow related requests on the owning worker.
The preview refresh events share a `run_id`.

`MIRROR_LOG_SAMPLE_RATE` controls routine preview lookups and fast media reads
(default `0.05`, range `0`–`1`). The first media read, slow media responses,
capacity errors and upstream failures are kept. Successful health probes are
omitted. Use `0` on constrained hosts to keep only the unsampled events.

For nginx, include `nginx-diagnostics.conf` in the HTTP context and set
`access_log /var/log/nginx/mirror-diagnostics.log mirror_diagnostics if=$mirror_log_request;`
in each Mirror HTTPS server in place of its general-purpose access log.
Add `proxy_set_header X-Request-ID $request_id;` to each public-facing proxy
location. If one ingress proxies internally to another edge, preserve the
generated ID on a listener reachable only by the trusted ingress. Enable
`MIRROR_TRUST_EDGE_REQUEST_ID=true` only on APIs reachable exclusively through
that trusted ingress or private peers. Otherwise the APIs generate their own
request IDs. Before collecting ingress logs, verify that local access and error
logs containing unfiltered request paths are excluded from collection.

#### OCI Logging pilot

The Hyderabad pilot publishes to `mirror-streaming-production` /
`mirror-playback-diagnostics` in OCI Logging with 30-day retention. The
pilot worker's `mirror-log-collector.timer` runs once a minute. It uses the
existing preview image for the OCI SDK and the worker's instance principal
with push-only permission scoped to the dedicated log group. Its uploader
accepts only structured Mirror events and allowlisted fields. The cursor
advances after a successful upload. The collector reads at most 600 recent
lines per source and caps recovery backlog at 30 minutes to bound VM work.

In OCI Logging Search, select the Mirror log and append
`| where data.playback_id = '<ID from Copy Playback Diagnostics>'` for the
session. Use `data.request_id` to locate ingress and worker records for one
request. The saved searches are `mirror-playback-timeline`,
`mirror-playback-failures`, `mirror-preview-refreshes`, and
`mirror-collector-health`.

Check `systemctl list-timers mirror-log-collector.timer` and
`journalctl -u mirror-log-collector.service` on the pilot VM if checkpoints
stop arriving. To pause collection, disable the timer and stop its service.
To revert the pilot ingress format, restore `/etc/mirror-edge/tls.conf.before-diagnostics`,
remove `/etc/mirror-edge/00-mirror-diagnostics.conf`, and validate the nginx
configuration before reloading.
