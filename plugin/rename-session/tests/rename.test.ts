import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

const TOOL = 'mcp__rename-session__rename'

// Stands for the engine's slash commands: keeps every one run.
function commands(on: On) {
  const ran: { command: string; args: string }[] = []
  on('command.run', ($, e) => {
    ran.push({ command: e.command, args: e.args })
    return { text: '' }
  })
  return ran
}

test('the tool queues /rename with the name and answers at once', async ($, on) => {
  const clock = mock.clock(on)
  const ran = commands(on)

  const res = await $.tool.call({ tool: TOOL, name: 'Fix the login flow' } as never)
  const before = ran.length
  await clock.advance(1)

  expect(res.result).toBe('The session will be renamed to "Fix the login flow" when this turn ends.')
  expect(before).toBe(0)
  expect(ran).toEqual([{ command: 'rename', args: 'Fix the login flow' }])
})

test('the name is cut to one printable line', async ($, on) => {
  const clock = mock.clock(on)
  const ran = commands(on)

  await $.tool.call({ tool: TOOL, name: '  Fix\nthe\t login\u001b[31m flow ' } as never)
  await clock.advance(1)

  expect(ran).toEqual([{ command: 'rename', args: 'Fix the login [31m flow' }])
})

test('an empty name is refused and nothing is renamed', async ($, on) => {
  const clock = mock.clock(on)
  const ran = commands(on)

  const res = await $.tool.call({ tool: TOOL, name: ' \n ' } as never)
  await clock.advance(1)

  expect(res.deny).toBe('Give the session a name: a few words on one line.')
  expect(ran).toEqual([])
})
