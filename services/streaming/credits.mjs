export function parseOMDbCredits(movie, imdb) {
  if (movie.Response !== 'True' || movie.imdbID !== imdb) throw new Error('Movie metadata unavailable')
  const credits = []
  for (const [field, department] of [['Actors', 'Actor'], ['Director', 'Director'], ['Writer', 'Writer']]) {
    if (typeof movie[field] !== 'string' || movie[field] === 'N/A') continue
    for (const name of movie[field].split(',').map(value => value.trim()).filter(Boolean)) {
      if (!credits.some(person => person.name === name && person.department === department)) {
        credits.push({name, department})
      }
    }
  }
  return {imdb, credits}
}

export function createMovieCredits({
  fetchImpl = fetch,
  now = Date.now,
  apiKey = () => process.env.OMDB_API_KEY,
  dailyLimit = 900
} = {}) {
  const cache = new Map()
  const pending = new Map()
  const day = 24 * 60 * 60 * 1000
  let requests = []
  let retryAt = 0

  function remember(imdb, value, ttl) {
    if (cache.size >= 256) cache.delete(cache.keys().next().value)
    cache.set(imdb, {value, expires: now() + ttl})
    return value
  }

  return async function movieCredits(imdb) {
    if (!/^tt\d{5,12}$/.test(imdb)) throw new Error('Invalid movie ID')
    const cached = cache.get(imdb)
    if (cached?.expires > now()) return cached.value
    if (pending.has(imdb)) return pending.get(imdb)
    const key = apiKey()
    if (!key || now() < retryAt) return null
    requests = requests.filter(time => time > now() - day)
    if (requests.length >= dailyLimit || pending.size >= 4) return null

    // Reserve quota before awaiting network work, including failed requests.
    requests.push(now())
    const task = (async () => {
      try {
        const url = new URL('https://www.omdbapi.com/')
        url.search = new URLSearchParams({apikey: key, i: imdb, plot: 'short'})
        const response = await fetchImpl(url, {signal: AbortSignal.timeout(15000), redirect: 'error'})
        if (response.status === 429) {
          retryAt = now() + day
          return null
        }
        if (!response.ok) throw new Error('Metadata provider unavailable')
        const text = await response.text()
        if (Buffer.byteLength(text) > 256 * 1024) throw new Error('Metadata response too large')
        const movie = JSON.parse(text)
        if (movie.Response === 'False') {
          const message = typeof movie.Error === 'string' ? movie.Error : ''
          if (/limit|quota/i.test(message)) retryAt = now() + day
          else if (/api key|unauthorized/i.test(message)) retryAt = now() + 60 * 60 * 1000
          else return remember(imdb, null, 60 * 60 * 1000)
          return null
        }
        return remember(imdb, parseOMDbCredits(movie, imdb), 7 * day)
      } catch {
        // Briefly stop provider calls while the app uses its fallback.
        retryAt = Math.max(retryAt, now() + 60 * 1000)
        return null
      }
    })()
    pending.set(imdb, task)
    try { return await task } finally { pending.delete(imdb) }
  }
}

export const movieCredits = createMovieCredits()
