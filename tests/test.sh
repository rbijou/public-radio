#!/bin/sh

set -eu

root=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
shell=$(command -v sh)

printf '#!%s\n' "$shell" >"$tmp/ffplay"
cat >>"$tmp/ffplay" <<'EOF'
if [ "${NITEJAR_COOKIE+x}" = x ]; then
  printf '%s\n' 'NITEJAR_COOKIE leaked into ffplay environment' >&2
  exit 1
fi
printf '<%s>\n' "$@"
EOF
chmod +x "$tmp/ffplay"

PATH="$tmp:${PATH:-/usr/bin:/bin}"; export PATH

run_radio() {
  "$shell" "$root/bin/radio" "$@"
}

test_cookie=$(printf '%064d' 0)
NITEJAR_COOKIE=$test_cookie
export NITEJAR_COOKIE

"$shell" -n "$root/bin/radio"
"$shell" -n "$root/install.sh"
"$shell" -n "$root/tests/test.sh"

run_radio sleep >"$tmp/sleep.out"
unset NITEJAR_COOKIE
grep -F '[ A M B I E N T ]' "$tmp/sleep.out" >/dev/null
grep -F '<https://nitejar.net/stream/nightjar.opus>' "$tmp/sleep.out" >/dev/null
grep -F "nj_awake=$test_cookie" "$tmp/sleep.out" >/dev/null

run_radio liquid >"$tmp/liquid.out"
grep -F '[ J A Z Z Y  D R U M  &  B A S S ]' "$tmp/liquid.out" >/dev/null
grep -F '<https://antares.dribbcast.com/proxy/dave1/stream/;>' "$tmp/liquid.out" >/dev/null

run_radio giants >"$tmp/giants.out"
grep -F '[ S A N  F R A N C I S C O ]' "$tmp/giants.out" >/dev/null
grep -F '<https://playerservices.streamtheworld.com/api/livestream-redirect/KNBRAMAAC.aac>' "$tmp/giants.out" >/dev/null

for argument in \
  -hide_banner -nodisp -nostats -reconnect -reconnect_at_eof \
  -reconnect_on_network_error -reconnect_streamed -reconnect_delay_max
do
  grep -F "<$argument>" "$tmp/liquid.out" >/dev/null
done

if NITEJAR_COOKIE= "$shell" "$root/bin/radio" sleep >"$tmp/no-cookie.out" 2>&1; then
  echo 'expected a missing Nitejar cookie to fail' >&2
  exit 1
fi
grep -F 'NITEJAR_COOKIE must be a 64-character lowercase SHA-256 value' "$tmp/no-cookie.out" >/dev/null

if NITEJAR_COOKIE=abc "$shell" "$root/bin/radio" sleep >"$tmp/short-cookie.out" 2>&1; then
  echo 'expected a short Nitejar cookie to fail' >&2
  exit 1
fi
grep -F 'NITEJAR_COOKIE must be a 64-character lowercase SHA-256 value' "$tmp/short-cookie.out" >/dev/null

if NITEJAR_COOKIE="${test_cookie%?}X" "$shell" "$root/bin/radio" sleep >"$tmp/invalid-cookie.out" 2>&1; then
  echo 'expected a non-hex Nitejar cookie to fail' >&2
  exit 1
fi
grep -F 'NITEJAR_COOKIE must be a 64-character lowercase SHA-256 value' "$tmp/invalid-cookie.out" >/dev/null

if run_radio invalid >"$tmp/invalid.out" 2>&1; then
  echo 'expected an invalid station to fail' >&2
  exit 1
fi
grep -F 'Usage: radio {sleep|liquid|giants}' "$tmp/invalid.out" >/dev/null

if run_radio sleep unexpected >"$tmp/extra.out" 2>&1; then
  echo 'expected extra arguments to fail' >&2
  exit 1
fi
grep -F 'Usage: radio {sleep|liquid|giants}' "$tmp/extra.out" >/dev/null

if run_radio >"$tmp/missing.out" 2>&1; then
  echo 'expected a missing station to fail' >&2
  exit 1
fi
grep -F 'Usage: radio {sleep|liquid|giants}' "$tmp/missing.out" >/dev/null

mkdir "$tmp/no-ffplay"
if PATH="$tmp/no-ffplay" "$shell" "$root/bin/radio" liquid >"$tmp/no-ffplay.out" 2>&1; then
  echo 'expected a missing ffplay dependency to fail' >&2
  exit 1
fi
grep -F 'radio: ffplay is missing' "$tmp/no-ffplay.out" >/dev/null

install_home="$tmp/install-home"
HOME="$install_home" "$shell" "$root/install.sh" >/dev/null
test -L "$install_home/.local/bin/radio"
test -x "$install_home/.local/bin/radio"
test "$(readlink "$install_home/.local/bin/radio")" = "$root/bin/radio"
HOME="$install_home" "$shell" "$root/install.sh" >"$tmp/reinstall.out"
grep -F 'Radio is already linked' "$tmp/reinstall.out" >/dev/null
HOME="$install_home" "$shell" "$root/install.sh" --uninstall >/dev/null
test ! -e "$install_home/.local/bin/radio"
test ! -L "$install_home/.local/bin/radio"

occupied_home="$tmp/occupied-home"
mkdir -p "$occupied_home/.local/bin"
printf '%s\n' 'keep me' >"$occupied_home/.local/bin/radio"
if HOME="$occupied_home" "$shell" "$root/install.sh" >"$tmp/occupied.out" 2>&1; then
  echo 'expected the installer to refuse an existing file' >&2
  exit 1
fi
grep -F 'refusing to replace existing path' "$tmp/occupied.out" >/dev/null
grep -Fx 'keep me' "$occupied_home/.local/bin/radio" >/dev/null
if HOME="$occupied_home" "$shell" "$root/install.sh" --uninstall >"$tmp/occupied-uninstall.out" 2>&1; then
  echo 'expected the uninstaller to refuse an existing file' >&2
  exit 1
fi
grep -F 'refusing to remove unrelated path' "$tmp/occupied-uninstall.out" >/dev/null
grep -Fx 'keep me' "$occupied_home/.local/bin/radio" >/dev/null

symlink_home="$tmp/symlink-home"
mkdir -p "$symlink_home/.local/bin" "$tmp/unrelated-directory"
ln -s "$tmp/unrelated-directory" "$symlink_home/.local/bin/radio"
if HOME="$symlink_home" "$shell" "$root/install.sh" >"$tmp/symlink.out" 2>&1; then
  echo 'expected the installer to refuse an unrelated symlink' >&2
  exit 1
fi
grep -F 'refusing to replace existing path' "$tmp/symlink.out" >/dev/null
test -L "$symlink_home/.local/bin/radio"
test ! -e "$tmp/unrelated-directory/radio"
if HOME="$symlink_home" "$shell" "$root/install.sh" --uninstall >"$tmp/symlink-uninstall.out" 2>&1; then
  echo 'expected the uninstaller to refuse an unrelated symlink' >&2
  exit 1
fi
grep -F 'refusing to remove unrelated path' "$tmp/symlink-uninstall.out" >/dev/null
test -L "$symlink_home/.local/bin/radio"
test "$(readlink "$symlink_home/.local/bin/radio")" = "$tmp/unrelated-directory"

printf 'All tests passed.\n'
