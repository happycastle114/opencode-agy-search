#!/bin/sh
set -eu

umask 077

if [ "$(id -u)" -eq 0 ]; then
    printf 'opencode-agy-search installer: run as the target user, not root\n' >&2
    exit 1
fi

PACKAGE_VERSION="0.3.1"
ARCHIVE_NAME="opencode-agy-search-${PACKAGE_VERSION}.tgz"
CHECKSUM_NAME="${ARCHIVE_NAME}.sha256"
DEFAULT_DOWNLOAD_URL="https://github.com/happycastle114/opencode-agy-search/releases/download/v${PACKAGE_VERSION}"
DOWNLOAD_URL="${OPENCODE_AGY_SEARCH_DOWNLOAD_URL:-$DEFAULT_DOWNLOAD_URL}"

fail() {
    printf 'opencode-agy-search installer: %s\n' "$1" >&2
    exit 1
}

replace_symlink() {
    new_link="$1"
    destination="$2"
    expected_target="$3"

    if [ ! -e "$destination" ] && [ ! -L "$destination" ]; then
        mv "$new_link" "$destination"
    elif mv -fh "$new_link" "$destination" 2>/dev/null; then
        : # BSD/macOS: -h replaces a symlink-to-directory without following it.
    elif mv -fT "$new_link" "$destination" 2>/dev/null; then
        : # GNU: -T treats the destination as a normal path.
    else
        # Minimal POSIX mv implementations have neither flag. The install lock
        # prevents concurrent writers; use a non-dereferencing two-step switch.
        rm "$destination"
        mv "$new_link" "$destination"
    fi

    [ -L "$destination" ] || fail "failed to install symlink at $destination"
    [ "$(readlink "$destination")" = "$expected_target" ] || \
        fail "installed symlink at $destination has the wrong target"
}

validate_package_tree() {
    tree_root="$1"
    [ -d "$tree_root" ] && [ ! -L "$tree_root" ] || \
        fail "$tree_root must be a real directory"
    unsafe_entry="$(find "$tree_root" \
        \( ! -type f ! -type d -o -type f -links +1 \
        -o -perm -020 -o -perm -002 \) \
        -print -quit)"
    [ -z "$unsafe_entry" ] || fail "package tree contains an unsafe entry"
}

download() {
    source_url="$1"
    destination="$2"
    command -v curl >/dev/null 2>&1 || fail "curl is required"
    case "$source_url" in
        https://*) curl --proto '=https' --tlsv1.2 -fLsS "$source_url" -o "$destination" ;;
        file://*) curl -fLsS "$source_url" -o "$destination" ;;
        *) fail "download URL must use HTTPS" ;;
    esac
}

home_directory="${HOME:-}"
if [ -z "$home_directory" ]; then
    fail "HOME is required"
fi
config_home="${XDG_CONFIG_HOME:-$home_directory/.config}"
data_home="${XDG_DATA_HOME:-$home_directory/.local/share}"
plugin_directory="${OPENCODE_AGY_SEARCH_PLUGIN_DIR:-$config_home/opencode/plugins}"
install_root="${OPENCODE_AGY_SEARCH_INSTALL_ROOT:-$data_home/opencode-agy-search}"
temp_base="${TMPDIR:-/tmp}"
mkdir -p "$install_root"
lock_directory="$install_root/.install-lock"
temporary="$(mktemp -d "$temp_base/opencode-agy-search.XXXXXX")"
marker="$temporary/.opencode-agy-search-owned"
current_temporary=""
plugin_temporary=""
lock_acquired=0
touch "$marker"

cleanup() {
    status=$?
    trap - EXIT INT TERM
    if [ -n "$current_temporary" ] && [ -L "$current_temporary" ]; then
        rm "$current_temporary"
    fi
    if [ -n "$plugin_temporary" ] && [ -L "$plugin_temporary" ]; then
        rm "$plugin_temporary"
    fi
    if [ "$lock_acquired" -eq 1 ] && [ -d "$lock_directory" ]; then
        rmdir "$lock_directory" 2>/dev/null || status=1
    fi
    case "$temporary" in
        "$temp_base"/opencode-agy-search.*)
            if [ -f "$marker" ]; then
                find "$temporary" -depth -delete
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

if ! mkdir "$lock_directory" 2>/dev/null; then
    fail "another install is running or $lock_directory is stale"
fi
lock_acquired=1

archive="$temporary/$ARCHIVE_NAME"
checksum="$temporary/$CHECKSUM_NAME"
download "$DOWNLOAD_URL/$ARCHIVE_NAME" "$archive"
download "$DOWNLOAD_URL/$CHECKSUM_NAME" "$checksum"

checksum_line_count="$(wc -l <"$checksum" | tr -d ' ')"
[ "$checksum_line_count" -eq 1 ] || fail "checksum document must contain one line"
IFS=' ' read -r expected_checksum checksum_filename checksum_extra <"$checksum" || \
    fail "invalid checksum document"
[ -z "${checksum_extra:-}" ] || fail "invalid checksum document"
[ "$checksum_filename" = "$ARCHIVE_NAME" ] || fail "checksum filename mismatch"
case "$expected_checksum" in
    ''|*[!0-9a-fA-F]*) fail "invalid checksum document" ;;
esac
[ "${#expected_checksum}" -eq 64 ] || fail "checksum must be SHA-256"
expected_checksum="$(printf '%s' "$expected_checksum" | tr '[:upper:]' '[:lower:]')"
if command -v sha256sum >/dev/null 2>&1; then
    actual_checksum="$(sha256sum "$archive" | awk '{ print $1 }')"
elif command -v shasum >/dev/null 2>&1; then
    actual_checksum="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
else
    fail "sha256sum or shasum is required"
fi
[ "$actual_checksum" = "$expected_checksum" ] || fail "archive checksum mismatch"

mkdir -p "$temporary/extract"
if ! tar -tzf "$archive" | while IFS= read -r entry; do
    case "$entry" in
        package|package/|package/*) ;;
        *) exit 1 ;;
    esac
    case "$entry" in
        ../*|*/../*|*/..|*/./*) exit 1 ;;
    esac
done; then
    fail "archive contains an unsafe path"
fi
if ! tar -tvzf "$archive" | while IFS= read -r listing; do
    case "$listing" in
        -*|d*) ;;
        *) exit 1 ;;
    esac
done; then
    fail "archive contains a link or unsupported entry type"
fi
tar -xzf "$archive" -C "$temporary/extract"
package_root="$temporary/extract/package"
validate_package_tree "$package_root"
for required in index.ts package.json LICENSE skills/agy-search/SKILL.md; do
    [ -f "$package_root/$required" ] || fail "archive is missing $required"
done
grep -F '"name": "@happycastle114/opencode-agy-search"' \
    "$package_root/package.json" >/dev/null || fail "archive package name is invalid"
grep -F "\"version\": \"$PACKAGE_VERSION\"" \
    "$package_root/package.json" >/dev/null || fail "archive package version is invalid"

release_id="${PACKAGE_VERSION}-$(printf '%s' "$actual_checksum" | cut -c1-12)"
release_directory="$install_root/releases/$release_id"
mkdir -p "$install_root/releases" "$plugin_directory"
if [ -e "$release_directory" ] || [ -L "$release_directory" ]; then
    validate_package_tree "$release_directory"
    diff -qr "$package_root" "$release_directory" >/dev/null 2>&1 || \
        fail "$release_directory does not match the verified archive"
else
    mv "$package_root" "$release_directory"
fi
validate_package_tree "$release_directory"
for required in index.ts package.json LICENSE skills/agy-search/SKILL.md; do
    [ -f "$release_directory/$required" ] || fail "installed release is missing $required"
done

current_link="$install_root/current"
if { [ -e "$current_link" ] || [ -L "$current_link" ]; } && [ ! -L "$current_link" ]; then
    fail "$current_link exists and is not an installer-owned symlink"
fi
current_temporary="$install_root/.current.$$"
ln -s "$release_directory" "$current_temporary"
replace_symlink "$current_temporary" "$current_link" "$release_directory"
current_temporary=""

plugin_link="$plugin_directory/agy-search.ts"
expected_plugin_target="$install_root/current/index.ts"
if [ -e "$plugin_link" ] || [ -L "$plugin_link" ]; then
    [ -L "$plugin_link" ] || fail "$plugin_link exists and is not an installer-owned symlink"
    [ "$(readlink "$plugin_link")" = "$expected_plugin_target" ] || \
        fail "$plugin_link points to a different plugin"
fi
plugin_temporary="$plugin_directory/.agy-search.ts.$$"
ln -s "$expected_plugin_target" "$plugin_temporary"
replace_symlink "$plugin_temporary" "$plugin_link" "$expected_plugin_target"
plugin_temporary=""

printf 'opencode-agy-search %s installed at %s\n' "$PACKAGE_VERSION" "$plugin_link"
printf 'restart OpenCode, then run: opencode debug skill\n'
