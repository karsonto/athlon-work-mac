#!/usr/bin/env bash
# Copy Swift runtime dylibs into an app bundle for deployment on older macOS versions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=resolve-toolchain.sh
source "${SCRIPT_DIR}/resolve-toolchain.sh"

HOST_SWIFT_DIR="/usr/lib/swift"

collect_swift_lib_names() {
  local binary="$1"
  local tmp
  tmp="$(mktemp)"

  otool -L "${binary}" 2>/dev/null > "${tmp}" || true
  for arch in x86_64 arm64 arm64e; do
    otool -arch "${arch}" -L "${binary}" 2>/dev/null >> "${tmp}" || true
  done

  grep -E '/usr/lib/swift/|@rpath/libswift' "${tmp}" \
    | sed -E 's/^[[:space:]]+([^[:space:]]+).*/\1/' \
    | while IFS= read -r lib; do
        [[ -n "${lib}" ]] || continue
        basename "${lib}"
      done \
    | sort -u

  rm -f "${tmp}"
}

rehome_swift_reference() {
  local binary="$1"
  local from="$2"
  local to="$3"

  install_name_tool -change "${from}" "${to}" "${binary}" 2>/dev/null || true
  for arch in x86_64 arm64; do
    install_name_tool -arch "${arch}" -change "${from}" "${to}" "${binary}" 2>/dev/null || true
  done
}

resolve_swift_search_dirs() {
  local toolchain="$1"
  local dir

  if [[ -f "${HOST_SWIFT_DIR}/libswiftCore.dylib" ]]; then
    printf '%s\n' "${HOST_SWIFT_DIR}"
  fi

  shopt -s nullglob
  for dir in \
    "${toolchain}/usr/lib/swift-5.5/macosx" \
    "${toolchain}/usr/lib/swift-6.2/macosx" \
    "${toolchain}/usr/lib/swift/macosx" \
    "${toolchain}"/usr/lib/swift-*/macosx; do
    [[ -d "${dir}" ]] || continue
    printf '%s\n' "${dir}"
  done
  shopt -u nullglob
}

find_swift_library_source() {
  local base="$1"
  local toolchain="$2"
  local dir source

  while IFS= read -r dir; do
    [[ -n "${dir}" ]] || continue
    source="${dir}/${base}"
    if [[ -f "${source}" ]]; then
      printf '%s' "${source}"
      return 0
    fi
  done < <(resolve_swift_search_dirs "${toolchain}")

  return 1
}

copy_library_if_missing() {
  local source="$1"
  local frameworks="$2"
  local base
  base="$(basename "${source}")"

  if [[ ! -f "${frameworks}/${base}" ]]; then
    cp "${source}" "${frameworks}/${base}"
    install_name_tool -id "@rpath/${base}" "${frameworks}/${base}" 2>/dev/null || true
  fi
}

verify_embedded_swift_core() {
  local frameworks="$1"
  local core="${frameworks}/libswiftCore.dylib"

  if [[ ! -f "${core}" ]]; then
    echo "error: missing required embedded Swift runtime libswiftCore.dylib" >&2
    return 1
  fi

  if ! lipo -info "${core}" 2>/dev/null | grep -q 'x86_64'; then
    echo "error: embedded libswiftCore.dylib is missing x86_64 slice (Intel Macs will crash)" >&2
    return 1
  fi

  if ! nm -arch x86_64 -gU "${core}" 2>/dev/null | grep -q '_\$s2IDs12IdentifiablePTl'; then
    echo "error: embedded libswiftCore.dylib is too old for this Swift 6 build" >&2
    echo "hint: copy libswiftCore from ${HOST_SWIFT_DIR} on the CI/build host, not swift-5.0/macosx" >&2
    return 1
  fi
}

embed_swift_runtime() {
  local app_bundle="$1"
  local executable="${app_bundle}/Contents/MacOS/AthlonAgent"
  local frameworks="${app_bundle}/Contents/Frameworks"
  local toolchain base source

  if [[ ! -f "${executable}" ]]; then
    echo "error: missing executable ${executable}" >&2
    return 1
  fi

  if [[ ! -f "${HOST_SWIFT_DIR}/libswiftCore.dylib" ]]; then
    echo "error: host Swift runtime not found at ${HOST_SWIFT_DIR}/libswiftCore.dylib" >&2
    echo "hint: package on macOS 13+ with Xcode 16+ (CI uses macos-15); do not use swift-5.0 toolchain copies" >&2
    return 1
  fi

  toolchain="$(resolve_toolchain)"
  mkdir -p "${frameworks}"

  install_name_tool -add_rpath "@executable_path/../Frameworks" "${executable}" 2>/dev/null || true

  # Seed libswiftCore from the host OS Swift 6 runtime first. Toolchain swift-5.0
  # copies are Swift 5 back-deploy stubs and will crash on launch (missing symbols).
  copy_library_if_missing "${HOST_SWIFT_DIR}/libswiftCore.dylib" "${frameworks}"

  while IFS= read -r base; do
    [[ -n "${base}" ]] || continue
    if [[ "${base}" == "libswiftCore.dylib" ]]; then
      continue
    fi
    source="$(find_swift_library_source "${base}" "${toolchain}" || true)"
    if [[ -z "${source}" && -f "${HOST_SWIFT_DIR}/${base}" ]]; then
      source="${HOST_SWIFT_DIR}/${base}"
    fi
    [[ -n "${source}" ]] || continue
    copy_library_if_missing "${source}" "${frameworks}"
  done < <(collect_swift_lib_names "${executable}")

  for required in libswiftCore.dylib libswift_Concurrency.dylib; do
    if [[ ! -f "${frameworks}/${required}" ]]; then
      source="$(find_swift_library_source "${required}" "${toolchain}" || true)"
      if [[ -z "${source}" && -f "${HOST_SWIFT_DIR}/${required}" ]]; then
        source="${HOST_SWIFT_DIR}/${required}"
      fi
      if [[ -n "${source}" ]]; then
        copy_library_if_missing "${source}" "${frameworks}"
      fi
    fi
  done

  shopt -s nullglob
  for dylib in "${frameworks}"/*.dylib; do
    base="$(basename "${dylib}")"
    rehome_swift_reference "${executable}" "/usr/lib/swift/${base}" "@rpath/${base}"
  done

  for dylib in "${frameworks}"/*.dylib; do
    install_name_tool -id "@rpath/$(basename "${dylib}")" "${dylib}" 2>/dev/null || true
    while IFS= read -r lib; do
      [[ -n "${lib}" ]] || continue
      base="$(basename "${lib}")"
      if [[ -f "${frameworks}/${base}" ]]; then
        rehome_swift_reference "${dylib}" "${lib}" "@rpath/${base}"
      fi
    done < <(otool -L "${dylib}" 2>/dev/null | grep -E '/usr/lib/swift/|@rpath/libswift' \
      | sed -E 's/^[[:space:]]+([^[:space:]]+).*/\1/')
  done
  shopt -u nullglob

  rm -f "${frameworks}"/*.original

  for required in libswiftCore.dylib libswift_Concurrency.dylib; do
    if [[ ! -f "${frameworks}/${required}" ]]; then
      echo "error: missing required embedded Swift runtime ${required}" >&2
      return 1
    fi
  done

  if otool -arch x86_64 -L "${executable}" 2>/dev/null | grep -q '/usr/lib/swift/libswift_Concurrency.dylib'; then
    echo "error: executable x86_64 slice still links /usr/lib/swift/libswift_Concurrency.dylib" >&2
    return 1
  fi

  verify_embedded_swift_core "${frameworks}"

  local count
  count="$(find "${frameworks}" -name '*.dylib' | wc -l | tr -d ' ')"
  echo "Embedded ${count} Swift runtime libraries into ${frameworks}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  embed_swift_runtime "$1"
fi
