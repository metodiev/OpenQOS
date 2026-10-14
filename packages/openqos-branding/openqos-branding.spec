# openqos-branding — the OpenQOS visual identity.
#
# The artwork itself is CC-BY-SA-4.0, which is why this package's License field
# differs from the code packages. branding/PROVENANCE.md records the authorship of
# every asset and is installed as the package's licence file; the full licence text
# is not yet bundled, which must be fixed before a release (docs/licensing.md).
#
# Nothing here is rendered at build time. The raster assets are committed, produced
# from the SVGs by branding/tools/render-assets.py, deliberately: rendering inside
# rpmbuild would make the package's contents depend on the build machine's librsvg
# version, and two machines would then produce two different "identical" packages.
# branding/tools/render-assets.py --check is what catches a stale asset instead.

%global branding_release 0.1

Name:           openqos-branding
Version:        %{branding_release}
Release:        2%{?dist}
Summary:        OpenQOS visual identity: logo, wallpaper, colour scheme and boot splash

License:        CC-BY-SA-4.0
URL:            https://github.com/metodiev/OpenQOS
Source0:        openqos-branding.tar.gz

BuildArch:      noarch

# hicolor is the fallback icon theme, and the icon named by LOGO=openqos-logo in
# os-release is installed into it. No Requires for Plasma: the wallpaper and colour
# scheme are inert without it, and a minimal image still needs the logo and the
# icon, so a hard dependency would drag a desktop into every profile.
Requires:       hicolor-icon-theme

# Satisfies the `system-logos` virtual name, which this package has to take over
# rather than merely compete for.
#
# Two packages provide it: Fedora's fedora-logos and the stand-in generic-logos.
# Both also own /usr/share/pixmaps/system-logo-white.png, the file dracut copies
# into the initramfs for the boot splash. Excluding only fedora-logos does not
# remove that file; it makes dnf satisfy the requirement with generic-logos
# instead, and the image then fails to build with a file conflict between the two
# -- which is how this was found. Excluding both leaves one provider, so the
# outcome is deterministic rather than whichever one dnf happens to prefer.
#
# Unversioned is enough here, and that was checked rather than assumed: every
# package that requires `system-logos` in the installed set asks for it without a
# version, including kde-settings-plasma and plymouth-graphics-libs. That is what
# makes this unlike fedora-release-identity, which is required at an exact version
# and is why openqos-release has to carry Fedora's version-release.
Provides:       system-logos

# The name kde-settings-plasma, kde-settings-plasmalogin and plasma-setup actually
# ask for.
#
# Fedora satisfies it with desktop-backgrounds-kde, a metapackage that provides both
# `desktop-backgrounds-kde` and `system-backgrounds-kde`, and whose only job is to
# require f44-backgrounds-kde, which in turn requires f44-backgrounds-base at an
# *exact* version. Those two ship Fedora's wallpapers, and OpenQOS excludes all
# three so the Plasma wallpaper picker stops offering "F44".
#
# The name to provide is `system-backgrounds-kde`, not the package's own name, and
# that is worth recording. `repoquery --whatrequires desktop-backgrounds-kde` lists
# those three packages, which reads as though they require it by name. They do not:
# repoquery --whatrequires resolves capabilities, so it was answering a different
# question than it appeared to. The build answered it precisely, once, by failing
# with "requires system-backgrounds-kde, but none of the providers can be
# installed".
#
# Providing the capability rather than Fedora's release-specific package names is
# deliberate: this name does not churn with the Fedora release the way
# f44-backgrounds-base does, so nothing here needs re-pinning.
Provides:       system-backgrounds-kde

# No Recommends on plymouth either, and that is not an oversight. The boot splash
# theme does nothing without Plymouth, but the images install packages with
# plusRecommended, so a Recommends here would pull Plymouth and its libraries into
# the minimal image — which exists precisely to be the smallest thing that boots.
# A missing theme is not a failure: Plymouth falls back to its built-in default.

%description
The OpenQOS visual identity: the mark and lockup, the default wallpaper, the Plasma
colour scheme, and the Plymouth boot splash.

The artwork is original work made for this project, not derived from Fedora's, KDE's
or anyone else's assets. See the installed PROVENANCE.md for authorship, licences,
how each raster file is generated from its vector source, and the limitations that
are known about the current assets.

%prep
%setup -q -n openqos-branding

%build
# Nothing to build. See the note at the top on why rendering lives outside rpmbuild.

%install
install -d %{buildroot}%{_datadir}/wallpapers/OpenQOS/contents/images
install -m 0644 wallpapers/metadata.json \
	%{buildroot}%{_datadir}/wallpapers/OpenQOS/metadata.json
install -m 0644 wallpapers/contents/images/*.png \
	%{buildroot}%{_datadir}/wallpapers/OpenQOS/contents/images/
install -m 0644 wallpapers/contents/screenshot.png \
	%{buildroot}%{_datadir}/wallpapers/OpenQOS/contents/screenshot.png

# desktop-backgrounds-kde owned this path, and it is the name Plasma and some
# configuration files use when they want "the default wallpaper". Pointing it at
# ours keeps that working once Fedora's packages are excluded, and makes the answer
# a distribution wallpaper rather than a missing directory.
ln -s OpenQOS %{buildroot}%{_datadir}/wallpapers/Default

install -d %{buildroot}%{_datadir}/color-schemes
install -m 0644 themes/OpenQOS.colors \
	%{buildroot}%{_datadir}/color-schemes/OpenQOS.colors

install -d %{buildroot}%{_datadir}/plymouth/themes/openqos
install -m 0644 plymouth/openqos/openqos.plymouth plymouth/openqos/watermark.png \
	%{buildroot}%{_datadir}/plymouth/themes/openqos/

# The logo the initramfs carries. dracut copies /usr/share/pixmaps/system-logo-white.png
# into the initramfs unconditionally, so whatever sits at this path is what the early
# boot splash is able to draw when the configured theme cannot be loaded. Fedora's
# fedora-logos owns this path and is excluded from the image, which is what frees it.
#
# Takes the inverse (light-on-dark) mark rather than the primary lockup, because the
# two consumers of this file both place it on a dark background. The name is
# upstream's and is kept: it is the path dracut looks for.
install -d %{buildroot}%{_datadir}/pixmaps
install -m 0644 logo/dist/openqos-mark-inverse.png \
	%{buildroot}%{_datadir}/pixmaps/system-logo-white.png

# Pins the splash theme into the initramfs. Relying on dracut's own theme handling
# is what produced a Fedora logo on the boot screen; see the file's own header.
install -d %{buildroot}%{_prefix}/lib/dracut/dracut.conf.d
install -m 0644 dracut/50-openqos-plymouth.conf \
	%{buildroot}%{_prefix}/lib/dracut/dracut.conf.d/50-openqos-plymouth.conf

install -d %{buildroot}%{_datadir}/icons/hicolor/scalable/apps
install -d %{buildroot}%{_datadir}/icons/hicolor/256x256/apps
install -d %{buildroot}%{_datadir}/icons/hicolor/48x48/apps
install -m 0644 icons/hicolor/scalable/apps/openqos-logo.svg \
	%{buildroot}%{_datadir}/icons/hicolor/scalable/apps/openqos-logo.svg
install -m 0644 icons/hicolor/256x256/apps/openqos-logo.png \
	%{buildroot}%{_datadir}/icons/hicolor/256x256/apps/openqos-logo.png
install -m 0644 icons/hicolor/48x48/apps/openqos-logo.png \
	%{buildroot}%{_datadir}/icons/hicolor/48x48/apps/openqos-logo.png

# No icon-cache scriptlet, deliberately. hicolor is the fallback theme and GTK looks
# it up directly, so there is nothing to refresh; adding a %post that calls
# gtk-update-icon-cache would mean a Requires(post) on GTK, which would pull a
# toolkit into the minimal image to keep a cache warm that is not read.

%files
%license PROVENANCE.md
%{_datadir}/wallpapers/OpenQOS
%{_datadir}/wallpapers/Default
%{_datadir}/color-schemes/OpenQOS.colors
%{_datadir}/plymouth/themes/openqos
%{_datadir}/pixmaps/system-logo-white.png
%{_prefix}/lib/dracut/dracut.conf.d/50-openqos-plymouth.conf
%{_datadir}/icons/hicolor/scalable/apps/openqos-logo.svg
%{_datadir}/icons/hicolor/256x256/apps/openqos-logo.png
%{_datadir}/icons/hicolor/48x48/apps/openqos-logo.png

# ----------------------------------------------------------------- scriptlet ---
%posttrans
# /usr/share/wallpapers/Fedora is a symlink owned by kde-settings-plasma, and it is
# the last place an OpenQOS image says "Fedora" where a user can see it: Plasma's
# wallpaper picker lists it by name. The artwork behind it is already ours, because
# kde-settings-plasma points Fedora at /usr/share/wallpapers/Default and this
# package points Default at OpenQOS. Only the label was left.
#
# There is no declarative way to remove it. kde-settings-plasma is required by
# plasma-workspace, so no exclude reaches it, and rpm has no "drop this file"
# primitive. A scriptlet is the only mechanism that works.
#
# %posttrans rather than %post, deliberately: within one dnf transaction the install
# order is not ours to choose, and kde-settings-plasma may be installed after this
# package. %posttrans runs once the transaction is complete, so a later install
# cannot put the symlink back.
#
# Accepted consequence: `rpm -V kde-settings-plasma` reports one missing file for as
# long as this package is installed. Nothing reads the path, and the alternative is a
# name in the wallpaper picker that contradicts every other surface of the system.
#
# The test is for a symlink rather than mere existence, so that a future Fedora
# release shipping a real directory here is left alone instead of deleted.
if [ -L %{_datadir}/wallpapers/Fedora ]; then
	rm -f %{_datadir}/wallpapers/Fedora
fi

%changelog
* Tue Oct 13 2026 OpenQOS contributors - 0.1-2
- Provide system-backgrounds-kde so Fedora's wallpaper packages can be excluded,
  ship /usr/share/wallpapers/Default for the paths desktop-backgrounds-kde owned,
  and drop the Fedora-named wallpaper symlink in %posttrans.
* Mon Oct 12 2026 OpenQOS contributors - 0.1-1
- Initial branding: mark and lockup in light and dark variants, default wallpaper,
  OpenQOS Plasma colour scheme, Plymouth boot splash, and the hicolor icon named by
  LOGO=openqos-logo in os-release.
