import assert from 'node:assert/strict'
import {EventEmitter} from 'node:events'
import {test} from 'node:test'
import {diagnostics, observeRequest, routeName} from './diagnostics.mjs'

function request({path = '/v1/sessions', id, trustRequestID = false, sampleRate = '0'} = {}) {
  const records = []
  const log = diagnostics('test', {
    env: {MIRROR_LOG_SAMPLE_RATE: sampleRate},
    write: line => records.push(JSON.parse(line))
  })
  const req = {method: 'GET', headers: {'x-request-id': id, authorization: 'Bearer private-token'}}
  const res = new EventEmitter()
  res.setHeader = (name, value) => { res[name] = value }
  const context = observeRequest(req, res, log, {trustRequestID})
  context.route = routeName(path)
  function close({finished = true, status = 200, headersSent = true} = {}) {
    Object.assign(res, {writableFinished: finished, statusCode: status, headersSent})
    res.emit('close')
    res.emit('close')
  }
  return {records, res, context, close}
}

test('only a trusted, well-formed caller request ID is used', () => {
  const supplied = 'a'.repeat(32)
  const first = request({id: supplied})
  assert.match(first.res['x-request-id'], /^[a-f0-9]{32}$/)
  assert.notEqual(first.res['x-request-id'], supplied)
  const forwarded = request({id: first.res['x-request-id'], trustRequestID: true})
  forwarded.close()
  assert.equal(forwarded.records[0].request_id, first.res['x-request-id'])
  const invalid = request({id: 'private-token', trustRequestID: true})
  invalid.close()
  assert.notEqual(invalid.records[0].request_id, 'private-token')
})

test('media failures stay visible without logging private paths or credentials', () => {
  const session = 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa'
  const {records, context, close} = request({path: `/v1/sessions/${session}/video.mp4`})
  context.outcome = 'media_failure'
  close({finished: false, status: 206})
  assert.equal(records.length, 1)
  assert.equal(records[0].route, 'media')
  assert.equal(records[0].level, 'warn')
  assert.doesNotMatch(JSON.stringify(records), new RegExp(`${session}|private-token|video[.]mp4`))
})

test('client disconnect is distinct from upstream failure and health noise is omitted', () => {
  const aborted = request()
  aborted.close({finished: false, headersSent: false})
  assert.equal(aborted.records[0].outcome, 'client_closed')
  assert.equal(aborted.records[0].status, undefined)
  const health = request({path: '/health'})
  health.close()
  assert.deepEqual(health.records, [])
  assert.equal(routeName('/v1/subtitles/tt1234567/es'), 'subtitles')
  assert.equal(routeName('/v1/no-such-route'), 'unknown')
})
