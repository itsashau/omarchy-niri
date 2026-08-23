# Omarchy Niri Bare Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get a second login session — "Omarchy (Niri)" — showing up at the
display manager alongside the existing Hyprland one, and confirm it boots to
a bare, usable Niri compositor session in the dev VM. No Quickshell/bar/theme
integration yet; that's spec Phases 4-7, each their own plan.

**Architecture:** `niri` is already an official Arch package (`extra/niri`,
confirmed installed-able via `pacman -Si niri` on this host, version
`26.04-1`) — no AUR/custom packaging needed for the compositor itself. The
only genuinely new artifact is a `/usr/local/share/wayland-sessions/
omarchy-niri.desktop` session entry, which is a fixed system path outside
what `omarchy dev link` covers (spec Architecture §1). We track the desktop
entry's content in the fork (`default/wayland-sessions/omarchy-niri.desktop`,
parallel to the existing `default/wayland-sessions/omarchy.desktop`) but
install it into the VM by hand (`sudo install`) rather than standing up the
full `omarchy-pkgs` packaging fork this early — see "Deferred: proper
packaging" below for why and when to revisit that.

**Tech Stack:** Arch `pacman`, a wayland-sessions `.desktop` entry, `uwsm`,
niri's own KDL config (auto-generated on first run — we ship none yet).

**Spec:** `docs/superpowers/specs/2026-08-23-omarchy-niri-design.md`
(Phase 3 of Phasing)

## VM environment note (discovered while executing this plan)

The dev VM's virtual GPU was originally `qxl` (set up in the bootstrap
plan). niri's DRM/KMS backend cannot open a device against it
(`Failed to open device: Invalid argument (os error 22)` on
`/dev/dri/card1`), producing a black screen on login even though niri
itself, uwsm, and the session entry all work correctly — confirmed by
running bare `niri` nested inside the working Hyprland session (its
winit backend, no raw DRM, opened a working windowed desktop). Fixed by
switching the VM's video model to `virtio-vga-gl` with `accel3d=yes` and
SPICE to `listen=none, gl.enable=yes, gl.rendernode=/dev/dri/renderD128`
(via `virt-xml --edit`; requires `/dev/dri/renderD*` on the host and a
qemu build with `virtio-vga-gl` support). This lives only in the VM's
libvirt domain XML, not in this repo. Connect to the console afterward
with `virt-viewer --connect qemu:///system --attach <vm-name>` — the
`--attach` flag is required once SPICE listen is `none`.

Also: SDDM's `sessionModel.data(index, Qt.DisplayRole)` does not reliably
return session names in this build — read them via a `Repeater`'s
delegate context instead (QML guarantees role-name properties there).
`default/sddm/omarchy/Main.qml` already reflects this fix.

## Global Constraints

- Everything happens in the `omarchy-niri` VM, dev-linked to
  `~/omarchy-niri-fork` on `niri-support` (bootstrap plan, done). Snapshot
  `omarchy-devlinked-baseline` is the revert point if anything here breaks
  the Hyprland session.
- No shell/theme integration in this plan — that starts at spec Phase 4
  (`NiriService`). Success here is "a Niri session shows at login and a
  terminal opens in it," nothing more.
- `omarchy dev link` does not cover `/usr/local/share/wayland-sessions/`
  (spec Architecture §1) — this plan's session-entry step uses a manual
  `sudo install` in the VM as the interim mechanism, not `dev link`.
- Keep the new `.desktop` entry's *content* version-controlled in the fork
  even though its *installation* is manual for now, so the real packaging
  step (deferred, see below) has exact source to copy from.

## Deferred: proper packaging

`default/wayland-sessions/omarchy.desktop` is actually installed by a
separate `omarchy-settings` Arch package, built from PKGBUILDs that live in
a *different* repo: `omacom-io/omarchy-pkgs` (confirmed via
`git ls-remote` — `basecamp/omarchy-pkgs` does not exist; the fork target is
`omacom-io/omarchy-pkgs`, no tags, actively-synced branches). Per
`docs/file-layout.md`, that PKGBUILD installs it to
`/usr/local/share/wayland-sessions/`, and `bin/omarchy-dev-pkg-test` is the
supported way to build+install a locally-edited version of that package.
Wiring `omarchy-niri.desktop` into that PKGBUILD properly (so a fresh
install or `omarchy-dev-pkg-test` run ships it, instead of a hand-copied
file this VM will forget on reinstall) is real, useful work — but it means
forking a second repo, adding its own `upstream` remote, and finding the
right branch to fork from (no `v4.0.0`-style tag exists there to pin to).
That's disproportionate to do before confirming Niri boots at all under
Omarchy. Revisit this once Phase 3 is proven and before this is shared
with anyone else — a `ponytail`-style flag, not a silent gap: **the session
entry currently lives only as a hand-installed file in one VM.**

---

## Task 1: Install niri and confirm it's a real package

**Files:** None (package install only).

- [ ] **Step 1: Install niri in the VM**

In the VM console:
```bash
sudo pacman -S niri
```
Expected: installs cleanly from the `extra` repo (no AUR helper needed).

- [ ] **Step 2: Add it to the tracked base package list**

Even though this VM already has it installed manually, a fresh Omarchy+Niri
install should get it from the ISO's pacstrap pass too. On the host, in
`~/Projects/omarchy-niri-fork`:

Edit `install/omarchy-base.packages`, adding `niri` alphabetically among the
existing entries (it currently reads `hyprland`, `hyprland-guiutils`,
`hyprland-preview-share-picker`, `hyprpicker`, `hyprsunset`, ... — insert
`niri` in the same alphabetical run, after the `hypr*` block and before
`imagemagick`).

- [ ] **Step 3: Commit**

```bash
cd ~/Projects/omarchy-niri-fork
git add install/omarchy-base.packages
git commit -m "Add niri to the base package list"
git push
```

- [ ] **Step 4: Pull the change into the VM's checkout**

In the VM: `cd ~/omarchy-niri-fork && git pull`
Expected: fast-forward, `niri` line now present in the VM's copy of
`install/omarchy-base.packages` too (this file isn't consulted again after
install, so this step is just keeping the two checkouts in sync — no
rebuild needed).

---

## Task 2: Add the Niri session entry AND a real SDDM session picker

**Discovered while starting Task 3 (see ledger):** the Omarchy SDDM theme
(`default/sddm/omarchy/Main.qml`) has no session-picker UI at all. Login
always calls `sddm.login(user, password, root.sessionIndex)` where
`sessionIndex` is computed once as "the first session whose display name
contains `uwsm`, else the last-used index" — there is no way for a person
to override that choice today. Adding a Niri session entry alone would not
make it selectable: whichever `uwsm`-named entry enumerates first would
silently become the sole reachable session. This task now includes giving
the theme an actual (minimal, keyboard-only) picker alongside the entry
itself.

**Files:**
- Create (host, then pulled into VM):
  `~/Projects/omarchy-niri-fork/default/wayland-sessions/omarchy-niri.desktop`
- Create (VM only, not tracked):
  `/usr/local/share/wayland-sessions/omarchy-niri.desktop`
- Modify (host, then pulled into VM):
  `~/Projects/omarchy-niri-fork/default/sddm/omarchy/Main.qml`
- Modify (VM only, not tracked — same fixed-system-path limitation as the
  session entry): `/usr/share/sddm/themes/omarchy/Main.qml`

**Step 1 already done (recorded here, not re-run):** confirmed in the VM
that `niri` ships its own `/usr/share/wayland-sessions/niri.desktop`
(`Exec=niri-session`, `DesktopNames=niri`) and that `uwsm` ships dedicated
plugins for it (`/usr/share/uwsm/plugins/niri.sh`,
`/usr/share/uwsm/plugins/niri_session.sh`). So the uwsm-wrapped equivalent
of the existing `Exec=uwsm start -g -1 -e -D Hyprland hyprland.desktop`
line is `Exec=uwsm start -g -1 -e -D niri niri.desktop` — same pattern,
referencing niri's own already-installed Desktop Entry ID.

- [ ] **Step 2: Write the session entry on the host**

Create `~/Projects/omarchy-niri-fork/default/wayland-sessions/omarchy-niri.desktop`:
```ini
[Desktop Entry]
Name=Omarchy (Niri uwsm)
Comment=Omarchy Niri session managed by uwsm
Exec=uwsm start -g -1 -e -D niri niri.desktop
TryExec=uwsm
Type=Application
```

- [ ] **Step 3: Add a minimal keyboard session picker to the SDDM theme**

`default/sddm/omarchy/Main.qml` currently computes `sessionIndex` once as a
read-only property (first session whose name contains `"uwsm"`, else
`sessionModel.lastIndex`) with no way to change it before pressing Enter.
Change it to a real, cyclable selection:

Replace:
```qml
  property string currentUser: userModel.lastUser
  property bool loginFailed: false
  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }
```
with:
```qml
  property string currentUser: userModel.lastUser
  property bool loginFailed: false
  property int sessionIndex: -1

  function defaultSessionIndex() {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  function sessionName(i) {
    return (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
  }

  function cycleSession(delta) {
    var count = sessionModel.rowCount()
    if (count <= 0) return
    root.sessionIndex = (root.sessionIndex + delta + count) % count
  }
```

Add a visible label showing the current selection, as a new `Text` item
inside the existing `Column` (after the `Row` containing the lock icon and
password entry, so it renders centered beneath them):
```qml
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "‹ " + root.sessionName(root.sessionIndex) + " ›"
      color: "#a9b1d6"
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 14
    }
```

Extend the password `TextInput`'s existing `Keys.onPressed` handler (it
currently only handles Return/Enter) to also cycle on Left/Right:
```qml
          Keys.onPressed: {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              sddm.login(root.currentUser, password.text, root.sessionIndex)
              event.accepted = true
            } else if (event.key === Qt.Key_Left) {
              root.cycleSession(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Right) {
              root.cycleSession(1)
              event.accepted = true
            }
          }
```

And initialize `sessionIndex` once the model is ready, in the existing
`Component.onCompleted` at the bottom of the file:
```qml
  Component.onCompleted: {
    root.sessionIndex = root.defaultSessionIndex()
    password.forceActiveFocus()
  }
```

This is deliberately minimal: keyboard-only (Left/Right arrows), no mouse
click-to-select, no fancy styling — enough for two sessions to both be
genuinely reachable. Mouse support or a fancier design is not needed for
this plan's goal and would be scope creep here.

- [ ] **Step 4: Commit and push**

```bash
cd ~/Projects/omarchy-niri-fork
git add default/wayland-sessions/omarchy-niri.desktop default/sddm/omarchy/Main.qml
git commit -m "Add a Niri session entry and a keyboard session picker to the SDDM theme"
git push
```

- [ ] **Step 5: Pull into the VM and hand-install both files**

In the VM:
```bash
cd ~/omarchy-niri-fork && git pull
sudo install -Dm644 default/wayland-sessions/omarchy-niri.desktop \
  /usr/local/share/wayland-sessions/omarchy-niri.desktop
omarchy-refresh-sddm
```
Expected: no errors. The `.desktop` install is hand-done per the "Deferred:
proper packaging" note above — `/usr/local/share/wayland-sessions/` is a
fixed system path `dev link` doesn't cover. `Main.qml` is different: the
repo already ships `omarchy-refresh-sddm` (`bin/omarchy-refresh-sddm`) for
exactly this — it `rm -rf`s and re-`cp -r`s the whole
`default/sddm/omarchy/` tree from `$OMARCHY_PATH`, so use it instead of a
manual `sudo install` (final review caught that the hand-rolled version was
used originally, and a missed step in it cost a debugging round-trip that
this command wouldn't have had).

- [ ] **Step 6: Restart SDDM to load the new theme**

```bash
sudo systemctl restart sddm
```
Expected: this immediately ends the current graphical session (logs you
out) and returns to a fresh SDDM greeter — that's fine, Task 3 logs back in
next anyway.

---

## Task 3: Log in to the bare Niri session

**Files:** None.

- [ ] **Step 1: Check the session picker at the SDDM greeter**

You should already be back at the SDDM login screen after Task 2 Step 6's
`sddm restart`. Click into the password field and press the Left/Right
arrow keys — confirm the small `‹ … ›` label beneath the password box
cycles between "Omarchy (Hyprland uwsm)" and "Omarchy (Niri uwsm)".

- [ ] **Step 2: Log in to the Niri session**

Cycle to "Omarchy (Niri uwsm)" and press Enter to log in.
Expected: a bare Niri compositor session — no Omarchy bar, no launcher, no
theming (none of that exists for Niri yet; this is spec Phase 3, "no shell
integration yet"). You should land on an empty desktop with whatever
terminal-launch keybind niri's auto-generated default config provides (niri
creates `~/.config/niri/config.kdl` from its own built-in default on first
run if the file doesn't exist — we're deliberately not shipping one yet).

- [ ] **Step 3: Confirm a terminal opens**

Check niri's default config for its terminal keybind (likely `Mod+T`  or
similar spawning `alacritty`/whatever niri defaults to — confirm by reading
the auto-generated `~/.config/niri/config.kdl` after Step 2, since niri's
shipped default may not match Omarchy's usual terminal). Open a terminal
and confirm you get a working shell.

- [ ] **Step 4: Confirm networking still works**

In the terminal: `ping -c 1 archlinux.org`
Expected: successful reply.

- [ ] **Step 5: Log out and confirm Hyprland still works unchanged**

Log out of the Niri session, log back in to "Omarchy (Hyprland uwsm)",
confirm the Quickshell bar/launcher are unaffected by anything in this
plan (per the spec's Testing Approach: every phase re-confirms Hyprland
alongside the new Niri behavior).

---

## Task 4: Snapshot the bare-Niri-session baseline

**Files:** None (VM snapshot).

- [ ] **Step 1: Shut down the VM**

In the VM console: `sudo shutdown now`
Wait for `virsh --connect qemu:///system list --all` to show `shut off`.

- [ ] **Step 2: Snapshot it**

```bash
virsh --connect qemu:///system snapshot-create-as omarchy-niri omarchy-bare-niri-session "niri package + manually-installed session entry, both sessions verified working"
```
Expected: `virsh --connect qemu:///system snapshot-list omarchy-niri` now
shows three snapshots. This is the revert point for the next plan
(`NiriService`), which starts touching `shell/`.

---

## What comes after this plan

Spec Phase 4: `NiriService`, sourced from `$NIRI_SOCKET`'s `EventStream`
mode, exposing the same workspaces/windows/focus/outputs shape the shell
already consumes from `HyprlandService`-equivalent code. Note from this
plan's exploration: there is no single `HyprlandService.qml` file today —
Hyprland IPC calls (`Quickshell.Hyprland`, `hyprctl`) are used directly
across several files (`shell/plugins/bar/Bar.qml`,
`shell/plugins/bar/widgets/Workspaces.qml`,
`shell/plugins/services/idle/Service.qml`,
`shell/plugins/notifications/Service.qml`,
`shell/plugins/lock/Service.qml`, and a few `Ui/` components). The next
plan needs to read each of these to decide the actual shape of a
compositor-abstraction seam (a real service singleton vs. a per-file
branch), rather than assuming a service that doesn't exist yet — the spec's
own Architecture §3 already flags this as prior-art-informed, not
confirmed against this codebase.

Also worth an early spike (spec's "Known open risk"):
`shell/plugins/services/idle/Service.qml` uses Quickshell's `IdleMonitor`
(built on the standard `ext-idle-notify-v1` protocol, which Niri supports —
good news, idle timeout detection itself should "just work") but *also*
listens for raw Hyprland window-open/close events
(`Connections { target: Hyprland; onRawEvent }`) purely to track whether a
screensaver window is currently mapped, so it knows whether dismissing it
counts as "activity." That one piece needs a Niri equivalent (e.g. via
`NiriService`'s window list) before idle/lock parity is real — this is the
concrete shape of the "open risk," not just a vague unknown.
