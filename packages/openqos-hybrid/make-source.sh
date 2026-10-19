#!/bin/bash
# openqos-hybrid — source archive builder.
#
# Called by scripts/build-packages.sh with rpmbuild's SOURCES directory. The
# archive is deterministic: sorted entries, epoch timestamps, numeric ownership
# and gzip told not to record a name or time.
set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: make-source.sh <SOURCES-dir>" >&2
	exit 2
fi

dest_dir="$1"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"

if [[ ! -d "${repo_root}/hybrid/openqos_hybrid" ]]; then
	echo "error: ${repo_root}/hybrid/openqos_hybrid does not exist" >&2
	exit 1
fi

mkdir -p -- "${dest_dir}"
archive="${dest_dir}/openqos-hybrid.tar.gz"

tar --create --file - \
	--directory "${repo_root}" \
	--sort=name \
	--mtime='@0' \
	--owner=0 --group=0 --numeric-owner \
	--mode='u=rwX,go=rX' \
	--exclude='__pycache__' \
	--exclude='*.pyc' \
	--exclude='.DS_Store' \
	--transform='s,^hybrid,openqos-hybrid,' \
	--transform='s,^LICENSE$,openqos-hybrid/LICENSE,' \
	hybrid \
	LICENSE | gzip -9n > "${archive}"

echo "  source: $(basename -- "${archive}") $(stat -c '%s' "${archive}") bytes"
