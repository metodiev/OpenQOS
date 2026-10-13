# OpenQOS Linux

OpenQOS Linux is an independent desktop Linux distribution built from
[Fedora](https://fedoraproject.org/) as its upstream base, with KDE Plasma as its
primary desktop. It is not a derivative of Ubuntu or Debian: it uses RPM, DNF,
Anaconda and Fedora's own image-composition tooling.

> **Project status: pre-alpha — Milestone 8 in progress.** The pipeline works end
> to end: it produces bootable `aarch64` images (minimal and KDE) whose checksums
> verify, and live installation media whose volume label, identity and boot path all
> agree. The system identifies itself as OpenQOS — `/usr/lib/os-release` is owned by our
> own `openqos-release`, and the wallpaper, colour scheme, login screen, boot splash and
> logo come from `openqos-branding`, with the artwork created for this project. A
> first-boot wizard creates the first user, and its absence is a build failure because
> these images deliberately ship no usable account.
> **Nothing built so far is publishable**: there is no installer yet, no x86_64 build,
> no signed checksums, and the artwork is deliberately plain. See the
> [roadmap](docs/roadmap.md).
>
> **Name/trademark:** "OpenQOS" is a working title. No trademark clearance has been
> performed. See [docs/licensing.md](docs/licensing.md).

## Verified baseline

These are the upstream versions this project currently targets. They were confirmed
against Fedora's official mirrors and sources, not assumed.

| Item | Value |
| --- | --- |
| Upstream base | **Fedora 44** (latest stable; Fedora 45 targeted 2026-10-20) |
| Primary architecture | `aarch64` (ARM64) |
| Secondary architecture | `x86_64` |
| Desktop | **KDE Plasma 6.7.5** (`plasma-workspace`, `plasma-desktop`, `kwin`) |
| Login manager | **`plasma-login-manager` 6.7.5** — KDE's QML login manager, which replaced SDDM in Plasma 6.7 |
| Package management | RPM + DNF5 |
| Image composition | **KIWI** (`kiwi-cli`), Fedora's current tool for desktop Live/disk media |
| Installer | Anaconda (kickstart-driven) |
| Build host | Fedora 44 `aarch64` virtual machine (Lima `vz`), **created and verified** |

Verified upstream artefacts used by this project:

* `Fedora-Cloud-Base-Generic-44-1.7.aarch64.qcow2` (build VM base)
* `Fedora-KDE-Desktop-Live-44-1.7.aarch64.iso` (behavioural reference)
* `Fedora.kiwi` / `components/desktops/kde.xml` from
  `releng/kiwi-descriptions` branch `f44` (package-set reference)

## Repository layout

```
openqos/
├── README.md            This file.
├── LICENSE              License for original OpenQOS code (see docs/licensing.md).
├── CONTRIBUTING.md      How to contribute and what the review bar is.
├── docs/                Architecture, environment setup, licensing, roadmap.
├── branding/            Original OpenQOS artwork: wallpapers, icons, themes, logo.
├── config/              Overlay trees, mirroring the image root
│   ├── common/          Applied on every architecture
│   │   ├── etc/xdg/     Desktop defaults (KDE, default applications)
│   │   └── usr/share/plasma/look-and-feel/  The OpenQOS look-and-feel package
│   ├── aarch64/         Applied only when building aarch64
│   └── x86_64/          Applied only when building x86_64
├── packages/            RPM packaging for openqos-* packages (config + branding).
├── kiwi/                KIWI image descriptions — the primary build path.
│   ├── OpenQOS.kiwi     Root description; includes the pieces below.
│   ├── config.sh        Build-time hook, gated on the profile name.
│   ├── openqos/         Our profiles: base, KDE, and test variants.
│   ├── upstream.lock    Pinned revision of Fedora's descriptions.
│   └── upstream/        Fedora's descriptions, fetched (not committed).
├── kickstart/           Kickstart files controlling the Anaconda install experience.
├── scripts/             Build, verification and helper tooling.
├── tools/lima/          Definition of the Fedora aarch64 development VM.
├── tests/               Checks for the repository and for built images.
└── .github/workflows/   CI: linting and (later) image builds.
```

OpenQOS **derives from** Fedora's image descriptions rather than vendoring them:
`scripts/fetch-upstream-descriptions.sh` fetches them at the commit pinned in
[`kiwi/upstream.lock`](kiwi/upstream.lock), so the difference between Fedora's
description and ours stays visible in review, and upstream fixes are adopted
deliberately instead of by silent drift.

Why `kiwi/` and not just `kickstart/`: since around Fedora 42, Fedora composes its
desktop Live and disk images with KIWI, and the old `fedora-kickstarts`/
`spin-kickstarts` repository is archived. Kickstart still defines what *Anaconda*
does when a user installs, so both directories are needed and they are not
interchangeable. See [docs/architecture.md](docs/architecture.md).

## Development environment

OpenQOS is built inside an `aarch64` Linux virtual machine; **none of the
distribution build tooling runs on macOS**. The macOS host is for editing, Git,
and driving the VM.

```sh
# On macOS (Apple Silicon), from the repository root.

# First time only — creates the VM (downloads ~504 MiB, provisions the toolchain):
limactl start --name=openqos-dev tools/lima/openqos-dev.yaml

# Afterwards — the instance already exists:
limactl start openqos-dev     # boot it
limactl shell openqos-dev     # enter the build environment
limactl stop openqos-dev      # reclaim ~8 GiB of host memory when not building
```

The VM is running Fedora 44 (`aarch64`), 6 CPUs, 8 GiB RAM, with `kiwi-ng` 11.1.1,
`lorax` 44.7 and the rest of the build toolchain installed. The repository is mounted
read-write into the guest at the same path, so saves on macOS are immediately visible
to builds.

Step-by-step instructions, including expected output at each step and the memory/
CPU settings chosen for a 16 GB Apple Silicon machine, are in
[docs/development-environment.md](docs/development-environment.md).

## Building an image

Images are built inside the VM, as root:

```sh
limactl shell openqos-dev                                  # macOS

cd /Users/miroslav/Documents/workspace/OpenQOS/OpenQOS      # Fedora, same path
scripts/fetch-upstream-descriptions.sh                     # once, or after a pin update
sudo scripts/build-image.sh --clean
```

`build-image.sh` is the single definition of how an OpenQOS image is produced. It
builds on the guest's local disk — KIWI needs ownership, ACLs and xattrs that the
virtiofs mount of this repository cannot represent — then publishes the artefacts
into `kiwi/build/<profile>/` together with a `MANIFEST.txt` recording the Fedora
release, the pinned upstream commit, the KIWI version, and the SHA-256 of every
artefact.

Profiles available today:

| Profile | Type | Purpose |
| --- | --- | --- |
| `OpenQOS-Minimal` | inherited | Smallest bootable image; **pipeline validation only** |
| `OpenQOS-KDE-Disk` | inherited | KDE Plasma pre-installed disk image |
| `OpenQOS-KDE-Live` | `iso` | KDE Plasma live **installation media** |
| `OpenQOS-Minimal-Test` | inherited | `OpenQOS-Minimal` plus SSH. **Not for release** |
| `OpenQOS-KDE-Disk-Test` | inherited | `OpenQOS-KDE-Disk` plus SSH. **Not for release** |
| `OpenQOS-KDE-Live-Test` | `iso` | `OpenQOS-KDE-Live` plus SSH and a known account. **Not for release** |

The `iso` profiles inherit their image type, and the live package list, from
Fedora's `LiveInstall`. Note that a live image has **no usable account** by
design — `livesys-scripts` creates a temporary autologin account at boot, and the
`-Test` variants exist only so that a built image can be inspected.

The disk layout, security baseline and development account are defined once in
`OpenQOS-Base` and inherited by the images above, rather than duplicated per
profile.

Both development profiles set a publicly known root password (`openqos-dev`) so the
image can be logged into while the pipeline is being validated. Images built from
them must never be published or used on real hardware. See
[docs/roadmap.md](docs/roadmap.md) for what replaces this.

## Documentation

| Document | Contents |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | Distribution architecture and build-pipeline design |
| [docs/development-environment.md](docs/development-environment.md) | Setting up and verifying the Fedora aarch64 build VM |
| [docs/licensing.md](docs/licensing.md) | Licensing and branding policy (proposal) |
| [docs/roadmap.md](docs/roadmap.md) | Milestones, current status, TODO |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). All original OpenQOS material is licensed
under GPL-3.0-or-later; upstream Fedora components keep their own licenses.
