# OpenQOS architecture

Status: **proposal for review.** Nothing in this document has been implemented or
built yet. Where a fact was checked against an upstream source, the source is named;
where something is a guess, it is labelled as such.

## 1. Goals and non-goals

**Goals**

* A recognisable, independently branded desktop Linux distribution.
* Built from Fedora — not Ubuntu or Debian — using Fedora's own tooling, packages,
  repositories and infrastructure.
* As close to upstream Fedora as practical, so that upstream security and feature
  updates keep flowing with minimal work.
* Reproducible, reviewable builds driven from this repository.

**Non-goals (at least initially)**

* Replacing or patching the Fedora kernel.
* Replacing the RPM/DNF ecosystem, or introducing non-Fedora package formats.
* A from-scratch installer. We customise Anaconda; we do not write a new installer.
* Running on Apple Silicon Mac hardware. See §8.

## 2. Upstream relationship

OpenQOS is a **derived distribution built by composition**, not a fork of Fedora's
source packages:

* Package content comes from official Fedora repositories.
* Our own content (`openqos-*` packages: branding, default configuration, release
  metadata) is built from [`packages/`](../packages) and layered on top.
* Upstream packages are consumed unmodified wherever possible. Any modification is a
  deliberate, documented decision, not a side effect.

This mirrors how Fedora's own Editions are assembled, and keeps the delta small
enough to maintain with limited hardware and time.

### Target baseline

| Item | Value | How verified |
| --- | --- | --- |
| Fedora release | 44 (latest stable) | `dl.fedoraproject.org/pub/fedora/linux/releases/` lists 33…44 |
| Next release | Fedora 45, targeted 2026-10-20 | Fedora schedule |
| KDE Plasma | 6.6.4 | `plasma-workspace-6.6.4-1.fc44.aarch64.rpm` etc. in the F44 aarch64 repo |

We deliberately do **not** track Rawhide. Fedora 45 will be re-evaluated once it is
released and has had updates stabilise.

## 3. Architecture matrix

| | Primary | Secondary |
| --- | --- | --- |
| CPU architecture | `aarch64` (ARM64) | `x86_64` |
| Why first | Matches the development machine's native architecture, so builds run under native virtualisation instead of slow emulation | Standard PC target; required for a credible distribution |
| Boot firmware | UEFI | UEFI (+ BIOS for wider PC compatibility) |

Shared and architecture-specific material is kept apart:

```
config/common/     architecture-neutral configuration (used by both)
config/aarch64/    aarch64-only configuration
config/x86_64/     x86_64-only configuration
```

The same split is applied inside the KIWI description: profiles are shared, and
architecture-specific content is selected with KIWI's `arch` attribute, exactly as
Fedora does (for example `<namedCollection name="kde-pim" arch="aarch64,ppc64le,x86_64"/>`).

## 4. Build pipeline

### 4.1 Tool selection (checked, not assumed)

| Tool | Verdict for OpenQOS | Evidence |
| --- | --- | --- |
| **KIWI** (`kiwi-cli`) | **Primary.** Fedora composes its desktop Live and disk images with KIWI. | `kiwi-cli-10.3.0` in F44, `kiwi-cli-11.1.1` in F44 updates, both `noarch`; `releng/kiwi-descriptions` is the canonical description set |
| **Kickstart** | **Still current**, but for a different job: it configures what *Anaconda* does at install time. | `pykickstart-3.69-1.fc44`; `mkksiso` injects `inst.ks=` |
| **lorax** / **livemedia-creator** | **Alternative build path.** Maintained and shipped, and the flow Fedora's Quick Docs still documents, but Fedora no longer uses it for its own desktop Live ISOs. | `lorax-44.6-1.fc44.aarch64` plus `lorax-lmc-novirt`/`lorax-lmc-virt` in F44 aarch64 |
| **osbuild** / **image-builder** | **Not yet.** Fedora uses it for Minimal/IoT, not for KDE desktop media. | `image-builder` present in F43/F44 |

The old `pagure.io/fedora-kickstarts` repository **is retired** — "all images
previously defined here are now built using kiwi". Its successor for the reference
kickstarts is `forge.fedoraproject.org/releng/spin-kickstarts`, with branches up to
`f43` and no `f44` branch. Do not follow the older Quick Docs page that tells you to
clone `pagure.io/fedora-kickstarts -b f42`.

### 4.2 Primary path: KIWI

Fedora's description set (`releng/kiwi-descriptions`, branch `f44`) is modular:

```
Fedora.kiwi                     root description; <include>s everything below
├── repositories/core.xml       repository definitions
├── components/common.xml       base system
├── components/boot.xml         bootloader
├── components/desktops/kde.xml KDE package set and profiles
├── components/liveinstall.xml  live-to-disk install support
├── teams/kde.xml               KDE-Desktop-Live / KDE-Desktop-Disk profiles
├── config.sh, scripts/         build hooks
└── grub-arm.cfg.iso-template   architecture-specific boot config
```

The KDE profiles we care about:

| Profile | Image type | Meaning |
| --- | --- | --- |
| `KDE-Desktop-Live` | `iso` | Bootable live media, installable to disk |
| `KDE-Desktop-Disk` | `oem` | Pre-installed disk image |

Invocation (the exact interface of Fedora's `kiwi-build` wrapper):

```sh
sudo ./kiwi-build --kiwi-file=Fedora.kiwi \
                  --image-type=iso \
                  --image-profile=KDE-Desktop-Live \
                  --image-release=0 \
                  --output-dir=./outdir
```

OpenQOS's equivalent is [`kiwi/OpenQOS.kiwi`](../kiwi/OpenQOS.kiwi), derived from
Fedora's description. Deriving rather than copying-and-forgetting matters: it keeps
the diff against upstream visible and reviewable.

The implemented layout is:

```
kiwi/
├── OpenQOS.kiwi       our root description; includes the pieces below
├── config.sh          our build-time configuration hook (profile-gated)
├── openqos/           our profiles and image types
│   ├── base.xml       OpenQOS-Base: shared base packages, disk layout, account
│   ├── kde.xml        KDE Plasma desktop profiles
│   └── test.xml       profiles with SSH, for automated verification
├── upstream.lock      pinned revision of Fedora's descriptions
└── upstream/          Fedora's descriptions, fetched, never committed
```

Note that Fedora's `config.sh` lives in `upstream/` and is **not** executed: KIWI
only looks for `config.sh` in the root of the description directory. That is why
Fedora's Cloud- and Live-specific behaviour does not leak into OpenQOS images, and
why anything we depend on must be set in our own `config.sh`.

Fedora's tree is fetched at a pinned commit by
[`scripts/fetch-upstream-descriptions.sh`](../scripts/fetch-upstream-descriptions.sh)
rather than vendored, for three reasons: our delta stays visible in review,
upstream fixes are adopted deliberately instead of by silent drift, and builds stay
reproducible because the revision is pinned by SHA.

Profiles we build today:

| Profile | Image type | Meaning |
| --- | --- | --- |
| `OpenQOS-Base` | `oem` | Shared base: Fedora base system, security baseline, aarch64 disk layout |
| `OpenQOS-Minimal` | (inherited) | Smallest bootable image; pipeline validation only |
| `OpenQOS-KDE` | — | The KDE Plasma desktop stack |
| `OpenQOS-KDE-Disk` | (inherited) | KDE Plasma pre-installed disk image |
| `OpenQOS-*-Test` | (inherited) | Whatever they inherit, plus SSH. **Not for release** |

A profile with an "(inherited)" type gets it from `OpenQOS-Base`, which it
`requires`. That is the KIWI mechanism which lets the disk layout be stated once
instead of duplicated per profile: preferences apply to every *active* profile name,
including required ones.

Profiles still to add:

| Profile | Image type | Meaning |
| --- | --- | --- |
| `OpenQOS-KDE-Live` | `iso` | Bootable live media, installable to disk |

### 4.2.1 A constraint worth knowing early

KIWI populates its target directory as a chroot, so it requires real ownership,
mode bits, ACLs and xattrs. The repository is mounted into the build VM over
virtiofs, which reports as `fuse` and cannot represent those, and KIWI refuses to
build there:

```
KiwiRuntimeError: Target root/image directory is lacking filesystem features
```

This is a genuine constraint rather than a bug, and it is why
[`scripts/build-image.sh`](../scripts/build-image.sh) builds into a scratch
directory on the guest's own disk (`/var/tmp/openqos-build`) and then publishes the
finished artefacts into `kiwi/build/` in the repository. The script checks the
scratch filesystem up front and fails with an explanatory message rather than
letting KIWI fail obscurely.

Also worth knowing: the build **must** run as root, because KIWI creates and mounts
disk images through loop devices.

A second, subtler constraint applies specifically to the `iso` image type.
`mkfs.erofs`, which KIWI uses to build the live filesystem, buffers through
`$TMPDIR`. This guest's `/tmp` is a tmpfs sized at half of RAM — 3.9 GiB on a
7.7 GiB guest — while the live filesystem compresses to roughly 3 GiB. Overrunning
it does not report anything about space; it reports:

```
mkfs.erofs: <E> erofs: failed to commit fragment for
  .../usr/share/locale/ko/LC_MESSAGES/libkldap6.mo: [Error 5] Input/output error
```

which sends you looking at the named file, the filesystem, or the compression
options, none of which are at fault. This was diagnosed by reproducing the exact
command on a comparable tree: it fails with `TMPDIR` unset and succeeds, producing
a 3.0 GiB image, with `TMPDIR` pointed at local disk.

`scripts/build-image.sh` therefore sets `TMPDIR=/var/tmp`. The value has to resolve
in **two** contexts — on the build host, where `mkfs.erofs` runs, and inside the
image chroot, where KIWI runs `dracut` to check ISO support. A directory under the
scratch root satisfies only the first: `dracut` then fails with `Invalid tmpdir`,
which KIWI reports as the thoroughly unhelpful *"Requested image type iso not
supported"*. `/var/tmp` is on local disk in both contexts and is already dracut's
own default, so dracut's behaviour is unchanged.

Enlarging the guest's `/tmp` instead would also work, and is arguably the cleaner
fix, but it changes the VM definition and so requires recreating the instance.

### 4.3 The role of kickstart

Kickstart is not an alternative to KIWI — it is a different layer.

* KIWI decides **what is on the medium**.
* Kickstart decides **what an installed system becomes** when Anaconda runs from
  that medium.

The file is `kickstart/openqos.ks`. It is shipped on the media as
`/usr/share/openqos/kickstart/openqos.ks`, and both installation paths hand it to
Anaconda: the interactive launcher on the live desktop, and the unattended service
that runs when the media are booted with `inst.ks=` or with a disk labelled
OEMDRV. §4.7 explains the installer as a whole.

### 4.4 Build outputs

| Artefact | Type | Notes |
| --- | --- | --- |
| `OpenQOS-Live-KDE-<rel>.aarch64.iso` | `iso` | Primary deliverable; boots and installs |
| `OpenQOS-KDE-<rel>.aarch64.raw` | `oem` | For flashing to ARM boards/VM images |
| `OpenQOS-Live-KDE-<rel>.x86_64.iso` | `iso` | Milestone 9 |

Every artefact is accompanied by a SHA-256 checksum in a GPG-signed `*-CHECKSUM`
file, following the upstream convention.

### 4.4.1 The medium carries its own identity

An installed system gets its identity from `openqos-release` (§5.1). A live medium
carries a second one, in the ISO volume descriptor, and it comes from Fedora's
`LiveInstall` preferences:

| Field | Fedora's value | OpenQOS's value |
| --- | --- | --- |
| `volid` | `Fedora_Linux` | derived from the profile name, e.g. `OpenQOS_KDE_Live_Test` |
| `publisher` | `Fedora Project` | `OpenQOS` |
| `application_id` | `Fedora_Linux` | `OpenQOS Linux` |

These cannot be overridden in the description. Preferences attach to every profile in
the active set, including required ones, so a second `<type image="iso">` for the same
build is a hard error — the same constraint that keeps the `oem` type out of
`base.xml`. KIWI supports `--set-type-attr=<attribute>=<value>` on the command line
instead, which is also how Fedora's own live-ISO label generator applies its labels,
so `scripts/build-image.sh` passes them there.

**The volume label is load-bearing, not cosmetic.** KIWI composes the kernel command
line as `root=live:CDLABEL=<volid>`, so the label is how a live system finds its own
root filesystem. Both the ISO builder and the bootloader config read the same
attribute, so they cannot disagree within a build — but the failure mode if they ever
did is media that boots to a dracut prompt rather than a desktop, which is why the two
are checked together after every build rather than assumed.

Labels are derived from the profile name with `-` replaced by `_`, so two different
media cannot be built with the same label: `CDLABEL` matching cannot distinguish two
identically-labelled discs. A label over 32 characters fails the build, because
ISO9660 allows no more and silently truncating would change what the bootloader looks
for.

### 4.5 How desktop configuration is applied

The desktop is configured through the mechanisms Plasma and KDE already provide,
rather than by editing files owned by other packages. Three of them matter, and
they were established by reading what Fedora and KDE actually ship:

**1. `/etc/xdg` is the highest-precedence system configuration directory.**
Plasma's own `/etc/xdg/plasma-workspace/env/env.sh` sets

```
XDG_CONFIG_DIRS=/etc/xdg:/usr/share/kde-settings/kde-profile/default/xdg
```

so a file we ship at `/etc/xdg/<app>rc` overrides the `kde-profile` shipped by
Fedora's `kde-settings` package. This is the supported way for a distribution to
state its own defaults, and it means no upstream file is ever modified.

**2. A *look-and-feel* package is how a distribution declares its identity.**
Installed at `/usr/share/plasma/look-and-feel/<id>/`, it contains:

| Path | Purpose |
| --- | --- |
| `metadata.json` | `KPackageStructure: Plasma/LookAndFeel` plus name, license, website |
| `contents/defaults` | Theme, colour scheme, icon theme, cursor, window decoration, splash |
| `contents/layouts/org.kde.plasma.desktop-layout.js` | The default panel: launcher, task manager, tray, clock |
| `contents/previews/` | Preview images for the global-theme picker |

Selecting it is then a single key, `[KDE] LookAndFeelPackage` in `kdeglobals`.
Plasma applies it when a user's session configuration is first created, so a new
user gets the layout without anything pre-seeded into `/etc/skel`.

OpenQOS therefore ships `org.openqos.desktop`, and
[`config/common/usr/share/plasma/look-and-feel/`](../config/common/usr/share/plasma/look-and-feel)
is where the visual identity lives. Today it selects upstream Breeze Dark;
Milestone 7 replaces those selections with the OpenQOS palette, wallpaper, icons
and splash. That is a content change to one directory, not a change to the
mechanism.

**3. KIWI resolves `<file name="...">` against the description directory — and it
does so inconsistently.** KIWI imports the file flattened to
`<description>/image/<basename>` but installs it from
`<description>/image/<dirname(name)>/<basename>`. Those two paths agree only when
`name` has no directory component, so a `<file>` referencing a nested path imports
successfully and then fails at install time with an rsync error about a directory
that does not exist. Every referenced file must therefore sit at the *description
root* under a unique bare basename.

`scripts/build-image.sh` handles this by symlinking each file from `config/` into
the description root as `staged-<basename>`, failing loudly if two files would
collide. `config/` remains the single source of truth, and the `staged-` prefix
gives one predictable pattern to ignore in Git.

A caveat that follows from (2): **a typo in the panel layout widget names is not a
build failure.** `layout.js` runs inside the user's session, so a wrong widget name
produces a panel with a missing widget, which only a visual check will catch.

That check used to be impossible here, and is now merely slow:
[`tests/screenshot-image.sh`](../tests/screenshot-image.sh) boots an image under QEMU,
which emulates a virtio GPU, and reads the screen through the QEMU monitor. See §4.6.

### 4.6 Login screen and first boot

Neither is OpenQOS software. Both are KDE components that OpenQOS *configures*, and in
both cases the work was to replace a Fedora-shaped default.

**Login screen.** SDDM is gone as of Plasma 6.7; the display manager is
`plasma-login-manager` (`plasmalogin.service`). Its configuration has a documented
split of ownership, which the packages implement as two files:

| File | Owner | OpenQOS |
| --- | --- | --- |
| `/usr/lib/plasmalogin/defaults.conf` | the distribution | **ours**, installed from `config/common/` |
| `/etc/plasmalogin.conf` | the user | untouched |

This is the same pattern as `/etc/xdg/kdeglobals` (§4.5): the distribution states its
default, the user's own file wins, and the two never fight. It matters here because
Fedora's copy of `defaults.conf` is what pointed the login screen at Fedora's wallpaper.

The greeter is a Plasma application. Its colours, fonts and icon theme come from
`/etc/xdg/kdeglobals` — so the OpenQOS colour scheme themes the login screen as a
side effect, and there is no greeter theme to author. What is left to configure is the
wallpaper, which is expressed as a Plasma wallpaper *plugin* and its settings rather
than as an image path:

```ini
[Greeter]
WallpaperPlugin=org.kde.image

[Greeter][Wallpaper][org.kde.image][General]
Image=file:///usr/share/wallpapers/OpenQOS/
```

**First boot.** KDE's `plasma-setup` runs a wizard before the display manager on the
first boot of a disk image, gated on the absence of `/etc/plasma-setup-done` and on the
media not being live. OpenQOS's contribution is to make that contract *load-bearing and
checked*: product images ship no usable account, so the wizard is the only way in, and
`kiwi/config.sh` fails the build if a profile ever installs a display manager without
either a usable account or a wizard that will run.

The rest of the first boot is inherited behaviour that is now verified rather than
assumed — hostname from `DEFAULT_HOSTNAME` in our os-release, an empty
`/etc/machine-id` that systemd populates on first boot, SSH host keys generated per
machine, and `[Accounts] UserGroups=wheel` in `plasmasetuprc` making the first user an
administrator.

### 4.7 The installer

Anaconda, Fedora's installer, is on the media already: it arrives with upstream's
`LiveInstall` profile, whose own comment is "The point of a live image is to
install". Nothing here replaces it. What OpenQOS adds is the definition of what an
installation produces, a launcher that uses it, and the branding that makes the
installer look like the distribution being installed.

#### 4.7.1 What Fedora does, and why OpenQOS does not

Anaconda removes the kickstart mechanism on live media, by design. `liveinst`
starts it with `--liveinst`, and Anaconda's single kickstart resolver,
`pyanaconda.startup_utils.find_kickstart()`, is gated on `not options.liveinst` in
both of its branches. A live install parses no kickstart at all; it copies the
running live system (`LiveOSPayload`) and asks a few questions interactively. There
is no post-install script mechanism either, so nothing in a repository decides
what a Fedora live installation becomes — storage is whatever automatic
partitioning chooses that day.

That is a reasonable product decision for Fedora and an unacceptable one here: the
project's own rule is that the installed system and the disk image are the same
system, and only one of them was defined by a file under review. So the launcher
does not pass `--liveinst`. Without it, `find_kickstart()` is willing, the kickstart
is honoured, and the payload is named by the kickstart instead —
`liveimg --url=file:///run/initramfs/live/LiveOS/squashfs.img`, which copies the
medium's own filesystem image to the target. Anaconda's `liveimg` command is a
supported, documented kickstart command; the only unusual part is which of
Anaconda's two live payloads ends up in use.

#### 4.7.2 What is on the media

| Path | What it is | Shipped by |
| --- | --- | --- |
| `/usr/share/openqos/kickstart/openqos.ks` | The installation definition: GPT, a 100 MiB ESP, one btrfs volume labelled `openqos` with `root`/`boot`/`home`/`var` subvolumes, locked root, and the `%post` assertions below. | `openqos-installer` (sources `kickstart/openqos.ks`) |
| `/usr/share/applications/org.openqos.installer.desktop` | "Install OpenQOS". `NoDisplay=true`, so it never becomes a menu entry on a system installed from media; the live desktop gets the icon instead. | `openqos-installer` |
| `/usr/bin/openqos-install` | The desktop entry's command. Refuses arguments, asks pkexec for privilege, passes the kickstart. | `openqos-installer` |
| `/usr/bin/openqos-install-root` | The privileged half: `/usr/libexec/anaconda/webui-desktop -t live`, then `anaconda --graphical --ks=…`. | `openqos-installer` |
| `/usr/libexec/openqos/openqos-autoinstall` | The unattended path, started by `openqos-autoinstall.service` before `graphical.target`. | `openqos-installer` |
| `/usr/libexec/openqos/openqos-install-setup` | Puts the icon on the live desktop and takes Anaconda's Fedora-named one away. | `openqos-installer` |
| `/etc/anaconda/profile.d/openqos.conf` | The installer's product profile, see §4.7.4. | `config/common`, via a KIWI `<file>` |
| `/usr/share/polkit-1/actions/org.openqos.installer.policy` | Permission to run `openqos-install-root`, and nothing else. | `openqos-installer` |

`openqos-installer` is installed on live profiles only (`kiwi/openqos/kde.xml`),
which is what keeps its `Requires: anaconda-core` from dragging an installer into
the pre-installed disk images.

#### 4.7.3 Asking for an unattended installation

Two ways, and the second is the older convention:

* `inst.ks=` on the kernel command line — a local path, a `file://` URL, or
  `hd:LABEL=OEMDRV:/ks.cfg`. Fedora's media honour this from the initramfs because
  they install `anaconda-dracut`; OpenQOS media do not carry it, so the request is
  honoured in the live session instead, which is what `openqos-autoinstall.service`
  is for.
* A disk labelled **OEMDRV** holding `/ks.cfg`, with nothing on the command line.
  That is Anaconda's own convention and needs no boot option at all. Anaconda
  ignores OEMDRV-labelled disks as installation targets
  (`pyanaconda/ui/lib/storage.py`), so the disk the kickstart came from cannot be
  wiped by the installation it describes.

With neither, the service does nothing. A machine that erases its disks should have
been told to.

Not handled: `http://`, `https://` and `nfs:` kickstarts. Fetching those needs the
network up and a URL implementation, and Anaconda's fetching lives in the
`anaconda-dracut` module this medium deliberately does without.

#### 4.7.4 The installer's product profile

Anaconda chooses one profile from `/etc/anaconda/profile.d` by matching the running
system's `/etc/os-release` against each profile's `[Profile Detection]` block.
Fedora ships one per product; without one matching `ID=openqos`, Anaconda says so in
the log and installs on bare defaults — LVM where OpenQOS ships btrfs, and the
Fedora stylesheet rather than none. `/etc/anaconda/profile.d/openqos.conf` inherits
Fedora's profile and overrides:

| Setting | Value | Why |
| --- | --- | --- |
| `[Profile Detection] os_id` | `openqos` | Matches our os-release. |
| `[Storage] default_scheme`, `btrfs_compression` | `BTRFS`, `zstd:1` | What the images use; relevant when a user edits the storage page by hand. |
| `[Bootloader] efi_dir` | `openqos` | The firmware menu is user-visible and should not say `fedora`. |
| `[Localization] use_geolocation` | `False` | Fedora's default asks `geoip.fedoraproject.org`. That is someone else's infrastructure, and it discloses the machine's address. The date/time page stays visible so the user can still set a timezone. |
| `[User Interface] custom_stylesheet` | empty | Fedora's base profile points at Fedora's installer stylesheet. |
| `[User Interface] hidden_webui_pages` | `anaconda-screen-accounts` | Account creation belongs to Plasma Setup, the first-boot wizard — Fedora KDE's choice, and what the disk images do. |

`custom_stylesheet` is cleared rather than replaced because the Fedora 44 Web UI
does not read it: the string appears nowhere in
`/usr/share/cockpit/anaconda-webui`. The installer's only branding is the product
name, which it reads from `PRETTY_NAME` in `/etc/os-release` — already ours. A
stylesheet of our own would have been dead configuration.

#### 4.7.5 The assertions

`kickstart/openqos.ks` ends with a `%post --erroronfail` block that refuses to
produce the system, and it checks the same three things `kiwi/config.sh` checks
when an image is built:

1. `/usr/lib/os-release` is owned by `openqos-release` — the installed system
   identifies as OpenQOS and not as the Fedora base.
2. No `fedora-release*` or `generic-release*` package is installed, so
   `/etc/system-release`, `/etc/fedora-release` and `/etc/redhat-release` do not
   exist — no Fedora flavour, and no Fedora release name, claims the medium.
3. If a display manager is installed, either an account with a password exists or
   Plasma Setup is present, enabled and not marked done — the machine is enterable.

The third is the one that matters. Locking root and leaving account creation to the
first-boot wizard are two individually sensible decisions whose combination bricks
a machine, and it is invisible until somebody tries to log in. It is asserted in
both artefact paths because the two artefacts can only stay equivalent if the same
promise is checked in both.

#### 4.7.6 Known limitations

* A system installed from live media carries the installer. Anaconda copies the
  running live system, and there is no hook to remove `anaconda-*` or
  `livesys-scripts` afterwards; Fedora's live installs have the same property. The
  live-only units are gated on `rd.live.image` and the launcher checks for the
  medium before doing anything, so nothing in an installed system misbehaves — it
  is disk space, not a defect. A `%post` that removes them is possible only for the
  unattended path, and two installation paths that produce different systems is
  worse than one that leaves 300 MiB behind.
* The kickstart expects a single installation target. Several candidate disks stop
  an unattended installation rather than guess.
* The installer desktop entry is English-only. Anaconda's own is translated;
  adding translations to ours is outstanding work, and it is cosmetic.

## 5. Package strategy

Our delta is packaged as RPMs so that it is versioned, upgradable and separable from
upstream content:

| Package | Contents | Architecture |
| --- | --- | --- |
| `openqos-release` | `/usr/lib/os-release` (the OpenQOS identity), `/etc/os-release`, and the `system-release` and `system-release(<N>)` capabilities that `setup` and `fedora-repos` require | `noarch` |
| `openqos-branding` | `/usr/share/wallpapers/OpenQOS`, `/usr/share/wallpapers/Default`, the Plasma colour scheme, the Plymouth theme and its dracut snippet, `/usr/share/pixmaps/system-logo-white.png`, and the hicolor icon named by `LOGO=openqos-logo` | `noarch` |
| `openqos-config-desktop` | Plasma panel/launcher/tray defaults, default applications, accessibility and locale defaults | `noarch` |
| `openqos-config-<arch>` | Architecture-specific defaults | per-arch |

`openqos-branding` and `openqos-release` carry the artwork licence and the code
licence respectively, because the two are used differently: images are redistributed
as assets, scripts are not. See [licensing.md](licensing.md).

Its contents are **not** rendered at build time. The raster assets are committed,
produced from the SVG sources by `branding/tools/render-assets.py`, because rendering
inside rpmbuild would make a package's contents depend on the build machine's librsvg
version — two machines would then produce two different "identical" packages. A stale
asset is caught by `render-assets.py --check` instead.

`openqos-branding` deliberately does not depend on Plasma. The wallpaper and colour
scheme are inert without it, but a minimal image still needs the logo and the icon, so
a hard dependency would drag a desktop into every profile.

### 5.2 Where we copy Fedora rather than include it

The default is to *include* Fedora's description files, so upstream fixes arrive by
changing the pinned commit and nothing else. There are two places where OpenQOS copies
instead, and both are because KIWI offers no way to subtract from another file:

| Ours | Replaces | Delta |
| --- | --- | --- |
| `kiwi/openqos/desktop-common.xml` | `upstream/components/desktops/common.xml` | `mediawriter` is ignored rather than installed |
| `kiwi/templates/grub-arm.cfg.iso-template` | `upstream/grub-arm.cfg.iso-template` | the GRUB menu class, `fedora` → `openqos` |

The first is a one-line change that cannot be expressed any other way. `<ignore>`
becomes dnf's exclude, and dnf refuses a transaction that both requests and excludes
the same package, which is exactly what upstream's explicit `<package
name="mediawriter"/>` line does. Owning the file is the price of dropping the package;
removing Fedora Media Writer from an OpenQOS desktop is worth it, since it is Fedora's
own image-writing utility and nothing depends on it.

The GRUB template is staged under upstream's *filename*, because that is the name
upstream's `grub_template` attribute asks for and KIWI resolves it against the
description root. `scripts/build-image.sh` prefers our copy and reports the substitution
in every build log, so the shadowing is never invisible.

Both divergences are checked by [`tests/check-upstream-drift.sh`](../tests/check-upstream-drift.sh),
which fails when the difference is anything other than the documented one. Without it,
owning a file means upstream additions stop reaching us silently, which is the real
cost of copying rather than including.

Rules:

* Never overwrite a file owned by an upstream package without recording that
  conflict in the package spec.
* Prefer `/etc/skel` and vendor-default configuration over editing upstream unit files.
* Keep branding assets out of binary blobs where a source form can be shipped.

### 5.1 How OpenQOS declares its identity

Fedora splits "who am I" across packages:

| Package | Owns | Ours? |
| --- | --- | --- |
| `fedora-release-common` | `/etc/os-release` (a symlink to `../usr/lib/os-release`), `/etc/system-release`, `/etc/redhat-release`, the CPE file | no — **not installed** |
| `fedora-release-identity-<flavour>` | `/usr/lib/os-release` | no — not installed |
| `openqos-release` | `/usr/lib/os-release`, `/etc/os-release` | yes |

`fedora-release-common` requires the **versioned virtual name**
`fedora-release-identity = <fedora-version>-<fedora-release>`, and 61 flavour
packages provide it — one per Fedora edition and spin. Because no profile names a
flavour, dnf selects one freely, and `fedora-release-identity-budgie` was what it
chose for an image with no desktop.

`fedora-release` requires `fedora-release-common`, and is in turn what satisfies two
requirements on the release identity:

| Requirer | Requires |
| --- | --- |
| `setup` | `system-release` |
| `fedora-repos` | `system-release(44)` |

The second is Fedora's own idiom: a capability whose *name* carries the release
number. `fedora-release` declares both.

Three consequences shape the design:

* `openqos-release` must provide the virtual name at exactly the version
  `fedora-release-common` asks for, plus `system-release` and `system-release(44)`.
  The version tracks Fedora's updates and is therefore not ours to choose, so the
  package carries Fedora's version-release (`44-18`) and the OpenQOS version lives in
  the os-release content. `scripts/build-packages.sh` reads the required version from
  the repositories and refuses to publish a package that does not provide it.
* The whole family is made ineligible, so the only remaining provider is ours:
  `<ignore name="fedora-release*"/>` and `<ignore name="generic-release*"/>`. KIWI
  converts these to dnf's exclude option, which accepts a glob. Because `<ignore>` is
  read per packages **section type** and not per profile, the same rule is needed in
  the `bootstrap` section (`kiwi/OpenQOS.kiwi`) as well as the `image` section
  ([`kiwi/openqos/base.xml`](../kiwi/openqos/base.xml)) — the bootstrap transaction
  installs the family via `filesystem` → `setup` → `system-release`, before any image
  package is considered.
* The glob covers the family rather than naming three packages, because the family
  serves three requirements and satisfying one of them is not enough. Between them,
  `fedora-release`, the `<flavour>` packages and the `-identity-<flavour>` packages
  own `/etc/system-release`, `/etc/fedora-release`, `/etc/redhat-release` and
  `/usr/lib/os-release`.
* `generic-release` is Fedora's unbranded counterpart and provides the same
  capabilities, including `fedora-release-identity`, owning `/usr/lib/os-release` as
  its only file. Excluding only the branded package hands the work to it rather than
  removing it. This is the same trap as `fedora-logos` and `generic-logos`, and the
  first attempt at this change hit both. The visible result of getting it right is
  that `/etc/system-release`, `/etc/fedora-release` and `/etc/redhat-release` do not
  exist in an OpenQOS image: each named Fedora, and nothing reads them for anything
  but `cat`. An earlier revision of this document kept them deliberately, "truthful
  about the base"; that was reversed because a file named `fedora-release` is a claim
  about what the system is, not merely a record of what it was built from.

Obsoleting a single flavour is the intuitive approach and does not work: it removes
one candidate out of 61, so dnf picks another and the conflict reappears under a
different package name. Repo priority does not decide it either, since our
repository and Fedora's all share one priority.

## 6. Reproducibility and verification

* Pin the exact Fedora release and compose; record it in the build manifest.
* Record SHA-256 digests of every downloaded upstream artefact and **verify against
  Fedora's PGP-signed `*-CHECKSUM` files** before use.
* Build scripts must be idempotent and must fail loudly rather than silently
  producing a different image.
* Test images are verified by booting them, not by trusting that a build command
  exited 0. See §7.

### 6.1 Password hashing

KIWI's `<user password="..." pwdformat="plain">` hashes with the C library's default
crypt method, which on current glibc is **MD5**: the image shipped a `$1$` hash in
`/etc/shadow`. KIWI offers no stronger option — `pwdformat` accepts only `plain` and
`encrypted`, and `encrypted` means committing a hash, which is no better than
committing the password.

The description therefore sets no usable password: `password="!"` with
`pwdformat="encrypted"`, which KIWI passes through verbatim (`useradd -p '!'`) and
which is the standard marker for an account that cannot be logged into. The attribute
cannot be omitted — KIWI's schema makes it required.

Credentials are set in [`kiwi/config.sh`](../kiwi/config.sh), where `chpasswd` can be
told the algorithm: `--crypt-method YESCRYPT`, named explicitly rather than left to a
default, so this cannot silently become something weaker if shadow-utils changes what
it picks. The result is a `$y$` hash.

Two assertions run in that same script, so a mistake fails the build rather than being
noticed later:

* **Nothing weaker than SHA-512.** Any `$1$` or `$5$` hash in `/etc/shadow` fails the
  build.
* **No credential on a non-development profile.** A profile whose name does not mark
  it as development must have every account locked (`!`) or passwordless (`*`).
  Milestone 8's installer creates the real user, and this is what stops a development
  credential reaching a publishable image by accident.

## 7. Definition of "verified"

A claim of success requires observed evidence. For this project:

* "Image built" means the file exists **and** its checksum matches the recorded
  manifest.
* "Image boots" means a virtual machine was started from it and reached a usable
  login, and the output of that boot was captured.
* "Package works" means it was installed on a running system and the effect observed.

If a step was not executed, the roadmap marks it as pending rather than done.

## 8. Apple Silicon caveat

The development machine is an Apple M5 MacBook Air. This affects the project in two
separate ways, and they must not be confused:

1. **Building.** No Fedora image-building tool runs on macOS. All builds happen
   inside an `aarch64` Fedora virtual machine on the Mac. This is straightforward and
   works well, because the guest architecture matches the host architecture.
2. **Booting OpenQOS on Apple hardware.** *Not targeted, and not promised.* ARM64
   compatibility is not Apple-hardware compatibility: Apple Silicon needs platform
   support beyond generic `aarch64` (its own bootstrap, interrupts, and device tree).
   A generic OpenQOS ISO will not boot natively on an M5 Mac.

OpenQOS's aarch64 images therefore target **standard UEFI `aarch64` virtual machines
and boards** (QEMU `virt`, UTM, and generic ARM servers/boards). Fedora does carry an
`asahi` team description for Apple Silicon, and Asahi Linux is a genuine future
option, but it is out of scope for this roadmap and is not a promise.

## 9. Directory-to-purpose map

| Directory | Purpose | Milestone |
| --- | --- | --- |
| [`docs/`](.) | Architecture, setup, licensing, roadmap | 1–3 |
| [`branding/`](../branding) | Original artwork and visual identity | 7 |
| [`config/`](../config) | Configuration overlays, split by architecture | 7 |
| [`packages/`](../packages) | `openqos-*` RPM packaging | 7 |
| [`kiwi/`](../kiwi) | KIWI image descriptions (primary build path) | 4, 6 |
| [`kickstart/`](../kickstart) | Anaconda install behaviour | 8 |
| [`scripts/`](../scripts) | Build and verification entry points | 4, 10 |
| [`tools/lima/`](../tools/lima) | Development VM definition | 2 |
| [`tests/`](../tests) | Repository and image checks | 10 |
| [`.github/workflows/`](../.github/workflows) | CI | 10 |
