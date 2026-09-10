#!/bin/zsh
# Builds Slant.app next to this script.
#   --install  copies it into /Applications and relaunches it
#   --dmg      also produces Slant.dmg
# SIGN_IDENTITY picks the codesign identity. Defaults to the local "Slant Dev"
# certificate when the keychain has one (scripts/make-dev-cert.sh creates it), else
# ad-hoc. A stable identity matters: macOS ties the Screen Recording grant to the
# signature, and ad-hoc signatures change on every build.
set -euo pipefail
cd "${0:A:h}"
swift build -c release
APP="Slant.app"
rm -rf "$APP" .build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swift scripts/make-icon.swift --symbol laptopcomputer --from 9FB8D6 --to 3D5273 --glyph FFFFFF --scale 0.50 \
  --out .build/AppIcon.iconset --icns "$APP/Contents/Resources/AppIcon.icns" >/dev/null
cp .build/release/Slant "$APP/Contents/MacOS/Slant"
cp Info.plist "$APP/Contents/Info.plist"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q '"Slant Dev"'; then SIGN_IDENTITY="Slant Dev"; else SIGN_IDENTITY="-"; fi
fi
codesign --force --sign "$SIGN_IDENTITY" --options runtime "$APP"
echo "Built $PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Slant 2>/dev/null || true
  rm -rf /Applications/Slant.app
  cp -R "$APP" /Applications/Slant.app
  open /Applications/Slant.app
  echo "Installed /Applications/Slant.app"
fi

if [[ "${1:-}" == "--dmg" ]]; then
  STAGE=".build/dmg"
  rm -rf "$STAGE" Slant.dmg
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -quiet -volname "Slant" -srcfolder "$STAGE" -ov -format UDZO Slant.dmg
  echo "Built $PWD/Slant.dmg"
fi
