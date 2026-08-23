# Niri Idle & Lock Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the two Hyprland-specific gaps in the idle/lock experience
(spec Phase 6, the design spec's own "known open risk"): the screensaver
launcher (`bin/omarchy-launch-screensaver`) and the idle service's
screensaver-window tracking (`shell/plugins/services/idle/Service.qml`)
both currently depend on raw Hyprland IPC. A third, previously-assumed gap
— `lock/Service.qml`'s stranded-lock recovery — turned out to be a real
open question, not a known port target: research during this plan's
design found niri's IPC has **no** session-lock-status query or event at
all, and re-reading `bin/omarchy-hyprland-session-locked`'s own comment
suggests the scenario it detects (an orphaned `ext-session-lock-v1` lock
after its client dies) may be a fundamental, protocol-mandated safety
behavior — not a Hyprland bug — meaning niri could plausibly have the
identical failure mode with no equivalent IPC-based way to detect it.
Task 1 is a pure VM investigation to settle this before any code gets
written for it.

**Scope note, confirmed during this plan's design (not assumed from the
spec):** the design spec's idle-timeout claim already holds — idle
detection itself uses the standard `ext-idle-notify-v1` protocol via
Quickshell's `IdleMonitor`, which niri supports, so that part needs no
changes at all. Only the screensaver-window-tracking piece (raw
`Connections { target: Hyprland; onRawEvent }` in `idle/Service.qml`) and
the screensaver *launcher itself* (`bin/omarchy-launch-screensaver`, which
turned out to be far more Hyprland-coupled than the idle service —
per-monitor `hyprctl dispatch focusmonitor`, and a raw `socat` connection
to Hyprland's own event socket for synchronization) need porting.

**Architecture:**
- `shell/plugins/services/niri/Service.qml` gains two signals
  (`windowOpened(var window)`, `windowClosed(int id)`), emitted from its
  existing `handleWindowOpenedOrChanged`/`handleWindowClosed` functions
  (already parsing niri's incremental window events for workspace-occupied
  tracking — this plan reuses that same event flow, not a second socket
  connection).
- `idle/Service.qml` connects to those signals under Niri, reusing its
  *entire* existing compositor-agnostic screensaver-window-tracking logic
  (`handleScreensaverWindowOpened`/`Closed`, the `screensaverWindows` map,
  `IdleModel.screensaverWindowsAfter`) unchanged — only the event *source*
  differs (a `Connections { target: Hyprland }` block already exists;
  Niri's is added as a sibling, gated the same way the rest of this
  project gates compositor-specific code).
- `bin/omarchy-launch-screensaver` gains parallel `niri_focus_monitor`/
  `niri_exec`/`wait_for_screensaver_window` functions alongside the
  existing `hypr_*` ones, selected by `$NIRI_SOCKET` presence (the same
  compositor-detection convention used everywhere else in this project,
  down to the bash level — `bin/omarchy-restart-shell` and friends already
  read env vars this way, this isn't a new pattern for the `bin/` layer).

**Tech Stack:** QML (Quickshell signals/Connections), bash (`niri msg`
CLI, matching the existing script's `hyprctl`/`socat` idioms).

**Spec:** `docs/superpowers/specs/2026-08-23-omarchy-niri-design.md`
(Phase 6, "Known open risk")

## Global Constraints

- Idle-timeout detection (`IdleMonitor` in `idle/Service.qml`) is already
  compositor-agnostic (`ext-idle-notify-v1`) — do not touch it. This plan
  only touches screensaver-window tracking and the launcher script.
- niri's IPC (confirmed via a fresh, complete fetch of `niri-ipc`'s
  `Request`/`Event`/`Action` enums during this plan's design — not assumed)
  has no session-lock-status query. If Task 1's spike finds niri needs a
  stranded-lock recovery, do NOT invent a detection mechanism in this
  plan — that's real, undetermined design work belonging in its own plan.
  This plan only fixes it if the fix is small and obvious from the spike;
  otherwise it documents the finding and stops there.
- niri's window/output identifiers: a window's `app_id` field is the same
  underlying xdg-shell concept Hyprland calls "class" (both are sourced
  from the same protocol-level window property) — no compositor-specific
  configuration of the screensaver's own app-id is needed, the existing
  `--class=org.omarchy.screensaver` / `--app-id=org.omarchy.screensaver`
  terminal flags already used per-terminal in the launcher already produce
  the value niri will report as `app_id`.
- `bin/omarchy-launch-screensaver`'s Hyprland path (`hypr_focus_monitor`,
  `hypr_exec`, the `socat`-based `wait_for_screensaver_window`, the
  monitor-iteration loop) must not change behavior — this plan adds a
  parallel Niri branch, selected by `$NIRI_SOCKET` presence, exactly like
  every other compositor branch in this project.
- No automated test harness covers live QML/Wayland/bash-compositor-IPC
  behavior in this repo. Verification is manual in the VM per task,
  side-by-side against Hyprland. This project's QML/Quickshell work has
  repeatedly shipped real behavioral bugs invisible to static/diff review
  (an env-var null-vs-empty-string bug, a Wayland layer-stacking
  assumption, both from the immediately prior plan) — budget real runtime
  verification, not just a syntax check, for anything non-trivial here.

---

## Task 1: VM spike — does niri need stranded-lock recovery at all? — DONE

**Finding:** yes, niri has the identical stuck-lock behavior Hyprland
does. Reproduced on both compositors: lock the session, kill the
quickshell process from a separate TTY, switch back — the lock screen
stayed up with no live client on both, confirming this is a universal
`ext-session-lock-v1` safety behavior, not a Hyprland-specific bug. niri's
IPC has no session-lock-status query at all, so
`omarchy-hyprland-session-locked`'s detection technique has no niri
equivalent today. Per this task's own instructions, not solved here —
recorded in "What comes after this plan" below as real, confirmed-needed
work for a dedicated future plan.

**Files:** None (investigation only; a follow-up ruling gets recorded in
this plan's own text, not code).

- [ ] **Step 1: Confirm current (Hyprland) stranded-lock behavior as a baseline**

In the VM, Hyprland session: lock the screen (`omarchy-shell lock lock`,
or whatever normally triggers it), then from a **different** TTY
(Ctrl+Alt+F2, log in there), find and kill the shell process:
```bash
pkill -f "quickshell.*shell.qml"
```
Switch back to the graphical VT (Ctrl+Alt+F1 or wherever the session
lives). Expected (per `omarchy-hyprland-session-locked`'s own comment):
the screen may show nothing/black, or Hyprland's own state still reports
`LOCK` in `solitaryBlockedBy` — check with
`hyprctl -j monitors | jq '.[].solitaryBlockedBy'`. Relaunch the shell
(`omarchy-launch-shell`) and confirm `lock/Service.qml`'s existing
`checkStrandedLock()`/`recoverStrandedLock()` logic kicks in (watch
`journalctl --user -b -t omarchy-shell | grep "omarchy lock"` for a
`lock-stranded: recovering` line). This confirms the baseline problem is
real and reproducible before checking whether niri has it too.

- [ ] **Step 2: Reproduce the same scenario under Niri**

Log into the Niri session, launch the shell manually (per this project's
established pattern —
`docs/superpowers/plans/2026-08-23-omarchy-niri-bare-session.md`'s
manual-launch workaround, since nothing autostarts it yet), lock the
screen the same way, then from a different TTY kill the shell process the
same way. Switch back to the graphical VT.

Record what actually happens:
- Does the screen return to a normal, usable Niri desktop on its own
  (niri released the lock when its client died — no fix needed, the
  scenario doesn't reproduce under niri)?
- Or does the screen stay black/stuck/unresponsive (niri has the same
  orphaned-lock behavior, but there's no IPC query to detect it from a
  freshly-restarted shell)?

- [ ] **Step 3: Rule on the finding**

If niri released the lock cleanly (first bullet above): this is a
**Non-Goal for niri, confirmed empirically, not assumed** — the failure
mode this code exists for doesn't reproduce under niri. Add one line to
`lock/Service.qml`'s existing `checkStrandedLock()` comment noting this was
checked and confirmed unnecessary under niri, and do nothing else — no
code changes to guard/branch anything, since there's nothing to guard
against.

If niri stayed stuck (second bullet): this is a **real problem with no
clean detection mechanism available today** (niri's IPC has nothing to
query for it). Do not attempt to invent one in this task — record the
finding precisely (what was observed, what was tried) as a note in this
plan's "What comes after this plan" section, for a dedicated future plan
once a detection approach exists or gets designed. This task's job is to
determine the fact, not solve an underdetermined problem on the spot.

---

## Task 2: NiriService — window opened/closed signals

**Files:**
- Modify: `shell/plugins/services/niri/Service.qml`

**Interfaces:**
- Produces: `signal windowOpened(var window)` (the niri `Window` object,
  same shape `handleWindowOpenedOrChanged` already receives — has `.id`,
  `.app_id`, `.workspace_id`, etc.), `signal windowClosed(int id)`.
  Consumed by Task 3.

- [ ] **Step 1: Add the signals and emit them**

In `shell/plugins/services/niri/Service.qml`, add near the other
`property`/`signal` declarations at the top of the file (after the
existing `lastEvent`/`lastEventAt` properties):
```qml
  signal windowOpened(var window)
  signal windowClosed(int id)
```

Then update `handleWindowOpenedOrChanged` and `handleWindowClosed` to emit
them after doing their existing work — the current functions are:
```qml
  function handleWindowOpenedOrChanged(data) {
    var w = data.window
    if (!w || w.id === undefined) return
    var next = {}
    for (var id in root.windowsById) next[id] = root.windowsById[id]
    next[w.id] = w
    root.windowsById = next
    root.recomputeOccupiedFromWindows()
  }

  function handleWindowClosed(data) {
    if (data.id === undefined) return
    var next = {}
    for (var id in root.windowsById) if (Number(id) !== data.id) next[id] = root.windowsById[id]
    root.windowsById = next
    root.recomputeOccupiedFromWindows()
  }
```
Add one line to each, right after `root.recomputeOccupiedFromWindows()`:
```qml
    root.windowOpened(w)
```
and
```qml
    root.windowClosed(data.id)
```
respectively — nothing else in either function changes.

- [ ] **Step 2: Sanity-check syntax**

`qmllint` is not installed on this host. Manually re-read the file for
balanced braces/parens.

- [ ] **Step 3: Commit and push**

```bash
git add shell/plugins/services/niri/Service.qml
git commit -m "NiriService: emit windowOpened/windowClosed signals"
git push
```
Run `git ls-remote origin niri-support` afterward and confirm the hash
matches `git rev-parse HEAD` — do not trust a "push succeeded" claim
without this check (see this project's own
`[[verify-subagent-pushes]]`-equivalent lesson from a prior plan).

- [ ] **Step 4: Verify in the VM**

Pull, restart the shell under Niri, open and close a window, and confirm
(via a temporary `console.log` if needed, or by checking that Task 3's
consumer — once implemented — reacts) that the signals actually fire.
This step is cheap to fold into Task 3's own verification instead of
duplicating it if you're executing both tasks back to back.

---

## Task 3: idle/Service.qml — Niri-path screensaver-window tracking

**Files:**
- Modify: `shell/plugins/services/idle/Service.qml`

**Interfaces:**
- Consumes: `NiriService.windowOpened`/`.windowClosed` (Task 2).
- Reuses unchanged: `root.handleScreensaverWindowOpened(address)`,
  `root.handleScreensaverWindowClosed(address)`, `root.screensaverClass`,
  `root.screensaverWindows` — all already compositor-agnostic.

- [ ] **Step 1: Add the Niri-path event wiring**

The file currently has this Hyprland-only block:
```qml
  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }
```
Add a sibling block (do not modify the existing one) for Niri:
```qml
  readonly property var niriService: root.shell ? root.shell.firstPartyServiceFor("omarchy.niri") : null

  function handleNiriWindowOpened(window) {
    if (!window) return
    if (String(window.app_id || "") === root.screensaverClass) {
      root.handleScreensaverWindowOpened(String(window.id))
    }
  }

  function handleNiriWindowClosed(id) {
    var address = String(id)
    if (root.screensaverWindows[address]) root.handleScreensaverWindowClosed(address)
  }

  Connections {
    target: root.niriService
    enabled: !!root.niriService
    function onWindowOpened(window) { root.handleNiriWindowOpened(window) }
    function onWindowClosed(id) { root.handleNiriWindowClosed(id) }
  }
```
`root.screensaverWindows` is keyed by an arbitrary string "address" today
(Hyprland's own window address format) — using `String(window.id)` for
niri's numeric window id as the equivalent key is consistent with how the
map is already used purely as a presence/count tracker, not something that
parses the key's format.

- [ ] **Step 2: Sanity-check syntax**

No `qmllint` on this host — manually re-read the file for balanced
braces/parens, and confirm `handleNiriWindowOpened`/`handleNiriWindowClosed`
call the exact same `root.handleScreensaverWindowOpened`/`Closed` functions
the Hyprland path already uses (no divergent logic introduced).

- [ ] **Step 3: Commit and push**

```bash
git add shell/plugins/services/idle/Service.qml
git commit -m "idle service: track the screensaver window under Niri via NiriService"
git push
```
Verify the push landed via `git ls-remote origin niri-support`.

- [ ] **Step 4: Verify Hyprland is unaffected in the VM**

Pull, restart shell under Hyprland. Trigger the idle timeout (or use
`omarchy-shell idle status`/lower the configured timeout temporarily) and
confirm the screensaver still launches and the lock timer still correctly
waits for/cancels based on the screensaver window's presence, exactly as
before this change.

- [ ] **Step 5: Verify Niri screensaver-window tracking works**

Under Niri (once Task 4's launcher port also lands — this step and Task
4's own verification are easiest done together): let the idle timer fire,
confirm the screensaver launches and the lock timer correctly holds off
while the screensaver window is mapped (check
`journalctl --user -b -t omarchy-shell | grep "omarchy idle"` for
`idle-monitor-active` / screensaver-cycle log lines), and confirm closing
the screensaver window (dismissing it) is correctly detected — the same
`omarchy-shell idle status` IPC call used for Hyprland verification works
identically here since it's the same service.

---

## Task 4: Port `bin/omarchy-launch-screensaver` for Niri

**Files:**
- Modify: `bin/omarchy-launch-screensaver`
- Create: `bin/omarchy-niri-monitor-focused`

- [x] **Step 1: Confirm niri's exact CLI syntax for the two actions this needs — DONE**

Confirmed live in the VM:
```
$ niri msg action focus-monitor --help
Usage: niri msg action focus-monitor <OUTPUT>
```
`<OUTPUT>` is **positional**, not a `--output` flag (the plan's original
guess, based on the Rust `Action::FocusMonitor { output: String }`
field name, was wrong — niri's CLI doesn't turn every struct field into a
named flag). Correct invocation: `niri msg action focus-monitor "$1"`.

```
$ niri msg action spawn --help
Usage: niri msg action spawn -- <COMMAND>...
```
This one matches the original plan exactly: `niri msg action spawn -- "$@"`.

Also confirmed the two `-j` JSON shapes Step 4 below depends on:
`niri msg -j outputs` returns an object keyed by output name (e.g.
`{"Virtual-1": {"name": "Virtual-1", ...}}`) — `jq -r 'keys[]'` is
correct. `niri msg -j focused-output` returns a single output object
directly with a top-level `"name"` field — `jq -r '.name'` is correct.

- [ ] **Step 2: Add the Niri-path functions**

The current script has, alongside `hypr_focus_monitor`/`hypr_exec`:
```bash
hypr_focus_monitor() {
  hyprctl dispatch "hl.dsp.focus({ monitor = \"$1\" })" >/dev/null 2>&1 || hyprctl dispatch focusmonitor "$1" >/dev/null
}

hypr_exec() {
  local command
  printf -v command '%q ' "$@"

  hyprctl dispatch "hl.dsp.exec_cmd([[$command]])" >/dev/null 2>&1 || hyprctl dispatch exec -- bash -lc "$command" >/dev/null
}
```
Add, as siblings (do not modify the `hypr_*` functions):
```bash
niri_focus_monitor() {
  niri msg action focus-monitor "$1" >/dev/null 2>&1
}

niri_exec() {
  niri msg action spawn -- "$@" >/dev/null 2>&1
}
```

- [ ] **Step 3: Add the Niri-path event-stream wait**

The current script has:
```bash
SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

# Open Hyprland's event stream before spawning anything, so a terminal that maps
# quickly can't emit its openwindow event before we are listening for it.
exec {events}< <(socat -U - "UNIX-CONNECT:$SOCKET")

wait_for_screensaver_window() {
  local line deadline=$((SECONDS + 5))
  while ((SECONDS < deadline)) && IFS= read -r -t $((deadline - SECONDS)) -u "$events" line; do
    [[ $line == openwindow\>\>*,org.omarchy.screensaver,* ]] && return 0
  done
}
```
Add a parallel Niri event-stream reader and wait function. niri's own IPC
is JSON-lines over `$NIRI_SOCKET`, started by writing the literal string
`"EventStream"` (established in `shell/plugins/services/niri/Service.qml`
and this project's prior plans — reuse that exact protocol knowledge, do
not re-derive it):
```bash
if [[ -n ${NIRI_SOCKET:-} ]]; then
  exec {niri_events}< <(printf '"EventStream"\n' | socat -U - "UNIX-CONNECT:$NIRI_SOCKET")
fi

wait_for_niri_screensaver_window() {
  local line deadline=$((SECONDS + 5))
  while ((SECONDS < deadline)) && IFS= read -r -t $((deadline - SECONDS)) -u "$niri_events" line; do
    [[ $(jq -r '.WindowOpenedOrChanged.window.app_id // empty' <<<"$line" 2>/dev/null) == "org.omarchy.screensaver" ]] && return 0
  done
}
```
Note the guard on `$NIRI_SOCKET` being set — unlike the Hyprland socket
open (which the script already does unconditionally, since this script
only ever ran under Hyprland before this plan), this new one must not run
`socat` against an empty/unset path under Hyprland.

- [ ] **Step 4: Branch the main loop on compositor**

The current script's main loop and trailing focus-restore:
```bash
for m in $(hyprctl monitors -j | jq -r '.[] | .name'); do
  hypr_focus_monitor "$m"

  case $terminal in
  *Alacritty*)
    hypr_exec alacritty --class=org.omarchy.screensaver --config-file "$OMARCHY_PATH/default/alacritty/screensaver.toml" -e omarchy-screensaver
    ;;
  *ghostty*)
    hypr_exec ghostty --class=org.omarchy.screensaver --config-file="$OMARCHY_PATH/default/ghostty/screensaver" --font-size=18 -e omarchy-screensaver
    ;;
  *foot*)
    hypr_exec foot --app-id=org.omarchy.screensaver --config="$OMARCHY_PATH/default/foot/screensaver.ini" -e omarchy-screensaver
    ;;
  *kitty*)
    hypr_exec kitty --class=org.omarchy.screensaver --override font_size=18 --override window_padding_width=0 -e omarchy-screensaver
    ;;
  esac

  wait_for_screensaver_window
done

hypr_focus_monitor "$focused"
```
Replace with a compositor-gated version — same terminal-selection `case`
body reused via a small helper so it isn't duplicated twice, since the
actual per-terminal launch commands are identical between compositors
(only the focus/exec/wait mechanism differs):
```bash
launch_screensaver_terminal() {
  local exec_fn="$1"
  case $terminal in
  *Alacritty*)
    "$exec_fn" alacritty --class=org.omarchy.screensaver --config-file "$OMARCHY_PATH/default/alacritty/screensaver.toml" -e omarchy-screensaver
    ;;
  *ghostty*)
    "$exec_fn" ghostty --class=org.omarchy.screensaver --config-file="$OMARCHY_PATH/default/ghostty/screensaver" --font-size=18 -e omarchy-screensaver
    ;;
  *foot*)
    "$exec_fn" foot --app-id=org.omarchy.screensaver --config="$OMARCHY_PATH/default/foot/screensaver.ini" -e omarchy-screensaver
    ;;
  *kitty*)
    "$exec_fn" kitty --class=org.omarchy.screensaver --override font_size=18 --override window_padding_width=0 -e omarchy-screensaver
    ;;
  esac
}

if [[ -n ${NIRI_SOCKET:-} ]]; then
  for m in $(niri msg -j outputs | jq -r 'keys[]'); do
    niri_focus_monitor "$m"
    launch_screensaver_terminal niri_exec
    wait_for_niri_screensaver_window
  done
  niri_focus_monitor "$focused"
else
  for m in $(hyprctl monitors -j | jq -r '.[] | .name'); do
    hypr_focus_monitor "$m"
    launch_screensaver_terminal hypr_exec
    wait_for_screensaver_window
  done
  hypr_focus_monitor "$focused"
fi
```
`$focused` (currently set via `omarchy-hyprland-monitor-focused`,
unconditionally, near the top of the script) also needs a Niri-aware
source. `bin/omarchy-hyprland-monitor-focused` is a small, dedicated
script (`hyprctl monitors -j | jq -r '.[] | select(.focused == true).name'`)
following this project's established `omarchy-hyprland-*` naming
convention — this project already has several compositor-specific helper
scripts named this way (`omarchy-hyprland-focus-app`,
`omarchy-hyprland-monitor-scaling`, `omarchy-hyprland-session-locked`), so
the fix that matches convention is a **new sibling script**, not inline
branching inside `omarchy-launch-screensaver`:

Create `bin/omarchy-niri-monitor-focused`:
```bash
#!/bin/bash

# omarchy:summary=Print the name of the currently focused Niri output.

niri msg -j focused-output | jq -r '.name'
```
(Confirm this jq path against real `niri msg -j focused-output` output in
Step 1's investigation, alongside the other CLI checks — the `Response`
enum's `FocusedOutput(Option<Output>)` wraps an `Output` struct whose
`name` field this assumes is top-level; verify rather than trust.)

Then in `omarchy-launch-screensaver`, change the existing:
```bash
focused=$(omarchy-hyprland-monitor-focused)
```
to:
```bash
if [[ -n ${NIRI_SOCKET:-} ]]; then
  focused=$(omarchy-niri-monitor-focused)
else
  focused=$(omarchy-hyprland-monitor-focused)
fi
```

- [ ] **Step 5: Sanity-check the script**

```bash
bash -n bin/omarchy-launch-screensaver
```
Expected: no syntax errors. There's no niri/Hyprland to test the actual
IPC calls against on this host — the real test is Step 6/7 in the VM.

- [ ] **Step 6: Commit and push**

```bash
chmod +x bin/omarchy-niri-monitor-focused
git add bin/omarchy-launch-screensaver bin/omarchy-niri-monitor-focused
git commit -m "Port the screensaver launcher's monitor iteration to Niri"
git push
```
Verify the push landed via `git ls-remote origin niri-support`.

- [ ] **Step 7: Verify Hyprland is unaffected in the VM**

Pull, and manually trigger the screensaver under Hyprland
(`omarchy-launch-screensaver force`). Confirm it launches exactly as
before — same terminal, same monitor-by-monitor behavior, focus restored
to the original monitor afterward.

- [ ] **Step 8: Verify the Niri path works**

Under Niri, run `omarchy-launch-screensaver force` (or let idle trigger
it, combined with Task 3's verification). Confirm: the screensaver
terminal launches on the (single, in this VM) output, `niri_focus_monitor`
doesn't error, and focus is restored afterward. If this VM ever gains a
second output, also confirm the per-monitor iteration + wait actually
serializes correctly (each monitor's screensaver appears on that monitor,
not all piling onto the last one) — matching the single-monitor
limitation already noted elsewhere in this project's memory.

---

## What comes after this plan

If Task 1's spike found niri DOES have an orphaned-lock problem: a future
plan needs to design an actual detection mechanism from scratch, since
niri's IPC has nothing to query for it — this might mean a different
approach entirely (e.g., a defensive one-time re-lock probe at shell
startup rather than a state query), not a straightforward port of
`omarchy-hyprland-session-locked`'s technique.

Otherwise, per the discussed breakdown: the smaller independent items next
("3d"): notifications' focus-by-class (`omarchy-hyprland-focus-app`),
keyboard-layout query/switch (niri's IPC does expose a `KeyboardLayouts`
request/event — confirmed via the same fresh IPC-surface fetch this plan
used, so this is likely NOT a Non-Goal after all, worth designing properly
rather than assuming it's unsupported), and monitor enable/scale. Then
theme KDL generation ("3e", spec Phase 7).
