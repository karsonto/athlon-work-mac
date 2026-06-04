#!/usr/bin/env bash
# Copy Swift runtime dylibs into an app bundle for deployment on older macOS versions.
set -euo pipefail

resolve_toolchain() {
  local toolchain="" swift_bin=""

  for candidate in \
    "$(xcrun --show-toolchain-path 2>/dev/null || true)" \
    "$(xcrun --toolchain default --show-toolchain-path 2>/dev/null || true)" \
    "$(xcrun --toolchain swift --show-toolchain-path 2>/dev/null || true)"; do
    if [[ -n "${candidate}" && -d "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done

  swift_bin="$(xcrun --find swift 2>/dev/null || true)"
  if [[ -n "${swift_bin}" ]]; then
    toolchain="${swift_bin%/usr/bin/swift}"
    if [[ -d "${toolchain}" ]]; then
      printf '%s' "${toolchain}"
      return 0
    fi
  fi

  echo "error: unable to locate Xcode Swift toolchain" >&2
  return 1
}

resolve_swift_runtime_dir() {
  local toolchain="$1"
  local dir

  shopt -s nullglob
  for dir in \
    "${toolchain}/usr/lib/swift-5.0/macosx" \
    "${toolchain}/usr/lib/swift/macosx" \
    "${toolchain}"/usr/lib/swift-*/macosx; do
    if [[ -f "${dir}/libswiftCore.dylib" ]]; then
      shopt -u nullglob
      printf '%s' "${dir}"
      return 0
    fi
  done
  shopt -u nullglob
  return 1
}

resolve_swift_compat_dir() {
  local toolchain="$1"
  local dir

  shopt -s nullglob
  for dir in "${toolchain}"/usr/lib/swift-*/macosx; do
    if [[ -f "${dir}/libswiftCompatibilitySpan.dylib" ]]; then
      shopt -u nullglob
      printf '%s' "${dir}"
      return 0
    fi
  done
  shopt -u nullglob
  return 1
}

find_swift_library() {
  local base="$1"
  local runtime_dir="$2"
  local compat_dir="$3"

  if [[ -n "${runtime_dir}" && -f "${runtime_dir}/${base}" ]]; then
    printf '%s' "${runtime_dir}/${base}"
    return 0
  fi
  if [[ -n "${compat_dir}" && -f "${compat_dir}/${base}" ]]; then
    printf '%s' "${compat_dir}/${base}"
    return 0
  fi
  return 1
}

collect_swift_lib_names() {
  local executable="$1"
  local tmp
  tmp="$(mktemp)"

  otool -L "${executable}" 2>/dev/null > "${tmp}" || true
  for arch in x86_64 arm64; do
    otool -arch "${arch}" -L "${executable}" 2>/dev/null >> "${tmp}" || true
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

copy_swift_library() {
  local source="$1"
  local frameworks="$2"
  local base="$3"
  local executable="$4"

  if [[ ! -f "${source}" ]]; then
    return 1
  fi

  if [[ ! -f "${frameworks}/${base}" ]]; then
    cp "${source}" "${frameworks}/${base}"
    install_name_tool -id "@rpath/${base}" "${frameworks}/${base}" 2>/dev/null || true
  fi

  install_name_tool -change "/usr/lib/swift/${base}" "@rpath/${base}" "${executable}" 2>/dev/null || true
  install_name_tool -change "@rpath/${base}" "@rpath/${base}" "${executable}" 2>/dev/null || true
  return 0
}

embed_swift_runtime() {
  local app_bundle="$1"
  local executable="${app_bundle}/Contents/MacOS/AthlonAgent"
  local frameworks="${app_bundle}/Contents/Frameworks"

  if [[ ! -f "${executable}" ]]; then
    echo "error: missing executable ${executable}" >&2
    return 1
  fi

  local toolchain runtime_dir compat_dir
  toolchain="$(resolve_toolchain)"
  runtime_dir="$(resolve_swift_runtime_dir "${toolchain}" || true)"
  compat_dir="$(resolve_swift_compat_dir "${toolchain}" || true)"

  mkdir -p "${frameworks}"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "${executable}" 2>/dev/null || true

  if xcrun --find swift-stdlib-tool >/dev/null 2>&1; then
    xcrun swift-stdlib-tool \
      --copy \
      --sign - \
      --scan-executable "${executable}" \
      --scan-folder "${frameworks}" \
      --scan-folder "${app_bundle}/Contents/PlugIns" \
      --scan-folder "${app_bundle}/Contents/Library/SystemExtensions" \
      --scan-folder "${app_bundle}/Contents/Extensions" \
      --platform macosx \
      --destination "${frameworks}" >/dev/null 2>&1 || true
  fi

  local base source copied_any=0
  while IFS= read -r base; do
    [[ -n "${base}" ]] || continue
    source="$(find_swift_library "${base}" "${runtime_dir}" "${compat_dir}" || true)"
    [[ -n "${source}" ]] || continue
    if copy_swift_library "${source}" "${frameworks}" "${base}" "${executable}"; then
      copied_any=1
    fi
  done < <(collect_swift_lib_names "${executable}")

  if [[ "${copied_any}" -eq 0 ]]; then
    shopt -s nullglob
    for dir in \
      "${runtime_dir}" \
      "${toolchain}/usr/lib/swift-5.0/macosx" \
      "${toolchain}"/usr/lib/swift-*/macosx; do
      [[ -n "${dir}" && -d "${dir}" ]] || continue
      for source in "${dir}"/libswift*.dylib; do
        base="$(basename "${source}")"
        if copy_swift_library "${source}" "${frameworks}" "${base}" "${executable}"; then
          copied_any=1
        fi
      done
    done
    shopt -u nullglob
  fi

  if [[ -n "${compat_dir}" \
        && -f "${compat_dir}/libswiftCompatibilitySpan.dylib" \
        && ! -f "${frameworks}/libswiftCompatibilitySpan.dylib" ]]; then
    cp "${compat_dir}/libswiftCompatibilitySpan.dylib" "${frameworks}/"
    install_name_tool -id "@rpath/libswiftCompatibilitySpan.dylib" \
      "${frameworks}/libswiftCompatibilitySpan.dylib" 2>/dev/null || true
  fi

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
    done < <(otool -L "${dylib}" 2>/dev/null | grep -E '/usr/lib/swift/|@rpath/libswift' \
      | sed -E 's/^[[:space:]]+([^[:space:]]+).*/\1/')
  done
  shopt -u nullglob

  local count
  count="$(find "${frameworks}" -name '*.dylib' | wc -l | tr -d ' ')"
  if [[ "${count}" -eq 0 ]]; then
    echo "error: no Swift runtime libraries embedded into ${frameworks}" >&2
    echo "error: toolchain=${toolchain}" >&2
    echo "error: runtime_dir=${runtime_dir:-<missing>}" >&2
    echo "error: compat_dir=${compat_dir:-<missing>}" >&2
    echo "error: linked swift libs:" >&2
    otool -L "${executable}" 2>/dev/null | grep -i swift >&2 || true
    return 1
  fi

  echo "Embedded ${count} Swift runtime libraries into ${frameworks}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  embed_swift_runtime "$1"
fi
