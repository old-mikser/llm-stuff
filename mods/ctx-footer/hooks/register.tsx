import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

const tokens = atom({ plugin: 'ctx-footer', key: 'tokens' } as const, null)

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
  const { context } = await $.session.usage()
  if (context.tokens != null) {
    await update($, tokens, () => ({ n: context.tokens!, estimated: false }))
    return
  }
  const est = await $.session.usage({ breakdown: 'summary' }).then(u => u.context.breakdown?.totalTokens, () => undefined)
  await update($, tokens, () => (est ? { n: est, estimated: true } : null))
}

async function text($: EngineInterface) {
  const m = await $.session.model().then(label, () => null)
  const t = await read($, tokens)
  return [m, t ? `${t.estimated ? '~' : ''}${(t.n / 1000).toFixed(1)}k` : null].filter(Boolean).join(' · ')
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const r = await next(e)
    await refresh($)
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
      await refresh($)
      $.ui.invalidate('ui.render')
    }
    return r
  })

  on('ui.render', { component: 'SessionMode' }, async ($, e, next) => {
    try {
      const s = await text($)
      if (!s) return next(e)
      return next({ ...e, props: { ...e.props, modes: [...e.props.modes, s] } })
    } catch {
      return next(e)
    }
  })
}
