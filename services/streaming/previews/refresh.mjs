import {mkdtemp, rm, writeFile} from 'node:fs/promises'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
import {fileURLToPath} from 'node:url'
import {randomUUID} from 'node:crypto'
import {performance} from 'node:perf_hooks'
import {createState, pendingClips, previewLayout} from './state.mjs'
import {movieHash, makeTorrentClip, runFile} from './clip.mjs'
import {fetchHomeCatalog} from './home-catalog.mjs'
import {diagnostics, elapsed} from '../diagnostics.mjs'

const state = createState(process.env.PREVIEW_STATE_DIR ?? '/state')
const log = diagnostics('preview_refresh')
const runID = randomUUID()
const record = (event, fields, level) => log.emit(event, {...fields, run_id: runID}, level)
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
  catch { record('preview_index_sync_failed', {}, 'warn') }
  return {targets, locations, targetFile, previous}
}

async function updateCatalog() {
  try {
    const rows = await fetchHomeCatalog()
    state.recordCatalog(rows)
    record('preview_catalog_loaded', {rows: Object.keys(rows).length, slots: Object.values(rows).flat().length})
  } catch (error) {
    if (!state.catalog()) throw error
    record('preview_catalog_fallback', {}, 'warn')
  }
}

async function refresh() {
  const started = performance.now()
  const scratch = await mkdtemp(join(tmpdir(), 'mirror-preview-'))
  try {
    const {targets, locations, targetFile, previous} = await synchronizeLayout(scratch)
    const wanted = state.wanted()
    const stored = new Set(Object.keys(locations).map(Number))
    if (process.argv.includes('--layout-only')) {
      record('preview_layout_synced', {stored: stored.size, duration_ms: elapsed(started)})
      return
    }
    const failures = state.failures()
    for (const key of Object.keys(failures)) {
      if (!wanted.has(Number(key))) delete failures[key]
    }
    const candidates = pendingClips(wanted, stored, failures)
    record('preview_refresh_started', {queued: candidates.length, wanted: wanted.size})
    let attempted = 0, published = 0, skipped = 0
    const failed = {source_lookup: 0, clip_generation: 0, object_upload: 0}
    for (const id of candidates) {
      if (!targets[id] || !state.wanted().has(id)) { skipped++; continue }
      attempted++
      const path = join(scratch, `${id}.mp4`)
      const previousFailures = failures[id]?.count ?? (failures[id] ? 1 : 0)
      let phase = 'source_lookup'
      try {
        const hash = await movieHash(id, previousFailures)
        phase = 'clip_generation'
        await makeTorrentClip(`magnet:?xt=urn:btih:${hash}${trackers}`, path)
        if (!state.wanted().has(id)) { skipped++; continue }
        phase = 'object_upload'
        await objects('put', String(id), path, JSON.stringify(targets[id]))
        locations[id] = targets[id][0]
        stored.add(id)
        delete failures[id]
        published++
      } catch {
        failures[id] = {at: Date.now(), count: previousFailures + 1}
        failed[phase]++
      } finally {
        await rm(path, {force: true})
        const current = state.wanted()
        state.publishLocations(Object.fromEntries(Object.entries(locations)
          .filter(([id]) => current.has(Number(id)))))
        state.saveFailures(failures)
        if (attempted % 10 === 0) record('preview_refresh_progress', {attempted, published, failed, stored: stored.size})
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
    record('preview_refresh_finished', {attempted, published, skipped, failed, stored: stored.size,
      duration_ms: elapsed(started)})
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
  const started = performance.now()
  let stage = 'catalog'
  try {
    await updateCatalog()
    stage = 'refresh'
    await refresh()
  } catch {
    record('preview_refresh_failed', {stage, duration_ms: elapsed(started)}, 'error')
    process.exitCode = 1
  }
}
