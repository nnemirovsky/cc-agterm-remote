# Privacy policy

cc-agterm-remote runs on your Mac and on your own servers. It has no server of its own and collects no telemetry. Nothing is sent to the author or to any third party.

## What it reads

On the Mac:

- The clipboard, when a remote Claude Code session asks for it: whether it holds an image, the image itself on Ctrl+V or `cmd+shift+v`, and nothing else. Text is only ever written to it.
- An image file you pass to `cc-remote-paste-image --file` or select for `cmd+shift+i`.
- agterm's pane list and the pane selection, through `agtermctl`.
- Its config, `~/.config/cc-agterm-remote/config`.

On a server:

- The session id and working directory from what Claude Code passes to the status hook. The rest of the hook input is ignored.
- The output of `claude agents --json`, and the names and modification times of the transcripts in `~/.claude/projects`, never their contents.
- The directories under `CC_REMOTE_ROOTS`, for the new-session picker, and the git state of a session's directory when you ask to clean it up.
- Your `claude remote-control` processes and their cgroups, for `claude-rc-refresh`.

The `rename-session` plugin reads only the name Claude passes to its tool.

## What it writes

On the Mac:

- The scripts in `~/.local/bin`, two launchd agents in `~/Library/LaunchAgents`, and the chords in a marked block of `~/.config/agterm/keymap.conf`.
- `~/.config/cc-agterm-remote/`: the config, the pane maps (`map.json`, `live-panes.json`), `bridge.log` and the clipboard socket.
- Short-lived files under `$TMPDIR`: a clipboard image on its way to a server, and images fetched from a server for display.
- The clipboard, when Claude Code on a server copies text.
- Pane names and status glyphs in agterm, through `agtermctl`.

On a server:

- The scripts in `~/.local/bin` and the `claude-rc` units in `~/.config/systemd/user`.
- `~/.cache/cc-agterm-remote/`: the status journal (`status.jsonl`, cut back to 500 lines past 5000), the forwarded clipboard socket, and pasted images, which are pruned after 7 days.
- The status hooks in `~/.claude/settings.json`, and marked blocks in `~/.bashrc` and `~/.tmux.conf`.
- For each remote-control server: `~/.config/cc-agterm-remote/rc/<name>.env` with its directory and your `PATH`, and the directory's trust flag in `~/.claude.json`.

`./install.sh uninstall` removes the scripts, agents, units, hooks and marked blocks. It keeps your config, the pane map, `bridge.log`, the status journal and pasted images, and keeps the remote-control units while you still have servers (`claude-rc remove` them first). The `rename-session` plugin writes nothing: it runs Claude Code's own `/rename`.

## Where it sends data

Only between your Mac and your servers, over your own ssh connections: session status lines, the clipboard image or text a session asks for, links to open, images you paste or show, and the commands behind each chord.

`claude-rc` runs Claude Code's own `claude remote-control`, which talks to Anthropic like any Claude Code session. That traffic is Claude Code's, under Anthropic's terms, not this project's.

## Contact

Questions go to [GitHub issues](https://github.com/nnemirovsky/cc-agterm-remote/issues).
