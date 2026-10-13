# Development environment

This document is **Milestones 1 and 2** of the [roadmap](roadmap.md): it explains the
recommended setup for developing OpenQOS on an Apple Silicon Mac, and how to verify
it. Steps marked **macOS** run in Terminal on the Mac; steps marked **Fedora** run
inside the virtual machine.

Where this document says "expected output", that text describes what the command
should print. The environment described here has been created and checked on this
machine; the results are recorded in the
[verification log](#11-verification-log), and anything that has *not* been observed
is listed there too.

## 1. The two worlds

| | macOS host (Apple Silicon) | Fedora aarch64 VM |
| --- | --- | --- |
| What it is for | Editing files, running Git, driving the VM | **All** OpenQOS builds |
| Can build images? | No | Yes |
| Terminal prompt | `miroslav@Miroslavs-MacBook-Air` | `[lima@openqos-dev ~]$` |

This separation is not a preference, it is a hard constraint:

* `kiwi`, `lorax`, `livemedia-creator` and `image-builder` are Linux tools with no
  macOS builds.
* `mkksiso` refuses to operate on an ISO whose architecture differs from the host's,
  so aarch64 media must be produced on an aarch64 system.
* KIWI's own guidance is that the image architecture should match the build host.

Because the Mac is arm64 and the VM is aarch64, the VM runs under hardware
virtualisation. There is no CPU emulation in this design, which is what makes it
practical on a 16 GB machine.

## 2. What was found on this machine

Verified on 2026-10-12 with `uname -m`, `sysctl`, `sw_vers` and `brew`:

| Item | Value |
| --- | --- |
| CPU | Apple M5 (`arm64`) |
| OS | macOS 27.0.1 |
| Memory | 16.0 GiB |
| Cores | 10 (4 performance, 6 efficiency) |
| Hardware virtualisation | available (`kern.hv_support = 1`) |
| Free disk | ~307 GiB |
| Homebrew | `/opt/homebrew` |
| **Present** | `limactl` 2.1.1, `git`, `curl`, `python3`, `node`, `colima` 0.10.1 (stopped), `docker` CLI |
| **Absent** | UTM, QEMU, Podman, Tart |

The absence of UTM and QEMU is not a problem: neither needs to be installed for the
recommended path.

## 3. Why Lima with the `vz` backend

| Option | Verdict |
| --- | --- |
| **Lima + `vmType: vz`** | **Chosen.** Already installed. Uses Apple's Virtualization.framework, so an aarch64 Fedora guest runs with hardware acceleration. Defined in a text file that lives in this repository, so the environment is reproducible and reviewable. Headless, which suits a build machine. |
| UTM | Perfectly good GUI alternative if you prefer to *see* the desktop while testing KDE builds. Would need installing (`brew install --cask utm`) and has no repo-tracked definition, so it is a companion, not the primary. |
| QEMU emulation | Only needed to run a *foreign* architecture (e.g. x86_64 on this Mac). Emulated builds are roughly an order of magnitude slower and would not fit the memory budget. Avoid until Milestone 9. |
| Colima | Container-oriented and currently stopped. It also starts a VM, so running it alongside the build VM would oversubscribe 16 GB. Do not run both at once. |

## 4. Resource budget (16 GiB)

| Consumer | Allocation |
| --- | --- |
| macOS and normal desktop applications | ~7–8 GiB |
| OpenQOS build VM | **8 GiB**, 6 CPUs, 120 GiB sparse disk |

The guest disk is sparse: 120 GiB is the ceiling, and only what is used is consumed on
the host. Realistic usage is roughly 20–25 GiB (see [Disk budget](#disk-budget)).

If macOS starts swapping while a build runs, reduce the VM to 6 GiB rather than
reducing the CPU count — image composition is more memory-bound than CPU-bound.

## 5. Step 1: validate the VM definition

**macOS**, from the repository root:

```sh
limactl validate tools/lima/openqos-dev.yaml
```

Expected output:

```
time="..." level=info msg="\"tools/lima/openqos-dev.yaml\": OK"
```

This only parses the YAML. It creates nothing and downloads nothing. It has been
run successfully on this machine.

## 6. Step 2: create and start the VM

**macOS**:

```sh
limactl start --name=openqos-dev tools/lima/openqos-dev.yaml
```

Expected behaviour:

1. Lima downloads `Fedora-Cloud-Base-Generic-44-1.7.aarch64.qcow2` — about **504 MiB**
   — and verifies its SHA-256 against the digest pinned in the YAML. A mismatch
   aborts the start.
2. The VM boots, and Lima waits for SSH.
3. The provisioning script runs once as root and installs the build tooling. This
   downloads roughly 1–2 GiB of RPMs and takes several minutes on a typical
   connection.
4. It finishes with `OpenQOS build dependencies installed.` and prints:

```
INFO[....] READY. Run `lima` to open the shell.
```

If step 1 is interrupted, re-run the same command; Lima resumes rather than starting
over. Nothing is written outside `~/.lima/openqos-dev`.

## 7. Step 3: verify the guest

**Fedora** — open a shell first:

```sh
limactl shell openqos-dev        # macOS
```

Then, inside the VM:

```sh
uname -m                     # expect: aarch64
cat /etc/fedora-release      # expect: Fedora release 44 (Forty Four)
cat /etc/os-release | grep -E '^(NAME|VERSION)='   # expect: Fedora Linux / 44
nproc                        # expect: 6
free -g | awk 'NR==2{print $2" GiB RAM"}'          # expect: 7 GiB RAM
df -h / | tail -1            # expect: / on a 120G filesystem, ~118G available
ping -c1 -W2 download.fedoraproject.org >/dev/null && echo "network OK"
```

`uname -m` returning `aarch64` is the important one: it confirms the build
architecture matches the target architecture, so no emulation is involved.

On memory: `free -g` reports **7 GiB**, not 8. The VM is configured with `8GiB` and
Lima's report reflects that, but the guest sees `MemTotal: 8098136 kB` (~7.7 GiB)
because firmware reserves a small amount. That is expected, not a misconfiguration.

## 8. Step 4: verify the build tooling

**Fedora**:

```sh
for p in kiwi-ng livemedia-creator mkksiso ksvalidator rpmbuild createrepo_c; do
  printf '%-20s ' "$p"; command -v "$p" || echo MISSING
done
```

Expected: all six resolve to a path under `/usr/bin`. `kiwi-ng` is the KIWI
entry point that `kiwi-cli` installs.

Then confirm the host requirements for ISO media are satisfied:

```sh
rpm -q kiwi-cli kiwi-systemdeps-iso-media dracut-kiwi-live distribution-gpg-keys lorax
```

Expected: five package names printed with no `not installed` lines.

And that Fedora's release signing keys are available for verification:

```sh
rpm -ql distribution-gpg-keys | grep -c 'RPM-GPG-KEY-fedora-4[34]'
```

Expected: a non-zero count.

### Disk budget

| Item | Approx. size |
| --- | --- |
| Fedora Cloud base image | 0.5 GiB |
| Build tooling and system | 2–3 GiB |
| DNF package cache | up to 5 GiB |
| KIWI build work directory | 8–12 GiB |
| Finished live ISO | ~3 GiB |

Measured reference: Fedora 44's own `Fedora-KDE-Desktop-Live-44-1.7.aarch64.iso` is
2.91 GiB. Plan for ~25 GiB of guest usage, comfortably inside the 120 GiB ceiling.
Keep at least 20 GiB free on macOS for copying artefacts out for testing.

## 9. Day-to-day workflow

```sh
# macOS — edit files and commit as usual in this repository
cd /Users/miroslav/Documents/workspace/OpenQOS/OpenQOS
git status

# macOS — get a shell in the build environment
limactl shell openqos-dev

# Fedora — the checkout is mounted at the same path, so builds read the same tree
cd /Users/miroslav/Documents/workspace/OpenQOS/OpenQOS
ls

# macOS — reclaim memory when you are not building
limactl stop openqos-dev
```

Because the checkout is a writable mount, there is no copy or push/pull step: save a
file on macOS and the change is already visible in the VM.

Caveat: mounts do not survive a guest reboot cleanly in all cases. If the checkout
looks empty inside the VM, run `limactl stop openqos-dev && limactl start openqos-dev`.

### Seeing what the desktop actually looks like

Nothing inside this VM can draw: there is no GPU and no `/dev/dri`, so Plasma, Plymouth
and the login manager render into nothing. To look at an image, boot it under QEMU,
which emulates a virtio GPU, and read the guest's screen:

```sh
# Fedora, inside the development VM
sudo tests/screenshot-image.sh kiwi/build/OpenQOS-KDE-Disk-Test/OpenQOS.aarch64-44.qcow2

# frames land as PPM files, which convert to PNG with any image tool
find /var/tmp/openqos-screenshot/shots -name '*.ppm'
```

Notes that save time:

* **It is slow.** There is no KVM here, so QEMU emulates, and a KDE desktop takes
  minutes to reach its login screen rather than seconds. Raise the timeout rather than
  concluding that something is broken.
* **Watch the framebuffer, not the serial console.** systemd stops logging to the
  serial console once the console moves, and a graphical greeter writes nothing to it
  at all, so the serial log goes quiet long before the screen is interesting.
* The helper stops early once the screen is showing an image rather than text. It can
  tell the difference because a flat screen, a text console and a wallpaper compress
  to very different sizes — file size alone says nothing, since a PPM is
  `width*height*3` bytes whatever it contains.
* The image is copied before booting. A boot writes to its disk and a built artefact
  must not change because someone looked at it.

### Installing from media, and testing the installer

`tests/install-test.sh` installs OpenQOS from its own media, unattended, and checks
what comes out. It needs root, because it attaches loop devices and mounts
filesystems read-only:

```bash
sudo tests/install-test.sh            # install, then examine the installed system
sudo tests/install-test.sh --boot     # and then boot it
```

It never edits the medium. Instead it builds a 16 MiB disk labelled `OEMDRV`
holding a kickstart that `%include`s the shipped `kickstart/openqos.ks` and adds
nothing but a `reboot`, attaches it as a second disk, and lets the media notice it —
which is both how an unattended installation is normally requested and a check that
the shipped file is what the installer used. Results are printed one line per
check, and left in `/var/tmp/openqos-install-test` (`RESULT.txt` plus the serial
consoles of both machines).

Editing `kickstart/openqos.ks` is cheap to check before a build: `ksvalidator -v F44
kickstart/openqos.ks` parses it against Fedora 44's command set and prints nothing
when it is clean. The package is called `pykickstart` in Fedora 44 — it was
`python3-pykickstart` before.

The installer itself is covered in
[architecture.md §4.7](architecture.md#47-the-installer).

## 10. Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `limactl start` hangs on "Installing rosetta" | Not applicable here — Rosetta is deliberately not enabled; the VM is native aarch64. |
| Passwordless SSH failed / VSOCK error | `ssh.overVsock` must be `false` with Fedora 43/44 (SELinux denial on vsock). Already set in the YAML. |
| Provisioning fails on a package name | The Fedora repository has changed since 2026-10-12. Find the current name with `dnf search <name>` in the VM and update the `provision` block. |
| Build dies with an out-of-memory error | Lower the VM to `memory: "6GiB"`, or stop other applications. Do not raise it above 8 GiB on a 16 GiB host. |
| `mkfs.erofs: failed to commit fragment ... [Error 5] Input/output error` | Not a disk-full or file-corruption error. `mkfs.erofs` buffers through `$TMPDIR`, and `/tmp` is a tmpfs of half the guest's RAM (3.9 GiB here) while a live filesystem compresses to about 3 GiB. `scripts/build-image.sh` sets `TMPDIR=/var/tmp`; if you invoke `kiwi-ng` directly, do the same. |
| `Requested image type iso not supported` with `dracut: Invalid tmpdir` | `$TMPDIR` points somewhere that does not exist inside the image chroot, where KIWI runs `dracut` for its ISO support check. Use a path valid in both contexts, such as `/var/tmp`. |
| `file /usr/lib/os-release conflicts between attempted installs of openqos-release and fedora-release-identity-<flavour>` | A Fedora identity flavour was installed alongside ours. Either the `fedora-release-identity-*` ignore is missing from a packages section — KIWI reads `<ignore>` per section *type*, so the `image` and `bootstrap` sections each need one — or `openqos-release` no longer provides the version `fedora-release-common` asks for. `scripts/build-packages.sh` checks the version and tells you which numbers to set; see [architecture.md §5.1](architecture.md#51-how-openqos-declares-its-identity). |
| `kernel-uki-dtbloader conflicts with kernel-core = <version>` | A profile activated both boot profiles. On aarch64 `BootCore` installs `kernel-core` while `BootCoreLive` installs `kernel-uki-dtbloader`, and the two conflict by design. Live media get `BootCoreLive` through `LiveInstall`, so only disk profiles should require `BootCore`. |
| Live media boot to a dracut prompt instead of a desktop | The kernel command line's `root=live:CDLABEL=<label>` does not match the ISO's volume id. Check both: `xorriso -indev <iso> -pvd_info` for the label, and `/boot/grub2/grub.cfg` inside the ISO for `CDLABEL`. KIWI derives both from the `volid` type attribute, so they should never disagree within a build — if they do, an override is being applied somewhere else. |
| `package X matches only excluded packages` | An `<ignore>` names a package that an active profile explicitly installs. `<ignore>` applies to packages pulled in transitively; removing one that is requested by name makes the transaction unsatisfiable, and needs a replacement package instead. |
| `RELAXNG_ERR_CONTENTVALID: Element user failed to validate content` | KIWI's schema makes `password` a **required** attribute of `<user>`, so it cannot simply be omitted. Use `password="!" pwdformat="encrypted"` for an account that must not be loggable: an encrypted value is passed through verbatim and `!` is the shadow marker for a locked account. |
| `/etc/shadow` contains a `$1$` hash | KIWI's `<user pwdformat="plain">` hashes with the C library default, which is MD5. There is no stronger KIWI option. Set the credential in `kiwi/config.sh` with `chpasswd --crypt-method YESCRYPT`, which the script's own assertions enforce. See [architecture.md §6.1](architecture.md#61-password-hashing). |
| `cfi.pflash01 device ... requires 67108864 bytes, pflash0 block backend provides 3145728` | QEMU 10 requires each pflash unit to be the full 64 MB the `virt` machine declares, so Fedora's 3 MB `/usr/share/edk2/aarch64/QEMU_EFI.fd` is rejected. Use the pre-padded `QEMU_EFI-pflash.qcow2` and `QEMU_EFI-qemuvars-pflash.qcow2` instead. `tests/screenshot-image.sh` already does. |
| `-vnc 127.0.0.1:9: Failed to find an available port` or `Could not set up host forwarding rule 'tcp::2222-:22'` | A previous guest is still running, or Lima already forwards that port. Find it with `pgrep -af qemu-system-aarch64` and stop it with `kill <pid>` — never a name-based kill, which matches your own command line and takes the session with it. `VNC_DISPLAY` and `SSH_PORT` override the defaults. |
| macOS becomes unresponsive during a build | Expected to a degree. Lower `cpus` to 4 to leave more for the UI. |
| Everything is slow | Check that `vmType` is `vz` and not `qemu`. `limactl info openqos-dev` shows the driver. |
| `KiwiTypeNotFound: Build type 'oem' not found for applied profiles` on a live profile | `scripts/build-image.sh` defaults to `--type oem`, which is the disk-image type. Live media need `--type iso`; without it KIWI looks for a type that no active profile defines. |
| Packages build, but every script in the RPM has mode 0600 | `rpmbuild` writing into the repository through the macOS mount loses the executable bit, silently. The build tree must be on the guest's own disk: `scripts/build-packages.sh` uses `/var/tmp/openqos-packages` (`OPENQOS_PACKAGE_BUILD_ROOT` overrides it). Check with `rpm -qp --queryformat '[%{FILEMODES:octal} %{FILENAMES}\n]' <rpm>`. |
| `/dev/null: Permission denied` from every login shell, or `line N: /dev/fd/63: No such file or directory` in a build | A KIWI build was killed part-way through, leaving its chroot's bind mounts behind; the next `rm -rf` of the scratch directory then ran over the guest's real `/dev` and deleted device nodes. Unmount anything under the scratch directory (`mount \| awk '$3 ~ /var\/tmp\/openqos-build/ {print $3}'`), then restart the VM: `/dev` is devtmpfs and systemd-tmpfiles restores `/dev/fd` and the rest at boot. Do not interrupt a build — pass a fresh `--output` instead, which avoids `--clean` altogether. |

## 11. Verification log

Milestone 2 was executed on 2026-10-12 and the results below were observed directly
in the guest, not inferred from the fact that a command exited 0.

| Check | Observed |
| --- | --- |
| `limactl validate` | `OK` |
| VM start | `READY. Run 'limactl shell openqos-dev' to open the shell.` |
| Image digest | Verified by Lima on download; no mismatch reported |
| Driver | `Starting the instance "openqos-dev" with internal VM driver "vz"` |
| `uname -m` | `aarch64` |
| `/etc/fedora-release` | `Fedora release 44 (Forty Four)` |
| `/etc/os-release` | `NAME="Fedora Linux"`, `VERSION="44 (Cloud Edition)"` |
| `nproc` | 6 |
| `MemTotal` | `8098136 kB` (7.7 GiB of the 8 GiB requested) |
| Root filesystem | `/dev/vda2  120G  2.2G  118G  2% /` |
| Outbound network | `HTTP/2 302` from `download.fedoraproject.org` |
| Repo mount | `virtiofs` at the checkout path, mounted `rw` |
| Home mount | `virtiofs` at `/Users/miroslav`, mounted `ro` |

Tool versions actually installed (these come from Fedora **updates**, so they are
newer than the Fedora 44 GA versions):

| Tool | Version |
| --- | --- |
| `kiwi-ng` | 11.1.1 |
| `kiwi-cli` | 11.1.1-2.fc44 |
| `kiwi-systemdeps-iso-media` | 11.1.1-2.fc44 |
| `dracut-kiwi-live` | 11.1.1-2.fc44 |
| `lorax` | 44.7-1.fc44 |
| `distribution-gpg-keys` | 1.123-1.fc44 |
| Fedora release keys present | 8 |

Also confirmed working inside the guest: `keepcache=1` was written to
`/etc/dnf/dnf.conf`, and `kiwi-ng`, `livemedia-creator`, `mkksiso`, `ksvalidator`,
`rpmbuild` and `createrepo_c` all resolve under `/usr/bin`.

### Still not verified

* **No image has been built.** That is Milestone 4.
* The provisioning output (`OpenQOS build dependencies installed.`) was not echoed
  in `limactl start`'s console output, although the packages were installed. Treat
  the `rpm -q` check in [Step 4](#8-step-4-verify-the-build-tooling) as the
  authoritative verification, not the message.
* The 120 GiB guest disk is sparse, as designed: `du -sh ~/.lima/openqos-dev` reports
  **3.2 GiB** of real host usage after provisioning. The 8 GiB of guest RAM leaves
  macOS at 43% free memory. Neither figure has been measured *during* a full image
  build yet — that happens in Milestone 4.

## 12. Notes on Apple Silicon

Running OpenQOS *inside a VM on this Mac* works, and that is the whole development
target for now. Booting OpenQOS **natively on the Mac's own hardware** is a different
problem that generic `aarch64` images do not solve, and it is not promised anywhere
in this project. See [architecture.md §8](architecture.md#8-apple-silicon-caveat).
