#!/bin/bash
# Packs the locally installed models for Undertone (nothing is downloaded).
#
#   scripts/org_pack_models.sh [--only <model>] [--force] [out-dir]
#
#   --only <model>  only this model (parakeet-tdt-0.6b-v3 | parakeet-ultra | cohere-transcribe)
#   --force         rebuild files even if an existing file still matches org/models.json
#   out-dir         default ../dist/models
#
# Produces in out-dir:
#   Undertone-Sprachmodell-<model>.zip   model package for distribution as a file:
#                                        roots <model>/ and silero-vad/ (Parakeet) or
#                                        cohere-transcribe/<gguf> (Cohere)
#   <folder>.zip, <gguf>                 single files for the optional archive mode (URL)
# and merges size + sha256 of every file into org/models.json (embedded into the app by make org).
#
# Existing files that still match their org/models.json entry are kept unchanged, because released
# apps only accept the exact bytes they were built with. Use --force only together with a new app release.
#
# Sources:
#   ~/Library/Application Support/FluidAudio/Models/{parakeet-tdt-0.6b-v3,parakeet-ultra,silero-vad}
#   cohere-transcribe-03-2026-Q4_K_M.gguf from an Application Support TranscribeCpp folder, if present
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec /usr/bin/python3 -I - "$REPO_DIR" "$@" <<'PY'
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

repo_dir, args = sys.argv[1], sys.argv[2:]
only, force, out_dir = None, False, os.path.join(repo_dir, "..", "dist", "models")
while args:
    arg = args.pop(0)
    if arg == "--only":
        only = args.pop(0)
    elif arg == "--force":
        force = True
    else:
        out_dir = arg

MODELS = ["parakeet-tdt-0.6b-v3", "parakeet-ultra", "cohere-transcribe"]
if only and only not in MODELS:
    sys.exit(f"Unbekanntes Modell {only}. Erlaubt: {', '.join(MODELS)}")

home = os.path.expanduser("~")
models_root = os.path.join(home, "Library", "Application Support", "FluidAudio", "Models")
manifest_path = os.path.join(repo_dir, "org", "models.json")
gguf_name = "cohere-transcribe-03-2026-Q4_K_M.gguf"
package_prefix = "Undertone-Sprachmodell-"
excludes = ["*.DS_Store", "*__MACOSX*", "*/.undertone-staging-*", "*.partial"]

os.makedirs(out_dir, exist_ok=True)
out_dir = os.path.abspath(out_dir)
os.makedirs(os.path.dirname(manifest_path), exist_ok=True)
manifest = {"files": {}}
if os.path.exists(manifest_path):
    manifest = json.load(open(manifest_path, encoding="utf-8"))
    manifest.setdefault("files", {})


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def still_valid(name):
    path = os.path.join(out_dir, name)
    entry = manifest["files"].get(name)
    if force or not entry or not os.path.exists(path):
        return False
    return os.path.getsize(path) == entry["size"] and sha256(path) == entry["sha256"]


def check_complete(folder):
    for root, _, files in os.walk(folder):
        if any(f.endswith(".partial") for f in files):
            sys.exit(f"Fehler: {folder} enthält unvollständige Downloads (*.partial)")


def zip_from(base_dir, roots, target):
    tmp = target + ".tmp"
    if os.path.exists(tmp):
        os.remove(tmp)
    cmd = ["/usr/bin/zip", "-r", "-X", "-q", tmp] + roots
    for pattern in excludes:
        cmd += ["-x", pattern]
    subprocess.run(cmd, cwd=base_dir, check=True)
    os.replace(tmp, target)


def record(name):
    path = os.path.join(out_dir, name)
    manifest["files"][name] = {"size": os.path.getsize(path), "sha256": sha256(path)}


def find_gguf():
    for folder in ("com.undertone.app", "com.prakashjoshipax.VoiceInk"):
        path = os.path.join(home, "Library", "Application Support", folder, "TranscribeCpp",
                            "cohere-transcribe", gguf_name)
        if os.path.isfile(path):
            return path
    return None


built, kept, skipped = [], [], []
selected = [only] if only else MODELS

for model in selected:
    if model == "cohere-transcribe":
        gguf = find_gguf()
        if not gguf:
            skipped.append(f"{model}: GGUF lokal nicht vorhanden")
            continue
        single = gguf_name
        if still_valid(single):
            kept.append(single)
        else:
            shutil.copyfile(gguf, os.path.join(out_dir, single))
            record(single)
            built.append(single)
        package = f"{package_prefix}{model}.zip"
        if still_valid(package):
            kept.append(package)
        else:
            with tempfile.TemporaryDirectory() as tmp:
                os.makedirs(os.path.join(tmp, "cohere-transcribe"))
                staged = os.path.join(tmp, "cohere-transcribe", gguf_name)
                try:
                    os.link(gguf, staged)  # same volume: no 1.5 GB copy
                except OSError:
                    shutil.copyfile(gguf, staged)
                zip_from(tmp, ["cohere-transcribe"], os.path.join(out_dir, package))
            record(package)
            built.append(package)
        continue

    model_dir = os.path.join(models_root, model)
    vad_dir = os.path.join(models_root, "silero-vad")
    if not os.path.isdir(model_dir) or not os.path.isdir(vad_dir):
        skipped.append(f"{model}: Ordner {model_dir} oder silero-vad fehlt")
        continue
    check_complete(model_dir)
    check_complete(vad_dir)

    for name, roots in (
        (f"{package_prefix}{model}.zip", [model, "silero-vad"]),
        (f"{model}.zip", [model]),
        ("silero-vad.zip", ["silero-vad"]),
    ):
        if name in kept or name in built:
            continue
        if still_valid(name):
            kept.append(name)
            continue
        print(f"Packe {name} ...")
        zip_from(models_root, roots, os.path.join(out_dir, name))
        record(name)
        built.append(name)

with open(manifest_path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2, sort_keys=True)
    handle.write("\n")

for name in built:
    entry = manifest["files"][name]
    print(f"neu      {name}\t{entry['size']}\t{entry['sha256']}")
for name in kept:
    entry = manifest["files"][name]
    print(f"unverändert {name}\t{entry['size']}\t{entry['sha256']}")
for note in skipped:
    print(f"übersprungen: {note}")
print(f"Manifest: {manifest_path}")
PY
