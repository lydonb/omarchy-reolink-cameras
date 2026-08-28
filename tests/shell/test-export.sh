#!/usr/bin/env bash
set -euo pipefail

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
test_root=$(mktemp -d -t omarchy-reolink-export.XXXXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

export HOME="$test_root/home"
export XDG_CONFIG_HOME="$test_root/config"
export XDG_CACHE_HOME="$test_root/cache"
mkdir -p -- "$HOME/Pictures" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME/omarchy-reolink/snapshots"
chmod 700 -- "$HOME" "$HOME/Pictures" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" \
  "$XDG_CACHE_HOME/omarchy-reolink" "$XDG_CACHE_HOME/omarchy-reolink/snapshots"
printf 'XDG_PICTURES_DIR="$HOME/Pictures"\n' >"$XDG_CONFIG_HOME/user-dirs.dirs"

host_id="host_export_fixture"
source="$XDG_CACHE_HOME/omarchy-reolink/snapshots/${host_id}-ch0.jpg"
printf '\377\330SAFE_REOLINK_EXPORT\377\331' >"$source"
chmod 600 -- "$source"
payload=$(jq -cn --arg hostId "$host_id" '{operation:"export",hostId:$hostId,channel:0}')

first=$(printf '%s\n' "$payload" | "$plugin_root/scripts/reolink-snapshot-export")
first_path=$(jq -r '.path' <<<"$first")
[[ $first_path == "$HOME/Pictures/Reolink/"*/*.jpg ]]
[[ -f $first_path && ! -L $first_path && $(stat -c %a -- "$first_path") == 600 ]]
[[ $(stat -c %a -- "$HOME/Pictures/Reolink") == 700 ]]
[[ $(stat -c %a -- "${first_path%/*}") == 700 ]]
cmp -- "$source" "$first_path"

second=$(printf '%s\n' "$payload" | "$plugin_root/scripts/reolink-snapshot-export")
second_path=$(jq -r '.path' <<<"$second")
[[ $second_path != "$first_path" && -f $second_path ]]

outside="$test_root/outside.jpg"
printf '\377\330OUTSIDE\377\331' >"$outside"
chmod 600 -- "$outside"
ln -s -- "$outside" "$XDG_CACHE_HOME/omarchy-reolink/snapshots/host_symlink_fixture-ch0.jpg"
symlink_payload=$(jq -cn '{operation:"export",hostId:"host_symlink_fixture",channel:0}')
if printf '%s\n' "$symlink_payload" | "$plugin_root/scripts/reolink-snapshot-export" >/dev/null 2>&1; then
  echo "snapshot export followed a source symlink" >&2
  exit 1
fi

extra_field=$(jq -c '.source="/etc/passwd"' <<<"$payload")
if printf '%s\n' "$extra_field" | "$plugin_root/scripts/reolink-snapshot-export" >/dev/null 2>&1; then
  echo "snapshot export accepted a caller-supplied source" >&2
  exit 1
fi

chmod 644 -- "$source"
if printf '%s\n' "$payload" | "$plugin_root/scripts/reolink-snapshot-export" >/dev/null 2>&1; then
  echo "snapshot export accepted a non-private cache file" >&2
  exit 1
fi
chmod 600 -- "$source"

hardlink="$test_root/source-hardlink.jpg"
ln -- "$source" "$hardlink"
if printf '%s\n' "$payload" | "$plugin_root/scripts/reolink-snapshot-export" >/dev/null 2>&1; then
  echo "snapshot export accepted a multiply linked cache file" >&2
  exit 1
fi
rm -- "$hardlink"

mv -- "$source" "$source.valid"
printf 'NOT_A_JPEG' >"$source"
chmod 600 -- "$source"
if printf '%s\n' "$payload" | "$plugin_root/scripts/reolink-snapshot-export" >/dev/null 2>&1; then
  echo "snapshot export accepted invalid image data" >&2
  exit 1
fi
rm -- "$source"
mv -- "$source.valid" "$source"

date_dir="$HOME/Pictures/Reolink/$(date '+%Y-%m-%d')"
mv -- "$date_dir" "$date_dir.real"
ln -s -- "$test_root" "$date_dir"
if printf '%s\n' "$payload" | "$plugin_root/scripts/reolink-snapshot-export" >/dev/null 2>&1; then
  echo "snapshot export followed a dated Pictures symlink" >&2
  exit 1
fi
unlink "$date_dir"
mv -- "$date_dir.real" "$date_dir"

mv -- "$HOME/Pictures/Reolink" "$HOME/Pictures/Reolink.real"
ln -s -- "$test_root" "$HOME/Pictures/Reolink"
if printf '%s\n' "$payload" | "$plugin_root/scripts/reolink-snapshot-export" >/dev/null 2>&1; then
  echo "snapshot export followed a managed Pictures symlink" >&2
  exit 1
fi
[[ -z $(find "$test_root" -maxdepth 1 -type f -name 'Reolink-*.jpg' -print -quit) ]]
