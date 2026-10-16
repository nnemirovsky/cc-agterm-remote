import type { Register } from 'claude-code'

// Claude cannot rename its own session: /rename is typed by a person, and
// --name applies at launch only. This mod gives it a tool that runs the real
// /rename, which updates everything that shows the name at once: the terminal
// title, `claude agents`, the /resume picker and the Claude app.
//
// A slash command cannot run inside the turn that asked for it (the engine
// refuses a plugin's command run from a hook the turn is waiting on), so the
// tool queues it and answers at once; the engine runs it when the turn ends.

const TOOL = 'rename'
const MAX = 120

// The name as one printable line, or undefined when nothing is left.
function clean(raw: unknown): string | undefined {
  if (typeof raw !== 'string') return undefined
  const name = raw.replace(/[\u0000-\u001f\u007f]+/g, ' ').replace(/\s+/g, ' ').trim().slice(0, MAX).trim()
  return name || undefined
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const res = await next(e)
    await $.tool
      .register({
        name: TOOL,
        description:
          'Renames this Claude Code session: the name its terminal title, the session list, the /resume picker and the Claude app show. ' +
          'Use a few words that say what the session works on. The rename takes effect when the current turn ends.',
        inputSchema: {
          type: 'object',
          properties: { name: { type: 'string', description: 'The new session name, a few words on one line.' } },
          required: ['name'],
        },
      })
      .catch(() => undefined)
    return res
  })

  on('tool.call', { tool: 'mcp__rename-session__rename' }, async ($, e) => {
    const name = clean((e as unknown as { name?: unknown }).name)
    if (!name) return { deny: 'Give the session a name: a few words on one line.' }
    $.clock.after(0, () => {
      void $.command.run({ command: 'rename', args: name }).catch(() => undefined)
    })
    return { result: `The session will be renamed to "${name}" when this turn ends.` }
  })
}
