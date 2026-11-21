import {createHash} from 'node:crypto'
import {createServer} from 'node:http'
import {applicationDefault, initializeApp} from 'firebase-admin/app'
import {getAuth} from 'firebase-admin/auth'
import {createState, movieIDs} from './state.mjs'

const projectId = process.env.FIREBASE_PROJECT_ID
if (!projectId) throw new Error('FIREBASE_PROJECT_ID is required')
initializeApp({credential: applicationDefault(), projectId})
const state = createState(process.env.PREVIEW_STATE_DIR ?? '/state')
const origin = new URL(process.env.PREVIEW_READ_URL)
if (origin.protocol !== 'https:' ||
    !/^objectstorage\.[a-z0-9-]+\.oraclecloud\.com$/.test(origin.hostname) ||
    !/^\/p\/[^/]+\/n\/[^/]+\/b\/[^/]+\/o\/home\/v1\/$/.test(origin.pathname)) {
  throw new Error('Invalid OCI preview read URL')
}

function json(res, status, value) {
  res.writeHead(status, {'Content-Type': 'application/json', 'Cache-Control': 'no-store'})
  res.end(JSON.stringify(value))
}

createServer(async (req, res) => {
  if (req.method !== 'POST' || req.url !== '/v1/home-previews') return json(res, 404, {})
  let uid
  try {
    const match = /^Bearer (.+)$/.exec(req.headers.authorization ?? '')
    if (!match) return json(res, 401, {})
    ;({uid} = await getAuth().verifyIdToken(match[1]))
  } catch { return json(res, 401, {}) }

  let ids
  try {
    const chunks = []
    let size = 0
    for await (const chunk of req) {
      size += chunk.length
      if (size > 8192) return json(res, 413, {})
      chunks.push(chunk)
    }
    ids = movieIDs(JSON.parse(Buffer.concat(chunks)))
  } catch { return json(res, 400, {}) }

  try {
    const account = createHash('sha256').update(uid).digest('hex')
    state.record(account, ids)
    const ready = new Set(state.clips())
    const entries = ids.filter(id => ready.has(id))
      .map(id => [id, new URL(`${id}.mp4`, origin).href])
    return json(res, 200, Object.fromEntries(entries))
  } catch {
    return json(res, 503, {})
  }
}).listen(Number(process.env.PREVIEW_PORT ?? 8790), process.env.PREVIEW_HOST ?? '127.0.0.1')
