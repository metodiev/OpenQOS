# Installing OpenQOS

This package is the installer integration on OpenQOS installation media: the
launcher, the definition of what an installation produces, and the pieces needed
to install without a human present.

The installer itself is Anaconda, Fedora's. What OpenQOS adds is a kickstart, and
the launcher that hands it to Anaconda — because Anaconda's own live-install mode
ignores kickstarts, and an installation defined by nothing in a repository is an
installation nobody can review.

## Installing from the live desktop

Click **Install OpenQOS** on the desktop. Anaconda's Web UI opens in a browser,
with storage already configured from `openqos.ks`, and asks for anything the
kickstart deliberately leaves open (the timezone, and any change to the storage
layout). The account is created after the first boot by Plasma Setup, which is
also how a machine flashed from a disk image behaves.

## Installing without a human

Boot the media with `inst.ks=` on the kernel command line:

```
inst.ks=/usr/share/openqos/kickstart/openqos.ks
```

The installation then runs before the desktop starts, unattended, and reports to
the console and the journal. `inst.ks=hd:LABEL=OEMDRV:/ks.cfg` reads a kickstart
from another disk or a USB stick instead; a disk labelled `OEMDRV` is ignored as
an installation target, so the stick cannot be wiped by the installation it
describes. A kickstart read this way replaces the one below, so it has to
describe the payload itself — see `openqos.ks` for the `liveimg` line.

Once an unattended installation finishes, Anaconda exits; power the machine off
(and remove the medium). Add `reboot` or `shutdown` to a kickstart to have it do
that itself.

## What is where

| Path | What it is |
| --- | --- |
| `/usr/share/openqos/kickstart/openqos.ks` | The installation definition: storage, bootloader, accounts, and the assertions that refuse to finish with a system nobody can log into. |
| `/usr/bin/openqos-install` | What the desktop entry runs. Refuses arguments, asks pkexec for privilege, and passes the kickstart above. |
| `/usr/bin/openqos-install-root` | The privileged half. Runs `/usr/libexec/anaconda/webui-desktop` and `anaconda --graphical --ks=...`. |
| `/usr/libexec/openqos/openqos-autoinstall` | The unattended path, started by `openqos-autoinstall.service` when `inst.ks=` is on the command line. |
| `/usr/libexec/openqos/openqos-install-setup` | Puts the launcher icon on the live desktop and takes Anaconda's Fedora-named one away. |
| `/etc/anaconda/profile.d/openqos.conf` | The installer's product profile: BTRFS with zstd:1, `\EFI\openqos`, no geolocation, and account creation left to the first-boot wizard. Installed by the images, not by this package. |

## Known limitations

* `http://`, `https://` and `nfs:` kickstarts are not fetched. Only a local path,
  a `file://` URL or a `hd:` device is read. Fetching over the network is what
  Anaconda's dracut module does on Fedora's own installation media, and OpenQOS
  live media do not carry it.
* The kickstart expects a single installation target. If more than one candidate
  disk is present, an unattended installation stops rather than guess.
* The launcher is only on live media. It is also harmless on a system installed
  from them, where it exits with a message saying the medium is missing.
