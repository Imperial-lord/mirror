import {mkdtemp, rm, writeFile} from 'node:fs/promises'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
import {fileURLToPath} from 'node:url'
import {createState, pendingClips, previewLayout} from './state.mjs'
import {movieHash, makeTorrentClip, runFile} from './clip.mjs'
import {fetchHomeCatalog} from './home-catalog.mjs'

const state = createState(process.env.PREVIEW_STATE_DIR ?? '/state')
const helper = fileURLToPath(new URL('./oci-store.py', import.meta.url))
const trackers = ['udp://tracker.opentrackr.org:1337/announce', 'udp://open.demonii.com:1337/announce']
  .map(url => `&tr=${encodeURIComponent(url)}`).join('')

async function objects(action, ...args) {
  const timeout = ['sync-layout', 'prune-layout', 'prune-flat'].includes(action) ? 600_000 : 60_000
  const {stdout} = await runFile('/opt/preview-tools/bin/python', [helper, action, ...args], {timeout})
  return stdout
}

async function synchronizeLayout(scratch) {
  const {targets, indexes} = previewLayout(state.rows())
  const targetFile = join(scratch, 'targets.json')
  const indexFile = join(scratch, 'indexes.json')
  await writeFile(targetFile, JSON.stringify(targets), {mode: 0o600})
  await writeFile(indexFile, JSON.stringify(indexes), {mode: 0o600})
  const locations = JSON.parse(await objects('sync-layout', targetFile))
  const previous = state.locations() ?? {}
  state.publishLocations(locations)
  try { await objects('sync-indexes', indexFile) }
  catch (error) { console.warn('Preview row indexes could not be synchronized:', error.code ?? error.name) }
  return {targets, locations, targetFile, previous}
}

async function updateCatalog() {
  try {
    const rows = await fetchHomeCatalog()
    state.recordCatalog(rows)
    console.log(`Loaded ${Object.keys(rows).length} Home catalog rows with ${Object.values(rows).flat().length} slots`)
  } catch (error) {
    if (!state.catalog()) throw error
    console.warn(`Using the last complete Home catalog: ${error.message}`)
  }
}

async function refresh() {
  const scratch = await mkdtemp(join(tmpdir(), 'mirror-preview-'))
  try {
    const {targets, locations, targetFile, previous} = await synchronizeLayout(scratch)
    const wanted = state.wanted()
    const stored = new Set(Object.keys(locations).map(Number))
    if (process.argv.includes('--layout-only')) {
      console.log(`Preview folder layout verified with ${stored.size} stored clips`)
      return
    }
    const failures = state.failures()
    for (const key of Object.keys(failures)) {
      if (!wanted.has(Number(key))) delete failures[key]
    }
    const candidates = pendingClips(wanted, stored, failures)
    console.log(`Preview refresh started with ${candidates.length} missing of ${wanted.size} Home titles`)
    for (const id of candidates) {
      if (!targets[id] || !state.wanted().has(id)) continue
      const path = join(scratch, `${id}.mp4`)
      const previousFailures = failures[id]?.count ?? (failures[id] ? 1 : 0)
      let phase = 'source lookup'
      try {
        const hash = await movieHash(id, previousFailures)
        phase = 'torrent excerpt'
        await makeTorrentClip(`magnet:?xt=urn:btih:${hash}${trackers}`, path)
        if (!state.wanted().has(id)) continue
        phase = 'OCI upload'
        await objects('put', String(id), path, JSON.stringify(targets[id]))
        locations[id] = targets[id][0]
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
        state.publishLocations(Object.fromEntries(Object.entries(locations)
          .filter(([id]) => current.has(Number(id)))))
        state.saveFailures(failures)
      }
    }
    // Keep a prior URL for one refresh if its title is still on Home.
    const currentTargets = previewLayout(state.rows()).targets
    for (const [id, path] of Object.entries(previous)) {
      if (currentTargets[id] && !currentTargets[id].includes(path)) currentTargets[id].push(path)
    }
    await writeFile(targetFile, JSON.stringify(currentTargets), {mode: 0o600})
    await objects('prune-layout', targetFile)
    state.saveFailures(failures)
    console.log(`Preview refresh finished with ${stored.size} stored clips`)
  } finally {
    await rm(scratch, {recursive: true, force: true})
  }
}

if (process.argv.includes('--cleanup-flat-only')) {
  const scratch = await mkdtemp(join(tmpdir(), 'mirror-preview-prune-'))
  try {
    const targets = join(scratch, 'targets.json')
    if (!state.locations()) throw new Error('Preview URLs have not been migrated')
    await writeFile(targets, JSON.stringify(previewLayout(state.rows()).targets), {mode: 0o600})
    await objects('prune-flat', targets)
  } finally {
    await rm(scratch, {recursive: true, force: true})
  }
} else {
  await updateCatalog()
  await refresh()
}
