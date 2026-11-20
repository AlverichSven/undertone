#!/bin/bash
# Uploads the packed model files to a plain file server (e.g. Nexus raw repository) and verifies
# them afterwards by downloading each file and comparing size and SHA-256 with org/models.json.
#
#   scripts/org_upload_models.sh <base-url> [models-dir]
#
#   base-url    e.g. https://nexus.example/repository/raw-undertone/models
#   models-dir  default ../dist/models
#
# Anonymous upload by default; set CURL_AUTH="-u user:password" (or a netrc) if the server needs it.
set -euo pipefail

if [ $# -lt 1 ]; then
    sed -n '2,11p' "$0"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BASE_URL="${1%/}"
MODELS_DIR="${2:-$REPO_DIR/../dist/models}"
MANIFEST="$REPO_DIR/org/models.json"
CURL_AUTH="${CURL_AUTH:-}"

[ -f "$MANIFEST" ] || { echo "Fehlt: $MANIFEST (erst scripts/org_pack_models.sh)" >&2; exit 1; }

names=$(/usr/bin/python3 -I -c 'import json,sys; print("\n".join(sorted(json.load(open(sys.argv[1]))["files"])))' "$MANIFEST")
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

status=0
while IFS= read -r name; do
    [ -n "$name" ] || continue
    file="$MODELS_DIR/$name"
    [ -f "$file" ] || { echo "Fehlt lokal: $file" >&2; status=1; continue; }

    echo "Lade hoch: $name"
    # shellcheck disable=SC2086
    curl --fail --show-error --silent $CURL_AUTH --upload-file "$file" "$BASE_URL/$name"

    echo "Prüfe: $name"
    # shellcheck disable=SC2086
    curl --fail --show-error --silent $CURL_AUTH -o "$tmp_dir/check" "$BASE_URL/$name"
    if /usr/bin/python3 -I - "$MANIFEST" "$name" "$tmp_dir/check" <<'PY'
import hashlib, json, os, sys
manifest, name, path = sys.argv[1:]
expected = json.load(open(manifest))["files"][name]
digest = hashlib.sha256()
with open(path, "rb") as handle:
    for chunk in iter(lambda: handle.read(4 * 1024 * 1024), b""):
        digest.update(chunk)
size = os.path.getsize(path)
ok = size == expected["size"] and digest.hexdigest() == expected["sha256"]
print(f"  {'OK' if ok else 'ABWEICHUNG'}: {size} Bytes, sha256 {digest.hexdigest()}")
sys.exit(0 if ok else 1)
PY
    then :; else status=1; fi
    rm -f "$tmp_dir/check"
done <<< "$names"

if [ $status -ne 0 ]; then
    echo "Mindestens eine Datei fehlt oder weicht ab." >&2
fi
exit $status
