# Omarchy Niri Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Niri session a real Omarchy config — keybindings,
input, appearance, window rules, autostart, and theme-color integration —
matching what the Hyprland session already has, using Niri's own idioms
where Hyprland's model doesn't translate.

**Architecture:** A new `default/niri/` config tree (entry point
`config.kdl`, plus `bindings.kdl` and `window-rules.kdl`, included from
it) parallel to `default/hypr/`. A new `default/themed/niri.kdl.tpl`
feeds theme border colors through the existing generic templating engine
(`omarchy-theme-set-templates`, unchanged). Because Niri's KDL `include`
has no environment-variable expansion (unlike Hyprland's Lua
`os.getenv("OMARCHY_PATH")`), a small wrapper script regenerates
`~/.config/niri/config.kdl` with the current `$OMARCHY_PATH` baked in
literally, run once at the start of every Niri session — this keeps
`omarchy dev link` working the same way it already does for Hyprland,
without needing any changes to `omarchy-dev-link`/`omarchy-dev-unlink`
themselves.

**Tech Stack:** KDL (niri's config format), bash (the config-generation
wrapper, theme template processing — reusing existing infrastructure).

**Spec:** `docs/superpowers/specs/2026-08-25-omarchy-niri-config-design.md`

## Global Constraints

- **Every Hyprland behavior with no real Niri equivalent gets an explicit
  comment in the output file explaining why it's absent** — never a
  silent omission, and never an approximate-but-misleading substitute.
  The spec's "Explicitly dropped" list is authoritative for what belongs
  here: window grouping, scratchpad/special-workspace, dwindle/
  pseudo-tiling toggle and all of `workspace-layouts.lua`, the clipboard
  universal-shortcut synthetic-key-injection trick, and the region-picker's
  dynamic per-layer keybind registration.
- **`Mod` = Super** for every translated binding, matching both
  Hyprland's convention and niri's own default config.
- **Niri's `include "path"` has no environment-variable expansion** — only
  `~` (home dir) and paths relative to the including file's own
  directory. Only the one wrapper-generated top-level file
  (`~/.config/niri/config.kdl`) ever needs a literal baked-in absolute
  path; every include inside `default/niri/` itself uses a plain relative
  filename.
- **Confirmed CLI/schema facts, from niri's own source
  (`niri-config`/`niri-ipc` crates) — do not re-derive or second-guess
  these:**
  - `include "path" optional=true` merges the included file's config
    into the current one; `layout` merges recursively (a themed override
    containing only `layout { border { active-color ... } }` does not
    need to repeat gaps/focus-ring/etc.); `binds` replaces by matching
    key rather than erroring on duplicates.
  - Config reload: `niri msg action load-config-file` (no arguments
    needed to reload the currently-loaded file).
  - `WindowRule` has a single `opacity: Option<f32>` field (not a
    Hyprland-style active/inactive pair).
  - `Cursor` has `hide_when_typing: bool` (→ KDL `hide-when-typing`,
    matches Hyprland's `hide_on_key_press`) and no
    `warp_on_change_workspace` equivalent.
  - `Animations` categorizes by semantic event (`window_open`,
    `window_close`, `window_movement`, `window_resize`,
    `workspace_switch`, `horizontal_view_movement`, plus a few
    UI-specific ones) — no 1:1 mapping to Hyprland's per-effect "leaves"
    exists. This plan uses niri's stock animation defaults: the
    `animations { }` block is omitted entirely from `config.kdl` (an
    absent block means niri's own defaults apply — confirmed from niri's
    own default-config.kdl, `off`/`slowdown` are the only settings shown
    there and both are commented out by default).
- Every task's output file(s) must be valid KDL — validate with
  `niri validate -c <file>` if a niri binary is available in this dev
  environment (check with `command -v niri` first; if unavailable on
  this host, note that in the task report and rely on the plan's
  live-VM verification checklist instead — do not skip validation
  silently, say explicitly which path was used).

---

## Task 1: Foundation — file structure, dev-link wiring, theme integration, reload

**Files:**
- Create: `default/niri/config.kdl`
- Create: `default/niri/bindings.kdl` (stub, populated by Tasks 3-5)
- Create: `default/niri/window-rules.kdl` (stub, populated by Task 7)
- Create: `default/themed/niri.kdl.tpl`
- Create: `bin/omarchy-refresh-niri`
- Modify: `default/wayland-sessions/omarchy-niri.desktop`
- Modify: `bin/omarchy-theme-set`
- Create: `test/shell.d/refresh-niri-test.sh`

**Interfaces:**
- Produces (consumed by every later task): `default/niri/config.kdl`
  with `include "bindings.kdl"` and `include "window-rules.kdl"` lines
  already present (so later tasks only ever ADD content inside
  `bindings.kdl`/`window-rules.kdl`/specific sections of `config.kdl`,
  never restructure this file's include wiring).

- [ ] **Step 1: Create the stub included files**

```bash
mkdir -p default/niri
cat > default/niri/bindings.kdl << 'EOF'
// Omarchy keybindings for Niri, translated from default/hypr/bindings/*.lua.
// Populated by later tasks in this plan; see
// docs/superpowers/plans/2026-08-25-omarchy-niri-config.md.
EOF
cat > default/niri/window-rules.kdl << 'EOF'
// Omarchy window rules for Niri, translated from default/hypr/windows.lua
// and default/hypr/apps/*.lua. Populated by a later task in this plan; see
// docs/superpowers/plans/2026-08-25-omarchy-niri-config.md.
EOF
```

- [ ] **Step 2: Create `default/niri/config.kdl`**

```kdl
// Omarchy defaults for Niri. Don't edit this file directly — put
// personal overrides in ~/.config/niri/config.kdl instead (see
// default/niri/README, or docs/superpowers/specs/2026-08-25-omarchy-niri-config-design.md).

input {
    keyboard {
        xkb {
            // Left empty deliberately: niri fetches xkb settings from
            // org.freedesktop.locale1 automatically when this block is
            // empty. Only add explicit layout/variant/options here if
            // live testing shows that doesn't pick up the right layout.
        }

        numlock
        repeat-rate 40
        repeat-delay 250
    }

    touchpad {
        tap
        clickfinger-behavior
        scroll-factor 0.4
    }
}

layout {
    gaps 8

    focus-ring {
        off
    }

    border {
        width 2
        active-color "#33ccff"
        inactive-color "#595959aa"
    }

    shadow {
        // Matches the current theme's shadow.enabled = false.
    }
}

cursor {
    hide-when-typing
}

hotkey-overlay {
    skip-at-startup
}

// Theme colors override the border section above. optional=true means
// this silently no-ops before the theme system has ever run (e.g. right
// after a fresh omarchy dev link), then picks up colors the moment it
// does — same pattern as Hyprland's
// require_optional.module("omarchy.current.theme.hyprland").
include "~/.local/state/omarchy/current/theme/niri.kdl" optional=true

include "bindings.kdl"
include "window-rules.kdl"
```

- [ ] **Step 3: Add a `niri_gradient` helper to the templating engine, and create the theme template**

Niri's border KDL has structurally different shapes for a flat color
(`active-color "#hex"`) vs. a gradient (`active-gradient from="#hex" to="#hex"
angle=N`) — two different node names, not just two formats of the same
value. Rather than have the template conditionally choose between them
(the existing sed-substitution engine has no conditional-node-shape
mechanism), always emit `active-gradient`, collapsing the flat-color case
to a "gradient" from a color to itself (`from="#X" to="#X" angle=0`),
which renders identically to a flat color. This sidesteps the
conditional-shape problem entirely and works for both 1-color and
2+-color theme specs uniformly.

Read `bin/omarchy-theme-set-templates` in full first (`hypr_gradient_value`,
`gradient_start_value`, `parse_gradient`, `color_to_shell_hex`,
`resolve_theme_ref` — this task reuses `parse_gradient`'s existing
`GRADIENT_COLORS`/`GRADIENT_ANGLE` output, not `hypr_gradient_value`
itself, which emits Hyprland's own Lua gradient object syntax, not KDL).

Add this function to `bin/omarchy-theme-set-templates`, placed next to
the other `*_value()` gradient helpers (near `hypr_gradient_value`):
```bash
niri_gradient_value() {
  local spec first last angle

  spec=$(resolve_theme_ref "$1" "${2:-}")
  parse_gradient "$spec"

  if (( ${#GRADIENT_COLORS[@]} == 0 )); then
    first=$(color_to_shell_hex "$spec")
    last="$first"
  else
    first="${GRADIENT_COLORS[0]}"
    last="${GRADIENT_COLORS[${#GRADIENT_COLORS[@]}-1]}"
  fi
  angle="${GRADIENT_ANGLE:-0}"

  printf 'from="%s" to="%s" angle=%s' "$first" "$last" "$angle"
}
```
Wire it into `add_gradient_function_value()`'s existing `case "$fn" in`
dispatch (alongside `hypr_gradient`/`gradient_start`/`shell_gradient`):
```bash
    niri_gradient)
      value=$(niri_gradient_value "$key" "$fallback")
      ;;
```
And extend `add_gradient_function_values`'s token-matching regex (which
currently matches `hypr_gradient|gradient_start|shell_gradient`) to also
match `niri_gradient`.

Then create the template itself:
```
cat > default/themed/niri.kdl.tpl << 'EOF'
layout {
    border {
        active-gradient {{ niri_gradient hyprland_active_border accent }}
        inactive-color "{{ hyprland_inactive_border }}"
    }
}
EOF
```
Note `active-gradient {{ niri_gradient ... }}` has no surrounding
quotes — `niri_gradient_value` already emits the complete
`from="..." to="..." angle=...` attribute string, not a single quoted
value like the plain `{{ key }}` substitutions use.
`inactive-color "{{ hyprland_inactive_border }}"` uses the existing plain
substitution unchanged (a flat color, matching Hyprland's own flat
inactive-border, needs no gradient handling).

- [ ] **Step 4: Wire the theme reload into `omarchy-theme-set`**

The file currently has, in its `post_theme_commands` array:
```bash
post_theme_commands=(
  omarchy-restart-terminal
  omarchy-restart-hyprctl
  omarchy-restart-btop
```
Add a new line right after `omarchy-restart-hyprctl`:
```bash
post_theme_commands=(
  omarchy-restart-terminal
  omarchy-restart-hyprctl
  omarchy-restart-niri
  omarchy-restart-btop
```
Create `bin/omarchy-restart-niri` (matching `bin/omarchy-restart-hyprctl`'s
own shape exactly):
```bash
#!/bin/bash

# omarchy:summary=Reload niri configuration (used by the Omarchy theme switching).

[[ -n ${NIRI_SOCKET:-} ]] && niri msg action load-config-file >/dev/null 2>&1
exit 0
```
The `[[ -n ${NIRI_SOCKET:-} ]]` guard matters: `post_theme_commands` runs
unconditionally regardless of which compositor is active (see
`omarchy-restart-hyprctl`, which has no such guard — `hyprctl reload`
presumably fails harmlessly when Hyprland isn't running, but confirm this
by reading how `run_parallel` in `omarchy-theme-set` handles a failing
command in that array before assuming the same "fails harmlessly, ignored"
behavior applies without a guard; if it does, you may drop this guard to
match the existing sibling's style exactly — but verify first, don't
assume).

- [ ] **Step 5: Create the config-generation wrapper**

```bash
cat > bin/omarchy-refresh-niri << 'EOF'
#!/bin/bash

# omarchy:summary=Regenerate the entry point ~/.config/niri/config.kdl points OMARCHY_PATH at
# omarchy:hidden=true

# Niri's `include` has no environment-variable expansion (unlike
# Hyprland's Lua config, which reads $OMARCHY_PATH live via os.getenv on
# every reload) — so unlike Hyprland's static ~/.config/hypr/hyprland.lua,
# this file has to be regenerated whenever OMARCHY_PATH changes, not just
# copied once. Run at the start of every Niri session (see
# default/wayland-sessions/omarchy-niri.desktop) so a dev-link change
# takes effect on next login, with no special-casing needed in
# omarchy-dev-link/omarchy-dev-unlink themselves.

if [[ -f /etc/omarchy.conf ]]; then
  . /etc/omarchy.conf
fi
: "${OMARCHY_PATH:=/usr/share/omarchy}"

config_path="$OMARCHY_PATH/default/niri/config.kdl"
# KDL string arguments need double quotes, not shell quoting — a plain
# printf %q would produce single-quoted or backslash-escaped output on a
# path with spaces, neither of which is valid KDL. Escape only a literal
# double quote (vanishingly unlikely in a real path, but correct to
# handle) and wrap in literal double quotes ourselves.
escaped_path=${config_path//\"/\\\"}

mkdir -p "$HOME/.config/niri"
printf 'include "%s"\n' "$escaped_path" > "$HOME/.config/niri/config.kdl"
EOF
chmod +x bin/omarchy-refresh-niri
```
Test this manually after writing it: run the script with a fake
`OMARCHY_PATH` exported (including one with a space in it, e.g.
`OMARCHY_PATH="/tmp/fake checkout"`), then `cat ~/.config/niri/config.kdl`
and confirm the output is exactly `include "<path>/default/niri/config.kdl"`
with real double quotes — valid KDL, not shell-quoted.

- [ ] **Step 6: Hook the wrapper into the Niri session launch**

The file currently is:
```
[Desktop Entry]
Name=Omarchy (Niri uwsm)
Comment=Omarchy Niri session managed by uwsm
Exec=uwsm start -g -1 -e -D niri niri.desktop
TryExec=uwsm
Type=Application
```
Change the `Exec=` line to run the wrapper first, then hand off to the
existing command unchanged:
```
Exec=bash -c 'omarchy-refresh-niri; exec uwsm start -g -1 -e -D niri niri.desktop'
```
Do not change anything else in this file.

- [ ] **Step 7: Add test coverage for the wrapper**

`/etc/omarchy.conf` does not exist in this project's test sandbox (it's
a real artifact only present on an actual Omarchy install after
`omarchy dev-link` has run there) — this test relies on that absence
rather than faking the file. Pre-exporting `OMARCHY_PATH` directly
exercises the exact same code path `/etc/omarchy.conf` would otherwise
populate (the script's own `: "${OMARCHY_PATH:=/usr/share/omarchy}"`
only assigns when the variable is unset/empty, so a pre-exported value
passes straight through untouched).

```bash
cat > test/shell.d/refresh-niri-test.sh << 'EOF'
#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_home=$(mktemp -d)
trap 'rm -rf "$test_home"' EXIT

run_refresh() {
  rm -rf "$test_home"
  mkdir -p "$test_home"
  env "$@" HOME="$test_home" "$ROOT/bin/omarchy-refresh-niri"
}

run_refresh OMARCHY_PATH="/fake/checkout"
[[ $(<"$test_home/.config/niri/config.kdl") == 'include "/fake/checkout/default/niri/config.kdl"' ]] ||
  fail "refresh-niri writes the include line with the given OMARCHY_PATH" "$(<"$test_home/.config/niri/config.kdl")"
pass "refresh-niri writes the include line with the given OMARCHY_PATH"

run_refresh -u OMARCHY_PATH
[[ $(<"$test_home/.config/niri/config.kdl") == 'include "/usr/share/omarchy/default/niri/config.kdl"' ]] ||
  fail "refresh-niri falls back to the packaged OMARCHY_PATH when unset" "$(<"$test_home/.config/niri/config.kdl")"
pass "refresh-niri falls back to the packaged OMARCHY_PATH when unset"

run_refresh OMARCHY_PATH="/fake/check out with spaces"
[[ $(<"$test_home/.config/niri/config.kdl") == 'include "/fake/check out with spaces/default/niri/config.kdl"' ]] ||
  fail "refresh-niri handles an OMARCHY_PATH containing spaces" "$(<"$test_home/.config/niri/config.kdl")"
pass "refresh-niri handles an OMARCHY_PATH containing spaces"
EOF
chmod +x test/shell.d/refresh-niri-test.sh
./test/shell.d/refresh-niri-test.sh
```
Expected: all three `pass` lines, no `not ok`. If the script from Step 5
doesn't pass this test as written and you determine the SCRIPT (not the
test) needs to change to make these three cases behave correctly, fix
the script — this test encodes the actual required behavior, not an
approximation of it.

- [ ] **Step 8: Validate and test**

```bash
command -v niri >/dev/null && niri validate -c default/niri/config.kdl || echo "no niri binary on this host, skipping KDL validation"
bash -n bin/omarchy-refresh-niri
bash -n bin/omarchy-restart-niri
./test/shell.d/refresh-niri-test.sh
./test/cli
./test/shell
```
Expected: clean, matching this project's known pre-existing failures
(`config-test.sh`, `snapper-test.sh`, `unowned-system-paths-test.sh`,
possibly `runtime-smoke-test.sh`) and nothing else.

- [ ] **Step 9: Commit and push**

```bash
git add default/niri/config.kdl default/niri/bindings.kdl default/niri/window-rules.kdl \
  default/themed/niri.kdl.tpl bin/omarchy-refresh-niri bin/omarchy-restart-niri \
  default/wayland-sessions/omarchy-niri.desktop bin/omarchy-theme-set \
  bin/omarchy-theme-set-templates test/shell.d/refresh-niri-test.sh
git commit -m "Add the Niri config foundation: file structure, dev-link wiring, theme integration"
git push
```
Run `git ls-remote origin niri-support` afterward and confirm the hash
matches `git rev-parse HEAD`.

---

## Task 2: Bindings — Applications, Media, Utilities, Voxtype (mechanical)

**Files:**
- Modify: `default/niri/bindings.kdl`

**Interfaces:**
- Consumes: the stub file from Task 1 (append after the existing header
  comment).

**Context:** every binding in `default/hypr/bindings/applications.lua`,
`media.lua`, `utilities.lua`, and `voxtype.lua` resolves to a plain shell
command via `default/hypr/helpers.lua`'s `command_from()` — confirmed by
reading that file in full. None of these commands know or care which
compositor invoked them. This task is a mechanical reformatting job:
same key combination, same shell command, different syntax.

- [ ] **Step 1: Read the source files**

Read these four files in full before writing anything:
`default/hypr/bindings/applications.lua`, `default/hypr/bindings/media.lua`,
`default/hypr/bindings/utilities.lua`, `default/hypr/bindings/voxtype.lua`,
and `default/hypr/helpers.lua` (for `command_from()`'s exact resolution
rules — you need this to know what shell command each `{ omarchy = ... }`/
`{ launch = ... }`/`{ webapp = ... }`/`{ tui = ... }` table actually
produces).

- [ ] **Step 2: Translate using this exact pattern**

niri bind syntax: `<Mod-combo> [property=value ...] { <action>; }`.

Four fully worked examples covering every distinct shape in these four
source files — apply this same transformation to every other binding in
all four files:

**Example A — plain omarchy-launch command** (from `applications.lua`):
```lua
o.bind("SUPER + RETURN", "Terminal", { omarchy = "terminal" })
```
→
```kdl
Mod+Return hotkey-overlay-title="Terminal" { spawn "omarchy-launch-terminal"; }
```
(`{ omarchy = "terminal" }` resolves to `omarchy-launch-terminal` per
`command_from()`; a single command with no shell features needed uses
`spawn` with the command split into argv, here just one argument.)

**Example B — locked + repeating, single command with an argument**
(from `media.lua`):
```lua
o.bind("XF86AudioRaiseVolume", "Volume up", "omarchy-audio-output-volume raise", { locked = true, repeating = true })
```
→
```kdl
XF86AudioRaiseVolume allow-when-locked=true { spawn "omarchy-audio-output-volume" "raise"; }
```
(`repeating = true` needs no niri-side property — niri repeats bound keys
on physical key-repeat unconditionally, per this plan's Global
Constraints. Multiple argv words become multiple quoted `spawn`
arguments, not one string.)

**Example C — a command using `||` fallback, needs a real shell** (from
`utilities.lua`):
```lua
o.bind("ALT + PRINT", "Screenrecording", "omarchy-capture-screenrecording --stop-recording || omarchy-menu toggle trigger.capture.screenrecord")
```
→
```kdl
Alt+Print hotkey-overlay-title="Screenrecording" { spawn-sh "omarchy-capture-screenrecording --stop-recording || omarchy-menu toggle trigger.capture.screenrecord"; }
```
(`spawn-sh` takes the whole command as one string argument, passed to
`sh -c` — use this whenever the original has `||`, pipes, or is built as
one assembled string rather than discrete argv words.)

**Example D — a `code:N` positional keysym** (from `applications.lua`'s
loop, and reappearing in `utilities.lua`):
```lua
o.bind("SUPER + SHIFT + code:201", "Omarchy menu", "omarchy-menu toggle root")
```
niri binds accept raw XKB keysym names, not X11 keycodes — `code:201` is
Hyprland's raw X11 keycode syntax and has no direct niri equivalent
number-for-number. Resolve what physical key `code:201` actually is on a
standard keyboard (check this project's own comments near other `code:N`
usages, or determine it via `wev`-style keysym lookup reasoning, or ask
for clarification if genuinely unclear rather than guessing) and bind
that key's actual XKB name instead. Do this same resolution for every
other `code:N` binding in these four files (there are more in
`tiling.lua`'s workspace-number loop and elsewhere — Task 4 handles those
specifically, but if you encounter any `code:N` in THESE four files,
resolve them here, don't skip them).

- [ ] **Step 3: Handle `preinstalled_bindings_enabled()`**

`applications.lua` wraps its second half in
`if o.preinstalled_bindings_enabled() then ... end` — a runtime check
(reads a state file, `~/.local/state/omarchy/preinstalls-removed`) that
this plan's static KDL file can't replicate dynamically. Translate all
of these bindings unconditionally (matching the common case — the flag
defaults to enabled), and add one comment noting the omitted
conditionality:
```kdl
// The following app/webapp bindings are unconditional here; Hyprland's
// config gates them on o.preinstalled_bindings_enabled() (a runtime
// state-file check for whether preinstalled apps were removed), which
// this static file can't replicate. Revisit if that ever needs porting.
```

- [ ] **Step 4: Voxtype's conditional install check**

`voxtype.lua` wraps its bindings in `if o.cmd_present("voxtype") then`.
Same situation as Step 3 — translate unconditionally with a similar
one-line comment noting the omitted runtime check.

- [ ] **Step 5: Append to `default/niri/bindings.kdl`**

Structure the additions under clear comment headers matching the
original file groupings, inside a `binds { }` block (niri's binds all
live in one top-level `binds { }` node — if the stub file from Task 1
doesn't already have an opening `binds {`, add it now and leave it open
for Tasks 3-5 to append into; if it does, just add your content inside
it):
```kdl
binds {
    // ---- Applications (default/hypr/bindings/applications.lua) ----
    Mod+Return hotkey-overlay-title="Terminal" { spawn "omarchy-launch-terminal"; }
    // ... (all remaining applications.lua bindings, per the pattern above)

    // ---- Media, volume, brightness (default/hypr/bindings/media.lua) ----
    // ... (all media.lua bindings)

    // ---- Utilities: menus, notifications, screenshots (default/hypr/bindings/utilities.lua) ----
    // ... (all utilities.lua bindings except the dynamic layer-based
    // selection-picker binds noted below — those have no niri
    // translation and are handled by Task 4's drop-list comment, not
    // here)

    // ---- Voice dictation (default/hypr/bindings/voxtype.lua) ----
    // ... (voxtype.lua bindings)
}
```
Leave this `binds { }` block open (don't close it with a final `}` yet)
if Tasks 3-5 are expected to append more `Mod+...` lines inside the same
block — confirm this by checking whether this task is the first or a
later one to touch this file in execution order; if executed in the
order this plan lists them (Task 2 before 3, 4, 5), leave the block open
and note clearly in your commit/report that the block is intentionally
unclosed for the next task to continue.

- [ ] **Step 6: Sanity-check and commit**

```bash
command -v niri >/dev/null && niri validate -c default/niri/config.kdl || echo "no niri binary, skipping validation (note: this will fail to validate until the binds{} block is closed by a later task if you left it open — only run this check once the block is genuinely complete, or skip it here and let Task 5 (the last bindings task) do the first real validation)"
```
```bash
git add default/niri/bindings.kdl
git commit -m "Translate application, media, and utility keybindings to Niri"
git push
```
Verify the push landed via `git ls-remote origin niri-support`.

---

## Task 3: Bindings — Window management (Niri idioms, judgment-heavy)

**Files:**
- Modify: `default/niri/bindings.kdl`

**Interfaces:**
- Consumes: the (possibly still-open) `binds { }` block from Task 2 —
  append inside it, don't open a new one.

**Context:** `default/hypr/bindings/tiling.lua` is where Hyprland's and
Niri's models genuinely diverge. Read this file in full, and read
niri's own default config's `binds { }` section (already fetched into
this project's research; if not available locally, it ships at
`/usr/share/doc/niri/default-config.kdl` on any system with niri
installed, including the project's own dev VM via SSH) for niri's own
suggested key-to-action pairing — use that as your starting template for
the direction/focus/move bindings specifically, since niri's own authors
already made sensible choices there that this project should follow
rather than reinvent.

- [ ] **Step 1: Translate what has a real niri equivalent**

Directional focus/move (both arrow keys AND hjkl, matching niri's own
default config precedent of binding both to the same actions):
```kdl
    Mod+Left  { focus-column-left; }
    Mod+Right { focus-column-right; }
    Mod+Up    { focus-window-up; }
    Mod+Down  { focus-window-down; }
    Mod+H     { focus-column-left; }
    Mod+L     { focus-column-right; }
    Mod+K     { focus-window-up; }
    Mod+J     { focus-window-down; }
```
Continue this same pattern (both arrows and hjkl bound to the same
action) for every other directional action `tiling.lua` has a real niri
equivalent for: monitor focus (`focus-monitor-left/right/up/down`),
workspace switching (`focus-workspace-down/up` for `Mod+Tab`/
`Mod+Shift+Tab`'s "next/previous workspace" — niri's dynamic workspace
model doesn't have `e+1`/`e-1`/`previous` exactly like Hyprland, use
`focus-workspace-down`/`focus-workspace-up` for next/previous and
`focus-workspace-previous` for "former workspace", all real niri
actions), workspace-by-number (`Mod+1` through `Mod+9` →
`focus-workspace 1` through `focus-workspace 9`, `Mod+Shift+N` →
`move-column-to-workspace N`), fullscreen (`Mod+F`/`Mod+Shift+F`... note
Hyprland's `Mod+F` is "Full screen" and `Mod+Ctrl+F` is "Tiled full
screen" — niri only has one fullscreen concept, `fullscreen-window`; use
`Mod+F` for it and note `Mod+Ctrl+F`'s "tiled full screen" distinction as
dropped, no niri equivalent, in your drop-list comment), floating toggle
(`toggle-window-floating`), close window (`close-window`), and monitor
scaling (`Mod+Slash`/`Mod+Alt+Slash` — these currently call
`omarchy-hyprland-monitor-scaling up`/`down`; there is no
`omarchy-niri-monitor-scaling` script yet in this project — check
whether one exists by the time you execute this task (search `bin/` for
it), and if not, either write a small niri equivalent using
`niri msg output <FOCUSED-NAME> scale <value>` cycling through the same
preset list `omarchy-hyprland-monitor-scaling` uses, following that
script's own structure closely, or — if that feels like real scope
creep for a bindings task — bind these two keys to a `spawn-sh` calling
a niri equivalent script you create as a small, separate, clearly-labeled
addition in this same task; use your judgment on which is cleaner, but
don't leave the keys unbound).

Resize (percentage-based, not pixel-nudge — see this plan's spec, Global
Constraints doesn't repeat this, check the design spec directly):
```kdl
    Mod+Minus { set-column-width "-10%"; }
    Mod+Equal { set-column-width "+10%"; }
    Mod+Shift+Minus { set-window-height "-10%"; }
    Mod+Shift+Equal { set-window-height "+10%"; }
```
(Hyprland's config has three tiers — normal/`Alt` "a little"/`Ctrl` "a
lot" pixel amounts. Niri's percentage model doesn't map to three
distinct tiers the same way; use just the one binding pair above at a
reasonable default percentage, and add a one-line comment noting the
three-tier pixel system didn't port, rather than inventing three
arbitrary percentage tiers with no real basis.)

Consume/expel (niri's own distinct idiom, no Hyprland equivalent to
translate FROM, but bind it anyway since it's core to niri's model and
already has sensible defaults in niri's own config):
```kdl
    Mod+BracketLeft  { consume-or-expel-window-left; }
    Mod+BracketRight { consume-or-expel-window-right; }
```

- [ ] **Step 2: Explicitly document what's dropped, with real comments**

Add this comment block, matching the spec's "Explicitly dropped" list
exactly, inside `binds { }`:
```kdl
    // The following Hyprland tiling.lua bindings have no Niri
    // equivalent and are intentionally not ported (see
    // docs/superpowers/specs/2026-08-25-omarchy-niri-config-design.md,
    // "Explicitly dropped: no real niri equivalent"):
    //   - Window grouping (Mod+G, Mod+Alt+G, Mod+Alt+Left/Right/Up/Down
    //     into-group, Mod+Alt+Tab group-cycle, Mod+Ctrl+Left/Right
    //     grouped-focus) — niri only has tabbed *columns*, a
    //     structurally different, column-scoped concept.
    //   - Scratchpad (Mod+S toggle, Mod+Alt+S move-to-scratchpad) — niri
    //     has no floating hidden-workspace concept.
    //   - Dwindle/pseudo-tiling toggle (Mod+J toggle-split, Mod+P
    //     pseudo) — niri has one layout model, no alternate layouts.
    //   - Workspace-layout save/restore (Mod+L) and everything in
    //     default/hypr/workspace-layouts.lua — same reason, niri has no
    //     per-workspace layout concept to save/restore at all.
    //   - Window swap (Mod+Shift+Left/Right/Up/Down) — niri's closest
    //     action is move-column-left/right (position within the row),
    //     which is not really a "swap" of two specific windows; the
    //     directional move bindings above already cover this idiom
    //     under niri's own model.
```
Cross-check this list against your own read of `tiling.lua` in Step 1 —
if you find a binding in that file that ISN'T covered by either the
"translate" list in Step 1 or this drop list, resolve it one way or the
other (translate it if you find a real niri action, or add it to this
drop list with a reason) rather than silently skipping it. Every single
line of `tiling.lua` needs to land in one of these two buckets.

- [ ] **Step 3: Workspace-to-monitor movement**

```lua
o.bind("SUPER + SHIFT + ALT + LEFT", "Move workspace to left monitor", hl.dsp.workspace.move({ monitor = "l" }))
```
→ niri has `move-workspace-to-monitor-left/right/up/down` (confirmed in
niri's own default config's binds section, commented-out example near
the column-to-monitor bindings) — translate all four directions using
`Mod+Shift+Alt+Left/Right/Up/Down`.

- [ ] **Step 4: Sanity-check and commit**

```bash
git add default/niri/bindings.kdl
git commit -m "Translate window-management keybindings to Niri idioms, documenting Hyprland concepts with no equivalent"
git push
```
Verify the push landed via `git ls-remote origin niri-support`.

---

## Task 4: Bindings — Clipboard (partial port, explicit drop)

**Files:**
- Modify: `default/niri/bindings.kdl`

**Interfaces:**
- Consumes: the still-open `binds { }` block from Tasks 2-3.

**Context:** Read `default/hypr/bindings/clipboard.lua` in full. Its
`send_key_state`-based universal-shortcut mechanism (distinguishing
terminal-vs-GUI Ctrl+C/V, reaching both normal windows and layer-shell
surfaces) is Hyprland-dispatcher-specific with no niri IPC equivalent —
per this plan's Global Constraints, this is dropped, not approximated.

- [ ] **Step 1: Port what has a real equivalent**

Only one binding in this file is a plain shell command, unrelated to the
synthetic-key mechanism:
```lua
o.bind("SUPER + CTRL + V", "Clipboard manager", "omarchy-shell shell toggle omarchy.clipboard")
```
→
```kdl
    Mod+Ctrl+V hotkey-overlay-title="Clipboard manager" { spawn "omarchy-shell" "shell" "toggle" "omarchy.clipboard"; }
```

- [ ] **Step 2: Document the drop**

```kdl
    // Mod+C (universal copy), Mod+V (universal paste), Mod+X (universal
    // cut) from default/hypr/bindings/clipboard.lua are NOT ported.
    // Hyprland's version uses synthetic key-state injection
    // (hl.dsp.send_key_state) to distinguish terminal-vs-GUI Ctrl+C/V
    // behavior and reach both normal windows and layer-shell surfaces —
    // niri's IPC has no equivalent "send this key combo to the focused
    // surface" action. See
    // docs/superpowers/specs/2026-08-25-omarchy-niri-config-design.md.
```

- [ ] **Step 3: Document the region-picker's dynamic bind drop**

`default/hypr/bindings/utilities.lua`'s `hl.on("layer.opened"/
"layer.closed", ...)` block (dynamically binding RETURN/TAB/arrow keys
only while `omarchy-capture-region`'s selection overlay is on screen) —
Task 2 should have skipped this already since it's not a static `o.bind`
call; if you find it wasn't yet documented as dropped, add this comment
inside `binds { }` now:
```kdl
    // default/hypr/bindings/utilities.lua also dynamically binds
    // RETURN/CTRL+RETURN/TAB/CTRL+TAB/arrow-keys while
    // omarchy-capture-region's slurp-based selection overlay is open
    // (via Hyprland's layer.opened/layer.closed events). No niri
    // equivalent event exists to replicate this. Whether
    // omarchy-capture-region needs this at all under niri is a separate,
    // later investigation — not solved here.
```

- [ ] **Step 4: Close the `binds { }` block**

This is the last bindings task in execution order. Close the `binds { }`
block with a final `}` if it's still open from Tasks 2-3.

- [ ] **Step 5: Validate, sanity-check, and commit**

```bash
command -v niri >/dev/null && niri validate -c default/niri/config.kdl || echo "no niri binary on this host, skipping KDL validation — rely on live-VM verification instead"
git add default/niri/bindings.kdl
git commit -m "Port the clipboard-manager toggle to Niri; document what has no equivalent"
git push
```
Verify the push landed via `git ls-remote origin niri-support`. If
`niri validate` ran and failed, fix the reported errors before
committing — this is the first point in the plan where the full
`binds { }` block is syntactically complete and can actually be
validated end-to-end.

---

## Task 5: Input settings

**Files:**
- Modify: `default/niri/config.kdl`

**Interfaces:**
- Consumes: the `input { }` block Task 1 already created (extend it, do
  not replace it wholesale — Task 1's `xkb { }`/`numlock`/`repeat-rate`/
  `repeat-delay`/`touchpad` content should already be correct per the
  spec; this task only adds what's still missing after checking).

**Context:** Read `default/hypr/input.lua` in full, and compare against
what Task 1 already put in `default/niri/config.kdl`'s `input { }` block.

- [ ] **Step 1: Confirm what Task 1 already covered, add what's missing**

Task 1's `config.kdl` already has `xkb {}` (empty, deliberate),
`numlock`, `repeat-rate 40`, `repeat-delay 250`, and a `touchpad { tap;
clickfinger-behavior; scroll-factor 0.4; }` block. Cross-check this
against `input.lua`'s actual values (`repeat_rate = 40`,
`repeat_delay = 250`, `numlock_by_default = true`,
`touchpad.clickfinger_behavior = true`, `touchpad.scroll_factor = 0.4`,
`touchpad.natural_scroll = false`) — these should already match. If they
don't (e.g. if Task 1 was executed with different values), fix them to
match `input.lua`'s real values now.

`natural_scroll = false` in Hyprland means natural-scroll is explicitly
OFF. Per niri's own config convention (a touchpad setting only takes
effect by being *present* in the block — omitting it means "off"/default,
not "on"), confirm the `touchpad { }` block does NOT contain a
`natural-scroll` line (its absence is correct, not a gap) — if Task 1
accidentally added one, remove it.

- [ ] **Step 2: DPMS-wakes-on-input verification note**

Add a comment near the `input { }` block:
```kdl
// key_press_enables_dpms / mouse_move_enables_dpms (Hyprland's DPMS-
// wake-on-input settings) are not configured here. This project's idle
// handling already uses the standard ext-idle-notify-v1 protocol under
// Niri (confirmed working), which may already cover this with no
// explicit config needed. Verify live in the VM (see this plan's
// closing Verification section) before adding explicit config here.
```

- [ ] **Step 3: Per-terminal touchpad scroll tweaks**

`input.lua`'s last two lines apply a per-app `scroll_touchpad` window
rule to terminal emulators. This belongs in `window-rules.kdl` (Task 7),
not here — if you're executing this task before Task 7, just leave a
one-line note in this task's commit/report flagging it for Task 7 to
pick up (don't silently drop it, and don't try to implement it here out
of the wrong file).

- [ ] **Step 4: Commit**

```bash
git add default/niri/config.kdl
git commit -m "Confirm and finalize Niri input settings"
git push
```
Verify the push landed via `git ls-remote origin niri-support`.

---

## Task 6: Look-and-feel — gaps, border, shadow, cursor confirmation

**Files:**
- Modify: `default/niri/config.kdl`
- Modify: `default/themed/niri.kdl.tpl` (only if Task 1's Step 3 left
  this genuinely unfinished — check first, don't redo working content)

**Interfaces:**
- Consumes: the `layout { }`/`cursor { }` blocks Task 1 already created.

**Context:** Read `default/hypr/looknfeel.lua` in full, and compare
against what Task 1 already put in `config.kdl`.

- [ ] **Step 1: Confirm gaps, border, shadow against the real theme values**

`looknfeel.lua` has `gaps_in = 5, gaps_out = 10` (Task 1 used a single
value of `8` as a reasonable middle ground, per the spec's "one sensible
value" guidance — confirm this is still what's in the file; adjust only
if it looks visually wrong once live-tested, not preemptively). Confirm
`border { width 2; ... }` matches `border_size = 2`. Confirm the
`shadow { }` block is empty/off (matching `shadow.enabled = false`) and
that no `blur`-related content was added anywhere (niri has no blur
concept at all).

- [ ] **Step 2: Confirm the theme template produces a real gradient**

Task 1 already added a `niri_gradient_value()` helper to
`bin/omarchy-theme-set-templates` and created
`default/themed/niri.kdl.tpl` using it. Confirm both are present and
correct (re-read them), then test concretely: run
`omarchy-theme-set-templates` in a context with a real `colors.toml`
available (check `themes/*/colors.toml` in this repo for a real example,
or use the actual `omarchy-theme-set <some-theme-name>` command if this
task is executed somewhere with a full Omarchy environment) and confirm
the generated `~/.local/state/omarchy/current/theme/niri.kdl` (or
equivalent staged path) contains valid KDL with real hex colors
substituted in — `active-gradient from="#..." to="#..." angle=..."` and
`inactive-color "#..."` — not literal `{{ }}` template syntax left
unprocessed. If anything is actually broken (not just unfinished), fix
it; this step should mostly be confirmation, not new design work.

- [ ] **Step 3: `allow_session_lock_restore` note**

Add a one-line comment near `config.kdl`'s top (or wherever makes sense
structurally) noting this Hyprland setting's niri counterpart doesn't
exist:
```kdl
// Hyprland's misc.allow_session_lock_restore has no niri equivalent —
// this is the config-side half of the already-documented,
// still-unsolved stranded-lock recovery gap (see this project's own
// memory/status notes and
// docs/superpowers/specs/2026-08-23-omarchy-niri-design.md's "Known
// open risk"). Not solved by this plan.
```

- [ ] **Step 4: Validate, sanity-check, and commit**

```bash
command -v niri >/dev/null && niri validate -c default/niri/config.kdl || echo "no niri binary on this host"
git add default/niri/config.kdl default/themed/niri.kdl.tpl
git commit -m "Finalize Niri look-and-feel: gaps, border, shadow, theme gradient"
git push
```
Verify the push landed via `git ls-remote origin niri-support`.

---

## Task 7: Window rules

**Files:**
- Modify: `default/niri/window-rules.kdl`

**Interfaces:**
- Consumes: the stub file from Task 1.

**Context:** Read `default/hypr/windows.lua`, every file under
`default/hypr/apps/` (19 files, ~196 lines total), and the tail of
`default/hypr/input.lua` (the two per-terminal `scroll_touchpad` rules,
flagged by Task 5 as belonging here) — all in full before writing
anything.

- [ ] **Step 1: Global opacity default**

```lua
o.window(".*", { tag = "+default-opacity" })
-- ...
o.window({ tag = "default-opacity" }, { opacity = "0.985 0.96" })
```
→ a single catch-all rule (niri's `WindowRule` has one `opacity` field,
not an active/inactive pair — per this plan's Global Constraints):
```kdl
window-rule {
    opacity 0.985
}
```
Any app-specific rule elsewhere in `apps/*.lua` that removes the
`default-opacity` tag (i.e. opts a specific app OUT of this default) needs
its own niri rule setting `opacity 1.0` (fully opaque) scoped to that
app's `match`, translated in Step 3 below alongside that app's other
rules.

- [ ] **Step 2: Maximize-suppress and XWayland drag-fix — document as
  unverified, don't blindly port**

```kdl
// The following two Hyprland window rules are NOT translated:
//   - suppress_event = "maximize" (applied to all windows)
//   - the XWayland empty-class/title/float/non-fullscreen/unpinned
//     no_focus rule (an XWayland drag-fix workaround)
// Both look Hyprland-internals-specific, and Niri uses a structurally
// different XWayland integration (a separate xwayland-satellite
// process) — the underlying bug the drag-fix works around may not even
// reproduce here. Verify live whether Niri has the same XWayland drag
// issue before deciding whether either of these needs a real niri
// translation. See
// docs/superpowers/specs/2026-08-25-omarchy-niri-config-design.md.
```

- [ ] **Step 3: Translate every app-specific rule**

For each file in `default/hypr/apps/`, translate its `o.window(match,
rules)` calls to niri `window-rule { match app-id=... title=...; ... }`
blocks. Field-name mapping: Hyprland's `class` regex → niri's `app-id`
regex (same regex semantics — both are standard regex engines; if any
rule uses an unusual regex feature, note it and verify live rather than
assuming compatibility). `title` maps directly (same field name both
sides). Hyprland `float = true` → niri `open-floating true`.
`workspace = "N"` → niri `open-on-workspace "N"`. `opacity` → niri's
single-value `opacity` field. For any Hyprland rule property with no
obvious niri counterpart in the `WindowRule` fields already confirmed in
this plan's Global Constraints, check niri's actual `WindowRule` struct
(read `niri-config/src/window_rule.rs` from a local niri source checkout
if one is available in this environment — clone
`https://github.com/YaLTeR/niri.git` fresh if not, matching how earlier
work in this project already did this repeatedly for exactly this kind
of confirmation) before deciding whether it's a real translation or
belongs in the drop-list; don't guess a field name.

Organize the output with one comment header per source file, e.g.:
```kdl
// ---- default/hypr/apps/<filename>.lua ----
window-rule {
    match app-id=r#"..."#
    ...
}
```

- [ ] **Step 4: Per-terminal touchpad scroll tweaks (from `input.lua`)**

```lua
o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })
o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })
```
Check niri's `WindowRule` struct (same source-check as Step 3) for a
touchpad-scroll-factor-equivalent field. If one exists, translate both
rules. If none exists, add a one-line drop comment here (not in
`config.kdl` — this belongs with the other window-rule content) noting
it and move on; don't invent a field.

- [ ] **Step 5: Validate, sanity-check, and commit**

```bash
command -v niri >/dev/null && niri validate -c default/niri/config.kdl || echo "no niri binary on this host"
git add default/niri/window-rules.kdl
git commit -m "Translate Hyprland window rules to Niri, including all per-app rules"
git push
```
Verify the push landed via `git ls-remote origin niri-support`.

---

## Task 8: Autostart

**Files:**
- Modify: `default/niri/config.kdl`

**Interfaces:**
- Consumes: `config.kdl` as finalized by Tasks 1-7 — this task only adds
  `spawn-at-startup`/`spawn-sh-at-startup` lines near the bottom, above
  the `include "bindings.kdl"`/`include "window-rules.kdl"` lines Task 1
  already placed at the end (or wherever structurally sensible — read
  the current file first to place these consistently with its existing
  organization, don't just blindly append at the very end after the
  includes).

**Context:** Read `default/hypr/autostart.lua` in full.

- [ ] **Step 1: Direct ports**

```kdl
spawn-at-startup "omarchy-launch-shell"
spawn-at-startup "omarchy-provision-first-run"
spawn-at-startup "omarchy-powerprofiles-init"
spawn-at-startup "udiskie" "--automount" "--no-notify" "--no-tray"
spawn-sh-at-startup "sleep 2 && omarchy-hook post-boot"
```
The `omarchy-launch-shell` line is what closes today's noted gap (Niri
not auto-launching the shell) — confirm this is genuinely present before
committing, it's the most user-visible part of this task.

- [ ] **Step 2: Monitor-watch script**

`autostart.lua` runs `omarchy-hyprland-monitor-watch` (via `o.launch()`,
i.e. `uwsm-app -- omarchy-hyprland-monitor-watch`). Check whether a niri
equivalent already exists (search `bin/` for anything like
`omarchy-niri-monitor-watch`; this project already has
`omarchy-niri-monitor-focused` from earlier work, a different but
related script — read it for reference). If no watch-equivalent exists,
read `bin/omarchy-hyprland-monitor-watch` to understand what it actually
does (likely: watches for monitor hotplug events and reacts, e.g.
re-running layout/scale logic), and decide whether Niri needs an
equivalent at all — niri's own output-hotplug handling may already cover
what this script exists for, given niri is a much newer, more actively
maintained compositor with first-class multi-monitor support built in
from the start (unlike Hyprland's more bolted-on evolution here). If it's
genuinely needed, building it is real, separate script work — write it
following `omarchy-hyprland-monitor-watch`'s structure, using
`niri msg -j event-stream`'s output-related events (already used
elsewhere in this project's `NiriService`, a working reference
implementation) rather than reinventing the watching mechanism from
scratch. If it's not needed, add a one-line comment explaining why and
move on — don't add a startup line calling a script that doesn't exist.

- [ ] **Step 3: Session environment propagation**

`autostart.lua` also runs, before anything else:
```lua
hl.exec_cmd("systemctl --user import-environment $(env | cut -d'=' -f 1)")
hl.exec_cmd("dbus-update-activation-environment --systemd --all")
```
Check whether niri's `--session` flag (used in this project's own
`omarchy-niri.desktop` via `uwsm start ... niri niri.desktop`, which
should end up passing `--session` through niri's own systemd/uwsm
integration — confirm this by checking how `niri.desktop` — the file
uwsm actually reads to launch niri, likely `/usr/share/wayland-sessions/
niri.desktop` or a uwsm-specific location, not this project's own
`omarchy-niri.desktop` — invokes niri, and whether `--session` appears)
already handles this environment propagation. If it does, this Hyprland
dance is unneeded under niri — add a comment noting the check was done
and why it's not ported, rather than blindly translating it. If genuine
uncertainty remains after checking, port it as a `spawn-sh-at-startup`
matching Hyprland's own two commands verbatim (safe either way — running
these twice, once via niri's own session handling and once via this
project's spawn, should be harmless even if redundant) and flag the
redundancy question for live verification.

- [ ] **Step 4: Validate, sanity-check, and commit**

```bash
command -v niri >/dev/null && niri validate -c default/niri/config.kdl || echo "no niri binary on this host"
git add default/niri/config.kdl
git commit -m "Add Niri session autostart entries, closing the shell-autostart gap"
git push
```
Verify the push landed via `git ls-remote origin niri-support`.

---

## Verification

This plan was written without a niri binary available on the planning
host for live `niri validate` checks against every task's output (some
tasks may have run validation via SSH to the project's dev VM instead —
check each task's own report for which path was used). Regardless of
validation-time checking, none of this has been live-tested in a running
Niri session — this is a large, foundational change touching every
aspect of the session (keybindings, input, appearance, window behavior,
autostart), so live verification needs to be genuinely thorough, not a
quick pass:

- [ ] `omarchy dev link`'s existing workflow still works: confirm
  `~/.config/niri/config.kdl` gets correctly generated on next Niri
  login with the right `OMARCHY_PATH` baked in (check its contents
  directly), and that logging into Niri afterward doesn't error (check
  `quickshell log`/niri's own logs for KDL parse errors — a bad config
  should fail loudly, confirm it doesn't fail at all).
- [ ] Spot-check keybindings across every category: at least one
  application launch, one media/volume key, one utility/menu toggle, one
  window-management action (focus, move, fullscreen, floating), one
  workspace-number switch, one monitor-focus action, the clipboard
  manager toggle.
- [ ] Confirm the shell now auto-launches on Niri login with no manual
  `omarchy-launch-shell` needed (the gap noted in this project's own
  status notes on 2026-08-25).
- [ ] Confirm gaps/border color/border gradient render correctly and
  match the active theme (switch themes with `omarchy-theme-set` and
  confirm the border color changes live under Niri, matching how it
  already changes under Hyprland).
- [ ] Confirm at least a few translated window rules actually apply
  (pick 2-3 apps from `apps/*.lua` with distinctive rules — e.g. one
  that opens floating, one with a workspace assignment — and confirm the
  niri-side behavior matches).
- [ ] Work through this plan's own "Open Questions for Implementation"
  from the design spec (repeated here for convenience — resolve each
  with live evidence, not assumption):
  1. Does the empty `xkb {}` block pick up the right layout from
     `org.freedesktop.locale1`?
  2. Does niri need explicit DPMS-wake-on-input config, or does it
     already work?
  3. Does the XWayland drag bug actually reproduce under niri's
     `xwayland-satellite` architecture?
  4. Does niri have a touchpad-scroll-factor window-rule equivalent (Task
     7 should have already resolved this via source-reading, but confirm
     live too)?
  5. Does niri's `--session` flag already handle environment propagation
     (Task 8 should have investigated this — confirm the conclusion live)?
  6. Was a monitor-watch niri equivalent actually needed (Task 8's
     conclusion, confirmed live)?
- [ ] Confirm Hyprland's own session is completely unaffected — none of
  this plan's files are read by the Hyprland session at all, but this is
  large enough, and Task 1 touches shared infrastructure
  (`omarchy-theme-set`), that a side-by-side confirmation is worth doing
  explicitly rather than assuming.
