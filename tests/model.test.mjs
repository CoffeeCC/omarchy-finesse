// Runs Model.js (a QML ".pragma library" script) under node.
// Usage: node --test tests/*.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

const src = readFileSync(new URL('../Model.js', import.meta.url), 'utf8').replace(/^\.pragma library\s*$/m, '')
const M = {}
vm.runInNewContext(src, M)

test('urls: scheme, trailing slash, jellyfin fallback to finesse origin', () => {
  assert.equal(M.finesseBase('media.example.com/finesse/'), 'https://media.example.com/finesse')
  assert.equal(M.finesseBase('javascript:alert(1)'), '')
  assert.equal(M.finesseBase('file:///etc/passwd'), '')
  assert.equal(M.finesseBase('media.lan:8096'), 'https://media.lan:8096')
  assert.equal(M.jellyfinBase('', 'https://h.ts.net:10000/finesse'), 'https://h.ts.net:10000')
  assert.equal(M.jellyfinBase('http://192.168.8.120:8096/', 'x'), 'http://192.168.8.120:8096')
  assert.equal(M.playUrl('https://h/finesse', 'abc'), 'https://h/finesse/play/abc')
  assert.equal(M.itemUrl('', 'abc'), '')
})

test('isConfigured needs finesse url and key', () => {
  assert.equal(M.isConfigured('https://h/finesse', '', 'k'), true)
  assert.equal(M.isConfigured('https://h/finesse', '', ' '), false)
  assert.equal(M.isConfigured('', 'https://jf', 'k'), false)
})

test('resumeUrl clamps limit', () => {
  assert.match(M.resumeUrl('https://jf', 'u1', 99), /\/Users\/u1\/Items\/Resume\?Limit=24&/)
  assert.match(M.resumeUrl('https://jf', 'u1', 'x'), /Limit=6&/)
})

test('pickUserId by name, else first enabled', () => {
  const users = JSON.stringify([
    { Id: 'a', Name: 'Admin', Policy: { IsDisabled: true } },
    { Id: 'b', Name: 'Paul' },
  ])
  assert.equal(M.pickUserId(users, 'paul'), 'b')
  assert.equal(M.pickUserId(users, 'nobody'), '')
  assert.equal(M.pickUserId(users, ''), 'b')
  assert.equal(M.pickUserId('not json', ''), '')
})

test('parseResume shapes episodes and movies', () => {
  const raw = JSON.stringify({
    Items: [
      {
        Id: 'e1', Type: 'Episode', Name: 'Pilot', SeriesName: 'Show', ParentIndexNumber: 1, IndexNumber: 2,
        RunTimeTicks: 36000000000, UserData: { PlaybackPositionTicks: 9000000000 }, ImageTags: { Primary: 't1' },
      },
      {
        Id: 'm1', Type: 'Movie', Name: 'Film', ProductionYear: 1999, RunTimeTicks: 72000000000,
        UserData: { PlaybackPositionTicks: 0 }, ImageTags: { Primary: 'p' }, BackdropImageTags: ['bd'],
      },
      { Name: 'no id' },
    ],
  })
  const rows = M.parseResume(raw, 'https://jf')
  assert.equal(rows.length, 2)
  assert.equal(rows[0].title, 'Show')
  assert.equal(rows[0].subtitle, 'S01E02 · Pilot')
  assert.equal(rows[0].progress, 0.25)
  assert.equal(rows[0].remaining, '45m left')
  assert.equal(rows[0].image, 'https://jf/Items/e1/Images/Primary?fillHeight=96&quality=85&tag=t1')
  assert.equal(rows[1].subtitle, '1999')
  assert.equal(rows[1].remaining, '2h left')
  assert.match(rows[1].image, /Images\/Backdrop\?.*tag=bd$/)
  assert.equal(M.parseResume('{"error":1}', 'x'), null)
})
