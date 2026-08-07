#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temp_base=$(cd "${TMPDIR:-/tmp}" && pwd -P)
e2e_root=$(mktemp -d "$temp_base/opencode-agy-search-installer.XXXXXX")
touch "$e2e_root/.opencode-agy-search-installer-owned"
server_pid=""
fixture_port=""

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
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

start_fixture_server() {
  local certificate="$e2e_root/fixture-cert.pem"
  local private_key="$e2e_root/fixture-key.pem"
  local port_file="$e2e_root/fixture-port"

  command -v openssl >/dev/null || {
    printf 'openssl is required for the loopback HTTPS fixture\n' >&2
    exit 1
  }
  command -v python3 >/dev/null || {
    printf 'python3 is required for the loopback HTTPS fixture\n' >&2
    exit 1
  }
  openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 \
    -keyout "$private_key" -out "$certificate" -subj '/CN=127.0.0.1' \
    -addext 'subjectAltName=IP:127.0.0.1' >/dev/null 2>&1
  python3 - "$e2e_root" "$certificate" "$private_key" >"$port_file" 2>"$e2e_root/fixture-server.log" <<'PY' &
import functools
import http.server
import ssl
import sys

directory, certificate, private_key = sys.argv[1:]
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=directory)
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certificate, private_key)
server.socket = context.wrap_socket(server.socket, server_side=True)
print(server.server_address[1], flush=True)
server.serve_forever()
PY
  server_pid=$!
  for _ in {1..50}; do
    [[ -s "$port_file" ]] && break
    sleep 0.1
  done
  [[ -s "$port_file" ]] || {
    printf 'loopback HTTPS fixture did not start\n' >&2
    exit 1
  }
  fixture_port=$(tr -d '\n' <"$port_file")
}

prepare_fixture_installer() {
  local source="$1"
  local asset_directory="$2"
  local destination="$3"

  # The shipped installer has no runtime URL override. This copy exists only
  # inside the test temp directory and bakes in the loopback HTTPS fixture.
  sed "s|^DEFAULT_DOWNLOAD_URL=.*|DEFAULT_DOWNLOAD_URL=\"https://127.0.0.1:${fixture_port}/${asset_directory}\"|" \
    "$source" >"$destination"
  chmod 700 "$destination"
}

mkdir -p "$e2e_root/assets" "$e2e_root/home"
cd "$repo_root"
npm pack --json --pack-destination "$e2e_root/assets" >/dev/null
packed=$(find "$e2e_root/assets" -maxdepth 1 -type f -name '*.tgz')
archive="$e2e_root/assets/opencode-agy-search-0.3.10.tgz"
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
perl -0pi -e 's/"version": "0\.3\.10"/"version": "0.2.9"/' \
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
sed 's/PACKAGE_VERSION="0.3.10"/PACKAGE_VERSION="0.2.9"/' \
  "$repo_root/scripts/install.sh" >"$e2e_root/install-0.2.9.template.sh"

start_fixture_server
current_installer="$e2e_root/install-current.sh"
old_installer="$e2e_root/install-0.2.9.sh"
prepare_fixture_installer "$repo_root/scripts/install.sh" assets "$current_installer"
prepare_fixture_installer "$e2e_root/install-0.2.9.template.sh" old-assets "$old_installer"

install_fixture_with() {
  installer="$1"
  target_config="$2"
  target_data="$3"
  HOME="$e2e_root/home" \
  XDG_CONFIG_HOME="$target_config" \
  XDG_DATA_HOME="$target_data" \
  CURL_CA_BUNDLE="$e2e_root/fixture-cert.pem" \
    sh "$installer"
}

install_fixture() {
  target_config="$1"
  target_data="$2"
  install_fixture_with "$current_installer" "$target_config" "$target_data"
}

mkdir -p "$e2e_root/insecure-install-parent"
chmod 0777 "$e2e_root/insecure-install-parent"
if OPENCODE_AGY_SEARCH_INSTALL_ROOT="$e2e_root/insecure-install-parent/install" \
  install_fixture "$e2e_root/insecure-install-config" "$e2e_root/insecure-install-data"; then
  printf 'installer accepted a non-sticky world-writable install ancestor\n' >&2
  exit 1
fi
[[ ! -e "$e2e_root/insecure-install-config/opencode/plugins/agy-search.ts" ]]
chmod 0700 "$e2e_root/insecure-install-parent"

install_fixture_with "$old_installer" "$e2e_root/config" "$e2e_root/data"
grep -F '"version": "0.2.9"' \
  "$e2e_root/data/opencode-agy-search/current/package.json" >/dev/null
old_current_target=$(readlink "$e2e_root/data/opencode-agy-search/current")
install_fixture "$e2e_root/config" "$e2e_root/data"

plugin="$e2e_root/config/opencode/plugins/agy-search.ts"
[[ -L "$plugin" ]]
[[ -f "$plugin" ]]
grep -F '"version": "0.3.10"' \
  "$e2e_root/data/opencode-agy-search/current/package.json" >/dev/null
new_current_target=$(readlink "$e2e_root/data/opencode-agy-search/current")
[[ "$new_current_target" != "$old_current_target" ]]
first_target=$(readlink "$plugin")
install_fixture "$e2e_root/config" "$e2e_root/data"
[[ $(readlink "$plugin") == "$first_target" ]]

archive_digest=$(awk 'NR == 1 { print $1 }' "$archive.sha256")
preexisting_release="$e2e_root/preexisting-data/opencode-agy-search/releases/0.3.10-${archive_digest:0:12}"
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
  local mode_release="$mode_data/opencode-agy-search/releases/0.3.10-${archive_digest:0:12}"
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
printf '{"name": "@happycastle114/opencode-agy-search", "version": "0.3.10"}\n' \
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
unsafe_installer="$e2e_root/install-unsafe-assets.sh"
prepare_fixture_installer "$repo_root/scripts/install.sh" unsafe-assets "$unsafe_installer"
if install_fixture_with "$unsafe_installer" "$e2e_root/unsafe-config" "$e2e_root/unsafe-data"; then
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

unsafe_scheme_installer="$e2e_root/install-unsafe-scheme.sh"
sed "s|^DEFAULT_DOWNLOAD_URL=.*|DEFAULT_DOWNLOAD_URL=\"file://$e2e_root/assets\"|" \
  "$repo_root/scripts/install.sh" >"$unsafe_scheme_installer"
if install_fixture_with "$unsafe_scheme_installer" \
  "$e2e_root/unsafe-scheme-config" "$e2e_root/unsafe-scheme-data"; then
  printf 'installer accepted a file download URL\n' >&2
  exit 1
fi
[[ ! -e "$e2e_root/unsafe-scheme-config/opencode/plugins/agy-search.ts" ]]

# A hostile legacy override cannot replace the baked production release URL.
OPENCODE_AGY_SEARCH_DOWNLOAD_URL="file://$e2e_root/assets" \
  install_fixture "$e2e_root/override-config" "$e2e_root/override-data"
[[ -L "$e2e_root/override-config/opencode/plugins/agy-search.ts" ]]
! grep -F 'OPENCODE_AGY_SEARCH_DOWNLOAD_URL' "$repo_root/scripts/install.sh" >/dev/null

mkdir -p "$e2e_root/curl-home"
printf '%s\n' 'max-filesize = 1' >"$e2e_root/curl-home/.curlrc"
CURL_HOME="$e2e_root/curl-home" \
  install_fixture "$e2e_root/curlrc-config" "$e2e_root/curlrc-data"
[[ -L "$e2e_root/curlrc-config/opencode/plugins/agy-search.ts" ]]

HTTPS_PROXY='http://127.0.0.1:1' https_proxy='http://127.0.0.1:1' \
HTTP_PROXY='http://127.0.0.1:1' http_proxy='http://127.0.0.1:1' \
ALL_PROXY='http://127.0.0.1:1' all_proxy='http://127.0.0.1:1' \
NO_PROXY='' no_proxy='' \
  install_fixture "$e2e_root/proxy-config" "$e2e_root/proxy-data"
[[ -L "$e2e_root/proxy-config/opencode/plugins/agy-search.ts" ]]

install_fixture_with "$old_installer" \
  "$e2e_root/link-failure-config" "$e2e_root/link-failure-data"
link_failure_current="$e2e_root/link-failure-data/opencode-agy-search/current"
link_failure_plugin="$e2e_root/link-failure-config/opencode/plugins/agy-search.ts"
link_failure_current_target=$(readlink "$link_failure_current")
link_failure_plugin_target=$(readlink "$link_failure_plugin")
mkdir -p "$e2e_root/failing-bin"
cat >"$e2e_root/failing-bin/mv" <<'SH'
#!/bin/sh
for argument in "$@"; do
  case "$argument" in
    */.agy-search.ts.*) exit 91 ;;
  esac
done
exec /bin/mv "$@"
SH
chmod 700 "$e2e_root/failing-bin/mv"
if PATH="$e2e_root/failing-bin:$PATH" install_fixture \
  "$e2e_root/link-failure-config" "$e2e_root/link-failure-data"; then
  printf 'installer ignored a simulated plugin-link switch failure\n' >&2
  exit 1
fi
if [[ $(readlink "$link_failure_current") != "$link_failure_current_target" ]]; then
  printf 'installer did not restore current after a plugin-link switch failure\n' >&2
  exit 1
fi
if [[ ! -L "$link_failure_plugin" ]] || \
  [[ $(readlink "$link_failure_plugin") != "$link_failure_plugin_target" ]]; then
  printf 'installer did not restore the plugin after a plugin-link switch failure\n' >&2
  exit 1
fi
grep -F '"version": "0.2.9"' \
  "$link_failure_current/package.json" >/dev/null

collision="$e2e_root/collision-config/opencode/plugins/agy-search.ts"
install_fixture_with "$old_installer" \
  "$e2e_root/collision-config" "$e2e_root/collision-data"
collision_current="$e2e_root/collision-data/opencode-agy-search/current"
collision_current_target=$(readlink "$collision_current")
rm "$collision"
printf 'user-owned\n' >"$collision"
if install_fixture "$e2e_root/collision-config" "$e2e_root/collision-data"; then
  printf 'installer overwrote a user-owned plugin\n' >&2
  exit 1
fi
if [[ $(readlink "$collision_current") != "$collision_current_target" ]]; then
  printf 'installer advanced current before rejecting a user-owned plugin\n' >&2
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
