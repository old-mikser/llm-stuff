import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

const tokens = atom({ plugin: 'ctx-footer', key: 'tokens' } as const, null)
const effort = atom({ plugin: 'ctx-footer', key: 'effort' } as const, null)

const CACHE_TTL_MS = 60 * 60_000
const COLD = '#87cefa'

const CYCLE_TIP = /\([^)]*to cycle\)/
const AGENTS_PILL = /^←\s*\d+\s+agents?$/

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

// A resumed session has no `turn.step` yet, so the effort comes from settings until the first turn.
async function fallbackEffort($: EngineInterface) {
  const level = (await $.settings.read()).effortLevel
  if (typeof level === 'string') await update($, effort, prev => prev ?? level)
}

async function elapsed($: EngineInterface) {
  const { startedAt } = await $.session.usage()
  const m = Math.floor(((await $.clock.now()) - startedAt) / 60_000)
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
    for (const ms of [1_000, 5_000]) $.clock.after(ms, () => void refresh($).then(() => $.ui.invalidate('ui.render')))
    $.clock.every(60_000, () => void refresh($).then(() => $.ui.invalidate('ui.render')))
    return r
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
      await update($, effort, () => (e.effort == null ? null : String(e.effort)))
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

  // A rewritten hint is drawn as plain text after `<mode> · `, so its pills stop being clickable.
  on('ui.render', { component: 'PromptHint' }, async ($, e, next) => {
    const parts = e.props.hint
      .split('·')
      .map(part => part.replace(CYCLE_TIP, '').trim())
      .filter(part => part && !AGENTS_PILL.test(part))
    const time = await elapsed($).catch(() => null)
    return next({ ...e, props: { ...e.props, hint: [time, ...parts].filter(Boolean).join(' · ') } })
  })
}
