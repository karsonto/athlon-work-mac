#!/usr/bin/env bash
# Extract Swift dylibs from the host dyld shared cache (macOS 11+).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-${SWIFT_RUNTIME_EXTRACT_DIR:-${ROOT}/.build/swift-runtime-extract}}"
EXTRACTOR="${DYLD_SHARED_CACHE_EXTRACTOR:-dyld-shared-cache-extractor}"
DSC_BUNDLE="${DSC_EXTRACTOR_BUNDLE:-/usr/lib/dsc_extractor.bundle}"

DYLD_CACHE_ROOT="/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld"
ARM_CACHE="${DYLD_CACHE_ROOT}/dyld_shared_cache_arm64e"
X86_CACHE="${DYLD_CACHE_ROOT}/dyld_shared_cache_x86_64"

resolve_cache_paths() {
  if [[ -f "${ARM_CACHE}" && -f "${X86_CACHE}" ]]; then
    return 0
  fi
  if [[ -f /System/Library/dyld/dyld_shared_cache_arm64e ]]; then
    ARM_CACHE="/System/Library/dyld/dyld_shared_cache_arm64e"
    X86_CACHE="/System/Library/dyld/dyld_shared_cache_x86_64"
    return 0
  fi
  echo "error: unable to locate dyld_shared_cache files" >&2
  return 1
}

extract_host_swift_runtime() {
  local arm_out="${OUTPUT_DIR}/arm64e"
  local x86_out="${OUTPUT_DIR}/x86_64"
  local core="${x86_out}/usr/lib/swift/libswiftCore.dylib"

  if [[ -f "${core}" ]]; then
    echo "Swift runtime extract already present at ${OUTPUT_DIR}"
    return 0
  fi

  if ! command -v "${EXTRACTOR}" >/dev/null 2>&1; then
    echo "error: ${EXTRACTOR} not found (install: brew install keith/formulae/dyld-shared-cache-extractor)" >&2
    return 1
  fi

  resolve_cache_paths

  mkdir -p "${OUTPUT_DIR}"
  echo "Extracting Swift runtime (arm64e) from dyld shared cache..."
  "${EXTRACTOR}" "${ARM_CACHE}" "${arm_out}" "${DSC_BUNDLE}"
  echo "Extracting Swift runtime (x86_64) from dyld shared cache..."
  "${EXTRACTOR}" "${X86_CACHE}" "${x86_out}" "${DSC_BUNDLE}"

  if [[ ! -f "${core}" ]]; then
    echo "error: extraction failed; missing ${core}" >&2
    return 1
  fi

  echo "Swift runtime extracted to ${OUTPUT_DIR}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  extract_host_swift_runtime
fi
