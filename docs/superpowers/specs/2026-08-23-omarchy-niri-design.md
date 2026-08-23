# Omarchy + Niri Support — Design

## Overview

Omarchy is an opinionated Linux desktop (configs + themes + a large set of
`omarchy-*` helper commands) built around the Hyprland compositor. As of
Omarchy 4.0 ("Quattro"), it ships as its own bootable installer ISO (rather
than a script layered onto an existing Arch install, which was the model
through the 3.x line), and its entire desktop shell (bar, launcher,
notifications, OSDs, lock screen, polkit agent) was rewritten as a single
long-running Quickshell (Qt/QML) process with a plugin architecture,
replacing the previous set of standalone tools (Waybar, Walker, Mako,
SwayOSD, hyprlock, hypridle, swaybg, polkit-gnome).

This project forks Omarchy 4.0 and adds first-class support for the
[Niri](https://github.com/YaLTeR/niri) compositor (a Rust,
scrollable-tiling Wayland compositor) as an alternative to Hyprland, with
the same theming and shell experience Omarchy already provides.

An existing project, Okimarchy, attempted this against Omarchy 3.x, but is
stale (last commit Nov 2025, never reached 3.2) and was built around the
pre-Quickshell architecture (duplicating Waybar/hyprlock/etc. configs per
compositor) that no longer exists in 4.0. We are not forking or updating
Okimarchy; we are forking vanilla Omarchy 4.0 and building Niri support
against its current Quickshell architecture directly.

Mango (MangoWC), a second compositor of interest, is explicitly deferred —
see Non-Goals.

## Goals

- A working Arch + Omarchy 4.0 desktop, running in a VM, that offers both a
  Hyprland session and a Niri session at login.
- Full parity between the two sessions: bar, launcher, notifications, OSDs,
  lock screen, idle handling, and all shell panels/plugins work under Niri,
  not just a subset.
- Omarchy's theme switcher restyles Niri's own config (borders, gaps,
  colors) the same way it restyles Hyprland's.
- The fork stays mergeable with upstream Omarchy going forward (unlike
  Okimarchy) by keeping Niri-specific additions structurally parallel to
  existing Hyprland-specific code rather than restructuring shared code.
- Built for personal use first. Structured cleanly enough to be shared
  publicly later, but not over-built for that yet (no multi-hardware
  support, no installer polish for strangers, no docs beyond what the
  owner needs).

## Non-Goals (for this spec)

- Mango/MangoWC support. Deferred to a follow-up project once Niri support
  is proven; the service-abstraction pattern built here (see below) is
  intended to generalize to it later.
- A live compositor-switch command (e.g. Okimarchy's `wm-switch`). v1
  offers two login session entries instead; switching means logging out
  and picking the other session.
- Installing on real hardware. All work happens in a VM until Niri support
  is solid.
- Distribution/packaging for other users.

## Architecture

### 1. Fork & repo strategy

Fork `basecamp/omarchy`, pinned at the `v4.0.0` tag (the actual tagged
release — `master` is the old pre-4.0 line at `3.8.5`, and the `quattro`
branch is a rolling dev branch that self-reports `4.0.0.alpha` and has been
observed by other users in a broken half-updated state; a tag is a fixed,
reviewable starting point). Keep an `upstream` remote on `basecamp/omarchy`
and pull updates periodically — this is the discipline Okimarchy skipped,
and why it went stale. Niri additions live in directory shapes parallel to
existing Hyprland ones (e.g. `default/niri/` beside `default/hypr/`, a
`NiriService` beside the existing `HyprlandService` under `shell/`), so
upstream merges stay clean rather than fighting a divergent structure.

Critically, Omarchy 4.0 changed its install model entirely: it is no
longer a script run on top of an existing Arch install (the old
`curl boot.sh | OMARCHY_REPO=... bash` pattern Okimarchy used, which only
exists on the `master`/3.x line). It now ships as its own bootable ISO
that performs the full OS install itself. Development against a fork
therefore does not mean building a custom ISO — Omarchy ships an official,
supported mechanism for exactly this: `omarchy dev link <path-to-checkout>`
writes `/etc/omarchy.conf` so the system resolves `bin/`, `default/`,
`shell/` (including the Quickshell code), `themes/`, `applications/`, and
`config/` from a local git checkout instead of the installed copy, and
makes `sudo omarchy-*` resolve from that checkout too (effective after a
reboot). The workflow is: install vanilla Omarchy once from the official
ISO, clone the fork onto that system, `omarchy dev link` it in, reboot.

One limit of `dev link`: it only covers those `$OMARCHY_PATH`-resolved
trees. Anything installed to a fixed system path — `/etc/`, systemd units,
udev rules, and notably `/usr/share/wayland-sessions/*.desktop` session
entries — is NOT covered. Adding the Niri login session entry (spec Phase
3) will need `omarchy-dev-pkg-test` or an equivalent packaging step rather
than dev-link alone; this is called out again in Phasing below.

### 2. Session / compositor architecture

No install-time "mode" and no runtime switcher in v1. Both compositors are
installed side by side, each with its own login session entry
(`omarchy-hyprland.desktop`, `omarchy-niri.desktop`); the user picks one at
the display manager. The Quickshell shell process detects which compositor
launched it by checking for `$NIRI_SOCKET` vs
`$HYPRLAND_INSTANCE_SIGNATURE`, and loads the matching backend service —
the same mechanism DankMaterialShell uses to support multiple compositors
without separate builds.

### 3. Service abstraction (the core of the project)

`HyprlandService` currently exposes workspaces, windows, focus, and
outputs to the rest of the shell (bar, launcher, plugins) as reactive QML
properties/signals, sourced from Hyprland's IPC (`hyprctl`/socket).
`NiriService` exposes the *same shape* of properties/signals, sourced from
Niri's own socket protocol (`$NIRI_SOCKET`, `EventStream` mode). Because
shell UI code only ever talks to "the active service" rather than a
specific compositor, bar/launcher/notification/panel components need zero
per-compositor branching once `NiriService` satisfies the same interface
as `HyprlandService`.

Implementation reference: `quickshell-ii-niri`'s existing `NiriService` is
prior art for bridging Niri's IPC into a Quickshell QML service, and will
be used as a reference/port basis rather than reverse-engineering Niri's
protocol from scratch.

### 4. Niri config generation & keybinds

Niri's config is a static KDL file (unlike Hyprland's newer Lua-templated
config in Omarchy 4.0). Omarchy's existing theme-generation step is
extended to also render `~/.config/niri/config.kdl` from the active
theme's palette (colors, borders, gaps) whenever the theme is switched via
the Omarchy menu.

Keybinds: compositor-agnostic actions (launch terminal, open launcher,
screenshot, volume/brightness, lock) stay identical to Hyprland's bindings
for muscle memory. Window-management keys use Niri's own idioms (column
focus/move/consume/expel) rather than forcing a grid-resize model that
doesn't exist in Niri.

### 5. Known open risk

Omarchy 4.0 moved lock-screen and idle handling into the Quickshell
process itself. It is not yet confirmed whether idle detection is
implemented against the standard `ext-idle-notify-v1` Wayland protocol
(which Niri supports, and which would mean idle "just works" under Niri)
or against Hyprland-specific IPC (which would require a Niri-specific idle
path). This is a spike to run early in implementation, not a design
decision to resolve now.

## Phasing

Full parity is the end goal, but lands in stages:

1. VM setup, vanilla Omarchy 4.0 installed from the official ISO, forked
   repo cloned in and linked via `omarchy dev link` as a working
   control/baseline on Hyprland.
2. Fork setup (GitHub fork, `upstream` remote, pinned to `v4.0.0`).
3. Bare Niri session sanity check — Niri package + minimal config +
   `/usr/share/wayland-sessions/omarchy-niri.desktop` entry (packaged via
   `omarchy-dev-pkg-test` or equivalent, since dev-link doesn't cover fixed
   system paths) — logging in, no shell integration yet.
4. `NiriService` implementation + bar working under Niri.
5. Launcher + notifications working under Niri.
6. Lock screen + idle parity under Niri (resolves the open risk above).
7. Remaining shell panels/plugins/OSD parity pass, plus theme KDL
   generation wired into the existing theme switcher.

Mango support (out of scope here) would follow this same phase structure
later, reusing the service-abstraction pattern rather than requiring new
architecture.

## Testing Approach

This is a personal desktop configuration, not a library — there is no
formal automated test suite. Verification per phase is manual, comparative
checking in the VM: for each piece of functionality, confirm the existing
Hyprland behavior still works unchanged, then confirm the equivalent
behavior now also works under Niri, side by side.
