# dist/ — build hand-off

`scripts/build-image.sh` copies the finished artefacts here at the end of every
successful image build. Everything except this file is gitignored.

## Why this exists rather than `kiwi/build/`

`kiwi/build/` is scratch. A `--clean` build replaces the directory, and the
directory name is derived from `--output`, so a path there is only valid until the
next build. It is fine for reading a manifest immediately after a build and wrong
for anything that has to survive — a release page, a download link, or a
VirtualBox session started a day later.

## What lands here

| File | What it is |
| --- | --- |
| `OpenQOS.<arch>-<release>.iso` | The bootable live medium |
| `OpenQOS.<arch>-<release>.packages` | Every installed package and its version |
| `OpenQOS.<arch>-<release>.changes` | Changelogs of the installed packages |
| `OpenQOS.<arch>-<release>.verified` | The verification stamps KIWI recorded |
| `MANIFEST.txt` | Build inputs and a SHA-256 for every file above |

Disk-image formats (`qcow2`, `vhd`, `vhdx`, `vmdk`) land here too when a build
requests one. The uncompressed `.raw` image does not: it is an intermediate that
can be reproduced from the requested format.

The architecture is part of every file name, so an `x86_64` and an `aarch64` build
coexist here without overwriting each other.

## Verifying a download

`MANIFEST.txt` records the SHA-256 of each artefact as built:

```sh
sha256sum -c <(grep -E '^\S+  \./OpenQOS' dist/MANIFEST.txt)
```

Run it from inside `dist/`, since the manifest lists bare file names.

## A note on aarch64

`scripts/build-image.sh` builds for the architecture of the machine it runs on —
KIWI offers no cross-architecture option, and the image type is chosen by matching
the host against the `arch` attribute in `kiwi/openqos/disk.xml`. So an aarch64
ISO is only produced on an aarch64 host: see `tools/lima/openqos-dev.yaml` and
`docs/development-environment.md`.
