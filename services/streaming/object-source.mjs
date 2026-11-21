import {Readable} from 'node:stream'

export function objectSources(raw = '{}') {
  const entries = new Map()
  for (const [hash, value] of Object.entries(JSON.parse(raw))) {
    const url = new URL(value)
    if (!/^[a-f0-9]{40}$/.test(hash) ||
      !/^https:\/\/objectstorage\.[a-z0-9-]+\.oraclecloud\.com$/.test(url.origin) ||
      !url.href.startsWith(`${url.origin}/p/`) ||
      !/^\/p\/[^/]+\/n\/[^/]+\/b\/[^/]+\/o\/.+/.test(url.pathname)) {
      throw new Error('Invalid Mirror Object Storage mapping')
    }
    entries.set(hash, url)
  }
  return entries
}

async function rangeResponse(url, start, end, signal) {
  const response = await fetch(url, {
    headers: {Range: `bytes=${start}-${end}`}, redirect: 'error', signal
  })
  const match = /^bytes (\d+)-(\d+)\/(\d+)$/.exec(response.headers.get('content-range') ?? '')
  const length = Number(match?.[3])
  if (response.status !== 206 || !response.body || !Number.isSafeInteger(length) ||
    length <= end || Number(match?.[1]) !== start || Number(match?.[2]) !== end) {
    await response.body?.cancel()
    throw new Error('Object Storage returned an invalid range')
  }
  return {response, length}
}

export async function openObject(url) {
  const {response, length} = await rangeResponse(url, 0, 0, AbortSignal.timeout(3000))
  await response.body.cancel()
  const etag = response.headers.get('etag')
  return {
    length,
    createReadStream({start, end}) {
      const controller = new AbortController()
      const stream = Readable.from((async function * () {
        const result = await rangeResponse(url, start, end,
          AbortSignal.any([controller.signal, AbortSignal.timeout(45_000)]))
        if (result.length !== length || (etag && result.response.headers.get('etag') !== etag)) {
          await result.response.body.cancel()
          throw new Error('Object changed during playback')
        }
        let remaining = end - start + 1
        for await (const chunk of result.response.body) {
          remaining -= chunk.length
          if (remaining < 0) throw new Error('Object range exceeded expected length')
          yield chunk
        }
        if (remaining !== 0) throw new Error('Object range was truncated')
      })(), {objectMode: false})
      stream.once('close', () => controller.abort())
      return stream
    }
  }
}
