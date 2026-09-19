#!/usr/bin/env bash
# fm-send typed-plane post-submit settle pause (FM_SEND_SETTLE).
#
# A typed-plane fm-send success only proves the composer cleared - the Enter
# landed and the text was submitted. The harness then takes a beat to spin up the
# turn before its busy footer appears, so an immediate peek after fm-send returns
# would see the stale idle pane. fm-send therefore pauses FM_SEND_SETTLE seconds
# (default 1, 0 disables) after a successful typed submit, so the receiving turn
# has time to visibly start. These tests use an explicit backend target to stay on
# that plane and pin the behavior hermetically (stubbed tmux + sleep, no real
# agent):
#   1. A successful typed text send pauses for the FM_SEND_SETTLE value (default 1).
#   2. FM_SEND_SETTLE=0 produces no pause at all (sleep is never invoked for it).
#   3. The pause is tunable (FM_SEND_SETTLE=7 pauses 7).
#   4. The --key path never pauses (it bypasses the submit/settle path entirely).
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-busy-lib.sh"

SEND="$ROOT/bin/fm-send.sh"

TMP_ROOT=$(fm_test_tmproot fm-send-settle)

# A fake tmux that lets fm-send's submit path reach a clean "empty" verdict, plus a
# fake sleep that records every requested duration (one per line) instead of
# sleeping. send-keys always succeeds; display-message yields a numeric cursor_y;
# capture-pane returns an empty bordered composer so fm_tmux_composer_state reads
# "empty" (submit landed) on the first Enter. The sleep log path comes from
# FM_SLEEP_LOG, and every named key the plane delivers is appended to FM_KEY_LOG
# so a test can count the presses an interrupt actually put on the wire.
make_stubs() {  # <dir> -> echoes fakebin dir
  local dir=$1 fb="$1/fakebin"
  mkdir -p "$fb"
  cat > "$fb/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  send-keys)
    if [ -n "${FM_KEY_LOG:-}" ]; then
      skip=0
      for a in "$@"; do
        if [ "$skip" -eq 1 ]; then skip=0; continue; fi
        case "$a" in
          send-keys) continue ;;
          -t) skip=1; continue ;;
          -l) break ;;
        esac
        printf '%s\n' "$a" >> "$FM_KEY_LOG"
      done
    fi
    exit 0 ;;
  display-message)
    for a in "$@"; do case "$a" in *cursor_y*) printf '1\n'; exit 0 ;; esac; done
    printf 'fakepane\n'; exit 0 ;;
  capture-pane) printf '╭────╮\n│    │\n╰────╯\n'; exit 0 ;;
  list-windows) exit 0 ;;
esac
exit 0
SH
  chmod +x "$fb/tmux"
  cat > "$fb/sleep" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${1:-}" >> "$FM_SLEEP_LOG"
exit 0
SH
  chmod +x "$fb/sleep"
  printf '%s\n' "$fb"
}

# run_send <fakebin> <sleep-log> [env-assignments...] -- <fm-send args...>
# Runs fm-send.sh with the stubs on PATH. FM_ROOT_OVERRIDE points at a non-repo
# temp dir so fm-guard's tangle check stays silent, and FM_HOME at an empty home so
# no in-flight task is seen; guard noise goes to stderr (discarded). Echoes nothing;
# returns fm-send's exit code.
run_send() {
  local fb=$1 log=$2 home; shift 2
  home="$TMP_ROOT/home-$RANDOM"; mkdir -p "$home/state"
  : > "$log"
  env "$@" PATH="$fb:$PATH" \
    FM_ROOT_OVERRIDE="$home" FM_HOME="$home" FM_SLEEP_LOG="$log" \
    "$SEND" "sess:win" "hello captain" 2>/dev/null
}

test_default_send_pauses_one_second() {
  local dir fb log rc last
  dir="$TMP_ROOT/default"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); log="$dir/sleep.log"
  run_send "$fb" "$log"; rc=$?
  expect_code 0 "$rc" "default send should succeed"
  last=$(tail -1 "$log")
  [ "$last" = 1 ] || fail "default send: expected a trailing 1s settle pause, got '$last'"$'\n'"--- sleeps ---"$'\n'"$(cat "$log")"
  pass "fm-send: a successful text send pauses the default 1s after submit"
}

test_zero_disables_pause() {
  local dir fb log rc
  dir="$TMP_ROOT/zero"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); log="$dir/sleep.log"
  run_send "$fb" "$log" FM_SEND_SETTLE=0; rc=$?
  expect_code 0 "$rc" "FM_SEND_SETTLE=0 send should succeed"
  # The disable path must not invoke sleep with 0 at all - the only sleeps left are
  # the submit core's own settle/enter waits, none of which is "0".
  if grep -qx '0' "$log"; then
    fail "FM_SEND_SETTLE=0 still paused (a sleep 0 was recorded)"$'\n'"--- sleeps ---"$'\n'"$(cat "$log")"
  fi
  pass "fm-send: FM_SEND_SETTLE=0 produces no settle pause"
}

test_pause_is_tunable() {
  local dir fb log rc last
  dir="$TMP_ROOT/tunable"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); log="$dir/sleep.log"
  run_send "$fb" "$log" FM_SEND_SETTLE=7; rc=$?
  expect_code 0 "$rc" "FM_SEND_SETTLE=7 send should succeed"
  last=$(tail -1 "$log")
  [ "$last" = 7 ] || fail "FM_SEND_SETTLE=7: expected a trailing 7s settle pause, got '$last'"$'\n'"--- sleeps ---"$'\n'"$(cat "$log")"
  pass "fm-send: the settle pause is tunable via FM_SEND_SETTLE"
}

test_key_path_never_pauses() {
  local dir fb log rc home
  dir="$TMP_ROOT/key"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); log="$dir/sleep.log"
  home="$dir/home"; mkdir -p "$home/state"
  : > "$log"
  env PATH="$fb:$PATH" FM_ROOT_OVERRIDE="$home" FM_HOME="$home" FM_SLEEP_LOG="$log" \
    "$SEND" "sess:win" --key Escape 2>/dev/null; rc=$?
  expect_code 0 "$rc" "--key send should succeed"
  [ ! -s "$log" ] || fail "--key path paused but must not"$'\n'"--- sleeps ---"$'\n'"$(cat "$log")"
  pass "fm-send: the --key path never pauses (settle scoped to text submit)"
}

# An Escape on this plane IS the interrupt, and the adapters need a DIFFERENT
# number of presses to cancel at all: one for claude, two for devin, which the
# control-plane table owns. What this plane must NOT do is record the outcome:
# it captures nothing, so it cannot tell a cancelled turn from an absorbed
# press - the case devin's own status row is built around, since one Escape
# merely ARMS the second - and a guessed idle would tell every supervisor a
# working worker was free. The record is left exactly as the adapter wrote it;
# bin/fm-control.sh's interrupt verb, which does read the pane, owns the close.
assert_escape_delivers_the_sequence_and_records_nothing() {  # <harness> <source> <expected-presses>
  local harness=$1 source=$2 want=$3 dir fb log keys rc home gen out got
  dir="$TMP_ROOT/$harness-interrupt"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); log="$dir/sleep.log"; keys="$dir/keys.log"
  home="$dir/home"; mkdir -p "$home/state"
  fm_write_meta "$home/state/task.meta" \
    "window=sess:win" "worktree=$home/wt" "project=$home/project" \
    "harness=$harness" "kind=ship" "mode=no-mistakes" "yolo=off"
  gen=$("$ROOT/bin/fm-busy-event.sh" arm "$home/state" task)
  printf 'busy_gen=%s\n' "$gen" >> "$home/state/task.meta"
  "$ROOT/bin/fm-busy-event.sh" apply "$home/state" task busy \
    --gen "$gen" --source "$source" --event turn-open >/dev/null \
    || fail "could not open a $harness turn from source $source"
  : > "$log"
  : > "$keys"

  env PATH="$fb:$PATH" FM_HOME="$home" FM_SLEEP_LOG="$log" FM_KEY_LOG="$keys" \
    "$SEND" task --key Escape 2>/dev/null; rc=$?
  expect_code 0 "$rc" "$harness Escape send should succeed"
  got=$(grep -cxF Escape "$keys") || got=0
  [ "$got" = "$want" ] \
    || fail "$harness interrupts on $want Escape press(es), but the plane delivered $got"
  out=$(fm_busy_classify tmux sess:win "$harness" task "$home/state")
  [ "$out" = "busy $source" ] \
    || fail "$harness's record is the adapter's to own on this plane, got '$out'"
}

test_escape_delivers_the_verified_sequence_and_records_nothing() {
  assert_escape_delivers_the_sequence_and_records_nothing claude claude-hook 1
  assert_escape_delivers_the_sequence_and_records_nothing devin devin-hook 2
  pass "fm-send: Escape delivers each adapter's verified interrupt sequence and records no outcome"
}

test_default_send_pauses_one_second
test_zero_disables_pause
test_pause_is_tunable
test_key_path_never_pauses
test_escape_delivers_the_verified_sequence_and_records_nothing
