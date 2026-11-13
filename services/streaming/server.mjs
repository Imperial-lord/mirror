import {existsSync} from 'node:fs'
import {loadEnvFile} from 'node:process'
import {fileURLToPath} from 'node:url'
import http from 'node:http'
import {randomUUID} from 'node:crypto'
import WebTorrent from 'webtorrent'
import {subtitles} from './subtitles.mjs'
import {catalogParameters, yearCatalog} from './catalog.mjs'
import {movieCredits} from './credits.mjs'
import {PieceCache, byteRange} from './cache.mjs'
import {serveVideo} from './media.mjs'
import {initializeApp, applicationDefault} from 'firebase-admin/app'
import {getAuth} from 'firebase-admin/auth'
const envFile = fileURLToPath(new URL('.env', import.meta.url))
if (existsSync(envFile)) loadEnvFile(envFile)
const host = process.env.HOST ?? '127.0.0.1'
const project = process.env.FIREBASE_PROJECT_ID
if (host !== '127.0.0.1' && !project) throw new Error('Public hosting requires FIREBASE_PROJECT_ID and Firebase credentials')
if (project) initializeApp({credential: applicationDefault(), projectId: project})
const sessions = new Map()
const MAX_SESSIONS = 4, TTL = 10 * 60_000
const json = (res, status, body) => { res.writeHead(status, {'Content-Type':'application/json'}); res.end(JSON.stringify(body)) }
function dispose(id) { const s = sessions.get(id); if (!s) return; sessions.delete(id); s.client.destroy(() => {}) }
async function authenticated(req) {
  if (!project) return
  const token = req.headers.authorization?.replace(/^Bearer /, '')
  if (!token) throw new Error('Unauthorized')
  await getAuth().verifyIdToken(token)
}
const server = http.createServer(async (req, res) => {
  try {
    const path = new URL(req.url, 'http://localhost').pathname
    if (path === '/health' && req.method === 'GET') return json(res, 200, {ok:true})
    const creditsRequest = /^\/v1\/credits\/(tt\d{5,12})$/.exec(path)
    if (creditsRequest && req.method === 'GET') {
      try { await authenticated(req) } catch { return json(res,401,{error:'Unauthorized'}) }
      try {
        const result = await movieCredits(creditsRequest[1])
        return json(res, result ? 200 : 503, result ?? {error:'Movie metadata unavailable'})
      } catch { return json(res,502,{error:'Movie metadata unavailable'}) }
    }
    if (path === '/v1/catalog' && req.method === 'GET') {
      try { await authenticated(req) } catch { return json(res,401,{error:'Unauthorized'}) }
      let filters
      try { filters = catalogParameters(new URL(req.url,'http://localhost').searchParams) }
      catch { return json(res,400,{error:'Invalid catalog filters'}) }
      try { return json(res,200,await yearCatalog(filters)) }
      catch (error) { console.warn('Year catalog failed:',error.message); return json(res,502,{error:'Catalog unavailable'}) }
    }
    const subtitleRequest = /^\/v1\/subtitles\/(tt\d{5,12})\/(en|it|es|fr)$/.exec(path)
    if (subtitleRequest && req.method === 'GET') {
      try { await authenticated(req) } catch { return json(res, 401, {error:'Unauthorized'}) }
      try {
        const result = await subtitles(subtitleRequest[1], subtitleRequest[2])
        return json(res, result ? 200 : 404, result ?? {error:'Subtitles unavailable'})
      } catch { return json(res, 502, {error:'Subtitles unavailable'}) }
    }
    if (path === '/v1/sessions' && req.method === 'POST') {
      try { await authenticated(req) } catch { return json(res, 401, {error:'Unauthorized'}) }
      if (sessions.size >= MAX_SESSIONS) return json(res, 503, {error:'Playback capacity reached'})
      let body = ''; for await (const chunk of req) { body += chunk; if (body.length > 2048) return json(res, 413, {error:'Request too large'}) }
      let hash; try { hash = JSON.parse(body).hash } catch { return json(res, 400, {error:'Invalid request'}) }
      if (!/^[a-f0-9]{40}$/i.test(hash ?? '')) return json(res, 400, {error:'Invalid movie hash'})
      if (sessions.size >= MAX_SESSIONS) return json(res, 503, {error:'Playback capacity reached'})
      const id = randomUUID(), client = new WebTorrent({utp:false, webSeeds:false})
      const session = {client, touched:Date.now(), active:0}; sessions.set(id, session)
      const disconnected = () => dispose(id)
      res.on('close', () => { if (!res.writableEnded) disconnected() })
      const timer = setTimeout(() => { if (!res.headersSent) json(res, 504, {error:'Movie unavailable'}); dispose(id) }, 45_000)
      client.on('error', () => { clearTimeout(timer); if (!res.headersSent) json(res, 502, {error:'Movie unavailable'}); dispose(id) })
      const magnet = `magnet:?xt=urn:btih:${hash}&tr=${encodeURIComponent('udp://tracker.opentrackr.org:1337/announce')}&tr=${encodeURIComponent('udp://open.demonii.com:1337/announce')}`
      const torrent = client.add(magnet, {store:PieceCache, storeOpts:{maxBytes:128*1024*1024}, storeCacheSlots:0, deselect:true}, () => {
        clearTimeout(timer)
        if (!sessions.has(id)) return
        const file = torrent.files.filter(f => /\.mp4$/i.test(f.name)).sort((a,b) => b.length-a.length)[0]
        if (!file) { json(res, 422, {error:'No compatible MP4 available'}); return dispose(id) }
        // Pinned WebTorrent adapter: evicted chunks must be downloaded again on future seeks.
        const store = torrent.store
        const raw = store.store ?? store
        raw.onEvict = index => torrent._markUnverified(index)
        Object.assign(session, {torrent, file})
        json(res, 201, {id, path:`/v1/sessions/${id}/video.mp4`})
      })
      torrent.on('error', () => { clearTimeout(timer); if (!res.headersSent) json(res, 502, {error:'Movie unavailable'}); dispose(id) })
      return
    }
    const match = /^\/v1\/sessions\/([a-f0-9-]{36})(\/video\.mp4)?$/.exec(path)
    const s = match && sessions.get(match[1])
    if (!s) return json(res, 404, {error:'Playback session expired'})
    s.touched = Date.now()
    if (req.method === 'DELETE' && !match[2]) { dispose(match[1]); res.writeHead(204); return res.end() }
    if (!match[2] || !['GET','HEAD'].includes(req.method) || !s.file) return json(res, 405, {error:'Method unavailable'})
    let range
    try { range = byteRange(req.headers.range, s.file.length) } catch { res.writeHead(416, {'Content-Range':`bytes */${s.file.length}`}); return res.end() }
    await serveVideo(req, res, s, range)
  } catch { if (!res.headersSent) json(res, 500, {error:'Playback unavailable'}); else res.destroy() }
})
const sweep = setInterval(() => { for (const [id,s] of sessions) if (!s.active && Date.now()-s.touched > TTL) dispose(id) }, 30_000)
server.listen(Number(process.env.PORT ?? 8787), host, () => console.log(`Playback service on ${host}:${server.address().port}`))
function shutdown() { clearInterval(sweep); for (const id of sessions.keys()) dispose(id); server.close() }
process.on('SIGTERM', shutdown); process.on('SIGINT', shutdown)
