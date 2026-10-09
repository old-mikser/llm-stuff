export type Tokens = { n: number; estimated: boolean } | null

declare module 'claude-code' {
  interface PluginState {
    'ctx-footer': { tokens: Tokens }
  }
}
