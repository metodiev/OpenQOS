# Licensing, branding and trademark policy

Status: **proposal, awaiting your decision.** This document records a policy
proposal and the reasoning behind it. It is not legal advice, and it deliberately
separates facts that were checked from points that carry legal uncertainty.

## 1. Three different rights, and why they must not be conflated

Most licensing mistakes in derived distributions come from treating one right as if
it covered all three:

| Right | Governs | Granted by a software license? |
| --- | --- | --- |
| **Copyright** | Copying, modifying and distributing the code, artwork and text | Yes — this is what GPL, MIT and CC licenses deal with |
| **Trademark** | Whether you may call a thing by a given name or mark | **No.** A copyright license says nothing about names or logos |
| **Distribution obligations** | Source availability for binaries you ship | Partly — GPL and similar licenses add these conditions |

Fedora's own guidelines make the same distinction explicitly: *"Trademarks and
copyright are different rights, so regardless of what rights or permissions you may
or may not have to use the Fedora Trademarks, you always have all your rights under
any applicable free and open source software licenses."*
([Fedora Trademark Guidelines](https://docs.fedoraproject.org/en-US/legal/trademarks/))

Consequence for this project: the license on our code cannot accidentally grant, or
accidentally withhold, the right to use the OpenQOS name. That needs its own policy,
and it is in §5.

## 2. Proposal: license per material type

| Material in this repository | Proposed license | SPDX identifier | Why |
| --- | --- | --- | --- |
| Build scripts, KIWI descriptions, packaging | GPL-3.0-or-later | `GPL-3.0-or-later` | Matches the `LICENSE` already in the repository, and matches the copyleft of much of what we build on. One license for all executable/derived-work material keeps things reviewable. |
| Configuration files and defaults | GPL-3.0-or-later | `GPL-3.0-or-later` | Same reasoning. These are small files; inventing a third license for them adds confusion without benefit. |
| Documentation in `docs/` | CC BY-SA 4.0 | `CC-BY-SA-4.0` | The Creative Commons convention for prose, and the license Fedora uses for its own documentation. Share-alike keeps derived documentation open. |
| Original artwork — wallpapers, icons, logo, Plasma and SDDM themes | CC BY-SA 4.0 | `CC-BY-SA-4.0` | Creative Commons is the normal choice for design assets, and share-alike prevents a later closed derivative of the visual identity. |
| Any font we create | SIL OFL 1.1 | `OFL-1.1` | The near-universal license for fonts, and what Fedora's font packaging expects. |
| The OpenQOS **name and logo as marks** | **Not a copyright license** — see §5 | — | A trademark policy is a separate track. |

Why `or-later` rather than the bare GPL-3.0 text currently in `LICENSE`: it lets
OpenQOS adopt a future GPL version if the ecosystem moves, without a relicensing
exercise. This is a decision you should make deliberately; if you prefer to pin
exactly GPL-3.0, say so and the documentation will say `GPL-3.0-only` instead.

## 3. Upstream Fedora components are not ours to relicense

This is the most important rule in the document:

* Every Fedora RPM we redistribute keeps **its own** license and copyright notices.
  GPL-licensed packages stay GPL; MIT packages stay MIT; CC0 packages stay CC0.
* We must **not** claim our project license covers bundled upstream content. The
  top-level `LICENSE` file covers original OpenQOS material only, and it must say so.
* Where we modify or patch an upstream package (which should be rare, and always
  deliberate), the modification is itself licensed under that package's license,
  not ours.
* Every bundled package's license and copyright notices must be preserved on the
  installed system, exactly as Fedora does.

### Practical obligation: we become a redistributor

The moment an OpenQOS image contains GPL binaries, we are distributing those
binaries and inherit the source-availability obligations that come with them. Fedora
publishes corresponding source for all of its packages, which makes compliance
achievable — but it has to be *designed in*, not assumed:

1. **Record exactly which repositories and compose the image drew from.** A release
   must be traceable to a specific Fedora compose.
2. **Never ship locally rebuilt or patched Fedora binaries without also publishing
   the corresponding source** alongside them.
3. **Keep the source offer reachable.** The release documentation must say where the
   corresponding source can be obtained for the packages in that image.
4. **Do not strip copyright or license files.** Anything Fedora puts in
   `/usr/share/licenses/` must still be there.

Items 1–4 are release-engineering requirements, and they are what makes
[roadmap](roadmap.md) Milestone 10 more than a formality.

### Per-package license inventory

Before the first public release we need a machine-generated inventory of the licenses
of everything in the image, so that redistribution is verifiable rather than assumed.
Fedora provides the data for this: each installed RPM records its license, and
`/usr/share/licenses/` holds the texts. Generating this inventory is a Milestone 10
task, and no release should happen without it.

## 4. Current state of this repository

| File | State | Proposed change |
| --- | --- | --- |
| [`LICENSE`](../LICENSE) | Verbatim GNU GPL version 3 text (674 lines). It is the standard FSF document, which carries *the FSF's* copyright line and no statement about what it applies to. | Keep the license text unmodified, and add a short scope statement so it is unambiguous that it covers original OpenQOS material and **not** bundled Fedora components. |
| Per-file notices | Partial. The files derived from Fedora carry SPDX headers; most original files do not yet. | Add SPDX headers as files are created, and adopt [REUSE](https://reuse.software/) conventions so license information is machine-checkable in CI. |
| `README.md` | States the project license. | Keep in sync with this document. |

### Files copied from Fedora, and why they carry Fedora's copyright

Most of Fedora's descriptions are *included* at build time, not copied, so they stay
their files and their notices are untouched. Two files are copied, because KIWI offers
no way to subtract from a file:

| Ours | Fedora's | Licence |
| --- | --- | --- |
| [`kiwi/openqos/desktop-common.xml`](../kiwi/openqos/desktop-common.xml) | `upstream/components/desktops/common.xml` | GPL-3.0-or-later |
| [`kiwi/templates/grub-arm.cfg.iso-template`](../kiwi/templates/grub-arm.cfg.iso-template) | `upstream/grub-arm.cfg.iso-template` | GPL-3.0-or-later |

[`forge.fedoraproject.org/releng/kiwi-descriptions`](https://forge.fedoraproject.org/releng/kiwi-descriptions)
is GPL-3.0-or-later (`COPYING` in that repository). Both copied files therefore carry
**Fedora's** copyright line alongside OpenQOS's, with the OpenQOS contribution stated as
the delta and nothing more. Written out here so the obligation is visible rather than
implied by a file header nobody reads.

The licences are compatible with this repository's own GPL-3.0, so there is no conflict
to resolve — but a derived file is still their file, and deleting the notice would be
wrong regardless of compatibility.

Note on the GPLv3 text itself: the document at
<https://www.gnu.org/licenses/gpl-3.0.txt> is a license *form*, not a per-project
notice. It contains no project copyright holder and no statement of which version
applies to your files. That is expected — the project supplies that notice
separately. This is a documentation gap right now, not a defect in the license
choice.

## 5. Branding and trademark policy (separate track)

### What the situation actually is

* Copyright licenses grant nothing in the way of name or logo rights. So neither
  GPL-3.0-or-later nor CC BY-SA 4.0 gives anyone permission to call something
  "OpenQOS" or to use the OpenQOS logo.
* Trademark rights arise from use in commerce and, in many jurisdictions, are
  strengthened by registration. I have not performed, and cannot perform, a
  trademark clearance search. **"OpenQOS" may already be in use by someone else,
  and this document must not be read as clearing it.**
* A free-software license cannot be used to make a mark free for all uses, because a
  trademark's function is to indicate a single source. Copyleft keeps the *code*
  open; the *mark* still needs controlling, or the name stops meaning anything.

### Proposed policy

| Question | Proposal |
| --- | --- |
| Who may use the name for an unmodified, official build? | Only official OpenQOS release artefacts. |
| May others redistribute modified builds? | Yes — the code license guarantees that. But modified builds must be renamed, following the practice Fedora itself requires via its Fedora Remix programme. |
| May others use the logo? | For unmodified official builds, and for factual statements like "based on OpenQOS", with an attribution/notice requirement. |
| May the logo be used to imply endorsement? | No. |
| What happens to the artwork license then? | It stays CC BY-SA 4.0, so others may *reuse and adapt* the artwork. The mark policy governs *using it as a brand for their own product*, which is a different thing. |

### Legal uncertainty, stated plainly

* **Name availability is unknown.** A search of relevant trademark registers
  (for example [USPTO TSDR/TESS](https://tmsearch.uspto.gov/) for the United States,
  EUIPO for the EU) and a domain/package-name check should happen before any public
  release. Treat "OpenQOS" as a working title, as the README does.
* **Jurisdiction matters.** A name can be clear in one jurisdiction and blocked in
  another. This project has no stated jurisdiction yet.
* **Fedora's own marks.** Because we build on Fedora, we must also comply with
  [Fedora's Trademark Guidelines](https://docs.fedoraproject.org/en-US/legal/trademarks/),
  which reserve Fedora marks including "Fedora Remix". Two consequences worth
  checking before the first image ships:
  * We should **not** present OpenQOS as "Fedora" or as an official Fedora product.
    Accurate phrasing is "based on Fedora Linux" plus a statement that OpenQOS is not
    affiliated with or endorsed by Red Hat or the Fedora Project.
  * Fedora's image descriptions install `fedora-release` (and `fedora-release-kde`)
    to provide `/etc/os-release` and branding. Replacing that with our own
    `openqos-release` package is the technical step; whether the replacement is
    *permitted* is a trademark question to settle with Fedora's guidelines, not a
    technical one.

    As first implemented at Milestone 7, that replacement was deliberately narrow.
    It has since been widened, and this is the record of it. OpenQOS now removes the
    whole `fedora-release*` family, `fedora-release` and `fedora-release-common`
    included, so `/etc/system-release`, `/etc/fedora-release` and
    `/etc/redhat-release` do not exist in an image at all.

    `openqos-release` takes over `/usr/lib/os-release` and the `/etc/os-release`
    symlink, and it no longer provides the `fedora-release-identity` virtual name:
    nothing asks for it once `fedora-release-common` is gone, and providing it would
    assert a relationship to a package that is not installed. It still provides
    `system-release` and `system-release(44)`, which is what `setup` and
    `fedora-repos` require — so this is a removal that leaves the packaging
    interface satisfied, not a packaging fight.

    What is *not* removed is the attribution, and that distinction is the point.
    `openqos-release` keeps `ID_LIKE="fedora"` and `PLATFORM_ID="platform:f44"` so
    the Fedora base stays visible to tooling and to users, and `fedora-repos` stays
    installed. Removing the name from `/etc` is a statement about what the running
    system *is*; the base, and the credit for it, are still declared.

    Fedora's marks are why this matters for compliance rather than tidiness. A file
    named `fedora-release` whose contents read "Fedora release 44 (Forty Four)"
    invites exactly the reading that Fedora's trademark guidelines reserve — that
    this is a Fedora product rather than a derived one. Removing it is the
    conservative choice, and it is a related but separate decision from the
    trademark question above.
* **Asset provenance.** Every wallpaper, icon and font we ship must be our own work or
  under a license that permits our use and redistribution. Third-party assets with
  unclear or non-commercial terms must not enter `branding/`. A provenance file per
  asset is cheap insurance.

  This is also why Fedora's wallpaper packages are excluded. `f44-backgrounds-base`
  ships CC-BY-SA-4.0 wallpaper sets together with the attribution that license
  requires, and `f44-backgrounds-kde` mirrors them into `/usr/share/wallpapers/F44`
  for KDE. Both are now excluded, alongside the `desktop-backgrounds-kde`
  metapackage that reached them, so the obligation does not arise: the image ships
  only OpenQOS artwork, `branding/` records its provenance, and
  `/usr/share/wallpapers/Default` — a path `desktop-backgrounds-kde` owned — now
  points at the OpenQOS wallpaper. Excluding them also takes "Fedora" and "F44" out
  of Plasma's wallpaper picker.

  One trace is deliberately left, and it is worth recording rather than chasing
  further. `/usr/share/wallpapers/Fedora` is a symlink owned by
  `kde-settings-plasma`, which `plasma-workspace` requires, so no exclude reaches
  it; `openqos-branding` deletes it in `%posttrans` instead. Where that scriptlet
  cannot run, the name survives — but the artwork behind it is OpenQOS's either way,
  because the symlink resolves to `/usr/share/wallpapers/Default`.
* **Nothing here is legal advice**, and none of it substitutes for review by a lawyer
  qualified in the relevant jurisdiction before a public release.

## 6. Mechanics

* **SPDX headers** on every source, script and configuration file, of the form
  `SPDX-License-Identifier: GPL-3.0-or-later` plus an `SPDX-FileCopyrightText` line.
* **REUSE layout** ([spec 3.3](https://reuse.software/spec-3.3/)):
  ```
  LICENSES/
    GPL-3.0-or-later.txt
    CC-BY-SA-4.0.txt
    OFL-1.1.txt
  ```
  with the top-level `LICENSE` stating the default and pointing at `LICENSES/`.
* **CI check.** Once the layout exists, a REUSE lint in
  `.github/workflows/` keeps it honest. This is a Milestone 10 task.
* **`branding/` provenance.** Each asset directory carries a short note recording the
  author, the license, and — for anything not created for this project — the source.

## 7. Decisions requested

1. Confirm GPL-3.0-**or-later** for code, scripts, configuration and packaging, or
   choose `GPL-3.0-only` to match the current `LICENSE` text literally.
2. Confirm CC BY-SA 4.0 for documentation and artwork, or propose alternatives.
3. Confirm that the OpenQOS name and logo will be handled by a separate mark policy
   (and that the working title is accepted as unresolved pending a clearance search).
