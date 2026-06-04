#!/usr/bin/env bash
# Resolve, patch dependencies, and build a universal macOS 12 release binary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

if [[ "${SKIP_RESOLVE:-}" != "1" ]]; then
  swift package resolve
  ./Scripts/patch-dependencies-macos12.sh
fi

# Avoid stale Xcode-integrated build state from multi-arch swift build.
rm -rf "${ROOT}/.build/apple"

# shellcheck source=resolve-toolchain.sh
source "${ROOT}/Scripts/resolve-toolchain.sh"
TOOLCHAIN="$(resolve_toolchain)"
COMPAT_LIB="${TOOLCHAIN}/usr/lib/swift/macosx"
SWIFT_LINK_FLAGS=(
  -Xlinker -L -Xlinker "${COMPAT_LIB}"
  -Xlinker -lswiftCompatibility56
  -Xlinker -lswiftCompatibilityConcurrency
  -Xlinker -lswiftCompatibilityPacks
  -Xlinker -lswiftCompatibilityDynamicReplacements
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks
)

ARM_BIN="${ROOT}/.build/arm64-apple-macosx/release/AthlonAgent"
X86_BIN="${ROOT}/.build/x86_64-apple-macosx/release/AthlonAgent"
UNIVERSAL_DIR="${ROOT}/.build/universal/release"
RESOURCE_BUNDLE="${ROOT}/.build/arm64-apple-macosx/release/AthlonAgent_AthlonAgent.bundle"

echo "Building arm64 release for macOS 12..."
swift build -c release --product AthlonAgent --triple arm64-apple-macosx12.0 "${SWIFT_LINK_FLAGS[@]}"

echo "Building x86_64 release for macOS 12..."
swift build -c release --product AthlonAgent --triple x86_64-apple-macosx12.0 "${SWIFT_LINK_FLAGS[@]}"

if [[ ! -f "${ARM_BIN}" || ! -f "${X86_BIN}" ]]; then
  echo "error: missing per-architecture release binaries" >&2
  echo "  arm64:  ${ARM_BIN}" >&2
  echo "  x86_64: ${X86_BIN}" >&2
  exit 1
fi

mkdir -p "${UNIVERSAL_DIR}"
lipo -create -output "${UNIVERSAL_DIR}/AthlonAgent" "${ARM_BIN}" "${X86_BIN}"

if [[ -d "${RESOURCE_BUNDLE}" ]]; then
  rm -rf "${UNIVERSAL_DIR}/AthlonAgent_AthlonAgent.bundle"
  cp -R "${RESOURCE_BUNDLE}" "${UNIVERSAL_DIR}/"
else
  echo "error: missing ${RESOURCE_BUNDLE}" >&2
  exit 1
fi

ARCHS="$(lipo -info "${UNIVERSAL_DIR}/AthlonAgent")"
echo "${ARCHS}"
case "${ARCHS}" in
  *x86_64*arm64*|*arm64*x86_64*) ;;
  *)
    echo "error: expected universal binary with x86_64 and arm64" >&2
    exit 1
    ;;
esac

echo "Universal release ready at ${UNIVERSAL_DIR}"
