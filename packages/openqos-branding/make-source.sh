#!/bin/bash
#
# Build the source archive for openqos-branding.
#
# Called by scripts/build-packages.sh with the directory rpmbuild reads sources
# from. Run standalone, it writes nothing outside that directory.
#
#   packages/openqos-branding/make-source.sh <SOURCES-dir>
#
# Why a tarball at all: rpmbuild resolves `Source0:` from SOURCES/, and the
# packaging script copies only the flat files sitting beside a .spec. The branding
# package is a directory tree, and its source of truth is branding/ at the
# repository root — duplicating that tree under packages/ would mean two copies of
# every asset and a silent drift between them.
#
# Why the tarball is not committed: it is generated from files that are already
# here, and a committed copy could disagree with them.
#
# Deterministic output: sorted entries, epoch timestamps, numeric ownership, and
# gzip told not to record a name or a time. Two runs on the same tree produce
# byte-identical archives, so a rebuild that differs means the assets changed.

set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: make-source.sh <SOURCES-dir>" >&2
	exit 2
fi

dest_dir="$1"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"

if [[ ! -d "${repo_root}/branding" ]]; then
	echo "error: ${repo_root}/branding does not exist" >&2
	exit 1
fi

mkdir -p -- "${dest_dir}"
archive="${dest_dir}/openqos-branding.tar.gz"

tar --create --file - \
	--directory "${repo_root}" \
	--sort=name \
	--mtime='@0' \
	--owner=0 --group=0 --numeric-owner \
	--exclude='.DS_Store' \
	--transform='s,^branding,openqos-branding,' \
	branding | gzip -9n > "${archive}"

echo "  source: $(basename -- "${archive}") $(stat -c '%s' "${archive}") bytes"
