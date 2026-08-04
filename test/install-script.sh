#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temp_base=$(cd "${TMPDIR:-/tmp}" && pwd -P)
e2e_root=$(mktemp -d "$temp_base/opencode-agy-search-installer.XXXXXX")
touch "$e2e_root/.opencode-agy-search-installer-owned"

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  case "$e2e_root" in
    "$temp_base"/opencode-agy-search-installer.*)
      if [[ -f "$e2e_root/.opencode-agy-search-installer-owned" ]]; then
        find "$e2e_root" -depth -delete
      else
        printf 'cleanup marker missing; refusing deletion\n' >&2
        status=1
      fi
      ;;
    *)
      printf 'cleanup prefix mismatch; refusing deletion\n' >&2
      status=1
      ;;
  esac
  exit "$status"
}
trap cleanup EXIT INT TERM

mkdir -p "$e2e_root/assets" "$e2e_root/home"
cd "$repo_root"
npm pack --json --pack-destination "$e2e_root/assets" >/dev/null
packed=$(find "$e2e_root/assets" -maxdepth 1 -type f -name '*.tgz')
archive="$e2e_root/assets/opencode-agy-search-0.3.0.tgz"
mv "$packed" "$archive"
archive_basename=$(basename "$archive")
if command -v sha256sum >/dev/null; then
  (cd "$e2e_root/assets" && sha256sum "$(basename "$archive")") \
    >"$archive.sha256"
else
  (cd "$e2e_root/assets" && shasum -a 256 "$(basename "$archive")") \
    >"$archive.sha256"
fi

mkdir -p "$e2e_root/old-assets" "$e2e_root/old-extract"
tar -xzf "$archive" -C "$e2e_root/old-extract"
perl -0pi -e 's/"version": "0\.3\.0"/"version": "0.2.9"/' \
  "$e2e_root/old-extract/package/package.json"
tar -czf "$e2e_root/old-assets/opencode-agy-search-0.2.9.tgz" \
  -C "$e2e_root/old-extract" package
if command -v sha256sum >/dev/null; then
  (cd "$e2e_root/old-assets" && sha256sum opencode-agy-search-0.2.9.tgz) \
    >"$e2e_root/old-assets/opencode-agy-search-0.2.9.tgz.sha256"
else
  (cd "$e2e_root/old-assets" && shasum -a 256 opencode-agy-search-0.2.9.tgz) \
    >"$e2e_root/old-assets/opencode-agy-search-0.2.9.tgz.sha256"
fi
sed 's/PACKAGE_VERSION="0.3.0"/PACKAGE_VERSION="0.2.9"/' \
  "$repo_root/scripts/install.sh" >"$e2e_root/install-0.2.9.sh"

install_fixture_with() {
  installer="$1"
  download_url="$2"
  target_config="$3"
  target_data="$4"
  HOME="$e2e_root/home" \
  XDG_CONFIG_HOME="$target_config" \
  XDG_DATA_HOME="$target_data" \
  OPENCODE_AGY_SEARCH_DOWNLOAD_URL="$download_url" \
    sh "$installer"
}

install_fixture() {
  target_config="$1"
  target_data="$2"
  install_fixture_with "$repo_root/scripts/install.sh" \
    "file://$e2e_root/assets" "$target_config" "$target_data"
}

install_fixture_with "$e2e_root/install-0.2.9.sh" \
  "file://$e2e_root/old-assets" "$e2e_root/config" "$e2e_root/data"
grep -F '"version": "0.2.9"' \
  "$e2e_root/data/opencode-agy-search/current/package.json" >/dev/null
old_current_target=$(readlink "$e2e_root/data/opencode-agy-search/current")
install_fixture "$e2e_root/config" "$e2e_root/data"

plugin="$e2e_root/config/opencode/plugins/agy-search.ts"
[[ -L "$plugin" ]]
[[ -f "$plugin" ]]
grep -F '"version": "0.3.0"' \
  "$e2e_root/data/opencode-agy-search/current/package.json" >/dev/null
new_current_target=$(readlink "$e2e_root/data/opencode-agy-search/current")
[[ "$new_current_target" != "$old_current_target" ]]
first_target=$(readlink "$plugin")
install_fixture "$e2e_root/config" "$e2e_root/data"
[[ $(readlink "$plugin") == "$first_target" ]]

archive_digest=$(awk 'NR == 1 { print $1 }' "$archive.sha256")
preexisting_release="$e2e_root/preexisting-data/opencode-agy-search/releases/0.3.0-${archive_digest:0:12}"
mkdir -p "$e2e_root/preexisting-extract" "$(dirname "$preexisting_release")"
tar -xzf "$archive" -C "$e2e_root/preexisting-extract"
mv "$e2e_root/preexisting-extract/package" "$preexisting_release"
printf 'tampered\n' >>"$preexisting_release/index.ts"
if install_fixture "$e2e_root/preexisting-config" "$e2e_root/preexisting-data"; then
  printf 'installer reused a mismatched preexisting release\n' >&2
  exit 1
fi
[[ ! -e "$e2e_root/preexisting-config/opencode/plugins/agy-search.ts" ]]

assert_preexisting_mode_rejected() {
  local mode="$1"
  local label="$2"
  local mode_data="$e2e_root/$label-data"
  local mode_extract="$e2e_root/$label-extract"
  local mode_release="$mode_data/opencode-agy-search/releases/0.3.0-${archive_digest:0:12}"
  mkdir -p "$mode_extract" "$(dirname "$mode_release")"
  tar -xzf "$archive" -C "$mode_extract"
  mv "$mode_extract/package" "$mode_release"
  chmod "$mode" "$mode_release/index.ts"
  if install_fixture "$e2e_root/$label-config" "$mode_data"; then
    printf 'installer accepted preexisting file mode %s\n' "$mode" >&2
    exit 1
  fi
  [[ ! -e "$e2e_root/$label-config/opencode/plugins/agy-search.ts" ]]
}

assert_preexisting_mode_rejected 0620 group-writable
assert_preexisting_mode_rejected 0602 world-writable

mkdir -p "$e2e_root/unsafe-assets/package/skills/agy-search"
ln -s /etc/passwd "$e2e_root/unsafe-assets/package/index.ts"
printf '{"name": "@happycastle114/opencode-agy-search", "version": "0.3.0"}\n' \
  >"$e2e_root/unsafe-assets/package/package.json"
printf 'unsafe\n' >"$e2e_root/unsafe-assets/package/LICENSE"
printf 'unsafe\n' >"$e2e_root/unsafe-assets/package/skills/agy-search/SKILL.md"
tar -czf "$e2e_root/unsafe-assets/$archive_basename" \
  -C "$e2e_root/unsafe-assets" package
rm -r "$e2e_root/unsafe-assets/package"
unsafe_archive="$e2e_root/unsafe-assets/$archive_basename"
if command -v sha256sum >/dev/null; then
  (cd "$e2e_root/unsafe-assets" && sha256sum "$archive_basename") \
    >"$unsafe_archive.sha256"
else
  (cd "$e2e_root/unsafe-assets" && shasum -a 256 "$archive_basename") \
    >"$unsafe_archive.sha256"
fi
if install_fixture_with "$repo_root/scripts/install.sh" \
  "file://$e2e_root/unsafe-assets" "$e2e_root/unsafe-config" "$e2e_root/unsafe-data"; then
  printf 'installer accepted an archive symlink\n' >&2
  exit 1
fi
[[ ! -e "$e2e_root/unsafe-config/opencode/plugins/agy-search.ts" ]]

printf '%064d  %s\n' 0 "$(basename "$archive")" >"$archive.sha256"
if install_fixture "$e2e_root/bad-config" "$e2e_root/bad-data"; then
  printf 'installer accepted an invalid checksum\n' >&2
  exit 1
fi
[[ ! -e "$e2e_root/bad-config/opencode/plugins/agy-search.ts" ]]
if command -v sha256sum >/dev/null; then
  (cd "$e2e_root/assets" && sha256sum "$(basename "$archive")") \
    >"$archive.sha256"
else
  (cd "$e2e_root/assets" && shasum -a 256 "$(basename "$archive")") \
    >"$archive.sha256"
fi

collision="$e2e_root/collision-config/opencode/plugins/agy-search.ts"
mkdir -p "$(dirname "$collision")"
printf 'user-owned\n' >"$collision"
if install_fixture "$e2e_root/collision-config" "$e2e_root/collision-data"; then
  printf 'installer overwrote a user-owned plugin\n' >&2
  exit 1
fi
grep -Fx 'user-owned' "$collision" >/dev/null

if [[ -n "${OPENCODE_BIN:-}" ]]; then
  XDG_CONFIG_HOME="$e2e_root/config" \
  XDG_DATA_HOME="$e2e_root/data" \
  XDG_CACHE_HOME="$e2e_root/cache" \
    "$OPENCODE_BIN" debug skill >"$e2e_root/skills.json"
  grep -F 'agy-search' "$e2e_root/skills.json" >/dev/null
fi

printf '{"installed":true,"global_plugin_loaded":%s}\n' \
  "$([[ -n "${OPENCODE_BIN:-}" ]] && printf true || printf false)"
