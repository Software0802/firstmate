# Verification: the devin (Devin CLI) crewmate/scout adapter

Active empirical facts for firstmate's devin adapter.
The skill tree rooted at [`.agents/skills/harness-adapters/SKILL.md`](../../.agents/skills/harness-adapters/SKILL.md) owns the operating facts through [`references/harness/devin.md`](../../.agents/skills/harness-adapters/references/harness/devin.md); this record owns how they were established and what is still unproven.

## Subject

| Field | Value |
|---|---|
| Version | `devin 3000.10.31 (b98cc431)` |
| Verified | 2026-09-19 |
| Binary | `~/.local/bin/devin`, a symlink into `~/.local/share/devin/cli/_versions/current/bin/devin`, an ELF 64-bit compiled single executable |
| Platform | Linux x64 (WSL2, kernel 6.18.33.1-microsoft-standard-WSL2) |
| Account | `devin auth status` reports `Logged in (via Devin).`, tier `Devin Max` |
| Backend | tmux, on a private server socket for the signal probes and through an isolated `FM_HOME` for the end-to-end spawn |

Every command below ran inside the disposable firstmate task worktree, a scratch directory under the session scratchpad, or an isolated `FM_HOME`.
The one shared artifact any of it touched is devin's own `trusted_workspaces.json`; every probe entry written into it was removed afterwards and the file was confirmed back at its original single-entry content.
No captain fleet state was touched.

## Detection: ancestry only, no marker

```
$ devin --version
devin 3000.10.31 (b98cc431)
```

devin runs a two-process model.
A tool subprocess's `ps -ef` view during a live turn:

```
luzhiku 189641 189639 devin --model swe-2-medium --permission-mode dangerous -p ...
luzhiku 189688 189641 /home/luzhiku/.local/share/devin/cli/_versions/3000.10.31/bin/devin acp
luzhiku 189802 189688 bash -c env | sort > ...
```

The front end and the `devin acp` agent child both carry the process name `devin`, so the anchored ancestry match reaches a tool subprocess through either.

The environment of that same tool subprocess carries no `DEVIN_*` variable at all.
It carries `CHISEL_SESSION_DB=/home/luzhiku/.local/share/devin/cli/sessions.db` and an inherited `CLAUDECODE=1` and `AI_AGENT=claude-code_2-1-278_agent` from the launching environment.
`CHISEL_SESSION_DB` is a session-database PATH rather than an identity, the same class as muse's `MUSE_CURRENT_SESSION_LOG`, so it is not promoted to a marker.
`DEVIN_PROJECT_DIR` appears only in HOOK process environments, never in tool subprocesses, so it is not a marker either.

`bin/fm-harness.sh` therefore matches the anchored process name `devin` alone, and the spawn clears `CLAUDECODE`, `PI_CODING_AGENT`, `GROK_AGENT`, and `FM_PI_HARNESS` at the launch boundary.
`tests/fm-devin-harness.test.sh` pins the anchored match on both process shapes, the rejection of unrelated names containing the fragment, the refusal to promote either devin-adjacent variable, and that an inherited `CLAUDECODE` never outranks a real `devin` ancestor.

## Launch: a prompt after `--`, with auto-submit

```
$ devin --config <per-task config> --model swe-2-medium --permission-mode dangerous -- 'Reply with exactly the word READY and nothing else, then stop.'
```

The brief submitted itself with no extra Enter and the reply rendered in the pane.
The bare positional `[PATH]...` form is deliberately unused: `devin --help` documents it as "Open Devin Desktop on the given path(s)", so the worktree comes from the pane's own cwd and the brief rides the `--` separator instead.

`--permission-mode dangerous` is required for an unattended worker.
Without it the first tool call parks the pane on an eight-option approval dialog (`1 Yes (Approve once)` through `8 No`), and a non-interactive run refuses outright:

```
warning: rejected a tool call that requires confirmation. Running in non-interactive mode. Use --permission-mode dangerous to auto-approve all tools.
```

With it, the composer's top border renders `(bypass permissions on)` and a real `sleep 40 && echo slept` ran with no gate.

## Trust: pre-registered before launch, gated on the session sidecar

A first launch in a fresh directory shows this dialog:

```
 ✱ Do you trust the authors of this directory?
   For security, devin should not be run in directories with untrusted content.

 /tmp/claude-1000/devin-probe/untrusted

 ❭ 1 Yes, trust
 · 2 No, exit

 ↓↑ to select · ↵ to choose · esc to quit
```

The safe choice is preselected, one Enter answers it, and answering appends the directory to `trusted_paths` in `<data>/devin/cli/trusted_workspaces.json`.
`devin -p` does not show the dialog at all; it refuses with `Error: Refusing to run in an untrusted workspace: <path>`.

Three properties were established by controlled probes, each with only the named path trusted:

- A path listed in `trusted_paths` before launch runs its turn immediately, with no dialog.
- devin compares the RESOLVED path: with only the symlink `/tmp/.../linkdir` trusted, a run from that logical cwd still refused, naming `/tmp/.../realdir`.
- A trusted directory covers its subdirectories: with only `<probe>/proj` trusted, a run from `<probe>/proj/subdir` succeeded.

`bin/fm-devin-trust.sh` therefore records the resolved form and only the resolved form, which is the opposite of agy's logical comparison.
A logical alias for a path devin never compares against would widen a global trust store for nothing.

The decisive property for the readiness gate is that NO devin hook fires while the dialog is on screen.
An untrusted launch carrying a `--config` with four hooks left the hook log directory completely empty for as long as the dialog was up, and `SessionStart` landed only after the Enter that answered it.
The `state/<id>.devin-session` sidecar that hook writes is therefore positive proof of two facts at once: devin cleared the dialog, and it loaded firstmate's config.
That is why the gate waits for the sidecar rather than for a busy verdict: this adapter arms its busy contract at spawn, so the seeded `busy/fm-spawn` record would read busy before devin had even started.
The spawn clears the sidecar beside the per-task config it composes, before the launch, because that proof is only worth anything for THIS incarnation: a spawn whose gate expired just as its predecessor's `SessionStart` landed leaves the file behind, and a plain re-dispatch of the same task id retires no wiring.

`--respect-workspace-trust false` also suppresses the check, and unlike gemini's `--skip-trust` it leaves project configuration loaded - all four hooks from a project `.devin/hooks.v1.json` fired under it in an untrusted directory.
The adapter still does not use it: an explicit per-worktree grant is auditable where a blanket per-launch bypass is not.
Like claude's and agy's, the entries the spawn writes are not pruned at teardown.

## Hook lifecycle: a verified open/close triple plus a session sidecar

One interactive pane, three prompts, then `/exit`, with every hook appending its stdin payload to a log:

| Hook | Fired | Payload evidence |
|---|---|---|
| `SessionStart` | once | `{"hook_event_name":"SessionStart","source":"startup","session_id":"tidal-mouth"}` |
| `UserPromptSubmit` | 3 | `{"hook_event_name":"UserPromptSubmit","prompt":"...","session_id":"tidal-mouth","prompt_id":"f26521fd-..."}` |
| `Stop` | 2 | `{"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"READY","session_id":"tidal-mouth","prompt_id":"..."}` |
| `SessionEnd` | once | `{"hook_event_name":"SessionEnd","reason":"prompt_input_exit","session_id":"tidal-mouth","prompt_id":"..."}` |

Three prompts against two `Stop` events is the load-bearing asymmetry: the second prompt was cancelled with a manual interrupt and fired NO `Stop`, and none arrived in the fifteen seconds after.
The third prompt's `Stop` then closed the record.
So devin's own wiring leaves a cancelled turn open - the claude gap, not gemini's self-closing one - and `fm_control_interrupt_ack_source devin` is `none` for that reason: the cancellation is rendered, never recorded by the adapter.
Whichever plane delivered the interrupt closes the record instead, writing `idle`/`fm-interrupt` bound to the running incarnation.
`bin/fm-control.sh <id> interrupt` is the sanctioned one and does it after the full sequence is delivered and verified, and so does `bin/fm-control.sh <id> exit` when it interrupts a busy task before typing the exit command, so an exit that then cannot prove the agent stopped still leaves no cancelled turn recorded busy.
`bin/fm-send.sh --key Escape` does the same after delivering the sequence itself.
Both read WHICH adapters need that close, and how many presses the sequence is, from `bin/fm-control-lib.sh` rather than deciding it twice.
The interrupt is not the only end this triple cannot report; see "The one turn end devin cannot report" below for the API-error end, which no plane of firstmate's delivers and no devin hook fires for.
That ordering is load-bearing for devin specifically, because a single Escape merely ARMS the second press and the turn carries on, so recording after one press would report idle for a running worker.
`tests/fm-devin-signals-live-e2e.test.sh` asserts that gap is still open, so a release that closes it fails loudly instead of leaving an unverified assumption in place.

A hook command needs no stdout JSON, unlike gemini's: every probe hook wrote only to a file and devin's lifecycle was unaffected.
Each wired hook still drains its stdin payload so devin never writes into a closed pipe.
The payload arrives with no trailing newline, which is worth recording because it is a silent trap for any hook that appends payloads to one file: a plain `cat >> log` runs successive events together on one line, and a line count of that file then reads 1 no matter how many events fired.
`tests/fm-devin-signals-live-e2e.test.sh` terminates each record itself and counts occurrences rather than lines for exactly that reason.

## The per-task config, and why it merges

`--config <PATH>` overrides `~/.config/devin/config.json`, devin's USER layer, rather than adding to it.
Writing a bare hooks object there would discard the captain's own settings for every worker, so the spawn merges: the composed file for the live smoke carried `devin.org_id`, `agent.model`, and `theme_mode` from the captain's config alongside firstmate's four hooks.
Credentials are not in that file - `devin auth status` reports them at `<data>/devin/credentials.toml` - so the merged copy carries no secret, and an `XDG_DATA_HOME` probe confirmed devin resolves that data root through XDG (`XDG_DATA_HOME=/tmp/... devin auth status` reported `Not logged in.` with `Credentials path: /tmp/.../devin/credentials.toml`).

`attribution` is the other reason the config rides the user layer: devin defaults it ON, adding a `Generated with [Devin]` line and a `Co-Authored-By` trailer to every commit and pull request, and `devin --help`'s own config reference marks it USER-ONLY, unavailable in a project layer.
`AGENTS.md` section 1 forbids an agent commit co-author, so the composed config sets `attribution: false`, the same shape the claude adapter uses for its per-launch attribution policy.
Project and project-local layers still load and take precedence over the file, so a project's own hooks and permissions keep working.

`read_config_from.claude: false` is the third key the spawn pins, and for the same reason: devin imports Claude Code's config by default, so a devin crewmate dispatched into a firstmate worktree would load that repo's committed `.claude/settings.json` and run claude's `PreToolUse` and `Stop` hooks, every one of which resolves `$CLAUDE_PROJECT_DIR` - a variable devin does not set, because it sets `DEVIN_PROJECT_DIR` instead.
The shape of the key was measured on devin 3000.10.31 rather than assumed: a deliberately wrong value makes devin report `Ignoring invalid value for "read_config_from" ...  Using the default ({"cursor":null,"windsurf":null,"claude":null,"opencode":null,"zed":null,"copilot":null,"agents_standard":null})`, and `{"read_config_from":{"claude":false}}` is accepted with no warning.
Only `claude` is pinned, and the captain's own entries are merged under it, so `agents_standard` keeps its default and `AGENTS.md` still reaches the worker.

## Rendered surface

The running turn's status row is the one stable ASCII busy token:

```
⢠⡀ Running tools · 5s (esc twice to interrupt)
```

After a single Escape the same row reads `esc again to interrupt` while the turn keeps running, so both spellings are registered or an interrupted-then-resumed pane would read idle mid-turn.
The phase word beside the braille spinner is model-driven and varied between `Thinking` and `Running tools` inside one turn, so it is not matched.

The busy token renders about 0.17s after Enter, measured over three submits in one pane (0.168s, 0.161s, 0.161s) for both a short steer and a 180-character one.
That is well inside `fm-send`'s shared three-retry budget, so devin takes no per-harness submit-confirm override the way agy does.

Getting a line INTO the composer in the first place has two quirks, both found by building the live guard and both already covered by the shared settle-and-retry submit core rather than by anything devin-specific.
An Enter delivered immediately after a typed line is taken as a NEWLINE inside the composer rather than a submit: the line stays visible on the composer row, a blank row appears beneath it, and a second Enter then submits both.
Typed input delivered while devin is repainting after a turn is dropped entirely, and a pane captured during that repaint reads blank, so a naive "type once, then press Enter" sequence can leave nothing to submit.
The real steer path was unaffected - `bin/fm-send.sh` delivered `STEER_OK` into the live smoke pane and the worker ran it - because `fm_backend_send_text_submit` already settles and retries.
The live guard therefore waits for a painted pane before typing and drives its Enter retry off devin's own `UserPromptSubmit` hook rather than off rendered text.

The composer's prompt glyph is `❭` (U+276D, bytes `e2 9d ad`), with the idle placeholder `Ask Devin to build features, fix bugs, or work on your code` and the mid-turn placeholder `Guide Devin while it works`.
devin parks its terminal cursor INSIDE the composer (`#{cursor_y}` on the composer row, `#{cursor_x}` 2, `#{cursor_flag}` 1), unlike cursor-agent.
The placeholder is drawn muted, and devin picks its SPELLING from the terminal rather than from its own design.
Two panes on the same host, running the same command in the same directory, captured the same row two ways:

```
COLORTERM=truecolor   ESC[39m❭ ESC[38;2;124;124;124mAsk Devin to build features, fix bugs, or work on your codeESC[39m
no COLORTERM          ESC[39m❭ ESC[38;5;244mAsk Devin to build features, fix bugs, or work on your codeESC[39m
```

A tmux server started by a daemon, a cron job, or a non-truecolor ssh session is the second shape, and it is the default one on this host.
`fm_composer_strip_ghost` originally luminance-tested truecolor only, so the second pane kept its placeholder, `fm_backend_composer_state` returned `pending` on a genuinely empty composer, and `bin/fm-control.sh <id> exit` refused with "composer visibly holds pending text" - the worker could not be stopped from that pane at all, and `bin/fm-send.sh` skipped its doorbell for the same reason.
The stripper now luminance-tests both spellings, mapping palette entries 16-255 through the standard xterm cube and grayscale ramp and leaving the theme colours 0-15 alone.
The cutoff is inclusive because the ramp rounds devin's 124-grey UP to entry 244, which is exactly `128,128,128`, exactly the default `FM_COMPOSER_GHOST_LUMA_MAX`.
Both panes now classify the same:

```
$ fm_backend_composer_state tmux firstmate:fm-devin-smoke-1
empty
```

That verdict is what makes `fm-control.sh exit` usable: before the glyph and placeholders were registered it read `unknown` and the control plane refused to type `/exit` rather than risk concatenating onto unseen text.

## The one turn end devin cannot report

devin's hook vocabulary in the 3000.10.31 binary is `PreToolUse`, `PostToolUse`, `PostCompaction`, `SessionStart`, `SessionEnd`, `PermissionRequest`, `Stop`, `SubagentStop`, and `UserPromptSubmit`.
There is no `StopFailure` equivalent, the hook that closes claude's record when a turn dies on an API error, so devin's `UserPromptSubmit` can open a turn that nothing ever closes.
Reproduced live on an account whose paid allowance was drained: a `kimi-k3-max` launch submitted its brief, the turn ended on `Quota exhausted`, the worker returned to an empty composer, and `state/<id>.busy-state` still read `state=busy source=devin-hook event=user-prompt-submit` a minute later, so `bin/fm-crew-state.sh` kept reporting `state: working · source: pane · harness busy (devin-hook)` for an idle worker.
Only a LATER turn's `Stop` could have closed it, which for an abandoned worker never comes.

`fm_busy_devin_turn_contradicted` in `bin/fm-busy-lib.sh` closes that hole from the read side, and it is deliberately the narrowest thing that can: it never produces a verdict of its own, it only CONTRADICTS an already-open record, and the verdict it produces is `unknown devin-turn-contradicted`, never `idle`, because the approved redesign forbids rendered text from proving a worker settled.
It requires both of devin's verified rendered facts at once - the in-flight token (`esc twice|again to interrupt`) absent AND the idle placeholder back on the composer row - so the two panes that could lie both fail closed: a turn in flight renders the token and the `Guide Devin while it works` placeholder instead, and a pane captured mid-repaint renders neither.
An unreadable or empty capture leaves the record's own verdict standing.
This is the same invariant the interrupt and exit record-closes hold, reached through the one path no plane of firstmate's ever touches.

## Interrupt: two Escapes, back to back

One Escape only rewrites the status row from `esc twice to interrupt` to `esc again to interrupt`; the turn continues.
A second Escape sent seconds later was absorbed and the row reverted, so the pair must be delivered promptly - which is exactly what `bin/fm-control.sh` does.
Sent back to back, the pair cancels:

```
 ✗ Canceled due to user interrupt
 └ Running in background

 ✱ Canceled. What should Devin do?
```

The composer returns to its idle placeholder with no repollution, so no clear key follows.

## End-to-end through the real spawn

One scout task in an isolated `FM_HOME` on tmux, against the real binary and a real treehouse worktree:

```
$ bin/fm-spawn.sh devin-smoke-1 <project> --harness devin --scout --model swe-2-medium
spawned devin-smoke-1 harness=devin kind=scout window=firstmate:fm-devin-smoke-1 worktree=/home/luzhiku/.treehouse/proj-a8d2ef/1/proj
```

The spawn pre-registered the worktree, composed `state/devin-smoke-1.devin-config.json` (merged, `attribution: false`), and returned only after `state/devin-smoke-1.devin-session` appeared.
The worker replied `DEVIN_SPAWN_OK` to its brief.
The recorded state tracked the turn through devin's own hooks:

```
v1 gen=g1789817586.376681.16415 seq=2 state=busy source=devin-hook event=user-prompt-submit
v1 gen=g1789817586.376681.16415 seq=3 state=idle  source=devin-hook event=stop
$ bin/fm-crew-state.sh devin-smoke-1
state: working · source: pane · harness busy (devin-hook)
```

`state/devin-smoke-1.turn-ended` was touched by the `Stop` hook.
The rest of the lifecycle ran against that same live pane:

```
$ bin/fm-control.sh devin-smoke-1 interrupt
interrupt-delivered devin-smoke-1 harness=devin backend=tmux verified=agent-alive cancel=unconfirmed
$ bin/fm-send.sh devin-smoke-1 "Reply with exactly: STEER_OK"      # inbox record + doorbell landed and ran
$ bin/fm-control.sh devin-smoke-1 exit
stopped devin-smoke-1 harness=devin backend=tmux endpoint=firstmate:fm-devin-smoke-1 worktree=...
$ bin/fm-control.sh devin-smoke-1 relaunch --note '...'
relaunched devin-smoke-1 harness=devin from=devin model=swe-2-medium effort=default backend=tmux ...
$ bin/fm-teardown.sh devin-smoke-1
teardown devin-smoke-1 complete (window firstmate:fm-devin-smoke-1, worktree ...)
```

That interrupt left the busy record untouched, because the smoke ran before the control plane took over closing it.
Both verbs now write `idle`/`fm-interrupt` themselves once the full sequence is delivered and verified, the contract the hook-lifecycle section above owns.
The relaunch minted a fresh busy generation (`g1789817836.505320.12981`) and a fresh devin session id (`dour-rain`, replacing `flashy-bath`), proving the wiring is re-armed rather than adopted.
Teardown left `state/` holding none of the task's files, including the per-task config and the session sidecar.

## Models

`devin models list` printed 48 families, from which `devin_model_ids` in `bin/fm-spawn.sh` extracts 441 selectable tokens: every concrete id, every family id, and every alias.
`--model` accepts all three forms; `devin --help` names `"claude-sonnet-4"`, `"claude-opus-4.6"`, `"opus"`, and `"codex"` together as examples.
The captain's four named ids - `kimi-k3-max`, `swe-2-max`, `swe-2-medium`, and `fusion-claude-fable-5-1-medium-sidekick-swe-2-medium` - are all present, as are the family ids `swe-2` and `fusion` and the aliases `opus`, `claude`, `sonnet`, `gemini`, `gpt`, and `swe`.

## Effort: no flag, and why none is synthesized

`devin --help` on 3000.10.31 exposes no effort, reasoning, or thinking flag.
The thinking level is encoded in the model id instead - `claude-opus-5-low` through `claude-opus-5-max`, `swe-2-medium`, `kimi-k3-high` - and cycled interactively with `alt+t`, which the idle footer advertises as `Press alt+t to cycle thinking levels`.
No family-plus-level mapping is synthesized from a requested `--effort`, because the families do not offer the same levels: SWE-2 lists high, medium, and max with no low or xhigh, Kimi K3 lists high, low, and max with no medium, and Gemini 3.8 Flash lists medium, low, and high only.
The record-and-omit contract therefore applies: the requested level stays in task metadata and never reaches the launch command.

## Account allowance

The TUI banner reports the account's remaining paid allowance, `Max · 0% remaining (resets in 20h 42m)` throughout this verification.
Every probe therefore ran on the free `swe-2-medium` model, and no paid-model launch was exercised.
A drained account does not block dispatch on the free SWE-2 family, but it is worth reading before dispatching a paid model.
`quota-axi` has no `devin` provider (its `--provider` list is claude, codex, cursor, copilot, grok, kimi, zai, agy, alibaba, opencode-go, commandcode), so a devin dispatch profile must declare `provider` explicitly rather than resolving through the single-provider table.

## What is not verified

Primary and secondmate use.
`docs/supervision-protocols/` carries no devin protocol, no turn-end guard adapter exists for it, and no pre-tool watcher-arm seatbelt has been built for its `PreToolUse` event, so `bin/fm-spawn.sh` refuses a devin secondmate.

Any backend other than tmux.
The end-to-end spawn, the composer read, and every signal probe ran on tmux, leaving Herdr, zellij, cmux, and Orca unexercised for devin.
Herdr's registry recognizing the process name `devin` was reported but not measured here.

Native resume.
`devin -r <session-id>`, `devin -r`, and `-c`/`--continue` all exist and the exit line advertises the first, but no pane-resume contract was exercised, so deterministic relaunch is what this adapter uses.

macOS, because every measurement above is Linux, and paid-model launches, for the account reason above.

What devin's claude import actually does to a session, because the crewmate adapter turns it off rather than measuring it.
The per-task config pins `read_config_from.claude: false`, whose accepted shape was measured live, so neither `~/.claude/settings.json` nor a worktree's `.claude/settings.json` reaches a devin worker.
Any future devin primary work that wants that import back has to establish devin's blocking semantics for a failed `PreToolUse` hook first.

Whether `subagents_enabled` should be forced off for a worker.
devin defaults it on, and `docs/subagent-guard.md` scopes that concern to a PRIMARY creating work outside firstmate's durable records, which a crewmate does not, so the default is left in place deliberately rather than by omission.

## Refresh

```
FM_DEVIN_SIGNALS_LIVE=1 bin/fm-test-run.sh tests/fm-devin-signals-live-e2e.test.sh
```

That guard passed all ten checks on 2026-09-19 against devin 3000.10.31: the dialog's hook silence, `SessionStart` after the answer, the launch reply, the `UserPromptSubmit`/`Stop` bracket, the settled composer, the busy token in flight, one Escape arming rather than cancelling, the pair cancelling, the absent interrupt `Stop`, and `/exit` with its `SessionEnd`.

That guard submits real prompts, so it is opt-in.
It stages a throwaway `XDG_DATA_HOME` copy of the operator's devin data directory, so its trust answer never reaches the real store.
The portable regression `tests/fm-devin-harness.test.sh` runs everywhere and needs no devin install.
