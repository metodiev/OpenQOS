#!/bin/bash
#
# Install OpenQOS from its own installation media, unattended, and check what
# comes out.
#
# Run inside the Fedora development VM, as root (it attaches loop devices and
# mounts filesystems read-only):
#
#   sudo tests/install-test.sh
#   sudo tests/install-test.sh --iso path/to.iso --boot
#
# What it does, and why each step is the way it is:
#
#   1. A disk labelled OEMDRV is built holding a kickstart, and attached to the
#      virtual machine as a second disk. That is Anaconda's own convention for
#      unattended installations and it needs no boot option: OpenQOS media notice
#      the disk and install. Editing the medium is therefore not necessary, and
#      the medium under test is byte-for-byte the one that ships.
#
#      The kickstart on it includes the shipped one and adds nothing but a
#      `reboot`, so the test cannot pass while `kickstart/openqos.ks` is broken.
#
#   2. The machine is booted with UEFI firmware and a blank target disk, and the
#      installation runs before the desktop starts.
#
#   3. When the installation's own %post assertions have reported, the machine is
#      powered off and the target disk is examined from outside — attached
#      read-only — rather than trusting anything the installer said about itself.
#
#   4. With --boot, the target disk is then started in a second virtual machine,
#      with the firmware variables the installation wrote, which is the only way
#      to know it boots.
#
# The default kickstart expects one installation target, and the OEMDRV disk is
# ignored by Anaconda as a target by design, so the target has to be the only
# other disk present.
#
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

iso="${repo_root}/kiwi/build/OpenQOS-KDE-Live/OpenQOS.aarch64-44.iso"
work="${OPENQOS_INSTALL_TEST_WORK:-/var/tmp/openqos-install-test}"
vnc_display="${VNC_DISPLAY:-8}"
target_size="20G"
boot_after=false
keep=false
probe_storage=false
install_timeout=$((90 * 60))
boot_timeout=$((12 * 60))

readonly uefi="/usr/share/edk2/aarch64/QEMU_EFI-pflash.qcow2"
readonly uefi_vars="/usr/share/edk2/aarch64/QEMU_EFI-qemuvars-pflash.qcow2"

usage() {
	cat >&2 <<-EOF
		usage: sudo tests/install-test.sh [options]

		  --iso PATH   Installation media to test
		               (default: kiwi/build/OpenQOS-KDE-Live/OpenQOS.aarch64-44.iso)
		  --work DIR   Scratch directory (default: ${work})
		  --boot       Also boot the installed system afterwards
		  --probe-storage
		               Test a candidate storage section here rather than the
		               one in the shipped kickstart/openqos.ks
		  --keep       Keep the scratch directory if it already exists
		  -h | --help
	EOF
	exit "${1:-1}"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--iso) iso="${2:?--iso needs a value}"; shift 2 ;;
	--work) work="${2:?--work needs a value}"; shift 2 ;;
	--boot) boot_after=true; shift ;;
	--probe-storage) probe_storage=true; shift ;;
	--keep) keep=true; shift ;;
	-h | --help) usage 0 ;;
	*) echo "error: unknown argument: $1" >&2; usage ;;
	esac
done

if [[ "${EUID}" -ne 0 ]]; then
	echo "error: this script attaches loop devices and mounts filesystems;" >&2
	echo "       run it with sudo." >&2
	exit 1
fi

# These exist in the Fedora development VM and not on macOS (where Homebrew's qemu
# provides qemu-img and qemu-system-aarch64 but no mke2fs). Failing on the first
# missing tool would be a confusing way to learn that the script was run on the
# wrong side, so the message says which side it belongs on.
for tool in qemu-system-aarch64 qemu-img qemu-nbd python3 mke2fs blkid lsblk; do
	if ! command -v "${tool}" >/dev/null; then
		echo "error: ${tool} is required but not installed." >&2
		echo "       Run this inside the Fedora development VM:" >&2
		echo "         limactl shell openqos-dev -- sudo tests/install-test.sh --boot" >&2
		exit 1
	fi
done

# /dev/nbdN exists only once the module is loaded, and nothing loads it for us.
if ! ls /dev/nbd0 >/dev/null 2>&1; then
	modprobe nbd max_part=8 2>/dev/null || {
		echo "error: the nbd module is not available, so the installed system" >&2
		echo "       cannot be attached read-only afterwards." >&2
		exit 1
	}
fi

[[ -f "${iso}" ]] || {
	echo "error: no installation media at ${iso}" >&2
	exit 1
}
for firmware in "${uefi}" "${uefi_vars}"; do
	[[ -f "${firmware}" ]] || {
		echo "error: ${firmware} is missing; install edk2-aarch64." >&2
		exit 1
	}
done

if [[ -e "${work}" ]] && [[ -n "$(ls -A -- "${work}" 2>/dev/null || true)" ]]; then
	if [[ "${keep}" == true ]]; then
		echo "error: ${work} exists and --keep was given; it would be reused mid-test." >&2
		exit 1
	fi
	echo "Replacing existing scratch directory: ${work}"
	rm -rf -- "${work}"
fi
mkdir -p -- "${work}"

# One result line per check, so a failure says which promise broke.
checks_failed=0
check() {
	local what="$1" expected="$2" actual="$3"
	if [[ "${actual}" == "${expected}" ]]; then
		printf '  ok    %-46s %s\n' "${what}" "${actual}"
	else
		printf '  FAIL  %-46s %s (expected %s)\n' "${what}" "${actual}" "${expected}"
		checks_failed=$((checks_failed + 1))
	fi
}

# --------------------------------------------------------------------------
# 1. The OEMDRV kickstart disk and the blank target.
# --------------------------------------------------------------------------
echo "== preparing the medium for an unattended installation"
ks_dir="${work}/oemdrv"
mkdir -p -- "${ks_dir}"
if [[ "${probe_storage}" == true ]]; then
	echo "  kickstart:  a candidate storage section, NOT the shipped one"
	cat > "${ks_dir}/ks.cfg" <<-'EOF'
# Storage probe: the shipped kickstart's own directives, but with Anaconda's
# automatic btrfs layout in place of the explicit partition commands.
#version=DEVEL
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts=us
timezone UTC --utc
selinux --enforcing
firewall --enabled
services --disabled=livesys,livesys-late
zerombr
clearpart --all --initlabel --disklabel=gpt
autopart --type=btrfs --fstype=btrfs
bootloader --timeout=5 --append="no_timer_check console=tty1 console=ttyAMA0,115200n8"
rootpw --lock
%pre --interpreter=/bin/bash
%include /usr/share/openqos/../openqos/ks-probe-noop
%end
shutdown
EOF
	# %include of a missing file would be an error; keep the probe free of it.
	sed -i '/ks-probe-noop/d;/^%pre --interpreter/d;/^%end$/d' "${ks_dir}/ks.cfg"
else
cat > "${ks_dir}/ks.cfg" <<-'EOF'
# Read by OpenQOS media because this disk is labelled OEMDRV. The installation
# definition under test is the shipped one, included whole.
%include /usr/share/openqos/kickstart/openqos.ks

# %pre runs in the installation environment — the live session — before the
# payload, so this is the only place a kickstart can watch Anaconda from outside
# it. Anaconda writes its progress and its reasons for stopping to
# /tmp/anaconda.log inside the live session, and nothing else will ever see that
# file: the session ends, and with it the file, whether the installation worked or
# not. Copying it to the serial console is what makes a failed installation
# diagnosable instead of merely a timeout.
# The tailer has to be started as a unit rather than as a background job of this
# script: Anaconda waits for its %pre script's output to close, and a background
# job keeps that pipe open, so %pre never returns and the installation never
# starts. That failure looks exactly like a hang, and it happened the first time
# this was tried.
%pre --interpreter=/bin/bash
systemd-run --unit=openqos-anaconda-log --collect \
  --property=StandardOutput=append:/dev/console \
  /bin/sh -c 'while [ ! -f /tmp/anaconda.log ]; do sleep 1; done; exec tail -F /tmp/anaconda.log'
%end

# The harness returns when the machine stops, so an unattended installation should
# end by stopping it rather than by reboot.
shutdown
EOF
fi

# mke2fs -d populates the image without needing a loop mount or root.
truncate -s 16M "${work}/oemdrv.img"
mke2fs -q -t ext4 -L OEMDRV -d "${ks_dir}" -F "${work}/oemdrv.img"

qemu-img create -q -f qcow2 "${work}/target.qcow2" "${target_size}"
cp -- "${uefi}" "${work}/QEMU_EFI.qcow2"
cp -- "${uefi_vars}" "${work}/QEMU_VARS.qcow2"
echo "  medium:     ${iso}"
echo "  target:     ${work}/target.qcow2 (${target_size})"
echo "  kickstart:  OEMDRV disk, %include of the shipped openqos.ks + reboot"

start_vm() {
	local serial_path="$1"
	local monitor_path="$2"
	shift 2
	qemu-system-aarch64 \
		-M virt -cpu max -smp 4 -m 4096 \
		-drive "if=pflash,format=qcow2,readonly=on,file=${work}/QEMU_EFI.qcow2" \
		-drive "if=pflash,format=qcow2,file=${work}/QEMU_VARS.qcow2" \
		-device virtio-gpu-pci \
		-device virtio-keyboard-pci \
		-device virtio-tablet-pci \
		-netdev user,id=n0 \
		-device virtio-net-pci,netdev=n0 \
		-vnc "127.0.0.1:${vnc_display}" \
		-serial "file:${serial_path}" \
		-monitor "unix:${monitor_path},server,nowait" \
		"$@" \
		> "${work}/qemu.out" 2>&1 &
	echo $!
}

# Monitor commands (power off, screen capture) go over a unix socket, the same
# channel the screenshot tool uses.
monitor_command() {
	local sock="$1" command="$2"
	python3 - "${sock}" "${command}" <<-'PY'
	import socket, sys, time
	sock_path, command = sys.argv[1], sys.argv[2]
	connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
	connection.settimeout(10)
	connection.connect(sock_path)
	time.sleep(0.3)
	connection.recv(4096)
	connection.sendall((command + "\n").encode())
	time.sleep(0.5)
	connection.close()
	PY
}

wait_for_log() {
	local log="$1" pattern="$2" timeout="$3"
	local waited=0
	while [[ "${waited}" -lt "${timeout}" ]]; do
		if grep -qF -- "${pattern}" "${log}" 2>/dev/null; then
			return 0
		fi
		sleep 10
		waited=$((waited + 10))
		printf '  [%4ds] waiting for: %s\n' "${waited}" "${pattern}"
	done
	return 1
}

power_off() {
	local pid="$1"
	local monitor_path="$2"
	monitor_command "${monitor_path}" "system_powerdown" || true
	for _ in $(seq 1 24); do
		kill -0 "${pid}" 2>/dev/null || return 0
		sleep 5
	done
	echo "  the machine did not power off; stopping it" >&2
	kill -TERM "${pid}" 2>/dev/null || true
	wait "${pid}" 2>/dev/null || true
}

# --------------------------------------------------------------------------
# 2. Install, unattended, from the media being tested.
# --------------------------------------------------------------------------
echo
echo "== installing (this takes tens of minutes under emulation)"
serial_log="${work}/serial-install.log"
monitor_path="${work}/monitor-install.sock"
vm_pid="$(start_vm "${serial_log}" "${monitor_path}" \
	-drive "if=virtio,format=raw,readonly=on,file=${iso}" \
	-drive "if=virtio,format=qcow2,file=${work}/target.qcow2" \
	-drive "if=virtio,format=raw,file=${work}/oemdrv.img")"
echo "  virtual machine pid ${vm_pid}, console in ${serial_log}"

# `openqos.ks` prints this from %post, inside the installed system, at the end of
# the installation: the same assertion that guards the disk images.
installation_marker="openqos.ks: the installed system is enterable"
waited=0
install_ok=false
while [[ "${waited}" -lt "${install_timeout}" ]]; do
	if grep -qF -- "${installation_marker}" "${serial_log}" 2>/dev/null; then
		install_ok=true
		break
	fi
	# Anaconda's own log is on the console now, so a stop is visible as it
	# happens rather than as a timeout. The first match is enough to say the
	# installation did not happen; the log below it says why.
	if grep -qE "Traceback \(most recent call last\)|Anaconda failed|Anaconda is unable to|KickstartError|PayloadInstallationError|StorageError|not enough space" "${serial_log}" 2>/dev/null; then
		echo "  FAIL  Anaconda reported an error (see ${serial_log})" >&2
		break
	fi
	if ! kill -0 "${vm_pid}" 2>/dev/null; then
		echo "  the machine stopped before reporting completion" >&2
		break
	fi
	sleep 10
	waited=$((waited + 10))
	if [[ $((waited % 300)) -eq 0 ]]; then
		printf '  [%4ds] installing...\n' "${waited}"
	fi
done

if [[ "${install_ok}" == true ]]; then
	echo "  installation reported completion"
	sleep 60
else
	echo "  FAIL  the installation did not report completion" >&2
	grep -aE "Traceback|Error|error|anaconda: " "${serial_log}" 2>/dev/null | tail -20 >&2
fi
if kill -0 "${vm_pid}" 2>/dev/null; then
	power_off "${vm_pid}" "${monitor_path}"
fi
if [[ "${install_ok}" != true ]]; then
	exit 1
fi
grep -F -- "${installation_marker}" "${serial_log}" | tail -1
power_off "${vm_pid}" "${monitor_path}"

# --------------------------------------------------------------------------
# 3. Examine the installed system from outside.
# --------------------------------------------------------------------------
echo
echo "== examining the installed system (read-only, from outside)"

nbd_device=""
for candidate in /dev/nbd0 /dev/nbd1 /dev/nbd2; do
	if ! lsblk -no NAME "${candidate}" >/dev/null 2>&1; then
		continue
	fi
	if [[ -z "$(lsblk -no NAME "${candidate}" 2>/dev/null | tail -n +2)" ]]; then
		nbd_device="${candidate}"
		break
	fi
done
if [[ -z "${nbd_device}" ]]; then
	echo "error: no free /dev/nbdN device for attaching the target disk" >&2
	exit 1
fi

qemu-nbd --connect="${nbd_device}" --read-only "${work}/target.qcow2"
for _ in $(seq 1 10); do
	[[ -n "$(lsblk -no NAME "${nbd_device}" 2>/dev/null | tail -n +2)" ]] && break
	sleep 1
done

root_partition=""
esp_partition=""
for partition in "${nbd_device}"p*; do
	[[ -b "${partition}" ]] || continue
	case "$(blkid -o value -s TYPE "${partition}" 2>/dev/null || true)" in
	btrfs) root_partition="${partition}" ;;
	vfat) esp_partition="${partition}" ;;
	esac
done
if [[ -z "${root_partition}" ]] || [[ -z "${esp_partition}" ]]; then
	echo "error: the target disk has no btrfs root and vfat ESP:" >&2
	lsblk -o NAME,SIZE,FSTYPE,LABEL "${nbd_device}" >&2
	exit 1
fi
echo "  target layout: ${esp_partition} (ESP), ${root_partition} (btrfs)"

root_mount="${work}/root"
esp_mount="${work}/esp"
mkdir -p -- "${root_mount}" "${esp_mount}"
mount -o ro "${root_partition}" "${root_mount}"

btrfs_label="$(blkid -o value -s LABEL "${root_partition}" || true)"
check "the btrfs volume is labelled" "openqos" "${btrfs_label}"

subvolumes="$(btrfs subvolume list "${root_mount}" 2>/dev/null | awk '{print $NF}' | sort | tr '\n' ' ' | sed 's/ $//')"
check "subvolumes are root boot home var" "boot home root var" "${subvolumes}"

os_release_id="$(sed -n 's/^ID=//p' "${root_mount}/etc/os-release")"
check "os-release identifies the system" "openqos" "${os_release_id}"
os_release_name="$(sed -n 's/^NAME=//p' "${root_mount}/etc/os-release" | tr -d '"')"
check "os-release names the product" "OpenQOS Linux" "${os_release_name}"

identity_owner="$(rpm --root="${root_mount}" -q --qf '%{NAME}' --whatprovides /usr/lib/os-release 2>/dev/null || true)"
check "os-release is owned by" "openqos-release" "${identity_owner}"

flavours="$(rpm --root="${root_mount}" -qa --qf '%{NAME}\n' 'fedora-release-identity-*' 2>/dev/null | tr '\n' ' ' || true)"
check "no Fedora flavour is installed" "" "${flavours// /}"

wizard="no"
if [[ -e "${root_mount}/etc/systemd/system/multi-user.target.wants/plasma-setup.service" ]]; then
	wizard="yes"
fi
check "the first-boot wizard will run" "yes" "${wizard}"

usable="$(awk -F: '$2 !~ /^[!*]/ { print $1 }' "${root_mount}/etc/shadow" 2>/dev/null | tr '\n' ' ' || true)"
check "no usable account was created" "" "${usable// /}"

installed_cmdline="$(cat "${root_mount}/etc/kernel/cmdline" 2>/dev/null || true)"
if [[ "${installed_cmdline}" == *rd.live.image* ]]; then
	check "the installed cmdline is not a live one" "no rd.live.image" "rd.live.image present"
else
	check "the installed cmdline is not a live one" "no rd.live.image" "no rd.live.image"
fi
if [[ "${installed_cmdline}" == *console=ttyAMA0* ]]; then
	check "the installed cmdline carries our arguments" "console=ttyAMA0" "console=ttyAMA0"
else
	check "the installed cmdline carries our arguments" "console=ttyAMA0" "${installed_cmdline:-none}"
fi

if [[ -f "${root_mount}/usr/share/openqos/kickstart/openqos.ks" ]]; then
	check "the installed system has the shipped kickstart" "present" "present"
else
	check "the installed system has the shipped kickstart" "present" "missing"
fi

livesys_enabled="no"
if [[ -e "${root_mount}/etc/systemd/system/multi-user.target.wants/livesys.service" ]]; then
	livesys_enabled="yes"
fi
check "live-only services are not enabled" "no" "${livesys_enabled}"

mount -o ro "${esp_partition}" "${esp_mount}"
if [[ -d "${esp_mount}/EFI/openqos" ]]; then
	check "the ESP is \\EFI\\openqos" "present" "present"
else
	check "the ESP is \\EFI\\openqos" "present" "$(cd "${esp_mount}/EFI" 2>/dev/null && printf '%s ' * || echo none)"
fi
umount "${esp_mount}"

# The disk the kickstart came from must still be intact: Anaconda ignores
# OEMDRV-labelled disks as installation targets, and clearpart --all would have
# taken it.
oemdrv_mount="${work}/oemdrv-ro"
mkdir -p -- "${oemdrv_mount}"
mount -o ro,loop "${work}/oemdrv.img" "${oemdrv_mount}"
if [[ -f "${oemdrv_mount}/ks.cfg" ]]; then
	check "the kickstart disk was not touched" "ks.cfg present" "ks.cfg present"
else
	check "the kickstart disk was not touched" "ks.cfg present" "ks.cfg gone"
fi
umount "${oemdrv_mount}"

umount "${root_mount}"
cleanup_mounts
trap - EXIT

# --------------------------------------------------------------------------
# 4. Boot it.
# --------------------------------------------------------------------------
boot_result="not attempted"
if [[ "${boot_after}" == true ]]; then
	echo
	echo "== booting the installed system"
	serial_log="${work}/serial-boot.log"
	monitor_path="${work}/monitor-boot.sock"
	vm_pid="$(start_vm "${serial_log}" "${monitor_path}" \
		-drive "if=virtio,format=qcow2,file=${work}/target.qcow2")"
	if wait_for_log "${serial_log}" "Reached target" "$((boot_timeout / 2))"; then
		boot_result="systemd reached a target"
	elif wait_for_log "${serial_log}" "Linux version" "$((boot_timeout / 2))"; then
		boot_result="the kernel started but systemd reported no target in time"
	else
		boot_result="nothing booted"
	fi
	echo "  ${boot_result}"

	# A photograph of the screen, since the first-boot wizard is what makes the
	# installed system usable and it is a graphical claim.
	monitor_command "${monitor_path}" "screendump ${work}/installed-screen.ppm" || true
	sleep 2
	power_off "${vm_pid}" "${monitor_path}"
	check "the installed system boots" "boots" "$([[ "${boot_result}" == "systemd reached a target" ]] && echo boots || echo "${boot_result}")"
fi

# --------------------------------------------------------------------------
# 5. Record what was tested.
# --------------------------------------------------------------------------
cat > "${work}/RESULT.txt" <<EOF
# OpenQOS installation test

media=$(basename -- "${iso}")
media_sha256=$(sha256sum "${iso}" | awk '{print $1}')
target_size=${target_size}
kickstart=OEMDRV disk -> %include /usr/share/openqos/kickstart/openqos.ks + reboot
finished_at=$(date -Is)
checks_failed=${checks_failed}
boot=${boot_result}

## The installation reported

$(grep -F -- "openqos.ks:" "${work}/serial-install.log" | tail -5)
EOF

echo
echo "== result"
cat "${work}/RESULT.txt"
echo
if [[ "${checks_failed}" -gt 0 ]]; then
	echo "FAILED: ${checks_failed} check(s) did not hold. Evidence in ${work}" >&2
	exit 1
fi
echo "All checks held. Evidence in ${work}"
