#!/usr/bin/env bash
# Copy Swift runtime dylibs into an app bundle for deployment on older macOS versions.
set -euo pipefail

collect_swift_lib_names() {
  local executable="$1"
  {
    otool -L "${executable}" 2>/dev/null || true
    for arch in x86_64 arm64; do
      otool -arch "${arch}" -L "${executable}" 2>/dev/null || true
    done
  } | awk '/\/usr\/lib\/swift\// {print $1}' | while IFS= read -r lib; do
    [[ -n "${lib}" ]] || continue
    basename "${lib}"
  done | sort -u
}

embed_swift_runtime() {
  local app_bundle="$1"
  local executable="${app_bundle}/Contents/MacOS/AthlonAgent"
  local frameworks="${app_bundle}/Contents/Frameworks"

  if [[ ! -f "${executable}" ]]; then
    echo "error: missing executable ${executable}" >&2
    return 1
  fi

  local toolchain
  toolchain="$(xcrun --toolchain default --show-toolchain-path 2>/dev/null || true)"
  if [[ -z "${toolchain}" ]]; then
    toolchain="$(dirname "$(dirname "$(xcrun --find swift)")")"
  fi

  local swift_lib_dir="${toolchain}/usr/lib/swift-5.0/macosx"
  local swift_compat_dir="${toolchain}/usr/lib/swift-6.2/macosx"

  mkdir -p "${frameworks}"

  install_name_tool -add_rpath "@executable_path/../Frameworks" "${executable}" 2>/dev/null || true

  local base
  while IFS= read -r base; do
    [[ -n "${base}" ]] || continue
    if [[ -f "${swift_lib_dir}/${base}" ]]; then
      if [[ ! -f "${frameworks}/${base}" ]]; then
        cp "${swift_lib_dir}/${base}" "${frameworks}/${base}"
        install_name_tool -id "@rpath/${base}" "${frameworks}/${base}"
      fi
      install_name_tool -change "/usr/lib/swift/${base}" "@rpath/${base}" "${executable}" 2>/dev/null || true
    elif [[ -f "${swift_compat_dir}/${base}" ]]; then
      if [[ ! -f "${frameworks}/${base}" ]]; then
        cp "${swift_compat_dir}/${base}" "${frameworks}/${base}"
        install_name_tool -id "@rpath/${base}" "${frameworks}/${base}"
      fi
      install_name_tool -change "/usr/lib/swift/${base}" "@rpath/${base}" "${executable}" 2>/dev/null || true
    fi
  done < <(collect_swift_lib_names "${executable}")

  shopt -s nullglob
  local dylib lib
  for dylib in "${frameworks}"/*.dylib; do
    install_name_tool -id "@rpath/$(basename "${dylib}")" "${dylib}" 2>/dev/null || true
    while IFS= read -r lib; do
      [[ -n "${lib}" ]] || continue
      base="$(basename "${lib}")"
      if [[ -f "${frameworks}/${base}" ]]; then
        install_name_tool -change "${lib}" "@rpath/${base}" "${dylib}" 2>/dev/null || true
      fi
    done < <(otool -L "${dylib}" 2>/dev/null | awk '/\/usr\/lib\/swift\// {print $1}')
  done
  shopt -u nullglob

  if [[ -f "${swift_compat_dir}/libswiftCompatibilitySpan.dylib" \
        && ! -f "${frameworks}/libswiftCompatibilitySpan.dylib" ]]; then
    cp "${swift_compat_dir}/libswiftCompatibilitySpan.dylib" "${frameworks}/"
    install_name_tool -id "@rpath/libswiftCompatibilitySpan.dylib" \
      "${frameworks}/libswiftCompatibilitySpan.dylib"
  fi

  local count
  count="$(find "${frameworks}" -name '*.dylib' | wc -l | tr -d ' ')"
  if [[ "${count}" -eq 0 ]]; then
    echo "error: no Swift runtime libraries embedded into ${frameworks}" >&2
    return 1
  fi

  echo "Embedded ${count} Swift runtime libraries into ${frameworks}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  embed_swift_runtime "$1"
fi
