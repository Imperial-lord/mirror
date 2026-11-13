# Home and movie details

Home uses five YTS requests: popular hero posters (`like_count`, 5), popular movies (`like_count`, 15), latest additions (`date_added`, 15), top rated (`rating`, minimum 8), and thrillers (`genre=Thriller`, `rating`). “Selected For You” currently uses latest additions, not a personalized recommendation service.

Continue Watching displays only real, unfinished local playback history. Remaining time comes from runtime minus watched seconds. Empty history does not generate sample cards. YTS is a catalog API, not a viewing-history service.

Decoded response data is cached in memory for one hour, keyed by the full request URL. Expired entries are removed, and the cache is capped at 128 responses. Cache misses bypass URLSession's HTTP cache so server headers cannot extend the explicit TTL. Pull-to-refresh clears response and HTTP caches. Poster caching remains managed by Nuke.

Movie cards render as content inside NavigationLink, avoiding nested buttons that intercept taps. Hero and Continue Watching cards use explicit detail-navigation actions. Movie details show the API rating without fabricated offsets; trailers use the returned YouTube code. Series/episode placeholders and fabricated review quotes/counts are not displayed for YTS movies.

Visual reference: https://www.behance.net/gallery/211500071/Online-Cinema-App-Mirror — Home and movie-detail boards. The supported movie-only sections use the reference's full-width poster, dark gradients, white text/actions, horizontal poster/landscape rows, and floating bottom controls.

Focused regression tests: `HomeDataTests` verifies query-to-section mapping and failure state. Auth integration tests require local Firebase emulators and can be run separately.

Continue Watching merges the signed-in user's Firestore `continue_watching` records
into local history on Home entry, refresh, and player dismissal. Cloud timestamps
prevent stale records overwriting newer local progress. Tapping artwork or its title
opens the fullscreen player directly; Movie information remains in the More menu.
The player reads the movie's Firestore position before opening playback, uses the
card's local position if the cloud read fails, seeks before starting AVPlayer, and
saves progress on exit as well as periodically during playback.

The catalog filter page follows Behance board 13 (reference captured in
`design/behance-catalog-filters.png`). Country, Studio and Year are interactive
alongside Genre, minimum IMDb Rating, and Newest/Popular/Rating sorting. Edits
remain local until Apply; Reset clears every draft value, and closing without
applying preserves the current selection.

YTS handles genre, minimum rating and sort order. Production metadata is fetched
from Wikidata by IMDb ID using P495 (country of origin) and P272 (production
company); country is never inferred from language. The curated picker identifiers
were checked against live Wikidata labels. The metadata cache persists in the app
Caches directory for seven days, bounded to 10,000 titles. Wikidata coverage is
incomplete: movies without the selected production metadata are excluded. Provider
failures show a retryable error and never masquerade as an empty catalog.

Year uses YTS.GG's real year-filtered browse route through the existing server's
GET `/v1/catalog?year=...` endpoint (same Firebase authentication as playback).
The server parses the site's movie links and pagination, resolves the actual YTS
API movie records, and caches 64 filtered pages and 512 resolved titles for one
hour. It validates returned release years and rejects provider challenges or
changed HTML as errors. It preserves Newest/Popular/Rating ordering and avoids
scanning unrelated years. It never silently drops unresolved movie records.
Year also checks the YTS `year` field exactly as a defensive predicate. Local predicates are combined with AND
and applied while advancing the upstream YTS page cursor. Each load stops at the first matching page, or examines at
most six pages when no matches are found, to bound work. Matching cards retain YTS ordering. A short or empty
filtered batch does not terminate pagination; an empty batch offers Search more
movies until the upstream catalog is exhausted. Uncommon production filters may require additional loads. Active Country,
Studio and Year selections appear as removable catalog chips. Filtered catalogs
use an explicit Load more action so sparse results do not trigger long automatic
background scans. There is no full-catalog download. Tests
cover combined filters, matches after empty pages, provider errors and retry.

Sources: [YTS API](https://yts.proxyninja.org/api),
[Wikidata Query Service](https://www.wikidata.org/wiki/Wikidata:SPARQL_query_service).
Wikidata structured data is CC0.

## Watch history and Library Recent

Recent no longer uses catalog/sample movies. Home and Library read the same
account-scoped SwiftData history and merge all saved Firestore `continue_watching`
records (including completed titles). New progress records include exact
`durationSeconds`, `year`, `genres`, poster/backdrop URLs and `watched` alongside
position and updatedAt. `watched` is true only when position/duration is strictly
greater than 0.95; exactly 95% remains Continue Watching. Unknown durations do not
qualify as watched. Exact duration takes precedence over legacy runtime minutes.

Local records now carry userId and permit the same movie for different accounts.
Legacy unscoped rows are adopted only if the signed-in account has the matching
cloud record. Older cloud rows are enriched via YTS movie details, with up to four
concurrent lookups, without changing their playback position or last-watch time.
The existing account-level cloud path is retained. Metadata and completed history
remain stored after a movie leaves Continue Watching. Library cards resume
playback directly and headers open their collections. Library genres are derived
only from completed (>95%) titles, independently of recommendation genre weights.
Selecting a genre filters the signed-in account's watched history; it never opens
the general genre catalog. Genre tiles show counts and open a two-column watched
poster grid. Continue Watching collections use full-width landscape cards. The
Behance Library reference is saved in `design/behance-library.jpg`; its chevrons
support collection navigation, but the reference does not explicitly mock these
history detail pages. Those pages reuse the reference's two-column collection
layout and consistent Phosphor back controls. Empty history has honest empty states.
Favorites are covered below; Downloads remain unchanged.

## Selected For You and Best genre rows

Selected For You combines suggestions from the three most recent history titles
with highly rated movies from the three strongest history genres. Genre scores
weight progress and recency; already-started/completed titles are excluded and
candidates deduplicated. With no history, new releases/popular/top-rated movies
provide a real-catalog fallback. Suggestions and genre requests use APIClient's
existing one-hour response cache. Returning from playback refreshes history and
recommendations.

Filter genres share `Genre.catalogGenres` with the Best collections. Best Thrillers
is followed by a Best row for every other filter genre, including Horror and
Comedy. These rows load as they approach the viewport, sort by rating, and have
independent retry handling. Popular Now and Top rated retain their existing
queries. Unit tests cover strict completion boundaries, legacy duration fallback,
account-separated persistence, recommendation exclusions/deduplication, history
seed queries, and all genre collections.

## Favorites and playlists

`LibraryStore` observes the authenticated account's `users/{uid}/favorites` and
`playlists` collections in real time. Both Library and the movie's Add to Library
sheet use the same store. Old favorites (`genre`) and playlist documents remain
readable; new favorites retain all `genres` and poster metadata. No catalog rows
are substituted for missing saved data, and failed reads/writes are visible.

The existing Must-Watch, Recommendation, and For traveling folder suggestions are
created once per account in a Firestore transaction, with real empty membership.
The parent user document records `libraryDefaultsInitialized`, so deleting a folder
does not recreate it. New folders use stable Firestore document IDs, may share names,
and can be renamed or deleted without deleting their movies from Favorites.

Favorites is the superset of saved movies. Deselecting it clears folder selections;
selecting any custom folder selects Favorites. Saving commits the favorite and
folder membership changes in one batch. Removing from Favorites removes the movie
from all custom folders; removing from one folder keeps Favorites and other folders.
The movie detail tick comes from this store, not the old unscoped UserDefaults flag.

Favorites opens its complete two-column grid from the section header. Custom folders
show their actual saved titles and counts, support Select/Remove and per-movie context
menus, and allow choosing movies from Favorites using Add movies. Creating folders is
also available while saving a movie. Account changes clear the store and restart the
listeners to prevent cross-account library display. Downloads remain unchanged.
