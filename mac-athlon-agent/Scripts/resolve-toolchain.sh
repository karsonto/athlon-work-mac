#!/usr/bin/env bash
# Portable Xcode toolchain root resolution (works without xcrun --show-toolchain-path).
resolve_toolchain() {
  local toolchain="" swift_bin="" developer_dir=""

  swift_bin="$(xcrun --find swift 2>/dev/null || true)"
  if [[ -n "${swift_bin}" ]]; then
    toolchain="${swift_bin%/usr/bin/swift}"
    if [[ -d "${toolchain}" ]]; then
      printf '%s' "${toolchain}"
      return 0
    fi
  fi

  developer_dir="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
  if [[ -n "${developer_dir}" ]]; then
    toolchain="${developer_dir}/Toolchains/XcodeDefault.xctoolchain"
    if [[ -d "${toolchain}" ]]; then
      printf '%s' "${toolchain}"
      return 0
    fi
  fi

  echo "error: unable to locate Xcode Swift toolchain" >&2
  return 1
}
