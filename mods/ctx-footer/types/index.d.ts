export type Tokens = number | null

declare module 'claude-code' {
  interface PluginState {
    'ctx-footer': { tokens: Tokens }
  }
}
