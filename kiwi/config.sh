#!/bin/bash
#
# Build-time configuration hook, executed by KIWI inside the image being built.
#
# KIWI runs this for every profile, so anything profile-specific must be gated on
# $kiwi_profiles.
#
# Note that Fedora's own config.sh is NOT executed for OpenQOS images: KIWI only
# looks for config.sh in the root of the description directory, and Fedora's copy
# lives in upstream/. That is why Fedora's Cloud- and Live-specific behaviour
# does not leak into our images, and why anything we rely on must be set here.

# shellcheck disable=SC1091
#   SC1091: /.kconfig and /.profile exist only inside the image being built.
# shellcheck disable=SC2154
#   SC2154: kiwi_iname and kiwi_profiles are injected by KIWI.
# These directives must appear before the first command to apply file-wide.
set -euo pipefail

test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

echo "Configuring OpenQOS image: [${kiwi_iname}]-[${kiwi_profiles}]"

case "${kiwi_profiles:-}" in
*Test*)
	echo "> test profile: enabling SSH for automated verification"
	# DEVELOPMENT ONLY. Password authentication for root is enabled so that a
	# built image can be logged into from outside during automated tests. Images
	# built from a -Test profile must never be published or used on real hardware.
	mkdir -p /etc/ssh/sshd_config.d
	printf '%s\n' \
		'# Managed by OpenQOS: see kiwi/config.sh. Test images only.' \
		'PermitRootLogin yes' \
		'PasswordAuthentication yes' \
		'KbdInteractiveAuthentication no' \
		> /etc/ssh/sshd_config.d/10-openqos-boot-test.conf
	chmod 0600 /etc/ssh/sshd_config.d/10-openqos-boot-test.conf

	# Fedora's openssh-server RPM ships a preset for this, but presets are not
	# applied inside a build chroot, so enable it explicitly.
	systemctl enable sshd.service
	;;
*) ;;
esac

# ----------------------------------------------------------------- password ---
#
# DEVELOPMENT ONLY, and the reason the credential is set here rather than in the
# image description: KIWI's `<user password="..." pwdformat="plain">` hashes with
# the C library default, which is MD5 on current glibc, so a description-set
# password ships as a $1$ hash in /etc/shadow.
#
# The algorithm is named explicitly instead of being left to a default. YESCRYPT
# is the modern choice for a login password and is one of the methods chpasswd
# offers; naming it means this cannot silently become something weaker if
# shadow-utils changes its default, and the same value is what `crypt` selects
# when the password is later changed.
#
# The value is a fixed, publicly known development credential. It exists so the
# pipeline can be validated, it is not a secret, and an image carrying it must
# never be published.
case "${kiwi_profiles:-}" in
*Test*)
	echo "> test profile: setting the development root credential (yescrypt)"
	printf 'root:%s\n' 'openqos-dev' | chpasswd --crypt-method YESCRYPT
	;;
*) ;;
esac

# ----------------------------------------------------------------- assertions ---
#
# A build that ships a weak hash should fail here, not be noticed later. Two
# checks: nothing may be weaker than SHA-512, and a profile that is not a
# development profile must not carry a login credential at all.
if awk -F: '$2 ~ /^\$(1|5)\$/ { found = 1 } END { exit !found }' /etc/shadow; then
	echo "error: a password hash weaker than SHA-512 is present in /etc/shadow:" >&2
	awk -F: '$2 ~ /^\$(1|5)\$/ { print "         " $1 " has a " substr($2, 1, 3) " hash" }' /etc/shadow >&2
	exit 1
fi

case "${kiwi_profiles:-}" in
*Test* | *Dev*) ;;
*)
	# Locked ("!") and no-password ("*") accounts are what a product image should
	# have: the installer, or the first-boot experience, is what creates the real
	# user. A set hash here means something set a credential on a publishable
	# profile, which is a mistake worth failing over.
	unexpected="$(awk -F: '$2 !~ /^[!*]/ { print $1 }' /etc/shadow)"
	if [[ -n "${unexpected}" ]]; then
		echo "error: profile '${kiwi_profiles}' is not a development profile but sets" >&2
		echo "       a password for: ${unexpected//$'\n'/ }" >&2
		echo "       Remove it, or name the profile so it is recognised as development." >&2
		exit 1
	fi
	;;
esac

# A desktop image that nobody can log into is not a usable artefact, and it is an
# easy one to produce by accident: locking root and shipping no user is two separate
# reasonable decisions whose combination bricks the image. Live media are exempt
# (livesys-scripts creates the live account at boot), and so are images with no
# display manager, such as OpenQOS-Minimal, which exists to prove the pipeline boots
# and is documented as having no login.
if [[ -e /usr/bin/plasmalogin ]]; then
	usable_accounts="$(awk -F: '$2 !~ /^[!*]/ { print $1 }' /etc/shadow)"

	wizard_unit=/usr/lib/systemd/system/plasma-setup.service
	wizard_enabled=/etc/systemd/system/multi-user.target.wants/plasma-setup.service
	first_boot_done=/etc/plasma-setup-done

	enterable=false
	if [[ -n "${usable_accounts}" ]]; then
		enterable=true
	elif [[ -e "${wizard_unit}" && -e "${wizard_enabled}" && ! -e "${first_boot_done}" ]]; then
		enterable=true
	fi

	if [[ "${enterable}" == false ]]; then
		echo "error: profile '${kiwi_profiles}' installs a display manager but no" >&2
		echo "       account could log in, and the first-boot wizard will not run." >&2
		echo "       Accounts that can log in: ${usable_accounts:-none}" >&2
		echo "       Wizard unit present:     $([[ -e "${wizard_unit}" ]] && echo yes || echo no)" >&2
		echo "       Wizard enabled:          $([[ -e "${wizard_enabled}" ]] && echo yes || echo no)" >&2
		echo "       Already marked done:     $([[ -e "${first_boot_done}" ]] && echo yes || echo no)" >&2
		exit 1
	fi
	echo "> this desktop image is enterable: $(
		[[ -n "${usable_accounts}" ]] && echo "an account with a password exists" || echo "the first-boot wizard will run"
	)"
fi

case "${kiwi_profiles:-}" in
*Live*)
	# Live media do not use a normal login: livesys-scripts creates a temporary
	# account and autologins it, choosing the session from this file. Fedora's own
	# config.sh is the thing that writes it, and ours replaces theirs, so if this
	# is not written the live image boots to a login prompt with no account that
	# can be used.
	echo "> live media: selecting the Plasma session for livesys"
	mkdir -p /etc/sysconfig
	printf '%s\n' 'livesys_session="kde"' > /etc/sysconfig/livesys
	;;
*) ;;
esac
