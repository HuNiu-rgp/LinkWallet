#!/bin/bash
# Build and package the Apple Silicon macOS release from the project root.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "This release configuration requires an Apple Silicon Mac." >&2
  exit 1
fi
RELEASE_VERSION="$(awk '/^version:/ { split($2, parts, "+"); print parts[1]; exit }' pubspec.yaml)"
if [[ ! "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Cannot read a semantic version from pubspec.yaml." >&2
  exit 1
fi
RELEASE_NAME="LinkWallet-${RELEASE_VERSION}-macos-arm64"
RELEASE_OUT="$PROJECT_ROOT/dist"
RELEASE_APP="$PROJECT_ROOT/build/macos/Build/Products/Release/LinkWallet.app"
RELEASE_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/linkwallet-release.XXXXXX")"
trap 'rm -rf "$RELEASE_STAGE"' EXIT

case "${1:-}" in
  "")
    flutter pub get
    flutter analyze --no-pub
    flutter test --no-pub
    flutter build macos --release --no-pub
    ;;
  --package-only) ;; # Repackage an already built and validated local app.
  *) echo "Usage: $0 [--package-only]" >&2; exit 2 ;;
esac
# Flutter can update App.framework after Xcode seals the outer app. Re-sign the
# compiled Dart framework, then the app, keeping its identifier and sandbox.
codesign --force --sign - --timestamp=none --preserve-metadata=identifier,flags \
  "$RELEASE_APP/Contents/Frameworks/App.framework"
codesign --force --sign - --timestamp=none --preserve-metadata=identifier,flags \
  --entitlements "$PROJECT_ROOT/macos/Runner/Release.entitlements" "$RELEASE_APP"
codesign --verify --deep --strict "$RELEASE_APP"

mkdir -p "$RELEASE_OUT"
ditto "$RELEASE_APP" "$RELEASE_STAGE/LinkWallet.app"
ln -s /Applications "$RELEASE_STAGE/Applications"
hdiutil create -volname "LinkWallet ${RELEASE_VERSION}" \
  -srcfolder "$RELEASE_STAGE" -format UDZO -ov "$RELEASE_OUT/$RELEASE_NAME.dmg"
ditto -c -k --sequesterRsrc --keepParent "$RELEASE_APP" "$RELEASE_OUT/$RELEASE_NAME.zip"
(
  cd "$RELEASE_OUT"
  shasum -a 256 "$RELEASE_NAME.dmg" "$RELEASE_NAME.zip" > SHA256SUMS
)
echo "Release packages: $RELEASE_OUT"
