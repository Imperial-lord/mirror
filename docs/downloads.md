# Device downloads

Downloads are device-local and scoped to the authenticated Firebase UID. Files and
an atomic JSON manifest live under Application Support/OfflineMovies/<account hash>.
The directory is excluded from iCloud backup and uses protection allowing background
transfers after the first device unlock. No downloaded-file list is mirrored to
Firestore: another device must not claim it owns files that exist only here.

The manifest retains the full movie metadata, selected torrent/quality, committed
byte count, actual total size, job generation, queued/preparing/downloading/paused/
failed/completed state, error message, downloaded subtitle files, selected subtitle
requests, local poster, and watch position/duration. Loading a downloaded movie never
needs a catalog or streaming-service request. Watch progress still uses the existing
local history and Firestore synchronization; Firestore queues offline progress writes.

## Transfer and recovery

DownloadStore opens the existing authenticated playback session and obtains its MP4
length using HEAD. iOS background URLSession downloads one 16 MiB HTTP byte range at
a time, one movie at a time. Each response must match the exact Content-Range, total,
and file length before being appended to a partial file. Appends use a 64 KiB copy
buffer. The streaming server retains its existing bounded piece cache/read windows;
it does not save the entire movie on disk.

Committed chunks survive pause, failure, app restart, and expired streaming sessions.
Pause discards the unfinished chunk. Retry opens a fresh playback session and resumes
at the committed offset. A restored background request can continue its existing
session; an expired session is renewed, with a bounded retry count. Generation IDs
reject late callbacks from cancelled/replaced jobs. Startup reattaches existing iOS
transfers before scheduling new work. iOS controls background scheduling; explicitly
force-quitting an app can stop its transfers until it is reopened.

Video quality choices and estimated sizes come from the actual available torrents.
Only one completed video asset is retained per movie. A quality replacement preserves
the old playable asset until the replacement succeeds, then removes it. Changing
quality preserves captions and watch progress. Requesting more captions for an existing
quality does not download the video again. Missing local movie files can be downloaded
again; their metadata alone is never treated as a playable asset. Free storage is
checked before the transfer, with write failures surfaced for retry.

The Wi-Fi-only switch in Settings is currently a visual placeholder; it does not restrict transfers.
Downloads provides pause/resume/retry, download settings, delete, real progress and
sizes, and local playback. Settings shows actual storage use and confirms deleting all
downloads. Deleting downloads keeps watch history and Favorites.

## Captions and playback

The download sheet asks for quality and any of English, Italian, Spanish, and French
subtitles (or none). Captions are saved as UTF-8 SRT. English fallback is labelled as
English, and unavailable downloads are reported instead of creating fake language
choices. Adding a language retains previously saved languages.

The existing fullscreen landscape player accepts an OfflineMovie source. It reads the
MP4 and captions directly from local URLs, resumes using the latest local history,
and retains seeking, speed, controls, and watch-progress behavior. Settings offers only
the saved video quality and saved subtitle languages plus Off. Audio is a fixed tile
with no action or chevron for both streamed and downloaded movies.

## Verification

OfflineDownloadTests uses a local HTTP fixture and a generated H.264 MP4. It tests exact
range validation, crash-safe append recovery, a failed second chunk followed by resume,
subtitle accumulation without a second video transfer, quality replacement, durable
manifest restoration, account isolation, missing-file recovery, and stale cancellation
callbacks. With the fixture origin shut down, AVPlayer loads and seeks the saved video
and subtitle cues are parsed entirely from saved files.

Live Simulator verification also completed The Day of the Doctor at 720p (770,542,817
bytes) with English captions using the OCI service. Its transfer continued in the
background and was paused/resumed at the committed 78% checkpoint. The completed
movie resumed around 15 minutes from local history, played with captions, and sought
forward successfully. Offline Settings offered HD 720 only and Off/English captions,
with fixed Audio. The Downloads row showed Continue watching after player dismissal.

The OCI service includes the media-slot cleanup fix in `media.mjs`: disconnecting a
client releases its slot immediately even if its upstream iterator stalls. Capacity
returns HTTP 503. The previous container was retained stopped for rollback.
