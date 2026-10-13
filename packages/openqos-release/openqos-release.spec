# openqos-release — OpenQOS Linux release identification.
#
# This is the package that makes the system say what it is. It owns
# /usr/lib/os-release, which /etc/os-release links to, and it replaces Fedora's
# identity package: OpenQOS is built from Fedora, but it is not Fedora, and the
# running system should not claim otherwise.
#
# ---
# Why Version here is Fedora's, not ours
# ---
# `fedora-release-common` Requires `fedora-release-identity = 44-18` — a
# *versioned virtual name*, pinned to that package's own version-release, and it
# is bumped with every Fedora update. Every `fedora-release-identity-*` flavour
# provides that name. So replacing one flavour is not enough: the replacement has
# to provide the virtual name at exactly the version the installed
# fedora-release-common asks for, or dnf simply picks a different flavour and the
# two fight over /usr/lib/os-release.
#
# The exact-match requirement means the version is not ours to choose. This
# package therefore carries Fedora's version-release, and OpenQOS's own version
# lives where it belongs: in the os-release content.
#
# The coupling is not left to discipline. scripts/build-packages.sh reads the
# required version from the repositories and refuses to publish if this package
# does not provide it, so a stale pin fails loudly with instructions rather than
# surfacing later as a file conflict during an image build.

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

# Satisfies fedora-release-common's versioned requirement. That requirement is
# what makes the *identity* of the distribution installable at all: with no
# provider present, dnf is free to pick any of Fedora's 61 flavours.
#
# There is deliberately no Obsoletes here. Obsoleting a flavour looks like the
# way to take its place, but it only removes that one candidate while the other
# 60 stay eligible — so dnf simply chooses a different flavour, and the failure
# reappears under a different name. Which flavour becomes ineligible is decided
# where the package set is assembled: see the <ignore> for
# `fedora-release-identity-*` in kiwi/openqos/base.xml.
Provides:       fedora-release-identity = %{version}-%{fedora_release}

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

%files
%{_prefix}/lib/os-release

%changelog
* Mon Oct 12 2026 OpenQOS contributors - 44-18
- Release identification for the Fedora 44 base, replacing the Fedora identity
  package. Version tracks fedora-release-common because its requirement on the
  identity virtual name is an exact match.
