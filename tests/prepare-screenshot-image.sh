#!/bin/bash
#
# Prepare a throwaway copy of an OpenQOS image for visual verification.
#
#   sudo tests/prepare-screenshot-image.sh <image.qcow2> <output.qcow2> [--desktop]
#
# Then screenshot it with tests/screenshot-image.sh.
#
# Why this is needed
# ------------------
# A freshly written OpenQOS disk image does not show a login screen. It shows the
# first-boot wizard, because that is what runs before the display manager on first
# boot — verified from inside a running guest, where the login manager had started
# `startplasma-wayland --user plasma-setup --autologin`.
#
# So a plain boot of the artefact can only ever show the wizard. Seeing the login
# screen, or the desktop, means simulating a machine that has already been through
# first boot, and — for the desktop — a user who is already logged in. That is what
# this script prepares, on a *copy*, because a build artefact must not be modified
# by looking at it.
#
# What it does, and why each part is legitimate rather than a cheat:
#
#   /etc/plasma-setup-done      tells the first-boot wizard it has already run. Any
#                               real machine has this after setup.
#   a test user with a password The image deliberately has no usable account. This
#                               creates one the same way the wizard would, so the
#                               greeter has something to log in.
#   autologin                   a real desktop session needs a logged-in user, and
#                               nothing in a headless VM can type a password. The
#                               autologin lives in a configuration drop-in that only
#                               exists in this throwaway copy.
#
# Everything this script changes is a state file a normal machine would have anyway;
# nothing about the image's own configuration is altered. If a verification needs the
# image's configuration changed to pass, that is a finding, not a setup step.

set -euo pipefail

if [[ $# -lt 2 ]]; then
	echo "usage: prepare-screenshot-image.sh <image.qcow2> <output.qcow2> [--desktop]" >&2
	exit 2
fi

image="$1"
output="$2"
want_desktop=false
[[ "${3:-}" == "--desktop" ]] && want_desktop=true

test_user="oqtest"
test_password="openqos-dev"

[[ -f "${image}" ]] || {
	echo "error: ${image} not found." >&2
	exit 1
}
[[ "${image}" != "${output}" ]] || {
	echo "error: output must differ from the source image." >&2
	exit 1
}

echo "Copying ${image} -> ${output}"
cp --reflink=auto -- "${image}" "${output}"

device=""
for candidate in /dev/nbd3 /dev/nbd2 /dev/nbd1 /dev/nbd0; do
	if ! lsblk "${candidate}" -o MOUNTPOINTS --noheadings 2>/dev/null | grep -q "/"; then
		device="${candidate}"
		break
	fi
done
[[ -n "${device}" ]] || {
	echo "error: no free nbd device." >&2
	exit 1
}

mountpoint=$(mktemp -d)
cleanup() {
	umount "${mountpoint}" 2>/dev/null || true
	rmdir "${mountpoint}" 2>/dev/null || true
	qemu-nbd --disconnect "${device}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

qemu-nbd --connect="${device}" "${output}"
sleep 3
# -o subvol=root: the btrfs default subvolume is the top level, which holds the
# filesystem's subvolumes rather than the filesystem. Mounting without this gives a
# tree with no /etc at all, and a confusing "No such file or directory" on write.
mount -o subvol=root "${device}p2" "${mountpoint}"

echo "Marking first-boot setup as done"
touch "${mountpoint}/etc/plasma-setup-done"

if [[ "${want_desktop}" == true ]]; then
	echo "Creating test user ${test_user}"
	# Created with the image's own useradd, inside a chroot, rather than by writing
	# the account files directly. Writing them by hand *looked* fine — getent found
	# the user — but passwd refused it with "Provided user name is not a valid name"
	# and PAM then refused the login, so no desktop session could start. Using the
	# real tool is the difference between an account that exists and one that works.
	chroot "${mountpoint}" useradd --create-home --groups wheel --shell /bin/bash "${test_user}"

	# useradd reported success inside the chroot but did not create the home
	# directory — the image has no /var/spool/mail, and the account ended up with a
	# passwd entry pointing at a home that did not exist. Logging in then failed with
	# "change directory failed", and the greeter refused the login, which is a
	# confusing way to learn that a scaffold is wrong. So the home is created and
	# owned explicitly, and checked rather than assumed.
	mkdir -p "${mountpoint}/home/${test_user}"
	if [[ -d "${mountpoint}/etc/skel" ]]; then
		cp -rT "${mountpoint}/etc/skel" "${mountpoint}/home/${test_user}" 2>/dev/null || true
	fi
	owner="$(chroot "${mountpoint}" id -u "${test_user}")"
	group="$(chroot "${mountpoint}" id -g "${test_user}")"
	chown -R "${owner}:${group}" "${mountpoint}/home/${test_user}"
	if [[ ! -f "${mountpoint}/home/${test_user}/.bashrc" ]]; then
		printf '# Created by tests/prepare-screenshot-image.sh\n' >"${mountpoint}/home/${test_user}/.bashrc"
		chown "${owner}:${group}" "${mountpoint}/home/${test_user}/.bashrc"
	fi
	echo "  home: /home/${test_user} owned by ${owner}:${group}"

	# A usable password, not a locked marker: PAM's autologin and greeter stacks will
	# not admit a locked account. The algorithm is named explicitly for the same
	# reason the image's own config.sh names it — leaving it to a default is how a
	# $1$ MD5 hash ends up in /etc/shadow.
	printf '%s:%s\n' "${test_user}" "${test_password}" |
		chroot "${mountpoint}" chpasswd --crypt-method YESCRYPT

	echo "Enabling autologin for ${test_user} in this copy only"
	# Written to /etc/plasmalogin.conf, the file upstream's README names for user
	# configuration, because a drop-in in /etc/plasmalogin.conf.d/ did not take
	# effect. Only this throwaway copy has it.
	cat >>"${mountpoint}/etc/plasmalogin.conf" <<EOF

# Added by tests/prepare-screenshot-image.sh in this throwaway copy only, so a
# headless guest can reach a desktop session without anyone to type a password.
[Autologin]
User=${test_user}
Session=plasma.desktop
Relogin=false
EOF
fi

sync
echo "Prepared ${output}"
if [[ "${want_desktop}" == true ]]; then
	echo "  first-boot wizard: skipped (flag present)"
	echo "  autologin:         ${test_user}, session plasma.desktop"
else
	echo "  first-boot wizard: skipped (flag present), so the login screen is reachable"
fi
