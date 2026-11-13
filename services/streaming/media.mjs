// Release request slots on socket close, even when an upstream iterator never settles.
export async function serveVideo(req, res, session, range, window = 4 * 1024 * 1024) {
  if (req.method !== 'HEAD' && session.active >= 4) {
    res.writeHead(503, {'Content-Type':'application/json'})
    return res.end(JSON.stringify({error:'Playback capacity reached'}))
  }
  const start = range?.start ?? 0, end = range?.end ?? session.file.length - 1
  const headers = {'Content-Type':'video/mp4', 'Accept-Ranges':'bytes', 'Cache-Control':'private, no-store', 'Content-Length':end-start+1}
  if (range) headers['Content-Range'] = `bytes ${start}-${end}/${session.file.length}`
  res.writeHead(range ? 206 : 200, headers)
  if (req.method === 'HEAD') return res.end()
  session.active++
  let stream, released = false
  const release = () => {
    if (released) return
    released = true
    session.active--
    session.touched = Date.now()
    stream?.destroy()
    res.off('close', release)
  }
  res.on('close', release)
  res.setTimeout(60_000, () => res.destroy())
  try {
    for (let offset = start; offset <= end && !res.destroyed; offset += window) {
      stream = session.file.createReadStream({start:offset, end:Math.min(end, offset+window-1)})
      for await (const chunk of stream) {
        if (res.destroyed) break
        if (!res.write(chunk)) await new Promise(resolve => {
          const done = () => { res.off('drain', done); res.off('close', done); resolve() }
          res.once('drain', done); res.once('close', done)
        })
      }
      session.touched = Date.now()
    }
    res.end()
  } catch (error) {
    if (!res.destroyed) console.warn('Media read failed:', error.code ?? error.message)
    res.destroy()
  } finally { release() }
}
