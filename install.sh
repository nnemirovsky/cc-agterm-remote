#!/usr/bin/env bash
# Install cc-agterm-remote on this Mac and on the servers named in
# ~/.config/cc-agterm-remote/config. Run it again after pulling a new version.
#
#   ./install.sh                 install both sides
#   ./install.sh --mac           only this Mac
#   ./install.sh --server        only the servers
#   ./install.sh --host H        of the servers, only H (with or without --server)
#   ./install.sh uninstall       remove both sides (add --mac or --server for one)
#
# On the Mac: the scripts into ~/.local/bin, two launchd agents (the bridge and
# the clipboard socket) and a block of chords at the end of
# ~/.config/agterm/keymap.conf.
# On the server: the scripts into ~/.local/bin, the status hooks into
# ~/.claude/settings.json, the claude-rc units into ~/.config/systemd/user, and
# marked blocks in ~/.bashrc and ~/.tmux.conf. Everything it adds to a file of
# yours sits between "cc-agterm-remote" markers, which uninstall removes.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
action=install mac=1 server=1 only=""
while [ $# -gt 0 ]; do
    case "$1" in
        install|uninstall) action="$1" ;;
        --mac) server=0 ;;
        --server) mac=0 ;;
        --host) only="${2:-}"; mac=0; shift ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
    esac
    shift
done

say() { printf '%s\n' "$*"; }
die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

CONF="${CC_REMOTE_CONFIG:-$HOME/.config/cc-agterm-remote/config}"
if [ ! -f "$CONF" ]; then
    mkdir -p "$(dirname "$CONF")"
    cp "$here/config.example" "$CONF"
    die "wrote $CONF from config.example: set CC_REMOTE_HOSTS there, then run this again"
fi
# shellcheck source=/dev/null
. "$CONF"
# The servers, as in mac/bin/cc-remote-config: CC_REMOTE_HOSTS, or the single
# CC_REMOTE_HOST of an older configuration.
if [ -n "${CC_REMOTE_HOSTS+x}" ]; then
    HOSTS=("${CC_REMOTE_HOSTS[@]}")
elif [ -n "${CC_REMOTE_HOST:-}" ]; then
    HOSTS=("$CC_REMOTE_HOST")
else
    die "set CC_REMOTE_HOSTS in $CONF"
fi
# Each server's mark, which leads its panes' names on the Mac and which its
# shells put in their title, derived as mac/bin/cc-remote-config derives it,
# from the full host list, so --host gives a server the same mark as a full
# install. A bad CC_REMOTE_MARKS entry stops the install.
# shellcheck disable=SC2016 # the script expands its own arguments
host_mark_of() {
    CC_REMOTE_CONFIG="$CONF" "$BASH" -c '. "$1" && host_mark "$2"' _ "$here/mac/bin/cc-remote-config" "$1"
}
if [ "$action" = install ]; then
    # shellcheck disable=SC2016
    mark_errors="$(CC_REMOTE_CONFIG="$CONF" "$BASH" -c '. "$1" && printf %s "$MARK_ERRORS"' _ "$here/mac/bin/cc-remote-config")"
    [ -z "$mark_errors" ] || die "$mark_errors"
fi
if [ -n "$only" ]; then
    case " ${HOSTS[*]} " in *" $only "*) HOSTS=("$only") ;; *) die "$only is not in CC_REMOTE_HOSTS" ;; esac
fi

BIN="$HOME/.local/bin"
STATE="$HOME/.config/cc-agterm-remote"
AGENTS="$HOME/Library/LaunchAgents"
KEYMAP="$HOME/.config/agterm/keymap.conf"
LABELS=(cc-agterm-remote.bridge cc-agterm-remote.clipboard)
MAC_BIN=(cc-remote-config cc-remote-ssh cc-remote-attach cc-remote-bridge cc-remote-clipboard
         cc-remote-paste cc-remote-paste-image cc-remote-show-image)
SERVER_BIN=(cc-remote-talk cc-remote-status cc-remote-open xclip claude-rc claude-rc-start claude-rc-refresh)

# Removes the lines between "# >>> $2 >>>" and "# <<< $2 <<<" from file $1.
strip_block() {
    [ -f "$1" ] || return 0
    awk -v b="# >>> $2 >>>" -v e="# <<< $2 <<<" '$0 == b {skip = 1; next} $0 == e {skip = 0; next} !skip' "$1" > "$1.tmp" &&
        mv "$1.tmp" "$1"
}

mac_install() {
    command -v jq >/dev/null || die "jq is missing on this Mac (brew install jq)"
    [ -x /Applications/agterm.app/Contents/MacOS/agtermctl ] || command -v agtermctl >/dev/null ||
        die "agterm is not installed (https://github.com/umputun/agterm)"

    mkdir -p "$BIN" "$AGENTS" "$(dirname "$KEYMAP")"
    mkdir -p "$STATE" && chmod 700 "$STATE"
    for f in "${MAC_BIN[@]}"; do
        mode=755; [ "$f" = cc-remote-config ] && mode=644
        install -m "$mode" "$here/mac/bin/$f" "$BIN/$f" || die "could not install $f"
    done
    say "installed ${#MAC_BIN[@]} scripts into $BIN"

    for label in "${LABELS[@]}"; do
        sed -e "s|@BIN@|$BIN|g" -e "s|@STATE@|$STATE|g" "$here/mac/launchd/$label.plist" > "$AGENTS/$label.plist"
        plutil -lint -s "$AGENTS/$label.plist" || die "bad plist $label"
        launchctl bootout "gui/$(id -u)/$label" 2>/dev/null
        # bootout returns before the job is gone, and a bootstrap that races it
        # fails with an I/O error, so try a few times.
        for try in 1 2 3 4 5; do
            launchctl bootstrap "gui/$(id -u)" "$AGENTS/$label.plist" 2>/dev/null && break
            [ "$try" = 5 ] && die "launchd refused $label"
            sleep 1
        done
    done
    say "started the launchd agents ${LABELS[*]}"

    touch "$KEYMAP"
    strip_block "$KEYMAP" cc-agterm-remote
    {
        printf '# >>> cc-agterm-remote >>>\n'
        sed -n '/^command /p' "$here/mac/keymap.conf" | sed -e "s|@BIN@|$BIN|g"
        printf '# <<< cc-agterm-remote <<<\n'
    } >> "$KEYMAP"
    # agterm keeps the old bindings until told to re-read the file, and a
    # binding to a script that moved does nothing at all.
    if "${AGTERMCTL:-$(command -v agtermctl || echo /Applications/agterm.app/Contents/MacOS/agtermctl)}" keymap reload >/dev/null 2>&1; then
        say "added the chords to $KEYMAP and reloaded agterm's keymap"
    else
        say "added the chords to $KEYMAP (agterm is not running; it reads them at launch)"
    fi
}

mac_uninstall() {
    for label in "${LABELS[@]}"; do
        launchctl bootout "gui/$(id -u)/$label" 2>/dev/null
        rm -f "$AGENTS/$label.plist"
    done
    for f in "${MAC_BIN[@]}"; do rm -f "$BIN/$f"; done
    strip_block "$KEYMAP" cc-agterm-remote
    rm -f "$STATE/clipboard.sock" "$STATE/live-panes.json"
    say "removed the Mac side (kept $CONF, $STATE/map.json and $STATE/bridge.log)"
}

# The server side's install script, for a server whose mark is $1. It runs
# over ssh, after the files are copied, with the scripts to install as its
# arguments. The mark comes first, as a line of its own rather than an
# argument, so no remote login shell has to unquote it; it holds no quote (see
# cc-remote-config).
server_script() {
    printf "mark='%s'\n" "$1"
    cat <<'EOS'
set -uo pipefail
src="$HOME/.cache/cc-agterm-remote/install"
bin="$HOME/.local/bin"
export PATH="$bin:$PATH"
fail() { echo "  $*" >&2; exit 1; }

command -v claude >/dev/null || fail "claude is not installed on this server"
command -v jq >/dev/null || fail "jq is missing (sudo apt install jq)"
if ! nc -h 2>&1 | grep -q -- '-U' && ! command -v python3 >/dev/null; then
    fail "the clipboard needs nc with -U (netcat-openbsd) or python3"
fi
command -v expect >/dev/null || echo "  note: expect is missing, so claude-rc servers cannot start (sudo apt install expect)"

mkdir -p "$bin" "$HOME/.config/systemd/user" "$HOME/.cache/cc-agterm-remote"
chmod 700 "$HOME/.cache/cc-agterm-remote"
for f in "$@"; do
    # Leave a real xclip (a binary) alone: this machine has a display after all.
    if [ "$f" = xclip ] && real=$(command -v xclip) && [ "$(head -c 4 "$real" 2>/dev/null | tail -c 3)" = ELF ]; then
        echo "  kept the real xclip at $real (Ctrl+V reads this machine's clipboard, not the Mac's)"
        continue
    fi
    mode=755; [ "$f" = cc-remote-talk ] && mode=644
    install -m "$mode" "$src/bin/$f" "$bin/$f"
done
echo "  installed the scripts into $bin"

cp "$src"/systemd/* "$HOME/.config/systemd/user/"
if systemctl --user daemon-reload 2>/dev/null; then
    systemctl --user enable --now claude-rc-refresh.timer >/dev/null 2>&1 &&
        echo "  enabled claude-rc-refresh.timer"
else
    echo "  note: no systemd user manager, so claude-rc servers and their refresh are unavailable"
fi

# The status hooks: one per state, replacing any earlier cc-remote-status entry.
settings="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
[ -s "$settings" ] || echo '{}' > "$settings"
hook="$bin/cc-remote-status"
tmp=$(mktemp "$settings.XXXXXX")
jq --arg h "$hook" '
    def drop: map(.hooks |= map(select(.command | contains("cc-remote-status") | not)) | select(.hooks | length > 0));
    def add($event; $state; $matcher):
        .hooks[$event] = (((.hooks[$event] // []) | drop)
            + [{hooks: [{type: "command", command: "\($h) \($state)"}]} + (if $matcher then {matcher: $matcher} else {} end)]);
    .hooks = (.hooks // {})
    | add("PostToolUse"; "active"; null)
    | add("Stop"; "completed"; null)
    | add("Notification"; "blocked"; "permission_prompt")' "$settings" > "$tmp" && mv "$tmp" "$settings" ||
    { rm -f "$tmp"; fail "could not add the status hooks to $settings"; }
echo "  added the status hooks to $settings"

# Strip a marked block from a file, then (with a body on stdin) add it back,
# at the top or the end.
block() {
    local file=$1 name=$2 where=$3 body tmp
    touch "$file"
    tmp=$(mktemp "$file.XXXXXX")
    awk -v b="# >>> $name >>>" -v e="# <<< $name <<<" '$0 == b {skip = 1; next} $0 == e {skip = 0; next} !skip' "$file" > "$tmp"
    body=$(cat)
    if [ -n "$body" ]; then
        if [ "$where" = top ]; then
            { printf '# >>> %s >>>\n%s\n# <<< %s <<<\n' "$name" "$body" "$name"; cat "$tmp"; } > "$file"
        else
            { cat "$tmp"; printf '# >>> %s >>>\n%s\n# <<< %s <<<\n' "$name" "$body" "$name"; } > "$file"
        fi
        rm -f "$tmp"
    else
        mv "$tmp" "$file"
    fi
}

if [ "$(basename "${SHELL:-}")" = bash ]; then
    # Above ~/.bashrc's interactive guard, so the non-interactive `ssh host
    # claude attach ...` a pane runs gets it too. Only where nothing set one: the
    # claude-rc units keep their BROWSER=true.
    block "$HOME/.bashrc" cc-agterm-remote top <<'EOF'
# Links clicked in a remote Claude Code session open on the Mac (cc-agterm-remote).
[ -n "${BROWSER:-}" ] || export BROWSER="$HOME/.local/bin/cc-remote-open"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
EOF
    # agterm names a pane from the OSC title, so mark the title itself rather
    # than renaming the pane, which would stop it following the title: the
    # server's mark says the shell is remote, and on which server, the rest
    # follows the directory. Only "$" needs escaping here, "\[" and the like
    # pass as they are.
    block "$HOME/.bashrc" cc-agterm-remote-title end <<EOF
# Mark this machine's shells in agterm's sidebar: "$mark ~/dir" (cc-agterm-remote).
if [ -n "\${SSH_CONNECTION:-}" ] && [ -n "\${PS1:-}" ]; then
    case "\$TERM" in xterm*|rxvt*|screen*|tmux*) PS1="\$PS1\[\e]0;$mark \w\a\]" ;; esac
fi
EOF
    echo "  added BROWSER and the pane title mark ($mark) to ~/.bashrc"
else
    echo "  note: your login shell is not bash, so set BROWSER=$bin/cc-remote-open yourself"
fi

block "$HOME/.tmux.conf" cc-agterm-remote end < "$src/tmux.conf"
tmux source-file "$HOME/.tmux.conf" 2>/dev/null
echo "  added OSC 8 link pass-through to ~/.tmux.conf"
rm -rf "$src"
EOS
}

server_install() {
    local HOST="$1" mark
    mark="$(host_mark_of "$HOST")"
    case "$mark" in ""|*\'*) die "no usable mark for $HOST: '$mark'" ;; esac
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" true 2>/dev/null ||
        die "cannot ssh to $HOST without a prompt; set up key-based access first"

    COPYFILE_DISABLE=1 tar --no-mac-metadata --no-xattrs -C "$here/server" -cf - bin systemd tmux.conf |
        ssh "$HOST" 'rm -rf ~/.cache/cc-agterm-remote/install && mkdir -p ~/.cache/cc-agterm-remote/install && tar -C ~/.cache/cc-agterm-remote/install -xf -' ||
        die "could not copy the server files to $HOST"

    server_script "$mark" | ssh "$HOST" "bash -s --$(printf ' %q' "${SERVER_BIN[@]}")" ||
        die "the server side failed on $HOST"
    say "installed the server side on $HOST (mark $mark)"
}

server_uninstall() {
    local HOST="$1"
    ssh "$HOST" "bash -s --$(printf ' %q' "${SERVER_BIN[@]}")" <<'EOS' || die "the server side failed on $HOST"
set -uo pipefail
bin="$HOME/.local/bin"
systemctl --user disable --now claude-rc-refresh.timer 2>/dev/null
rm -f "$HOME/.config/systemd/user/claude-rc-refresh."{service,timer}
ls "$HOME"/.config/cc-agterm-remote/rc/*.env >/dev/null 2>&1 &&
    echo "  kept claude-rc@.service and its servers: remove each with claude-rc remove <name> first" ||
    rm -f "$HOME/.config/systemd/user/claude-rc@.service"
systemctl --user daemon-reload 2>/dev/null
for f in "$@"; do
    [ "$f" = xclip ] && ! grep -q cc-remote-talk "$bin/xclip" 2>/dev/null && continue
    [ "$f" = claude-rc ] || [ "$f" = claude-rc-start ] && ls "$HOME"/.config/cc-agterm-remote/rc/*.env >/dev/null 2>&1 && continue
    rm -f "$bin/$f"
done
settings="$HOME/.claude/settings.json"
if [ -f "$settings" ]; then
    tmp=$(mktemp "$settings.XXXXXX")
    jq '.hooks |= ((. // {}) | map_values(map(.hooks |= map(select(.command | contains("cc-remote-status") | not)) | select(.hooks | length > 0))))' \
        "$settings" > "$tmp" && mv "$tmp" "$settings" || rm -f "$tmp"
fi
for pair in ".bashrc cc-agterm-remote" ".bashrc cc-agterm-remote-title" ".tmux.conf cc-agterm-remote"; do
    set -- $pair
    f="$HOME/$1"
    [ -f "$f" ] || continue
    awk -v b="# >>> $2 >>>" -v e="# <<< $2 <<<" '$0 == b {skip = 1; next} $0 == e {skip = 0; next} !skip' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
rm -rf "$HOME/.cache/cc-agterm-remote/quiet" "$HOME"/.cache/cc-agterm-remote/clipboard*.sock
EOS
    say "removed the server side on $HOST"
}

if [ "$action" = install ]; then
    [ "$mac" = 1 ] && mac_install
    # One server failing (down, say) leaves the others to be installed.
    if [ "$server" = 1 ]; then
        failed=""
        for h in "${HOSTS[@]}"; do ( server_install "$h" ) || failed="$failed $h"; done
        [ -z "$failed" ] || die "the server side failed on:$failed (./install.sh --host <host> to retry one)"
    fi
    say ""
    say "Optional: the rename-session plugin lets Claude name its own session. On both machines:"
    say "  claude plugin marketplace add nnemirovsky/cc-agterm-remote"
    say "  claude plugin install rename-session@cc-agterm-remote"
else
    [ "$mac" = 1 ] && mac_uninstall
    if [ "$server" = 1 ]; then
        failed=""
        for h in "${HOSTS[@]}"; do ( server_uninstall "$h" ) || failed="$failed $h"; done
        [ -z "$failed" ] || die "the server side failed on:$failed"
    fi
fi
exit 0
