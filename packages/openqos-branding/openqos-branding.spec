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
Release:        1%{?dist}
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

install -d %{buildroot}%{_datadir}/color-schemes
install -m 0644 themes/OpenQOS.colors \
	%{buildroot}%{_datadir}/color-schemes/OpenQOS.colors

install -d %{buildroot}%{_datadir}/plymouth/themes/openqos
install -m 0644 plymouth/openqos/openqos.plymouth plymouth/openqos/watermark.png \
	%{buildroot}%{_datadir}/plymouth/themes/openqos/

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
%{_datadir}/color-schemes/OpenQOS.colors
%{_datadir}/plymouth/themes/openqos
%{_datadir}/icons/hicolor/scalable/apps/openqos-logo.svg
%{_datadir}/icons/hicolor/256x256/apps/openqos-logo.png
%{_datadir}/icons/hicolor/48x48/apps/openqos-logo.png

%changelog
* Mon Oct 12 2026 OpenQOS contributors - 0.1-1
- Initial branding: mark and lockup in light and dark variants, default wallpaper,
  OpenQOS Plasma colour scheme, Plymouth boot splash, and the hicolor icon named by
  LOGO=openqos-logo in os-release.
