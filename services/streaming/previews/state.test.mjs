import assert from 'node:assert/strict'
import {mkdtempSync, rmSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
import {test} from 'node:test'
import {createState, maxClips, movieIDs} from './state.mjs'

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

test('invalid IDs are rejected and the number of eligible objects is capped', t => {
  const directory = mkdtempSync(join(tmpdir(), 'mirror-preview-state-'))
  t.after(() => rmSync(directory, {recursive: true}))
  const state = createState(directory)
  const ids = Array.from({length: 320}, (_, index) => index + 1)
  state.record('one', movieIDs(ids))
  state.record('two', [1000])
  assert.equal(state.wanted().size, maxClips)
  assert.ok(state.wanted().has(1000))
  for (const value of [[1, -1], [1.5], ['1'], [...ids, 321], {}]) {
    assert.throws(() => movieIDs(value))
  }
})
