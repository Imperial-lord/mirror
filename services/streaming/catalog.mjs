import {load} from 'cheerio'

const cache = new Map(), titles = new Map(), pending = new Map()
const YEAR_MAX = new Date().getFullYear() + 1
export function catalogParameters(params) {
  const year = Number(params.get('year')), page = Number(params.get('page') ?? 1)
  const rating = Number(params.get('minimum_rating') ?? 0)
  const sort = params.get('sort_by') ?? 'like_count'
  const query = params.get('query_term')?.trim() ?? ''
  const genre = params.get('genre')?.toLowerCase() ?? 'all'
  if (!Number.isInteger(year) || year < 1888 || year > YEAR_MAX || !Number.isInteger(page) || page < 1 || page > 10000 ||
      !Number.isInteger(rating) || rating < 0 || rating > 9 || !['like_count','date_added','rating'].includes(sort) ||
      query.length > 200 || !/^[a-z-]{1,30}$/.test(genre)) throw new Error('Invalid catalog filters')
  return {year,page,rating,sort,query,genre}
}
export function parseBrowse(html, filters) {
  const $ = load(html)
  const entries = $('.browse-movie-wrap').map((_, element) => {
    const title = $(element).find('.browse-movie-title').clone(); title.find('span').remove()
    const url = new URL($(element).find('.browse-movie-link').attr('href'), 'https://yts.gg')
    const year = Number($(element).find('.browse-movie-year').text().trim())
    if (url.origin !== 'https://yts.gg' || !url.pathname.startsWith('/movies/') || year !== filters.year) throw new Error('Unexpected catalog result')
    return {title:title.text().trim(), path:url.pathname, year}
  }).get()
  // A block/challenge or changed page structure must not masquerade as no results.
  if (!entries.length && !/no movies found/i.test($.text())) throw new Error('Catalog provider unavailable')
  const hasMore = $('a').toArray().some(a => {
    const href = $(a).attr('href')
    if (!href) return false
    try { return Number(new URL(href, 'https://yts.gg').searchParams.get('page')) > filters.page } catch { return false }
  })
  return {entries,hasMore}
}
async function get(url, json = false) {
  const response = await fetch(url, {signal:AbortSignal.timeout(20000), redirect:'error', headers:{'User-Agent':'MirrorMovieApp/1.0'}})
  if (!response.ok) throw new Error(`Catalog provider HTTP ${response.status}`)
  const text = await response.text()
  if (Buffer.byteLength(text) > 4*1024*1024) throw new Error('Catalog response too large')
  return json ? JSON.parse(text) : text
}
function remember(map, key, value, max) {
  if (map.size >= max) map.delete(map.keys().next().value)
  map.set(key, {value, expires:Date.now()+3600000})
}
async function resolveMovie(entry) {
  const cached = titles.get(entry.path)
  if (cached?.expires > Date.now()) return cached.value
  const url = new URL('https://movies-api.accel.li/api/v2/list_movies.json')
  url.search = new URLSearchParams({query_term:entry.title,limit:'50'})
  const response = await get(url,true)
  if (response.status !== 'ok') throw new Error('Catalog lookup failed')
  let movie = response.data?.movies?.find(m => new URL(m.url).pathname === entry.path && m.year === entry.year)
  if (!movie) {
    // Generic titles can fall outside the API's first 50 search hits. Resolve the
    // site's actual catalog ID instead of omitting a matching movie.
    const $ = load(await get('https://yts.gg'+entry.path))
    const id = $('#movie-info').attr('data-movie-id')
    if (!/^\d+$/.test(id ?? '')) throw new Error('Movie ID unavailable')
    const detail = await get(`https://movies-api.accel.li/api/v2/movie_details.json?movie_id=${id}&with_images=false&with_cast=false`,true)
    movie = detail.data?.movie
    if (detail.status !== 'ok' || !movie || movie.year !== entry.year || new URL(movie.url).pathname !== entry.path) throw new Error('Movie lookup mismatch')
  }
  remember(titles, entry.path, movie, 512)
  return movie
}
export async function yearCatalog(filters) {
  const key = JSON.stringify(filters), cached = cache.get(key)
  if (cached?.expires > Date.now()) return cached.value
  if (pending.has(key)) return pending.get(key)
  if (pending.size >= 4) throw new Error('Catalog busy')
  const task = (async () => {
    const sort = {like_count:'likes',date_added:'latest',rating:'rating'}[filters.sort]
    const term = encodeURIComponent(filters.query || '0')
    const url = new URL(`https://yts.gg/browse-movies/${term}/all/${filters.genre}/${filters.rating}/${sort}/${filters.year}/all`)
    if (filters.page > 1) url.searchParams.set('page',filters.page)
    const {entries,hasMore} = parseBrowse(await get(url), filters)
    const movies = new Array(entries.length)
    let cursor = 0
    await Promise.all(Array.from({length:Math.min(4,entries.length)},async () => {
      while (cursor < entries.length) {
        const index = cursor++
        movies[index] = await resolveMovie(entries[index])
      }
    }))
    const result = {movies,hasMore}
    remember(cache,key,result,64)
    return result
  })()
  pending.set(key,task)
  try { return await task } finally { pending.delete(key) }
}
