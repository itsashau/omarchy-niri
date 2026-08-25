# Omarchy Niri Config — Design

## Overview

Omarchy 4.0's Hyprland session is configured through a tree of Lua files
under `default/hypr/` (bindings, input, look-and-feel, window rules,
autostart), refreshed into `~/.config/hypr/` and layered with a
theme-generated color override. Niri has no equivalent config at all in
this fork yet — the bare-session work (Phase 3) only shipped the login
session entry, so a Niri session currently runs on niri's own built-in
stock default config with no Omarchy customization whatsoever.

This spec designs a full parity pass: a Niri config tree under
`default/niri/`, structurally parallel to `default/hypr/`, covering
keybindings, input, appearance, window rules, and autostart — plus the
theme-color integration that lets Omarchy's theme switcher restyle Niri's
borders the same way it restyles Hyprland's.

Where a Hyprland behavior has no real Niri equivalent (several do — see
below), this spec documents that explicitly rather than forcing an
approximate translation. The goal is an honest port, not a fictional one.

## Goals

- A `default/niri/` config tree, dev-linkable the same way
  `default/hypr/` already is, giving a Niri session real Omarchy
  keybindings, input settings, appearance, and window rules instead of
  niri's stock defaults.
- Theme switching restyles Niri's border/focus-ring colors the same way
  it already restyles Hyprland's, using the existing generic templating
  engine (`omarchy-theme-set-templates`) — no new templating mechanism.
- Compositor-agnostic actions (terminal, launcher, screenshot,
  volume/brightness, lock, all the `omarchy-shell`/`omarchy-menu`/
  `omarchy-launch-*` bindings) keep the exact same key combinations as
  Hyprland, for muscle memory — per the project's existing design spec.
- Window-management keys use Niri's own idioms (column focus/move/
  consume/expel) rather than forcing a model that doesn't exist in Niri.
- Every Hyprland behavior with no real Niri equivalent is explicitly
  documented as dropped (with a one-line reason), not silently omitted or
  forced into an approximate but misleading mapping.

## Non-Goals

- Reproducing Hyprland's exact animation feel. Niri categorizes
  animations by a different, incompatible set of event types (see
  "Look-and-feel" below); this spec uses niri's own stock animation
  defaults rather than a granular per-type translation.
- Solving the non-Latin-keyboard-layout keybind fallback. This is a real
  Hyprland workaround with an unverified niri equivalent, but doesn't
  affect this fork's actual owner (a Latin/English keyboard) — deferred
  as a follow-up if it's ever actually needed, not solved speculatively.
- The stranded-lock recovery gap (already documented, unsolved, from the
  idle-lock-parity work). `looknfeel.lua`'s `allow_session_lock_restore`
  setting is the Hyprland-side half of that same gap; this spec doesn't
  attempt to solve it, only notes the connection.
- Multi-monitor-specific window/workspace behavior beyond what's already
  in scope elsewhere (already a documented deferred gap for this project;
  this VM is single-output, so most of it can't be tested here anyway).

## Architecture

### File structure

```
default/niri/
  config.kdl        — entry point: input{}, layout{} (gaps/border/shadow/
                       struts), cursor{}, animations{}, hotkey-overlay{},
                       spawn-at-startup lines, and three includes:
                       theme colors (optional), bindings.kdl,
                       window-rules.kdl
  bindings.kdl       — every keybind, translated from all 6 Hyprland
                       binding files, organized under comment headers
                       that preserve the original files' groupings
                       (Applications / Media & Utilities / Window
                       Management) for readability and future diffing
                       against upstream Hyprland changes
  window-rules.kdl   — the global near-opaque default plus every
                       per-app rule translated from windows.lua and the
                       19-file default/hypr/apps/ directory

default/themed/
  niri.kdl.tpl       — new theme template (parallel to
                       hyprland.lua.tpl), generates only the border/
                       focus-ring colors from the active theme's
                       palette, via the existing generic
                       {{ hypr_gradient ... }}-style substitution engine
                       in omarchy-theme-set-templates (already handles
                       any *.tpl file in this directory — no engine
                       changes needed, this is purely a new template)
```

### Dev-link / runtime resolution

Niri's `include "path"` directive expands `~` to the home directory, and
resolves any other relative path against the directory of the file doing
the including — but has **no environment-variable expansion**, unlike
Hyprland's Lua config (`os.getenv("OMARCHY_PATH")`). This means the
existing Hyprland pattern — a thin, static `~/.config/hypr/hyprland.lua`
whose `require()` calls resolve live against `$OMARCHY_PATH` at Lua
runtime — can't be copied verbatim for niri's static KDL includes.

Instead: whatever wires up `omarchy dev link` support for niri (an
addition to the existing dev-link/refresh tooling — the exact touchpoint
is an implementation-plan decision, not a design one) generates
`~/.config/niri/config.kdl` as a single line with the actual resolved
`OMARCHY_PATH` value baked in literally:

```kdl
include "/home/ash/omarchy-niri-fork/default/niri/config.kdl"
```

Everything else (`bindings.kdl`, `window-rules.kdl`, the theme override)
is included using ordinary relative-to-including-file paths from inside
`default/niri/config.kdl` itself, which resolve correctly regardless of
where that top-level generated file lives — the same live-editing benefit
`omarchy dev link` already gives Hyprland and the Quickshell shell.

### Theme color integration

`default/niri/config.kdl` includes the theme override near its `layout`
section:

```kdl
include "~/.local/state/omarchy/current/theme/niri.kdl" optional=true
```

`optional=true` means this silently no-ops before the theme system has
ever run (e.g. right after `omarchy dev link`, before the first
`omarchy-theme-set`), then picks up colors the moment it does — exactly
mirroring how Hyprland's `require_optional.module("omarchy.current.theme.hyprland")`
behaves. `omarchy-theme-set-templates` needs zero changes; it already
processes every `*.tpl` file in `default/themed/` generically, so adding
`niri.kdl.tpl` there is enough.

Niri's `include` merges the included file's `layout { border { ... } }`
block into the main config's own `layout { }` recursively (confirmed
from niri's config-merge implementation — `layout` uses `merge_with`, not
whole-section replacement), so the theme file only needs to set border/
focus-ring colors, not repeat the rest of the layout config.

### Applying a theme change live

`omarchy-theme-set`'s existing `post_theme_commands` array (which already
runs `omarchy-restart-hyprctl` for the Hyprland side) gets one more
command: `niri msg action load-config-file` (confirmed exact CLI syntax
from niri's own IPC source — reloads the currently-loaded config file,
no path argument needed). Niri also auto-watches its config file and
reloads on a short delay regardless, so this is purely for immediate,
deterministic application matching how `hyprctl reload` behaves — not
strictly required for correctness, just for feel-parity with the
Hyprland theme-switch experience.

## Keybind translation

### Principle: mechanical where the underlying command is compositor-agnostic

`applications.lua`'s `o.bind(keys, description, { omarchy = "..." })` (and
the `{ launch = ... }` / `{ webapp = ... }` / `{ tui = ... }` variants)
all resolve, via `command_from()` in `helpers.lua`, to plain shell
commands (`omarchy-launch-<name>`, `omarchy-launch-webapp <url>`,
`omarchy-launch-or-focus ...`, etc.) — confirmed by reading the helper's
full resolution logic, not assumed. The same is true for nearly all of
`media.lua` and `utilities.lua` (volume/brightness/media-key bindings,
menu toggles, notification controls, panel toggles, screenshot/capture
commands) and all of `voxtype.lua`. None of these commands know or care
which compositor invoked them.

These translate directly into niri `binds{}` entries using the same key
combination (`Mod` = Super, matching both Hyprland's convention and
niri's own default config), calling the identical shell command via
`spawn` (single command, no shell features needed) or `spawn-sh` (when
the original uses `||`, pipes, or multiple arguments assembled as one
string). `{ locked = true }` bindings (volume/brightness keys, power
menu, lid-switch handling) become `allow-when-locked=true`, niri's own
equivalent property. `{ repeating = true }` needs no niri-side
equivalent property — niri's binds repeat on physical key-repeat by
default; the Hyprland `repeating` flag is opting *in* to something niri
already does unconditionally.

### Principle: window-management uses niri's own idioms, not a forced mapping

`tiling.lua`'s directional focus/move/swap bindings map onto niri's own
`focus-column-left/right`, `focus-window-up/down`, `move-column-left/
right`, `move-window-up/down`, using niri's own suggested key layout
(arrows plus hjkl, both bound to the same actions, matching niri's own
default config precedent) rather than trying to preserve Hyprland's exact
key-to-action pairing where the underlying action doesn't exist.
Workspace-by-number, monitor-focus/move, fullscreen, and floating-toggle
all have direct niri actions and port with the same key combos Hyprland
already uses. Resize-by-pixel-amount (`hl.dsp.window.resize({ x=-100,
y=0, relative=true })`) becomes niri's `set-column-width "-10%"` /
`set-window-height` — a percentage-based model, not a pixel-nudge one;
the exact percentage-per-keypress is an implementation detail, not a
design question.

### Explicitly dropped: no real niri equivalent

Each of these gets a one-line comment in `bindings.kdl` explaining why it
isn't there, rather than being silently omitted:

- **Window grouping** (tabs within a window, `hl.dsp.group.*`) — niri
  only has tabbed *columns* (`toggle-column-tabbed-display`), a
  structurally different, column-scoped concept, not an arbitrary
  multi-window group. Not ported.
- **Scratchpad / special workspace** (`workspace = "special:scratchpad"`)
  — niri has no floating hidden-workspace concept at all. Not ported.
- **Dwindle/pseudo-tiling toggle**, and the entire contents of
  `workspace-layouts.lua` (saving/restoring per-workspace Hyprland
  layouts) — niri has exactly one layout model (scrollable tiling
  columns), no alternate layouts to toggle or restore. Not ported; that
  whole file has no niri translation.
- **The clipboard universal-shortcut trick** (`clipboard.lua`'s
  `send_key_state`-based synthetic key injection distinguishing terminal
  vs. GUI paste behavior, reaching both normal windows and layer-shell
  surfaces) — this is Hyprland-dispatcher-specific; niri's IPC has no
  equivalent "send this key combo to the focused surface" action. Only
  the plain clipboard-manager toggle (`Mod+Ctrl+V`) ports; the
  Ctrl+C/V-vs-Ctrl+Insert/Shift+Insert terminal distinction does not.
- **The region-picker's dynamic per-layer keybind registration**
  (`utilities.lua`'s `hl.on("layer.opened"/"layer.closed", ...)`, which
  binds RETURN/TAB/arrow keys only while `omarchy-capture-region`'s
  selection overlay is on screen) — Hyprland-event-API-specific, no
  obvious niri equivalent event. `omarchy-capture-region` itself is a
  separate, existing script (uses `slurp`) whose own keyboard handling is
  out of scope for this spec; whether it needs this at all under niri is
  a separate, later investigation, not solved here.
- **Window-group resize/cycle binds** (`Super+Alt+Left/Right/Up/Down`
  into-group, `Super+Alt+Tab` group-cycle, `Super+Ctrl+Left/Right`
  grouped-focus) — consequence of grouping not existing, same as above.

### Deferred, not dropped

- **Non-Latin keyboard layout keybind fallback** — see Non-Goals. Not
  needed for this fork's actual keyboard; revisit only if it becomes
  needed.

## Input

- `input { keyboard { xkb { } } }` left empty first, letting niri fetch
  settings from `org.freedesktop.locale1` automatically (per niri's own
  default-config documentation) — this needs zero config-generation
  logic, unlike Hyprland's `/etc/vconsole.conf`-reading dance. Falls back
  to explicit `layout`/`variant`/`options` values (read the same way
  Hyprland's `input.lua` already does) only if live testing shows the
  automatic path doesn't pick up the right layout.
- `keyboard { numlock }`, `repeat-rate 40`, `repeat-delay 250` — direct
  equivalents of Hyprland's `numlock_by_default`/`repeat_rate`/
  `repeat_delay`.
- `touchpad { natural-scroll; tap; }` — Hyprland's
  `touchpad.natural_scroll = false` means this fork actually runs
  natural-scroll *off*; niri's `touchpad { }` block only enables a
  setting by being *present* (per niri's own default-config comments —
  "omitting settings disables them"), so `natural-scroll` is simply
  omitted, not written as `off`. `tap` (tap-to-click) has no explicit
  Hyprland setting in this fork's current config to translate — niri's
  own default already enables it; left as-is.
- `clickfinger_behavior`/`scroll_factor` (Hyprland touchpad settings) —
  standard libinput settings; niri's `touchpad { }` block has direct
  equivalents for both. Ports directly.
- DPMS-wakes-on-any-input (`key_press_enables_dpms`/
  `mouse_move_enables_dpms`) — flagged for live verification rather than
  assumed. This project's idle handling already uses the standard
  `ext-idle-notify-v1` protocol under niri (confirmed working, from the
  idle-lock-parity work), so DPMS wake behavior may already work
  correctly with no niri-side config at all. Verify live; add explicit
  config only if the VM shows it's actually needed.
- `cursor { hide-when-typing }` — direct equivalent of
  `cursor.hide_on_key_press` (confirmed matching field in niri's own
  `Cursor` config struct). `warp_on_change_workspace` has no matching
  field in niri's cursor config at all — dropped, minor cosmetic setting.

## Look-and-feel

- **Gaps**: niri's `layout { gaps N }` is a single value (no
  Hyprland-style inner/outer split). Use one sensible value rather than
  trying to preserve the exact 5px-inner/10px-outer distinction, which
  niri's model doesn't have.
- **Border**: `layout { border { width 2; active-color / active-gradient
  ...; inactive-color ... } }`. Niri's border supports gradients natively
  (`active-gradient from=... to=... angle=...`), so the current theme's
  45°, two-color active-border gradient can be preserved exactly, not
  approximated as a flat color. Colors come from `niri.kdl.tpl` (see
  Architecture above), the same theme palette Hyprland's border already
  uses.
- **Rounding / shadow / blur**: the current theme has all three
  effectively off (`rounding = 0`, `shadow.enabled = false`,
  `blur.enabled = false`). Nothing to actively port: niri's shadow
  defaults off already, blur isn't a niri concept at all (dropped, but
  moot since it's off anyway), and corner-radius simply isn't set
  (defaults to square corners, matching `rounding = 0`).
- **`layout = "dwindle"`, window-group border/groupbar styling** — no
  niri equivalent (niri has one layout model; no grouping). Not ported,
  consistent with dropping grouping/dwindle in the Keybinds section.
- **`allow_session_lock_restore`** — this *is* the already-documented,
  still-unsolved stranded-lock recovery gap from the idle-lock-parity
  work, not a new finding. Noted here for completeness; not solved by
  this spec.
- **Animations** — niri categorizes animations by semantic event type
  (`window_open`, `window_close`, `window_movement`, `window_resize`,
  `workspace_switch`, `horizontal_view_movement`, plus a few UI-specific
  ones like `overview_open_close`) — confirmed from niri's own config
  schema. This has no clean 1:1 mapping to Hyprland's per-effect "leaves"
  (`fade`, `fadeSwitch`, `layers`, `layersIn`/`layersOut`, etc. — a
  different categorization built around a different compositor's
  internal effect pipeline). This spec uses niri's own stock animation
  defaults rather than attempting a granular per-type translation of
  Hyprland's tuned curves/speeds — a deliberate simplification (cosmetic
  only, and niri's defaults are already tuned for its own scrolling-view
  interaction model, which Hyprland's animation feel wasn't designed
  around anyway).

## Window rules

- **Global default opacity**: Hyprland's `opacity = "0.985 0.96"` (active/
  inactive pair) becomes a single niri `opacity` value on a catch-all
  `window-rule` (confirmed niri's `WindowRule` struct has an `opacity:
  Option<f32>` field — single value, no active/inactive distinction to
  preserve).
- **Field-name mapping**: Hyprland's `class`/`title` regex match becomes
  niri's `app-id`/`title` regex match (`window-rule { match
  app-id=r#"..."# title="..."; ... }`) — same regex semantics
  (Rust `regex` crate on niri's side vs Hyprland's own regex engine;
  assumed compatible for the simple patterns this fork's app rules use,
  worth a spot-check during implementation on any rule using more exotic
  regex features).
- **Maximize-event suppression** and **the XWayland empty-class/title
  drag-fix** (`windows.lua`'s two Hyprland-specific window rules): both
  look Hyprland-internals-specific with no obvious niri equivalent, and
  niri uses a structurally different XWayland integration entirely (a
  separate `xwayland-satellite` process, confirmed as its own config
  section in niri's schema, rather than Hyprland's built-in XWayland
  support) — the underlying bug this workaround exists for may not even
  reproduce under niri's different architecture. Flagged for live
  verification rather than blindly porting a workaround for a bug that
  may not exist here.
- **The 19-file, 196-line `default/hypr/apps/` directory** of per-app
  rules: this spec establishes the translation convention above (field
  names, opacity model) but doesn't pre-translate all 19 files here —
  that's mechanical, per-file work for the implementation plan, not a
  design decision.
- **Per-app touchpad scroll-factor tweaks** (`input.lua`'s terminal-
  specific `scroll_touchpad` window rules) — niri's `WindowRule` struct
  needs checking for an equivalent property during implementation; if
  none exists, drop and note it (a minor per-app scroll-feel tweak, not
  core functionality).

## Autostart

Fixes today's noted gap: Niri doesn't currently auto-launch the Omarchy
shell on login at all (the user has to run it manually every session) —
this spec's `spawn-at-startup`/`spawn-sh-at-startup` lines are what
finally close that gap.

- `spawn-at-startup "omarchy-launch-shell"`, `"omarchy-provision-first-run"`,
  `"omarchy-powerprofiles-init"` — direct ports, same commands Hyprland's
  `autostart.lua` already runs.
- `udiskie --automount --no-notify --no-tray` — compositor-agnostic,
  ports directly via `spawn-at-startup`.
- `omarchy-hyprland-monitor-watch` — Hyprland-specific script name (a
  monitor hot-plug watcher). Needs either a niri-side equivalent script
  (small, separate implementation task — niri's event stream already
  gives this project everything needed to build one, per the existing
  `NiriService` precedent) or confirmation that niri handles monitor
  hotplug adequately without one. Not designed further here — flagged as
  an implementation-time decision, not a blocking one.
- `systemctl --user import-environment ...` / `dbus-update-activation-environment
  --systemd --all` (session environment propagation) — needs checking
  whether niri's own `--session` flag (confirmed to exist in niri's CLI,
  used for exactly this kind of systemd/D-Bus environment integration)
  already handles this via the existing uwsm-based session setup this
  project already uses for niri (per the bare-session work). If so, this
  Hyprland-specific dance is unnecessary under niri entirely — verify
  live before porting it unmodified.
- `sleep 2 && omarchy-hook post-boot` — ports directly via
  `spawn-sh-at-startup "sleep 2 && omarchy-hook post-boot"`.

## Testing Approach

Consistent with this project's established practice: no automated test
can meaningfully verify "does this keybind produce the right window
layout" or "does this border color look right" — this is fundamentally a
live, comparative, side-by-side-with-Hyprland verification job in the VM,
the same way every prior phase of this project has been verified. Given
the scope (300+ individual bindings, dozens of window rules), full
verification will need to be spread across the implementation plan's
tasks rather than one final pass — each task's own closing checklist
verifies its own slice live, rather than deferring everything to the end.

## Open Questions for Implementation

Collected from throughout this spec, for the implementation plan to
resolve with source-confirmation or live-testing before shipping, not
guessing:

1. Does niri's empty `xkb {}` block actually pick up the right layout
   from `org.freedesktop.locale1` in this VM, or is explicit
   layout/variant/options generation needed after all?
2. Does niri need explicit config for DPMS-wake-on-input, or does it
   already work given the existing `ext-idle-notify-v1` integration?
3. Does the XWayland empty-class/title drag bug this fork's window rule
   works around actually reproduce under niri's `xwayland-satellite`
   architecture at all?
4. Does niri's `WindowRule` schema have a touchpad-scroll-factor
   equivalent for the per-app terminal scroll tweaks?
5. Does niri's `--session` flag already handle the environment
   propagation `autostart.lua` currently does by hand for Hyprland?
6. Is there already a niri-side monitor-hotplug-watch script from earlier
   work, or does `omarchy-hyprland-monitor-watch`'s niri equivalent need
   building from scratch?
