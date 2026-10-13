#!/bin/bash
#
# Build the source archive for openqos-installer.
#
# Called by scripts/build-packages.sh with the directory rpmbuild reads sources
# from. Run standalone, it writes nothing outside that directory.
#
#   packages/openqos-installer/make-source.sh <SOURCES-dir>
#
# This package's files live in three places on purpose, and the archive is what
# puts them where rpmbuild expects:
#
#   files/            the tree that is installed into the image, under the paths
#                     it will have in the image (usr/bin/openqos-install and so on)
#   ../../kickstart/  openqos.ks, which is the installation definition and belongs
#                     next to the image definition it is kept in step with, not
#                     inside a package directory
#   ../../LICENSE     this repository's licence, so the package can ship one
#
# Deterministic output: sorted entries, epoch timestamps, numeric ownership, and
# gzip told not to record a name or a time, so two runs on the same tree produce
# byte-identical archives and a rebuild that differs means a file changed.
#
set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: make-source.sh <SOURCES-dir>" >&2
	exit 2
fi

dest_dir="$1"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"

if [[ ! -f "${repo_root}/kickstart/openqos.ks" ]]; then
	echo "error: ${repo_root}/kickstart/openqos.ks does not exist" >&2
	exit 1
fi

mkdir -p -- "${dest_dir}"
archive="${dest_dir}/openqos-installer.tar.gz"

tar --create --file - \
	--directory "${repo_root}" \
	--sort=name \
	--mtime='@0' \
	--owner=0 --group=0 --numeric-owner \
	--exclude='.DS_Store' \
	--transform='s,^packages/openqos-installer/files,openqos-installer,' \
	--transform='s,^packages/openqos-installer/README.md,openqos-installer/README.md,' \
	--transform='s,^kickstart/openqos.ks,openqos-installer/openqos.ks,' \
	--transform='s,^LICENSE$,openqos-installer/LICENSE,' \
	packages/openqos-installer/files \
	packages/openqos-installer/README.md \
	kickstart/openqos.ks \
	LICENSE | gzip -9n > "${archive}"

echo "  source: $(basename -- "${archive}") $(stat -c '%s' "${archive}") bytes"
