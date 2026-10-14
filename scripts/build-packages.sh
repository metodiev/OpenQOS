#!/bin/bash
#
# Build the OpenQOS RPMs and publish them as an rpm-md repository.
#
# Run inside the Fedora development VM:
#
#   scripts/build-packages.sh
#   scripts/build-packages.sh --clean
#
# The builds themselves run as whoever invokes the script, not as root: only the
# publish step needs write access to the repository directory, and building as
# root bakes root ownership into the package payload.
#
# Published to /srv/openqos/packages, which is the path referenced by the
# <repository> entry in kiwi/openqos/base.xml. A repository source has to be an
# absolute URI, so the two locations are written down in two places by necessity
# and this comment is the link between them.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
publish_dir="/srv/openqos/packages"

# The build tree lives on the virtual machine's own disk, not in the repository.
# This is not tidiness. The repository is a mount from the macOS host, and
# rpmbuild writing into it through that mount loses the executable bit: packages
# built in packages/_build came out with mode 0600 for every file produced by
# `install -m 0755`, silently, with no error from rpmbuild — which for this
# repository means a launcher and a systemd ExecStart that cannot run. Moving the
# build tree here produces the modes the spec asks for. It is the same constraint
# the image build documents for KIWI's target directory.
#
# OPENQOS_PACKAGE_BUILD_ROOT overrides the location for a build on a host where
# the repository is a normal filesystem.
build_root="${OPENQOS_PACKAGE_BUILD_ROOT:-/var/tmp/openqos-packages}"

usage() {
	cat >&2 <<-'EOF'
		usage: scripts/build-packages.sh [--clean]

		  --clean   Start from an empty build tree instead of reusing it
		  -h, --help
	EOF
}

clean=false
for arg in "$@"; do
	case "${arg}" in
		--clean) clean=true ;;
		-h | --help) usage; exit 0 ;;
		*) echo "error: unknown argument: ${arg}" >&2; usage; exit 2 ;;
	esac
done

for tool in rpmbuild createrepo_c; do
	if ! command -v "${tool}" >/dev/null 2>&1; then
		echo "error: ${tool} is required but not installed." >&2
		echo "       It is part of the development VM definition; see" >&2
		echo "       tools/lima/openqos-dev.yaml." >&2
		exit 1
	fi
done

mapfile -t specs < <(find "${repo_root}/packages" -mindepth 2 -maxdepth 2 -name '*.spec' 2>/dev/null | sort)
if [[ "${#specs[@]}" -eq 0 ]]; then
	echo "error: no package specifications found under packages/" >&2
	exit 1
fi

if [[ "${clean}" == true ]]; then
	rm -rf -- "${build_root}"
fi
# Always clear the directories that hold outputs and staged sources. Reusing them
# means a previous run's RPM stays behind, which is worse than untidy: it is
# published to the repository, so the next image build installs a package this
# tree no longer produces — and it silently defeats any version check on the
# freshly built result. BUILD/ and BUILDROOT/ are left alone; that is the part
# worth reusing.
rm -rf -- "${build_root}"/RPMS "${build_root}"/SRPMS "${build_root}"/SOURCES
mkdir -p -- "${build_root}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

echo "Building ${#specs[@]} package specification(s)"

for spec in "${specs[@]}"; do
	name="$(basename -- "${spec}" .spec)"
	src_dir="$(dirname -- "${spec}")"
	echo "  ${name}"

	# Everything beside the .spec is a source. rpmbuild resolves `Source0: foo`
	# from SOURCES/, so this is what makes a package's own files visible to it.
	find "${src_dir}" -maxdepth 1 -type f ! -name '*.spec' \
		-exec cp -p -t "${build_root}/SOURCES" {} +

	# A package whose sources are a directory tree provides make-source.sh instead
	# of relying on the copy above, which only handles flat files. The script is
	# responsible for writing the archive into SOURCES/; see
	# packages/openqos-branding/make-source.sh for why the branding tree is not
	# duplicated under packages/.
	if [[ -x "${src_dir}/make-source.sh" ]]; then
		"${src_dir}/make-source.sh" "${build_root}/SOURCES"
	fi

	cp -p -- "${spec}" "${build_root}/SPECS/"

	rpmbuild --quiet \
		--define "_topdir ${build_root}" \
		--define "_build_id_links none" \
		-ba "${build_root}/SPECS/${name}.spec"
done

mapfile -t built < <(find "${build_root}/RPMS" -type f -name '*.rpm' | sort)
if [[ "${#built[@]}" -eq 0 ]]; then
	echo "error: rpmbuild produced no packages" >&2
	exit 1
fi

# --- release capability guard -------------------------------------------------
#
# OpenQOS excludes Fedora's release packages, so openqos-release has to satisfy the
# requirements that made them necessary. Two packages ask, in two forms, and rpm
# matches both literally:
#
#   setup        Requires: system-release        (bare)
#   fedora-repos Requires: system-release(44)    (release number in the name)
#
# The second moves with the base, which is why it is checked rather than trusted.
# If openqos-release stops providing it, the bootstrap transaction finds no
# provider for system-release and fails — or, worse, dnf keeps an older
# fedora-release alive and the exclusion quietly stops doing anything.
#
# The query enables updates-testing because that matches what the *image* build
# resolves: Fedora's upstream core.xml enables fedora, updates and
# updates-testing. Querying only this VM's enabled repos would understate the
# required release number and let a stale pin through.
required_release="$(dnf5 repoquery --enablerepo=updates-testing --latest-limit 1 \
	--requires fedora-repos 2>/dev/null |
	sed -n 's/^system-release(\([0-9][0-9]*\))$/\1/p' | head -n1)"

for candidate in "${built[@]}"; do
	[[ "${candidate}" == *"/openqos-release-"* ]] || continue
	if [[ -z "${required_release}" ]]; then
		echo "warning: could not determine the system-release(N) capability required" >&2
		echo "         by fedora-repos; skipping the release capability guard." >&2
		break
	fi
	release_provides="$(rpm -qp --provides "${candidate}")"
	missing=0
	for capability in system-release "system-release(${required_release})"; do
		grep -qxF -- "${capability}" <<<"${release_provides}" || missing=1
	done
	if [[ "${missing}" -eq 0 ]]; then
		echo "Release guard: system-release and system-release(${required_release}) satisfied by $(basename "${candidate}")"
	else
		echo "error: release capability mismatch." >&2
		echo "       fedora-repos requires system-release(${required_release}) and setup requires system-release" >&2
		echo "       $(basename "${candidate}") provides:" >&2
		grep -- system-release <<<"${release_provides}" | sed 's/^/         /' >&2
		echo >&2
		echo "       Set this in packages/openqos-release/openqos-release.spec, then rebuild:" >&2
		echo "         Version:        ${required_release}" >&2
		exit 1
	fi
done

echo
echo "Publishing ${#built[@]} package(s) to ${publish_dir}"

# Clear the published set first. Leaving a stale RPM behind means the repository
# advertises a package the tree no longer produces, and the next image build
# silently installs it.
sudo mkdir -p -- "${publish_dir}"
sudo find "${publish_dir}" -maxdepth 1 -type f -name '*.rpm' -delete
sudo cp -p -- "${built[@]}" "${publish_dir}/"
sudo createrepo_c --quiet "${publish_dir}"

echo
echo "=============================================================="
for rpm in "${built[@]}"; do
	base="$(basename -- "${rpm}")"
	printf '%s\n' " ${base}"
	echo "   provides:  $(rpm -qp --provides "${rpm}" 2>/dev/null | tr '\n' ' ')"
	echo "   obsoletes: $(rpm -qp --obsoletes "${rpm}" 2>/dev/null | tr '\n' ' ')"
done
echo "=============================================================="
echo "Repository: ${publish_dir}"
find "${publish_dir}" -maxdepth 1 -type f -name '*.rpm' -printf '  %f\n' | sort
