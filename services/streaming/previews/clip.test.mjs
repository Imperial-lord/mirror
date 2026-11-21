import assert from 'node:assert/strict'
import {test} from 'node:test'
import {movieHash} from './clip.mjs'

test('uses ordinary catalog sources when is_repack is the string zero', async t => {
  const hash = 'a'.repeat(40)
  t.mock.method(globalThis, 'fetch', async () => Response.json({data: {movie: {
    id: 42,
    torrents: [
      {hash: 'b'.repeat(40), seeds: 300, is_repack: '1'},
      {hash, seeds: 100, is_repack: '0'},
      {hash: 'c'.repeat(40), seeds: 5, is_repack: false},
    ],
  }}}))
  assert.equal(await movieHash(42), hash)
  assert.equal(await movieHash(42, 1), 'c'.repeat(40))
  await assert.rejects(movieHash(43), /Movie unavailable/)
})
