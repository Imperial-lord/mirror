import {mkdirSync, readFileSync, renameSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'

export const maxPerAccount = 325
const maxAccounts = 50

export function movieIDs(value) {
  if (!Array.isArray(value) || value.length > maxPerAccount ||
      value.some(id => !Number.isSafeInteger(id) || id < 1)) throw new Error('Invalid movie IDs')
  return [...new Set(value)]
}

export function pendingClips(wanted, stored, failures) {
  const failureTime = id => failures[id]?.at ?? failures[id] ?? 0
  return [...wanted].filter(id => !stored.has(id))
    .sort((a, b) => failureTime(a) - failureTime(b))
}

export function createState(directory) {
  mkdirSync(directory, {recursive: true})
  const read = (name, fallback) => {
    try { return JSON.parse(readFileSync(join(directory, name), 'utf8')) }
    catch (error) { if (error.code === 'ENOENT') return fallback; throw error }
  }
  const write = (name, value) => {
    const path = join(directory, name)
    writeFileSync(`${path}.tmp`, JSON.stringify(value), {mode: 0o600})
    renameSync(`${path}.tmp`, path)
  }
  return {
    record(account, ids, now = Date.now()) {
      const requests = read('requests.json', {})
      const accounts = Object.keys(requests)
      if (!Object.hasOwn(requests, account) && accounts.length >= maxAccounts) {
        const oldest = accounts.reduce((first, id) =>
          requests[id].updatedAt < requests[first].updatedAt ? id : first)
        delete requests[oldest]
      }
      requests[account] = {ids, updatedAt: now}
      write('requests.json', requests)
    },
    catalog: () => read('catalog.json', null),
    recordCatalog: rows => write('catalog.json', rows),
    rows() {
      const reports = Object.entries(read('requests.json', {}))
        .map(([account, request]) => [account, {'reported-home': request.ids}])
      return Object.fromEntries([['catalog', read('catalog.json', {})], ...reports])
    },
    wanted() {
      const reported = Object.values(read('requests.json', {})).map(request => request.ids)
      const catalog = Object.values(read('catalog.json', {}))
      const rows = [...reported, ...catalog]
      const ids = new Set()
      const longest = Math.max(0, ...rows.map(row => row.length))
      for (let index = 0; index < longest; index++) {
        for (const row of rows) {
          if (row[index] !== undefined) ids.add(row[index])
        }
      }
      return ids
    },
    clips: () => read('clips.json', []),
    publish: ids => write('clips.json', [...ids]),
    failures: () => read('failures.json', {}),
    saveFailures: failures => write('failures.json', failures),
  }
}
