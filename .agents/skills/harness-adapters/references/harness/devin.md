# Devin CLI

Cognition's `devin` TUI, verified end to end on 2026-09-19 with devin 3000.10.31 on Linux.
Verified as a CREWMATE and SCOUT adapter only; `../../../../../bin/fm-spawn.sh` refuses a secondmate launch on it because `../../../../../docs/supervision-protocols/` carries no devin wake protocol.
`../../../../../docs/verification/devin.md` owns how every fact below was established and what is still unproven.

## Operating facts

| Fact | Value |
|---|---|
| Binary | Absolute `devin` from `PATH`, refused if absent; a compiled single binary reached through a versioned symlink, so the live process name is exactly `devin`. It runs a two-process model - the front end plus a `devin acp` agent child - and both report `comm=devin`. |
| Launch | `devin --config <per-task config> --permission-mode dangerous --model <id> -- "<brief>"`, with the resolved absolute binary; the brief auto-submits with no extra Enter. The spawn pre-registers the worktree in devin's trust store first, then waits for devin's own `SessionStart` hook to write the session sidecar (answering the folder-trust dialog if it renders anyway) before reporting success. |
| Busy state | Semantic `devin-hook`: `UserPromptSubmit` opens a turn, `Stop` and `SessionEnd` close it. `Stop` does NOT fire on a manual interrupt - the claude gap, not the gemini one - so `../../../../../bin/fm-control.sh <task-id> interrupt` closes the record itself with `idle`/`fm-interrupt` once it has delivered the full sequence, verified it, and watched the `(esc twice|again to interrupt)` token clear from the visible pane, as does the `exit` verb's own interrupt of a busy task; a worker is never left recorded busy at an idle composer. An absorbed second Escape leaves that token rendered and the turn running, so the record is left busy and the verb reports `busy-record=left-busy` rather than recording an idle worker that is still working. devin's hook vocabulary also has no `StopFailure` equivalent, so a turn that dies on an API error (a quota rejection, a 5xx, a dropped connection) fires nothing at all; `../../../../../bin/fm-busy-lib.sh` therefore corroborates a `devin-hook` record opened by `UserPromptSubmit` against devin's own rendered composer and downgrades it to `unknown devin-turn-contradicted` when the in-flight token is absent AND the idle placeholder is back on the composer row. That contradiction can only produce `unknown`, never `idle`: rendered text still may not prove a worker settled. It touches no other record devin trusts - the `fm-spawn` launch-brief seed and an `fm-recovery` reset are written before devin has the prompt, so its idle composer is the expected surface there. |
| Rendered tail | Not a state source, but the running turn's status row carries the one stable ASCII busy token: `(esc twice to interrupt)`, which becomes `(esc again to interrupt)` after a single Escape and is absent when idle. The phase word beside the braille spinner is model-driven and varied between `Thinking` and `Running tools` inside one turn; neither it nor the spinner is ever a signal. |
| Turn end | `Stop` fires once per COMPLETED turn carrying `stop_hook_active`, `last_assistant_message`, `session_id`, and `prompt_id`, and keeps the `state/<id>.turn-ended` touch as the watcher NOTIFICATION. `SessionEnd` fires once on `/exit` with reason `prompt_input_exit`. |
| Exit | `/exit` (alias `/quit`), ONE Enter; the slash popup does not swallow it for an exact match. The process exits and prints `Resume this session with 'devin -r <session-id>'`. |
| Interrupt | `Escape` TWICE, delivered back to back. One Escape only rewrites the status row to `esc again to interrupt`; a second press seconds later was absorbed and the turn carried on. The pair prints `Canceled due to user interrupt` and `Canceled. What should Devin do?`, and the composer returns to its idle placeholder with no repollution, so no clear key follows. |
| Skill | `/<skill>`, for example `/no-mistakes`; ONE Enter submits. devin discovers firstmate's user skills from `~/.agents/skills/` and a project's own from `.agents/skills/`. |
| Autonomy | `--permission-mode dangerous` auto-approves every tool call and renders `(bypass permissions on)` on the composer's top border. Without it the first tool call parks the pane on an eight-option approval dialog. |
| Marker | None; a live tool subprocess carries no `DEVIN_*` variable at all. `DEVIN_PROJECT_DIR` is set for HOOK processes only, and `CHISEL_SESSION_DB` is a session-database path, not an identity - see Detection below. |
| Resume | `devin -r <session-id>` (the id the spawn's session sidecar records), `devin -r` for a picker, and `-c`/`--continue`; none carries a verified pane-resume contract, so use deterministic relaunch. |
| Model | `--model <id>` accepting a concrete id, a family id, or an alias from `devin models list` (for example `swe-2-max`, `kimi-k3-max`, `fusion-claude-fable-5-1-medium-sidekick-swe-2-medium`, or the family `swe-2`); `bin/fm-spawn.sh` refuses a requested id a reachable listing omits. The listing is a remote fetch, so the probe runs stdin-detached under the shared hard bound and an unreachable or hung listing launches unvalidated with a notice. |
| Effort | None. `devin --help` on 3000.10.31 exposes no effort, reasoning, or thinking flag, so `references/common/model-and-effort.md`'s record-and-omit contract applies. The thinking level is instead encoded IN the model id (`-low`, `-medium`, `-high`, `-xhigh`, `-max`) and cycled interactively with `alt+t`, so express effort by choosing the model id. Families do not all offer every level, which is why no family-plus-level mapping is synthesized. |
| Composer | Bordered row whose prompt glyph is `❭` (U+276D), with the idle placeholder `Ask Devin to build features, fix bugs, or work on your code` and the mid-turn placeholder `Guide Devin while it works`. Both placeholders are drawn muted, and devin picks the SPELLING from the terminal: truecolor `38;2;124;124;124` when the pane advertises `COLORTERM`, 256-colour `38;5;244` when it does not (a tmux server started by a daemon, a cron job, or a non-truecolor ssh session). The shared ghost stripper luminance-tests both, so a styled capture strips the placeholder either way and the classifier reads the idle composer as `empty` - which is what lets the control plane type `/exit` at all. |
| Submit | Two quirks, both covered by the shared settle-and-retry submit core rather than by anything devin-specific. An Enter delivered immediately after a typed line is taken as a NEWLINE inside the composer, not a submit, so the line needs a second Enter. Typed input delivered while devin repaints after a turn is dropped entirely, and a pane captured mid-repaint reads blank. Once submitted, devin renders its busy token about 0.17s after Enter for both short and long steers, well inside the shared submit-confirm budget, so devin takes no per-harness `fm-send` retry override the way agy does. |

## Trust, and where the decision persists

Every task worktree is a path devin has never seen, so an unregistered launch stops on `Do you trust the authors of this directory?` with the safe choice `❭ 1 Yes, trust` preselected, and NO devin hook fires while that dialog is on screen.
`devin -p` refuses outright instead, with `Refusing to run in an untrusted workspace`.
`--respect-workspace-trust false` does suppress the check and, unlike gemini's `--skip-trust`, leaves project configuration loaded, but the adapter does not use it: an explicit per-worktree grant is auditable where a blanket per-launch bypass is not.

devin honours a `trusted_paths` entry written ahead of launch, so `../../../../../bin/fm-spawn.sh` pre-registers the worktree through `../../../../../bin/fm-devin-trust.sh` before launch, the claude and agy shape: the helper refuses anything but a linked worktree of the spawning project, writes only the launching user's own store, and preserves every other key and entry.
The store is `<data>/devin/cli/trusted_workspaces.json`, where `<data>` follows `XDG_DATA_HOME` and defaults to `~/.local/share`.
devin compares the RESOLVED path, the opposite of agy: trusting only a symlink's own path still refused, naming the resolved target, so the resolved form is the one entry the helper writes and no logical alias is added beside it.
A trusted directory covers its subdirectories.

The post-launch readiness gate is the backstop: it answers a dialog that renders anyway with a single Enter, then requires the `state/<id>.devin-session` sidecar devin's own `SessionStart` hook writes.
That sidecar, not a busy verdict, is the proof, because this adapter ARMS its busy contract at spawn and the seeded record would read busy before devin had even started.
The spawn clears that sidecar before launching, so a file left by a previous incarnation of the same task id can never answer the gate for a pane that is still on the dialog.
A pane whose session cannot be confirmed fails the spawn, records the failure in the task status, and closes the endpoint.
Never steer into a pane still showing the dialog; a spawn that reported success has already cleared it.

## Credential precondition

A verified devin worker ran under an account signed in with `devin auth login`, whose credentials live in `<data>/devin/credentials.toml` and NOT in the config file the launch replaces.
`devin auth status` prints `Logged in (via Devin).` plus the account tier; an unauthenticated install prints `Not logged in.` and names the credentials path it wants.
Treat any auth prompt or refusal as a credential blocker under `../../../../../AGENTS.md` section 9, fix the environment, and retire the endpoint rather than typing into it.
The TUI also renders the account's remaining paid allowance on its banner (`Max · 0% remaining (resets in 20h 42m)`), which is worth reading before dispatching a paid model: a drained account still runs the free SWE-2 family.

## Commit attribution

devin's `attribution` option defaults to ON and adds a `Generated with [Devin]` line and a `Co-Authored-By` trailer to every commit and pull request a worker makes, which `../../../../../AGENTS.md` section 1 forbids.
It is a USER-layer-only option, so the spawn carries `attribution: false` in the per-task config below rather than relying on the captain's own settings, the same reason the claude adapter carries its attribution policy per launch.

## Detection

Detected by ancestry alone: `../../../../../bin/fm-harness.sh` matches the anchored process name `devin`, never `*devin*`.
No environment marker is promoted.
A live tool subprocess carried no `DEVIN_*` variable; `DEVIN_PROJECT_DIR` reaches hook processes only, and the internal `CHISEL_SESSION_DB` it does export to tool subprocesses is a session-database PATH rather than an identity, the same reason muse's `MUSE_CURRENT_SESSION_LOG` is not promoted.
devin does not clear an inherited `CLAUDECODE`, so a structural devin ancestor outranks that retained marker, which `../../../../../bin/fm-harness.sh` decides without depending on the spawn's own launch-boundary marker clearing.
devin is deliberately absent from the session-lock name vocabulary in `../../../../../bin/fm-session-lock-lib.sh`, where muse, gemini, agy, and rovo are also absent: a crewmate-only adapter must never own a home session lock.

## Worker busy state and turn end

`../../../../../bin/fm-spawn.sh` writes a firstmate-owned per-task config at `state/<id>.devin-config.json` with four hooks bound to the minted busy generation, and the launch reaches it through `--config`.
This wiring belongs only to the canonical exact `devin` adapter template; a raw devin-shaped launch is an unverified escape hatch that receives no busy-state wiring, no turn-end hook, and therefore no trusted busy state.

`--config` REPLACES devin's user config layer rather than adding to it, so that file is the captain's own `~/.config/devin/config.json` with firstmate's keys merged over it.
Writing a bare hooks object there would silently drop their org binding, default model, and theme for every worker.
Credentials are not in that file, so the merged copy carries no secret.
It is deliberately NOT the worktree's `.devin/config.json`, which is a PROJECT-committed path, and devin's project and project-local layers still load and take precedence over it, so a project's own hooks and permissions keep working.

The same config pins `read_config_from.claude: false`.
devin imports Claude Code's config by default, so without that pin a worker in a firstmate worktree would load the repo's committed `.claude/settings.json` and run claude's `PreToolUse` and `Stop` hooks against `$CLAUDE_PROJECT_DIR`, which devin never sets.
`read_config_from` is an object of per-source booleans and the captain's own entries are merged under the pin, so only `claude` is disabled and `agents_standard` keeps carrying `AGENTS.md` to the worker.

`UserPromptSubmit` records busy, `Stop` records idle and keeps the `state/<id>.turn-ended` touch as the watcher NOTIFICATION, `SessionEnd` records idle so a process shutdown cannot strand a busy record, and `SessionStart` writes the session sidecar instead of a busy event.
Those three are every close the hook vocabulary offers, and none of them fires when a turn dies on an API error, which is why the read-side corroboration in the Busy state row above exists rather than a fourth hook.
Each hook drains its stdin payload so devin never writes into a closed pipe, and each busy command tolerates a refused event so a stale-generation writer can never break devin's own lifecycle.
devin's hook contract needs no stdout JSON, unlike gemini's.
A hook payload arrives with NO trailing newline, so any hook that appends payloads to one file must terminate its own record or successive events run together on one line.
`../../../../../bin/fm-teardown.sh` removes both the config and the sidecar, so nothing survives into a pooled worktree; the trust entry the spawn pre-registered is not pruned, exactly as claude's and agy's are not.

## Primary integration

Unsupported and unverified.
`../../../../../docs/supervision-protocols/` carries no devin protocol, no turn-end guard adapter exists for it, no pre-tool watcher-arm seatbelt has been built for its `PreToolUse` event, and this adapter verified only the crewmate-side launch, busy state, interrupt, and exit.
`references/common/primary-hooks.md`'s unsupported-boundary rule applies: never invent a wake protocol from a similar TUI.
devin's hook surface makes a future primary integration plausible - it exposes `PreToolUse`, `PostToolUse`, `PermissionRequest`, `UserPromptSubmit`, `Stop`, `PostCompaction`, `SessionStart`, and `SessionEnd` - but it remains unbuilt work, not a fact to rely on.
devin also reads Claude Code's own hook files by default, which the crewmate config turns off; any future primary work that wants that import back must first establish devin's blocking semantics for a failed `PreToolUse` hook.
