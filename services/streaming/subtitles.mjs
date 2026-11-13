import {load} from 'cheerio'
import AdmZip from 'adm-zip'
import {inflateRawSync} from 'node:zlib'
const languages = {en:'english',it:'italian',es:'spanish',fr:'french'}
const cache = new Map()
const MAX = 2*1024*1024
export async function providerFetch(url) {
  url = new URL(url)
  if (url.protocol !== 'https:' || !['yts-subs.com','subtitles.yts-subs.com'].includes(url.hostname)) throw new Error('Invalid subtitle source')
  const response = await fetch(url, {signal:AbortSignal.timeout(5000),redirect:'manual'})
  if (!response.ok) throw new Error('Subtitle source unavailable')
  const chunks=[]; let size=0
  for await (const chunk of response.body) {
    size+=chunk.length; if(size>4*1024*1024) throw new Error('Subtitle response too large')
    chunks.push(chunk)
  }
  return Buffer.concat(chunks)
}
export function tracks(html, language) {
 const $=load(html)
 return $('tr').toArray().filter(row=>$(row).find('.sub-lang').text().trim().toLowerCase()===languages[language])
   .map(row=>({path:$(row).find('a.subtitle-download').attr('href'),text:$(row).text()}))
   .filter(x=>x.path?.startsWith('/subtitles/'))
   .sort((a,b)=>Number(/yify|yts/i.test(b.text))-Number(/yify|yts/i.test(a.text)))
}
export function extract(archive) {
 const zip = new AdmZip(archive)
 const entry = zip.getEntries().find(e=>!e.isDirectory && /\.srt$/i.test(e.entryName) && e.header.size<=MAX)
 if(!entry) throw new Error('No supported subtitle file')
 const compressed=entry.getCompressedData()
 const data=entry.header.method===8 ? inflateRawSync(compressed,{maxOutputLength:MAX}) : entry.header.method===0 ? compressed : null
 if(!data || data.length>MAX) throw new Error('Subtitle too large')
 let text=new TextDecoder(data[0]===255 && data[1]===254 ? 'utf-16le':'utf-8').decode(data)
 if(text.includes('\ufffd')) text=new TextDecoder('windows-1252').decode(data)
 if(!/\d{2}:\d{2}:\d{2}[,.]\d{3}\s*-->/.test(text)) throw new Error('Invalid subtitle timing')
 return text.replace(/^\ufeff/,'')
}
export async function subtitles(imdb, language, get=providerFetch) {
 if(!/^tt\d{5,12}$/.test(imdb) || !languages[language]) throw new Error('Invalid subtitle request')
 const key=`${imdb}:${language}`, existing=cache.get(key)
 if(existing && Date.now()-existing.time<6*3600000) return existing.value
 const html=(await get(`https://yts-subs.com/movie-imdb/${imdb}`)).toString()
 for(const lang of [...new Set([language,'en'])]) {
  for(const track of tracks(html,lang).slice(0,3)) {
   try {
    const $=load((await get(new URL(track.path,'https://yts-subs.com'))).toString())
    const encoded=$('#btn-download-subtitle').attr('data-link')
    const href=encoded ? Buffer.from(encoded,'base64').toString() : $('a[href$=".zip"]').attr('href')
    if(!href) continue
    const text=extract(await get(new URL(href,'https://yts-subs.com')))
    const value={language:lang,requestedLanguage:language,text}
    if(cache.size>=32) cache.delete(cache.keys().next().value)
    cache.set(key,{time:Date.now(),value});return value
   } catch { /* Try another release, then English. */ }
  }
 }
 return null
}
