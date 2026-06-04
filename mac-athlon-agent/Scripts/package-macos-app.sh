#!/usr/bin/env bash
# Assemble Athlon Agent.app from `swift build -c release` output.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-Athlon Agent}"
BUNDLE_DIR="${BUNDLE_DIR:-$ROOT/dist/${APP_NAME}.app}"
EXEC_NAME="AthlonAgent"

resolve_build_dir() {
  if [[ -n "${BUILD_DIR:-}" ]]; then
    printf '%s' "${BUILD_DIR}"
    return
  fi
  local universal="${ROOT}/.build/universal/release"
  local apple="${ROOT}/.build/apple/Products/Release"
  local legacy="${ROOT}/.build/release"
  if [[ -f "${universal}/${EXEC_NAME}" ]]; then
    printf '%s' "${universal}"
  elif [[ -f "${apple}/${EXEC_NAME}" ]]; then
    printf '%s' "${apple}"
  else
    printf '%s' "${legacy}"
  fi
}

embed_swift_stdlib() {
  local app="$1"
  chmod +x "${ROOT}/Scripts/embed-swift-runtime.sh"
  "${ROOT}/Scripts/embed-swift-runtime.sh" "${app}"
}

BUILD_DIR="$(resolve_build_dir)"
RESOURCE_BUNDLE="${BUILD_DIR}/${EXEC_NAME}_${EXEC_NAME}.bundle"

if [[ ! -f "${BUILD_DIR}/${EXEC_NAME}" ]]; then
  echo "error: missing ${BUILD_DIR}/${EXEC_NAME}" >&2
  echo "hint: run Scripts/build-release-macos12.sh for Intel + Apple Silicon builds" >&2
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

embed_swift_stdlib "${BUNDLE_DIR}"
codesign --force --deep --sign - "${BUNDLE_DIR}"

echo "Packaged: ${BUNDLE_DIR}"
echo "Binary: $(lipo -info "${BUNDLE_DIR}/Contents/MacOS/${EXEC_NAME}")"
plutil -p "${BUNDLE_DIR}/Contents/Info.plist" | grep -E 'CFBundleExecutable|CFBundleName|LSMinimumSystemVersion'
