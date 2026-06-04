#!/usr/bin/env bash
# Copy Swift runtime dylibs into an app bundle for deployment on older macOS versions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=resolve-toolchain.sh
source "${SCRIPT_DIR}/resolve-toolchain.sh"

HOST_SWIFT_DIR="/usr/lib/swift"
EXTRACT_DIR="${SWIFT_RUNTIME_EXTRACT_DIR:-${ROOT}/.build/swift-runtime-extract}"
EXTRACT_X86="${EXTRACT_DIR}/x86_64/usr/lib/swift"
EXTRACT_ARM="${EXTRACT_DIR}/arm64e/usr/lib/swift"
# macOS 12 dyld resolves @rpath unreliably when extra rpaths are present; use explicit paths.
EXEC_FRAMEWORKS_PATH='@executable_path/../Frameworks'
DYLIB_FRAMEWORKS_PATH='@loader_path'
KEEP_RPATH="${EXEC_FRAMEWORKS_PATH}"

collect_swift_lib_names() {
  local binary="$1"
  local tmp
  tmp="$(mktemp)"

  otool -L "${binary}" 2>/dev/null > "${tmp}" || true
  for arch in x86_64 arm64 arm64e; do
    otool -arch "${arch}" -L "${binary}" 2>/dev/null >> "${tmp}" || true
  done

  grep -E '/usr/lib/swift/|@rpath/libswift|@executable_path/../Frameworks/libswift' "${tmp}" \
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

list_rpaths() {
  local binary="$1"
  otool -l "${binary}" 2>/dev/null \
    | awk '/cmd LC_RPATH/{show=1; next} show && $1=="path"{gsub(/\(offset.*/,"",$2); print $2; show=0}'
}

clean_executable_rpaths() {
  local executable="$1"
  local rpath
  local pass=0

  while (( pass < 32 )); do
    pass=$((pass + 1))
    local removed=0
    while IFS= read -r rpath; do
      [[ -n "${rpath}" ]] || continue
      [[ "${rpath}" == "${KEEP_RPATH}" ]] && continue
      if install_name_tool -delete_rpath "${rpath}" "${executable}" 2>/dev/null; then
        removed=1
      fi
    done < <(list_rpaths "${executable}")
    (( removed )) || break
  done

  install_name_tool -add_rpath "${KEEP_RPATH}" "${executable}" 2>/dev/null || true
}

embedded_frameworks_path() {
  local base="$1"
  local for_dylib="${2:-0}"
  if [[ "${for_dylib}" -eq 1 ]]; then
    printf '%s/%s' "${DYLIB_FRAMEWORKS_PATH}" "${base}"
  else
    printf '%s/%s' "${EXEC_FRAMEWORKS_PATH}" "${base}"
  fi
}

rehome_swift_libs_to_frameworks() {
  local binary="$1"
  local frameworks="$2"
  local for_dylib="${3:-0}"
  local base dest from

  shopt -s nullglob
  for base in "${frameworks}"/*.dylib; do
    base="$(basename "${base}")"
    dest="$(embedded_frameworks_path "${base}" "${for_dylib}")"
    rehome_swift_reference "${binary}" "/usr/lib/swift/${base}" "${dest}"
    rehome_swift_reference "${binary}" "@rpath/${base}" "${dest}"
    rehome_swift_reference "${binary}" "${EXEC_FRAMEWORKS_PATH}/${base}" "${dest}"
  done
  shopt -u nullglob
}

resolve_swift_search_dirs() {
  local toolchain="$1"
  local dir

  if [[ -d "${EXTRACT_X86}" ]]; then
    printf '%s\n' "${EXTRACT_X86}"
  fi
  if [[ -d "${EXTRACT_ARM}" ]]; then
    printf '%s\n' "${EXTRACT_ARM}"
  fi
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
    [[ "${dir}" == *swift-5.0* ]] && continue
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

merge_swift_library_into_frameworks() {
  local base="$1"
  local frameworks="$2"
  local x86="${EXTRACT_X86}/${base}"
  local arm="${EXTRACT_ARM}/${base}"
  local dest="${frameworks}/${base}"

  if [[ -f "${x86}" && -f "${arm}" ]]; then
    lipo -create -output "${dest}" "${x86}" "${arm}"
    install_name_tool -id "$(embedded_frameworks_path "${base}" 1)" "${dest}" 2>/dev/null || true
    return 0
  fi
  if [[ -f "${x86}" ]]; then
    cp "${x86}" "${dest}"
    install_name_tool -id "$(embedded_frameworks_path "${base}" 1)" "${dest}" 2>/dev/null || true
    return 0
  fi
  if [[ -f "${arm}" ]]; then
    cp "${arm}" "${dest}"
    install_name_tool -id "$(embedded_frameworks_path "${base}" 1)" "${dest}" 2>/dev/null || true
    return 0
  fi
  return 1
}

copy_library_if_missing() {
  local source="$1"
  local frameworks="$2"
  local base
  base="$(basename "${source}")"

  if [[ -f "${frameworks}/${base}" ]]; then
    return 0
  fi

  if merge_swift_library_into_frameworks "${base}" "${frameworks}"; then
    return 0
  fi

  cp "${source}" "${frameworks}/${base}"
  install_name_tool -id "$(embedded_frameworks_path "${base}" 1)" "${frameworks}/${base}" 2>/dev/null || true
}

ensure_swift_runtime_extract() {
  if [[ -f "${EXTRACT_X86}/libswiftCore.dylib" ]]; then
    return 0
  fi
  if [[ -f "${HOST_SWIFT_DIR}/libswiftCore.dylib" ]]; then
    return 0
  fi
  chmod +x "${SCRIPT_DIR}/extract-host-swift-runtime.sh"
  "${SCRIPT_DIR}/extract-host-swift-runtime.sh" "${EXTRACT_DIR}"
}

dylib_contains_arch() {
  local dylib="$1"
  local arch="$2"
  lipo -info "${dylib}" 2>/dev/null \
    | sed -n 's/.*are: //p' \
    | tr ' ' '\n' \
    | grep -qx "${arch}"
}

patch_embedded_dylib_deployment_target() {
  local dylib="$1"
  local arch work="${dylib}.vtool-work"

  cp "${dylib}" "${work}"
  for arch in x86_64 arm64 arm64e; do
    dylib_contains_arch "${dylib}" "${arch}" || continue
    vtool -set-build-version macos 12.0 12.0 -replace -arch "${arch}" -output "${dylib}" "${work}"
    cp "${dylib}" "${work}"
  done
  rm -f "${work}"
}

patch_embedded_dylibs_deployment_target() {
  local frameworks="$1"
  local dylib

  shopt -s nullglob
  for dylib in "${frameworks}"/*.dylib; do
    patch_embedded_dylib_deployment_target "${dylib}"
  done
  shopt -u nullglob
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

  if ! vtool -show-build -arch x86_64 "${core}" 2>/dev/null | grep -q 'minos 12.0'; then
    echo "error: embedded libswiftCore.dylib x86_64 slice is not tagged for macOS 12" >&2
    vtool -show-build -arch x86_64 "${core}" 2>/dev/null | grep minos >&2 || true
    return 1
  fi

  local symbol_count
  symbol_count="$(nm -arch x86_64 -gU "${core}" 2>/dev/null | grep -c '2IDs12IdentifiablePTl' || true)"
  if [[ "${symbol_count}" -eq 0 ]]; then
    echo "error: embedded libswiftCore.dylib is too old for this Swift 6 build" >&2
    echo "hint: extract from dyld shared cache; do not use swift-5.0 toolchain copies" >&2
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

  ensure_swift_runtime_extract

  toolchain="$(resolve_toolchain)"
  mkdir -p "${frameworks}"

  install_name_tool -add_rpath "${KEEP_RPATH}" "${executable}" 2>/dev/null || true

  while IFS= read -r base; do
    [[ -n "${base}" ]] || continue
    source="$(find_swift_library_source "${base}" "${toolchain}" || true)"
    [[ -n "${source}" ]] || continue
    copy_library_if_missing "${source}" "${frameworks}"
  done < <(collect_swift_lib_names "${executable}")

  for required in libswiftCore.dylib libswift_Concurrency.dylib libswiftCompatibilitySpan.dylib; do
    if [[ ! -f "${frameworks}/${required}" ]]; then
      source="$(find_swift_library_source "${required}" "${toolchain}" || true)"
      if [[ -n "${source}" ]]; then
        copy_library_if_missing "${source}" "${frameworks}"
      fi
    fi
  done

  rehome_swift_libs_to_frameworks "${executable}" "${frameworks}" 0

  shopt -s nullglob
  for dylib in "${frameworks}"/*.dylib; do
    base="$(basename "${dylib}")"
    install_name_tool -id "$(embedded_frameworks_path "${base}" 1)" "${dylib}" 2>/dev/null || true
    rehome_swift_libs_to_frameworks "${dylib}" "${frameworks}" 1
  done
  shopt -u nullglob

  rm -f "${frameworks}"/*.original

  clean_executable_rpaths "${executable}"
  rehome_swift_libs_to_frameworks "${executable}" "${frameworks}" 0

  for required in libswiftCore.dylib libswift_Concurrency.dylib; do
    if [[ ! -f "${frameworks}/${required}" ]]; then
      echo "error: missing required embedded Swift runtime ${required}" >&2
      return 1
    fi
  done

  if otool -arch x86_64 -L "${executable}" 2>/dev/null \
    | grep -E '/usr/lib/swift/|@rpath/libswift' \
    | grep -v '/usr/lib/swift/libswiftNetwork.dylib' \
    | grep -q .; then
    echo "error: executable x86_64 slice still uses /usr/lib/swift or @rpath for embedded Swift libraries" >&2
    otool -arch x86_64 -L "${executable}" 2>/dev/null \
      | grep -E '/usr/lib/swift/|@rpath/libswift' \
      | grep -v '/usr/lib/swift/libswiftNetwork.dylib' >&2 || true
    return 1
  fi

  if ! otool -arch x86_64 -L "${executable}" 2>/dev/null | grep -q "${EXEC_FRAMEWORKS_PATH}/libswiftCore.dylib"; then
    echo "error: executable x86_64 slice must link ${EXEC_FRAMEWORKS_PATH}/libswiftCore.dylib" >&2
    return 1
  fi

  if list_rpaths "${executable}" | grep -vx "${KEEP_RPATH}" | grep -q .; then
    echo "error: unexpected LC_RPATH entries remain on executable" >&2
    list_rpaths "${executable}" >&2
    return 1
  fi

  patch_embedded_dylibs_deployment_target "${frameworks}"
  verify_embedded_swift_core "${frameworks}"

  local count
  count="$(find "${frameworks}" -name '*.dylib' | wc -l | tr -d ' ')"
  echo "Embedded ${count} Swift runtime libraries into ${frameworks}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  embed_swift_runtime "$1"
fi
