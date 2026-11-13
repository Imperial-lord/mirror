import {test} from 'node:test'
import assert from 'node:assert/strict'
import AdmZip from 'adm-zip'
import {extract, subtitles, tracks} from './subtitles.mjs'
const srt='1\n00:00:01,000 --> 00:00:02,500\nHello world\n'
function archive() { const zip=new AdmZip(); zip.addFile('movie.srt',Buffer.from(srt)); return zip.toBuffer() }
test('extracts timed SRT from ZIP in memory',()=>assert.equal(extract(archive()),srt))
test('rejects archives without SRT',()=>{ const zip=new AdmZip();zip.addFile('unsafe.exe',Buffer.from('x'));assert.throws(()=>extract(zip.toBuffer())) })
test('language selection uses exact language names',()=>{
 const html='<tr><td class="sub-lang">Italian</td><td><a class="subtitle-download" href="/subtitles/a">download</a></td></tr>'
 assert.equal(tracks(`<table>${html}</table>`,'it').length,1)
 assert.equal(tracks(`<table>${html}</table>`,'en').length,0)
})
test('missing language falls back to English, never mislabeled',async()=>{
 const get=async url=>{
  url=String(url)
  if(url.includes('movie-imdb')) return Buffer.from('<table><tr><td class="sub-lang">English</td><td><a class="subtitle-download" href="/subtitles/fixture">download</a></td></tr></table>')
  if(url.endsWith('.zip')) return archive()
  return Buffer.from(`<a id="btn-download-subtitle" data-link="${Buffer.from('https://subtitles.yts-subs.com/fixture.zip').toString('base64')}"></a>`)
 }
 const result=await subtitles('tt9999999','fr',get)
 assert.equal(result.language,'en');assert.equal(result.requestedLanguage,'fr');assert.equal(result.text,srt)
})
