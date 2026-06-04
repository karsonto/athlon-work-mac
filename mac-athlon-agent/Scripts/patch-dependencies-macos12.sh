#!/usr/bin/env bash
# Lower declared platform minimums and backport MCP SDK APIs for macOS 12 builds.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKOUTS="${ROOT}/.build/checkouts"
MCP_SOURCES="${CHECKOUTS}/swift-sdk/Sources/MCP"

patch_platform() {
  local file="$1"
  [[ -f "${file}" ]] || return 0
  sed -i '' \
    -e 's/\.macOS(.v14)/.macOS("12.0")/g' \
    -e 's/\.macOS("14.0")/.macOS("12.0")/g' \
    -e 's/\.macOS("13.0")/.macOS("12.0")/g' \
    -e 's/\.macOS(.v13)/.macOS("12.0")/g' \
    "${file}"
}

patch_task_sleep() {
  local file="$1"
  [[ -f "${file}" ]] || return 0
  perl -0pi -e '
    s/Task\.sleep\(for: \.milliseconds\(([^)]+)\)\)/Task.sleep(nanoseconds: UInt64(\1) * 1_000_000)/g;
    s/Task\.sleep\(for: \.microseconds\(([^)]+)\)\)/Task.sleep(nanoseconds: UInt64(\1) * 1_000)/g;
    s/Task\.sleep\(for: \.seconds\(([^)]+)\)\)/Task.sleep(nanoseconds: UInt64((\1) * 1_000_000_000))/g;
  ' "${file}"
}

if [[ ! -d "${CHECKOUTS}" ]]; then
  if [[ "${CI:-}" == "true" || "${STRICT:-}" == "1" ]]; then
    echo "error: ${CHECKOUTS} not found — run 'swift package resolve' first" >&2
    exit 1
  fi
  echo "note: ${CHECKOUTS} not found yet — run 'swift package resolve' first" >&2
  exit 0
fi

while IFS= read -r -d '' pkg; do
  patch_platform "${pkg}"
done < <(find "${CHECKOUTS}" -name Package.swift -print0)

if [[ -d "${CHECKOUTS}/swift-sdk" ]]; then
  chmod -R u+w "${CHECKOUTS}/swift-sdk" 2>/dev/null || true
fi

if [[ -d "${MCP_SOURCES}" ]]; then
  while IFS= read -r -d '' src; do
    patch_task_sleep "${src}"
  done < <(find "${MCP_SOURCES}" -name '*.swift' -print0)

  cp "${ROOT}/Scripts/patches/mcp-Data+Extensions.macos12.swift" \
    "${MCP_SOURCES}/Extensions/Data+Extensions.swift"
fi

echo "Patched SwiftPM checkouts for macOS 12 deployment target."
