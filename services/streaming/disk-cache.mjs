import {mkdir, readdir, statfs, writeFile, rename, readFile, unlink, stat} from 'node:fs/promises'
import {join} from 'node:path'
import {randomUUID} from 'node:crypto'

const pieceName = /^[a-f0-9]{40}-\d+\.piece$/
const missing = () => Object.assign(new Error('Piece missing'), {notFound: true})

export async function diskPieceStore(directory, {budget, reserve}) {
  await mkdir(directory, {recursive: true, mode: 0o700})
  const entries = (await readdir(directory, {withFileTypes: true})).filter(entry => entry.isFile())
  const index = new Map()
  const subscribers = new Map()
  let bytes = 0
  let pending = Promise.resolve()
  const serialize = operation => {
    const next = pending.then(operation)
    pending = next.catch(() => {})
    return next
  }
  const remove = async key => {
    try { await unlink(join(directory, key)) } catch (error) { if (error.code !== 'ENOENT') throw error }
    bytes -= index.get(key) ?? 0
    index.delete(key)
    const split = key.lastIndexOf('-')
    for (const store of subscribers.get(key.slice(0, split)) ?? []) {
      store.onEvict(Number.parseInt(key.slice(split + 1), 10))
    }
  }
  const persisted = []
  for (const entry of entries) {
    if (pieceName.test(entry.name)) persisted.push([entry.name, await stat(join(directory, entry.name))])
    else if (/^[a-f0-9-]{36}\.tmp$/.test(entry.name)) await unlink(join(directory, entry.name))
  }
  persisted.sort((a, b) => a[1].mtimeMs - b[1].mtimeMs)
  for (const [key, file] of persisted) { index.set(key, file.size); bytes += file.size }
  while (bytes > budget) await remove(index.keys().next().value)

  return class DiskPieceStore {
    constructor(_chunkLength, {torrent}) {
      this.hash = torrent.infoHash
      if (!/^[a-f0-9]{40}$/.test(this.hash)) throw new Error('Invalid cache namespace')
      if (!subscribers.has(this.hash)) subscribers.set(this.hash, new Set())
      subscribers.get(this.hash).add(this)
    }
    onEvict = () => {}
    put(piece, buffer, cb = () => {}) {
      const key = `${this.hash}-${piece}.piece`
      serialize(async () => {
        const fs = await statfs(directory)
        let free = fs.bavail * fs.bsize
        while (index.size && (bytes + buffer.length > budget || free - buffer.length < reserve)) {
          const oldest = index.keys().next().value
          free += index.get(oldest)
          await remove(oldest)
        }
        if (buffer.length > budget || free - buffer.length < reserve) throw new Error('Piece cache is full')
        const temp = join(directory, `${randomUUID()}.tmp`)
        try {
          await writeFile(temp, buffer, {mode: 0o600})
          await rename(temp, join(directory, key))
          bytes += buffer.length - (index.get(key) ?? 0)
          index.delete(key)
          index.set(key, buffer.length)
        } finally {
          await unlink(temp).catch(error => { if (error.code !== 'ENOENT') throw error })
        }
      }).then(() => cb(null), cb)
    }
    get(piece, options, cb) {
      if (typeof options === 'function') { cb = options; options = {} }
      const key = `${this.hash}-${piece}.piece`
      if (!index.has(key)) return queueMicrotask(() => cb(missing()))
      serialize(async () => {
        const length = index.get(key)
        if (length === undefined) throw missing()
        let data
        try { data = await readFile(join(directory, key)) }
        catch (error) {
          if (error.code !== 'ENOENT') throw error
          await remove(key)
          throw missing()
        }
        index.delete(key)
        index.set(key, length)
        const offset = options?.offset ?? 0
        return data.subarray(offset, options?.length == null ? undefined : offset + options.length)
      }).then(data => cb(null, data), cb)
    }
    close(cb = () => {}) {
      const stores = subscribers.get(this.hash)
      stores?.delete(this)
      if (stores?.size === 0) subscribers.delete(this.hash)
      queueMicrotask(() => cb(null))
    }
    destroy(cb) { this.close(cb) }
  }
}
