#!/usr/bin/env python3
"""Copies the configured model into the Undertone app bundle (organisation build).

Usage: org_bundle_model.py <Undertone.app> <model>

Result: Contents/Resources/Models/<folder>/ for the model (plus silero-vad/ for Parakeet, or
cohere-transcribe/<gguf> for Cohere) and Contents/Resources/Models/bundle.json with a content id
per folder. The app copies these folders to ~/Library/Application Support on launch
(OrgBundledModels.swift). Sources are the locally installed model folders; nothing is downloaded.
The bundle must be signed afterwards so the signature seals the model files.

Content id (must match OrgBundledModels.contentIdentifier): SHA-256 over
"<relative path>\\0<size>\\0<sha256>\\n" for every regular file, sorted by path (UTF-8),
hidden files and folders ignored.
"""

import hashlib
import json
import os
import shutil
import sys

HOME = os.path.expanduser("~")
FLUID_ROOT = os.path.join(HOME, "Library", "Application Support", "FluidAudio", "Models")
GGUF_NAME = "cohere-transcribe-03-2026-Q4_K_M.gguf"
PARAKEET = {"parakeet-tdt-0.6b-v3", "parakeet-ultra"}


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def content_id(folder):
    entries = []
    for root, dirs, files in os.walk(folder):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in files:
            if name.startswith("."):
                continue
            path = os.path.join(root, name)
            if not os.path.isfile(path) or os.path.islink(path):
                continue
            entries.append((os.path.relpath(path, folder), path))
    entries.sort(key=lambda entry: entry[0].encode("utf-8"))
    outer = hashlib.sha256()
    for relative, path in entries:
        outer.update(f"{relative}\0{os.path.getsize(path)}\0{file_sha256(path)}\n".encode("utf-8"))
    return outer.hexdigest()


def copy_folder(source, target):
    if not os.path.isdir(source):
        sys.exit(f"Modellordner fehlt: {source} (Modell erst lokal laden)")
    for root, _, files in os.walk(source):
        if any(name.endswith(".partial") for name in files):
            sys.exit(f"{source} enthält unvollständige Downloads (*.partial)")
    shutil.copytree(source, target, ignore=lambda _dir, names: [n for n in names if n.startswith(".")])


def find_gguf():
    for folder in ("com.undertone.app", "com.prakashjoshipax.VoiceInk"):
        path = os.path.join(HOME, "Library", "Application Support", folder, "TranscribeCpp",
                            "cohere-transcribe", GGUF_NAME)
        if os.path.isfile(path):
            return path
    sys.exit(f"{GGUF_NAME} lokal nicht gefunden (Cohere erst einmal laden)")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    app, model = sys.argv[1:]
    models_dir = os.path.join(app, "Contents", "Resources", "Models")
    if os.path.exists(models_dir):
        shutil.rmtree(models_dir)
    os.makedirs(models_dir)

    if model in PARAKEET:
        folders = [model, "silero-vad"]
        for folder in folders:
            copy_folder(os.path.join(FLUID_ROOT, folder), os.path.join(models_dir, folder))
    elif model == "cohere-transcribe":
        folders = ["cohere-transcribe"]
        os.makedirs(os.path.join(models_dir, "cohere-transcribe"))
        shutil.copyfile(find_gguf(), os.path.join(models_dir, "cohere-transcribe", GGUF_NAME))
    else:
        sys.exit(f"Unbekanntes Modell {model}")

    manifest = {"model": model, "folders": {}}
    for folder in folders:
        manifest["folders"][folder] = content_id(os.path.join(models_dir, folder))
        print(f"Gebündelt: {folder}  {manifest['folders'][folder]}")
    with open(os.path.join(models_dir, "bundle.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")


if __name__ == "__main__":
    main()
