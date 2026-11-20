#!/bin/bash
# Publishes an Undertone update for Sparkle (in-app "Neue Version verfügbar").
#
#   scripts/org_publish_update.sh <Undertone.app> <feed-base-url/> [--no-upload] [--out <dir>]
#
# 1. Update archive dist/updates/Undertone-<version>-<build>.zip (only Undertone.app, ditto --keepParent)
# 2. EdDSA signature with Sparkle's sign_update (private key from the login keychain, account "undertone")
# 3. appcast.xml with one item (version, build, date, length, signature, minimumSystemVersion 15.0,
#    release notes from org/RELEASE_NOTES.md plus the fixed accessibility hint)
# 4. Upload archive + appcast.xml with curl --fail --upload-file to <feed-base-url>, then GET and compare.
#    --no-upload stops after step 3 (local test). Auth optional: CURL_AUTH="-u user:pass".
set -euo pipefail

APP="$1"
FEED_BASE="$2"
shift 2
UPLOAD=1
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_DIR/../dist/updates"
while [ $# -gt 0 ]; do
    case "$1" in
        --no-upload) UPLOAD=0 ;;
        --out) OUT_DIR="$2"; shift ;;
        *) echo "Unbekannte Option $1" >&2; exit 1 ;;
    esac
    shift
done
case "$FEED_BASE" in */) ;; *) FEED_BASE="$FEED_BASE/" ;; esac
CURL_AUTH="${CURL_AUTH:-}"
NOTES="$REPO_DIR/org/RELEASE_NOTES.md"
# GitHub mode: GITHUB_RELEASE_REPO=owner/name publishes a GitHub release (tag v<version>-<build>) with
# the archive and appcast.xml as assets; the feed base is then .../releases/latest/download/.
GITHUB_RELEASE_REPO="${GITHUB_RELEASE_REPO:-}"

SPARKLE_BIN=""
for candidate in "$REPO_DIR/.org-build/SourcePackages/artifacts/sparkle/Sparkle/bin" \
    "$REPO_DIR/.local-build/SourcePackages/artifacts/sparkle/Sparkle/bin"; do
    [ -x "$candidate/sign_update" ] && { SPARKLE_BIN="$candidate"; break; }
done
[ -n "$SPARKLE_BIN" ] || { echo "sign_update nicht gefunden (erst make org)" >&2; exit 1; }
[ -f "$NOTES" ] || { echo "Fehlt: $NOTES (Versionshinweise)" >&2; exit 1; }
codesign --verify --deep --strict "$APP" || { echo "Signatur der App ungültig" >&2; exit 1; }

PLIST="$APP/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
PUBKEY_APP=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PLIST")
PUBKEY_KEYCHAIN=$("$SPARKLE_BIN/generate_keys" --account undertone -p)
[ "$PUBKEY_APP" = "$PUBKEY_KEYCHAIN" ] || { echo "SUPublicEDKey der App passt nicht zum Schlüssel im Schlüsselbund" >&2; exit 1; }

mkdir -p "$OUT_DIR"
ARCHIVE_NAME="Undertone-$VERSION-$BUILD.zip"
ARCHIVE="$OUT_DIR/$ARCHIVE_NAME"
rm -f "$ARCHIVE"
ditto -c -k --keepParent --norsrc --noextattr --noqtn "$APP" "$ARCHIVE"

SIGNATURE_ATTRS=$("$SPARKLE_BIN/sign_update" --account undertone "$ARCHIVE")
ED_SIGNATURE=$(printf '%s' "$SIGNATURE_ATTRS" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(printf '%s' "$SIGNATURE_ATTRS" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')
[ -n "$ED_SIGNATURE" ] && [ -n "$LENGTH" ] || { echo "sign_update lieferte keine Signatur: $SIGNATURE_ATTRS" >&2; exit 1; }
"$SPARKLE_BIN/sign_update" --account undertone --verify "$ARCHIVE" "$ED_SIGNATURE" >/dev/null \
    || { echo "Signaturprüfung fehlgeschlagen" >&2; exit 1; }

TAG="v$VERSION-$BUILD"
if [ -n "$GITHUB_RELEASE_REPO" ]; then
    ENCLOSURE_URL="https://github.com/$GITHUB_RELEASE_REPO/releases/download/$TAG/$ARCHIVE_NAME"
else
    ENCLOSURE_URL="$FEED_BASE$ARCHIVE_NAME"
fi

/usr/bin/python3 -I - "$OUT_DIR/appcast.xml" "$NOTES" "$VERSION" "$BUILD" "$ENCLOSURE_URL" \
    "$LENGTH" "$ED_SIGNATURE" <<'PY'
import datetime, html, re, sys
out, notes_path, version, build, url, length, signature = sys.argv[1:]
hint = ("Nach dem Update bleibt Undertone bereit. Falls die Diktiertaste nicht reagiert: "
        "Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen, Undertone entfernen und neu hinzufügen.")

def markdown_to_html(text):
    parts, in_list = [], False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith(("- ", "* ")):
            if not in_list:
                parts.append("<ul>"); in_list = True
            parts.append(f"<li>{inline(stripped[2:])}</li>")
            continue
        if in_list:
            parts.append("</ul>"); in_list = False
        if not stripped:
            continue
        heading = re.match(r"^(#{1,3})\s+(.*)", stripped)
        if heading:
            level = min(len(heading.group(1)) + 2, 5)
            parts.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
        else:
            parts.append(f"<p>{inline(stripped)}</p>")
    if in_list:
        parts.append("</ul>")
    return "\n".join(parts)

def inline(text):
    text = html.escape(text)
    return re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)

notes = markdown_to_html(open(notes_path, encoding="utf-8").read())
notes += f"\n<p><i>{html.escape(hint)}</i></p>"
pub_date = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Undertone</title>
    <language>de</language>
    <item>
      <title>Undertone {html.escape(version)}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:version>{html.escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <description><![CDATA[{notes}]]></description>
      <enclosure url="{html.escape(url)}" length="{length}" type="application/octet-stream" sparkle:edSignature="{signature}"/>
    </item>
  </channel>
</rss>
"""
open(out, "w", encoding="utf-8").write(xml)
PY

echo "Update $VERSION ($BUILD):"
printf '  %s\t%s Bytes\t%s\n' "$ARCHIVE_NAME" "$LENGTH" "$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"
echo "  appcast.xml -> enclosure $ENCLOSURE_URL"

if [ $UPLOAD -eq 0 ]; then
    echo "Kein Upload (--no-upload). Dateien in $OUT_DIR"
    exit 0
fi

verify_url() {
    local file="$1" url="$2" check
    check="$(mktemp)"
    curl --fail --show-error --silent --location -o "$check" "$url"
    if [ "$(shasum -a 256 "$file" | cut -d' ' -f1)" != "$(shasum -a 256 "$check" | cut -d' ' -f1)" ]; then
        rm -f "$check"; echo "Abweichung beim Abruf: $url" >&2; exit 1
    fi
    rm -f "$check"; echo "  OK: $url"
}

if [ -n "$GITHUB_RELEASE_REPO" ]; then
    command -v gh >/dev/null || { echo "gh nicht installiert" >&2; exit 1; }
    NOTES_FILE="$(mktemp)"
    {
        cat "$NOTES"
        echo
        echo "Nach dem Update bleibt Undertone bereit. Falls die Diktiertaste nicht reagiert: Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen, Undertone entfernen und neu hinzufügen."
        echo
        echo "---"
        echo "Undertone basiert auf [VoiceInk](https://github.com/Beingpax/VoiceInk) (GPLv3). Enthaltenes Sprachmodell: [Parakeet Ultra](https://huggingface.co/moondream/parakeet-ultra) von Moondream bzw. [CoreML-Fassung](https://huggingface.co/FluidInference/parakeet-ultra-coreml) von FluidInference (CC-BY-4.0), basierend auf NVIDIA Parakeet; Sprachpausen-Erkennung [Silero VAD](https://huggingface.co/FluidInference/silero-vad-coreml) (MIT)."
        echo
        echo "Updates sind mit einem EdDSA-Schlüssel signiert; die App installiert nur passend signierte Archive."
    } > "$NOTES_FILE"
    echo "GitHub-Release $TAG in $GITHUB_RELEASE_REPO"
    gh release create "$TAG" "$ARCHIVE" "$OUT_DIR/appcast.xml" \
        --repo "$GITHUB_RELEASE_REPO" --title "Undertone $VERSION ($BUILD)" --notes-file "$NOTES_FILE" --latest
    rm -f "$NOTES_FILE"
    verify_url "$ARCHIVE" "$ENCLOSURE_URL"
    verify_url "$OUT_DIR/appcast.xml" "https://github.com/$GITHUB_RELEASE_REPO/releases/latest/download/appcast.xml"
    echo "Veröffentlicht: https://github.com/$GITHUB_RELEASE_REPO/releases/latest/download/appcast.xml"
    exit 0
fi

upload_and_verify() {
    local file="$1" name
    name="$(basename "$file")"
    echo "Lade hoch: $name"
    # shellcheck disable=SC2086
    curl --fail --show-error --silent $CURL_AUTH --upload-file "$file" "$FEED_BASE$name"
    local check
    check="$(mktemp)"
    # shellcheck disable=SC2086
    curl --fail --show-error --silent $CURL_AUTH -o "$check" "$FEED_BASE$name"
    if [ "$(shasum -a 256 "$file" | cut -d' ' -f1)" != "$(shasum -a 256 "$check" | cut -d' ' -f1)" ]; then
        rm -f "$check"
        echo "Abweichung nach dem Upload: $name" >&2
        exit 1
    fi
    rm -f "$check"
    echo "  OK"
}

# Archive first, appcast last: clients only see the new version once the archive is there.
upload_and_verify "$ARCHIVE"
upload_and_verify "$OUT_DIR/appcast.xml"
echo "Veröffentlicht: ${FEED_BASE}appcast.xml"
