import {randomUUID} from 'node:crypto'
import {performance} from 'node:perf_hooks'

export const elapsed = start => Math.round(performance.now() - start)

export function diagnostics(service, {
  env = process.env, write = line => process.stdout.write(line + '\n'), random = Math.random
} = {}) {
  const node = /^[a-f0-9]{8}$/.test(env.MIRROR_NODE_ID ?? '') ? env.MIRROR_NODE_ID : 'local'
  const rate = Number(env.MIRROR_LOG_SAMPLE_RATE ?? 0.05)
  const sample = () => random() < (Number.isFinite(rate) && rate >= 0 && rate <= 1 ? rate : 0.05)
  const emit = (event, fields = {}, level = 'info') => {
    try {
      write(JSON.stringify({...fields, timestamp: new Date().toISOString(), schema_version: 1,
        service, node, level, event}))
    } catch {
      // Diagnostics must never interrupt playback.
    }
  }
  return {emit, sample}
}

const routes = new Map([
  ['/health', 'health'], ['/v1/sessions', 'session_create'], ['/v1/subtitles', 'subtitles'],
  ['/v1/credits', 'credits'], ['/v1/catalog', 'catalog'], ['/v1/ai/search', 'ai_search'],
  ['/v1/home-previews', 'home_previews']
])

export function routeName(path) {
  if (/^\/v1\/sessions\/[a-f0-9-]{36}\/video\.mp4$/.test(path)) return 'media'
  if (/^\/v1\/sessions\/[a-f0-9-]{36}$/.test(path)) return 'session'
  if (path.startsWith('/v1/subtitles/')) return 'subtitles'
  if (path.startsWith('/v1/credits/')) return 'credits'
  return routes.get(path) ?? 'unknown'
}

export function observeRequest(req, res, log, {trustRequestID = false} = {}) {
  const incoming = req.headers['x-request-id']
  const id = trustRequestID && typeof incoming === 'string' && /^[a-f0-9]{32}$/.test(incoming)
    ? incoming : randomUUID().replaceAll('-', '')
  const context = {request_id: id, route: 'unknown'}
  const start = performance.now()
  const method = ['GET', 'POST', 'HEAD', 'DELETE'].includes(req.method) ? req.method : 'other'
  res.setHeader('x-request-id', id)
  res.once('close', () => {
    const completed = res.writableFinished
    const status = res.headersSent ? res.statusCode : undefined
    const duration_ms = elapsed(start)
    if (context.route === 'health' && completed && status === 200) return
    const failed = status >= 500 || ['media_failure', 'media_timeout', 'internal_error'].includes(context.outcome)
    if (context.route === 'media' && context.session_first_byte_ms === undefined &&
        !failed && duration_ms < 2000 &&
        (!completed || status < 400) && !log.sample()) return
    if (['unknown', 'home_previews'].includes(context.route) && !failed && !log.sample()) return
    log.emit('request_completed', {...context, method, status, duration_ms,
      outcome: context.outcome ?? (!completed ? 'client_closed' : status >= 400 ? 'rejected' : 'completed')},
    failed ? 'warn' : 'info')
  })
  return context
}
