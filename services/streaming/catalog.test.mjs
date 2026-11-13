import test from 'node:test'
import assert from 'node:assert/strict'
import {catalogParameters,parseBrowse} from './catalog.mjs'
const card = year => `<div class="browse-movie-wrap"><a class="browse-movie-link" href="https://yts.gg/movies/fight-club-1999"></a><a class="browse-movie-title"><span>[EN]</span> Fight Club</a><div class="browse-movie-year">${year}</div></div>`
test('year browse keeps title, verifies year and reads next page',()=>{
  const result=parseBrowse(card(1999)+'<a href="?page=2">Next »</a>',{year:1999,page:1})
  assert.deepEqual(result.entries,[{title:'Fight Club',path:'/movies/fight-club-1999',year:1999}])
  assert.equal(result.hasMore,true)
})
test('unexpected unfiltered page and provider block are errors, not no matches',()=>{
  assert.throws(()=>parseBrowse(card(2026),{year:1999,page:1}))
  assert.throws(()=>parseBrowse('<h1>Just a moment</h1>',{year:1999,page:1}))
  assert.deepEqual(parseBrowse('<h1>No movies found</h1>',{year:1999,page:1}),{entries:[],hasMore:false})
})
test('catalog parameters reject malformed filters',()=>{
  assert.throws(()=>catalogParameters(new URLSearchParams('year=1999&sort_by=anything')))
  assert.throws(()=>catalogParameters(new URLSearchParams('year=1999&genre=../../')))
  assert.equal(catalogParameters(new URLSearchParams('year=1999&sort_by=rating')).year,1999)
})
