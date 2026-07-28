#!/usr/bin/env bash
set -euo pipefail
SCRIPT_ROOT=$(cd "$(dirname "$0")" && pwd) || exit 1

# pre-flight: verify the new config (from the repo, before touching anything).
if command -v Hyprland >/dev/null 2>&1; then
	echo "[+] verifying config..."
	Hyprland -c "$SCRIPT_ROOT/hyprland.lua" --verify-config
else
	echo "[o] warning: Hyprland binary not found, skipping verification" >&2
fi

# pause auto-reload so it doesn't reload mid-copy
HYPR_RUNNING=0
if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
	HYPR_RUNNING=1
	echo -n "[+] pausing auto-reload: "
	hyprctl eval 'hl.config({ misc = { disable_autoreload = true } })'
fi

# install
echo "[+] installing..."
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
set -x
mkdir -p "$DEST"
rm -rf "${DEST:?}/lib" "${DEST:?}/conf"
cp "$SCRIPT_ROOT/hyprland.lua" "$DEST/"
cp -rv "$SCRIPT_ROOT/lib" "$SCRIPT_ROOT/conf" "$DEST/"
set +x
echo

# apply
if [ "$HYPR_RUNNING" = 1 ]; then
	echo -n "[+] reloading: "
	hyprctl reload
	echo -n '[+] resuming auto-reload: '
	hyprctl eval 'hl.config({ misc = { disable_autoreload = false } })'
fi
