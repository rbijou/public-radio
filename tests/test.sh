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

# A curl that always fails keeps the now-playing poller offline and silent in
# every test that is not specifically about it.
printf '#!%s\nexit 1\n' "$shell" >"$tmp/curl"
chmod +x "$tmp/curl"

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
cat >"$tmp/no-ffplay/printf" <<EOF
#!$shell
PATH='$PATH' exec printf "\$@"
EOF
chmod +x "$tmp/no-ffplay/printf"
if PATH="$tmp/no-ffplay" "$shell" "$root/bin/radio" liquid >"$tmp/no-ffplay.out" 2>&1; then
  echo 'expected a missing ffplay dependency to fail' >&2
  exit 1
fi
grep -F 'radio: ffplay is missing' "$tmp/no-ffplay.out" >/dev/null

# Now playing: canned curl stubs stand in for the station status endpoints.
# The stub ffplay returns once the curl stub has been polled (marker file,
# 20-second cap), so the asserts are event-ordered rather than timed.
np=$tmp/np
mkdir "$np"
cat >"$np/ffplay" <<EOF
#!$shell
if [ "\${NITEJAR_COOKIE+x}" = x ]; then
  printf '%s\n' 'NITEJAR_COOKIE leaked into ffplay environment' >&2
  exit 1
fi
n=0
while [ ! -e "$np/fetched" ] && [ "\$n" -lt 20 ]; do
  sleep 1
  n=\$((n + 1))
done
sleep 1
EOF
chmod +x "$np/ffplay"

cat >"$np/curl" <<EOF
#!$shell
printf '%s\n' "\$*" >>"$np/curl-liquid.args"
printf 'Fixture Artist - Liquid Fixture\n'
: >"$np/fetched"
EOF
chmod +x "$np/curl"
rm -f "$np/fetched"
PATH="$np:$PATH" "$shell" "$root/bin/radio" liquid >"$tmp/np-liquid.out"
grep -F 'Now playing: Fixture Artist - Liquid Fixture' "$tmp/np-liquid.out" >/dev/null
grep -F 'currentsong?sid=1' "$np/curl-liquid.args" >/dev/null

# The sleep poller must receive the gate cookie via curl's arguments while the
# environment stays scrubbed (radio unsets NITEJAR_COOKIE before spawning).
cat >"$np/curl" <<EOF
#!$shell
if [ "\${NITEJAR_COOKIE+x}" = x ]; then
  printf '%s\n' 'NITEJAR_COOKIE leaked into curl environment' >&2
  exit 1
fi
printf '%s\n' "\$*" >>"$np/curl-sleep.args"
printf '%s' '{"icestats":{"source":[{"listenurl":"http://nitejar.net:8000/nightjar.mp3","title":"Fixture - Ambient Track"},{"listenurl":"http://nitejar.net:8000/nightjar.opus"}]}}'
: >"$np/fetched"
EOF
rm -f "$np/fetched"
NITEJAR_COOKIE=$test_cookie PATH="$np:$PATH" "$shell" "$root/bin/radio" sleep >"$tmp/np-sleep.out"
grep -F 'Now playing: Fixture - Ambient Track' "$tmp/np-sleep.out" >/dev/null
grep -F "nj_awake=$test_cookie" "$np/curl-sleep.args" >/dev/null
grep -F 'status-json.xsl' "$np/curl-sleep.args" >/dev/null

# Titles are whitelisted to printable ASCII: C0 controls, DEL, UTF-8-encoded
# C1 controls (terminal escape injection), and any other non-ASCII byte must
# never reach the terminal.
cat >"$np/curl" <<EOF
#!$shell
printf 'Bad\033[31mC1\302\233Title\r\n'
: >"$np/fetched"
EOF
rm -f "$np/fetched"
PATH="$np:$PATH" "$shell" "$root/bin/radio" liquid >"$tmp/np-escape.out"
grep -F 'Now playing: Bad[31mC1Title' "$tmp/np-escape.out" >/dev/null
if LC_ALL=C grep "$(printf '\033')" "$tmp/np-escape.out" >/dev/null; then
  echo 'expected control bytes to be stripped from titles' >&2
  exit 1
fi
if LC_ALL=C grep "$(printf '\302')" "$tmp/np-escape.out" >/dev/null; then
  echo 'expected non-ASCII bytes to be stripped from titles' >&2
  exit 1
fi

# A flooding endpoint is capped: 8 KiB read cap, 200-character printed title.
# This stub touches the marker first because the read cap SIGPIPEs the writer.
cat >"$np/curl" <<EOF
#!$shell
: >"$np/fetched"
dd if=/dev/zero bs=1024 count=1024 2>/dev/null | tr '\\0' 'A'
EOF
rm -f "$np/fetched"
PATH="$np:$PATH" "$shell" "$root/bin/radio" liquid >"$tmp/np-flood.out"
grep 'Now playing: A\{200\}$' "$tmp/np-flood.out" >/dev/null
if grep 'A\{201\}' "$tmp/np-flood.out" >/dev/null; then
  echo 'expected flooded titles to be truncated at 200 characters' >&2
  exit 1
fi

# Signaling the script's own PID must stop playback (the exec-era behavior):
# TERM forwards to ffplay and radio reports ffplay's exit status (143 = died
# of TERM, since the stub installs no handler).
sig=$tmp/sig
mkdir "$sig"
printf '#!%s\nsleep 20\n' "$shell" >"$sig/ffplay"
chmod +x "$sig/ffplay"
cp "$tmp/curl" "$sig/curl"
PATH="$sig:$PATH" "$shell" "$root/bin/radio" liquid >"$tmp/sig.out" 2>&1 &
radio_pid=$!
sleep 2
kill -TERM "$radio_pid"
sig_status=0
wait "$radio_pid" || sig_status=$?
if [ "$sig_status" -ne 143 ]; then
  echo "expected TERM to stop radio with status 143, got $sig_status" >&2
  exit 1
fi

# KNBR has no track metadata: the poller must not run at all.
gi=$tmp/gi
mkdir "$gi"
printf '#!%s\nsleep 2\n' "$shell" >"$gi/ffplay"
chmod +x "$gi/ffplay"
cat >"$gi/curl" <<EOF
#!$shell
: >"$gi/giants-curl-called"
EOF
chmod +x "$gi/curl"
PATH="$gi:$PATH" "$shell" "$root/bin/radio" giants >"$tmp/np-giants.out"
if [ -e "$gi/giants-curl-called" ]; then
  echo 'expected no now-playing poll for giants' >&2
  exit 1
fi

# Without curl the stations must still play, just without titles. The printf
# wrapper keeps the restricted PATH honest on shells where printf is not a
# builtin (mksh); it re-resolves through the full test PATH.
nocurl=$tmp/no-curl
mkdir "$nocurl"
cp "$tmp/ffplay" "$nocurl/ffplay"
ln -s "$(command -v cat)" "$nocurl/cat"
cat >"$nocurl/printf" <<EOF
#!$shell
PATH='$PATH' exec printf "\$@"
EOF
chmod +x "$nocurl/printf"
PATH="$nocurl" "$shell" "$root/bin/radio" liquid >"$tmp/no-curl.out" 2>&1
grep -F 'Playing Liquid DnB' "$tmp/no-curl.out" >/dev/null
if grep -F 'Now playing:' "$tmp/no-curl.out" >/dev/null; then
  echo 'expected no now-playing output without curl' >&2
  exit 1
fi

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
