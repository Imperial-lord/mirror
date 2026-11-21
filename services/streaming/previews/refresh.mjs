import {mkdtemp, rm} from 'node:fs/promises'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
import {fileURLToPath} from 'node:url'
import {createState} from './state.mjs'
import {movieHash, makeTorrentClip, runFile} from './clip.mjs'

const state = createState(process.env.PREVIEW_STATE_DIR ?? '/state')
const helper = fileURLToPath(new URL('./oci-store.py', import.meta.url))
const batch = Number(process.env.PREVIEW_MAX_ATTEMPTS ?? 12)
const retryAfter = 90 * 60 * 1000
const trackers = ['udp://tracker.opentrackr.org:1337/announce', 'udp://open.demonii.com:1337/announce']
  .map(url => `&tr=${encodeURIComponent(url)}`).join('')
if (!Number.isSafeInteger(batch) || batch < 1 || batch > 24) {
  throw new Error('PREVIEW_MAX_ATTEMPTS must be between 1 and 24')
}

async function objects(action, ...args) {
  const {stdout} = await runFile('/opt/preview-tools/bin/python', [helper, action, ...args], {
    timeout: 60_000,
  })
  return stdout
}

async function refresh() {
  const wanted = state.wanted()
  const stored = new Set(JSON.parse(await objects('list')))
  const failures = state.failures()
  for (const key of Object.keys(failures)) {
    if (!wanted.has(Number(key))) delete failures[key]
  }
  state.publish([...stored].filter(id => wanted.has(id)))
  for (const id of stored) {
    if (wanted.has(id) || state.wanted().has(id)) continue
    await objects('delete', String(id))
    stored.delete(id)
  }

  const failureTime = id => failures[id]?.at ?? failures[id] ?? 0
  const candidates = [...wanted].filter(id =>
    !stored.has(id) && Date.now() - failureTime(id) >= retryAfter)
    .sort((a, b) => failureTime(a) - failureTime(b)).slice(0, batch)
  const scratch = await mkdtemp(join(tmpdir(), 'mirror-preview-'))
  try {
    for (const id of candidates) {
      if (!state.wanted().has(id)) continue
      const path = join(scratch, `${id}.mp4`)
      const previousFailures = failures[id]?.count ?? (failures[id] ? 1 : 0)
      let phase = 'source lookup'
      try {
        const hash = await movieHash(id, previousFailures)
        phase = 'torrent excerpt'
        await makeTorrentClip(`magnet:?xt=urn:btih:${hash}${trackers}`, path)
        if (!state.wanted().has(id)) continue
        phase = 'OCI upload'
        await objects('put', String(id), path)
        stored.add(id)
        delete failures[id]
        console.log(`Published preview for ${id}`)
      } catch (error) {
        failures[id] = {at: Date.now(), count: previousFailures + 1}
        const details = phase === 'OCI upload' ? error.code ?? error.name
          : error.stderr?.trim().split('\n').at(-1) || error.message
        console.warn(`Preview unavailable for ${id} during ${phase}: ${details}`)
      } finally {
        await rm(path, {force: true})
        const current = state.wanted()
        state.publish([...stored].filter(id => current.has(id)))
        state.saveFailures(failures)
      }
    }
  } finally {
    await rm(scratch, {recursive: true, force: true})
  }
  state.saveFailures(failures)
  console.log(`Preview refresh finished with ${stored.size} stored clips`)
}

await refresh()
