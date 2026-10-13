# Contributing to OpenQOS

Thank you for considering a contribution. This document describes the conventions
this project holds itself to. They exist mostly to keep the delta against upstream
Fedora small enough to maintain.

## Ground rules

These are not style preferences. Changes that break them will be sent back:

1. **Fedora only.** No Ubuntu or Debian tooling, package formats, repositories or
   assumptions. Package management is RPM and DNF. Installation is Anaconda.
2. **Do not copy Fedora's branding.** Fedora's logo, wordmark and artwork are covered
   by Red Hat's trademarks. Take inspiration from Fedora's quality; create original
   OpenQOS assets. See [docs/licensing.md](docs/licensing.md).
3. **Never claim a result you did not observe.** "Built successfully" requires a file
   with a matching checksum. "Boots" requires a virtual machine that reached a usable
   login. If you did not run it, write "not verified" and say so.
4. **No destructive disk operations** without explicit approval, and never against a
   macOS installation.
5. **Keep upstream diffs visible.** When you take something from Fedora — a KIWI
   component, a kickstart, a package specification — derive from it in a way that
   makes your changes readable, rather than copying it into a file that silently
   diverges.
6. **Separate our material from upstream's.** No OpenQOS artifact should overwrite an
   upstream file without that conflict being a deliberate, documented decision.

## Development environment

Builds run inside the Fedora aarch64 virtual machine described in
[docs/development-environment.md](docs/development-environment.md). Nothing in the
build toolchain runs on macOS.

Hardware budget matters. This project is developed on a 16 GB Apple Silicon machine:

* One heavy virtual machine at a time. Stop `openqos-dev` before starting anything
  else, including colima.
* The guest is capped at 8 GiB and 6 CPUs on purpose. Do not raise it.
* Prefer targeted builds over full rebuilds, and keep the DNF cache warm.

## Repository layout

| Path | Holds |
| --- | --- |
| `docs/` | Architecture, environment setup, licensing, roadmap |
| `branding/` | Original artwork, with provenance notes |
| `config/common/` | Configuration used by every architecture |
| `config/aarch64/`, `config/x86_64/` | Architecture-specific configuration |
| `packages/` | RPM specifications for `openqos-*` packages |
| `kiwi/` | KIWI image descriptions — the primary build path |
| `kickstart/` | Kickstart files controlling Anaconda's install behaviour |
| `scripts/` | Build and verification entry points |
| `tools/lima/` | The development VM definition |
| `tests/` | Repository and image checks |

Note that `kiwi/` and `kickstart/` do different jobs and are not interchangeable:
KIWI decides what is on the medium, kickstart decides what the installed system
becomes. See [docs/architecture.md](docs/architecture.md).

## Git workflow

* Work on `main` until there is more than one contributor; then use short-lived
  branches named `<type>/<short-description>`, for example `feat/kde-defaults` or
  `fix/kiwi-grub-arm`.
* Commit messages: a short imperative subject line under 72 characters, then a body
  explaining **why** the change is needed if that is not obvious. Reference the
  milestone where relevant, for example:

  ```
  Add minimal aarch64 OEM image profile

  Milestone 4: prove the KIWI pipeline end to end before adding a desktop.
  Starts from a non-desktop profile so a failure is unambiguously a pipeline
  failure.
  ```

* Keep commits reviewable. A change that adds a build script and reformats
  unrelated files should be two commits.
* Never commit secrets, tokens, or generated images and build artifacts. See
  [`.gitignore`](.gitignore).

## Licensing of contributions

* By contributing, you agree your contribution is licensed under the license that
  applies to the directory you are touching — see
  [docs/licensing.md §2](docs/licensing.md#2-proposal-license-per-material-type).
* Original code, scripts, configuration and packaging: `GPL-3.0-or-later`.
* Documentation and artwork: `CC-BY-SA-4.0`.
* Add an `SPDX-License-Identifier` and `SPDX-FileCopyrightText` header to files you
  create once the `LICENSES/` layout exists (Milestone 3).
* **Only contribute artwork you created or that is licensed for our use.** Every
  asset in `branding/` needs a provenance note naming its author, its license and —
  if you did not create it — where it came from. Third-party assets with
  non-commercial or unclear terms cannot be accepted.

## Verification bar

Before opening a change, run the smallest thing that actually checks your work:

| Change | Minimum check |
| --- | --- |
| Documentation only | None required |
| Shell script | `shellcheck <script>` inside the build VM |
| `tools/lima/openqos-dev.yaml` | `limactl validate tools/lima/openqos-dev.yaml` on macOS |
| KIWI description | `xmllint --noout` on the file, then a build with `scripts/build-image.sh` that produces a manifest with matching checksums |
| `kiwi/upstream.lock` | A build at the new pin, with the resulting diff reviewed |
| Kickstart file | `ksvalidator <file>` inside the build VM |
| Branding or desktop defaults | A booted image where the change is visible |

State in your commit or pull request exactly what you ran and what you observed. If
something could not be tested on this hardware, say so.

Note that `xmllint` only checks that the XML is well formed. KIWI's own schema
validation is stricter, and it runs as part of the build — that is what catches
things like an invalid attribute on `<user>`. Two easy mistakes: KIWI's schema wants
`password`, not `pwd`, on a `<user>`; and XML forbids two consecutive hyphens inside
a comment, so a command line pasted into a comment will break the file.

## Building an image

Images are built inside the development VM, as root:

```sh
scripts/fetch-upstream-descriptions.sh        # once, or after changing the pin
sudo scripts/build-image.sh --clean
```

The build lands on the guest's local disk and the artefacts are published to
`kiwi/build/<profile>/`, together with a `MANIFEST.txt` recording the Fedora
release, the pinned upstream commit, the KIWI version and the SHA-256 of every
artefact. That manifest is the thing to attach to a pull request — not a claim that
a command exited 0.

## Adding a dependency

Prefer what Fedora already ships. If you need a new build-time dependency, name the
exact Fedora package, confirm it exists for the target architecture, and add it to
the `provision` block in `tools/lima/openqos-dev.yaml` so the environment stays
reproducible for everyone.

## Reporting problems

Include: what you ran, the full output, and what you expected instead. For image
problems, always include the architecture, the Fedora base release, and whether the
image booted.
