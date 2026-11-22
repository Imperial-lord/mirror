import assert from 'node:assert/strict'
import {mkdtempSync, rmSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
import {test} from 'node:test'
import {createState, maxPerAccount, movieIDs, pendingClips, previewLayout} from './state.mjs'

test('a movie appears in each matching row folder using one encoding job', () => {
  const {targets, indexes} = previewLayout({
    catalog: {'popular-now': [1, 2], 'top-rated': [1], 'genre-sci-fi': [1]},
    account: {'reported-home': [1, 3]},
  })
  assert.deepEqual(targets, {
    1: ['popular-now/1.mp4', 'top-rated/1.mp4', 'genres/sci-fi/1.mp4'],
    2: ['popular-now/2.mp4'],
    3: ['reported-home/3.mp4'],
  })
  assert.deepEqual(indexes.catalog['genre-sci-fi'], ['genres/sci-fi/1.mp4'])
  assert.deepEqual(indexes.account['reported-home'], ['popular-now/1.mp4', 'reported-home/3.mp4'])
})

test('the worker includes every catalog row before the app reports any discovery rows', t => {
  const directory = mkdtempSync(join(tmpdir(), 'mirror-preview-state-'))
  t.after(() => rmSync(directory, {recursive: true}))
  const state = createState(directory)
  const catalog = Object.fromEntries(Array.from({length: 20}, (_, row) => [
    `row-${row}`, Array.from({length: 15}, (_, i) => 1 + row * 15 + i),
  ]))
  state.recordCatalog(catalog)
  state.record('account', Array.from({length: 25}, (_, i) => 301 + i))
  assert.equal(state.wanted().size, 325)
  assert.deepEqual(state.rows().catalog, catalog)
  state.record('account', [1, 2])
  assert.equal(state.wanted().size, 300)
})

test('a refresh attempts every missing title, including recent failures', () => {
  const ids = Array.from({length: 68}, (_, index) => index + 1)
  const stored = new Set(ids.slice(0, 17))
  const failures = {18: {at: Date.now(), count: 1}, 19: Date.now() - 1000}
  assert.deepEqual(
    pendingClips(new Set(ids), stored, failures),
    [...ids.slice(19), 19, 18],
  )
})

test('a fresh Home snapshot replaces its old titles while another account keeps shared titles', t => {
  const directory = mkdtempSync(join(tmpdir(), 'mirror-preview-state-'))
  t.after(() => rmSync(directory, {recursive: true}))
  const api = createState(directory)
  const cron = createState(directory)
  const now = Date.now()
  api.record('one', movieIDs([1, 2, 1]), now)
  api.record('two', movieIDs([2, 3]), now)
  assert.deepEqual([...cron.wanted()], [1, 2, 3])
  api.record('one', movieIDs([4]), now + 1)
  assert.deepEqual([...cron.wanted()], [4, 2, 3])
  api.record('one', movieIDs([4]), now + 7 * 60 * 60 * 1000)
  assert.deepEqual([...createState(directory).wanted()], [4, 2, 3])
  cron.publish(new Set([4, 3]))
  assert.deepEqual(api.clips(), [4, 3])
})

test('invalid IDs are rejected and all reported titles remain eligible', t => {
  const directory = mkdtempSync(join(tmpdir(), 'mirror-preview-state-'))
  t.after(() => rmSync(directory, {recursive: true}))
  const state = createState(directory)
  const ids = Array.from({length: maxPerAccount}, (_, index) => index + 1)
  state.record('one', movieIDs(ids))
  state.record('two', [1000])
  assert.equal(state.wanted().size, ids.length + 1)
  assert.ok(state.wanted().has(1000))
  for (const value of [[1, -1], [1.5], ['1'], [...ids, maxPerAccount + 1], {}]) {
    assert.throws(() => movieIDs(value))
  }
})
