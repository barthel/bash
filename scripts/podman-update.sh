#!/bin/sh
# podman-update.sh: hält Podman (https://github.com/containers/podman) per GitHub-Release-Paket aktuell.
#
# Hintergrund: Podman 6.x unterstützt keine Intel-Macs mehr (Release Notes v6.0.0). Homebrew hat
# für 6.x keine Intel-Bottles, ein brew upgrade würde nicht lauffähig bauen. Der 5.x-Zweig wird
# weiter gepflegt und liefert ein signiertes amd64-Installer-Paket (Red Hat, notarisiert).
#
# Schritt 1: Client
#   1. neueste 5.x-Version mit amd64-Paket ermitteln (oder PODMAN_PIN)
#   2. Paket laden, SHA-256 gegen "shasums" und Signatur (Red Hat) prüfen
#   3. laufende Podman-Machine stoppen
#   4. sudo installer -pkg ... (installiert nach /opt/podman, Symlinks in /usr/local/bin zeigen darauf)
#   5. Machine wieder starten, falls sie vorher lief
#
# Schritt 2: Machine-VM (läuft immer, auch wenn der Client schon aktuell ist)
#   Vergleicht Major.Minor des Clients (z. B. 5.8) mit dem der laufenden VM. Weichen sie ab, wird die VM
#   mit "podman machine os apply quay.io/podman/machine-os:<Major.Minor> --restart" auf das passende
#   Image gehoben (Download rund 1 GB, Neustart der VM). Patch-Versionen innerhalb derselben Minor-Linie
#   löst das nicht aus. Ist die VM nicht gestartet, wird der Schritt übersprungen.
#   Das Image wird per ostree-unverified-registry von quay.io gezogen (keine Image-Signaturprüfung).
#   Rollback: podman machine ssh <Machine> 'sudo rpm-ostree rollback --reboot'
#
# Aufruf aus topgrade: siehe [commands] in ~/.config/topgrade.toml
#
# Standard: installiert die jeweils neueste Version der Hauptversion PODMAN_MAJOR (Standard: 5).
#
# Versions-Pin (vorbereitet, standardmäßig AUS):
#   Umgebungsvariable PODMAN_PIN setzen, mit oder ohne führendes "v".
#   Beispiel einmalig:  PODMAN_PIN=5.8.8 ~/.local/bin/podman-update.sh
#   Dauerhaft in topgrade: den auskommentierten Eintrag mit PODMAN_PIN in
#   ~/.config/topgrade.toml aktivieren und den Eintrag ohne Pin auskommentieren.
#   Ist PODMAN_PIN gesetzt, wird exakt diese Version installiert (auch als Downgrade).
#   Die VM folgt dem Client (Major.Minor der installierten Version).
#   Pin lösen: Variable weglassen bzw. den Eintrag ohne Pin wieder aktivieren.
#
# Weitere Variablen:
#   PODMAN_MAJOR       Hauptversion für die Suche (Standard 5)
#   PODMAN_MACHINE     Name der Machine (Standard podman-machine-default)
#   PODMAN_VM_SKIP=1   VM-Schritt überspringen
#   PODMAN_VM_TAG      Image-Tag für die VM erzwingen statt Major.Minor des Clients (z. B. 5.8)
#   PODMAN_VM_DRYRUN=1 VM-Befehl nur anzeigen, nicht ausführen
#
# Achtung: Das Paket ruft im preinstall "rm -rf /opt/podman" auf. Eigene Dateien dort gehen verloren.

set -e

MAJOR="${PODMAN_MAJOR:-5}"
MACHINE="${PODMAN_MACHINE:-podman-machine-default}"
OPT_BIN=/opt/podman/bin/podman
ASSET=podman-installer-macos-amd64.pkg
REPO=containers/podman
VM_REPO=quay.io/podman/machine-os

[ "$(uname -m)" = "x86_64" ] || { echo "podman-update: nur für Intel-Macs gedacht (uname -m = $(uname -m))" >&2; exit 1; }

update_client() {
    cur=""
    if [ -x "$OPT_BIN" ]; then
        cur=$("$OPT_BIN" --version 2>/dev/null | awk '{print $3}') || cur=""
    fi

    if [ -n "${PODMAN_PIN:-}" ]; then
        want=${PODMAN_PIN#v}
        echo "podman: Versions-Pin aktiv ($want)"
    else
        want=$(curl -fsSL --max-time 30 "https://api.github.com/repos/$REPO/releases?per_page=50" | python3 -c '
import sys, json
major, asset = sys.argv[1], sys.argv[2]
def key(t):
    return tuple(int(x) for x in t[1:].split(".") if x.isdigit())
cands = []
for r in json.load(sys.stdin):
    t = r["tag_name"]
    if r.get("prerelease") or r.get("draft") or not t.startswith("v" + major + "."):
        continue
    if any(a["name"] == asset for a in r["assets"]):
        cands.append(t)
if cands:
    print(max(cands, key=key)[1:])
' "$MAJOR" "$ASSET") || want=""
        [ -n "$want" ] || { echo "podman: keine ${MAJOR}.x-Version mit $ASSET gefunden (GitHub-Limit?)" >&2; exit 1; }
    fi

    if [ "$cur" = "$want" ]; then
        echo "podman $cur ist aktuell ($OPT_BIN)"
        return 0
    fi

    echo "podman: ${cur:-nicht aus /opt/podman installiert} -> $want"

    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    base="https://github.com/$REPO/releases/download/v$want"
    curl -fsSL --max-time 300 -o "$tmp/$ASSET" "$base/$ASSET"
    curl -fsSL --max-time 30 -o "$tmp/shasums" "$base/shasums"

    expected=$(grep "[[:space:]]$ASSET\$" "$tmp/shasums" | awk '{print $1}')
    [ -n "$expected" ] || { echo "podman: keine Prüfsumme für $ASSET in shasums, Abbruch" >&2; exit 1; }
    actual=$(shasum -a 256 "$tmp/$ASSET" | awk '{print $1}')
    [ "$expected" = "$actual" ] || { echo "podman: Prüfsumme stimmt nicht (erwartet $expected, erhalten $actual), Abbruch" >&2; exit 1; }
    echo "podman: SHA-256 geprüft"

    sig=$(pkgutil --check-signature "$tmp/$ASSET" 2>&1)
    echo "$sig" | grep -q "Red Hat, Inc." || { echo "podman: Signatur nicht von Red Hat, Abbruch" >&2; echo "$sig" >&2; exit 1; }
    echo "$sig" | grep -q "Notarization: trusted" || { echo "podman: Paket nicht notarisiert, Abbruch" >&2; exit 1; }
    echo "podman: Signatur und Notarisierung geprüft"

    was_running=0
    if command -v podman >/dev/null 2>&1; then
        state=$(podman machine inspect --format '{{.State}}' "$MACHINE" 2>/dev/null || true)
        if [ "$state" = "running" ]; then
            was_running=1
            echo "podman: stoppe Machine $MACHINE"
            podman machine stop "$MACHINE"
        fi
    fi

    sudo installer -pkg "$tmp/$ASSET" -target /

    [ -x "$OPT_BIN" ] || { echo "podman: $OPT_BIN fehlt nach der Installation" >&2; exit 1; }
    echo "podman: installiert $("$OPT_BIN" --version)"

    if [ "$was_running" = "1" ]; then
        echo "podman: starte Machine $MACHINE"
        "$OPT_BIN" machine start "$MACHINE"
    fi
}

update_vm() {
    if [ "${PODMAN_VM_SKIP:-0}" = "1" ]; then
        echo "podman-vm: übersprungen (PODMAN_VM_SKIP=1)"
        return 0
    fi
    [ -x "$OPT_BIN" ] || { echo "podman-vm: $OPT_BIN fehlt, übersprungen"; return 0; }

    state=$("$OPT_BIN" machine inspect --format '{{.State}}' "$MACHINE" 2>/dev/null || true)
    if [ "$state" != "running" ]; then
        echo "podman-vm: Machine $MACHINE läuft nicht (Status: ${state:-unbekannt}), übersprungen"
        return 0
    fi

    client_ver=$("$OPT_BIN" --version | awk '{print $3}')
    server_ver=$("$OPT_BIN" version --format '{{.Server.Version}}' 2>/dev/null || true)
    [ -n "$server_ver" ] || { echo "podman-vm: VM-Version nicht ermittelbar, übersprungen" >&2; return 0; }

    tag="${PODMAN_VM_TAG:-${client_ver%.*}}"
    vm_minor="${server_ver%.*}"

    if [ "$vm_minor" = "$tag" ]; then
        echo "podman-vm: VM ($server_ver) passt zum Image-Tag $tag"
        return 0
    fi

    echo "podman-vm: VM $server_ver -> Image-Tag $tag"

    # Existiert das Tag in der Registry? (Fehlt es, bleibt die VM unverändert.)
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
        -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
        "https://quay.io/v2/podman/machine-os/manifests/$tag" || true)
    if [ "$code" != "200" ]; then
        echo "podman-vm: Tag $VM_REPO:$tag nicht gefunden (HTTP $code), übersprungen" >&2
        return 0
    fi

    if [ "${PODMAN_VM_DRYRUN:-0}" = "1" ]; then
        echo "podman-vm: Dry-Run, würde ausführen: $OPT_BIN machine os apply $VM_REPO:$tag $MACHINE --restart"
        return 0
    fi

    "$OPT_BIN" machine os apply "$VM_REPO:$tag" "$MACHINE" --restart
    echo "podman-vm: VM jetzt $("$OPT_BIN" version --format '{{.Server.Version}}' 2>/dev/null || echo unbekannt)"
}

update_client
update_vm
