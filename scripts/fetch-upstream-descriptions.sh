#!/bin/bash
#
# Materialise Fedora's KIWI image descriptions at the revision pinned in
# kiwi/upstream.lock, into kiwi/upstream/.
#
# OpenQOS does not vendor Fedora's descriptions into this repository. They are
# fetched at a pinned revision instead, so that:
#   * the delta between Fedora's description and ours stays visible in review,
#   * upstream fixes are taken deliberately rather than by silently drifting,
#   * builds stay reproducible, because the revision is pinned by commit SHA.
#
# The output directory is gitignored. Run this before building an image.
#
# Runs inside the Fedora development VM (see docs/development-environment.md).
# Requires: git.
#
# Usage:
#   scripts/fetch-upstream-descriptions.sh
#   scripts/fetch-upstream-descriptions.sh --update-lock

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
lock_file="${repo_root}/kiwi/upstream.lock"
dest_dir="${repo_root}/kiwi/upstream"
upstream_url="https://forge.fedoraproject.org/releng/kiwi-descriptions.git"

usage() {
	cat >&2 <<-EOF
		usage: $(basename -- "$0") [--update-lock]

		  (no options)   fetch the pinned revision into kiwi/upstream
		  --update-lock  move the pin to the current head of the recorded branch
	EOF
}

# Read a single key from the lock file without executing it.
lock_value() {
	sed -n "s/^$1=//p" "${lock_file}" | head -n1
}

update_lock=false
for arg in "$@"; do
	case "${arg}" in
		--update-lock) update_lock=true ;;
		-h|--help) usage; exit 0 ;;
		*) echo "error: unknown argument: ${arg}" >&2; usage; exit 2 ;;
	esac
done

if [[ ! -f "${lock_file}" ]]; then
	echo "error: lock file not found: ${lock_file}" >&2
	exit 1
fi

branch="$(lock_value upstream_branch)"
commit="$(lock_value upstream_commit)"
release="$(lock_value fedora_release)"

if [[ -z "${branch}" || -z "${commit}" ]]; then
	echo "error: ${lock_file} must set upstream_branch and upstream_commit" >&2
	exit 1
fi

if [[ -d "${dest_dir}/.git" ]]; then
	echo "Updating existing checkout in kiwi/upstream ..."
	git -C "${dest_dir}" fetch --quiet origin "${branch}"
else
	echo "Cloning ${upstream_url} (branch ${branch}) ..."
	rm -rf -- "${dest_dir}"
	git clone --quiet --branch "${branch}" --single-branch "${upstream_url}" "${dest_dir}"
fi

head_commit="$(git -C "${dest_dir}" rev-parse --verify "origin/${branch}")"

if [[ "${update_lock}" == true ]]; then
	new_commit="$(git -C "${dest_dir}" rev-parse "origin/${branch}")"
	git -C "${dest_dir}" checkout --quiet "${new_commit}"
	if [[ "${new_commit}" == "${commit}" ]]; then
		echo "Lock already current at ${new_commit}; nothing to do."
	else
		echo "Moving pin: ${commit} -> ${new_commit}"
		sed -i "s/^upstream_commit=.*/upstream_commit=${new_commit}/" "${lock_file}"
		sed -i "s|^upstream_date=.*|upstream_date=$(git -C "${dest_dir}" log -1 --format=%cs "${new_commit}")|" "${lock_file}"
		echo "Updated ${lock_file}; review the change with 'git diff'."
	fi
	exit 0
fi

if ! git -C "${dest_dir}" cat-file -e "${commit}^{commit}" 2>/dev/null; then
	echo "error: pinned commit ${commit} is not present in ${branch}." >&2
	echo "       The branch may have been rewritten. Re-pin with --update-lock and review." >&2
	exit 1
fi

if ! git -C "${dest_dir}" cat-file -e "${head_commit}^{commit}" 2>/dev/null; then
	echo "error: could not resolve origin/${branch}" >&2
	exit 1
fi

git -C "${dest_dir}" checkout --quiet "${commit}"

actual="$(git -C "${dest_dir}" rev-parse HEAD)"
if [[ "${actual}" != "${commit}" ]]; then
	echo "error: checkout is at ${actual}, expected ${commit}" >&2
	exit 1
fi

if [[ "${head_commit}" != "${commit}" ]]; then
	echo "note: branch ${branch} has moved on (head ${head_commit:0:12})."
	echo "      Still building from pinned ${commit:0:12} for reproducibility."
	echo "      Review and adopt newer upstream with --update-lock."
fi

echo "Fedora ${release} descriptions ready at kiwi/upstream (${commit:0:12})."
