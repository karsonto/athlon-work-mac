#!/usr/bin/env bash
# Copy Swift runtime dylibs into an app bundle for deployment on older macOS versions.
set -euo pipefail

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

  local -a libs_to_copy=()
  while IFS= read -r lib; do
    [[ -n "${lib}" ]] || continue
    local base
    base="$(basename "${lib}")"
    if [[ -f "${swift_lib_dir}/${base}" ]]; then
      libs_to_copy+=("${base}")
    elif [[ -f "${swift_compat_dir}/${base}" ]]; then
      cp "${swift_compat_dir}/${base}" "${frameworks}/${base}"
      install_name_tool -change "${lib}" "@rpath/${base}" "${executable}" 2>/dev/null || true
    fi
  done < <(otool -L "${executable}" | awk '/\/usr\/lib\/swift\// {print $1}')

  local base
  for base in "${libs_to_copy[@]}"; do
    if [[ ! -f "${frameworks}/${base}" ]]; then
      cp "${swift_lib_dir}/${base}" "${frameworks}/${base}"
      install_name_tool -id "@rpath/${base}" "${frameworks}/${base}"
    fi
    install_name_tool -change "/usr/lib/swift/${base}" "@rpath/${base}" "${executable}" 2>/dev/null || true
  done

  local dylib lib base
  for dylib in "${frameworks}"/*.dylib; do
    [[ -f "${dylib}" ]] || continue
    install_name_tool -id "@rpath/$(basename "${dylib}")" "${dylib}" 2>/dev/null || true
    while IFS= read -r lib; do
      [[ -n "${lib}" ]] || continue
      base="$(basename "${lib}")"
      if [[ -f "${frameworks}/${base}" ]]; then
        install_name_tool -change "${lib}" "@rpath/${base}" "${dylib}" 2>/dev/null || true
      fi
    done < <(otool -L "${dylib}" | awk '/\/usr\/lib\/swift\// {print $1}')
  done

  if [[ -f "${swift_compat_dir}/libswiftCompatibilitySpan.dylib" \
        && ! -f "${frameworks}/libswiftCompatibilitySpan.dylib" ]]; then
    cp "${swift_compat_dir}/libswiftCompatibilitySpan.dylib" "${frameworks}/"
    install_name_tool -id "@rpath/libswiftCompatibilitySpan.dylib" \
      "${frameworks}/libswiftCompatibilitySpan.dylib"
  fi

  local count
  count="$(find "${frameworks}" -name '*.dylib' | wc -l | tr -d ' ')"
  echo "Embedded ${count} Swift runtime libraries into ${frameworks}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  embed_swift_runtime "$1"
fi
