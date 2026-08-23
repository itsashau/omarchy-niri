# Omarchy Niri Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a VM running vanilla Omarchy 4.0 installed from its
official ISO, linked to a personal fork via `omarchy dev link`, as a
working Hyprland baseline — the foundation everything else (NiriService,
theming, full parity) builds on.

**Architecture:** QEMU/KVM VM on the host (Arch Linux, so native libvirt
tooling applies), installed directly from Omarchy 4.0's own bootable ISO
(it is a standalone distro installer as of 4.0, not a script run on top of
an existing Arch install). A personal GitHub fork of `basecamp/omarchy`,
pinned to the `v4.0.0` tag, is cloned both on the host (source of truth)
and inside the VM, then linked into the running system with
`omarchy dev link` so the VM's Omarchy resolves its code from that
checkout. Niri support itself is out of scope for this plan — see "What
comes after this plan."

**Tech Stack:** QEMU/KVM, libvirt, virt-install/virsh, Omarchy 4.0's
official ISO installer, git/GitHub.

**Spec:** `docs/superpowers/specs/2026-08-23-omarchy-niri-design.md`

## Global Constraints

- Everything happens in a VM. Do not touch real hardware (spec Non-Goals).
- The fork tracks the `v4.0.0` tag, not `master` (old 3.x line) or
  `quattro` (rolling dev branch, self-reports `4.0.0.alpha`) (spec
  Architecture §1).
- Keep an `upstream` remote on `basecamp/omarchy` so future merges stay
  possible — the discipline Okimarchy skipped (spec Architecture §1).
- Development against the fork happens via `omarchy dev link`, not a
  custom ISO build. It only covers `$OMARCHY_PATH`-resolved trees
  (`bin/`, `default/`, `shell/`, `themes/`, `applications/`, `config/`) —
  anything at a fixed system path (session `.desktop` files, systemd
  units, `/etc/`) is NOT covered by it (spec Architecture §1).
- Built for personal use first — no distro/hardware-portability work, no
  installer polish for other users (spec Goals).

---

## Task 1: Verify virtualization support and install the KVM/libvirt stack — DONE

Completed: AMD-V confirmed, `qemu-full`/`virt-manager`/`libvirt`/`dnsmasq`/
`virt-viewer`/`edk2-ovmf` installed, `libvirtd` active, user in `libvirt`
group, `qemu:///system`'s `default` NAT network active. Note for every
later step: this host defaults to `qemu:///session` — always pass
`--connect qemu:///system` explicitly on `virsh`/`virt-install` commands.

---

## Task 2: Download the Omarchy 4.0 ISO

**Files:**
- Create: `~/vm-images/omarchy-4.0.0.iso`

- [ ] **Step 1: Download the ISO**

Run:
```bash
mkdir -p ~/vm-images && cd ~/vm-images
curl -fLO https://iso.omarchy.org/omarchy-4.0.0.iso
```
Expected: download completes (~6.3GB). Note: unlike the Arch ISO, Omarchy
does not publish a checksum file at a predictable path — we're relying on
HTTPS transport integrity only, not a published hash.

- [ ] **Step 2: (optional) reclaim space from the earlier Arch ISO**

The `archlinux-x86_64.iso` downloaded earlier is no longer needed (Omarchy
4.0 doesn't install on top of a separate Arch install). If you want the
space back: `rm -f ~/vm-images/archlinux-x86_64.iso`

---

## Task 3: Replace the Arch-only VM with a fresh one for the real Omarchy install

The VM built in the previous version of this plan only has bare Arch
installed, which Omarchy 4.0 doesn't install onto — it needs to own the
disk from its own ISO. We tear down that VM and its snapshots and build a
fresh one against the Omarchy ISO instead, with more headroom (host has
60GB RAM / 32 cores / 1.6TB free, so there's no reason to stay tight).

**Files:**
- Delete: `/var/lib/libvirt/images/omarchy-niri.qcow2` (old Arch disk)
- Create: `/var/lib/libvirt/images/omarchy-niri.qcow2` (new, fresh disk)

- [ ] **Step 1: Confirm the VM is shut off**

Run: `virsh --connect qemu:///system list --all`
Expected: `omarchy-niri` shows `shut off`. If it's running, shut it down
first (`virsh --connect qemu:///system shutdown omarchy-niri`).

- [ ] **Step 2: Undefine the VM and remove its storage and snapshots**

Run:
```bash
virsh --connect qemu:///system undefine omarchy-niri --remove-all-storage --snapshots-metadata
```
Expected: confirmation that the domain and its storage were removed;
`virsh --connect qemu:///system list --all` no longer shows `omarchy-niri`.

- [ ] **Step 3: Create the new VM against the Omarchy ISO**

Run:
```bash
virt-install \
  --connect qemu:///system \
  --name omarchy-niri \
  --memory 12288 \
  --vcpus 6 \
  --disk path=/var/lib/libvirt/images/omarchy-niri.qcow2,size=80,format=qcow2 \
  --cdrom /var/lib/libvirt/images/omarchy-4.0.0.iso \
  --os-variant archlinux \
  --boot uefi \
  --graphics spice \
  --video qxl \
  --network network=default \
  --noautoconsole
```
(The ISO also needs to be under `/var/lib/libvirt/images/` for the
`libvirt-qemu` system user to read it — copy it there with the same
`chown root:libvirt-qemu` / `chmod 640` treatment we used for the Arch ISO
if you downloaded it elsewhere.)
Expected: command exits without error.

- [ ] **Step 4: Confirm it's running**

Run: `virsh --connect qemu:///system list --all`
Expected: `omarchy-niri` shows `running`.

---

## Task 4: Install Omarchy 4.0 from the official ISO

This all happens in the VM console — open it with:
```bash
virt-viewer --connect qemu:///system omarchy-niri
```

**Files:** None (happens entirely inside the VM's installer).

- [ ] **Step 1: Work through the installer wizard**

Selections:
- Keyboard layout: your normal layout
- Hostname, username, password: your choice (VM-only, low stakes)
- Disk: the single virtual disk, full-disk install
- **Encryption**: the installer encrypts by default. For this throwaway
  dev VM, skip it for convenience (no LUKS passphrase on every boot) — the
  Omarchy manual explicitly documents hitting `Ctrl+C` at the disk
  formatting confirmation to switch to an unencrypted install. Do this
  unless you'd rather practice with encryption too.

Confirm and let the installer run (typically under 5 minutes).

- [ ] **Step 2: Reboot into the installed system**

The installer reboots on its own. Since we never attached a second
cdrom and the disk is first in boot order, it should boot straight into
the new install rather than back into the ISO.
Expected: a login manager (or console login) for the system you just
created.

- [ ] **Step 3: Log in and confirm the Hyprland/Omarchy desktop loads**

Expected: Quickshell bar visible, `Super+Space` opens the launcher/menu.

- [ ] **Step 4: Confirm networking**

In the VM console: `ping -c 1 archlinux.org`
Expected: successful reply (NetworkManager handles DHCP automatically on
an Omarchy install, same as the plain Arch install did).

---

## Task 5: Snapshot the vanilla (pre-dev-link) baseline

**Files:** None (VM snapshot).

- [ ] **Step 1: Shut down the VM**

In the VM console: `sudo shutdown now`
Wait for `virsh --connect qemu:///system list --all` to show `shut off`.

- [ ] **Step 2: Snapshot it**

Run:
```bash
virsh --connect qemu:///system snapshot-create-as omarchy-niri omarchy-vanilla-baseline "Vanilla Omarchy 4.0 from official ISO, unmodified"
```
Expected: `virsh --connect qemu:///system snapshot-list omarchy-niri` shows
`omarchy-vanilla-baseline`. This is your revert point if the dev-link step
in Task 7 goes wrong: `virsh --connect qemu:///system snapshot-revert omarchy-niri omarchy-vanilla-baseline`

---

## Task 6: Set up the fork on the host

The GitHub fork itself (`itsashau/omarchy-niri`) is already done. This
task clones it, wires up the `upstream` remote, pins it to a real branch
based on the `v4.0.0` tag, and brings the project docs into it as the
project of record.

**Files:**
- Create: `~/Projects/omarchy-niri-fork/` (clone of the fork — named
  distinctly from the existing `~/Projects/omarchy-niri` scratch/docs repo
  to avoid confusion between the two)
- Create: `~/Projects/omarchy-niri-fork/docs/superpowers/specs/2026-08-23-omarchy-niri-design.md`
- Create: `~/Projects/omarchy-niri-fork/docs/superpowers/plans/2026-08-23-omarchy-niri-bootstrap.md`

- [ ] **Step 1: Clone the fork to the host**

Run:
```bash
git clone https://github.com/itsashau/omarchy-niri.git ~/Projects/omarchy-niri-fork
cd ~/Projects/omarchy-niri-fork
```
Expected: clone succeeds.

- [ ] **Step 2: Add the upstream remote**

Run:
```bash
git remote add upstream https://github.com/basecamp/omarchy.git
git fetch upstream --tags
git remote -v
```
Expected: `origin` points at your fork, `upstream` at `basecamp/omarchy`,
tags fetched successfully.

- [ ] **Step 3: Create a working branch from the v4.0.0 tag**

Run:
```bash
git checkout -b niri-support v4.0.0
cat version
```
Expected: `version` file prints `4.0.0.alpha` (this is Omarchy's own
internal version string for this tag, not a sign the tag itself is
unstable — see spec Architecture §1). You're now on a real branch
(`niri-support`), not a detached HEAD.

- [ ] **Step 4: Bring the spec and this plan into the fork**

Run:
```bash
mkdir -p docs/superpowers/specs docs/superpowers/plans
cp ~/Projects/omarchy-niri/docs/superpowers/specs/2026-08-23-omarchy-niri-design.md docs/superpowers/specs/
cp ~/Projects/omarchy-niri/docs/superpowers/plans/2026-08-23-omarchy-niri-bootstrap.md docs/superpowers/plans/
git add docs/superpowers
git commit -m "Add Niri support spec and bootstrap plan"
```
Expected: commit succeeds.

- [ ] **Step 5: Push the branch**

Run: `git push -u origin niri-support`
Expected: push succeeds; `niri-support` now exists on
`github.com/itsashau/omarchy-niri`.

---

## Task 7: Clone the fork inside the VM and activate `omarchy dev link`

`omarchy dev link` operates on whichever machine you run it on — it writes
that machine's own `/etc/omarchy.conf`. So the checkout it points at has
to live inside the VM, not just on the host. For now we keep two clones
(host = where you'll actually edit code, VM = what's linked); `git pull`
inside the VM after pushing from the host keeps them in sync. A shared
filesystem between host and VM is a reasonable future convenience, but
isn't needed yet and would be premature to set up before any real editing
has happened.

**Files:** None on the host; inside the VM: creates `~/omarchy-niri-fork/`
and `/etc/omarchy.conf`.

- [ ] **Step 1: Boot the VM back up**

Run: `virsh --connect qemu:///system start omarchy-niri`, then
`virt-viewer --connect qemu:///system omarchy-niri`. Log in.

- [ ] **Step 2: Clone the fork inside the VM**

In the VM console, run:
```bash
git clone https://github.com/itsashau/omarchy-niri.git ~/omarchy-niri-fork
cd ~/omarchy-niri-fork
git checkout niri-support
```
Expected: clone and checkout succeed; this matches the branch created on
the host in Task 6.

- [ ] **Step 3: Link Omarchy at this checkout**

In the VM console, run (as your normal user, not root/sudo):
```bash
omarchy dev link ~/omarchy-niri-fork
```
Expected output: `Pointed Omarchy at /home/<you>/omarchy-niri-fork` and
`sudo now resolves omarchy-* from ~/omarchy-niri-fork/bin`. When it asks
"Reboot now to activate?", confirm yes.

- [ ] **Step 4: Verify the link is active after reboot**

After the VM reboots and you log back in, run:
```bash
omarchy-dev-status
```
Expected: output confirms `OMARCHY_PATH` is set to
`~/omarchy-niri-fork` (or equivalent confirmation that Omarchy is running
from the checkout rather than the packaged install).

- [ ] **Step 5: Confirm the Hyprland session still works end-to-end**

Log in to the Hyprland session, confirm the Quickshell bar and launcher
still work, and switch a theme via the Omarchy menu to confirm the
theming pipeline still works when running from the linked checkout.

---

## Task 8: Snapshot the dev-linked baseline

**Files:** None (VM snapshot).

- [ ] **Step 1: Shut down the VM**

In the VM console: `sudo shutdown now`
Wait for `virsh --connect qemu:///system list --all` to show `shut off`.

- [ ] **Step 2: Create the baseline snapshot**

Run:
```bash
virsh --connect qemu:///system snapshot-create-as omarchy-niri omarchy-devlinked-baseline "Omarchy 4.0 dev-linked to niri-support branch, Hyprland verified working"
```
Expected: `virsh --connect qemu:///system snapshot-list omarchy-niri` now
shows both `omarchy-vanilla-baseline` and `omarchy-devlinked-baseline`.
This second snapshot is your revert point for every experiment from here
on — if a later Niri change breaks the Hyprland session, revert with:
`virsh --connect qemu:///system snapshot-revert omarchy-niri omarchy-devlinked-baseline`

---

## What comes after this plan

This plan deliberately stops here. Adding the Niri package, a minimal
session entry, and (later) `NiriService`/Quickshell integration requires
reading the actual files in the now-cloned fork — package lists, session
file locations, and the `HyprlandService` implementation — to write exact,
correct file paths and code rather than guessing them. It also needs to
work around `dev link`'s fixed-system-path limitation (spec Architecture
§1): a Niri session `.desktop` entry under
`/usr/share/wayland-sessions/` isn't covered by `dev link` and will need
`omarchy-dev-pkg-test` or an equivalent packaging step.

Once Task 8 is done, the next step is a short exploration pass over
`~/omarchy-niri-fork` (find where Hyprland is packaged, where session
`.desktop` files live, how `HyprlandService` is structured, and how
`omarchy-dev-pkg-test` works) to write **Plan 2: Bare Niri Session**,
covering spec Phase 3 with real paths. Phase 4 (`NiriService`) follows as
its own plan after that.
