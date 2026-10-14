#!/bin/bash
#
# Build an OpenQOS image with KIWI, and write a build manifest recording the
# SHA-256 of every artefact produced.
#
# Run inside the Fedora development VM (see docs/development-environment.md).
# Root is required: KIWI creates and mounts disk images through loop devices.
#
# Usage:
#   sudo scripts/build-image.sh
#   sudo scripts/build-image.sh --profile OpenQOS-Minimal --clean
#
# KIWI populates its target directory as a chroot, so it needs real ownership,
# mode bits, ACLs and xattrs. The repository is mounted into the VM over
# virtiofs, which cannot represent those (it reports as "fuse"), and KIWI
# refuses to build there. The build therefore runs in a scratch directory on the
# guest's own disk, and the finished artefacts are copied into the repository
# afterwards.
#
# The KIWI invocation lives here, so there is exactly one place that defines how
# OpenQOS images are produced.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

profile="OpenQOS-Minimal"
image_type="oem"
kiwi_file="OpenQOS.kiwi"
description_dir="${repo_root}/kiwi"
output_name=""
scratch_root="${OPENQOS_SCRATCH:-/var/tmp/openqos-build}"
clean=false

usage() {
	cat >&2 <<-'EOF'
		usage: sudo scripts/build-image.sh [options]

		  --profile NAME   KIWI profile to build (default: OpenQOS-Minimal)
		  --type TYPE      KIWI image type   (default: oem)
		  --output NAME    Artefact directory name under kiwi/build
		                   (default: the profile name)
		  --scratch DIR    Local-filesystem scratch root (default: /var/tmp/openqos-build)
		  --clean          Replace an existing scratch directory
		  -h, --help       Show this message
	EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--profile) profile="${2:?--profile needs a value}"; shift 2 ;;
		--type) image_type="${2:?--type needs a value}"; shift 2 ;;
		--output) output_name="${2:?--output needs a value}"; shift 2 ;;
		--scratch) scratch_root="${2:?--scratch needs a value}"; shift 2 ;;
		--clean) clean=true; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "error: unknown argument: $1" >&2; usage; exit 2 ;;
	esac
done

if [[ "${EUID}" -ne 0 ]]; then
	echo "error: must run as root (KIWI needs loop devices to build disk images)." >&2
	echo "       Try: sudo $0 $*" >&2
	exit 1
fi

if [[ ! -f "${description_dir}/${kiwi_file}" ]]; then
	echo "error: description not found: ${description_dir}/${kiwi_file}" >&2
	exit 1
fi

if [[ ! -d "${description_dir}/upstream" ]]; then
	echo "error: Fedora's descriptions are missing from kiwi/upstream." >&2
	echo "       Run: scripts/fetch-upstream-descriptions.sh" >&2
	exit 1
fi

host_arch="$(uname -m)"
# KIWI builds an image for the architecture of the machine it runs on — there is
# no cross-architecture option, and the image type is chosen by matching the host
# against the `arch` attribute in kiwi/openqos/disk.xml. So the host arch must be
# one the description actually defines a type for, and this is where that is
# stated. Without it KIWI fails later with "no image type defined", which does
# not name the architecture that is missing.
case "${host_arch}" in
	aarch64 | x86_64) ;;
	*)
		echo "error: no image type is defined for host architecture '${host_arch}'." >&2
		echo "       OpenQOS defines types for aarch64 and x86_64." >&2
		exit 1
		;;
esac

name="${output_name:-${profile}}"
scratch_dir="${scratch_root}/${name}"
artefact_dir="${repo_root}/kiwi/build/${name}"

mkdir -p -- "${scratch_root}"
scratch_fs="$(stat -f -c %T "${scratch_root}" 2>/dev/null || echo unknown)"
case "${scratch_fs}" in
	fuse|fuseblk|smb2|cifs|nfs|nfs4|unknown)
		echo "error: ${scratch_root} is on a '${scratch_fs}' filesystem." >&2
		echo "       KIWI builds a root filesystem there and needs extended" >&2
		echo "       permissions, ACLs and xattrs, which that filesystem cannot" >&2
		echo "       provide. Use local disk, for example /var/tmp." >&2
		exit 1
		;;
esac

if [[ -e "${scratch_dir}" ]] && [[ -n "$(ls -A -- "${scratch_dir}" 2>/dev/null || true)" ]]; then
	if [[ "${clean}" == true ]]; then
		echo "Replacing existing scratch directory: ${scratch_dir}"
		rm -rf -- "${scratch_dir}"
	else
		echo "error: ${scratch_dir} already exists and is not empty." >&2
		echo "       Pass --clean to replace it, or --output NAME to build elsewhere." >&2
		exit 1
	fi
fi
mkdir -p -- "${scratch_dir}" "${artefact_dir}"

# KIWI resolves <file name="..."> against the *description* directory, and it
# imports the file flattened to <description>/image/<basename> while installing
# it from <description>/image/<dirname(name)>/<basename>. Those two only agree
# when `name` has no directory component, so every referenced file has to sit at
# the description root under its own bare basename.
#
# Each configuration file is therefore staged as a symlink named staged-<basename>.
# Symlinks rather than copies keep config/ the single source of truth, and the
# staged- prefix gives a single predictable pattern to ignore in Git.
#
# config/<arch>/ trees mirror the image root, so config/common/etc/xdg/kdeglobals
# installs to /etc/xdg/kdeglobals. Files under config/common apply to every
# architecture; files under config/<arch> apply only when building that
# architecture.
staged_count=0
while IFS= read -r -d '' cfg_file; do
	rel_path="${cfg_file#"${repo_root}/config/"}"
	cfg_arch="${rel_path%%/*}"
	case "${cfg_arch}" in
		common | "${host_arch}") ;;
		*) continue ;;
	esac

	staged_name="staged-$(basename -- "${cfg_file}")"
	staged_link="${description_dir}/${staged_name}"
	link_target="$(realpath --relative-to="${description_dir}" -- "${cfg_file}")"

	if [[ -L "${staged_link}" ]] && [[ "$(readlink -- "${staged_link}")" != "${link_target}" ]]; then
		echo "error: two configuration files both stage to ${staged_name}" >&2
		echo "       KIWI requires a unique basename per file at the description root." >&2
		exit 1
	fi

	ln -sfn -- "${link_target}" "${staged_link}"
	staged_count=$((staged_count + 1))
done < <(find "${repo_root}/config" -type f ! -name '.gitkeep' ! -name '.DS_Store' -print0 | sort -z)

if [[ "${staged_count}" -eq 0 ]]; then
	echo "warning: no configuration files found under config/" >&2
fi

# Fedora's own description references a few files by bare name too — the live-ISO
# GRUB template via a `grub_template` attribute, and the ESP exclusion list via a
# `<file name="...">` entry — so KIWI resolves those against the description root
# as well. Those names are upstream's and cannot be changed without editing
# upstream's type, so a file of ours that needs to replace one has to be staged
# under upstream's name.
#
# Only the GRUB template is ours. It is byte-identical to upstream's except for
# the menu class, and the substitution is reported below rather than performed
# silently, because shadowing a file by name is exactly the sort of thing that
# becomes invisible six months later.
case "${host_arch}" in
	aarch64) iso_grub_template="grub-arm.cfg.iso-template" ;;
	x86_64) iso_grub_template="grub-x86.cfg.iso-template" ;;
	*) iso_grub_template="" ;;
esac

# The ESP exclusion list stays upstream's: it works around an upstream bug in the
# embedded ESP and has nothing to do with branding.
iso_esp_excludes="iso-esp-excludes.yaml"
if [[ ! -e "${description_dir}/upstream/${iso_esp_excludes}" ]]; then
	echo "error: pinned upstream has no ${iso_esp_excludes}." >&2
	echo "       It is referenced by upstream's LiveInstall description." >&2
	exit 1
fi
ln -sfn -- "upstream/${iso_esp_excludes}" "${description_dir}/${iso_esp_excludes}"
echo "Staged upstream/${iso_esp_excludes} into the description directory (symlink)"

if [[ -n "${iso_grub_template}" ]]; then
	our_template="${repo_root}/kiwi/templates/${iso_grub_template}"
	upstream_template="${description_dir}/upstream/${iso_grub_template}"

	if [[ -f "${our_template}" ]]; then
		if [[ ! -e "${upstream_template}" ]]; then
			echo "error: ${our_template} exists but upstream has no" >&2
			echo "       ${iso_grub_template} to derive from." >&2
			exit 1
		fi
		ln -sfn -- "templates/${iso_grub_template}" "${description_dir}/${iso_grub_template}"
		# Say so, every build. Shadowing a file by name is exactly the sort of
		# thing that becomes invisible six months later.
		#
		# The count is not classified here: it includes this file's own header.
		# tests/check-upstream-drift.sh is what asserts the *body* differs from
		# upstream only in the menu class, which is the claim that matters.
		differing="$(diff "${upstream_template}" "${our_template}" | grep -c '^[<>]' || true)"
		echo "Staged our templates/${iso_grub_template}, replacing upstream's"
		echo "  upstream's is at upstream/${iso_grub_template}; ${differing} lines differ"
		echo "  expected: this file's header, plus the menu class"
	elif [[ -e "${upstream_template}" ]]; then
		ln -sfn -- "upstream/${iso_grub_template}" "${description_dir}/${iso_grub_template}"
		echo "Staged upstream/${iso_grub_template} into the description directory (symlink)"
	fi
fi

echo "=============================================================="
echo " OpenQOS image build"
echo "   profile    : ${profile}"
echo "   image type : ${image_type}"
echo "   arch       : ${host_arch}"
echo "   scratch    : ${scratch_dir}  (${scratch_fs}, local)"
echo "   artefacts  : ${artefact_dir}"
echo "=============================================================="

# mkfs.erofs, which KIWI uses for the `iso` image type, buffers through $TMPDIR.
# This guest's /tmp is a tmpfs sized at half of RAM (3.9 GiB), while a live
# filesystem compresses to about 3 GiB — close enough that overrunning it is
# routine. The failure surfaces as a confusing
#
#   mkfs.erofs: <E> erofs: failed to commit fragment for ...: [Error 5] Input/output error
#
# rather than as anything mentioning space.
#
# $TMPDIR must resolve in *two* contexts: on the build host, where mkfs.erofs
# runs, and inside the image chroot, where KIWI runs dracut to check ISO support.
# A directory under the scratch root satisfies only the first and makes dracut
# fail with "Invalid tmpdir", which KIWI reports as "image type iso not
# supported". /var/tmp is on local disk in both contexts, and is already dracut's
# own default, so nothing changes for it.
export TMPDIR="/var/tmp"

# --------------------------------------------------------- medium identity ---
# Live media carry their identity on the medium: an ISO volume label, a publisher
# and an application id. All three are inherited from Fedora's `LiveInstall`
# preferences, and OpenQOS cannot edit them there without duplicating the whole ISO
# type — Preferences attach to every profile in the active set, including required
# ones, so defining a second <type image="iso"> for the same build is a hard error.
#
# KIWI can override type attributes from the command line instead, which is also how
# Fedora's own live-ISO label generator does it. That keeps the identity here, in one
# place, instead of forking upstream's description.
#
# The label is not cosmetic. KIWI composes the kernel command line as
# `root=live:CDLABEL=<volid>`, so the volume label is how the live system finds its
# own root filesystem. Overriding volid changes both consistently, because the ISO
# builder and the bootloader config read the same attribute — but it is worth knowing
# that a mismatch here produces media that boots to a dracut prompt rather than a
# desktop, so scripts/tests must check the label and the command line agree.
kiwi_type_args=()
medium_label=""
if [[ "${image_type}" == "iso" ]]; then
	# Derived from the profile name so two different media built here can never carry
	# the same label: CDLABEL matching cannot tell two identically-labelled discs
	# apart. Only [A-Z0-9_] is used, which every ISO9660 volume descriptor accepts.
	medium_label="$(printf '%s' "${profile}" | tr -- '-' '_')"
	if [[ "${#medium_label}" -gt 32 ]]; then
		echo "error: ISO volume label '${medium_label}' is ${#medium_label} characters;" >&2
		echo "       ISO9660 allows at most 32." >&2
		exit 1
	fi
	kiwi_type_args=(
		"--set-type-attr=volid=${medium_label}"
		"--set-type-attr=application_id=OpenQOS Linux"
		"--set-type-attr=publisher=OpenQOS"
	)
	echo "Medium label: ${medium_label}"
fi

# The one place the image build is defined.
kiwi-ng \
	--type="${image_type}" \
	--profile="${profile}" \
	--kiwi-file="${kiwi_file}" \
	system build \
	--description "${description_dir}" \
	--target-dir "${scratch_dir}" \
	"${kiwi_type_args[@]}"

# ----------------------------------------------------------------- publish ---
# KIWI leaves the uncompressed disk image next to the requested format. Publish
# only the requested format; the raw image is reproducible from it and would
# double the artefact size.
published=0
while IFS= read -r -d '' candidate; do
	base="$(basename -- "${candidate}")"
	case "${base}" in
		*.raw)
			stem="${base%.raw}"
			converted=false
			for ext in qcow2 vhd vhdx vmdk; do
				if [[ -f "${scratch_dir}/${stem}.${ext}" ]]; then
					converted=true
					break
				fi
			done
			if [[ "${converted}" == true ]]; then
				echo "Skipping intermediate: ${base}"
				continue
			fi
			;;
	esac
	echo "Publishing: ${base}"
	cp -f -- "${candidate}" "${artefact_dir}/${base}"
	published=$((published + 1))
done < <(find "${scratch_dir}" -maxdepth 1 -type f -print0 | sort -z)

if [[ "${published}" -eq 0 ]]; then
	echo "error: build produced no artefacts in ${scratch_dir}" >&2
	exit 1
fi

# ---------------------------------------------------------------- manifest ---
# A build is not "done" because the command exited 0: it is done when the
# artefacts exist and their checksums are recorded. See docs/roadmap.md.
upstream_commit="$(sed -n 's/^upstream_commit=//p' "${repo_root}/kiwi/upstream.lock" | head -n1)"
fedora_release="$(sed -n 's/^fedora_release=//p' "${repo_root}/kiwi/upstream.lock" | head -n1)"
kiwi_version="$(kiwi-ng --version 2>/dev/null | sed -n 's/.*version //p' | head -n1 || true)"

manifest="${artefact_dir}/MANIFEST.txt"

{
	echo "# OpenQOS build manifest"
	echo "profile=${profile}"
	echo "image_type=${image_type}"
	echo "arch=${host_arch}"
	if [[ -n "${medium_label}" ]]; then
		echo "medium_label=${medium_label}"
	fi
	echo "fedora_release=${fedora_release}"
	echo "upstream_description_commit=${upstream_commit}"
	echo "kiwi_version=${kiwi_version}"
	echo "built_at=$(date --iso-8601=seconds)"
	echo "built_on=$(uname -n) kernel=$(uname -r)"
	echo
} > "${manifest}"

(
	cd -- "${artefact_dir}"
	sha256sum -- ./* 2>/dev/null | grep -v "MANIFEST.txt" || true
) >> "${manifest}"

# ------------------------------------------------------------------- dist ---
# A hand-off location inside the repository. kiwi/build/ is scratch: a --clean
# build replaces it, and the directory name comes from --output, so an artefact
# needed for a release page or a VirtualBox session should not be read from there.
# dist/ is the stable copy, and it keeps the architecture in the file name so an
# x86_64 and an aarch64 build sit side by side without colliding.
#
# dist/ is gitignored for the same reason kiwi/build/ is; see the note at the top of
# .gitignore. Only dist/README.md is tracked, so the directory explains itself in a
# fresh clone.
dist_dir="${repo_root}/dist"
mkdir -p -- "${dist_dir}"

dist_published=0
for artefact in "${artefact_dir}"/*; do
	[[ -f "${artefact}" ]] || continue
	base="$(basename -- "${artefact}")"
	# The uncompressed disk image is an intermediate and is reproducible from the
	# requested format, so it is skipped when a converted format exists. A build
	# that requested raw has nothing else, so this is a guard, not a policy.
	case "${base}" in
		*.raw) continue ;;
	esac
	cp -f -- "${artefact}" "${dist_dir}/${base}"
	dist_published=$((dist_published + 1))
done

if [[ "${dist_published}" -eq 0 ]]; then
	echo "error: nothing was published to ${dist_dir}" >&2
	exit 1
fi

echo
echo "=============================================================="
echo " Build complete"
echo " Artefacts : ${artefact_dir}"
echo " Hand-off  : ${dist_dir}"
echo " Manifest  : ${manifest}"
echo "=============================================================="
cat -- "${manifest}"
