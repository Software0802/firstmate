#!/usr/bin/env bash
# Live drift guard for the Devin CLI adapter's vendor-controlled surface:
# the folder-trust dialog and its hook ordering, the lifecycle hook triple,
# the rendered busy token, the double-Escape interrupt, and the exit command.
# Opt-in because it submits real prompts (no echo provider exists for devin).
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVIN_BIN=$(command -v devin 2>/dev/null || true)
REAL_TMUX=$(command -v tmux 2>/dev/null || true)
LAB=
SOCKET="fm-devin-signals-$$"
SESSION=devin-signals
TARGET="$SESSION:devin"

cleanup() {
  [ -n "$REAL_TMUX" ] && "$REAL_TMUX" -L "$SOCKET" kill-server >/dev/null 2>&1 || true
  [ -z "$LAB" ] || rm -rf -- "$LAB"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  cleanup
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

fm_live_gate opt-in FM_DEVIN_SIGNALS_LIVE devin tmux
[ -n "$DEVIN_BIN" ] || fail "devin is not installed"

LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-devin-signals.XXXXXX") || fail "could not create the isolated devin lab"
trap cleanup EXIT
mkdir -p "$LAB/workspace" "$LAB/out"
git -C "$LAB/workspace" init -q || fail "could not initialize the isolated devin workspace"
git -C "$LAB/workspace" config user.email "guard@local" || fail "could not configure the isolated devin workspace"
git -C "$LAB/workspace" config user.name "guard" || fail "could not configure the isolated devin workspace"
git -C "$LAB/workspace" commit -q --allow-empty -m init || fail "could not seed the isolated devin workspace"
WORKSPACE=$(cd "$LAB/workspace" && pwd -P) || fail "could not resolve the isolated devin workspace"
OUT="$LAB/out"

# devin resolves its data root through XDG, and the trust answer below WRITES
# to that root, so the worker runs under a throwaway XDG_DATA_HOME holding a
# copy of the operator's devin data directory. Its trust answer and every other
# devin write land in the lab, never the operator's real store.
DATA_HOME="$LAB/data"
mkdir -p "$DATA_HOME" || fail "could not create the throwaway devin data home"
REAL_DATA=${XDG_DATA_HOME:-$HOME/.local/share}
[ -d "$REAL_DATA/devin" ] || fail "no devin data directory to stage for the throwaway lab"
cp -R "$REAL_DATA/devin" "$DATA_HOME/devin" || fail "could not stage the throwaway devin credential copy"

# The per-task config the adapter composes, reduced to what this guard proves:
# the four lifecycle hooks, each draining its stdin payload into a log.
CONFIG="$LAB/task-config.json"
node -e '
const fs = require("node:fs");
const [out, outdir] = process.argv.slice(1);
// devin writes a hook payload with NO trailing newline, so appends would
// concatenate onto one line and a line count would read 1 forever. Each hook
// terminates its own record.
const cmd = (name) => "sh -c \x27{ cat; echo; } >> " + outdir + "/" + name + ".log\x27";
const one = (command) => [{ hooks: [{ type: "command", command }] }];
fs.writeFileSync(out, JSON.stringify({
  attribution: false,
  hooks: {
    SessionStart: one(cmd("sessionstart")),
    UserPromptSubmit: one(cmd("prompt")),
    Stop: one(cmd("stop")),
    SessionEnd: one(cmd("sessionend")),
  },
}, null, 2) + "\n");
' "$CONFIG" "$OUT" || fail "could not compose the isolated devin config"

# shellcheck source=/dev/null
. "$ROOT/bin/fm-busy-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-composer-lib.sh"

"$REAL_TMUX" -L "$SOCKET" new-session -d -s "$SESSION" -n control -x 120 -y 40 -c "$WORKSPACE" \
  || fail "could not start the isolated tmux server"
"$REAL_TMUX" -L "$SOCKET" new-window -d -t "$SESSION:" -n devin -c "$WORKSPACE" \
  || fail "could not open the isolated devin window"

capture() {
  "$REAL_TMUX" -L "$SOCKET" capture-pane -p -t "$TARGET" -S -200 2>/dev/null || true
}

# The VISIBLE viewport only. Every busy assertion reads this rather than
# capture(): a finished turn's status row stays in scrollback, so a
# scrollback-wide read would keep matching the busy token long after the turn
# that drew it ended, and a later turn could then pass without ever starting.
capture_visible() {
  "$REAL_TMUX" -L "$SOCKET" capture-pane -p -t "$TARGET" 2>/dev/null || true
}

# Count OCCURRENCES, not lines: a truncated or unterminated record must never
# make two events read as one.
hook_count() {  # <log-name>
  local n
  n=$(grep -o hook_event_name "$OUT/$1.log" 2>/dev/null | wc -l | tr -d ' ') || n=0
  [ -n "$n" ] || n=0
  printf '%s' "$n"
}

# Type <text> into devin's composer and submit it, proving the submit landed
# from devin's own UserPromptSubmit hook rather than from rendered text.
#
# Both halves need retries against the real TUI, and both are facts about
# devin rather than test scaffolding. Typed input is dropped when it arrives
# while devin is still repainting after a turn, and an Enter delivered
# immediately after the typed line is taken as a NEWLINE inside the composer
# instead of a submit. The real submit core in bin/fm-composer-lib.sh solves
# the same two problems with the same settle-and-retry shape.
submit_prompt() {  # <text>
  local text=$1
  local before
  local typed=
  local submitted=
  local screen
  before=$(hook_count prompt)
  for _ in $(seq 1 20); do
    screen=$(capture_visible)
    # A blank viewport means devin is repainting, which is exactly when it
    # drops typed input. Wait for a painted pane rather than typing into it,
    # or the line lands nowhere and the retry types a second copy.
    if [ -z "$(printf '%s' "$screen" | tr -d '[:space:]')" ]; then
      sleep 0.5
      continue
    fi
    case "$screen" in *"$text"*) typed=1; break ;; esac
    "$REAL_TMUX" -L "$SOCKET" send-keys -t "$TARGET" -l "$text" || return 1
    sleep 0.8
  done
  [ -n "$typed" ] || return 1
  for _ in $(seq 1 10); do
    "$REAL_TMUX" -L "$SOCKET" send-keys -t "$TARGET" Enter || return 1
    for _ in $(seq 1 8); do
      [ "$(hook_count prompt)" -gt "$before" ] && { submitted=1; break; }
      sleep 0.25
    done
    [ -n "$submitted" ] && break
  done
  [ -n "$submitted" ]
}

# Wait for devin's rendered busy token in the VISIBLE viewport.
wait_for_busy() {
  for _ in $(seq 1 300); do
    capture_visible | fm_busy_lines_match devin && return 0
    sleep 0.2
  done
  return 1
}

# The launch prompt asks for a computed answer (12345+67890=80235) so the
# awaited token never appears in the echoed launch line itself, where a plain
# reply token would false-positive on the shell echo (including across tmux
# wrapped rows).
"$REAL_TMUX" -L "$SOCKET" send-keys -t "$TARGET" -l \
  "XDG_DATA_HOME=\"$DATA_HOME\" $DEVIN_BIN --config \"$CONFIG\" --permission-mode dangerous --model ${FM_DEVIN_SIGNALS_MODEL:-swe-2-medium} -- \"Add 12345 and 67890. Reply with exactly the sum and nothing else\"" \
  || fail "could not type the devin launch line"
"$REAL_TMUX" -L "$SOCKET" send-keys -t "$TARGET" Enter \
  || fail "could not submit the devin launch line"

# A fresh workspace stops on the folder-trust dialog. No devin hook fires while
# it is up, which is exactly why the adapter's readiness gate waits for the
# session sidecar rather than for a busy verdict; prove both halves here.
DIALOG='Do you trust the authors of this directory?'
screen=
for _ in $(seq 1 150); do
  screen=$(capture)
  case "$screen" in
    *"$DIALOG"*|*80235*|*80,235*) break ;;
  esac
  sleep 0.5
done
case "$screen" in
  *"$DIALOG"*)
    [ "$(hook_count sessionstart)" = 0 ] \
      || fail "a devin hook fired while the folder-trust dialog was still on screen"
    pass "no devin hook fires while the folder-trust dialog gates the pane"
    "$REAL_TMUX" -L "$SOCKET" send-keys -t "$TARGET" Enter \
      || fail "could not answer the devin trust dialog"
    ;;
  *) fail "a fresh workspace did not show devin's folder-trust dialog" ;;
esac

started=
for _ in $(seq 1 120); do
  [ "$(hook_count sessionstart)" -ge 1 ] && { started=1; break; }
  sleep 0.5
done
[ -n "$started" ] || fail "devin's SessionStart hook never fired after the trust answer"
pass "devin's SessionStart hook fires once the trust dialog is answered"

# The launch turn executes and its reply lands. Its busy row is deliberately
# NOT asserted here: a free-tier arithmetic answer can complete between polls,
# which would make this guard flaky rather than make it catch drift. The long
# turn below is what the rendered signature is proved against.
for _ in $(seq 1 480); do
  case "$(capture)" in *80235*|*80,235*) break ;; esac
  sleep 0.5
done
case "$(capture)" in
  *80235*|*80,235*) pass "the real devin worker processed its launch prompt" ;;
  *) fail "the real devin worker never answered its launch prompt" ;;
esac

settled=
for _ in $(seq 1 240); do
  [ "$(hook_count stop)" -ge 1 ] && { settled=1; break; }
  sleep 0.5
done
[ -n "$settled" ] || fail "devin's Stop hook never closed the completed turn"
[ "$(hook_count prompt)" -ge 1 ] || fail "devin's UserPromptSubmit hook never opened the launch turn"
pass "devin's UserPromptSubmit and Stop hooks bracket a completed turn"

# The settled composer must not still read busy. Scope to the visible tail the
# same way the owners do, because mid-turn rows stay in scrollback.
idle_settled=
for _ in $(seq 1 120); do
  screen=$(capture_visible)
  case "$screen" in *"Ask Devin to build features"*) idle_settled=1; break ;; esac
  sleep 0.5
done
[ -n "$idle_settled" ] || fail "the devin composer never settled to its idle placeholder"
printf '%s' "$screen" | grep -v '^[[:space:]]*$' | tail -12 | fm_busy_lines_match devin \
  && fail "harness=devin matched its own idle composer as busy" || true
pass "the settled devin composer no longer matches the busy signature"

# A genuinely long turn: long enough that the rendered busy signature, the
# double-Escape contract, and the missing interrupt Stop are each observable.
stop_before=$(hook_count stop)
submit_prompt "Write a 1500-word essay on the history of glass" \
  || fail "the long devin prompt never reached devin's UserPromptSubmit hook"
wait_for_busy || fail "the long devin turn never showed its busy token"
pass "the real devin busy token matches its registered signature in flight"

# ONE Escape must NOT cancel - it only arms the second press - and the pair
# must. Both halves are asserted, because a vendor that moved to a single
# Escape would silently make fm-control's second press land in the composer.
"$REAL_TMUX" -L "$SOCKET" send-keys -t "$TARGET" Escape \
  || fail "could not send the first Escape to the real devin turn"
armed=
for _ in $(seq 1 25); do
  case "$(capture_visible)" in *"esc again to interrupt"*) armed=1; break ;; esac
  sleep 0.2
done
[ -n "$armed" ] \
  || fail "devin no longer rewrites its status row after a single Escape; the double-Escape contract has drifted"
pass "one Escape only arms devin's second press"

"$REAL_TMUX" -L "$SOCKET" send-keys -t "$TARGET" Escape \
  || fail "could not send the second Escape to the real devin turn"
cancelled=
for _ in $(seq 1 120); do
  case "$(capture)" in
    *"Canceled due to user interrupt"*|*"Canceled. What should Devin do?"*) cancelled=1; break ;;
  esac
  sleep 0.5
done
[ -n "$cancelled" ] || fail "a double Escape never cancelled the real devin turn"
pass "a double Escape cancels the real devin turn"

# The interrupt must leave the busy record's shape intact: devin fires no Stop
# for a cancelled turn, which is what fm-control's cancel=unconfirmed reports
# and what the adapter documents as its claude-shaped gap.
sleep 5
[ "$(hook_count stop)" = "$stop_before" ] \
  || fail "devin now fires Stop on a manual interrupt; the adapter's documented gap has closed and must be re-verified"
pass "devin still fires no Stop hook for a manual interrupt"

"$REAL_TMUX" -L "$SOCKET" send-keys -t "$TARGET" -l "/exit" \
  || fail "could not type the devin exit command"
sleep 0.8
"$REAL_TMUX" -L "$SOCKET" send-keys -t "$TARGET" Enter \
  || fail "could not submit the devin exit command"
gone=
for _ in $(seq 1 60); do
  current=$("$REAL_TMUX" -L "$SOCKET" display-message -p -t "$TARGET" '#{pane_current_command}' 2>/dev/null || true)
  case "$current" in *devin*) sleep 0.5 ;; *) gone=1; break ;; esac
done
[ -n "$gone" ] || fail "/exit never stopped the real devin process"
[ "$(hook_count sessionend)" -ge 1 ] || fail "devin's SessionEnd hook never fired on /exit"
pass "/exit stops the real devin process and fires its SessionEnd hook"

cleanup
trap - EXIT
