#version=DEVEL
#
# OpenQOS Linux — the installation definition.
#
# This file is what an OpenQOS installation *is*: which disks, which filesystem
# and subvolumes, which bootloader arguments, which accounts. It is read by
# Anaconda in two situations, and it is deliberately the same file in both:
#
#   1. Interactively, from the live media's "Install OpenQOS" launcher
#      (/usr/bin/openqos-install), which runs Anaconda in graphical mode.
#   2. Unattended, when the live media are booted with `inst.ks=` on the kernel
#      command line (/usr/libexec/openqos/openqos-autoinstall).
#
# Why a kickstart rather than Fedora's own live-install behaviour: Anaconda
# removes this mechanism entirely on live media. `liveinst` starts Anaconda with
# `--liveinst`, and Anaconda's single kickstart resolver,
# `pyanaconda.startup_utils.find_kickstart()`, is gated on `not options.liveinst`
# in both of its branches — a live install therefore parses no kickstart at all.
# That leaves what a Fedora live install produces defined by nothing in the
# repository: storage is whatever automatic partitioning decides that day. The
# layout below is instead fixed, and mirrors kiwi/openqos/disk.xml, so a machine
# installed from media and a machine flashed from a disk image end up the same
# shape. Both aarch64 media and x86_64 media will read this file unchanged; the
# only architecture-specific parts are the bootloader's own, which Anaconda and
# the payload handle.
#
# The payload is the medium itself (`liveimg`): the live filesystem image is
# copied to the target rather than installed from packages. There is no
# %packages section because there is nothing for one to do on this media — what
# is on the medium is what gets installed, including all OpenQOS branding,
# configuration and the first-boot experience. See docs/architecture.md §4.7.

# --- Localisation -----------------------------------------------------------
# Matches the images: en_US.UTF-8, US keyboard, UTC. The graphical installer
# shows the date and time page, so the person installing can change the timezone.
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts=us
timezone UTC --utc

# --- Security ---------------------------------------------------------------
# selinux-policy-targeted is in the base package set and the images run
# enforcing; the installed system must not be weaker than the medium.
selinux --enforcing
firewall --enabled

# livesys and livesys-late create the live account and configure the live
# session. They are already gated on rd.live.image, so they cannot run on an
# installed system, but they have no business being enabled there either.
services --disabled=livesys,livesys-late

# --- Storage ----------------------------------------------------------------
# Mirrors kiwi/openqos/disk.xml:
#
#   * one GPT disk, wiped first
#   * a 100 MiB EFI system partition
#   * one btrfs filesystem labelled "openqos" taking the rest of the disk
#   * root, home and var as separate subvolumes of it
#   * zstd:1 compression, set for the installed system by
#     /etc/anaconda/profile.d/openqos.conf, which is where Anaconda's own
#     automatic partitioning reads it from
#
# The disk is not named. Anaconda ignores disks labelled OEMDRV by design
# (pyanaconda/ui/lib/storage.py), so installation media carrying a kickstart on
# a separate stick still leave a single candidate target.
zerombr
clearpart --all --initlabel --disklabel=gpt
part /boot/efi --fstype=efi --size=100
part btrfs.01 --fstype=btrfs --size=2048 --grow
btrfs / --label=openqos --subvol --name=root btrfs.01
btrfs /home --subvol --name=home btrfs.01
btrfs /var --subvol --name=var btrfs.01

# /boot is not a subvolume of its own, unlike kiwi/openqos/disk.xml. Blivet
# rejected the layout that declared one, with "btrfs subvolume root's first non
# subvolume ancestor must be a btrfs volume" (blivet/devices/btrfs.py:641), the
# storage configuration then failed to save, and Anaconda stopped with
# "Installation Destination" as an incomplete mandatory spoke. /boot lives on the
# root subvolume, which GRUB reads perfectly well.

# --- Bootloader -------------------------------------------------------------
# Same arguments as the disk images, minus systemd.firstboot, which is a
# build-time convenience for the images and would be wrong on a machine someone
# installed. no_timer_check and the serial console are deliberate: aarch64
# virtual machines are the development target.
bootloader --timeout=5 --append="no_timer_check console=tty1 console=ttyAMA0,115200n8"

# --- Accounts ---------------------------------------------------------------
# No usable account, on purpose, and the same choice Fedora's KDE installer
# makes: Plasma Setup, the first-boot wizard, is what creates the user. That is
# how the disk images behave too, so a machine installed from media and a machine
# flashed from an image offer the same first boot. The wizard needs Plasma
# Setup installed and enabled, which the %post below refuses to install a system
# without.
rootpw --lock

%post --erroronfail
# An installed system that nobody can log into is the one failure mode nobody
# notices until they try, and it is reachable by two individually sensible
# decisions: locking root and leaving account creation to the wizard. The same
# invariant is asserted when a disk image is built (kiwi/config.sh, "this desktop
# image is enterable"), because the two artefacts can only stay equivalent if the
# same promise is checked in both places.
#
# This runs inside the installed system (Anaconda chroots here), so every path
# below is the target's.

# 1. The system must identify as OpenQOS, not as the Fedora base it is built
#    from. /usr/lib/os-release is owned by openqos-release, which is what every
#    tool that asks "who am I" reads.
os_release_owner="$(rpm -q --qf '%{NAME}' --whatprovides /usr/lib/os-release)"
if [ "${os_release_owner}" != "openqos-release" ]; then
	echo "openqos.ks: /usr/lib/os-release is owned by '${os_release_owner}'," >&2
	echo "            expected openqos-release. The image would not identify" >&2
	echo "            itself as OpenQOS." >&2
	exit 1
fi

# 2. No Fedora flavour may be installed alongside it: fedora-release-common
#    requires exactly one provider of fedora-release-identity, and a flavour
#    package is what claims the medium is Fedora (see
#    kiwi/OpenQOS.kiwi for the ignore list that prevents this at build time).
flavours="$(rpm -qa --qf '%{NAME}\n' 'fedora-release-identity-*' || true)"
if [ -n "${flavours}" ]; then
	echo "openqos.ks: Fedora flavour packages are installed:" >&2
	echo "${flavours}" | sed 's/^/            /' >&2
	exit 1
fi

# 3. If a display manager is installed, somebody must be able to log in: either
#    an account with a hash, or the first-boot wizard, which must be present,
#    enabled, and not already marked as done.
if [ -e /usr/bin/plasmalogin ]; then
	usable_accounts="$(awk -F: '$2 !~ /^[!*]/ { print $1 }' /etc/shadow)"
	wizard_unit=/usr/lib/systemd/system/plasma-setup.service
	wizard_enabled=/etc/systemd/system/multi-user.target.wants/plasma-setup.service
	first_boot_done=/etc/plasma-setup-done

	enterable=false
	if [ -n "${usable_accounts}" ]; then
		enterable=true
	elif [ -e "${wizard_unit}" ] && [ -e "${wizard_enabled}" ] && [ ! -e "${first_boot_done}" ]; then
		enterable=true
	fi

	if [ "${enterable}" = false ]; then
		echo "openqos.ks: the installed system has a display manager but no" >&2
		echo "            account that could log in, and the first-boot wizard" >&2
		echo "            will not run. Installing this would produce a machine" >&2
		echo "            nobody can log into." >&2
		echo "            Accounts that can log in: ${usable_accounts:-none}" >&2
		echo "            Wizard unit present:     $([ -e "${wizard_unit}" ] && echo yes || echo no)" >&2
		echo "            Wizard enabled:          $([ -e "${wizard_enabled}" ] && echo yes || echo no)" >&2
		echo "            Already marked done:     $([ -e "${first_boot_done}" ] && echo yes || echo no)" >&2
		exit 1
	fi
	echo "openqos.ks: the installed system is enterable: $(
		[ -n "${usable_accounts}" ] && echo "an account with a password exists" || echo "the first-boot wizard will run"
	)"
fi
%end
