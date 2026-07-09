#!/usr/bin/env bash
#
# Builds MacDictationNotion into a proper .app bundle (menu-bar app) and ad-hoc
# code-signs it so that microphone / speech / notification permissions work.
#
# Usage:
#   ./build.sh          # build the .app bundle
#   ./build.sh run      # build, then launch the app
#
set -euo pipefail

APP_NAME="MacDictationNotion"
BUNDLE="${APP_NAME}.app"
BIN=".build/release/${APP_NAME}"
CONTENTS="${BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"

cd "$(dirname "$0")"

echo "▶︎ Building (release)…"
swift build -c release

echo "▶︎ Assembling ${BUNDLE}…"
rm -rf "${BUNDLE}"
mkdir -p "${MACOS_DIR}"
cp "${BIN}" "${MACOS_DIR}/${APP_NAME}"
cp "Resources/Info.plist" "${CONTENTS}/Info.plist"

echo "▶︎ Ad-hoc code signing…"
codesign --force --deep --sign - "${BUNDLE}"

echo "✅ Done → ${BUNDLE}"

if [[ "${1:-}" == "run" ]]; then
    echo "▶︎ Launching…"
    open "${BUNDLE}"
else
    echo "   Launch with:  open ${BUNDLE}"
fi
