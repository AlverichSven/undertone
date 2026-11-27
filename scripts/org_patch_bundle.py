#!/usr/bin/env python3
"""Post-build branding for the organisation build ("Undertone").

Usage: org_patch_bundle.py <App.app> <Localizable.xcstrings> <model> <model-server-url>
                           [<model-archive-url> [<models.json>]]

- Info.plist: bundle id, names, executable, model and model-server keys, Sparkle keys removed,
  usage descriptions rebranded.
- Model archive: base URL (may be empty) and the size/SHA-256 manifest from org/models.json
  (UndertoneModelArchiveManifest). An http:// archive host gets an ATS exception for that host only.
- *.lproj/Localizable.strings and InfoPlist.strings: every visible "VoiceInk" becomes
  "Undertone". Keys from the source catalog that contain "VoiceInk" are added to each table so
  the replacement also applies where the table would otherwise fall back to the raw key.
"""

import json
import os
import plistlib
import re
import shutil
import sys

APP_NAME = "Undertone"
BUNDLE_ID = "com.undertone.app"
EXECUTABLE = "Undertone"
ALLOWED_MODELS = {"parakeet-tdt-0.6b-v3", "parakeet-ultra", "cohere-transcribe"}
WORD = re.compile(r"(?<![A-Za-z])VoiceInk(?![A-Za-z])")

USAGE_DESCRIPTIONS = {
    "NSMicrophoneUsageDescription": "Undertone benötigt das Mikrofon, um Ihre Sprache lokal in Text umzuwandeln.",
    "NSAppleEventsUsageDescription": "Undertone nutzt diese Berechtigung nur zum Einfügen von Text.",
    "NSScreenCaptureUsageDescription": "Undertone liest keine Bildschirminhalte.",
}


def rebrand(value):
    if isinstance(value, str):
        return WORD.sub(APP_NAME, value)
    if isinstance(value, list):
        return [rebrand(v) for v in value]
    if isinstance(value, dict):
        return {k: rebrand(v) for k, v in value.items()}
    return value


def load_plist(path):
    raw = open(path, "rb").read()
    try:
        return plistlib.loads(raw)
    except Exception:
        # Xcode writes UTF-16 XML; plistlib's expat parser needs UTF-8.
        text = raw.decode("utf-16")
        text = text.replace('encoding="UTF-16"', 'encoding="UTF-8"')
        return plistlib.loads(text.encode("utf-8"))


def save_plist(path, data):
    with open(path, "wb") as handle:
        plistlib.dump(data, handle, fmt=plistlib.FMT_BINARY)


def load_manifest(manifest_path):
    if not manifest_path or not os.path.exists(manifest_path):
        return None
    data = json.load(open(manifest_path, encoding="utf-8"))
    files = data.get("files", {})
    manifest = {}
    for name, entry in files.items():
        sha = str(entry["sha256"]).lower()
        size = int(entry["size"])
        if not re.fullmatch(r"[0-9a-f]{64}", sha) or size <= 0:
            sys.exit(f"Ungültiger Eintrag für {name} in {manifest_path}")
        manifest[name] = {"size": size, "sha256": sha}
    return manifest


def patch_archive(info, archive_url, manifest):
    info.pop("UndertoneModelArchiveBaseURL", None)
    info.pop("UndertoneModelArchiveManifest", None)
    if archive_url:
        info["UndertoneModelArchiveBaseURL"] = archive_url
    if manifest:
        info["UndertoneModelArchiveManifest"] = manifest

    match = re.match(r"^http://([^/:]+)", archive_url or "")
    if match:
        host = match.group(1)
        is_ip = re.fullmatch(r"[0-9.]+", host) is not None
        if not is_ip and host != "localhost":
            ats = info.setdefault("NSAppTransportSecurity", {})
            domains = ats.setdefault("NSExceptionDomains", {})
            domains[host] = {"NSExceptionAllowsInsecureHTTPLoads": True}
            print(f"ATS-Ausnahme (HTTP) nur für {host} eingetragen")


REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_UPDATE_FEED_BASE = "https://github.com/AlverichSven/undertone-releases/releases/latest/download/"


def patch_version_and_updates(info):
    """Own Undertone version and Sparkle update settings (daily check, never install automatically).

    Environment (set by the Makefile):
      UNDERTONE_BUILD_NUMBER   CFBundleVersion (default: current time YYYYMMDDHHmm)
      UNDERTONE_UPDATE_FEED_BASE  base URL of appcast.xml and update archives
    """
    version = open(os.path.join(REPO_DIR, "org", "VERSION"), encoding="utf-8").read().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        sys.exit(f"org/VERSION ungültig: {version!r}")
    build = os.environ.get("UNDERTONE_BUILD_NUMBER", "").strip()
    if not build:
        import datetime
        build = datetime.datetime.now().strftime("%Y%m%d%H%M")
    if not build.isdigit():
        sys.exit(f"Build-Nummer ungültig: {build!r}")
    info["CFBundleShortVersionString"] = version
    info["CFBundleVersion"] = build

    feed_base = os.environ.get("UNDERTONE_UPDATE_FEED_BASE", "").strip() or DEFAULT_UPDATE_FEED_BASE
    if not feed_base.endswith("/"):
        feed_base += "/"
    if not re.match(r"^https?://[^/]+", feed_base):
        sys.exit(f"Ungültige Update-URL {feed_base!r}")
    public_key = open(os.path.join(REPO_DIR, "org", "sparkle_public_key.txt"), encoding="utf-8").read().strip()

    info["UndertoneUpdateFeedBaseURL"] = feed_base
    info["SUFeedURL"] = feed_base + "appcast.xml"
    info["SUPublicEDKey"] = public_key
    info["SUEnableAutomaticChecks"] = True
    info["SUScheduledCheckInterval"] = 86400
    info["SUAutomaticallyUpdate"] = False
    info["SUAllowsAutomaticUpdates"] = False
    info["SUEnableInstallerLauncherService"] = False  # not sandboxed
    print(f"Version {version} ({build}), Update-Feed {info['SUFeedURL']}")


def patch_info_plist(app, model, server, archive_url="", manifest=None):
    path = os.path.join(app, "Contents", "Info.plist")
    info = load_plist(path)
    patch_archive(info, archive_url, manifest)

    info["CFBundleIdentifier"] = BUNDLE_ID
    info["CFBundleName"] = APP_NAME
    info["CFBundleDisplayName"] = APP_NAME
    info["CFBundleExecutable"] = EXECUTABLE
    info["CFBundleDevelopmentRegion"] = "de"
    info["UndertoneTranscriptionModel"] = model
    info["UndertoneModelServerBaseURL"] = server
    info["NSHumanReadableCopyright"] = (
        "Basiert auf VoiceInk von Prakash Joshi Pax, GPLv3. Quellcode: https://github.com/AlverichSven/undertone"
    )
    patch_version_and_updates(info)
    for key, text in USAGE_DESCRIPTIONS.items():
        if key in info:
            info[key] = text

    # Own icon (org/Undertone.icns, rendered by scripts/org_make_icon.py) instead of the
    # VoiceInk icon from Assets.car: CFBundleIconName would win, so drop it.
    icon_src = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "org", "Undertone.icns")
    if os.path.exists(icon_src):
        shutil.copyfile(icon_src, os.path.join(app, "Contents", "Resources", "Undertone.icns"))
        info["CFBundleIconFile"] = "Undertone"
        info.pop("CFBundleIconName", None)
    else:
        print(f"warning: {icon_src} missing, keeping upstream icon", file=sys.stderr)

    # Smiley table for spoken smileys (OrgVoiceCommands).
    smileys_src = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "org", "smileys.json")
    if os.path.exists(smileys_src):
        shutil.copyfile(smileys_src, os.path.join(app, "Contents", "Resources", "smileys.json"))
    else:
        print(f"warning: {smileys_src} missing, spoken smileys disabled", file=sys.stderr)

    # „Öffnen mit > Undertone“ for the company dictionary (Undertone-Woerterbuch.json). Rank
    # "Alternate": Undertone never becomes the default app for JSON files.
    doc_types = [t for t in info.get("CFBundleDocumentTypes", []) if t.get("CFBundleTypeName") != "Undertone-Firmenwörterbuch"]
    doc_types.append({
        "CFBundleTypeName": "Undertone-Firmenwörterbuch",
        "CFBundleTypeRole": "Viewer",
        "LSHandlerRank": "Alternate",
        "LSItemContentTypes": ["public.json"],
    })
    info["CFBundleDocumentTypes"] = doc_types

    save_plist(path, info)


def load_overrides():
    """German (Sie-form) replacements for strings visible in Undertone (org/de-overrides.json)."""
    path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "org", "de-overrides.json")
    if not os.path.exists(path):
        return {}
    return json.load(open(path, encoding="utf-8"))


def patch_strings(app, catalog_path):
    catalog = json.load(open(catalog_path, encoding="utf-8"))
    branded_keys = [key for key in catalog.get("strings", {}) if WORD.search(key)]
    overrides = load_overrides()

    resources = os.path.join(app, "Contents", "Resources")
    changed = 0
    for entry in sorted(os.listdir(resources)):
        if not entry.endswith(".lproj"):
            continue
        lproj = os.path.join(resources, entry)
        language = entry[: -len(".lproj")]

        # Undertone is German only: with de as the single localization (and development region),
        # macOS shows German regardless of the system language.
        if language != "de":
            shutil.rmtree(lproj)
            continue

        table_path = os.path.join(lproj, "Localizable.strings")
        if os.path.exists(table_path):
            table = load_plist(table_path)
            for key in branded_keys:
                table.setdefault(key, key)
            table.update(overrides)
            table = {key: rebrand(value) for key, value in table.items()}
            save_plist(table_path, table)
            changed += 1

        dict_path = os.path.join(lproj, "Localizable.stringsdict")
        if os.path.exists(dict_path):
            save_plist(dict_path, rebrand(load_plist(dict_path)))

        info_strings_path = os.path.join(lproj, "InfoPlist.strings")
        if os.path.exists(info_strings_path):
            info_strings = rebrand(load_plist(info_strings_path))
            info_strings["CFBundleName"] = APP_NAME
            info_strings["CFBundleDisplayName"] = APP_NAME
            if language == "de":
                info_strings.update(USAGE_DESCRIPTIONS)
            else:
                for key in USAGE_DESCRIPTIONS:
                    info_strings.pop(key, None)
            save_plist(info_strings_path, info_strings)

    return changed


def main():
    if len(sys.argv) not in (5, 6, 7):
        sys.exit(__doc__)
    app, catalog, model, server = sys.argv[1:5]
    archive_url = (sys.argv[5] if len(sys.argv) > 5 else "").strip().rstrip("/")
    manifest_path = sys.argv[6] if len(sys.argv) > 6 else ""
    if archive_url and not re.match(r"^https?://[^/]+", archive_url):
        sys.exit(f"Ungültige Modell-Archiv-URL '{archive_url}'")
    manifest = load_manifest(manifest_path)
    if manifest is None:
        print("warning: org/models.json fehlt, Archiv-Modus kann keine Modelle laden", file=sys.stderr)
    if archive_url and not manifest:
        sys.exit("MODEL_ARCHIVE gesetzt, aber org/models.json fehlt oder ist leer (scripts/org_pack_models.sh)")
    if model not in ALLOWED_MODELS:
        sys.exit(f"Unbekanntes Modell '{model}'. Erlaubt: {', '.join(sorted(ALLOWED_MODELS))}")
    server = server.rstrip("/")
    if not re.match(r"^https?://[^/]+", server):
        sys.exit(f"Ungültige Modell-Server-URL '{server}'")

    old_exe = os.path.join(app, "Contents", "MacOS", "VoiceInk")
    new_exe = os.path.join(app, "Contents", "MacOS", EXECUTABLE)
    if os.path.exists(old_exe):
        os.rename(old_exe, new_exe)

    patch_info_plist(app, model, server, archive_url, manifest)
    tables = patch_strings(app, catalog)
    print(
        f"Bundle gepatcht: {BUNDLE_ID}, Modell {model}, Server {server}, "
        f"Archiv {archive_url or '(aus)'}, Manifest {len(manifest or {})} Dateien, {tables} Sprachtabellen"
    )


if __name__ == "__main__":
    main()
