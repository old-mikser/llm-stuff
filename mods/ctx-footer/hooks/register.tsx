import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

const tokens = atom({ plugin: 'ctx-footer', key: 'tokens' } as const, null)
const effort = atom({ plugin: 'ctx-footer', key: 'effort' } as const, null)

const CACHE_TTL_MS = 60 * 60_000
const COLD = '#87cefa'

const CYCLE_TIP = /\([^)]*to cycle\)/
const KEY_HINT = /\b(to|for)\b/

// "claude-opus-5-5" -> "Opus 5.5"
const label = (id: string) => {
  const m = id.match(/^claude-([a-z]+)-(\d+)(?:-(\d+))?/)
  if (!m) return id
  const [, family = '', major, minor] = m
  const name = family.charAt(0).toUpperCase() + family.slice(1)
  return minor ? `${name} ${major}.${minor}` : `${name} ${major}`
}

// Before the first API response of a window (fresh session, /clear, compaction) the engine has no
// measured fill, so fall back to /context's local estimate, which sends no requests.
async function refresh($: EngineInterface) {
  const n = (await $.session.usage()).context.tokens
  if (n != null) {
    await update($, tokens, () => ({ n, estimated: false }))
    return
  }
  const est = await $.session.usage({ breakdown: 'summary' }).then(u => u.context.breakdown?.totalTokens, () => undefined)
  await update($, tokens, () => (est ? { n: est, estimated: true } : null))
}

const lastResponseKey = async ($: EngineInterface) => `last-response:${await $.session.id()}`

const ASSISTANT_ROW = '"type":"assistant"'

// Responses from before this mod recorded them live only in the transcript.
async function transcriptLastResponse($: EngineInterface) {
  const base = (await $.env.get('CLAUDE_CONFIG_DIR')) ?? `${await $.env.get('HOME')}/.claude`
  const slug = (await $.session.cwd()).replace(/[^a-zA-Z0-9]/g, '-')
  const log = await $.fs.read(`${base}/projects/${slug}/${await $.session.id()}.jsonl`)
  const row = log.lastIndexOf(ASSISTANT_ROW)
  if (row < 0) return undefined
  const start = log.lastIndexOf('\n', row) + 1
  const end = log.indexOf('\n', row)
  const stamp = log.slice(start, end < 0 ? undefined : end).match(/"timestamp":"([^"]+)"/)?.[1]
  const at = stamp ? Date.parse(stamp) : NaN
  return Number.isNaN(at) ? undefined : at
}

async function isCold($: EngineInterface) {
  const key = await lastResponseKey($)
  let at = await $.store.get(key)
  if (typeof at !== 'number') {
    at = await transcriptLastResponse($).catch(() => undefined)
    if (typeof at !== 'number') return true
    await $.store.set(key, at)
  }
  return (await $.clock.now()) - at > CACHE_TTL_MS
}

let lastEffort: string | null = null

// Until the first `turn.step` of a resumed or cleared session, the last seen effort, else settings'.
async function fallbackEffort($: EngineInterface) {
  const configured = (await $.settings.read()).effortLevel
  const level = lastEffort ?? (typeof configured === 'string' ? configured : null)
  if (level) await update($, effort, prev => prev ?? level)
}

function reseed($: EngineInterface, delays: number[]) {
  for (const ms of delays)
    $.clock.after(ms, () => {
      void fallbackEffort($)
        .catch(() => {})
        .then(() => refresh($))
        .then(() => $.ui.invalidate('ui.render'))
    })
}

const firstTurnKey = async ($: EngineInterface) => `first-turn:${await $.session.id()}`

// Counts from the first prompt; a session with turns from before this record falls back to its launch.
async function elapsed($: EngineInterface) {
  const key = await firstTurnKey($)
  const stored = await $.store.get(key)
  let since: number
  if (typeof stored === 'number') since = stored
  else {
    if ((await $.session.turns()) === 0) return 'new'
    since = (await $.session.usage()).startedAt
    await $.store.set(key, since)
  }
  const m = Math.floor(((await $.clock.now()) - since) / 60_000)
  return m < 60 ? `${m}m` : `${Math.floor(m / 60)}h ${m % 60}m`
}

async function segments($: EngineInterface) {
  const m = await $.session.model().then(label, () => null)
  const t = await read($, tokens)
  const f = await read($, effort)
  const fill = t ? `${t.estimated ? '~' : ''}${(t.n / 1000).toFixed(1)}k` : null
  return { head: [m, f].filter(Boolean).join(' '), fill }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const r = await next(e)
    await fallbackEffort($).catch(() => {})
    await refresh($)
    // On `--resume` the transcript can land after this hook, so the first read sees no window yet.
    reseed($, [1_000, 5_000])
    $.clock.every(60_000, () => void refresh($).then(() => $.ui.invalidate('ui.render')))
    return r
  })

  // A `/clear` or in-process resume starts a new session with empty state and no `session.start`.
  on('session.end', async ($, e, next) => {
    const r = await next(e)
    if (e.reason === 'clear' || e.reason === 'resume') reseed($, [200, 1_000, 5_000])
    return r
  })

  on('turn.start', async ($, e, next) => {
    const key = await firstTurnKey($)
    if (typeof (await $.store.get(key)) !== 'number') {
      await $.store.set(key, await $.clock.now())
      $.ui.invalidate('ui.render')
    }
    return next(e)
  })

  on('session.measure', async ($, e, next) => {
    await refresh($)
    $.ui.invalidate('ui.render')
    return next(e)
  })

  on('turn.step', async function* ($, e, next) {
    const r = yield* next(e)
    if (!e.agentId) {
      await $.store.set(await lastResponseKey($), await $.clock.now())
      lastEffort = e.effort == null ? null : String(e.effort)
      await update($, effort, () => lastEffort)
      await refresh($)
      $.ui.invalidate('ui.render')
    }
    return r
  })

  on('ui.render', { component: 'SessionMode' }, async ($, e, next) => {
    try {
      const { head, fill } = await segments($)
      if (!head && !fill) return next(e)
      if (!fill) return next({ ...e, props: { ...e.props, modes: [...e.props.modes, head] } })
      const cold = await isCold($)
      const { Text } = $.ui.resolve(e)
      const lead = [...e.props.modes, head].filter(Boolean).join(' & ')
      return (
        <Text dimColor wrap="truncate">
          {lead ? `${lead} · ` : ''}
          {cold ? <Text color={COLD}>{fill}</Text> : fill}
        </Text>
      )
    } catch {
      return next(e)
    }
  })

  // A rewritten hint is plain text, so while a pill shows (the agents pill opens the background
  // tasks, monitors among them) the engine's line stays live and the time goes in `tail`.
  on('ui.render', { component: 'PromptHint' }, async ($, e, next) => {
    const time = await elapsed($).catch(() => null)
    const parts = e.props.hint
      .split('·')
      .map(part => part.replace(CYCLE_TIP, '').trim())
      .filter(Boolean)
    if (parts.some(part => !KEY_HINT.test(part)))
      return next(time ? { ...e, props: { ...e.props, tail: time } } : e)
    return next({ ...e, props: { ...e.props, hint: [time, ...parts].filter(Boolean).join(' · ') } })
  })
}
