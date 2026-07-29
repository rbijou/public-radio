#!/bin/sh

set -eu

usage() {
  printf '%s\n' 'Usage: ./install.sh [--uninstall]' >&2
}

case "$#" in
  0) action=install ;;
  1)
    if [ "$1" = '--uninstall' ]; then
      action=uninstall
    else
      usage
      exit 2
    fi
    ;;
  *)
    usage
    exit 2
    ;;
esac

if [ -z "${HOME:-}" ]; then
  printf '%s\n' 'radio installer: HOME is not set' >&2
  exit 1
fi

root=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
source_file="$root/bin/radio"
destination="$HOME/.local/bin"
target="$destination/radio"
link_target=

if [ -L "$target" ]; then
  link_target=$(readlink "$target" 2>/dev/null || :)
fi

if [ "$action" = uninstall ]; then
  if [ -L "$target" ] && [ "$link_target" = "$source_file" ]; then
    rm "$target"
    printf 'Removed radio link at %s\n' "$target"
  elif [ -e "$target" ] || [ -L "$target" ]; then
    printf 'radio installer: refusing to remove unrelated path %s\n' "$target" >&2
    exit 1
  else
    printf 'No radio link found at %s\n' "$target"
  fi
  exit 0
fi

if [ ! -x "$source_file" ]; then
  printf 'radio installer: source is missing or not executable: %s\n' "$source_file" >&2
  exit 1
fi

mkdir -p "$destination"
if [ -L "$target" ] && [ "$link_target" = "$source_file" ]; then
  printf 'Radio is already linked at %s\n' "$target"
elif [ -e "$target" ] || [ -L "$target" ]; then
  printf 'radio installer: refusing to replace existing path %s\n' "$target" >&2
  exit 1
else
  ln -s "$source_file" "$target"
  printf 'Linked radio at %s\n' "$target"
fi

case ":$PATH:" in
  *":$destination:"*) ;;
  *) printf 'Add %s to PATH before using radio.\n' "$destination" ;;
esac
