const genres = [
  'Action', 'Adventure', 'Animation', 'Comedy', 'Crime', 'Documentary', 'Drama', 'Family',
  'Fantasy', 'History', 'Music', 'Horror', 'Mystery', 'Romance', 'Sci-Fi', 'Thriller', 'War', 'Western',
]
const rows = [
  ['popular-now', {sort_by: 'like_count'}],
  ['top-rated', {sort_by: 'rating', minimum_rating: '8'}],
  ...genres.map(genre => [`genre-${genre.toLowerCase()}`, {sort_by: 'rating', genre}]),
]

async function catalogRow(query, fetcher) {
  const url = new URL('https://movies-api.accel.li/api/v2/list_movies.json')
  url.search = new URLSearchParams({limit: '15', page: '1', order_by: 'desc', ...query})
  const response = await fetcher(url, {signal: AbortSignal.timeout(15000)})
  if (!response.ok) throw new Error(`Catalog HTTP ${response.status}`)
  const payload = await response.json()
  const movies = payload.data?.movies ?? (payload.data?.movie_count === 0 ? [] : null)
  if (payload.status !== 'ok' || !Array.isArray(movies) || movies.length > 15 ||
      movies.some(movie => !Number.isSafeInteger(movie?.id) || movie.id < 1)) {
    throw new Error('Invalid catalog row')
  }
  return movies.map(movie => movie.id)
}

export async function fetchHomeCatalog(fetcher = fetch) {
  const entries = []
  for (let index = 0; index < rows.length; index += 4) {
    entries.push(...await Promise.all(rows.slice(index, index + 4).map(async ([row, query]) => {
      try { return [row, await catalogRow(query, fetcher)] }
      catch {
        try { return [row, await catalogRow(query, fetcher)] }
        catch (error) { throw new Error(`${row}: ${error.message}`, {cause: error}) }
      }
    })))
  }
  return Object.fromEntries(entries)
}
