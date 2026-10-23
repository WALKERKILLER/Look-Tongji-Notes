#!/usr/bin/env bash
# Packages a built Linux bundle as .tar.gz, .deb, .rpm, Arch .pkg.tar.zst
# and AppImage. Used by .github/workflows/release.yml; runs locally too.
#
#   app/linux/packaging/package.sh <version> <bundle dir> <out dir> [formats]
#
# formats is a space-separated subset of "tar deb rpm archlinux appimage"
# (all by default).
# The bundle must already hold lookd and agent/ (see the workflow). nfpm
# and linuxdeploy are taken from PATH; a format whose tool is missing is
# skipped with a warning.
set -euo pipefail

version=$1 bundle=$(realpath "$2") out=$(realpath -m "$3") formats=${4:-tar deb rpm archlinux appimage}
want() { case " $formats " in *" $1 "*) return 0 ;; esac; return 1; }
here=$(dirname "$(realpath "$0")")
icons=$(realpath "$here/../icons/hicolor")
mkdir -p "$out"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

case $(uname -m) in
  x86_64) arch=x64 nfpm_arch=amd64 appimage_arch=x86_64 ;;
  aarch64) arch=arm64 nfpm_arch=arm64 appimage_arch=aarch64 ;;
  *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
base="look-studio-$version-linux-$arch"

# Plain archive: the bundle plus the desktop entry and icons for a manual install.
if want tar; then
  mkdir -p "$work/$base/share/applications" "$work/$base/share/icons"
  cp -a "$bundle/." "$work/$base/"
  cp "$here/cn.lookstudio.look_studio.desktop" "$work/$base/share/applications/"
  cp -a "$icons" "$work/$base/share/icons/"
  tar -C "$work" -czf "$out/$base.tar.gz" "$base"
fi

# deb / rpm / Arch; nfpm maps a pre-release suffix to each format's rules.
if ! want deb && ! want rpm && ! want archlinux; then
  :
elif command -v nfpm >/dev/null; then
  for fmt in deb rpm archlinux; do
    want $fmt || continue
    STAGE=$bundle ICONS=$icons PACKAGING=$here VERSION=$version NFPM_ARCH=$nfpm_arch \
      nfpm package --config "$here/nfpm.yaml" --packager "$fmt" --target "$work/" >/dev/null
  done
  for f in "$work"/*.deb "$work"/*.rpm "$work"/*.pkg.tar.zst; do
    case $f in
      *.deb) mv "$f" "$out/$base.deb" ;;
      *.rpm) mv "$f" "$out/$base.rpm" ;;
      *.pkg.tar.zst) mv "$f" "$out/$base.pkg.tar.zst" ;;
    esac
  done
else
  echo "warning: nfpm not found, skipping deb, rpm and Arch packages" >&2
fi

# AppImage: the bundle under look-studio/, libmpv and its libraries under
# usr/lib (deployed by linuxdeploy, which leaves the GTK stack to the host).
if ! want appimage; then
  :
elif command -v linuxdeploy >/dev/null; then
  app="$work/AppDir"
  mkdir -p "$app/look-studio" "$app/usr/lib"
  cp -a "$bundle/." "$app/look-studio/"
  mpv=$(ldconfig -p | awk '/libmpv\.so\.[12] /{print $NF; exit}')
  [ -n "$mpv" ] || { echo "libmpv not found on the build host" >&2; exit 1; }
  icon="$work/cn.lookstudio.look_studio.png"
  cp "$icons/256x256/apps/cn.lookstudio.look_studio.png" "$icon"
  (cd "$work" && APPIMAGE_EXTRACT_AND_RUN=1 LINUXDEPLOY_OUTPUT_VERSION=$version OUTPUT="$out/$base.AppImage" ARCH=$appimage_arch \
    linuxdeploy --appdir "$app" --library "$mpv" \
      --desktop-file "$here/cn.lookstudio.look_studio.desktop" --icon-file "$icon" \
      --custom-apprun "$here/AppRun" --output appimage >/dev/null)
else
  echo "warning: linuxdeploy not found, skipping AppImage" >&2
fi

ls -1 "$out"
