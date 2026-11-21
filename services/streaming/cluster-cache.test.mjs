import assert from 'node:assert/strict'
import {mkdtemp, rm} from 'node:fs/promises'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
import {test} from 'node:test'
import {promisify} from 'node:util'
import {diskPieceStore} from './disk-cache.mjs'
import {clusterRouting} from './cluster.mjs'
import {objectSources} from './object-source.mjs'

test('a second session and a restarted worker can reuse pieces; eviction notifies live sessions', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'mirror-pieces-'))
  try {
    const torrent = {infoHash: 'a'.repeat(40)}
    const options = {budget: 8, reserve: 0}
    const Store = await diskPieceStore(directory, options)
    const first = new Store(4, {torrent})
    const second = new Store(4, {torrent})
    await promisify(first.put.bind(first))(0, Buffer.from('abcd'))
    await promisify(first.close.bind(first))()
    assert.deepEqual(await promisify(second.get.bind(second))(0, {offset: 1, length: 2}), Buffer.from('bc'))
    await promisify(second.close.bind(second))()
    const ReopenedStore = await diskPieceStore(directory, options)
    const reopened = new ReopenedStore(4, {torrent})
    const evicted = []
    reopened.onEvict = piece => evicted.push(piece)
    assert.deepEqual(await promisify(reopened.get.bind(reopened))(0, {}), Buffer.from('abcd'))
    await promisify(reopened.put.bind(reopened))(1, Buffer.from('efgh'))
    await promisify(reopened.put.bind(reopened))(2, Buffer.from('ijkl'))
    assert.deepEqual(evicted, [0])
    await assert.rejects(promisify(reopened.get.bind(reopened))(0, {}), {notFound: true})
  } finally {
    await rm(directory, {recursive: true, force: true})
  }
})

test('workers prefer the same owner for a movie and can identify each other’s sessions', () => {
  const make = (node, peer) => clusterRouting({
    MIRROR_NODE_ID: node, MIRROR_PEER_ID: peer,
    MIRROR_PEER_URL: 'http://10.0.0.5:18787',
    MIRROR_PEER_KEY: 'fixture'.repeat(5)
  })
  const a = make('0123abcd', '4567abcd')
  const b = make('4567abcd', '0123abcd')
  assert.ok(a.ownsElsewhere(b.id()))
  assert.ok(b.ownsElsewhere(a.id()))
  assert.equal(a.ownsElsewhere(a.id()), false)
  for (const hash of ['a'.repeat(40), 'b'.repeat(40)]) {
    assert.notEqual(a.prefersPeer(hash), b.prefersPeer(hash))
  }
  assert.equal(a.forwarded({headers: {'x-mirror-peer': 'wrong'}}), false)
})

test('preloaded source mappings only accept exact hashes and OCI object URLs', () => {
  const hash = 'a'.repeat(40)
  assert.throws(() => objectSources(JSON.stringify({[hash]: 'https://localhost/private'})))
  assert.throws(() => objectSources(JSON.stringify({bad: 'https://objectstorage.ap-hyderabad-1.oraclecloud.com/p/test/n/name/b/media/o/clip.mp4'})))
  assert.equal(objectSources(JSON.stringify({[hash]: 'https://objectstorage.ap-hyderabad-1.oraclecloud.com/p/test/n/name/b/media/o/clip.mp4'})).size, 1)
})
