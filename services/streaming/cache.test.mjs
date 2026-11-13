import {test} from 'node:test'
import assert from 'node:assert/strict'
import {PieceCache, byteRange} from './cache.mjs'
import WebTorrent from 'webtorrent'
import {once} from 'node:events'
const put = (s,i,b) => new Promise((resolve,reject)=>s.put(i,b,e=>e?reject(e):resolve()))
const read = async stream => { const data=[]; for await (const chunk of stream) data.push(chunk); return Buffer.concat(data) }
test('HTTP byte ranges include suffixes and reject invalid or multi ranges', () => {
 assert.deepEqual(byteRange('bytes=5-999',10),{start:5,end:9})
 assert.deepEqual(byteRange('bytes=-3',10),{start:7,end:9})
 assert.deepEqual(byteRange('bytes=0-0',10),{start:0,end:0})
 for (const value of ['bytes=10-','bytes=5-2','bytes=-0','bytes=0-2,4-6']) assert.throws(()=>byteRange(value,10))
})
test('cache evicts old pieces and remains under byte budget',async()=>{
 const store = new PieceCache(4,{maxBytes:8}), evicted=[]; store.onEvict=i=>evicted.push(i)
 for(let i=0;i<4;i++) await put(store,i,Buffer.alloc(4,i))
 assert.equal(store.bytes,8); assert.deepEqual(evicted,[0,1])
})
test('real torrent seeks refetch evicted pieces without downloading the full file', {timeout:30000}, async()=>{
 const seed = new WebTorrent({dht:false,tracker:false,lsd:false,utp:false})
 const peer = new WebTorrent({dht:false,tracker:false,lsd:false,utp:false})
 try {
  const data=Buffer.alloc(2*1024*1024); for(let i=0;i<data.length;i++) data[i]=i%251
  const seeded=await new Promise(resolve=>seed.seed(data,{name:'fixture.mp4',pieceLength:16384,private:true},resolve))
  const downloaded=await new Promise(resolve=>peer.add(seeded.torrentFile,{deselect:true,store:PieceCache,storeCacheSlots:0,storeOpts:{maxBytes:65536}},resolve))
  const raw=downloaded.store.store; raw.onEvict=i=>downloaded._markUnverified(i)
  downloaded.addPeer(`127.0.0.1:${seed.torrentPort}`)
  for(const start of [0,1024*1024,0]) {
   const actual=await read(downloaded.files[0].createReadStream({start,end:start+32767}))
   assert.deepEqual(actual,data.subarray(start,start+32768))
   assert.ok(raw.bytes<=65536)
  }
  assert.ok(downloaded.downloaded<data.length)
 } finally { await Promise.all([seed,peer].map(c=>new Promise(resolve=>c.destroy(resolve)))) }
})
