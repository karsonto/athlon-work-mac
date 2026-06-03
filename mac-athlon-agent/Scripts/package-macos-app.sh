#!/usr/bin/env bash
# Assemble Athlon Agent.app from `swift build -c release` output.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/.build/release}"
APP_NAME="${APP_NAME:-Athlon Agent}"
BUNDLE_DIR="${BUNDLE_DIR:-$ROOT/dist/${APP_NAME}.app}"
EXEC_NAME="AthlonAgent"
RESOURCE_BUNDLE="${BUILD_DIR}/${EXEC_NAME}_${EXEC_NAME}.bundle"

if [[ ! -f "${BUILD_DIR}/${EXEC_NAME}" ]]; then
  echo "error: missing ${BUILD_DIR}/${EXEC_NAME} — run: swift build -c release --product AthlonAgent" >&2
  exit 1
fi

if [[ ! -d "${RESOURCE_BUNDLE}" ]]; then
  echo "error: missing ${RESOURCE_BUNDLE} (SwiftPM resource bundle)" >&2
  exit 1
fi

rm -rf "${BUNDLE_DIR}"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS" "${BUNDLE_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${EXEC_NAME}" "${BUNDLE_DIR}/Contents/MacOS/${EXEC_NAME}"
chmod +x "${BUNDLE_DIR}/Contents/MacOS/${EXEC_NAME}"

cp "${ROOT}/AthlonAgent/Info.plist" "${BUNDLE_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${EXEC_NAME}" "${BUNDLE_DIR}/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string ${EXEC_NAME}" "${BUNDLE_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${APP_NAME}" "${BUNDLE_DIR}/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleName string ${APP_NAME}" "${BUNDLE_DIR}/Contents/Info.plist"

cp -R "${RESOURCE_BUNDLE}" "${BUNDLE_DIR}/Contents/Resources/"

printf 'APPL????' > "${BUNDLE_DIR}/Contents/PkgInfo"

codesign --force --deep --sign - "${BUNDLE_DIR}"

echo "Packaged: ${BUNDLE_DIR}"
plutil -p "${BUNDLE_DIR}/Contents/Info.plist" | grep -E 'CFBundleExecutable|CFBundleName'
