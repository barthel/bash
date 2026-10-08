#!/bin/sh
# rtk-update.sh: hält rtk (https://github.com/rtk-ai/rtk) per GitHub-Release aktuell.
#
# Hintergrund: Homebrew baut auf Intel-macOS keine Bottles mehr. Ein brew upgrade
# würde rust, llvm und cmake aus dem Quellcode bauen. Dieses Skript nutzt stattdessen
# das fertige Release-Binary (SHA-256 wird vom offiziellen install.sh geprüft).
#
# Aufruf aus topgrade: siehe [commands] in ~/.config/topgrade.toml
#
# Standard: installiert die jeweils neueste Release-Version nach ~/.local/bin/rtk.
#
# Versions-Pin (vorbereitet, standardmäßig AUS):
#   Umgebungsvariable RTK_PIN setzen, mit oder ohne führendes "v".
#   Beispiel einmalig:  RTK_PIN=0.51.0 ~/.local/bin/rtk-update.sh
#   Dauerhaft in topgrade: den auskommentierten Eintrag mit RTK_PIN in
#   ~/.config/topgrade.toml aktivieren und den Eintrag ohne Pin auskommentieren.
#   Ist RTK_PIN gesetzt, wird exakt diese Version installiert (auch als Downgrade).
#   Pin lösen: Variable weglassen bzw. den Eintrag ohne Pin wieder aktivieren.
#
# Zielverzeichnis überschreibbar mit RTK_INSTALL_DIR (Standard: ~/.local/bin).

set -e

INSTALL_DIR="${RTK_INSTALL_DIR:-$HOME/.local/bin}"
RTK_BIN="$INSTALL_DIR/rtk"

cur=""
if [ -x "$RTK_BIN" ]; then
    cur=$("$RTK_BIN" --version 2>/dev/null | awk '{print $2}') || cur=""
fi

if [ -n "${RTK_PIN:-}" ]; then
    want=${RTK_PIN#v}
    echo "rtk: Versions-Pin aktiv ($want)"
else
    want=$(curl -fsSI --max-time 20 https://github.com/rtk-ai/rtk/releases/latest \
        | grep -i '^location:' | sed -E 's|.*/tag/v?||' | tr -d '\r\n') || want=""
    [ -n "$want" ] || { echo "rtk: neueste Version nicht ermittelbar" >&2; exit 1; }
fi

if [ "$cur" = "$want" ]; then
    echo "rtk $cur ist aktuell ($RTK_BIN)"
    exit 0
fi

echo "rtk: ${cur:-nicht installiert} -> $want"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --max-time 30 -o "$tmp/install.sh" \
    https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh
RTK_INSTALL_DIR="$INSTALL_DIR" RTK_VERSION="v$want" sh "$tmp/install.sh"
