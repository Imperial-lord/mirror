import http from 'node:http'
import {randomUUID} from 'node:crypto'
import {pipeline} from 'node:stream/promises'

export function clusterRouting(env = process.env) {
  const node = env.MIRROR_NODE_ID
  const peerNode = env.MIRROR_PEER_ID
  const peer = env.MIRROR_PEER_URL && new URL(env.MIRROR_PEER_URL)
  const key = env.MIRROR_PEER_KEY
  const enabled = Boolean(node || peerNode || peer || key)
  if (enabled && (!/^[a-f0-9]{8}$/.test(node ?? '') || !/^[a-f0-9]{8}$/.test(peerNode ?? '') ||
    node === peerNode || !peer || peer.protocol !== 'http:' ||
    !/^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(peer.hostname) ||
    peer.username || peer.password || peer.pathname !== '/' || peer.search || peer.hash || (key?.length ?? 0) < 32)) {
    throw new Error('Invalid Mirror cluster configuration')
  }
  return {
    enabled,
    id() { const uuid = randomUUID(); return enabled ? node + uuid.slice(8) : uuid },
    ownsElsewhere(id) { return enabled && id.startsWith(peerNode + '-') },
    prefersPeer(hash) {
      return enabled && ((Number.parseInt(hash[0], 16) % 2 === 0) === (peerNode < node))
    },
    forwarded(req) { return enabled && req.headers['x-mirror-peer'] === key },
    async forward(req, res, path, body) {
      const upstream = await new Promise((resolve, reject) => {
        const headers = {'x-mirror-peer': key}
        for (const name of ['authorization', 'content-type', 'range']) {
          if (req.headers[name] !== undefined) headers[name] = req.headers[name]
        }
        headers['x-request-id'] = res.getHeader('x-request-id') ?? randomUUID().replaceAll('-', '')
        if (body !== undefined) headers['content-length'] = Buffer.byteLength(body)
        const request = http.request(new URL(path, peer), {method: req.method, headers}, resolve)
        const disconnect = () => { if (!res.writableEnded) request.destroy() }
        res.once('close', disconnect)
        request.once('close', () => res.off('close', disconnect))
        request.on('error', reject)
        request.setTimeout(57_000, () => request.destroy(new Error('Worker timed out')))
        request.end(body)
      })
      if (upstream.statusCode === 503 && upstream.headers['x-mirror-capacity'] === 'full') {
        upstream.resume()
        return false
      }
      const headers = {...upstream.headers}
      for (const name of ['connection', 'keep-alive', 'transfer-encoding', 'x-mirror-capacity', 'x-request-id']) delete headers[name]
      res.writeHead(upstream.statusCode, headers)
      await pipeline(upstream, res)
      return true
    }
  }
}
