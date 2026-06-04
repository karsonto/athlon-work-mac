#!/usr/bin/env bash
# Resolve, patch dependencies, and build a universal macOS 12 release binary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

swift package resolve
./Scripts/patch-dependencies-macos12.sh

echo "Building universal binary (x86_64 + arm64) for macOS 12..."
swift build -c release --product AthlonAgent --arch x86_64 --arch arm64

EXEC="${ROOT}/.build/apple/Products/Release/AthlonAgent"
if [[ ! -f "${EXEC}" ]]; then
  echo "error: missing universal binary at ${EXEC}" >&2
  exit 1
fi

ARCHS="$(lipo -info "${EXEC}")"
echo "${ARCHS}"
case "${ARCHS}" in
  *x86_64*arm64*|*arm64*x86_64*) ;;
  *)
    echo "error: expected universal binary with x86_64 and arm64" >&2
    exit 1
    ;;
esac
