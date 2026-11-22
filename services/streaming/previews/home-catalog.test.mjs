import assert from 'node:assert/strict'
import {test} from 'node:test'
import {fetchHomeCatalog} from './home-catalog.mjs'

test('loads all 20 shared Home rows with the same 15-title catalog queries', async () => {
  const requests = []
  const result = await fetchHomeCatalog(async url => {
    requests.push(Object.fromEntries(url.searchParams))
    return Response.json({status: 'ok', data: {
      movies: Array.from({length: 15}, (_, index) => ({id: index + 1})),
    }})
  })
  assert.equal(Object.keys(result).length, 20)
  assert.equal(Object.values(result).flat().length, 300)
  assert.equal(requests.filter(query => query.genre).length, 18)
  assert.ok(requests.every(query => query.limit === '15' && query.order_by === 'desc'))
  assert.equal(requests.find(query => query.sort_by === 'like_count').page, '1')
  assert.equal(requests.find(query => query.minimum_rating).minimum_rating, '8')
})

test('an upstream failure cannot publish a partial catalog', async () => {
  await assert.rejects(fetchHomeCatalog(async url => url.searchParams.get('genre') === 'Action'
    ? new Response('', {status: 503})
    : Response.json({status: 'ok', data: {movies: [{id: 1}]}})), /genre-action/)
})
