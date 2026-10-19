#!/bin/bash
# Run the Python tests for the hybrid application subsystem.
#
# The tests do not need root, a desktop session or any external runtime. They
# build synthetic RPM/PE/ELF/DMG/Mach-O files, inject fake command runners and
# use temporary XDG directories, so they are safe on a developer workstation and
# in CI.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
cd -- "${repo_root}"

exec python3 -m unittest discover -s tests/hybrid -t . -v
