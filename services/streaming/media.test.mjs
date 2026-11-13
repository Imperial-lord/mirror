import test from 'node:test'
import assert from 'node:assert/strict'
import {EventEmitter} from 'node:events'
import {Readable} from 'node:stream'
import {serveVideo} from './media.mjs'
class Response extends EventEmitter {
  destroyed = false; data = []; status = null
  writeHead(status, headers) { this.status = status; this.headers = headers }
  setTimeout() {}
  write(chunk) { this.data.push(chunk); return true }
  end(body) { if(body) this.data.push(body); this.emit('close') }
  destroy() { this.destroyed = true; this.emit('close') }
}
test('cancelled stalled reads release slots immediately and only once', () => {
  let destroyed = 0
  const session = {active:0,file:{length:100,createReadStream:()=>({
    async *[Symbol.asyncIterator]() { await new Promise(()=>{}); yield Buffer.alloc(0) },
    destroy() { destroyed++ }
  })}}
  for(let index=0;index<8;index++) {
    const res = new Response()
    void serveVideo({method:'GET'},res,session,{start:0,end:9})
    assert.equal(session.active,1)
    res.destroy(); res.emit('close')
    assert.equal(session.active,0)
    assert.equal(res.listenerCount('close'),0)
  }
  assert.equal(destroyed,8)
})
test('valid ranges are served in bounded windows and slots are released', async () => {
  const ranges = [], session = {active:0,file:{length:10,createReadStream:range=>{
    ranges.push(range); return Readable.from([Buffer.alloc(range.end-range.start+1)])
  }}}
  const res = new Response()
  await serveVideo({method:'GET'},res,session,{start:2,end:8},3)
  assert.equal(res.status,206); assert.equal(res.headers['Content-Range'],'bytes 2-8/10')
  assert.equal(Buffer.concat(res.data).length,7); assert.equal(session.active,0)
  assert.deepEqual(ranges,[{start:2,end:4},{start:5,end:7},{start:8,end:8}])
})
test('capacity responds explicitly while HEAD does not consume a stream slot', async () => {
  const session = {active:4,file:{length:10,createReadStream:()=>{throw new Error('must not read')}}}
  const res = new Response(); await serveVideo({method:'GET'},res,session,null)
  assert.equal(res.status,503); assert.equal(session.active,4)
  const head = new Response(); await serveVideo({method:'HEAD'},head,session,null)
  assert.equal(head.status,200); assert.equal(session.active,4)
})
