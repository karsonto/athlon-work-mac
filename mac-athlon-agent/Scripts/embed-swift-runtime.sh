#!/usr/bin/env bash
# Copy Swift runtime dylibs into an app bundle for deployment on older macOS versions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=resolve-toolchain.sh
source "${SCRIPT_DIR}/resolve-toolchain.sh"

find_swift_library_source() {
  local base="$1"
  local toolchain="$2"
  local dir source

  shopt -s nullglob
  for dir in \
    "${toolchain}/usr/lib/swift-5.5/macosx" \
    "${toolchain}/usr/lib/swift-5.0/macosx" \
    "${toolchain}/usr/lib/swift/macosx" \
    "${toolchain}"/usr/lib/swift-*/macosx; do
    source="${dir}/${base}"
    if [[ -f "${source}" ]]; then
      shopt -u nullglob
      printf '%s' "${source}"
      return 0
    fi
  done
  shopt -u nullglob
  return 1
}

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

embed_swift_runtime() {
  local app_bundle="$1"
  local executable="${app_bundle}/Contents/MacOS/AthlonAgent"
  local frameworks="${app_bundle}/Contents/Frameworks"
  local toolchain base source dir

  if [[ ! -f "${executable}" ]]; then
    echo "error: missing executable ${executable}" >&2
    return 1
  fi

  toolchain="$(resolve_toolchain)"
  mkdir -p "${frameworks}"

  install_name_tool -add_rpath "@executable_path/../Frameworks" "${executable}" 2>/dev/null || true

  while IFS= read -r base; do
    [[ -n "${base}" ]] || continue
    source="$(find_swift_library_source "${base}" "${toolchain}" || true)"
    [[ -n "${source}" ]] || continue
    copy_library_if_missing "${source}" "${frameworks}"
  done < <(collect_swift_lib_names "${executable}")

  shopt -s nullglob
  for dir in \
    "${toolchain}/usr/lib/swift-5.0/macosx" \
    "${toolchain}/usr/lib/swift-5.5/macosx" \
    "${toolchain}"/usr/lib/swift-*/macosx; do
    [[ -d "${dir}" ]] || continue
    for source in "${dir}"/libswift*.dylib; do
      copy_library_if_missing "${source}" "${frameworks}"
    done
  done
  shopt -u nullglob

  for required in libswiftCore.dylib libswift_Concurrency.dylib; do
    if [[ ! -f "${frameworks}/${required}" ]]; then
      source="$(find_swift_library_source "${required}" "${toolchain}" || true)"
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

  local count
  count="$(find "${frameworks}" -name '*.dylib' | wc -l | tr -d ' ')"
  echo "Embedded ${count} Swift runtime libraries into ${frameworks}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  embed_swift_runtime "$1"
fi
