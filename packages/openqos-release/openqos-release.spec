# openqos-release — OpenQOS Linux release identification.
#
# This is the package that makes the system say what it is. It owns
# /usr/lib/os-release and the /etc/os-release symlink that points at it, and it
# replaces Fedora's identity package: OpenQOS is built from Fedora, but it is not
# Fedora, and the running system should not claim otherwise.
#
# ---
# Why Version here is Fedora's, not ours
# ---
# The version is not ours to choose. Excluding Fedora's release packages makes
# this package responsible for the requirements that made them necessary, and one
# of those carries Fedora's release number inside the capability *name*:
#
#   setup        Requires: system-release        (bare)
#   fedora-repos Requires: system-release(44)    (the number is in the name)
#
# So the major version tracks Fedora's release, and Release tracks
# fedora-release-common's, which is bumped with every Fedora update. OpenQOS's own
# version lives where it belongs: in the os-release content.
#
# The coupling is not left to discipline. scripts/build-packages.sh reads the
# required capability from the repositories and refuses to publish if this package
# does not provide it, so a stale pin fails loudly, with instructions, rather than
# surfacing later as an unresolvable requirement during an image build.

# The Fedora version-release our identity replaces, kept separate from Release:
# because Release: carries %%{?dist}, and the requirement we have to satisfy is
# on the bare number. Drop this macro into the Provides and it expands to
# 44-18.fc44, which matches nothing.
#
# (Macros above are written %% escaped because rpm expands them even inside
# comments, and an unescaped one produces forty lines of build warnings.)
%global fedora_release 18

Name:           openqos-release
Version:        44
Release:        %{fedora_release}%{?dist}
Summary:        OpenQOS Linux release identification

License:        GPL-3.0-or-later
URL:            https://github.com/metodiev/OpenQOS
Source0:        os-release

BuildArch:      noarch

# There is deliberately no `fedora-release-identity` Provide here any more, and
# deliberately no Obsoletes.
#
# The Provide existed because fedora-release-common requires
# `fedora-release-identity = <version>-<release>` as an exact match. OpenQOS now
# excludes fedora-release-common itself, along with the rest of that family, so
# nothing asks for the name. Keeping it would assert a relationship to a package
# that is not installed.
#
# Obsoleting the identity packages was never workable in any case: it removes one
# candidate out of 61 while the rest stay eligible, so dnf picks another and the
# failure reappears under a different name. Which candidates are ineligible is
# decided where the package set is assembled, not here. See the `fedora-release*`
# ignore in kiwi/openqos/base.xml and kiwi/OpenQOS.kiwi.

# Satisfies the two requirements on the release identity, which is what makes
# fedora-release removable at all. The forms are not interchangeable:
#
#   setup        Requires: system-release        (bare)
#   fedora-repos Requires: system-release(44)    (the Fedora release number)
#
# The second is Fedora's own idiom: a capability whose *name* carries the release
# number. fedora-release declares both, so this has to as well. %%{version} is
# already Fedora's release version for the reason described at the top of this
# file, so these follow the base when the base moves rather than needing an edit.
Provides:       system-release
Provides:       system-release(%{version})

%description
Defines the identity of OpenQOS Linux in /usr/lib/os-release.

OpenQOS is built from Fedora Linux and says so, in the fields that exist for
exactly that purpose: ID_LIKE="fedora" and PLATFORM_ID="platform:f44". It does
not claim to be Fedora, and it does not claim to be a Red Hat product.

%prep
# No source to unpack: this package ships a file, not a build.

%build
# Nothing to build.

%install
install -D -p -m 0644 %{SOURCE0} %{buildroot}%{_prefix}/lib/os-release

# /etc/os-release is the location every tool actually reads, and it is a symlink
# rather than a second copy so there is one file to edit and no way for the two to
# disagree. Fedora's release packages own this path; OpenQOS excludes them, and
# openqos-release would otherwise leave a system with no /etc/os-release at all.
install -d %{buildroot}%{_sysconfdir}
ln -s ../usr/lib/os-release %{buildroot}%{_sysconfdir}/os-release

%files
%{_prefix}/lib/os-release
%{_sysconfdir}/os-release

%changelog
* Mon Oct 12 2026 OpenQOS contributors - 44-18
- Release identification for the Fedora 44 base, replacing the Fedora identity
  package. Version tracks fedora-release-common because its requirement on the
  identity virtual name is an exact match.
