import {execFile} from 'node:child_process'
import {once} from 'node:events'
import {createServer} from 'node:http'
import {promisify} from 'node:util'
import WebTorrent from 'webtorrent'
import {byteRange, PieceCache} from '../cache.mjs'
import {serveVideo} from '../media.mjs'

export const runFile = promisify(execFile)
const maxDownload = 64 * 1024 * 1024

export async function movieHash(id, previousFailures = 0) {
  const url = new URL('https://movies-api.accel.li/api/v2/movie_details.json')
  url.searchParams.set('movie_id', id)
  const response = await fetch(url, {signal: AbortSignal.timeout(15_000)})
  if (!response.ok) throw new Error(`Catalog HTTP ${response.status}`)
  const movie = (await response.json()).data?.movie
  if (movie?.id !== id || !Array.isArray(movie.torrents)) throw new Error('Movie unavailable')
  const sources = movie.torrents.filter(source => {
    const repacked = /^(1|true)$/i.test(String(source.is_repack))
    return /^[a-f0-9]{40}$/i.test(source.hash) && !repacked && Number(source.seeds) > 0
  })
  sources.sort((a, b) => Number(b.seeds) - Number(a.seeds))
  if (!sources.length) throw new Error('No seeded catalog source')
  return sources[previousFailures % sources.length].hash.toLowerCase()
}

export async function encodeClip(input, output, {signal} = {}) {
  await runFile('ffmpeg', [
    '-nostdin', '-loglevel', 'error', '-y',
    '-threads', '1', '-format_whitelist', 'mov,matroska', '-ss', '60', '-i', input,
    '-t', '10', '-map', '0:V:0', '-an', '-sn', '-dn', '-map_metadata', '-1', '-map_chapters', '-1',
    '-vf', 'scale=640:-2', '-filter_threads', '1', '-r', '24',
    '-c:v', 'libx264', '-threads', '1', '-preset', 'veryfast',
    '-pix_fmt', 'yuv420p', '-crf', '25', '-maxrate', '900k', '-bufsize', '900k',
    '-movflags', '+faststart', output,
  ], {signal, timeout: 90_000})
  const {stdout} = await runFile('ffprobe', [
    '-v', 'error', '-show_entries', 'format=duration,size:stream=codec_type,codec_name',
    '-of', 'json', output,
  ], {signal, timeout: 5000})
  const {format, streams} = JSON.parse(stdout)
  const duration = Number(format?.duration)
  const size = Number(format?.size)
  if (!(duration >= 9.9 && duration <= 10.1 && size > 0 && size <= 2 * 1024 * 1024) ||
      streams?.length !== 1 || streams[0].codec_type !== 'video' || streams[0].codec_name !== 'h264') {
    throw new Error('Generated clip did not meet the duration, size, or video format requirements')
  }
}

export async function makeTorrentClip(magnet, output) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), 90_000)
  const client = new WebTorrent({
    utp: false, webSeeds: false, maxConns: 12,
    downloadLimit: 1024 * 1024, uploadLimit: 16 * 1024,
  })
  client.on('error', () => controller.abort())
  let server, watchdog
  try {
    const torrent = client.add(magnet, {
      deselect: true, store: PieceCache, storeOpts: {maxBytes: maxDownload},
      storeCacheSlots: 0,
    })
    torrent.on('error', () => controller.abort())
    await once(torrent, 'ready', {signal: controller.signal})
    const file = torrent.files.filter(file => /\.(mp4|mkv)$/i.test(file.name))
      .sort((a, b) => b.length - a.length)[0]
    if (!file) throw new Error('Torrent has no compatible video')
    const session = {file, active: 0}
    const cache = torrent.store.store ?? torrent.store
    cache.onEvict = index => { if (!torrent.destroyed) torrent._markUnverified(index) }
    watchdog = setInterval(() => {
      if (torrent.downloaded > maxDownload) controller.abort()
    }, 250)
    server = createServer((req, res) => {
      let range
      try {
        range = byteRange(req.headers.range, file.length)
      } catch {
        res.writeHead(416, {'Content-Range': `bytes */${file.length}`})
        return res.end()
      }
      void serveVideo(req, res, session, range)
    }).listen(0, '127.0.0.1')
    await once(server, 'listening', {signal: controller.signal})
    await encodeClip(`http://127.0.0.1:${server.address().port}/movie`, output, {signal: controller.signal})
  } finally {
    clearTimeout(timer)
    clearInterval(watchdog)
    server?.close()
    server?.closeAllConnections()
    await new Promise(resolve => client.destroy(() => resolve()))
  }
}
