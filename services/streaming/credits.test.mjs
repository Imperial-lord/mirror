import test from 'node:test'
import assert from 'node:assert/strict'
import {parseOMDbCredits} from './credits.mjs'

test('OMDb credits preserve departments and omit absent data', () => {
  const result = parseOMDbCredits({Response:'True', imdbID:'tt2779318', Actors:'John Hurt, Matt Smith', Director:'Nick Hurran', Writer:'N/A'}, 'tt2779318')
  assert.deepEqual(result.credits, [
    {name:'John Hurt', department:'Actor'}, {name:'Matt Smith', department:'Actor'},
    {name:'Nick Hurran', department:'Director'}
  ])
})

test('wrong IMDb IDs and provider failures cannot populate movie credits', () => {
  assert.throws(() => parseOMDbCredits({Response:'True', imdbID:'tt1234567'}, 'tt2779318'))
  assert.throws(() => parseOMDbCredits({Response:'False', Error:'Invalid API key!'}, 'tt2779318'))
})

import {createMovieCredits} from './credits.mjs'

const payload = imdb => ({Response:'True', imdbID:imdb, Actors:'John Hurt', Director:'Nick Hurran', Writer:'N/A'})
const reply = movie => new Response(JSON.stringify(movie), {status:200})

test('repeated and concurrent requests share one lookup until TTL expires', async () => {
  let calls = 0, time = 1
  const lookup = createMovieCredits({
    apiKey: () => 'test-key', now: () => time,
    fetchImpl: async url => { calls++; return reply(payload(url.searchParams.get('i'))) }
  })
  const values = await Promise.all([lookup('tt2779318'), lookup('tt2779318')])
  assert.equal(calls, 1)
  assert.deepEqual(values[0], values[1])
  await lookup('tt2779318')
  assert.equal(calls, 1)
  time += 7 * 86400000 + 1
  await lookup('tt2779318')
  assert.equal(calls, 2)
})

test('daily budget serves cache and sends uncached movies to fallback', async () => {
  let calls = 0, time = 1
  const lookup = createMovieCredits({
    apiKey: () => 'test-key', dailyLimit: 2, now: () => time,
    fetchImpl: async url => { calls++; return reply(payload(url.searchParams.get('i'))) }
  })
  await Promise.all([lookup('tt2779318'), lookup('tt1234567'), lookup('tt7654321')])
  assert.equal(calls, 2)
  assert.equal(await lookup('tt7654321'), null)
  assert.ok(await lookup('tt2779318'))
  time += 86400000 + 1
  assert.ok(await lookup('tt7654321'))
  assert.equal(calls, 3)
})

test('provider quota suppresses calls while cached credits remain usable', async () => {
  let calls = 0, time = 1
  const lookup = createMovieCredits({
    apiKey: () => 'test-key', now: () => time,
    fetchImpl: async url => {
      calls++
      return reply(calls === 2 ? {Response:'False', Error:'Request limit reached!'} : payload(url.searchParams.get('i')))
    }
  })
  assert.ok(await lookup('tt2779318'))
  assert.equal(await lookup('tt1234567'), null)
  assert.equal(await lookup('tt7654321'), null)
  assert.equal(calls, 2)
  assert.ok(await lookup('tt2779318'))
  time += 86400000 + 1
  assert.ok(await lookup('tt7654321'))
  assert.equal(calls, 3)
})

test('provider errors allow fallback without request loops', async () => {
  for (const failure of ['network', 'key', 'missing', 'http-limit']) {
    let calls = 0
    const lookup = createMovieCredits({
      apiKey: () => 'test-key',
      fetchImpl: async () => {
        calls++
        if (failure === 'network') throw new Error('Connection failed')
        if (failure === 'http-limit') return new Response('', {status:429})
        return reply({Response:'False', Error:failure === 'key' ? 'Invalid API key!' : 'Movie not found!'})
      }
    })
    assert.equal(await lookup('tt2779318'), null)
    assert.equal(await lookup('tt2779318'), null)
    assert.equal(calls, 1)
  }
})

test('missing configuration and malformed IDs never call OMDb', async () => {
  let calls = 0
  const lookup = createMovieCredits({apiKey: () => '', fetchImpl: async () => { calls++; return reply({}) }})
  assert.equal(await lookup('tt2779318'), null)
  await assert.rejects(lookup('bad-id'))
  assert.equal(calls, 0)
})
