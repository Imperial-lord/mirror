// WebTorrent chunk-store API. Eviction must also invalidate the torrent bitfield.
export class PieceCache {
  constructor(chunkLength, options = {}) {
    this.chunkLength = chunkLength
    this.limit = options.maxBytes ?? 128 * 1024 * 1024
    this.chunks = new Map(); this.bytes = 0
    this.onEvict = () => {}
    if (chunkLength > this.limit) throw new Error('Torrent pieces exceed cache budget')
  }
  put(index, buffer, cb = () => {}) {
    const old = this.chunks.get(index)
    if (old) this.bytes -= old.length
    this.chunks.delete(index); this.chunks.set(index, Buffer.from(buffer)); this.bytes += buffer.length
    while (this.bytes > this.limit) {
      const [key, data] = this.chunks.entries().next().value
      this.chunks.delete(key); this.bytes -= data.length; this.onEvict(key)
    }
    queueMicrotask(() => cb(null))
  }
  get(index, options, cb) {
    if (typeof options === 'function') { cb = options; options = {} }
    const data = this.chunks.get(index)
    if (!data) return queueMicrotask(() => cb(Object.assign(new Error('Piece missing'), {notFound: true})))
    this.chunks.delete(index); this.chunks.set(index, data)
    const offset = options?.offset ?? 0
    queueMicrotask(() => cb(null, data.subarray(offset, options?.length == null ? data.length : offset + options.length)))
  }
  close(cb = () => {}) { this.chunks.clear(); this.bytes = 0; queueMicrotask(cb) }
  destroy(cb) { this.close(cb) }
}
export function byteRange(header, size) {
  if (!header) return null
  const m = /^bytes=(\d*)-(\d*)$/.exec(header)
  if (!m || (!m[1] && !m[2])) throw new Error('Invalid range')
  const start = m[1] ? Number(m[1]) : Math.max(0, size - Number(m[2]))
  const end = m[1] ? (m[2] ? Math.min(Number(m[2]), size - 1) : size - 1) : size - 1
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start > end || start >= size) throw new Error('Invalid range')
  return {start, end}
}
