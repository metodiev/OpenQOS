# Roadmap

Milestones are ordered so that each one produces something you can actually check
before the next begins. Nothing here is time-boxed — correctness first.

**Status legend:** ✅ done · 🔄 in progress · ⬜ not started

| # | Milestone | Status | Produces |
| --- | --- | --- | --- |
| 1 | Inspect development environment and plan the setup | ✅ | [`docs/development-environment.md`](development-environment.md) |
| 2 | Establish and verify the Fedora aarch64 build VM | ✅ | [Lima definition](../tools/lima/openqos-dev.yaml); verified Fedora 44 aarch64 guest |
| 3 | Initialise repository, documentation and Git workflow | 🔄 | Repository skeleton and this documentation |
| 4 | Build the smallest practical Fedora-based test image | ✅ | `OpenQOS.aarch64-44.qcow2` with a verified checksum manifest |
| 5 | Boot and verify that image in a VM | ✅ | Captured boot evidence, and a verified login into a running image |
| 6 | Add KDE Plasma and configure the initial desktop | 🔄 | A bootable KDE live image |
| 7 | Introduce OpenQOS branding, defaults and packages | 🔄 | `openqos-release` and `openqos-branding`; images and media carry the OpenQOS identity |
| 8 | Develop the installer and installation media | ⬜ | Installable media with a customised Anaconda experience |
| 9 | Establish the x86_64 build and test pipeline | ⬜ | x86_64 images built from shared sources |
| 10 | Automated checks, checksums, release docs, reproducibility | ⬜ | A releasable, verifiable artifact set |

## Milestone 1 — Development environment ✅

**Complete.** Verified on the host, not assumed:

* Apple M5, `arm64`, macOS 27.0.1, 16 GiB RAM, 10 cores, hardware virtualisation
  available, ~307 GiB free disk.
* `limactl` 2.1.1 present; UTM, QEMU, Podman and Tart absent and not required.
* Repository state: Git repository on `main`, remote `origin`
  (`github.com/metodiev/OpenQOS`), one commit, `LICENSE` (GPL-3.0 text) and an
  18-byte placeholder `README.md`.
* `tools/lima/openqos-dev.yaml` validated with `limactl validate` → `OK`.

Deliverable: the setup plan, with exact commands and expected output, in
[`docs/development-environment.md`](development-environment.md).

## Milestone 2 — Fedora aarch64 build VM ✅

**Complete.** The VM was created and started on 2026-10-12 and every exit criterion
was observed inside the guest. Full results are in the
[verification log](development-environment.md#11-verification-log).

- [x] `limactl start --name=openqos-dev tools/lima/openqos-dev.yaml` completed.
- [x] `uname -m` reports `aarch64`.
- [x] `/etc/fedora-release` reports Fedora 44.
- [x] `kiwi-ng`, `livemedia-creator`, `mkksiso`, `ksvalidator` and `rpmbuild` all
      resolve under `/usr/bin`.
- [x] `rpm -q` confirms `kiwi-systemdeps-iso-media` and `dracut-kiwi-live`.

Notable observed values: `kiwi-ng` 11.1.1 and `lorax` 44.7 — both from Fedora
updates, so newer than the Fedora 44 GA versions quoted in the research this plan
was based on. The checkout mounts read-write via `virtiofs`, so builds run against
the macOS working tree directly.

## Milestone 3 — Repository and Git workflow 🔄

**In progress.** Created: the directory skeleton, `README.md`, `CONTRIBUTING.md`,
`docs/{architecture,development-environment,licensing,roadmap}.md`, `.gitignore`,
`.editorconfig`, and `tools/lima/openqos-dev.yaml`.

Still to do:

- [x] Establish the commit convention documented in `CONTRIBUTING.md`.
- [ ] Configure a Git identity for this repository.
- [ ] Decide the licensing questions in [licensing.md §7](licensing.md#7-decisions-requested).
- [ ] Add `LICENSES/` and SPDX headers, then a REUSE lint in CI.
- [ ] Add a CI job that validates the Lima YAML and any shell scripts.
- [ ] Commit the initial structure.

## Milestone 4 — Smallest practical test image ✅

**Complete.** Two images build reproducibly and their checksums verify independently.

Delivered:

* [`kiwi/OpenQOS.kiwi`](../kiwi/OpenQOS.kiwi) — our root description, including
  Fedora's repository, base and boot definitions from a pinned upstream checkout.
* [`kiwi/openqos/base.xml`](../kiwi/openqos/base.xml) — `OpenQOS-Base`: the shared
  base profile, aarch64 `oem`/`qcow2` image type, security baseline and
  development account. `OpenQOS-Minimal` and the KDE image both inherit it (the
  file was named `minimal.xml` until Milestone 6 restructured it).
* [`kiwi/upstream.lock`](../kiwi/upstream.lock) — Fedora's descriptions pinned at
  commit `dfc49a5a10f6` (branch `f44`).
* [`scripts/fetch-upstream-descriptions.sh`](../scripts/fetch-upstream-descriptions.sh) —
  fetches that revision; refuses to build if the pin is missing.
* [`scripts/build-image.sh`](../scripts/build-image.sh) — the single definition of
  how an image is built, plus checksum manifest generation.

Artefacts, all with a manifest whose SHA-256 was re-checked with `sha256sum -c`:

| Profile | Image | SHA-256 (first 16) |
| --- | --- | --- |
| `OpenQOS-Minimal` | `OpenQOS.aarch64-44.qcow2` | `273b16157db1bbea` |
| `OpenQOS-Minimal-Test` | `OpenQOS.aarch64-44.qcow2` | `60ca593cdc6aec54` |

### Seven problems found by building, not by reading

Each of these was discovered by an actual build or boot, and each is now fixed:

1. `pwd=` is not a valid KIWI attribute on `<user>`; the schema requires
   `password=`. Caught by KIWI's RelaxNG validation.
2. Two consecutive hyphens are illegal inside an XML comment, so a command line
   cannot be pasted into one. Caught by `xmllint`.
3. KIWI refuses a target directory on a `fuse` filesystem — the virtiofs mount of
   this repository — because it cannot represent ownership, ACLs and xattrs. The
   build now runs on guest-local disk and publishes artefacts into the repository.
4. KIWI's locale step fails outright without a language pack; `glibc-langpack-en`
   was needed for `en_US.UTF-8`.
5. `kernel-core` does not provide `virtio_blk` or `virtio_pci` — they are in
   `kernel-modules`. Without them the image could not find its own root filesystem
   on a virtio block disk, which is how QEMU, UTM and Lima attach disks by default.
6. `systemd-networkd` is installed by the base package set but ships no enabled
   configuration, so the first image had no working network. `NetworkManager` fixed
   it, and it is what Plasma expects later anyway.
7. Fedora's `standard` comps group provides **no SELinux policy, no firewall and no
   audit daemon**. The first image came up with `enforce` reading 0 and every file
   labelled from the kernel's default context. Adding `selinux-policy-targeted`,
   `rpm-plugin-selinux`, `firewalld` and `audit` produced a correctly labelled,
   enforcing system with no first-boot relabel cycle — KIWI processes SELinux
   contexts itself once a policy is present.

## Milestone 5 — Boot and verify ✅

**Complete.** The images were booted in an `aarch64` UEFI virtual machine, and the
`OpenQOS-Minimal-Test` image was logged into over SSH to inspect the running system.
Boot evidence is stored in the session workspace, not committed.

Boot, from the serial console of the product image:

```
Fedora Linux 44 (Forty Four)
Kernel 7.2.9-201.fc44.aarch64 on aarch64 (hvc0)

fedora login:
```

Verified inside the running system:

| Check | Observed |
| --- | --- |
| Login | `LOGIN OK as root, aarch64` |
| Kernel | `7.2.9-201.fc44.aarch64` |
| Kernel command line | `root=UUID=80e522c4-… rootflags=subvol=root` |
| Disk layout | `vda1` 100M `vfat` `/boot/efi`; `vda2` 5.9G `btrfs` labelled **`openqos`** |
| btrfs subvolumes | `root`, `boot`, `home`, `var` — exactly as specified |
| Mount options | `rw,relatime,compress=zstd:1,discard=async,space_cache=v2,subvol=/root` |
| systemd | `running`, **zero failed units** |
| SELinux | **`Enforcing`**, `/etc/shadow` → `shadow_t`, `/usr/bin/passwd` → `passwd_exec_t` |
| Network | `enp0s1 UP 192.168.5.15/24` — NetworkManager brought up DHCP unattended |
| Services | `sshd`, `NetworkManager`, `systemd-resolved`, `firewalld`, `auditd` all active |

### Correction to this milestone's original criteria

The original wording asked for `/etc/os-release` to identify OpenQOS. It does not,
and that is expected: identity arrives with the `openqos-release` package at
Milestone 7. The image is currently Fedora-identified, which is correct for a
pipeline-validation artefact. **Nothing built so far is publishable as OpenQOS.**
*(Superseded at Milestone 7: images now carry the OpenQOS identity. The boot
evidence above stands as-is — it describes the Fedora-identified build that was
current when it was captured.)*

### Method, and its limits

Lima cannot complete its normal setup against these images, because it injects an
SSH key through cloud-init and these images have no cloud-init. The instances were
therefore started with provisioning disabled, which boots the VM and leaves it
running after Lima's own readiness check times out. That is sufficient for
verification but is not a reusable test harness.

Turning this into an automated boot test — for CI at Milestone 10 and for inspecting
a graphical session at Milestone 6 — is the next piece of infrastructure work. The
`OpenQOS-Minimal-Test` profile is a first step: it exists so that a built image can
be logged into at all.

## Milestone 6 — KDE Plasma desktop 🔄

**In progress.** The desktop stack and image profile are in place; the SUSE-style
desktop *configuration* (panel, launcher, tray, defaults) has not been started.

Implemented:

* [`kiwi/openqos/base.xml`](../kiwi/openqos/base.xml) — `OpenQOS-Base`, holding the
  shared disk layout, security baseline and development account, so that profiles
  inherit one definition instead of duplicating it. `OpenQOS-Minimal` now requires
  it, which is how the KDE image reuses the same verified aarch64 boot layout.
* [`kiwi/openqos/kde.xml`](../kiwi/openqos/kde.xml) — `OpenQOS-KDE` (the desktop
  stack) and `OpenQOS-KDE-Disk`, derived from Fedora's own
  `components/desktops/kde.xml` so we inherit Fedora KDE SIG's exclusions and
  comps-group resolution rather than re-deriving them.
* [`kiwi/openqos/test.xml`](../kiwi/openqos/test.xml) — `-Test` variants carrying
  SSH, so a built desktop can be inspected in a running system.

Two problems found by building:

1. `<ignore name="mediawriter"/>` against a package that an active upstream profile
   explicitly installs makes the dnf transaction unsatisfiable — it fails with
   "argument 'mediawriter' matches only excluded packages". `<ignore>` only applies
   to packages pulled in transitively. Removing Fedora-branded tools needs a
   replacement package, which is Milestone 7 work.
2. The shared disk size had to be raised well above what the minimal image needs:
   a full KDE Plasma desktop plus LibreOffice is an order of magnitude larger than
   the base system, and the size is a shared sparse ceiling.

Remaining for this milestone:

- [x] Build and boot the KDE image, and confirm the desktop stack is live.
- [x] Ship an original OpenQOS look-and-feel package and desktop defaults.
- [x] `OpenQOS-KDE-Live` — the installable live ISO, in progress (see below).
- [x] The OpenQOS palette, wallpaper, icons and splash (delivered at Milestone 7;
      until then the look-and-feel selected upstream Breeze Dark).
- [x] `contents/previews/` for the global-theme picker, plus `[Wallpaper] Image=`
      (also Milestone 7). The previews are a scaled crop of our wallpaper, not a
      screenshot — see Milestone 7 for why.
- [ ] Visual confirmation of the panel layout in a real session.
- [ ] A dedicated first-boot experience.

### Desktop configuration, verified in a running image

| Check | Command | Observed |
| --- | --- | --- |
| Our defaults win over Fedora's | `kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage` | `org.openqos.desktop` |
| Click behaviour | `kreadconfig6 ... --key SingleClick` | `false` |
| Package is valid and recognised by Plasma | `kpackagetool6 --type Plasma/LookAndFeel --list --global` | `org.openqos.desktop` listed |
| Default browser | `xdg-mime query default text/html` | `org.mozilla.firefox.desktop` |
| Default file manager | `xdg-mime query default inode/directory` | `org.kde.dolphin.desktop` |
| Desktop reached | `systemctl is-active graphical.target` | `active` |
| Login manager | `systemctl is-active plasmalogin` | `active` |
| systemd | `systemctl --failed` | zero failed units |

The first row is the important one: Fedora's `kde-settings` profile sets
`LookAndFeelPackage=org.fedoraproject.fedora.desktop`, and our `/etc/xdg/kdeglobals`
successfully overrides it, which confirms the precedence mechanism rather than
assuming it.

**Not verified:** the rendered pixels. See below.

### Panel layout verified through a real Plasma session

A headless session was started the way the image would start one — `kwin_wayland
--virtual` for the compositor, then `startplasma-wayland` for the session — as a
non-root user, and Plasma wrote `plasma-org.kde.plasma.desktop-appletsrc`. The
panel it built is exactly what
[`org.kde.plasma.desktop-layout.js`](../config/common/usr/share/plasma/look-and-feel/org.openqos.desktop/contents/layouts/org.kde.plasma.desktop-layout.js)
specifies:

| What | Result |
| --- | --- |
| Panel containment | `plugin=org.kde.panel`, `formfactor=2` (horizontal), `location=4` (bottom) |
| Desktop containment | `plugin=org.kde.plasma.folder`, `wallpaperplugin=org.kde.image` |
| Our seven applets | `kickoff`, `pager`, `icontasks`, `marginsseparator`, `systemtray`, `digitalclock`, `showdesktop` — all present |
| Localisation conditional | `kimpanel` **absent**, correctly, because `languageId` is `en_US` and not in the IME list |
| System tray contents | 17 further applets, which are the tray's own defaults, not our layout |

This is stronger evidence than a screenshot for the thing that actually changed:
it proves Plasma *executed our script* and produced the intended widget set, which
is precisely the failure mode a screenshot would hide (a screenshot shows a panel;
it does not show which seven applets are in it).

All eight widget identifiers used by the layout were also checked against the
installed applet plugins (`.so` files under
`/usr/lib64/qt6/plugins/plasma/applets/`, and KPackages under
`/usr/share/plasma/plasmoids/`), so a typo would have been caught either way.

### The live installation ISO

`OpenQOS-KDE-Live` builds and boots. It requires Fedora's `LiveInstall` for the ISO
image type and the live package set, but deliberately *not* Fedora's
`KDE-Desktop-Live`: that profile carries Fedora's `fedora-release-kde` and
`plasma-welcome-fedora`, and it would leave `OpenQOS-KDE` inactive, so our own
configuration would not reach the live image at all.

| Artefact | Size | SHA-256 (first 16) |
| --- | --- | --- |
| `OpenQOS.aarch64-44.iso` | 3.2 GiB | `09dae75743db2f56` |

Verified:

| Check | Observed |
| --- | --- |
| Checksum | `sha256sum -c` → `OK` |
| Medium structure | hybrid MBR + GPT, El Torito with a **UEFI** boot image |
| UEFI boot path | `/EFI/BOOT/BOOTAA64.EFI`, `grubaa64.efi`, `fbaa64.efi`, `grub.cfg` |
| Live filesystem | `/LiveOS/squashfs.img` (an erofs image) |
| **Boots** | kernel and initrd from the ISO, to a login prompt |
| Hostname | `localhost-live` — set by the live bootstrap, unlike a disk install |
| Live session selection | `/etc/sysconfig/livesys` contains `livesys_session="kde"` |
| Autologin | `livesys-kde` writes `[Autologin] User=liveuser` with the Plasma session into `/etc/plasmalogin.conf` |

Deviations accepted for now: the medium inherits `volid="Fedora_Linux"` and
`publisher="FEDORA PROJECT"` from `LiveInstall`'s ISO type. Overriding the medium's
identity means defining our own ISO type *and* our own copy of the live package
list — Milestone 7 work, alongside the rest of the branding.

#### Live media have no usable account, by design

Worth knowing before trying to test one: `livesys-main` runs `passwd -d root` at
boot, deleting whatever password the image carries, and creates `liveuser` without
one. So `OpenQOS-KDE-Live-Test`'s root password is wiped on every boot and **that
profile cannot be logged into over SSH**. That is correct live-media behaviour, not
a defect — but it means verifying live media means reading the serial console. This
was found by trying to log in, failing, and then reading `livesys-main` rather than
assuming the password was wrong.

#### A note on building live media on this machine

Two failures cost real time and both had misleading symptoms. Both are described in
[architecture.md §4.2.1](architecture.md#421-a-constraint-worth-knowing-early):
`mkfs.erofs` buffering through `$TMPDIR` into a 3.9 GiB tmpfs, and the fact that
`$TMPDIR` must also resolve inside the image chroot where KIWI runs `dracut`.

### The screenshot could not be captured

`spectacle` does not complete under KWin's `--virtual` headless backend: it timed
out (`rc=124`) both outside and inside a session D-Bus, and failed with `rc=1` with
an empty log. Missing portals are not the cause — `xdg-desktop-portal`,
`-kde` and `-gtk` are all installed. The capture request appears never to complete,
which is a known limitation of virtual/headless outputs rather than a defect in this
image.

Capturing a real screenshot therefore needs a display-backed session, which means
either a nested compositor that supports screencopy, or booting the image under a
hypervisor that provides a virtual GPU and capturing from the host. Neither is
available on this machine today (Lima's `vz` instances expose no `/dev/dri`).
Worth recording separately: **there is no `/dev/dri` in the vz guest**, so
`graphical.target` being "active" and `plasmalogin` being "active" mean the
services are running, not that anything is being displayed.

### Desktop verified in a running image

| Check | Observed |
| --- | --- |
| Login | `LOGIN OK: root on aarch64` |
| Default target | `graphical.target`, **active** |
| Login manager | `plasma-login-manager-6.7.5` **enabled** and **active** |
| `display-manager.service` | → `plasmalogin.service` (real unit, not dangling) |
| Session | `/usr/share/wayland-sessions/plasma.desktop` present |
| Plasma | `plasmashell` libraries all resolve, `kwin 6.7.5` |
| SELinux | `Enforcing` |
| systemd | `graphical.target` reached, **zero failed units** |

One correction worth recording: my first check concluded there was no display
manager, because I looked for `sddm`. Plasma 6.7 replaced SDDM with a QML login
manager shipped in a package called `plasma-login-manager` that installs
`plasmalogin.service`. The lesson is that KDE branding and unit naming changed
under us; verify against the running system rather than against remembered names.

## Milestone 7 — Branding, defaults and packages 🔄

Everything branded becomes an RPM under [`packages/`](../packages), not a loose file
copied into the image: `openqos-release`, `openqos-branding`,
`openqos-config-desktop`, `openqos-config-<arch>`. Original artwork goes in
[`branding/`](../branding) with provenance notes.

In place so far:

- [`packages/openqos-release/`](../packages/openqos-release) — owns
  `/usr/lib/os-release`, which `/etc/os-release` links to. This is the package that
  makes the running system say what it is.
- [`packages/openqos-branding/`](../packages/openqos-branding) — the visual identity:
  wallpaper package, Plasma colour scheme, Plymouth boot splash, and the hicolor icon
  that `LOGO=openqos-logo` refers to. Sources in [`branding/`](../branding).
- [`scripts/build-packages.sh`](../scripts/build-packages.sh) — rpmbuild from
  `packages/*/`, published to `/srv/openqos/packages` as an rpm-md repository, which
  [`kiwi/openqos/base.xml`](../kiwi/openqos/base.xml) consumes over `file://`. A
  package whose sources are a directory tree ships a `make-source.sh` instead of
  relying on the flat-file copy.
- A split between [`base.xml`](../kiwi/openqos/base.xml) (shared content, no image
  type) and [`disk.xml`](../kiwi/openqos/disk.xml) (the `oem` type), so the live
  profile can share the base content without a second `<type>` element.

### Replacing Fedora's identity is not a package rename

The first attempt obsoleted `fedora-release-identity-basic` and shipped a
replacement. It failed twice, and both failures are worth recording because neither
is discoverable by reading Fedora's packaging.

`fedora-release-common` requires the **virtual name** `fedora-release-identity` at an
exact version, not a package name:

```
$ rpm -q --requires fedora-release-common | grep identity
fedora-release-identity = 44-18
```

That version tracks Fedora's own updates, so it is not ours to choose — which is why
`openqos-release` carries Fedora's version-release (`44-18`) and OpenQOS's own
version lives in the os-release content instead. `scripts/build-packages.sh` reads the
required version from the repositories and refuses to publish a package that does not
provide it, turning a stale pin into an immediate, explained failure instead of a
confusing one three steps later.

The second problem is that **61 packages** provide that virtual name — one per Fedora
flavour — and each declares a `Conflicts` on it so exactly one can ever be installed.
Nothing in a profile names a flavour, so dnf is free to satisfy the requirement with
whichever it likes, and it chose `fedora-release-identity-budgie` for an image with no
desktop at all. Obsoleting one flavour only removes one candidate: the next build
picks a different one, and the conflict reappears under a new name. Every Fedora
repository and ours also share one priority, so repo priority does not decide it
either.

What works is making the whole family ineligible, leaving exactly one provider:

```xml
<ignore name="fedora-release-identity-*"/>
```

and it has to be written **twice**, because KIWI reads `<ignore>` per packages
*section type*, not per profile. The `image`-section ignore does nothing for the
bootstrap transaction, which is where a flavour actually arrives: bootstrap installs
`filesystem`, which pulls `basesystem` → `fedora-release` → `fedora-release-common` →
a flavour, before any image package is considered.

### Identity, verified in the built images

Read from each image's own RPM database and filesystem, with the QCOW2 attached
read-only via `qemu-nbd` or the live EROFS extracted from the ISO — not inferred from
a build log:

| Check | Minimal (qcow2) | KDE disk (qcow2) | KDE live (ISO) |
| --- | --- | --- | --- |
| `rpm -qf /usr/lib/os-release` | `openqos-release-44-18.fc44.noarch` | same | same |
| `rpm -V openqos-release` | clean | — | — |
| Fedora identity flavours | none | none | none |
| `/etc/os-release` | `NAME="OpenQOS Linux"`, `ID=openqos` | — | `NAME="OpenQOS Linux"`, `ID=openqos` |
| Kernel packages | `kernel-core` | `kernel-core` | `kernel-uki-dtbloader`, no `kernel-core` |

`fedora-release-common` and `fedora-release` remain installed and unmodified, which is
the point: the base stays Fedora, only the identity is ours.

`rpm -V` is clean rather than reporting a modified file, because the file is properly
owned by our package. The alternative — overwriting a file owned by an upstream
package — was rejected for exactly that reason.

The live ISO still carries Fedora's volume identity (`Fedora_Linux` / `FEDORA
PROJECT`); giving it ours is on the list below, and `livesys_session="kde"` from our
own `config.sh` is confirmed present in the live root.

Also fixed here, found by the same guard: `build-packages.sh` reused its `RPMS/`
directory between runs, so a stale package from a previous build stayed in the tree
and was republished to the repository — where the next image build would install it.
Output directories are now cleared on every run.

### Boot core is a property of the media, not of OpenQOS

Splitting the base profile from the disk type surfaced a second problem, in the
profile graph rather than in packaging.

Upstream defines two mutually exclusive boot profiles, and on aarch64 they install
*different kernel packages*:

| Profile | aarch64 kernel package |
| --- | --- |
| `BootCore` | `kernel-core` |
| `BootCoreLive` | `kernel-uki-dtbloader`, and deliberately **not** `kernel-core` |

The two declare a `Conflicts` on each other at the same version — they are
alternative kernel packagings, not companions — so a build that activates both
cannot be resolved at all:

```
Problem: package kernel-uki-dtbloader-7.2.9-201.fc44.aarch64 from updates
  conflicts with kernel-core = 7.2.9-201.fc44 provided by kernel-core-7.2.9-201...
```

`OpenQOS-KDE-Live` activated both. It requires `LiveInstall`, which requires
`BootCoreLive`, and it also required `OpenQOS-Base`, which required `BootCore` — a
requirement that is correct for disk images and wrong for live media, where upstream
has already chosen the live boot path.

The fix is to move the requirement to where the media type is known: `BootCore` is
now required by `OpenQOS-Disk`, and `OpenQOS-Base` requires no boot profile at all.
Live profiles continue to get `BootCoreLive` through `LiveInstall`. The disk images
are unaffected — they still require `OpenQOS-Disk`, and so still get `kernel-core`.

Worth noting for Milestone 9: this is aarch64-specific. On x86_64 both profiles use
`kernel-core`, so the same mistake would not have shown up there.

### Original artwork

The mark is an open ring with a tail — a "Q" drawn as geometry rather than as a
letterform, so it survives being rendered at 16px and needs no font:

| File | For |
| --- | --- |
| `logo/openqos-mark.svg`, `logo/openqos-mark-inverse.svg` | The mark, on light and dark backgrounds |
| `logo/openqos-logo.svg`, `logo/openqos-logo-inverse.svg` | Horizontal lockup, both variants |
| `wallpapers/openqos-default.svg` | The default wallpaper, 3840×2160 |
| `themes/OpenQOS.colors` | Plasma colour scheme |
| `plymouth/openqos/openqos.plymouth` | Boot splash theme |

Nothing is derived from Fedora's or KDE's artwork. [`branding/PROVENANCE.md`](../branding/PROVENANCE.md)
records authorship, licence and the honest limitations; the assets are
CC-BY-SA-4.0 while the generator script is GPL-3.0-or-later, because the two are used
differently.

The ring is an explicit arc path, not a circle with `stroke-dasharray`. The first
attempt used a dashed circle and put the gap in the wrong quadrant: the dash pattern
starts at the circle's own start point and travels in a direction that depends on the
assumption being made about the y axis, which in SVG points down. Written as an arc,
the gap is simply the sector the path does not cover. Both the mark and the wallpaper
now use the same construction.

The raster assets are generated, not hand-exported:

```sh
branding/tools/render-assets.py            # rewrite the outputs
branding/tools/render-assets.py --check    # verify they still match
```

It uses GdkPixbuf with librsvg's GdkPixbuf loader, so no new build dependency is
introduced — the development VM has no rsvg-convert, no ImageMagick, no Pillow, and
the cairo GObject binding exposes no surface type (that needs pycairo). Outputs are
deterministic, and the wallpaper variant for portrait screens is rendered *cover*
(scaled then centre-cropped) rather than stretched, which is what stops a 16:9 design
from being squashed into a 9:16 frame.

### The medium says who it is too

The `openqos-release` package fixed the *installed* identity. The live ISO carried a
second one, inherited from Fedora's `LiveInstall` preferences:

```
Volume Id    : Fedora_Linux          →  OpenQOS_KDE_Live_Test
Publisher Id : FEDORA PROJECT        →  OPENQOS
Application  : Fedora_Linux          →  OpenQOS Linux
```

Those cannot be edited in the description. Preferences attach to every profile in the
active set including required ones, so a second `<type image="iso">` for the same
build is a hard error — which is exactly why `OpenQOS-KDE-Live` inherits them. KIWI
supports overriding type attributes from the command line instead, and that is how
Fedora's own live-ISO label generator sets its labels, so
[`scripts/build-image.sh`](../scripts/build-image.sh) passes them there.

**The label is not cosmetic.** KIWI composes the kernel command line as
`root=live:CDLABEL=<volid>`, so the volume label is how the live system finds its own
root filesystem. Both are read from the same attribute, so they cannot drift within a
build — but a mismatch produces media that boots to a dracut prompt instead of a
desktop, which is why the label and the command line are checked together rather than
assumed:

| Check | Observed |
| --- | --- |
| ISO volume id | `OpenQOS_KDE_Live_Test` |
| ISO publisher | `OPENQOS` |
| Kernel command line | `root=live:CDLABEL=OpenQOS_KDE_Live_Test` — matches the volume id |
| Manifest | `medium_label=OpenQOS_KDE_Live_Test` |

The label is derived from the profile name with `-` replaced by `_`, so two different
media built here can never carry the same label: `CDLABEL` matching cannot tell two
identically-labelled discs apart. A label longer than 32 characters fails the build
rather than being silently truncated.

### Branding as a package, verified in the images

`openqos-branding` installs the wallpaper package, the colour scheme, the Plymouth
theme and the hicolor icon named by `LOGO=openqos-logo` in os-release.

It does not render anything at build time: the raster assets are committed, produced
by the generator. Rendering inside rpmbuild would make the package's contents depend
on the build machine's librsvg version, so two machines would produce two different
"identical" packages.

Read from the built images, with the QCOW2 attached read-only, and read through KDE's
and Plymouth's own parsers rather than by eye:

| Check | Observed |
| --- | --- |
| Package installed | `openqos-branding 0.1-1.fc44` on the KDE disk image and the live ISO |
| Wallpaper package | `/usr/share/wallpapers/OpenQOS/{metadata.json,contents/images/3840x2160.png,1080x1920.png}` |
| Colour scheme | `/usr/share/color-schemes/OpenQOS.colors` |
| Boot splash | `/usr/share/plymouth/themes/openqos/{openqos.plymouth,watermark.png}` |
| Splash selected | `/etc/plymouth/plymouthd.conf` → `Theme=openqos` |
| Plymouth knows the theme | `plymouth-set-default-theme --list` includes `openqos` |
| Icon | `/usr/share/icons/hicolor/{scalable,256x256,48x48}/apps/openqos-logo.*`; `LOGO=openqos-logo` in os-release matches |
| Icon directory declared | `hicolor/index.theme` lists `scalable/apps`, `256x256/apps`, `48x48/apps` |
| Look-and-feel selected | `kreadconfig6 --file /etc/xdg/kdeglobals --group KDE --key LookAndFeelPackage` → `org.openqos.desktop` |
| Wallpaper selected | `kreadconfig6 … --group Wallpaper --key Image` → `OpenQOS` |
| Colour scheme selected | `kreadconfig6 … --group General --key ColorScheme` → `OpenQOS` |
| Look-and-feel previews | `contents/previews/{preview.png,fullscreenpreview.jpg}` present |

`Image=OpenQOS` is a wallpaper package *name*, not a path — Plasma looks for
`contents/images/<width>x<height>.<ext>` underneath it, and pointing the key at a file
is the mistake that produces a blank desktop.

The Plymouth theme uses the `two-step` module that Plymouth itself provides and Fedora
ships its themes on, rather than a hand-written `script` theme. Every setting is a
supported key of a compiled-in module, so the worst case for a key that turns out to be
unsupported is a missing element, not a failed splash.

### Not verified, and why

* **The boot splash has never been drawn.** This VM has no DRM device, so Plymouth
  runs its text renderer. What is verified is that Plymouth parses the theme and lists
  it; what is not is what it looks like.
* **No screenshots of the desktop.** Same cause — there is nothing to capture. The
  look-and-feel previews are a scaled crop of our own wallpaper, not a photograph of a
  running session. A placeholder that is honest beats a blank preview, but it is still
  a placeholder.

### Fedora-branded content, checked rather than assumed

The earlier note in this roadmap claimed the image installed `mediawriter`,
`plasma-welcome-fedora` and `fedora-release-kde`. Reading the built image's package
list showed that was wrong about two of the three, and the real situation is:

| Package | Status | Why |
| --- | --- | --- |
| `mediawriter` | **removed** | Named explicitly by upstream's desktop baseline. OpenQOS now owns that file (`openqos/desktop-common.xml`) so the line can be dropped. |
| `fedora-release-kde` | never installed | Requested only by upstream's `teams/*.xml`, which we do not include. |
| `plasma-welcome-fedora` | never installed | Nothing requests it. The `<ignore>` for it sits in upstream's *KDE-Mobile* packages block, which we never activate. |
| `plasma-welcome` | kept | Upstream KDE's own welcome application, not Fedora branding. |
| `fedora-logos` | kept | **Cannot be removed**: `breeze-icon-theme` and much else require it. Its files are Fedora's marks in Anaconda and favicon assets; OpenQOS references none of them. |
| `fedora-repos`, `fedora-gpg-keys`, `fedora-appstream-metadata`, … | kept | Functional Fedora infrastructure, not branding. An OpenQOS system uses Fedora's repositories, and its GPG keys are what verify them. |

Removing `mediawriter` is the only one that needed code, and it needed a deliberate
copy of an upstream file: `<ignore>` cannot do it, because dnf refuses a transaction
that both requests and excludes the same package. The cost of owning the file is that
upstream additions to the desktop baseline no longer reach us automatically, so
[`tests/check-upstream-drift.sh`](../tests/check-upstream-drift.sh) now fails when the
difference is anything other than the documented one.

### `/etc/system-release` is deliberately still Fedora's

`system-release`, `redhat-release` and `fedora-release` are one symlink chain owned by
`fedora-release-common`, and they read `Fedora release 44 (Forty Four)`. That looks
wrong on an OpenQOS system, and it is a decision rather than an oversight:

* **os-release is the identity, and it is ours.** Every modern tool — `hostnamectl`,
  the desktop's about dialogs, `lsb_release`, systemd, Anaconda — reads it. It says
  OpenQOS.
* **Those three files state the base, and it is true.** OpenQOS *is* Fedora 44
  underneath, and third-party software uses those names to decide which Fedora
  conventions apply. Rewriting them would make the system lie about its base to the
  software that depends on knowing it.
* **They belong to a package we keep unmodified.** We chose to leave
  `fedora-release-common` installed and unmodified. Overriding its files from outside
  the package means the content is silently reverted by any `dnf reinstall` or update
  of it, and `rpm -V` then reports a modified file on a package we claim is untouched.

If the decision is reversed, the change is one KIWI `<file>` targeting
`/usr/lib/fedora-release`, which is what all three `/etc` names resolve to — but it
should be reversed deliberately, with the reasoning above in mind.

### The MD5 password hash is fixed, and the fix is enforced

KIWI's `<user pwdformat="plain">` hashes with the C library default, which on current
glibc is MD5. The built images carried a `$1$` hash in `/etc/shadow`. KIWI cannot do
better: `pwdformat` accepts only `plain` and `encrypted`, and `encrypted` means
committing a hash.

So the description sets `password="!" pwdformat="encrypted"` — KIWI passes it through
verbatim and `!` is the standard marker for an account with no usable password. The
attribute cannot be dropped entirely: KIWI's schema makes `password` required on
`<user>`, which is why an earlier attempt to simply omit it failed validation.

Credentials are set in [`kiwi/config.sh`](../kiwi/config.sh) with
`chpasswd --crypt-method YESCRYPT`, the algorithm named rather than left to a default.
Two assertions run there, and a mistake fails the build:

* any `$1$` or `$5$` hash in `/etc/shadow` fails the build;
* a profile whose name does not mark it as development must have every account locked
  or passwordless.

| Check | Before | After |
| --- | --- | --- |
| `/etc/shadow` for root, development profile | `$1$…` (MD5) | `$y$j9T$…` (yescrypt) |
| Weak hashes in the image | one | none |
| Credential on a non-development profile | present | none — enforced |

The boot splash also moved to KIWI's own mechanism: `<bootsplash-theme>openqos</bootsplash-theme>`
in a preferences block, which makes KIWI run `plymouth-set-default-theme` inside the
image. The previous approach shipped our own `/etc/plymouth/plymouthd.conf` as an
overlay, which overwrote a file the plymouth package owns and created it even on
profiles with no Plymouth installed.

### The login screen, and the first boot

Both are KDE machinery that OpenQOS configures rather than replaces, and both had a
Fedora-shaped default to undo.

**The login screen.** Plasma 6.7 replaced SDDM with `plasma-login-manager`
(`plasmalogin.service`), so there is no SDDM theme to write. Its own README names the
two configuration files and who owns which:

| File | Owner | Set here |
| --- | --- | --- |
| `/usr/lib/plasmalogin/defaults.conf` | the distribution | the wallpaper, replacing the same file from Fedora's `kde-settings-plasmalogin`, which pointed the greeter at **Fedora's** wallpaper package |
| `/etc/plasmalogin.conf` | the user | left untouched, so a user who picks their own login wallpaper keeps it |

Two things follow from the greeter being a Plasma application. Its colours, fonts and
icon theme come from `/etc/xdg/kdeglobals`, which OpenQOS already owns — so the
OpenQOS colour scheme themes the login screen too, and there is no separate greeter
theme to write. And the wallpaper value is not a path to an image but a Plasma
wallpaper *plugin* plus its settings, which is why the config nests the way it does:

```ini
[Greeter]
WallpaperPlugin=org.kde.image

[Greeter][Wallpaper][org.kde.image][General]
Image=file:///usr/share/wallpapers/OpenQOS/
```

**The first boot.** KDE's `plasma-setup` wizard is the first-boot experience, and it
is already installed and enabled. Its unit documents its own contract:

```ini
ConditionPathExists=!/etc/plasma-setup-done
ConditionKernelCommandLine=!rd.live.image
Before=display-manager.service
```

so it runs once, before the login manager, on anything that is not live media.

That contract turned out to be load-bearing, not decorative. OpenQOS product images
ship **no usable account at all** — root is locked, and no user exists until someone
creates one — which is a deliberate security decision made earlier in this milestone.
On its own that decision produces an image nobody can log into, so the wizard is what
makes the image usable, and the build now asserts the relationship instead of trusting
it: [`kiwi/config.sh`](../kiwi/config.sh) fails if a profile installs a display manager
and yet has neither an account with a password nor a wizard that will run. The
assertion is what caught the two decisions drifting apart.

The rest of the first boot is inherited and now verified rather than assumed:

| Behaviour | Where it comes from | Observed |
| --- | --- | --- |
| Hostname `openqos` | `DEFAULT_HOSTNAME` in our os-release | The console of a freshly booted image reads `openqos login:` |
| New machine-id | `/etc/machine-id` is left empty | `systemd-machine-id-commit`: "Save Transient machine-id to Disk" |
| SSH host keys | generated per machine | `sshd-keygen@ecdsa/ed25519/rsa` all start on first boot |
| First user is an administrator | `[Accounts] UserGroups=wheel` in our `plasmasetuprc` | installed and verified in the image |

### Seeing it, at last

Every visual claim in this roadmap has been qualified with "not verified, this VM has
no GPU and no `/dev/dri`". That is now solved, and the fix is worth recording because
it unblocks all future UI work: [`tests/screenshot-image.sh`](../tests/screenshot-image.sh)
boots an image under QEMU — which emulates a virtio GPU, so the guest *does* have
`/dev/dri` — and reads its screen through the QEMU monitor's `screendump`. No display on
the host is involved.

Three things had to be learned the hard way, and are in the script's comments so they
are not learned twice:

* QEMU 10 requires each pflash unit to be the full 64 MB the `virt` machine declares
  and refuses Fedora's 3 MB `QEMU_EFI.fd`. The pre-padded `*-pflash.qcow2` images work.
* The serial console cannot be used to detect progress: systemd stops logging there
  once the console moves, and a graphical greeter writes nothing to it at all. Progress
  is judged from the framebuffer.
* Blank, console and graphical are distinguishable by *compressed pixel size*, and file
  size is useless for this — a PPM is `width*height*3` bytes whether it holds a
  wallpaper or one flat colour. A text console compresses to tens of kilobytes, a
  wallpaper to far more, and a blank screen to almost nothing.

### What the first real screenshots show

The first capture was a **freshly written disk image**, and it produced the most useful
finding of the milestone. The screen stayed blank for nineteen minutes — there is no
KVM here, so QEMU emulates — and then showed the first-boot wizard, not a login screen.
Asking the guest directly (switching VT with the QEMU monitor's `sendkey`, logging in,
reading the answers off the framebuffer) explained why:

```
# pgrep -al plasmalogin
951 /usr/libexec/plasmalogin-helper ... --start /usr/bin/startplasma-wayland --user plasma-setup --autologin
1913 /usr/bin/kwin_wayland --wayland-fd 7 --socket wayland-0
```

The login manager is running, and what it is running is the **first-boot wizard**, in
autologin, as the `plasmalogin` session. That is exactly the designed behaviour — the
wizard comes before the greeter on first boot — and it means **a freshly written image
shows the wizard, not a login screen**. Which also means the themed login screen can
only be seen on an image where setup is already done.

The same session verified, at runtime rather than by inspection:

| Check | Observed |
| --- | --- |
| Console identity | `OpenQOS Linux 0.1 (Development)`, hostname `openqos` |
| Login over the console | worked with the development credential — so the yescrypt hash is usable |
| `systemctl is-active plasmalogin` | `active` |
| `systemctl --failed` | `0 loaded units listed` |
| Graphics | `/dev/dri/card0` and `renderD128` present under QEMU |
| First boot | `systemd-machine-id-commit` generating a machine-id, `sshd-keygen@*` creating host keys |

Then, with `/etc/plasma-setup-done` present in a throwaway copy so the wizard steps
aside, the login screen itself was captured. The frames are kept as evidence in the
session workspace, not in this repository — they are build output, and a screenshot of a
throwaway copy is not a project asset. What they show:

* **The colour scheme is applied to the login screen**, as predicted — the clock, date,
  username and password fields, and the sleep/restart/shutdown buttons are all drawn in
  the OpenQOS palette. No separate greeter theme was needed, because the greeter is a
  Plasma application reading `/etc/xdg/kdeglobals`.
* **Our wallpaper does render on the login screen** — one frame shows the OpenQOS
  wallpaper with its rings and tail, which is also proof that
  `Image=file:///usr/share/wallpapers/OpenQOS/` resolves.

**And one thing was misread, now corrected.** An earlier version of this note claimed the
greeter showed our wallpaper in one frame and Plasma's built-in default in the next, with
nothing to explain the change. The explanation was mine, not the greeter's: two capture
runs had been started against the same work directory, and each one wipes and rewrites
it, so the frames I compared came from two different boots with two different
configurations.

What the greeter actually does, seen in a single clean run, is show its **own** background
first and then apply the configured wallpaper a few seconds later once the Plasma
wallpaper plugin has loaded. The framed sequence is:

| Frame | Content | Screen |
| --- | --- | --- |
| 155s | 107 KB | greeter up, its own default background |
| 177s | 236 KB | the same screen with the **OpenQOS wallpaper** applied |

That is also a reminder for anyone using the tool: give each run its own `WORK`
directory, and read a *sequence* of frames rather than a single one, because a screen
that changes is telling you something.

### Which form of the wallpaper setting

Plasma's own schema for the image wallpaper plugin describes its `Image` key as
"wallpaper image path *or* wallpaper name". Fedora's configuration of the login screen
used a file URL pointing at a wallpaper *package directory*, and that form is the
plugin's "pick a random image from this folder" mode — a folder which, in a wallpaper
package, holds only `contents/` and `metadata.json`, with the images one level down.

Both forms rendered our wallpaper at least once, so this is not settled by the
screenshots; it is settled by the documentation and by consistency. OpenQOS shipsthe
wallpaper **name**, `Image=OpenQOS`, because that is what the key's own schema says it
accepts and it is the same form the desktop wallpaper already uses in the look-and-feel
defaults — so the greeter and the desktop resolve the same package the same way instead
of by two different routes.

### Still to do

- [x] Original artwork: logo, wallpaper, colour scheme, boot splash, with provenance
      notes in [`branding/`](../branding).
- [x] `openqos-branding` as a real package, with `contents/previews/` and
      `[Wallpaper] Image=OpenQOS`.
- [x] Our own ISO volume identity: `volid`, `application_id` and `publisher`.
- [x] Remove `mediawriter`; check the rest of the Fedora-branded package list against
      a real image rather than a guess.
- [x] Our own GRUB template, without the `fedora` menu class.
- [x] Fix the MD5 password hash, and enforce it in the build.
- [x] Theme the login screen through Plasma Login's own distribution hook.
- [x] First-boot experience; assert that an image with a desktop is enterable.
- [x] See the login screen, and the first boot, on a running guest.
- [x] Settle which wallpaper the greeter keeps: ours, applied a few seconds after the
      greeter's own background, and stable thereafter.
- [ ] **Capture the desktop.** Not yet done, and the reason is now known rather than
      guessed: the scaffold in `tests/prepare-screenshot-image.sh` created a test
      account whose home directory did not exist, so the greeter refused the login.
      That is fixed — `useradd` inside the chroot reported success without creating
      the home — but the capture has not been re-run since. The panel layout in
      particular has still never been seen.
- [ ] Replace `mediawriter` with an OpenQOS image writer. Removing it was the
      branding fix; having no image writer at all is a product gap, not a decision.
- [ ] Reconsider `/etc/system-release` once the product identity is settled — see the
      note above for why it is still Fedora's, and what reversing it costs.

## Milestone 8 — Installer and installation media ⬜

**In progress.** Anaconda is on the media and now installs a system that
`kickstart/openqos.ks` defines, under OpenQOS's own identity.

What this milestone set out to do was the three things the placeholder listed —
a kickstart, branded installer media, and a verified install-to-disk path — and
the first finding reshaped how the third one works.

### What was already true

Anaconda arrives on the media through upstream's `LiveInstall` profile, whose own
comment is "The point of a live image is to install": `anaconda-core`,
`anaconda-live`, `anaconda-tui` and `anaconda-webui` (Fedora 44's Web UI front
end). It was reachable only from a Fedora-branded desktop icon —
`/etc/xdg/autostart/liveinst-setup.desktop` copies `/usr/share/applications/liveinst.desktop`,
*"Install to Hard Drive"* with Fedora's installer icon, into the live user's
desktop directory. Our own live layout offered no installer at all.

### Findings that shaped the design

| Finding | Evidence | Consequence |
| --- | --- | --- |
| Anaconda removes the kickstart mechanism on live media, by design | `/usr/bin/anaconda:346` calls `pyanaconda.startup_utils.find_kickstart()`; both branches are gated on `not options.liveinst`, so a live install parses the 8-line deprecated `interactive-defaults.ks` instead | The launcher must not pass `--liveinst`, or nothing in this repository decides what an installation becomes |
| A live install copies the running live system and has no post-install hook | `--liveinst` selects `LiveOSPayload`; no `%post` runs | Every choice that matters must be made by the kickstart, not by a post-install script |
| Kickstarts *are* honoured without `--liveinst`, including `liveimg` | `find_kickstart()`'s guards; `liveimg` is a supported kickstart command and `get_local_image_path_from_url()` strips `file://` | OpenQOS names its own payload instead of relying on Anaconda's live default |
| Nothing can start Anaconda from the boot command line on these media | `anaconda-dracut` (dracut module `80anaconda`) is not installed, so `inst.ks=` does nothing at boot | The unattended path is a systemd unit in the live session, ordered before `graphical.target` |
| Anaconda's branding surface for a distribution is `/etc/anaconda/profile.d`, and no profile matched us | Anaconda ships `fedora.conf`, `fedora-kde.conf`, `rhel.conf` and more; detection is by `os-release` values, and on no match it logs "Unable to find any suitable configuration files for the detected os-release values" and uses bare defaults | Our installer was running Fedora's `anaconda.conf` defaults — LVM, no product decisions |
| Fedora's installer stylesheet hook is dead in Fedora 44 | `custom_stylesheet` is defined in `pyanaconda/core/configuration/ui.py` and the string appears nowhere in `/usr/share/cockpit/anaconda-webui` | The profile clears it rather than shipping a stylesheet nobody reads; the installer's branding is the product name it reads from `PRETTY_NAME` |
| Anaconda ignores disks labelled `OEMDRV` as installation targets | `pyanaconda/ui/lib/storage.py:375` | A kickstart stick cannot be wiped by the installation it describes, and the test harness can use that path instead of editing the medium |

### What was built

* `kickstart/openqos.ks` — the installation definition. GPT, a 100 MiB ESP, one
  btrfs volume labelled `openqos` with `root`/`boot`/`home`/`var` subvolumes
  (mirroring `kiwi/openqos/disk.xml`), `selinux --enforcing`, no usable account,
  the same kernel arguments as the disk images, and a `%post --erroronfail` that
  refuses to finish with a system that does not identify as OpenQOS or that nobody
  can log into. Validated with `ksvalidator -v F44`.
* `packages/openqos-installer/` — the launcher, the polkit action that permits it
  (and nothing else), the live-desktop icon setup, and the unattended service.
  Installed on live profiles only.
* `config/common/etc/anaconda/profile.d/openqos.conf` — the installer's product
  profile: btrfs + zstd:1, `\EFI\openqos`, geolocation off, account creation left
  to Plasma Setup.
* `tests/install-test.sh` — installs from the real media, unattended, and then
  examines the result from outside the machine.
* `scripts/build-packages.sh` — build tree moved off the shared repository mount.
  See the defect below.
* Documentation: [architecture.md §4.7](architecture.md#47-the-installer) and a
  workflow section plus four troubleshooting rows in
  [development-environment.md](development-environment.md).

### Two defects found while building this

1. **`rpmbuild` lost the executable bit on the shared filesystem.** Every script
   in `openqos-installer` came out of the RPM with mode `0600`, silently, with no
   error: `rpmbuild` writing into `packages/_build` through the macOS mount drops
   the mode, and for this package that means a launcher and a unit `ExecStart` that
   cannot run. The build tree is now `/var/tmp/openqos-packages`, and the reason is
   written down in the script.
2. **Killing a KIWI build damages the VM.** An interrupted build left its chroot's
   bind mounts behind, and the next `rm -rf` of the scratch directory ran over the
   guest's real `/dev`, replacing `/dev/null` with a regular file and deleting
   `/dev/fd` and the rest. Symptom: `Permission denied` from every login shell and
   `/dev/fd/63: No such file or directory` mid-build. `/dev` is devtmpfs, so a VM
   restart repairs it. Documented, with the lesson: pass a fresh `--output` instead
   of interrupting a build.

### Verification

`tests/install-test.sh --boot`:

`tests/install-test.sh --boot` — **not passing yet.** The first run reached the
installer and stopped there, which is worth recording as it is:

| What | Result |
| --- | --- |
| The media are recognised as installation media and the service runs | yes — `openqos-autoinstall` started in the live session, before `graphical.target`, because the OEMDRV disk was present |
| Anaconda started | **no** — `pyanaconda/display.py:252` in `do_startup_wl_actions`: `os.path.join(os.getenv("XDG_RUNTIME_DIR"), ...)` raised `TypeError: expected str, bytes or os.PathLike object, not NoneType` |
| The kickstart was reached | no |

Cause: a systemd *system* unit has no session environment, and Anaconda reads
`XDG_RUNTIME_DIR` unconditionally when it starts. The unit now provides one
(`RuntimeDirectory=openqos-autoinstall`, `RuntimeDirectoryMode=0700`,
`Environment=XDG_RUNTIME_DIR=...`), and the script sets a default as well for a run
by hand.

Second run, media rebuilt with that fix — the crash is gone and the chain up to
Anaconda is verified:

```
[168s] openqos-autoinstall: reading the kickstart from /dev/disk/by-label/OEMDRV:/ks.cfg
[172s] openqos-autoinstall: installing unattended from /run/install/ks.cfg
```

**The installation still did not happen.** Nothing was written to the target disk:
the sparse qcow2 is 196 KiB after the run, and the guest powered off about 18
minutes after boot. So the media find the kickstart, stage it and hand it to
Anaconda, and Anaconda then ends without installing anything.

Why is not yet known, because the harness cannot see it — two blind spots of its
own, both worth fixing before the next attempt:

* Its completion marker is output from `%post`. Anaconda sends `%post` output to
  a log file on the target, not to the console, so the marker can never appear and
  every run ends in a 90-minute timeout.
* Its offline checks need `/dev/nbdN`, which does not exist until `modprobe nbd`
  has run. `qemu-nbd: Failed to open /dev/nbd0: No such file or directory`.

The next step is not a guess but a collector: a unit that runs after
`openqos-autoinstall.service` and copies `/tmp/anaconda.log` and
`/tmp/anaconda-post.log` from the live session onto the OEMDRV disk, which the
harness can then read offline. Anaconda's own log says why it stopped; nothing
outside the machine does.

Milestone 8 is therefore **not verified**.

### Evidence

* `files/m8-installer-evidence/serial-install-first-attempt.log` — the guest's
  serial console from the first attempt, containing the traceback above.
* `files/m8-installer-evidence/harness-output-first-attempt.txt` — the harness's own
  output for the same run, showing the OEMDRV medium being built and the machine
  booted from the real ISO.
* In the VM: `/var/tmp/install-test.log`, `/var/tmp/install-test/` (the next run
  replaces it).

### Still outstanding

* The interactive install has not been photographed end to end. The launcher, the
  polkit action and the desktop icon are on the media and the unattended path
  exercises the same kickstart, but nobody has yet clicked "Install OpenQOS" and
  watched the Web UI come up.
* A system installed from live media carries `anaconda-*` and `livesys-scripts`,
  because Anaconda copies the running live system and there is no post-install hook
  that both installation paths share. See §4.7.6.
* `mediawriter` was removed from the desktop as Fedora branding and nothing has
  replaced it, so there is still no OpenQOS image writer.

## Milestone 9 — x86_64 pipeline ⬜

**Not started.** Same shared descriptions and configuration, a separate
architecture-specific build configuration, and a build run on an x86_64 host or an
emulated x86_64 guest. Cross-architecture builds are slow; expect this milestone to
need more time than the aarch64 one.

## Milestone 10 — Release engineering ⬜

**Not started.** Exit criteria:

- [ ] PGP-signed SHA-256 checksums for every artefact, following Fedora's convention.
- [ ] An image verification procedure documented for users.
- [ ] The per-package license inventory from [licensing.md §3](licensing.md#3-upstream-fedora-components-are-not-ours-to-relicense).
- [ ] A build manifest pinning the Fedora compose and every input digest.
- [ ] Reproducible-build guidance, and release notes.

## Deliberate scope boundaries

These are out of scope, and are recorded here so they are decisions rather than
omissions:

* Patching or replacing the Fedora kernel.
* Any non-RPM packaging format.
* Writing a new installer instead of customising Anaconda.
* Booting natively on Apple Silicon Mac hardware. It is not promised anywhere in this
  project; see [architecture.md §8](architecture.md#8-apple-silicon-caveat).
* x86_64 builds before Milestone 9.
