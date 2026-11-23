import {existsSync} from 'node:fs'
import {loadEnvFile} from 'node:process'
import {fileURLToPath} from 'node:url'
import http from 'node:http'
import {randomUUID} from 'node:crypto'
import {performance} from 'node:perf_hooks'
import WebTorrent from 'webtorrent'
import {subtitles} from './subtitles.mjs'
import {catalogParameters, yearCatalog} from './catalog.mjs'
import {createAISearch, SearchFailure} from './ai-search.mjs'
import {movieCredits} from './credits.mjs'
import {PieceCache, byteRange} from './cache.mjs'
import {serveVideo} from './media.mjs'
import {diskPieceStore} from './disk-cache.mjs'
import {clusterRouting} from './cluster.mjs'
import {objectSources, openObject} from './object-source.mjs'
import {initializeApp, applicationDefault} from 'firebase-admin/app'
import {getAuth} from 'firebase-admin/auth'
import {diagnostics, elapsed, observeRequest, routeName} from './diagnostics.mjs'
const envFile = fileURLToPath(new URL('.env', import.meta.url))
if (existsSync(envFile)) loadEnvFile(envFile)
const host = process.env.HOST ?? '127.0.0.1'
const project = process.env.FIREBASE_PROJECT_ID
if (host !== '127.0.0.1' && !project) throw new Error('Public hosting requires FIREBASE_PROJECT_ID and Firebase credentials')
if (project) initializeApp({credential: applicationDefault(), projectId: project})
const aiSearch = createAISearch()
const sessions = new Map()
const cluster = clusterRouting()
const log = diagnostics('streaming')
const trustEdge = process.env.MIRROR_TRUST_EDGE_REQUEST_ID === 'true'
const objects = objectSources(process.env.MIRROR_OBJECT_SOURCES)
const GiB = 1024 ** 3
const Store = process.env.MIRROR_CACHE_DIR
  ? await diskPieceStore(process.env.MIRROR_CACHE_DIR, {budget: 12 * GiB, reserve: 5 * GiB})
  : PieceCache
const MAX_SESSIONS = 4, TTL = 10 * 60_000
const json = (res, status, body) => { res.writeHead(status, {'Content-Type':'application/json'}); res.end(JSON.stringify(body)) }
function dispose(id, reason) {
  const session = sessions.get(id)
  if (!session) return
  sessions.delete(id)
  clearTimeout(session.timer)
  log.emit('session_closed', {
    request_id: session.requestID, playback_id: session.playbackID, source: session.source,
    reason, duration_ms: elapsed(session.started), reads: session.reads,
    bytes_written: session.bytesWritten, session_first_byte_ms: session.firstByteMs
  })
  session.client?.destroy(() => {})
}

async function forward(req, res, path, body, context) {
  const start = performance.now()
  let outcome = 'forwarded'
  try {
    const accepted = await cluster.forward(req, res, path, body)
    if (!accepted) outcome = 'peer_at_capacity'
    return accepted
  } catch (error) {
    outcome = res.destroyed && !res.headersSent ? 'client_closed' : 'peer_forward_failed'
    throw error
  } finally {
    context.forward_outcome = outcome
    context.forward_ms = elapsed(start)
    if (outcome === 'peer_forward_failed' || outcome === 'peer_at_capacity') {
      log.emit('peer_forward_issue', {request_id: context.request_id, route: context.route,
        outcome, duration_ms: context.forward_ms}, 'warn')
    }
  }
}
async function authenticated(req) {
  if (!project) return {uid:'local-development'}
  const token = req.headers.authorization?.replace(/^Bearer /, '')
  if (!token) throw new Error('Unauthorized')
  return getAuth().verifyIdToken(token)
}
const server = http.createServer(async (req, res) => {
  const forwarded = cluster.forwarded(req)
  const context = observeRequest(req, res, log, {trustRequestID: forwarded || trustEdge})
  if (forwarded) context.forwarded = true
  try {
    const path = new URL(req.url, 'http://localhost').pathname
    context.route = routeName(path)
    if (path === '/v1/ai/search' && req.method === 'POST') {
      let user
      try { user = await authenticated(req) } catch { return json(res,401,{error:'Sign in to use AI search.'}) }
      try {
        const chunks=[];let size=0
        for await(const chunk of req){size+=chunk.length;if(size>24000)return json(res,413,{error:'Conversation too long. Please start a new chat.'});chunks.push(chunk)}
        let input
        try{input=JSON.parse(Buffer.concat(chunks).toString())}catch{return json(res,400,{error:'Invalid search request.'})}
        const controller=new AbortController()
        const disconnected=()=>{if(!res.writableEnded)controller.abort()}
        res.on('close',disconnected)
        try{return json(res,200,await aiSearch(input,user.uid,controller.signal))}
        finally{res.off('close',disconnected)}
      }catch(error){return json(res,error instanceof SearchFailure?error.status:502,{code:error.code??'unavailable',error:error instanceof SearchFailure?error.message:'AI search is temporarily unavailable.'})}
    }
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
      catch { context.outcome = 'catalog_unavailable'; return json(res,502,{error:'Catalog unavailable'}) }
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
      let body = ''; for await (const chunk of req) { body += chunk; if (body.length > 2048) return json(res, 413, {error:'Request too large'}) }
      let hash; try { hash = JSON.parse(body).hash } catch { return json(res, 400, {error:'Invalid request'}) }
      if (!/^[a-f0-9]{40}$/i.test(hash ?? '')) return json(res, 400, {error:'Invalid movie hash'})
      hash = hash.toLowerCase()
      if (cluster.enabled && !forwarded && (cluster.prefersPeer(hash) || sessions.size >= MAX_SESSIONS)) {
        try { if (await forward(req, res, path, body, context)) return }
        catch { if (res.headersSent || res.destroyed) return }
      }
      if (sessions.size >= MAX_SESSIONS) {
        context.outcome = 'session_capacity'
        context.active_sessions = sessions.size
        res.setHeader('x-mirror-capacity', 'full')
        return json(res, 503, {error:'Playback capacity reached'})
      }
      const id = cluster.id()
      const session = {touched:Date.now(), active:0, started: performance.now(),
        playbackID: randomUUID(), requestID: context.request_id, reads:0, bytesWritten:0}
      context.playback_id = session.playbackID
      const respondReady = () => {
        context.source = session.source
        context.outcome = 'session_ready'
        context.active_sessions = sessions.size
        return json(res, 201, {id, path:`/v1/sessions/${id}/video.mp4`, diagnostic_id: session.playbackID})
      }
      sessions.set(id, session)
      const object = objects.get(hash)
      if (object) {
        try {
          session.file = await openObject(object)
          if (res.destroyed) return dispose(id, 'client_closed')
          session.source = 'object_storage'
          return respondReady()
        } catch { context.source_fallback = 'object_unavailable' }
      }
      if (res.destroyed) return dispose(id, 'client_closed')
      const client = new WebTorrent({utp:false, webSeeds:false})
      session.client = client
      session.source = context.source = 'torrent'
      const disconnected = () => dispose(id, 'client_closed')
      res.on('close', () => { if (!res.writableEnded) disconnected() })
      const unavailable = (status, reason) => {
        if (!sessions.has(id)) return
        context.outcome = reason
        if (res.headersSent) {
          log.emit('source_failed', {playback_id: session.playbackID, source: session.source, reason}, 'warn')
        } else json(res, status, {error:'Movie unavailable'})
        dispose(id, reason)
      }
      session.timer = setTimeout(() => unavailable(504, 'source_timeout'), 45_000)
      client.on('error', () => unavailable(502, 'torrent_client_error'))
      const magnet = `magnet:?xt=urn:btih:${hash}&tr=${encodeURIComponent('udp://tracker.opentrackr.org:1337/announce')}&tr=${encodeURIComponent('udp://open.demonii.com:1337/announce')}`
      const torrent = client.add(magnet, {store:Store, storeOpts:{maxBytes:128*1024*1024}, storeCacheSlots:0, deselect:true}, () => {
        clearTimeout(session.timer)
        if (!sessions.has(id)) return
        const file = torrent.files.filter(f => /\.mp4$/i.test(f.name)).sort((a,b) => b.length-a.length)[0]
        if (!file) {
          context.outcome = 'no_compatible_media'
          json(res, 422, {error:'No compatible MP4 available'})
          return dispose(id, context.outcome)
        }
        // Pinned WebTorrent adapter: evicted chunks must be downloaded again on future seeks.
        const store = torrent.store
        const raw = store.store ?? store
        raw.onEvict = index => { if (!torrent.destroyed) torrent._markUnverified(index) }
        Object.assign(session, {torrent, file})
        respondReady()
      })
      torrent.on('error', () => unavailable(502, 'torrent_source_error'))
      return
    }
    const match = /^\/v1\/sessions\/([a-f0-9-]{36})(\/video\.mp4)?$/.exec(path)
    if (match && !forwarded && cluster.ownsElsewhere(match[1])) {
      try {
        if (await forward(req, res, path, undefined, context)) return
      } catch {
        if (res.headersSent || res.destroyed) return
        return json(res, 404, {error:'Playback session expired'})
      }
    }
    const s = match && sessions.get(match[1])
    if (!s) return json(res, 404, {error:'Playback session expired'})
    context.playback_id = s.playbackID
    context.source = s.source
    s.touched = Date.now()
    if (req.method === 'DELETE' && !match[2]) { dispose(match[1], 'deleted'); res.writeHead(204); return res.end() }
    if (!match[2] || !['GET','HEAD'].includes(req.method) || !s.file) return json(res, 405, {error:'Method unavailable'})
    let range
    try { range = byteRange(req.headers.range, s.file.length) } catch { res.writeHead(416, {'Content-Range':`bytes */${s.file.length}`}); return res.end() }
    await serveVideo(req, res, s, range, undefined, context)
  } catch {
    context.outcome = 'internal_error'
    if (!res.headersSent) json(res, 500, {error:'Playback unavailable'}); else res.destroy()
  }
})
const sweep = setInterval(() => {
  for (const [id,s] of sessions) if (!s.active && Date.now()-s.touched > TTL) dispose(id, 'idle_expiry')
}, 30_000)
server.listen(Number(process.env.PORT ?? 8787), host, () => log.emit('service_started', {cluster_enabled:cluster.enabled}))
function shutdown() {
  clearInterval(sweep)
  for (const id of sessions.keys()) dispose(id, 'shutdown')
  server.close(() => log.emit('service_stopped'))
}
process.on('SIGTERM', shutdown); process.on('SIGINT', shutdown)
