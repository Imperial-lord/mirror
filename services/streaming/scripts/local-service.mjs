// macOS development launcher. launchd owns the service independently of a terminal/chat.
import {mkdirSync, writeFileSync} from 'node:fs'
import {fileURLToPath} from 'node:url'
import {resolve} from 'node:path'
import {spawnSync} from 'node:child_process'

if (process.platform !== 'darwin') throw new Error('Use npm start or Docker outside macOS')
const root = fileURLToPath(new URL('../', import.meta.url))
const runtime = resolve(root, '.runtime')
const label = 'com.mirror.playback.local'
const domain = `gui/${process.getuid()}`
const target = `${domain}/${label}`
const action = process.argv[2] ?? 'status'
const run = (...args) => spawnSync('/bin/launchctl', args, {encoding:'utf8'})
if (action === 'stop') {
  const result = run('bootout', target)
  if (result.status !== 0 && run('print', target).status === 0) throw new Error(result.stderr)
  console.log('Local playback service stopped')
} else if (action === 'start') {
  mkdirSync(runtime, {recursive:true})
  const xml = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
  const plist = resolve(runtime, 'service.plist')
  writeFileSync(plist, `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>${label}</string>
<key>ProgramArguments</key><array><string>${xml(process.execPath)}</string><string>${xml(resolve(root, 'server.mjs'))}</string></array>
<key>WorkingDirectory</key><string>${xml(root)}</string>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>10</integer>
<key>StandardOutPath</key><string>${xml(resolve(runtime, 'service.log'))}</string>
<key>StandardErrorPath</key><string>${xml(resolve(runtime, 'service.log'))}</string>
</dict></plist>`)
  if (run('print', target).status !== 0) {
    const result = run('bootstrap', domain, plist)
    if (result.status !== 0) throw new Error(result.stderr)
  }
  console.log('Local playback service managed by launchd; logs: ' + resolve(runtime, 'service.log'))
} else if (action === 'status') {
  const result = run('print', target)
  console.log(result.status === 0 ? result.stdout : 'Local playback service is not running')
} else throw new Error('Usage: node scripts/local-service.mjs start|stop|status')
