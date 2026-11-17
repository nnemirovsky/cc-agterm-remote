# cc-agterm-remote

Run Claude Code on a Linux server (or several) and work with it from [agterm](https://github.com/umputun/agterm)
on your Mac as if it ran locally. Sessions keep going while the laptop sleeps, the Claude app on your
phone can start and drive them, and long builds and test suites run on a machine sized for them.

What you get on the Mac:

- **Chords to manage remote sessions.** Pick a session and attach, restart, stop, resume or clean
  up its worktree; start a new one in a directory picked from the server; open a plain shell. With
  several servers the pickers list the sessions of all of them.
- **The agent-status glyph on remote panes**, the same busy / waiting / done dot agterm shows for a
  local session, and Claude's own session name as the pane name, after a mark that says which
  server the pane is on.
- **Ctrl+V pastes a Mac clipboard image** into a remote Claude Code prompt, and Claude's own copy
  goes to the Mac clipboard.
- **Links clicked in a remote session open in the Mac's browser.**
- **Panes that survive a dropped connection**: they reconnect on their own, with backoff.

And on the server:

- **Remote-control servers** (`claude-rc`), the entry points the Claude app creates sessions
  through, as systemd user units, kept on the current Claude Code build by an hourly refresh.
- **A `rename-session` plugin** that lets Claude name its own session.

## Requirements

- macOS with agterm (0.24 tested) and `jq` (`brew install jq`).
- One or more Linux servers with systemd, each reached by `ssh <host>` with key-based login and no
  prompt. A private network such as Tailscale is the sensible way to reach them (see Security).
- On the server: Claude Code (native install, 2.1.301 tested), `jq`, `netcat-openbsd` (or
  `python3`), `expect` for remote-control servers, and bash as your login shell for the automatic
  `~/.bashrc` setup.

Both sides lean on Claude Code behaviour that is not a public interface (the output of `claude
agents --json` and `claude --bg`, background session handling). A Claude Code update can break a
piece of this; the tested versions are above.

## Install

```bash
git clone https://github.com/nnemirovsky/cc-agterm-remote
cd cc-agterm-remote
./install.sh          # writes ~/.config/cc-agterm-remote/config and stops: set CC_REMOTE_HOSTS
./install.sh          # installs the Mac side and the server side on every host
```

The configuration (`config.example` has every key):

```bash
CC_REMOTE_HOSTS=(devbox buildbox)     # the ssh hosts; the first is the default for new sessions
CC_REMOTE_NAMES=("devbox=dev box")    # what pickers call a host (default: the host)
CC_REMOTE_MARKS=("devbox=⧉d")         # what leads its pane names (default: see "Pane names")
CC_REMOTE_ROOTS=(dev src)             # where the new-session picker looks for repos
CC_REMOTE_DIRS=("dev/work=work root") # extra picker rows, path=label
```

A configuration from before `CC_REMOTE_HOSTS`, with a single `CC_REMOTE_HOST` (and
`CC_REMOTE_NAME`), still works. See "Several servers" for adding one.

`install.sh` puts the scripts into `~/.local/bin` on both machines. On the Mac it starts two launchd
agents, `cc-agterm-remote.bridge` and `cc-agterm-remote.clipboard`, and appends the chords to
`~/.config/agterm/keymap.conf`. On the server it adds the status hooks to `~/.claude/settings.json`,
the `claude-rc` units to `~/.config/systemd/user`, and small blocks to `~/.bashrc` and
`~/.tmux.conf`. Everything it adds to a file of yours sits between `cc-agterm-remote` markers. Run it
again after pulling a new version; `./install.sh uninstall` takes it all out (`--mac` or `--server`
for one side, `--host <host>` for one server).

The plugin is installed separately, on both machines:

```bash
claude plugin marketplace add nnemirovsky/cc-agterm-remote
claude plugin install rename-session@cc-agterm-remote
```

## The chords

| chord | what |
|---|---|
| `cmd+shift+r` | Manage remote sessions: pick one, then attach / restart / kill / clean up / cancel. Stopped sessions sit under a separator, most recently active first, and resume. |
| `cmd+shift+h` | New remote Claude Code session: with several servers, pick one (the first is the default), then a directory there from a picker or a typed path. |
| `cmd+shift+k` | From inside an attached pane: restart its session, or stop it and close the pane, optionally removing its worktree and branch. |
| `cmd+shift+s` | New plain ssh shell on a server, same server and directory pickers. |
| `cmd+shift+v` | Paste a clipboard image by uploading it and typing its path (the fallback for Ctrl+V). |
| `cmd+shift+i` | Show the image whose path is selected (or copied), from the Mac or the server. |
| `cmd+v` | Paste as usual, but with only an image on the clipboard send Ctrl+V, which is how Claude Code pastes an image. In the quick terminal it types single-line text and refuses multi-line text, since agterm can only type there and each line would run. |

They also show up by name in agterm's Navigate ▸ Custom Commands (`ctrl+shift+O`). The same actions
are available from a terminal: `cc-remote-attach --help`.

## Sessions

Sessions are Claude Code **background sessions** (`claude --bg`, managed with `claude agents`,
`attach`, `stop`). They survive the ssh connection, the Claude app can reach them, and the server's
supervisor retires idle ones after about an hour without losing them: they show under the picker's
`stopped` separator and resume with the conversation intact.

- **Attach** opens a pane running `ssh -t <host> claude attach <id>` and records which pane shows
  which session, for the status bridge. Closing the pane leaves the session running. An attached
  background session always renders fullscreen; `cc-remote-attach --direct <dir>` runs a plain
  `claude` in tmux instead, for the classic renderer, at the cost of `claude agents` management.
- **Restart** stops the process, waits for it to exit, resumes the session under the same id and
  swaps the pane for a new one in the same spot. It picks up plugin, settings and Claude Code
  updates. Claude gets a note as its next prompt that its background shells, monitors and
  subagents were terminated, so it starts again whichever still matter; that turn lights no status
  dot or badge. **Resume** does the same for a stopped or crashed session.
- **Clean up** is offered only when nothing would be lost: in a linked worktree it removes the
  worktree and its branch, in a repo's main checkout on another branch it switches to the default
  branch and deletes that one. It needs no changes to tracked files and every commit either merged
  into the default branch or pushed. Untracked files don't block it; the row names them.
- **Sessions the Claude app started** against a remote-control server show as `from app` rows.
  Attaching one takes it over (experimental): its process is stopped and the session resumed as a
  background session under the same id, which the app still reaches. Claude gets a note about it;
  `CC_REMOTE_NO_TAKEOVER_NOTE=1` leaves it out.
- **Headless runs** (`claude --print`, such as the reviewers a review tool starts inside a session)
  are left out of the pickers, although `claude agents` lists them.
- **Plain shells** (`cmd+shift+s`) follow the remote shell's title, which the `~/.bashrc` block marks
  with the server's mark, `⧉ ~/dir`. A `claude` started by hand in one still reports to its pane,
  through `CC_REMOTE_PANE`.

## Pane names

Remote panes are named `⧉ ✳ <session name>`: `⧉` marks remote, `✳` marks Claude. The bridge
relabels a pane when Claude names its session.

With several servers the mark also says which server: each gets the circled first letter of its
name, so with `CC_REMOTE_HOSTS=(torvalds ritchie)` panes read `ⓣ ✳ <session name>` and
`ⓡ ✳ <session name>`, and shells `ⓣ ~/dir`. When two servers share a first letter, the later one
takes the next letter of its name that is still free (`tesla` after `torvalds` is `ⓔ`), and a
server with no letter left gets `⧉` and its first letter. `CC_REMOTE_MARKS` picks them yourself,
in any style:

```bash
CC_REMOTE_MARKS=("torvalds=⧉t" "ritchie=⧉r")
```

A mark is one word without quotes, backslashes, `$`, `` ` `` or `!`; `install.sh` refuses another.
The session pickers open with a legend row (`ⓣ torvalds · ⓡ ritchie`) and lead each session with
its server's mark and name, and the new-session and new-shell server picker lists each server
after its mark. `cc-remote-bridge --once` prints the marks too.

The Mac names Claude panes, so a changed mark reaches them on its own: the bridge renames every
attached pane to its server's current mark within a minute, panes named `⧉ ✳ …` before there were
marks included. A shell's title comes from the server's `~/.bashrc`, so after changing the marks
(or adding a server) run `./install.sh` again for the servers, and shells opened before that keep
their old mark until they are reopened.

## Several servers

List them in `CC_REMOTE_HOSTS`. Everything else follows:

- **The pickers ask every server at once** and lead each row with its host's mark and name (see
  "Pane names"). A server that does not answer within `CC_REMOTE_CONNECT_TIMEOUT` seconds (5)
  shows as an `unavailable` row; the others list as usual.
- **Every action goes to the session's own server**: attach, restart, resume, kill, clean up, take
  over, the stop chord, and `cmd+shift+v` / `cmd+shift+i`, which find the server in the pane's ssh
  command. `cc-remote-attach <host>:<id>` names one from a terminal; a bare id is looked up on
  every server.
- **New sessions and shells ask for the server first**, the first one in the list on top, and the
  directory picker then lists that server's directories. `cc-remote-attach --host <host> --new`
  skips the question, so a chord per server is one line in the keymap.
- **A session moved to another server** keeps its id. Its stopped copy on the old server is hidden
  while it runs on the new one, and one stopped on both shows once, where it was active last.
- **The bridge keeps one connection per server**, each reconnecting on its own, and forwards the
  clipboard socket to each.

The pane map records each pane as `<host>:<id>`. Panes and map entries from before `CC_REMOTE_HOSTS`
carry no host and belong to `CC_REMOTE_HOST`, so keep that set to the old server while such panes
are open:

```bash
CC_REMOTE_HOSTS=(newbox oldbox)
CC_REMOTE_HOST=oldbox                 # the server older panes run on
```

To add a server, put it in `CC_REMOTE_HOSTS` and run `./install.sh --host <host>` for its server
side, then `./install.sh --mac` (or reload the bridge:
`launchctl kickstart -k gui/$(id -u)/cc-agterm-remote.bridge`) so the bridge connects to it. Going
from one server to two changes the first one's mark from `⧉` too, as does putting a new server
ahead of one whose letter it shares: then run `./install.sh --server` for all of them.
Remote-control servers (`claude-rc add`) are per server; the app lists them as `<host>-<name>`.

## How the pieces fit

```
Mac (agterm)                                       server
────────────                                       ──────
chords ─ cc-remote-attach ──────ssh─────────────▶ claude agents / attach / stop / --bg --resume
pane   ─ cc-remote-ssh (reconnects) ─ssh -t─────▶ claude attach <id>

cc-remote-bridge ◀────ssh tail -F, per server─── ~/.cache/cc-agterm-remote/status.jsonl
  │   (launchd)                                      ▲
  └─ agtermctl session status                        └─ cc-remote-status (Claude Code hooks)

cc-remote-clipboard ◀═ the bridge's ssh -R ═════ ~/.cache/cc-agterm-remote/clipboard.sock
  (launchd socket)                                   ▲
                                                     ├─ xclip stand-in (Ctrl+V, copy)
                                                     └─ cc-remote-open (BROWSER, links)

phone / claude.ai ─────────────────────────────▶ claude-rc@<name> (systemd, claude remote-control)
```

**Status.** Claude Code hooks on the server append `{session_id, state}` lines to a journal, and the
bridge tails it over one persistent ssh connection per server and paints the pane that shows that
session.
The mapping lives on the Mac, because a phone-started session or a background daemon has no
`AGTERM_*` environment to report a pane with.

**Clipboard and links.** Claude Code on Linux pastes an image by running `xclip`. The server gets a
stand-in `xclip` that asks the Mac over a Unix socket the bridge forwards, answered by
`cc-remote-clipboard` (`osascript` and `pbcopy`, nothing extra installed). `BROWSER` on the server
is `cc-remote-open`, which asks the Mac to `open` an http(s) link the same way, so a link clicked in
an attached session opens in your browser, as do `gh auth login --web` and OAuth prompts. With the
bridge down both fail fast. A machine that has a real `xclip` keeps it.

**Images in the terminal.** `cmd+shift+i` hands the path to the
[inline-images](https://github.com/nnemirovsky/cc-inline-images) plugin when the session runs it,
which draws the image inside Claude Code; otherwise it opens agterm's image overlay, copying a remote
file over first. Background sessions need `CLAUDE_CODE_FORCE_TERMINAL_IMAGES=1` in the `env` block
of the server's `~/.claude/settings.json` to draw images at all.

## Remote-control servers

The Claude app (phone, claude.ai/code) creates sessions on your server through a `claude
remote-control` server running in a directory. `claude-rc` makes each one a systemd user unit:

```bash
claude-rc add hub ~/dev/hub          # claude-rc@hub.service, listed in the app as <host>-hub
claude-rc list
claude-rc env hub                    # the app's environment id (changes on every restart)
claude-rc remove hub
loginctl enable-linger "$USER"       # keep them running while you are logged out (may need sudo)
```

`add` records the directory and your login shell's `PATH` in
`~/.config/cc-agterm-remote/rc/<name>.env`, marks the directory trusted (a server has no terminal
for the trust dialog) and starts the unit under `expect`, which answers the one-time "Enable Remote
Control?" prompt. Servers start with `--no-create-session-in-dir`, so they idle until the app asks
for a session. The new-session picker lists their directories first.

A server keeps running the binary it started with, while the native updater only re-points
`~/.local/bin/claude`. Left alone, a server drifts for weeks, misses new models, and dies when its
credential expires about 30 days after start. `claude-rc-refresh`, run hourly by a timer, finds
every `claude remote-control` process of yours, maps it to its unit through its cgroup, and
restarts the ones on an old build. Restarting a unit kills the sessions the app spawned inside it,
so a unit hosting one waits until that session has been quiet for `RC_IDLE_HOURS` (8). A server
running outside systemd is reported as an orphan.

```bash
DRY_RUN=1 claude-rc-refresh          # what it would do
RC_FORCE=1 claude-rc-refresh         # ignore the idle guard
journalctl --user -u claude-rc-refresh -n 20
```

Work meant to outlive a server restart belongs in a background session: `claude --bg
--remote-control <name> "<task>"` registers a session the app can open, but runs in the background
daemon rather than under the server.

## The rename-session plugin

Claude cannot rename its own session: `/rename` is typed by a person and `--name` applies only at
launch. The plugin adds a tool, `mcp__rename-session__rename`, that runs the real `/rename` when
the current turn ends. That updates the terminal title, `claude agents`, the `/resume` picker and
the Claude app together. Ask for it in a skill or a prompt ("name this session after the ticket").

## Security

- **The clipboard and link sockets are yours only.** On the Mac the launchd socket is mode 0600 in
  `~/.config/cc-agterm-remote` (0700). On the server the forwarded socket is owner-only (sshd's
  default `StreamLocalBindMask`) in `~/.cache/cc-agterm-remote` (0700). Anyone who can act as your
  user on the server can still read your Mac clipboard's image, set its text and open http(s) links
  while the bridge is connected; that is the feature.
- **`cc-remote-open` and the clipboard server accept only http(s) URLs without spaces or control
  characters**, and nothing else is run on the Mac.
- **Keep ssh off the public internet** where you can. A tailnet with the firewall closing everything
  else, key-only login and no root login is a good baseline.
- Remote commands quote every path and argument they pass.

## Troubleshooting

Each of these cost real time once.

- **`--resume` needs the full session uuid.** The 8-character short id forks a copy under a new id.
  So does resuming a session whose process is still exiting, which is why restart waits for it.
- **The first background session after a plugin update can run the old plugin.** The daemon keeps a
  pre-warmed spare process, with plugins already loaded, and `--bg` / `--resume` claim it. Restart
  once more.
- **A chord that does nothing failed silently.** Custom commands run under a bare `/bin/sh` with
  stderr going nowhere; the scripts post a notification on failure, so silence means the chord never
  fired. Remote paths in the keymap must be absolute: a `~` there expands on the Mac.
- **The first interactive `claude` on a fresh server runs the onboarding wizard**, even when it is
  logged in. `-p`, `--bg` and remote-control skip it. Run `claude` once over `ssh -t`.
- **Interactive logins need a real TTY** (Claude Code, `gh`, codex): `ssh -t <host> '<login command>'`.
  `BROWSER=true` stops `gh` launching a text browser that waits at a prompt.
- **An orphaned `claude remote-control`** (started by hand) lists its directory twice in the app and
  ignores SIGTERM: `kill -9` it. `claude-rc-refresh` reports one.
- **`pkill -f <pattern>` over ssh matches your own ssh command line** and kills it. Use the bracket
  trick: `pkill -f "[c]laude attach"`.
- **An unsent draft lives only in the session's memory.** To clear one, attach in tmux and overwrite
  it with a single space; an empty box comes back after a reattach.
- **Long work in background shells**: `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1` stops Claude Code
  killing an idle session's background shells under memory pressure, and `BASH_MAX_TIMEOUT_MS`
  raises their 2-hour limit. Both go in the server's settings `env` block and apply to new sessions.
- **The bridge**: `cc-remote-bridge --once` prints the configuration, the servers and the pane map;
  its log is `~/.config/cc-agterm-remote/bridge.log`, and
  `launchctl kickstart -k gui/$(id -u)/cc-agterm-remote.bridge` restarts it.

## License

MIT
