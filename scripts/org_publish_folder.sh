#!/bin/bash
# Copies the Undertone release (Undertone.zip: app with built-in model + LIESMICH.txt) into the
# shared folder (e.g. a SharePoint/OneDrive folder synced to this Mac).
#
#   scripts/org_publish_folder.sh [target-dir]
#
#   target-dir    or environment variable UNDERTONE_PUBLISH_DIR (required)
#
# Source: ../dist/release/Undertone.zip (make org-release). Fixed file name; the shared folder keeps the versions.
# The former option --with-model is accepted and ignored (the model is part of the app now).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="$REPO_DIR/../dist/release"
TARGET="${UNDERTONE_PUBLISH_DIR:-}"

for arg in "$@"; do
    case "$arg" in
        --with-model) echo "Hinweis: --with-model wird ignoriert, das Modell steckt in der App." ;;
        *) TARGET="$arg" ;;
    esac
done

file="$RELEASE_DIR/Undertone.zip"
[ -f "$file" ] || { echo "Fehlt: $file (erst make org-release)" >&2; exit 1; }
[ -n "$TARGET" ] || { echo "Zielordner fehlt: Argument oder UNDERTONE_PUBLISH_DIR setzen" >&2; exit 1; }
[ -d "$TARGET" ] || { echo "Zielordner nicht gefunden: $TARGET" >&2; exit 1; }

echo "Kopiere Undertone.zip nach $TARGET"
cp -f "$file" "$TARGET/Undertone.zip.part"
mv -f "$TARGET/Undertone.zip.part" "$TARGET/Undertone.zip"
if [ "$(shasum -a 256 "$file" | cut -d' ' -f1)" != "$(shasum -a 256 "$TARGET/Undertone.zip" | cut -d' ' -f1)" ]; then
    echo "Abweichung nach dem Kopieren: Undertone.zip" >&2
    exit 1
fi
echo "Fertig. OneDrive lädt die Datei im Hintergrund hoch."
