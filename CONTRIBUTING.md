# Contributing

Thanks for looking at `cc-agterm-remote`. This covers the dev loop, the tests and how changes land.

## Dev loop

Most of the repo is bash that `install.sh` copies into `~/.local/bin`: `mac/` for the Mac, `server/` for the servers. After an edit, install the side you changed again:

```
./install.sh --mac               # also restarts the bridge and clipboard agents
./install.sh --server            # every server, or --host <host> for one
```

`cc-remote-bridge --once` prints the configuration, the servers and the pane map. The bridge logs to `~/.config/cc-agterm-remote/bridge.log`. Chords run under a bare `/bin/sh` with stderr going nowhere, so try a script from a terminal first.

The `rename-session` plugin lives in `plugin/rename-session`. Load it from the working tree instead of through the marketplace:

```
claude --plugin-dir /path/to/cc-agterm-remote/plugin/rename-session
```

It is a function-hook mod in `hooks/register.ts`. Claude Code watches a `--plugin-dir` folder and reloads the mod when a file in it changes.

## Tests

```
claude plugin validate .
claude plugin validate plugin/rename-session
claude plugin test plugin/rename-session
```

The first checks the marketplace manifest at the root, the other two the plugin and its tests in `plugin/rename-session/tests/`. CI runs all three on every PR.

The shell scripts have no test suite. Lint them before opening a PR (`server/bin/claude-rc-start` is an expect script, so it is left out):

```
shellcheck --severity=error install.sh mac/bin/* server/bin/cc-remote-* server/bin/xclip server/bin/claude-rc server/bin/claude-rc-refresh
```

## Pull requests

- Open a PR against `main`. Direct pushes are blocked.
- CI must be green and every review thread resolved before a PR can merge.
- PRs are squash-merged, and the PR title becomes the commit subject, so write it as a commit message.
- Bump `version` in `plugin/rename-session/.claude-plugin/plugin.json` in the PR that should ship a new plugin release.

## Commits

Scoped conventional commits with a lowercase description:

```
feat(scope): add the thing
fix(scope): stop doing the wrong thing
```
