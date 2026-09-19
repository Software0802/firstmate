#!/usr/bin/env bash
# Behavior tests for the verified Devin CLI crewmate/scout adapter.
#
# The facts pinned here are the ones a devin release could silently change and
# the ones a wrong guess would make dangerous:
#   1. devin publishes no harness-identity marker of its own (a live tool
#      subprocess carries no DEVIN_* variable; CHISEL_SESSION_DB there is a
#      session-database path, not an identity), so detection is ancestry alone
#      on the anchored process name `devin`.
#   2. The anchored match must never claim unrelated commands containing the
#      fragment, and a structural devin ancestor must outrank a retained or
#      inherited CLAUDECODE, which devin does not clear.
#   3. The launch carries the brief after `--` with --config, --model, and
#      --permission-mode dangerous; a requested model a reachable
#      `devin models list` omits refuses loudly instead of wedging a pane,
#      while a hung or unreachable listing is cut off and never blocks.
#   4. devin has no effort flag, so every requested level is recorded in task
#      metadata and omitted from the launch (record-and-omit).
#   5. A fresh worktree would park devin on its folder-trust dialog, and NO
#      devin hook fires while that dialog is up, so the spawn pre-registers the
#      worktree in devin's own trusted_paths store through
#      bin/fm-devin-trust.sh (scope-refused for anything but a linked worktree
#      of the project, and recording the RESOLVED path devin compares and
#      nothing wider) and the post-launch gate is the backstop: it answers a
#      dialog that renders anyway, and it reports success only once THIS
#      launch's own SessionStart hook has written the session sidecar - never
#      on the seeded busy record and never on a predecessor's sidecar.
#   6. The per-task config MERGES the captain's own user config, because
#      --config replaces that whole layer, and it forces attribution off so no
#      worker adds a Co-Authored-By trailer and pins claude config import off
#      so a worktree's .claude hooks never fire inside a devin session.
#   7. devin is a crewmate/scout adapter only: a secondmate launch is refused.
#   8. The busy signature is the pinned `esc twice|again to interrupt` token
#      alone, scoped to harness=devin and never borrowed across adapters.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# bin/fm-harness.sh checks verified ENV markers before ancestry. A suite run
# from inside another harness inherits those markers, which outrank the fake
# ancestry the detection cases set up. Drop the ambient markers so the asserted
# verdict does not depend on which harness launched the suite.
unset CLAUDECODE PI_CODING_AGENT FM_PI_HARNESS GROK_AGENT CURSOR_AGENT CURSOR_INVOKED_AS \
  ATLASSIAN_AGENT_TYPE ROVODEV_CLI GEMINI_CLI AGENT FM_OMP_HARNESS

# shellcheck source=/dev/null
. "$ROOT/bin/fm-control-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-busy-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-composer-lib.sh"

HARNESS="$ROOT/bin/fm-harness.sh"
SPAWN="$ROOT/bin/fm-spawn.sh"
TRUST="$ROOT/bin/fm-devin-trust.sh"
TMP_ROOT=$(fm_test_tmproot fm-devin-harness)

# One recorded `devin models list` body, the shape the real command prints:
# unindented "<Label> (<family-id>)" headers, optional indented alias lines,
# and indented "<model-id>  <label>  [<limits>]" rows.
# shellcheck disable=SC2016  # the $-prefixed price cells are literal listing text
DEVIN_MODELS_BODY='Available models (3 families)

Claude Opus 5 (claude-opus-5)
  aliases: opus
  claude-opus-5-medium                     Claude Opus 5 Medium  [1M context, $5 / 1M Input]
  claude-opus-5-max                        Claude Opus 5 Max  [1M context, $5 / 1M Input]

SWE-2 (swe-2)
  aliases: swe
  swe-2-medium                             SWE-2 Medium  [262K context, Free]
  swe-2-max                                SWE-2 Max  [262K context, Free]

Fusion (fusion)
  fusion-claude-fable-5-1-medium-sidekick-swe-2-medium    Fusion (Claude Fable 5.1 Medium + SWE-2 Medium)  [1M context]'

# The store is devin's own persisted JSON, so trust is asserted against the
# parsed trusted_paths array and preservation against parsed values.
devin_trusted_paths() {  # <store>
  node -e 'const fs=require("node:fs");const j=fs.existsSync(process.argv[1])?JSON.parse(fs.readFileSync(process.argv[1],"utf8")):{};for(const p of (j.trusted_paths||[]))console.log(p);' "$1"
}

devin_store_value() {  # <store> <key>
  node -e 'const j=JSON.parse(require("node:fs").readFileSync(process.argv[1],"utf8"));console.log(JSON.stringify(j[process.argv[2]]));' "$1" "$2"
}

assert_devin_trusted() {  # <store> <path> <msg>
  devin_trusted_paths "$1" | grep -Fqx "$2" || fail "$3"
}

assert_devin_not_trusted() {  # <store> <path> <msg>
  devin_trusted_paths "$1" | grep -Fqx "$2" && fail "$3"
  return 0
}

test_devin_ancestry_detects_the_native_command_name() {
  local fakebin out
  fakebin=$(fm_fakebin "$TMP_ROOT/anc-native")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"comm="*) printf '%s\n' '/home/someone/.local/share/devin/cli/_versions/current/bin/devin'; exit 0 ;;
  *"args="*) printf '%s\n' 'devin --permission-mode dangerous -- hello'; exit 0 ;;
esac
exit 1
SH
  chmod +x "$fakebin/ps"
  out=$(PATH="$fakebin:$PATH" "$HARNESS")
  [ "$out" = devin ] \
    || fail "a natively-named devin command must be detected by ancestry, got '$out'"
  pass "fm-harness.sh: ancestry detects a natively-named devin command"
}

test_devin_ancestry_detects_the_acp_agent_child() {
  local fakebin out
  # devin runs a two-process model: the front end plus a `devin acp` agent
  # child, and a tool subprocess sits under the CHILD. Both report comm=devin,
  # so the nearest-ancestor walk must name the harness from either one.
  fakebin=$(fm_fakebin "$TMP_ROOT/anc-acp")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"comm="*) printf '%s\n' 'devin'; exit 0 ;;
  *"args="*) printf '%s\n' '/home/someone/.local/share/devin/cli/_versions/3000.10.31/bin/devin acp'; exit 0 ;;
esac
exit 1
SH
  chmod +x "$fakebin/ps"
  out=$(PATH="$fakebin:$PATH" "$HARNESS")
  [ "$out" = devin ] \
    || fail "the devin acp agent child must be detected by ancestry, got '$out'"
  pass "fm-harness.sh: ancestry detects the devin acp agent child"
}

test_devin_ancestry_rejects_unrelated_mentions() {
  local fakebin out
  fakebin=$(fm_fakebin "$TMP_ROOT/anc-negatives")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"comm="*) printf '%s\n' "${FAKE_PS_COMM:?}"; exit 0 ;;
  *"args="*) printf '%s\n' "${FAKE_PS_ARGS:?}"; exit 0 ;;
esac
exit 1
SH
  chmod +x "$fakebin/ps"

  out=$(FAKE_PS_COMM=devinci FAKE_PS_ARGS='devinci --serve' \
    PATH="$fakebin:$PATH" "$HARNESS")
  [ "$out" != devin ] \
    || fail "an unrelated devinci command must not detect devin, got '$out'"

  out=$(FAKE_PS_COMM=bash FAKE_PS_ARGS='bash -c "echo devin --help"' \
    PATH="$fakebin:$PATH" "$HARNESS")
  [ "$out" != devin ] \
    || fail "a later shell argument naming devin must not detect devin, got '$out'"
  pass "fm-harness.sh: ancestry rejects unrelated devin mentions"
}

test_devin_promotes_no_environment_marker() {
  local fakebin out
  # CHISEL_SESSION_DB reaches devin's tool subprocesses but is a session
  # DATABASE PATH, not an identity, so it must never claim the harness the way
  # GEMINI_CLI does for gemini; DEVIN_PROJECT_DIR reaches hook processes only
  # and is a path for the same reason.
  out=$(CHISEL_SESSION_DB=/home/someone/.local/share/devin/cli/sessions.db "$HARNESS")
  [ "$out" != devin ] \
    || fail "CHISEL_SESSION_DB must never claim the devin identity, got '$out'"
  out=$(DEVIN_PROJECT_DIR=/tmp/somewhere "$HARNESS")
  [ "$out" != devin ] \
    || fail "DEVIN_PROJECT_DIR must never claim the devin identity, got '$out'"
  # Drive the hazard the other way: devin does not clear an inherited
  # CLAUDECODE, so a structural devin ancestor must still outrank the retained
  # marker rather than being renamed away from it. Pin both halves so neither
  # can rot silently.
  fakebin=$(fm_fakebin "$TMP_ROOT/anc-claude")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"comm="*) printf '%s\n' devin; exit 0 ;;
  *"args="*) printf '%s\n' 'devin --permission-mode dangerous -- hi'; exit 0 ;;
esac
exit 1
SH
  chmod +x "$fakebin/ps"
  out=$(CLAUDECODE=1 PATH="$fakebin:$PATH" "$HARNESS")
  [ "$out" = devin ] \
    || fail "a structural devin ancestor must outrank an inherited CLAUDECODE, got '$out'"
  pass "fm-harness.sh: no environment marker claims the devin identity"
}

test_devin_control_mechanics_are_the_verified_ones() {
  fm_control_harness_supported devin || fail "devin must be a supported control harness"
  [ "$(fm_control_harness_family devin)" = devin ] || fail "devin must map to its own family"
  fm_control_harness_supports_kind devin scout || fail "devin must run scouts"
  fm_control_harness_supports_kind devin ship || fail "devin must run ships"
  fm_control_harness_supports_kind devin secondmate \
    && fail "devin must refuse secondmates" || true
  [ "$(fm_control_interrupt_key devin)" = Escape ] || fail "devin must interrupt on Escape"
  [ "$(fm_control_interrupt_repeat devin)" = 2 ] || fail "devin must interrupt on a double press"
  [ -z "$(fm_control_interrupt_clear_key devin)" ] || fail "devin must need no clear key"
  [ "$(fm_control_interrupt_ack_source devin)" = none ] || fail "devin must have no ack source"
  [ "$(fm_control_exit_command devin)" = /exit ] || fail "devin must exit on /exit"
  pass "fm-control-lib: devin mechanics are Escape twice, no clear key, and /exit"
}

test_devin_relaunch_retires_its_own_wiring() {
  local paths
  paths=$(fm_control_harness_wiring_paths devin /wt /state task1)
  printf '%s\n' "$paths" | grep -Fqx '/state/task1.devin-config.json' \
    || fail "a devin relaunch must retire the per-task config, got '$paths'"
  printf '%s\n' "$paths" | grep -Fqx '/state/task1.devin-session' \
    || fail "a devin relaunch must retire the session sidecar, got '$paths'"
  printf '%s\n' "$paths" | grep -q '^/wt/' \
    && fail "devin must write nothing into the project worktree, got '$paths'" || true
  pass "fm-control-lib: a devin relaunch retires its config and session sidecar"
}

test_devin_busy_source_is_trusted_only_for_devin() {
  local sources
  sources=$(fm_busy_sources_for_harness devin)
  case " $sources " in
    *" devin-hook "*) ;;
    *) fail "devin must trust its own devin-hook source, got '$sources'" ;;
  esac
  case " $(fm_busy_sources_for_harness claude) " in
    *" devin-hook "*) fail "claude must never trust the devin-hook source" ;;
  esac
  case " $sources " in
    *" claude-hook "*) fail "devin must never trust the claude-hook source" ;;
  esac
  pass "fm-busy-lib: devin-hook is trusted for devin alone"
}

test_devin_classify_reads_its_hook_record() {
  local statedir gen busy idle
  statedir="$TMP_ROOT/classify"; mkdir -p "$statedir"
  gen=$("$ROOT/bin/fm-busy-event.sh" arm "$statedir" devin-case-1) \
    || fail "could not arm a devin busy incarnation"
  busy=$(fm_busy_classify tmux fake:win devin devin-case-1 "$statedir" '')
  [ "$busy" = "busy fm-spawn" ] \
    || fail "the seeded launch turn must classify busy fm-spawn, got '$busy'"
  "$ROOT/bin/fm-busy-event.sh" apply "$statedir" devin-case-1 idle \
    --gen "$gen" --source devin-hook --event stop >/dev/null \
    || fail "a devin Stop event must be accepted"
  idle=$(fm_busy_classify tmux fake:win devin devin-case-1 "$statedir" '')
  [ "$idle" = "idle devin-hook" ] || fail "Stop must classify 'idle devin-hook', got '$idle'"
  "$ROOT/bin/fm-busy-event.sh" apply "$statedir" devin-case-1 busy \
    --gen "$gen" --source devin-hook --event user-prompt-submit >/dev/null \
    || fail "a devin UserPromptSubmit event must be accepted"
  busy=$(fm_busy_classify tmux fake:win devin devin-case-1 "$statedir" '')
  [ "$busy" = "busy devin-hook" ] \
    || fail "UserPromptSubmit must classify 'busy devin-hook', got '$busy'"
  # A manual interrupt fires NO devin hook of any kind, which is why nothing
  # devin-owned appears between these two events; closing the record after an
  # interrupt is fm-send's Escape path, covered in tests/fm-send-settle.test.sh.
  "$ROOT/bin/fm-busy-event.sh" apply "$statedir" devin-case-1 idle \
    --gen "$gen" --source devin-hook --event session-end >/dev/null \
    || fail "a devin SessionEnd event must be accepted"
  idle=$(fm_busy_classify tmux fake:win devin devin-case-1 "$statedir" '')
  [ "$idle" = "idle devin-hook" ] || fail "SessionEnd must classify idle, got '$idle'"
  pass "fm-busy-lib: devin's hook triple opens and closes its own record"
}

test_devin_busy_signatures_are_harness_scoped() {
  printf '⢠⡀ Running tools · 5s (esc twice to interrupt)\n' | fm_busy_lines_match devin \
    || fail "harness=devin must match its own esc-twice token"
  printf '⣠⠀ Running tools · 8s (esc again to interrupt)\n' | fm_busy_lines_match devin \
    || fail "harness=devin must still match after one Escape rewrites the token"
  printf '❭ Ask Devin to build features, fix bugs, or work on your code\n' | fm_busy_lines_match devin \
    && fail "devin's idle composer must not read busy" || true
  printf '⠲ Thinking · 1s (esc twice to interrupt)\n' | fm_busy_lines_match \
    || fail "the harness-less union must acknowledge a devin submit"
  printf 'esc twice to interrupt\n' | fm_busy_lines_match agy \
    && fail "harness=agy must never borrow devin's token" || true
  printf 'esc to cancel\n' | fm_busy_lines_match devin \
    && fail "harness=devin must never borrow agy's token" || true
  printf 'esc to interrupt\n' | fm_busy_lines_match devin \
    && fail "harness=devin must never borrow claude's token" || true
  pass "fm-composer-lib: devin delivery signatures never cross harnesses"
}

test_devin_tmux_names_the_native_binary_an_agent() {
  local got
  # shellcheck source=/dev/null
  . "$ROOT/bin/fm-backend.sh"
  fm_backend_source tmux || fail "fm_backend_source tmux failed"
  got=$(fm_agent_process_classify_name devin)
  [ "$got" = agent ] || fail "tmux liveness must read the devin binary as an agent, got '$got'"
  got=$(fm_agent_process_classify_name devinci)
  [ "$got" = other ] || fail "tmux liveness must not read devinci as an agent, got '$got'"
  got=$(fm_agent_process_classify_name bash)
  [ "$got" = shell ] || fail "tmux liveness must still read bash as a shell, got '$got'"
  pass "bin/fm-agent-process-lib.sh: devin is an agent, fragments are not"
}

make_devin_trust_case() {  # <name> -> "<case>|<proj>|<wt>|<home>"
  local name=$1 case_dir proj wt home
  case_dir="$TMP_ROOT/trust-$name"
  proj="$case_dir/project"
  wt="$case_dir/wt"
  home="$case_dir/home"
  mkdir -p "$home"
  fm_git_worktree "$proj" "$wt" "wt-trust-$name"
  printf '%s|%s|%s|%s\n' "$case_dir" "$proj" "$wt" "$home"
}

read_devin_trust_case() {
  IFS='|' read -r CASE_DIR PROJ_DIR WT_DIR HOME_DIR <<EOF
$1
EOF
}

run_devin_trust() {  # <home> <worktree> <project>
  HOME="$1" XDG_DATA_HOME="$1/.local/share" "$TRUST" "$2" "$3" 2>&1
}

devin_trust_store() {  # <home>
  printf '%s\n' "$1/.local/share/devin/cli/trusted_workspaces.json"
}

test_devin_trust_registers_the_resolved_worktree_path() {
  local rec store out link
  rec=$(make_devin_trust_case fresh)
  read_devin_trust_case "$rec"
  store=$(devin_trust_store "$HOME_DIR")
  mkdir -p "$(dirname "$store")"
  printf '%s\n' '{"trusted_paths":["/home/someone/elsewhere"],"schema":2}' > "$store"
  link="$CASE_DIR/wt-link"
  ln -s "$WT_DIR" "$link"
  out=$(run_devin_trust "$HOME_DIR" "$link" "$PROJ_DIR") || fail "a fresh linked worktree must be trusted: $out"
  assert_devin_trusted "$store" "$WT_DIR" "the resolved worktree path devin compares against was not registered"
  assert_devin_not_trusted "$store" "$link" \
    "registration widened the store with a logical path devin never compares against"
  assert_devin_trusted "$store" "/home/someone/elsewhere" "registration dropped an existing trusted_paths entry"
  [ "$(devin_store_value "$store" schema)" = 2 ] \
    || fail "registration did not preserve an unrelated store key"
  out=$(run_devin_trust "$HOME_DIR" "$link" "$PROJ_DIR") || fail "repeat registration must succeed: $out"
  [ "$(devin_trusted_paths "$store" | grep -Fcx "$WT_DIR")" -eq 1 ] \
    || fail "repeat registration duplicated the worktree entry"
  pass "fm-devin-trust.sh: registers the resolved worktree path and preserves the store"
}

test_devin_trust_creates_a_missing_store() {
  local rec store out
  rec=$(make_devin_trust_case nostore)
  read_devin_trust_case "$rec"
  store=$(devin_trust_store "$HOME_DIR")
  out=$(run_devin_trust "$HOME_DIR" "$WT_DIR" "$PROJ_DIR") || fail "a missing store must be created: $out"
  [ -f "$store" ] || fail "no trust store was created at $store"
  assert_devin_trusted "$store" "$WT_DIR" "the worktree was not registered in the created store"
  pass "fm-devin-trust.sh: creates devin's trust store when none exists"
}

test_devin_trust_refuses_out_of_scope_paths() {
  local rec store out rc plain before after
  rec=$(make_devin_trust_case scope)
  read_devin_trust_case "$rec"
  store=$(devin_trust_store "$HOME_DIR")
  mkdir -p "$(dirname "$store")"
  printf '%s\n' '{"trusted_paths":[]}' > "$store"
  rc=0; out=$(run_devin_trust "$HOME_DIR" "$PROJ_DIR" "$PROJ_DIR") || rc=$?
  [ "$rc" -ne 0 ] || fail "the primary checkout must be refused"
  assert_contains "$out" "primary checkout" "primary-checkout refusal lacked its reason"
  assert_devin_not_trusted "$store" "$PROJ_DIR" "a refused primary checkout was still registered"
  rc=0; out=$(run_devin_trust "$HOME_DIR" "$HOME_DIR" "$PROJ_DIR") || rc=$?
  [ "$rc" -ne 0 ] || fail "the home directory must be refused"
  assert_devin_not_trusted "$store" "$HOME_DIR" "a refused home directory was still registered"
  plain="$CASE_DIR/plain"; mkdir -p "$plain"
  rc=0; out=$(run_devin_trust "$HOME_DIR" "$plain" "$PROJ_DIR") || rc=$?
  [ "$rc" -ne 0 ] || fail "a plain directory must be refused"
  assert_devin_not_trusted "$store" "$plain" "a refused plain directory was still registered"
  rc=0; out=$(run_devin_trust "$HOME_DIR" "$WT_DIR/.git" "$PROJ_DIR") || rc=$?
  [ "$rc" -ne 0 ] || fail "a path below the worktree root must be refused"
  printf '%s\n' '{not json' > "$store"
  before=$(cat "$store")
  rc=0; out=$(run_devin_trust "$HOME_DIR" "$WT_DIR" "$PROJ_DIR") || rc=$?
  [ "$rc" -ne 0 ] || fail "an unparseable store must be refused"
  after=$(cat "$store")
  [ "$before" = "$after" ] || fail "an unparseable store was rewritten"
  pass "fm-devin-trust.sh: refuses every out-of-scope path and never rewrites a broken store"
}

# The fake tmux renders a devin-shaped screen that advances through
# launched -> (trust dialog ->) running as the real spawn drives it, so the
# launch command, the pre-registration, the single Enter that answers a dialog,
# and the readiness gate are exercised through their real code paths. Whether
# the dialog renders is decided the way devin decides it: the pane path is
# looked up in the trusted_paths array of the store the spawn just wrote.
# Reaching the `running` state is what writes the session sidecar, exactly as
# devin's own SessionStart hook does, so the gate's real proof is exercised.
# FM_FAKE_DEVIN_IGNORE_TRUST=1 models a vendor that stopped honouring the store;
# FM_FAKE_DEVIN_ANSWER=stuck models a dialog whose answer never starts a session.
make_devin_fakebin() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$FM_FAKE_TMUX_CALL_LOG"
state=$(cat "$FM_FAKE_DEVIN_STATE" 2>/dev/null || true)
fake_screen() {
  case "$state" in
    dialog)
      printf ' * Do you trust the authors of this directory?\n   For security, devin should not be run in directories with untrusted content.\n\n %s\n\n > 1 Yes, trust\n . 2 No, exit\n' "$FM_FAKE_PANE_PATH"
      ;;
    running)
      printf 'Thinking · 3s (esc twice to interrupt)\n────\n> Guide Devin while it works\n────\nSWE-2 Medium\n'
      ;;
    *)
      printf 'shell starting\n$ \n'
      ;;
  esac
}
start_session() {
  printf '{"hook_event_name":"SessionStart","source":"startup","session_id":"fake-session"}' \
    > "$FM_FAKE_DEVIN_SESSION_MARKER"
  printf 'running\n' > "$FM_FAKE_DEVIN_STATE"
}
fake_path_trusted() {
  [ "${FM_FAKE_DEVIN_IGNORE_TRUST:-0}" = 1 ] && return 1
  node -e 'const fs=require("node:fs");let j={};try{j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));}catch(e){process.exit(1);}process.exit(Array.isArray(j.trusted_paths)&&j.trusted_paths.includes(process.argv[2])?0:1);' \
    "$FM_FAKE_DEVIN_STORE" "$FM_FAKE_PANE_PATH"
}
case "$*" in
  *"#{pane_current_path}"*) printf '%s\n' "$FM_FAKE_PANE_PATH"; exit 0 ;;
  *"#{cursor_y}"*) printf '1\n'; exit 0 ;;
esac
case "${1:-}" in
  display-message) printf 'firstmate\n'; exit 0 ;;
  list-windows) exit 0 ;;
  has-session|new-session|new-window|kill-window) exit 0 ;;
  send-keys)
    literal=
    prev=
    for arg in "$@"; do
      if [ "$prev" = -l ]; then literal=$arg; break; fi
      prev=$arg
    done
    if [ -n "$literal" ]; then
      case "$literal" in
        *--permission-mode*)
          printf '%s\n' "$literal" >> "$FM_FAKE_LAUNCH_LOG"
          printf 'launched\n' > "$FM_FAKE_DEVIN_STATE"
          ;;
      esac
      exit 0
    fi
    case " $* " in
      *' Enter '*)
        case "$state" in
          launched)
            if fake_path_trusted; then start_session; else printf 'dialog\n' > "$FM_FAKE_DEVIN_STATE"; fi
            ;;
          dialog)
            [ "${FM_FAKE_DEVIN_ANSWER:-works}" = works ] && start_session
            ;;
        esac
        ;;
    esac
    exit 0
    ;;
  capture-pane) fake_screen; exit 0 ;;
esac
exit 0
SH
  chmod +x "$fakebin/tmux"
  cat > "$fakebin/devin" <<'SH'
#!/usr/bin/env bash
set -u
if [ "${1:-}" = models ]; then
  if [ "${FM_FAKE_DEVIN_MODELS_FAIL:-0}" = 1 ]; then exit 3; fi
  if [ "${FM_FAKE_DEVIN_MODELS_HANG:-0}" = 1 ]; then cat > /dev/null; sleep 30; exit 0; fi
  printf '%s\n' "$FM_FAKE_DEVIN_MODELS_BODY"
  exit 0
fi
echo "fake devin must never execute" >&2
exit 9
SH
  chmod +x "$fakebin/devin"
  fm_fake_exit0 "$fakebin" treehouse gh-axi gh
  printf '%s\n' "$fakebin"
}

make_devin_spawn_case() {
  local name=$1 id=$2 case_dir home proj wt fakebin
  case_dir="$TMP_ROOT/$name"
  home="$case_dir/home"
  proj="$case_dir/project"
  wt="$case_dir/wt"
  fakebin=$(make_devin_fakebin "$case_dir/fake")
  mkdir -p "$home/data/$id" "$home/projects" "$home/state" "$home/config" \
    "$home/.config/devin" "$home/.local/share/devin/cli"
  cat > "$home/data/$id/brief.md" <<'EOF'
# Task
## Captain's intent
Exercise Devin dispatch.

## Firstmate spec
Verify launch and delivery behavior.
EOF
  printf 'devin\n' > "$home/config/crew-harness"
  # The captain's own user config, which --config replaces and the spawn must
  # therefore merge rather than discard.
  printf '%s\n' '{"theme_mode":"dark","devin":{"org_id":"org-test"},"agent":{"model":"swe-2-max"},"attribution":true,"read_config_from":{"cursor":true,"claude":true}}' \
    > "$home/.config/devin/config.json"
  printf '%s\n' '{"trusted_paths":["/home/someone/elsewhere"]}' \
    > "$home/.local/share/devin/cli/trusted_workspaces.json"
  fm_git_worktree "$proj" "$wt" "wt-$name"
  touch "$home/state/.last-watcher-beat"
  : > "$case_dir/launch.log"
  : > "$case_dir/tmux-calls.log"
  : > "$case_dir/devin.state"
  printf '%s\n' "$case_dir|$home|$proj|$wt|$fakebin"
}

read_devin_spawn_record() {
  IFS='|' read -r CASE_DIR HOME_DIR PROJ_DIR WT_DIR FAKEBIN_DIR <<EOF
$1
EOF
}

# The spawn drives the real bin/fm-devin-trust.sh, composes the per-task config
# with node, and the fake tmux's trust lookup reads the store with node too,
# and runners do not keep node in the system bin dirs. Carry the directory the
# invoking environment resolves node from, the fm-agy-harness shape.
NODE_BIN=$(command -v node) || fail "test needs node"
NODE_BIN_DIR=$(dirname "$NODE_BIN")
BASE_PATH=${FM_TEST_BASE_PATH:-$NODE_BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin}

run_devin_spawn() {
  local case_dir=$1 home=$2 proj=$3 wt=$4 fakebin=$5 id=$6
  shift 6
  HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share" \
    FM_ROOT_OVERRIDE='' FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROJECTS_OVERRIDE="$home/projects" FM_CONFIG_OVERRIDE="$home/config" \
    FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$wt" TMUX="fake,1,0" \
    FM_FAKE_LAUNCH_LOG="$case_dir/launch.log" \
    FM_FAKE_TMUX_CALL_LOG="$case_dir/tmux-calls.log" \
    FM_FAKE_DEVIN_STATE="$case_dir/devin.state" \
    FM_FAKE_DEVIN_STORE="$home/.local/share/devin/cli/trusted_workspaces.json" \
    FM_FAKE_DEVIN_SESSION_MARKER="$home/state/$id.devin-session" \
    FM_FAKE_DEVIN_MODELS_BODY="${FM_FAKE_DEVIN_MODELS_BODY:-$DEVIN_MODELS_BODY}" \
    FM_FAKE_DEVIN_MODELS_FAIL="${FM_FAKE_DEVIN_MODELS_FAIL:-0}" \
    FM_FAKE_DEVIN_MODELS_HANG="${FM_FAKE_DEVIN_MODELS_HANG:-0}" \
    FM_FAKE_DEVIN_IGNORE_TRUST="${FM_FAKE_DEVIN_IGNORE_TRUST:-0}" \
    FM_FAKE_DEVIN_ANSWER="${FM_FAKE_DEVIN_ANSWER:-works}" \
    FM_DEVIN_READY_POLLS=4 FM_DEVIN_POLL_INTERVAL=0 \
    FM_DEVIN_MODELS_TIMEOUT=${FM_DEVIN_MODELS_TIMEOUT:-1} \
    PATH="$fakebin:$BASE_PATH" \
    "$SPAWN" "$id" "$proj" --harness devin --mode no-mistakes --yolo off "$@" 2>&1
}

test_devin_launch_carries_the_brief_model_and_autonomy() {
  local id rec out rc launch meta
  id="devin-launch-z1-$$"
  rec=$(make_devin_spawn_case launch "$id")
  read_devin_spawn_record "$rec"
  out=$(run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$id" \
    --model swe-2-medium)
  rc=$?
  expect_code 0 "$rc" "devin spawn with a listed model should succeed: $out"
  launch=$(cat "$CASE_DIR/launch.log")
  assert_contains "$launch" "$FAKEBIN_DIR/devin" "devin launch did not pin the resolved absolute binary"
  assert_contains "$launch" "--permission-mode dangerous" "devin launch omitted unattended autonomy"
  assert_contains "$launch" "--model 'swe-2-medium'" "devin launch did not carry the requested model"
  assert_contains "$launch" "--config '$HOME_DIR/state/$id.devin-config.json'" \
    "devin launch did not point at the firstmate-owned per-task config"
  assert_contains "$launch" "env -u CLAUDECODE" "devin launch did not clear the inherited launcher marker"
  assert_not_contains "$launch" "__DEVINBIN__" "devin launch left its binary placeholder unsubstituted"
  assert_not_contains "$launch" "__DEVINCONFIG__" "devin launch left its config placeholder unsubstituted"
  assert_not_contains "$launch" "__MODELFLAG__" "devin launch left its model placeholder unsubstituted"
  assert_not_contains "$launch" "__BRIEF__" "devin launch left its brief placeholder unsubstituted"
  meta="$HOME_DIR/state/$id.meta"
  assert_grep 'harness=devin' "$meta" "devin meta did not record its harness"
  assert_grep 'model=swe-2-medium' "$meta" "devin meta did not record its model"
  pass "fm-spawn: devin launch carries brief, model, config, and autonomy with cleared markers"
}

test_devin_config_merges_the_user_config_and_forces_attribution_off() {
  local id rec out rc cfg
  id="devin-config-z2-$$"
  rec=$(make_devin_spawn_case config "$id")
  read_devin_spawn_record "$rec"
  out=$(run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$id" \
    --model swe-2-medium)
  rc=$?
  expect_code 0 "$rc" "devin spawn should succeed: $out"
  cfg="$HOME_DIR/state/$id.devin-config.json"
  [ -f "$cfg" ] || fail "the spawn wrote no per-task devin config"
  [ "$(devin_store_value "$cfg" attribution)" = false ] \
    || fail "the per-task config must force devin's commit attribution off"
  [ "$(devin_store_value "$cfg" theme_mode)" = '"dark"' ] \
    || fail "--config replaces the user layer, so the per-task config must preserve the captain's own keys"
  node -e 'const j=JSON.parse(require("node:fs").readFileSync(process.argv[1],"utf8"));
    if (j.read_config_from?.claude !== false) {
      console.error("claude config import is not pinned off"); process.exit(1); }
    if (j.read_config_from.cursor !== true) {
      console.error("the captain'"'"'s other config importers were dropped"); process.exit(1); }
    if ("agents_standard" in j.read_config_from) {
      console.error("only claude may be pinned; agents_standard must keep its default"); process.exit(1); }' "$cfg" \
    || fail "the per-task config must stop devin importing claude's hook files without disabling the rest"
  node -e 'const j=JSON.parse(require("node:fs").readFileSync(process.argv[1],"utf8"));
    const want=["SessionStart","UserPromptSubmit","Stop","SessionEnd"];
    for (const k of want) { if (!Array.isArray(j.hooks[k])) { console.error("missing hook "+k); process.exit(1); } }
    const stop=j.hooks.Stop[0].hooks[0].command;
    if (!stop.includes(".turn-ended")) { console.error("Stop hook lost its turn-end notification"); process.exit(1); }
    if (!stop.includes("--source devin-hook")) { console.error("Stop hook lost its busy source"); process.exit(1); }
    if (!j.hooks.SessionStart[0].hooks[0].command.includes(".devin-session")) {
      console.error("SessionStart hook does not write the session sidecar"); process.exit(1); }
    for (const k of want) { if (!j.hooks[k][0].hooks[0].command.startsWith("cat >")) {
      console.error("hook "+k+" does not drain its stdin payload"); process.exit(1); } }' "$cfg" \
    || fail "the per-task devin config does not carry the verified hook wiring"
  [ -z "$(find "$WT_DIR/.devin" -mindepth 1 2>/dev/null)" ] \
    || fail "the spawn wrote devin configuration into the project worktree"
  pass "fm-spawn: devin's per-task config merges the user layer, forces attribution off, and carries its hooks"
}

test_devin_effort_is_recorded_but_never_launched() {
  local id rec out rc launch meta level
  for level in low high xhigh max; do
    id="devin-effort-$level-z3-$$"
    rec=$(make_devin_spawn_case "effort-$level" "$id")
    read_devin_spawn_record "$rec"
    out=$(run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$id" \
      --model swe-2-medium --effort "$level")
    rc=$?
    expect_code 0 "$rc" "devin spawn with effort $level should still succeed: $out"
    launch=$(cat "$CASE_DIR/launch.log")
    assert_not_contains "$launch" "--effort" "devin launch passed an effort flag it has no support for"
    assert_not_contains "$launch" "--thinking" "devin launch invented a thinking flag"
    meta="$HOME_DIR/state/$id.meta"
    assert_grep "effort=$level" "$meta" "devin meta did not retain the requested effort axis"
  done
  pass "fm-spawn: devin records every effort level in metadata and launches none of them"
}

test_devin_unlisted_model_refuses_before_pane_creation() {
  local id rec out rc
  id="devin-badmodel-z4-$$"
  rec=$(make_devin_spawn_case badmodel "$id")
  read_devin_spawn_record "$rec"
  rc=0
  out=$(run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$id" \
    --model swe-3-max) || rc=$?
  [ "$rc" -ne 0 ] || fail "an unlisted devin model should refuse the spawn"
  assert_contains "$out" "not listed by 'devin models list'" "unlisted model refusal lacked its concrete reason"
  [ -s "$CASE_DIR/launch.log" ] && fail "an unlisted model created a launch command" || true
  pass "fm-spawn: an unlisted devin model refuses before pane creation"
}

test_devin_accepts_family_ids_and_aliases() {
  local id rec out rc token
  for token in swe-2 opus fusion-claude-fable-5-1-medium-sidekick-swe-2-medium; do
    id="devin-modelform-z5-$$-$RANDOM"
    rec=$(make_devin_spawn_case "modelform-$RANDOM" "$id")
    read_devin_spawn_record "$rec"
    rc=0
    out=$(run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$id" \
      --model "$token") || rc=$?
    expect_code 0 "$rc" "devin must accept the listed token '$token': $out"
    assert_contains "$(cat "$CASE_DIR/launch.log")" "--model '$token'" \
      "devin launch dropped the accepted token '$token'"
  done
  pass "fm-spawn: devin accepts concrete ids, family ids, and aliases from its listing"
}

test_devin_accepts_a_family_id_from_a_padded_header() {
  local id rec out rc body
  id="devin-padhdr-z12-$$"
  rec=$(make_devin_spawn_case padhdr "$id")
  read_devin_spawn_record "$rec"
  # The same listing shape with trailing blanks on one family header, which a
  # terminal-formatted catalog can carry. printf keeps the padding explicit so
  # no whitespace-trimming tool can quietly retire this case.
  body=$(printf '%s\n\nSWE-3 (swe-3)  \n  swe-3-medium    SWE-3 Medium  [262K context, Free]\n' \
    "$DEVIN_MODELS_BODY")
  rc=0
  out=$(FM_FAKE_DEVIN_MODELS_BODY="$body" run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" \
    "$WT_DIR" "$FAKEBIN_DIR" "$id" --model swe-3) || rc=$?
  expect_code 0 "$rc" "a family id whose header is padded must still be listed: $out"
  assert_contains "$(cat "$CASE_DIR/launch.log")" "--model 'swe-3'" \
    "the padded family header dropped its model from the launch"
  pass "fm-spawn: devin reads a family id from a header with trailing blanks"
}

test_devin_unreachable_listing_launches_unvalidated() {
  local id rec out rc
  id="devin-nolisting-z6-$$"
  rec=$(make_devin_spawn_case nolisting "$id")
  read_devin_spawn_record "$rec"
  rc=0
  out=$(FM_FAKE_DEVIN_MODELS_FAIL=1 run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" \
    "$FAKEBIN_DIR" "$id" --model swe-2-medium) || rc=$?
  expect_code 0 "$rc" "an unreachable model listing must not block the spawn: $out"
  [ -s "$CASE_DIR/launch.log" ] || fail "an unreachable listing produced no launch command"
  assert_contains "$out" "listing is unreachable" "an unreachable listing launched without its notice"
  pass "fm-spawn: an unreachable devin listing establishes nothing and launches"
}

test_devin_hung_listing_is_cut_off_and_launches() {
  local id rec out rc started elapsed
  id="devin-hanglisting-z7-$$"
  rec=$(make_devin_spawn_case hanglisting "$id")
  read_devin_spawn_record "$rec"
  rc=0
  started=$(date +%s)
  out=$(FM_FAKE_DEVIN_MODELS_HANG=1 run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" \
    "$FAKEBIN_DIR" "$id" --model swe-2-medium) || rc=$?
  elapsed=$(( $(date +%s) - started ))
  expect_code 0 "$rc" "a hung model listing must not block the spawn: $out"
  [ "$elapsed" -lt 20 ] || fail "the model probe was not cut off by its bound (took ${elapsed}s)"
  assert_contains "$out" "did not answer within 1s" "a hung listing launched without its timeout notice"
  assert_contains "$(cat "$CASE_DIR/launch.log")" "--model 'swe-2-medium'" \
    "a hung listing dropped the requested model instead of launching it unvalidated"
  pass "fm-spawn: a hung devin listing is cut off by its bound and launches unvalidated"
}

test_devin_spawn_pre_registers_trust_and_skips_the_dialog() {
  local id rec out rc store
  id="devin-trustpre-z8-$$"
  rec=$(make_devin_spawn_case trustpre "$id")
  read_devin_spawn_record "$rec"
  out=$(run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$id" \
    --model swe-2-medium)
  rc=$?
  expect_code 0 "$rc" "a pre-registered worktree should spawn cleanly: $out"
  store="$HOME_DIR/.local/share/devin/cli/trusted_workspaces.json"
  assert_devin_trusted "$store" "$WT_DIR" "the spawn did not pre-register the worktree in devin's own store"
  assert_devin_trusted "$store" "/home/someone/elsewhere" "the spawn dropped an existing trusted_paths entry"
  [ -s "$HOME_DIR/state/$id.devin-session" ] \
    || fail "the readiness gate reported success without devin's session sidecar"
  pass "fm-spawn: devin trust is pre-registered and the gate proves the session started"
}

test_devin_gate_answers_a_dialog_that_renders_anyway() {
  local id rec out rc
  id="devin-dialog-z9-$$"
  rec=$(make_devin_spawn_case dialog "$id")
  read_devin_spawn_record "$rec"
  out=$(FM_FAKE_DEVIN_IGNORE_TRUST=1 run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" \
    "$FAKEBIN_DIR" "$id" --model swe-2-medium)
  rc=$?
  expect_code 0 "$rc" "the gate must answer a dialog the pre-registration did not remove: $out"
  [ -s "$HOME_DIR/state/$id.devin-session" ] \
    || fail "the gate reported success without devin's session sidecar"
  pass "fm-spawn: the devin gate answers a folder-trust dialog that renders anyway"
}

test_devin_gate_fails_the_spawn_when_no_session_starts() {
  local id rec out rc
  id="devin-stuck-z10-$$"
  rec=$(make_devin_spawn_case stuck "$id")
  read_devin_spawn_record "$rec"
  rc=0
  out=$(FM_FAKE_DEVIN_IGNORE_TRUST=1 FM_FAKE_DEVIN_ANSWER=stuck \
    run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$id" \
    --model swe-2-medium) || rc=$?
  [ "$rc" -ne 0 ] || fail "a devin pane whose session never starts must fail the spawn"
  assert_contains "$out" "did not start its session" "the gate failure lacked its concrete reason"
  assert_grep 'failed:' "$HOME_DIR/state/$id.status" "the gate failure was not recorded in the task status"
  pass "fm-spawn: a devin pane whose session never starts fails the spawn and is cleaned up"
}

test_devin_gate_ignores_a_sidecar_from_a_previous_incarnation() {
  local id rec out rc marker
  id="devin-stalesidecar-z13-$$"
  rec=$(make_devin_spawn_case stalesidecar "$id")
  read_devin_spawn_record "$rec"
  # A spawn that timed out just as its predecessor's SessionStart landed leaves
  # this file behind, and a plain re-dispatch of the same task id retires no
  # wiring. Only this launch's own session may satisfy the gate.
  marker="$HOME_DIR/state/$id.devin-session"
  printf '{"hook_event_name":"SessionStart","session_id":"previous-incarnation"}' > "$marker"
  rc=0
  out=$(FM_FAKE_DEVIN_IGNORE_TRUST=1 FM_FAKE_DEVIN_ANSWER=stuck \
    run_devin_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$id" \
    --model swe-2-medium) || rc=$?
  [ "$rc" -ne 0 ] || fail "a stale session sidecar must not satisfy the readiness gate"
  assert_contains "$out" "did not start its session" "the gate failure lacked its concrete reason"
  pass "fm-spawn: the devin gate ignores a session sidecar left by a previous incarnation"
}

test_devin_secondmate_launch_is_refused() {
  local id rec out rc
  id="devin-secondmate-z11-$$"
  rec=$(make_devin_spawn_case secondmate "$id")
  read_devin_spawn_record "$rec"
  rc=0
  out=$(HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" XDG_DATA_HOME="$HOME_DIR/.local/share" \
    FM_ROOT_OVERRIDE='' FM_HOME="$HOME_DIR" \
    FM_STATE_OVERRIDE="$HOME_DIR/state" FM_DATA_OVERRIDE="$HOME_DIR/data" \
    FM_PROJECTS_OVERRIDE="$HOME_DIR/projects" FM_CONFIG_OVERRIDE="$HOME_DIR/config" \
    FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$WT_DIR" TMUX="fake,1,0" \
    PATH="$FAKEBIN_DIR:$BASE_PATH" \
    "$SPAWN" "$id" "$PROJ_DIR" --harness devin --secondmate 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "a devin secondmate launch must be refused"
  assert_contains "$out" "crewmate/scout adapter only" "the secondmate refusal lacked its reason"
  [ -s "$CASE_DIR/launch.log" ] && fail "a refused secondmate still built a launch command" || true
  pass "fm-spawn: a devin secondmate launch is refused before anything is provisioned"
}

test_devin_ancestry_detects_the_native_command_name
test_devin_ancestry_detects_the_acp_agent_child
test_devin_ancestry_rejects_unrelated_mentions
test_devin_promotes_no_environment_marker
test_devin_control_mechanics_are_the_verified_ones
test_devin_relaunch_retires_its_own_wiring
test_devin_busy_source_is_trusted_only_for_devin
test_devin_classify_reads_its_hook_record
test_devin_busy_signatures_are_harness_scoped
test_devin_tmux_names_the_native_binary_an_agent
test_devin_trust_registers_the_resolved_worktree_path
test_devin_trust_creates_a_missing_store
test_devin_trust_refuses_out_of_scope_paths
test_devin_launch_carries_the_brief_model_and_autonomy
test_devin_config_merges_the_user_config_and_forces_attribution_off
test_devin_effort_is_recorded_but_never_launched
test_devin_unlisted_model_refuses_before_pane_creation
test_devin_accepts_family_ids_and_aliases
test_devin_accepts_a_family_id_from_a_padded_header
test_devin_unreachable_listing_launches_unvalidated
test_devin_hung_listing_is_cut_off_and_launches
test_devin_spawn_pre_registers_trust_and_skips_the_dialog
test_devin_gate_answers_a_dialog_that_renders_anyway
test_devin_gate_fails_the_spawn_when_no_session_starts
test_devin_gate_ignores_a_sidecar_from_a_previous_incarnation
test_devin_secondmate_launch_is_refused
