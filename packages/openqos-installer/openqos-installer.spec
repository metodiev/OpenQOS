# openqos-installer — the OpenQOS installer integration.
#
# What this package is: the launcher, the kickstart that defines an installation,
# and the pieces for installing unattended. The installer itself is Anaconda,
# Fedora's; nothing here replaces it. See the installed README.md for the paths
# and for how each one is used.
#
# Why a package and not configuration files in the image: the launchers must be
# executable, and they must be executable with the same modes on every build. KIWI
# overlays are installed from a copy step whose permissions are not part of the
# description, while rpm carries the mode with the file.
#
# This package is installed on live media only (kiwi/openqos/kde.xml), which is
# what keeps `Requires: anaconda-core` from pulling the installer into the
# pre-installed disk images.

%global installer_release 0.1

Name:           openqos-installer
Version:        %{installer_release}
Release:        1%{?dist}
Summary:        The OpenQOS installer launcher and the kickstart that defines an installation

License:        GPL-3.0-or-later
URL:            https://github.com/metodiev/OpenQOS
Source0:        openqos-installer.tar.gz

BuildArch:      noarch

# anaconda-core has the installer and its command-line options; anaconda-webui has
# /usr/libexec/anaconda/webui-desktop, which starts the Cockpit service and opens a
# browser on the Web UI. Both are asked for explicitly rather than through
# anaconda-live, because this package does not use liveinst: --liveinst is the flag
# that makes Anaconda ignore kickstarts.
Requires:       anaconda-core
Requires:       anaconda-webui
# pkexec, and the polkit daemon that answers it.
Requires:       polkit

BuildRequires:  systemd-rpm-macros

%description
The OpenQOS installer integration: the desktop launcher, the kickstart that
defines what an installation produces, and the service that installs unattended
when the media are booted with inst.ks=.

Anaconda does the installing. This package exists because Anaconda's live-install
mode ignores kickstarts by design, which would otherwise leave the layout,
bootloader arguments and accounts of an installed OpenQOS machine defined by
whatever Anaconda's defaults happen to be. With this package they are defined by
kickstart/openqos.ks in the OpenQOS source repository, the same file that
kiwi/openqos/disk.xml is kept in step with.

%prep
%setup -q -n openqos-installer

%build
# Nothing to build: shell, unit files and one kickstart.

%install
install -D -m 0755 usr/bin/openqos-install %{buildroot}%{_bindir}/openqos-install
install -D -m 0755 usr/bin/openqos-install-root %{buildroot}%{_bindir}/openqos-install-root

install -D -m 0755 usr/libexec/openqos/openqos-install-setup \
	%{buildroot}%{_libexecdir}/openqos/openqos-install-setup
install -D -m 0755 usr/libexec/openqos/openqos-autoinstall \
	%{buildroot}%{_libexecdir}/openqos/openqos-autoinstall

install -D -m 0644 usr/lib/systemd/system/openqos-autoinstall.service \
	%{buildroot}%{_unitdir}/openqos-autoinstall.service
install -D -m 0644 usr/lib/systemd/system-preset/90-openqos.preset \
	%{buildroot}%{_presetdir}/90-openqos.preset

install -D -m 0644 etc/xdg/autostart/zz-openqos-install.desktop \
	%{buildroot}%{_sysconfdir}/xdg/autostart/zz-openqos-install.desktop
install -D -m 0644 usr/share/applications/org.openqos.installer.desktop \
	%{buildroot}%{_datadir}/applications/org.openqos.installer.desktop
install -D -m 0644 usr/share/polkit-1/actions/org.openqos.installer.policy \
	%{buildroot}%{_datadir}/polkit-1/actions/org.openqos.installer.policy

install -D -m 0644 openqos.ks \
	%{buildroot}%{_datadir}/openqos/kickstart/openqos.ks

%post
%systemd_post openqos-autoinstall.service

%preun
%systemd_preun openqos-autoinstall.service

%postun
%systemd_postun openqos-autoinstall.service

%files
%license LICENSE
%doc README.md
%{_bindir}/openqos-install
%{_bindir}/openqos-install-root
%{_libexecdir}/openqos
%{_unitdir}/openqos-autoinstall.service
%{_presetdir}/90-openqos.preset
%{_sysconfdir}/xdg/autostart/zz-openqos-install.desktop
%{_datadir}/applications/org.openqos.installer.desktop
%{_datadir}/polkit-1/actions/org.openqos.installer.policy
%{_datadir}/openqos/kickstart/openqos.ks

%changelog
* Tue Oct 13 2026 OpenQOS contributors - 0.1-1
- Initial installer integration: the "Install OpenQOS" launcher, the kickstart that
  defines an installation, and unattended installation driven by inst.ks=.
