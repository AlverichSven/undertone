# Undertone: Organisations-Fassung von VoiceInk

Abgespeckte, voreingestellte Fassung von VoiceInk 2.27 (GPLv3) für die Verteilung an Kollegen.
Quellcode: `app/`, Branch `org-edition` (nicht committet). Alle Code-Änderungen stehen hinter
dem Compile-Flag `ORG_EDITION` bzw. `OrgEdition.isEnabled`; `make local` baut unverändert VoiceInk.

## Verteilung (eine Datei: GitHub Releases, optional zusätzlich ein gemeinsamer Ordner)

Entscheidung nach Feldtest (19.11.2026): App und Sprachmodell kommen **zusammen** in einer Datei. Grund:
Safari/Finder hatte das separate Modell-ZIP beim Kollegen automatisch entpackt, danach passte die Prüfsumme nicht
mehr. Der größere Download ist akzeptiert.

| Datei | Inhalt |
|---|---|
| `Undertone.zip` | `Undertone.app` (mit eingebautem Modell unter `Contents/Resources/Models/`) + `LIESMICH.txt` |

Fester Dateiname ohne Version. Für einen gemeinsamen Ordner (z. B. SharePoint/OneDrive, lokal synchronisiert):
`UNDERTONE_PUBLISH_DIR=<ordner> scripts/org_publish_folder.sh`.
Entpackt der Mac die ZIP automatisch, funktioniert der entstandene Ordner genauso (Signatur bleibt gültig).
Frühere separate Modellpakete (`Undertone-Sprachmodell-*.zip`) werden nicht mehr gebraucht.

**Modell im Bundle:** `make org` kopiert `MODEL` und (bei Parakeet) `silero-vad` aus
`~/Library/Application Support/FluidAudio/Models` nach `Undertone.app/Contents/Resources/Models/<ordner>/`
(Skript `scripts/org_bundle_model.py`; schreibt `Models/bundle.json` mit Modellname und einer Inhalts-ID je Ordner)
und signiert danach. Die Signatur versiegelt die Modelldateien: Eine geänderte Datei lässt
`codesign --verify --deep --strict` scheitern („a sealed resource is missing or invalid“). Cohere würde als
`Models/cohere-transcribe/<gguf>` gebündelt (nicht getestet, GGUF lokal nicht vorhanden).

**Beim Start (vor dem Onboarding, ohne Netz, `OrgBundledModels.swift`):**
- Trägt der Zielordner (`FluidAudio/Models/<ordner>`, Cohere: `com.undertone.app/TranscribeCpp/cohere-transcribe`)
  die Marker-Datei `.undertone-bundle-id` mit derselben Inhalts-ID: nichts tun.
- Ordner ohne Marker (z. B. von VoiceInk, Hugging Face oder einem alten Paket): einmal Inhalt vergleichen; gleich →
  nur Marker schreiben, sonst ersetzen.
- Ersetzen: aus dem Bundle in einen Staging-Ordner daneben klonen (APFS), Kopie gegen die Inhalts-ID prüfen, Marker
  schreiben, alten Ordner beiseite und neuen per Umbenennen an seinen Platz legen.
- Inhalts-ID: SHA-256 über `"<relativer Pfad>\0<Größe>\0<SHA-256>\n"` aller Dateien, nach Pfad sortiert, versteckte
  Dateien ignoriert. Python (`org_bundle_model.py`) und Swift rechnen identisch (im Test bestätigt).

**Onboarding:** Im Normalfall nur Mikrofon und Bedienungshilfen. Der Modellschritt erscheint nur als Rückfall
(App ohne Modell gebaut, Kopieren gescheitert, Modell in der App passt nicht zum konfigurierten) und nennt die
Ursache. Dann bleiben die bisherigen Wege: „Modelldatei auswählen …“ (Paket-ZIP, geprüft gegen `org/models.json`),
Drag & Drop, „Öffnen mit“, „In Downloads und OneDrive suchen“ (automatische Suche nur mit
`defaults write com.undertone.app modelPackageAutoSearch -bool true`, sonst aus, damit macOS nicht nach
Ordnerzugriff fragt) und „Stattdessen aus dem Internet laden (Hugging Face)“ bzw. Archiv-URL.

**App-Updates:** Neue `Undertone.app` drüberkopieren. Gleiches Modell → nichts wird kopiert (Marker), kein
Onboarding. Anderes Modell in der App → wird beim Start eingerichtet. Einstellungen, Wörterbuch, Verlauf bleiben.

## Bauen

```sh
cd app
make org-release MODEL=parakeet-ultra     # Hauptweg: dist/release/Undertone.zip (App mit Modell + LIESMICH)
make org MODEL=parakeet-ultra             # nur dist/Undertone.app (mit Modell)
make org ORG_BUNDLE_MODEL=0               # App ohne Modell (nur Rückfallwege)
make org-models MODEL=parakeet-ultra      # optionales Modellpaket nach dist/models (Rückfall/Zusatzmodell)
make org MODEL_SERVER=https://models.example.intern
make org MODEL_ARCHIVE=https://nexus.example/repository/raw-undertone/models   # Archiv-Modus fest einbauen
make org-release ORG_SIGN_IDENTITY=-                                          # ad-hoc statt Zertifikat
scripts/org_publish_folder.sh <ordner>                                        # Undertone.zip in einen gemeinsamen Ordner
```

- Standard für `MODEL` ist `parakeet-tdt-0.6b-v3`; der aktuelle Release ist `MODEL=parakeet-ultra`. Das Modell
  muss lokal unter `~/Library/Application Support/FluidAudio/Models` vollständig vorhanden sein, sonst bricht der
  Bau ab.
- `make org-release` = `org` + `dist/release/Undertone.zip` (`ditto -c -k`, App + `LIESMICH.txt` aus
  `app/org/LIESMICH.txt` mit eingesetzter Version). Alte Modellpakete in `dist/release` werden entfernt.
- `scripts/org_publish_folder.sh` kopiert nur `Undertone.zip` (Option `--with-model` wird ignoriert) und
  vergleicht danach den Hash.
- Ergebnis: `dist/Undertone.app` (Bundle-ID `com.undertone.app`, ad-hoc signiert, `LOCAL_BUILD` +
  `ORG_EDITION`). DerivedData in `VoiceInk/.org-build` (in `.gitignore`). Nichts landet in `~/Downloads`.
- Swift-Pakete werden, falls vorhanden, aus `.local-build/SourcePackages` übernommen.
- Nach dem Xcode-Bau (Skript `scripts/org_patch_bundle.py`): XPC `VoiceInkRefineXPC.xpc` entfernt,
  Executable in `Undertone` umbenannt, Info.plist (Bundle-ID, Namen, `UndertoneTranscriptionModel`,
  `UndertoneModelServerBaseURL`, Sparkle-Schlüssel entfernt) und alle `*.lproj`-Texte „VoiceInk“ → „Undertone“,
  danach neu ad-hoc signiert (Entitlements und Hardened Runtime bleiben erhalten).
- `org/models.json` (aus `scripts/org_pack_models.sh`) wird als Prüfsummen-Manifest
  `UndertoneModelArchiveManifest` in die Info.plist übernommen (signiert). Fehlt die Datei, warnt der Bau;
  mit `MODEL_ARCHIVE` bricht er ab.
- Größen (19.11.2026, Ultra): `Undertone.app` 683 MB, `Undertone.zip` 579.704.532 Bytes
  (SHA-256 `18f72ad07f2b75262a952f2a44e39c095e80edc6ac2372f0aa05d9fc0e16d89c`). Ohne Modell: 79 MB.
- Kollegen müssen die App beim ersten Start über „Datenschutz & Sicherheit > Dennoch öffnen“ freigeben
  (keine Notarisierung).

## Signatur und Freigaben (TCC)

Ad-hoc signiert ändert sich die Signatur bei jedem Bau; macOS verliert dann die Freigaben für Bedienungshilfen
und Mikrofon. Mit einem festen, selbst erstellten Zertifikat bleibt die „Designated Requirement“ gleich
(`identifier "com.undertone.app" and certificate leaf = H"5b6708f8…"`) und die Freigaben überleben Updates.
Sparkle prüft außerdem, dass ein Update dieselbe Signatur hat; ad-hoc wäre dafür ungeeignet.

- Zertifikat: **„Undertone Signing“** im Anmelde-Schlüsselbund, SHA-1 `5B6708F86D6852497C1486FA0DC88521A1992561`
  (wird als `CSSMERR_TP_NOT_TRUSTED` gelistet, Signieren funktioniert trotzdem).
- Standard für `make org`/`org-release`: `ORG_SIGN_IDENTITY ?= Undertone Signing`; ad-hoc nur mit
  `ORG_SIGN_IDENTITY=-`.
- Signiert wird von innen nach außen ohne `--deep` (`scripts/org_sign_app.sh`): Sparkles XPCs, `Updater.app`,
  `Autoupdate`, die Frameworks, zuletzt die App. Entitlements, Flags und Hardened Runtime jedes Teils bleiben
  (`--preserve-metadata`), verschachtelte Teile behalten ihre Kennung.
- Beim ersten `codesign` mit dem Zertifikat fragt macOS nach dem Zugriff auf den privaten Schlüssel: dort
  „Immer erlauben“ wählen, sonst bleibt der Bau hängen.
- **Sichern:** Zertifikat mit privatem Schlüssel als `.p12` exportieren (Schlüsselbundverwaltung > Rechtsklick >
  Exportieren) und sicher ablegen. Ohne diesen Schlüssel braucht jedes künftige Update wieder neue Freigaben,
  und Sparkle-Updates scheitern an der Signaturprüfung.

Neues Zertifikat anlegen (falls je nötig): Schlüsselbundverwaltung > Zertifikatsassistent > „Zertifikat
erstellen …“, Identitätstyp „Selbst-signierte Root“, Zertifikattyp **„Code-Signatur“**.

Prüfen: `codesign -dr - dist/Undertone.app` muss bei zwei Bauten dieselbe Zeile zeigen. Praxis: Version A
installieren, Freigaben erteilen, Version B drüberkopieren oder per Update installieren: Undertone bleibt unter
Bedienungshilfen aktiv, Einfügen funktioniert ohne Rückfrage. Die Gatekeeper-Rückfrage beim allerersten Start
bleibt (kein Apple-Zertifikat).

## Updates (Sparkle, GitHub Releases)

- Undertone prüft **einmal täglich** (`SUScheduledCheckInterval` 86400) und installiert **nie automatisch**
  (`SUAutomaticallyUpdate` und `SUAllowsAutomaticUpdates` = false; Sparkle lädt erst nach dem Klick auf
  „Update installieren“). Nutzer sehen „Neue Version verfügbar“ mit den Versionshinweisen.
- Von Hand: Menüleiste > „Nach Updates suchen …“, App-Menü, oder Einstellungen > Updates („Jetzt prüfen“,
  automatische Prüfung an/aus, installierte Version).
- Quelle: `UPDATE_FEED_BASE` (Standard GitHub Releases `https://github.com/AlverichSven/undertone-releases/releases/latest/download/`) →
  `SUFeedURL = {UPDATE_FEED_BASE}appcast.xml`. Überschreiben per Defaults/MDM `updateFeedBaseURL`
  (Sparkle-Delegate `feedURLString(for:)`).
- Versionen: `CFBundleShortVersionString` aus `org/VERSION` (1.0.0), `CFBundleVersion` = Bau-Zeitpunkt
  `YYYYMMDDHHmm` (`ORG_BUILD_NUMBER`). Sparkle vergleicht die Build-Nummer.
- EdDSA-Schlüssel: privat im Anmelde-Schlüsselbund (Sparkle, Konto **`undertone`**), öffentlich in
  `org/sparkle_public_key.txt` und Info.plist `SUPublicEDKey`. **Sichern:** `generate_keys --account undertone -x
  <datei>` exportiert den privaten Schlüssel; die Datei sicher verwahren und danach löschen (nie ins Repo).
  Ohne ihn lassen sich keine Updates mehr signieren; alle Macs bräuchten eine Neuinstallation von Hand.

### Update veröffentlichen

```sh
cd app
$EDITOR org/RELEASE_NOTES.md                    # Neuerungen (Markdown: Überschrift, Liste)
$EDITOR org/VERSION                             # z. B. 1.0.1
make org-publish MODEL=parakeet-ultra           # baut, signiert, Archiv + appcast.xml, Upload, Prüfung
make org-publish MODEL=parakeet-ultra PUBLISH_ARGS=--no-upload   # nur lokal (dist/updates)
```

`scripts/org_publish_update.sh`: `dist/updates/Undertone-<version>-<build>.zip` (nur die App,
`ditto -c -k --keepParent`), EdDSA-Signatur mit `sign_update`, Gegenprüfung, `appcast.xml` (Version, Build,
Datum, Länge, Signatur, `minimumSystemVersion` 15.0, Versionshinweise plus fester Hinweis zur Bedienungshilfe),
Upload per `curl --fail --upload-file` erst des Archivs, dann der `appcast.xml`, danach GET und Hash-Vergleich.
Auth optional: `CURL_AUTH="-u user:pass"`. Die Erstinstallation läuft über das Release-ZIP
(`make org-release`, `scripts/org_publish_folder.sh`).

**Standard:** GitHub-Releases in `AlverichSven/undertone-releases` (`make org-publish`, braucht `gh` mit Anmeldung). **Alternative eigener Server:** Raw-Repository, anonym lesbar, Deployment-Policy **„Allow redeploy“**
(`appcast.xml` wird bei jedem Release überschrieben). Vor dem ersten Release prüfen, ob anonymer Upload erlaubt ist
oder Zugangsdaten nötig sind (`CURL_AUTH`).

## Zentrale Konfiguration (Admin / MDM)

Beide Werte werden bei jedem Start gelesen. Reihenfolge: UserDefaults bzw. MDM-Profil (Domain
`com.undertone.app`) → Info.plist des Bundles → eingebauter Standard.

| Zweck | UserDefaults/MDM | Info.plist (per `make org`) | Standard |
|---|---|---|---|
| Sprachmodell | `transcriptionModel` | `UndertoneTranscriptionModel` (`MODEL=`) | `parakeet-tdt-0.6b-v3` |
| Modell-Server (HF-Weg) | `modelServerBaseURL` | `UndertoneModelServerBaseURL` (`MODEL_SERVER=`) | `https://huggingface.co` |
| Modell-Archiv (Raw-Server) | `modelArchiveBaseURL` | `UndertoneModelArchiveBaseURL` (`MODEL_ARCHIVE=`) | leer = HF-Weg |

```sh
defaults write com.undertone.app transcriptionModel parakeet-ultra
defaults write com.undertone.app modelServerBaseURL https://models.example.intern
```

- Erlaubte Modelle: `parakeet-tdt-0.6b-v3` (Parakeet V3, 494 MB, Live-Text), `parakeet-ultra`
  (640 MB, Live-Text), `cohere-transcribe` (1,56 GB, kein Live-Text, App arbeitet dann still ohne).
  Ungültige Werte → Parakeet V3. Nutzer sehen keine Modellauswahl.
- Normalerweise legt der Bau (`MODEL`) das Modell fest und bringt es mit. Setzt der Admin per MDM ein anderes
  Modell, das nicht auf dem Mac liegt, zeigt die App beim nächsten Start den Rückfall-Modellschritt
  (Datei auswählen, Internet-Download).
- Modell-Server-URL muss mit `http(s)://` beginnen, sonst gilt der nächste Wert der Reihenfolge.

## Archiv-Modus (optional, Nexus Raw o. ä.)

Nicht mehr der Hauptweg (kein Nexus vorhanden), bleibt aber eingebaut. Ist `modelArchiveBaseURL` gesetzt, lädt die App keine Modelle über Hugging Face, sondern einzelne Dateien
per einfachem `GET {base}/<datei>`:

| Datei | Wird entpackt/abgelegt nach | Wann |
|---|---|---|
| `parakeet-tdt-0.6b-v3.zip` | `~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3` | Modell Parakeet V3 |
| `parakeet-ultra.zip` | `…/FluidAudio/Models/parakeet-ultra` | Modell Parakeet Ultra |
| `silero-vad.zip` | `…/FluidAudio/Models/silero-vad` | bei Parakeet, falls VAD fehlt |
| `cohere-transcribe-03-2026-Q4_K_M.gguf` | `~/Library/Application Support/com.undertone.app/TranscribeCpp/cohere-transcribe/` (+ `.sha256`-Datei) | Modell Cohere |

- Jede ZIP hat den Modellordner als Wurzel (genau die Struktur, die FluidAudio erwartet).
- **Integrität:** Größe und SHA-256 jeder Datei stehen im signierten Bundle (`org/models.json` → Info.plist),
  nie vom Server. Download in einen Staging-Ordner neben dem Ziel, Prüfung, erst dann Entpacken und Umbenennen
  ins Ziel (gleiches Volume). Abweichung → Datei verworfen, Meldung „Modelldatei beschädigt oder verändert …“
  im Einrichtungsbildschirm. Fehlt ein Eintrag im Manifest → Fehler, kein Download. Für Cohere muss der Eintrag
  zusätzlich zur fest eingebauten Cohere-Prüfsumme passen.
- Im Archiv-Modus zeigt FluidAudios eigene Registry auf die Archiv-URL; ein versehentlicher HF-Download
  scheitert dort, statt Hugging Face zu kontaktieren.
- **HTTP vs. HTTPS:** HTTPS empfohlen. Für eine `http://`-Archiv-URL mit Hostnamen trägt `make org MODEL_ARCHIVE=…`
  eine ATS-Ausnahme nur für diesen Host ein. Wird die URL nur per MDM/`defaults` gesetzt, muss sie HTTPS sein
  (oder eine IP-Adresse/localhost; ATS gilt dafür nicht).

### Skripte

```sh
scripts/org_pack_models.sh [--only <modell>] [--force]   # Pakete + Einzel-ZIPs nach ../dist/models, org/models.json
scripts/org_upload_models.sh <url>                        # nur Archiv-Modus: Upload + Prüfung per GET
scripts/org_publish_folder.sh <ordner>                    # Undertone.zip in einen gemeinsamen Ordner kopieren
```

`org_pack_models.sh` lädt nichts herunter (Quelle: lokale Modellordner; Cohere-GGUF nur, wenn lokal vorhanden,
derzeit nicht). Vorhandene Dateien, die noch zu `org/models.json` passen, bleiben unverändert; neue Einträge werden
ins Manifest gemischt. `--force` nur zusammen mit einem neuen App-Release, denn verteilte Apps akzeptieren nur die
Bytes, mit denen sie gebaut wurden. Stand 19.11.2026 (`dist/models`):

| Datei | Bytes | SHA-256 |
|---|---|---|
| `Undertone-Sprachmodell-parakeet-tdt-0.6b-v3.zip` | 466.653.849 | `1d087d41d879f5677015197315d2d7a091788439a3f44114b83909e80608716e` |
| `Undertone-Sprachmodell-parakeet-ultra.zip` | 554.689.430 | `0af268fb185fd10a8e709a11c4e24df949c82eff80197fc9025233b3dc287343` |
| `parakeet-tdt-0.6b-v3.zip` (Archiv) | 465.815.777 | `298ae5125b598d66645f171cbab2d56e12610092ff8bcf033da8903ca3f41dc1` |
| `parakeet-ultra.zip` (Archiv) | 553.851.358 | `164ef4f612044f4f36415801220512de93d9e578c31fa9fd31185cd7a1416419` |
| `silero-vad.zip` (Archiv) | 838.094 | `d88e3dac4ab630d50b358401b6ae91f93b68b705ddb90b6862bcc21e017c921c` |

## Abläufe

### App-Release

1. `org/VERSION` und `org/RELEASE_NOTES.md` pflegen.
2. `cd app && make org-publish MODEL=parakeet-ultra` (signiert mit „Undertone Signing“, lädt Update hoch).
3. Für Neuinstallationen zusätzlich `scripts/org_publish_folder.sh <ordner>` (`dist/release/Undertone.zip`).
4. Bestehende Installationen bekommen den Hinweis „Neue Version verfügbar“ innerhalb eines Tages.

### Modellwechsel

1. Neues Modell einmal lokal laden (z. B. Undertone über „Stattdessen aus dem Internet laden“ oder VoiceInk), sodass
   der Ordner unter `~/Library/Application Support/FluidAudio/Models` vollständig ist (Cohere: GGUF unter
   `…/TranscribeCpp/cohere-transcribe/`).
2. `make org-release MODEL=<modell>` und verteilen. Beim Start richtet jede App ihr gebündeltes Modell ein.
3. Ein MDM-Wert `transcriptionModel`, der nicht zum gebündelten Modell passt, führt zum Rückfall-Modellschritt
   (Paketdatei bzw. Internet). Besser das Modell über `MODEL` im Bau festlegen.
4. Ein neues Modell (nicht eines der drei) braucht zusätzlich Code-Änderungen in `OrgEdition.swift`.

### Später: zusätzliches Modell nachladen oder wechseln (Wunsch, noch nicht gebaut)

Nutzer sollen ein weiteres Modell nachladen bzw. wechseln können, wenn der Admin eins zusätzlich bereitstellt.
Dafür sind die vorhandenen Wege absichtlich im Code geblieben und nur im Normalfall ausgeblendet:
Paket-Installation aus Datei (`OrgModelArchiveInstaller.installPackage`, Prüfung gegen `org/models.json`,
Pakete aus `scripts/org_pack_models.sh` bzw. `make org-models`), Archiv-Download (`modelArchiveBaseURL`),
Hugging-Face-Download und die Paket-Suche. Fehlen würden eine Auswahl in den Einstellungen und eine Liste
„vom Admin freigegebener Modelle“ (z. B. per MDM), die das Modell im Modus „Diktat“ statt `transcriptionModel`
steuert.

## Oberfläche (Org-Bau)

- Hauptfenster dunkel (Superwhisper-Vorbild): Sidebar mit zwei Gruppen (Übersicht, Verlauf, Audio transkribieren,
  Wörterbuch / Einstellungen, Mikrofon), Seitentitel 24 pt semibold, rechts oben Mikrofon-Pille (Klick → Mikrofon).
- Startseite „Übersicht“ (`OrgHomeView.swift`): Statistik (Ø Wörter pro Minute, Wörter, genutzte Apps, gesparte
  Zeit; Zeitraum Heute / 7 Tage / 30 Tage / Gesamt) aus `SessionMetric`; „Letzte Aufnahmen“ (5), Klick kopiert
  den Text, „Alle anzeigen“ → Verlauf. Die App je Diktat merkt sich `OrgAppUsageStore`
  (`~/Library/Application Support/com.undertone.app/org-app-usage.json`), erst ab diesem Stand; ältere Aufnahmen
  zählen nicht zu „genutzte Apps“ und zeigen kein App-Symbol.
- Schrift: Überschriften höchstens semibold, Text regular, ausgewählter Sidebar-Eintrag medium.
- Live-Text: neue Wörter werden einzeln eingeblendet (35 bis 60 ms je Wort, höchstens ein Block Rückstand,
  Korrekturen sofort, beim Stopp sofort der volle Text). Nur Anzeige, der eingefügte Text ist unverändert.
- Nur Deutsch: Der Bau entfernt alle anderen `*.lproj` und setzt `CFBundleDevelopmentRegion` auf `de`;
  `VoiceInk/org/de-overrides.json` ersetzt sichtbare Texte in Sie-Form (übrige VoiceInk-Texte duzen noch).

## Voreinstellungen ab dem ersten Start

- Ein einziger Modus „Diktat“: Modell laut Konfiguration, Sprache Deutsch (`de`), Live-Text an
  (wenn das Modell es kann), Ergebnis wird ins aktive Fenster eingefügt, keine KI, kein Kontext.
- Aufnahme: Push-to-talk auf der fn-/Globus-Taste (in den Einstellungen änderbar, auch Modus
  Toggle/Hybrid). Abbrechen: zweimal Esc.
- Töne bei Start/Stopp, Systemton-Stummschaltung, Zwischenablage wiederherstellen: wie VoiceInk-Standard.
- Startansicht: Verlauf.

## Was entfernt bzw. abgeschaltet ist

- Pro/Lizenz/Trial/Kaufen (Sidebar „VoiceInk Pro“, Banner, Onboarding-Schritt), Dashboard,
  GitHub-Stern-Hinweis.
- Modi (Sidebar, Moduswahl im Rekorder, in „Transcribe Audio“, im Verlauf und im Menüleistenmenü).
- AI Models (Sidebar ganz entfernt), alle Cloud- und Custom-Anbieter; Registry enthält nur die drei Modelle,
  importierte Whisper-Modelle werden ignoriert.
- KI-Nachbearbeitung (Enhancement, Cloud-LLMs, Ollama, OpenRouter, VoiceInkRefine/MLX): zur Laufzeit fest
  aus, Prompt-Auswahl im Verlauf weg, XPC nicht im Bundle. Assistent-/Antwortmodus fest aus
  (Ausgabe immer „Einfügen“), Custom Commands aus.
- Dictionary-AutoLearn (beobachtet Tippen, nutzt optional LLM): fest aus, UI ausgeblendet.
- Kontext: keine Website-Erkennung per AppleScript, kein Bildschirm-Lesen, keine Bildschirmaufnahme-Freigabe.
- Ankündigungen. (Sparkle ist seit 1.0.0 wieder aktiv, siehe „Updates“.)
- Einstellungen: nur Tastenkürzel, Sprache, Anzeige des Modells, Live-Text-Anzeige, Zwischenablage,
  Autostart, Dock-Symbol, Lizenzhinweis. Kein Backup/Export, keine Diagnose, keine Updates.
- Onboarding: ein Bildschirm mit Mikrofon, Bedienungshilfen und automatischem Modell-Download.

Sidebar: Verlauf, Transcribe Audio, Dictionary, Mikrofon (Audio), Einstellungen.

Daten liegen getrennt von VoiceInk unter `~/Library/Application Support/com.undertone.app`
(Verlauf, Wörterbuch, Cohere-Modell). Parakeet-Modelle und VAD liegen wie bei VoiceInk unter
`~/Library/Application Support/FluidAudio/Models` (gemeinsam genutzt, falls beide Apps installiert sind).

## Spiegel-Server für Modelle

Der Server muss die Hugging-Face-Pfade nachbilden. FluidAudio (Parakeet, VAD) braucht zusätzlich die
HF-API zum Auflisten der Dateien:

- `GET {base}/api/models/{repo}/tree/{revision}` und `.../tree/{revision}/{pfad}` → JSON-Liste wie bei
  Hugging Face (`type` = `file`/`directory`, `path`, `size`, bei großen Dateien `lfs.oid`/`lfs.size`).
- `GET {base}/{repo}/resolve/{revision}/{pfad}` → Datei (Range-Anfragen empfohlen, Downloads werden fortgesetzt).

Ein HF-kompatibler Proxy (z. B. Artifactory/Nexus „Hugging Face Remote Repository“) erfüllt das; ein
reiner Dateiserver reicht nur für Cohere.

| Repo | Revision | Benötigt für | Dateien |
|---|---|---|---|
| `FluidInference/parakeet-tdt-0.6b-v3-coreml` | `main` | Modell Parakeet V3 | `Preprocessor.mlmodelc/`, `Encoder.mlmodelc/`, `Decoder.mlmodelc/`, `JointDecisionv3.mlmodelc/` (je komplett: `coremldata.bin`, `model.mil`, `weights/weight.bin`, `analytics/coremldata.bin`, ggf. `metadata.json`), `parakeet_vocab.json`, Metadaten im Wurzelverzeichnis (`*.json`, `*.model`, `*.bin`, z. B. `config.json`, `parakeet_v3_vocab.json`) |
| `FluidInference/parakeet-ultra-coreml` | `main` | Modell Parakeet Ultra | wie oben (gleiche Dateinamen) |
| `FluidInference/silero-vad-coreml` | `main` | beide Parakeet-Modelle (Sprachpausen-Erkennung) | `silero-vad-unified-256ms-v6.2.1.mlmodelc/` (komplett), `config.json` |
| `handy-computer/cohere-transcribe-03-2026-gguf` | `dfa4adebb64f3076b7b6b90b721275cc069cb421` | Modell Cohere | `cohere-transcribe-03-2026-Q4_K_M.gguf` (1.558.162.944 Bytes, SHA-256 `0ea56826d8bd5d74b7143a4a04e022dc1bb75452cfae49d98b6acb0c1d16a1fb`), nur `resolve`, keine API |

Am einfachsten die drei FluidInference-Repos vollständig auf `main` spiegeln. Für ein festes Modell
genügen dessen Repo plus (bei Parakeet) `silero-vad-coreml`.

## Sprachbefehle und Smileys

- Umsetzung: `VoiceInk/Infrastructure/TextProcessing/OrgVoiceCommands.swift`, aufgerufen in
  `TranscriptionPipeline` nach den Wörterbuch-Ersetzungen, nur auf den eingefügten Endtext (Live-Text zeigt
  die gesprochenen Wörter).
- Befehle: neue Zeile, neuer Absatz, Doppelpunkt, Semikolon, Ausrufezeichen, Fragezeichen, Anführungszeichen
  (auf/zu/wechselnd), Klammer auf/zu, Bindestrich, Schrägstrich. Bewusst nicht: Punkt, Komma (setzt das Modell,
  kommen im normalen Reden vor). Leerzeichen und Großschreibung nach Absatz/!/? werden bereinigt.
- Smileys: Startwort „Smiley“/„Smilie“/„Emoji“, dann längste passende Wortfolge. Tabelle `org/smileys.json`
  (`kurz`: ca. 70 Kurznamen, haben Vorrang; `alle`: 4.017 Einträge aus der mitgelieferten Liste), wird vom Bundle-Patch nach
  `Contents/Resources/smileys.json` kopiert.
- Schalter in den Einstellungen (Karte „Sprachbefehle“), Defaults-Schlüssel `orgVoiceCommandsEnabled`,
  `orgSmileysEnabled` (Standard an).
- Nicht bei Sprache Englisch (siehe „Sprache“).

## Textverarbeitung, Firmenwörterbuch, Mikrofon, Sprache (ab 1.1.0)

### Reihenfolge der Textverarbeitung (eingefügter Endtext, `TranscriptionPipeline`)

1. `TranscriptionOutputFilter` (VoiceInk): Klammer-Halluzinationen, **Füllgeräusche** (VoiceInks Liste plus
   deutsche Laute aus `OrgFillerWords`; VoiceInks Aufräumen von Kommas, Leerzeichen und Großschreibung).
2. Trigger-Wörter (VoiceInk, im Org-Bau ohne Wirkung).
3. **Doppelte Wörter** (`OrgFillerWords.removeRepeatedWords`): vor allem Folgenden, damit Wörterbuch und Befehle
   den bereinigten Text sehen.
4. **Projektschlüssel** (`OrgCompanyTerms.applyProjectKeys`): vor der Vokabular-Korrektur und allen Ersetzungen,
   damit weder die phonetische Korrektur noch eine Ersetzung (z. B. „AB“ → „A&B“) einen buchstabierten Schlüssel
   zerlegt, bevor er erkannt ist.
5. Vokabular-Korrektur (VoiceInk `PhoneticVocabularyMatcher`): eigene Wörter plus Wörter des Firmenwörterbuchs.
6. Absatzformatierung (VoiceInk).
7. **Ersetzungen des Firmenwörterbuchs**, danach die eigenen Ersetzungen des Nutzers (VoiceInk): Die eigenen Regeln
   haben das letzte Wort.
8. Sprachbefehle und Smileys (`OrgVoiceCommands`), nicht bei Englisch.

### Füllwörter (`OrgFillerWords.swift`)

- Schalter „Füllwörter entfernen“, Defaults `orgFillerWordsEnabled` (Standard an). Aus: es wird gar nichts entfernt,
  auch nicht VoiceInks englische Liste.
- Deutsch/Automatisch: „äh“, „ähm“, „öh“, „öhm“, „hm“, „hmm“, „mhm“ plus VoiceInks Liste **ohne „um“** (VoiceInk
  hätte sonst „um 10 Uhr“ zu „10 Uhr“ gemacht). Englisch: VoiceInks Liste plus „uh“, „um“, „er“, „erm“.
- Doppelte Wörter: direkt aufeinander, nur durch Leerzeichen getrennt, Groß/Klein egal, nur Buchstabenwörter (Zahlen
  nie). Bleiben stehen: bewusste Dopplungen („so so“, „ja ja“, „nein nein“, „na na“, „sehr sehr“, „ganz ganz“,
  „viel viel“, „immer immer“, „bitte bitte“, „gut gut“ u. a.), „Sie sie“ (Anrede plus Pronomen) und Artikel nach
  Komma („…, die die Zeitung liest“). Englisch: u. a. „that that“, „had had“, „very very“.
- Bekannte Grenze: Bei „Ich habe, äh, das …“ bleibt das erste Komma stehen (VoiceInks Logik behält ein Komma vor
  dem Füllwort, weil es oft echt ist: „Ich weiß nicht, öhm, ob …“).

### Firmenwörterbuch (`OrgCompanyDictionary.swift`, `OrgCompanyTerms.swift`)

Dateiformat (alle Felder optional, Beispiel mit erfundenen Werten):

```json
{
  "beschreibung": "Firmenwörterbuch für Undertone",
  "version": "2026-01-15",
  "woerter": ["Beispielprodukt", "Musterkunde"],
  "jiraSchluessel": ["ABCDEF", "XYZW"],
  "ersetzungen": [{ "von": "A und B", "nach": "A&B" }]
}
```

- Quellen: automatisch beim Start und alle 24 Stunden die **neueste** Datei `Undertone-Woerterbuch.json` (auch
  „… (1).json“) unter `~/Library/CloudStorage/<Anbieter>/` bis Tiefe 4 und unter `~/Downloads` bis Tiefe 2.
  OneDrive-Platzhalter (`SF_DATALESS` bzw. `ubiquitousItemDownloadingStatus == notDownloaded`) werden übersprungen
  und in den Einstellungen mit Hinweis genannt. Geladen wird nur, wenn die Datei neuer ist als die geladene.
  Von Hand: „Firmenwörterbuch importieren …“, „Jetzt suchen“, Finder „Öffnen mit → Undertone“ oder Ablegen auf das
  Dock-Symbol (Info.plist-Dokumenttyp `public.json`, Rang „Alternate“; ein Doppelklick öffnet JSON weiter im
  Standardprogramm, weil macOS Zuordnungen nicht nach Dateinamen kennt).
- Ablage: Kopie in `~/Library/Application Support/com.undertone.app/Firmenwoerterbuch.json`, getrennt von den eigenen
  Einträgen (SwiftData). Ein neues Firmenwörterbuch ersetzt das alte vollständig. „Entfernen“ löscht die Kopie;
  die automatische Suche lädt danach erst wieder eine neuere Datei.
- Defaults: `orgCompanyDictionaryEnabled` (Standard an), `orgCompanyDictionaryAutoSearch` (Standard an; aus = nur
  von Hand), intern `orgCompanyDictionarySource`, `orgCompanyDictionarySourceDate`, `orgCompanyDictionaryRemovedDate`.
- `woerter`: gehen in VoiceInks Vokabular (`CustomVocabularyService.loadSavedVocabulary`, hinter den eigenen Wörtern,
  die bei Kollisionen gewinnen). Bei Parakeet wirkt das Vokabular nur über die phonetische Nachkorrektur
  (`RecordingVocabulary.correctTranscription` → `PhoneticVocabularyMatcher`); das Modell selbst bekommt keine Hinweise.
  Begriffe mit Sonderzeichen oder Ziffern (z. B. „A&B“) überspringt der Matcher.
- `jiraSchluessel`: Folge von Wortstücken, nur durch Leerzeichen, Punkte oder Bindestriche getrennt, die ohne
  Trenner case-insensitiv genau einem Schlüssel entspricht, wird zum Schlüssel in Großbuchstaben („AB CD EF“,
  „a.b.cd-ef“, „AbCdEf“ → `ABCDEF`). Längster Treffer zuerst, nur Schlüssel ab 4 Zeichen, nur ganze Wörter. Folgt
  eine Zahl („… 12“, „…-12“, „… Bindestrich 12“, „1.234“), entsteht das Ticket `ABCDEF-12` bzw. `ABCDEF-1234`.
  Schutz für normale Sprache: Enthält die Folge ein normales Wort (ab 4 Buchstaben, mit Kleinbuchstaben, etwa
  „IT Security“ oder „E-Board“), wird sie nur mit folgender Ticketnummer umgewandelt. Projektschlüssel gehen nicht
  ins Vokabular (sie würden normale Wörter anziehen).
- `ersetzungen`: ganze Wörter bzw. Wortfolgen, case-insensitiv, längste zuerst (wie VoiceInks Ersetzungen;
  Leerzeichen in `von` passen auf beliebig viele Leerzeichen). Schlüssel bleiben unberührt, weil „AB“ als ganzes
  Wort nicht in `ABCDEF` passt.

### Bluetooth-Schutz (`AudioDeviceManager+OrgBluetooth.swift`)

- Defaults `orgBluetoothProtectionEnabled` (Standard an), Schalter unter Einstellungen → Mikrofon.
- In `resolveCurrentRecordingDevice` (zentrale Gerätewahl für Aufnahme, Vorbereitung und Geräteanzeige): Ist das
  gewählte Gerät laut `kAudioDevicePropertyTransportType` Bluetooth oder Bluetooth LE, nimmt Undertone das
  eingebaute Mikrofon (`isInternalMicrophone`, sonst ein anderes Gerät mit Transport „Built-in“, z. B. Klinke),
  sofern es nutzbar ist (Deckel offen). Gilt in allen Eingabemodi, auch bei ausdrücklich gewähltem Bluetooth-Gerät.
  Kein eingebautes Mikrofon (Mac mini) oder Deckel zu: Bluetooth-Gerät wie bisher.
- Das Standard-Eingabegerät des Systems wird nie geändert; Undertone setzt das Gerät nur an der eigenen Audio-Unit
  (`kAudioOutputUnitProperty_CurrentDevice`).

### Letztes Diktat erneut einfügen

- VoiceInk hat die Funktion schon („Paste Last Transcription“, `ShortcutAction.pasteLastTranscription`, ohne
  Standard-Tastenkürzel). Der Org-Bau setzt beim Start **⌃⌥V**, sofern der Nutzer das Kürzel nicht selbst gesetzt
  oder gelöscht hat und es nicht belegt ist (`ShortcutStore.seedShortcut`, Defaults `Shortcut_pasteLastTranscription`).
  Änderbar unter Einstellungen → Tastenkürzel; Menüleiste „Letztes Diktat erneut einfügen“.
- Eingefügt wird der fertige Text (nach Füllwörtern, Wörterbuch und Befehlen) des letzten **abgeschlossenen**
  Diktats (abgebrochene und fehlgeschlagene werden übersprungen), über `CursorPaster` mit Wiederherstellung der
  Zwischenablage.

### Sprache

- Auswahl Deutsch (`de`, Standard), Englisch (`en`), Automatisch (`auto`, nur wenn das Modell es anbietet; Cohere
  nicht). Gespeichert im Modus „Diktat“ (`ModeConfig.selectedLanguage`), umschaltbar in den Einstellungen und in der
  Menüleiste („Sprache: …“).
- Wirkung bei Parakeet V3/Ultra: FluidAudio nutzt die Sprache nur als **Schrift-Filter** (`TokenLanguageFilter`:
  Latein/Kyrillisch/Griechisch). Deutsch und Englisch dekodieren identisch, das Modell erkennt die Sprache selbst.
  „Automatisch“ schaltet den Filter ab (theoretisch können dann kyrillische Zeichen auftauchen). Bei Cohere wird
  die Sprache dem Modell wirklich vorgegeben.
- In Undertone steuert die Sprache vor allem die Nachbearbeitung: Englisch → keine deutschen Sprachbefehle und
  Smileys, englische Füllwörter („uh“, „um“). Deutsch und Automatisch → deutsche Regeln.
- Ein eigenes Tastenkürzel „Auf Englisch diktieren“ gibt es bewusst nicht: Bei Parakeet würde es die Erkennung nicht
  ändern, nur die Nachbearbeitung, und VoiceInks zweites Aufnahmekürzel ist an Modi gebunden, die der Org-Bau auf
  einen festen Modus reduziert.

## Netzwerk

Verbindungen der Org-Fassung: die tägliche Update-Prüfung (`appcast.xml`) und ggf. das Update-Archiv vom
internen Nexus, sonst nur optionale Modell-Downloads über die Basis-URL (FluidAudio und Cohere). Bei
`https://huggingface.co` leitet Hugging Face große Dateien auf eigene CDN-Hosts um (`*.hf.co`,
`cas-bridge.xethub.hf.co`); mit eigenem Spiegel entfällt das. Links in der Oberfläche (z. B. Quellcode-Link)
öffnen nur den Browser.

## Bekannte offene Punkte

- Modell im Bundle getestet (19.11.2026, Ultra): Signatur gültig; Manipulation an einer Kopie (`config.json`
  geändert) → „a sealed resource is missing or invalid“; Erstinstallation simuliert (`parakeet-ultra` weg) →
  Ordner nach ca. 5 s aus dem Bundle da, `diff -rq` gegen das Backup gleich bis auf `.undertone-bundle-id`, keine
  Netzverbindung, Onboarding-Flag blieb 1; vorhandenes `silero-vad` per Inhaltsvergleich erkannt (nur Marker
  ergänzt); zweiter Start: mtime und Inode unverändert; aus entpacktem `Undertone.zip` gestartet: Signatur gültig,
  läuft. Diktieren und Oberfläche nicht von mir geprüft. Der Rückfall-Modellschritt (App ohne Modell) ist nicht
  getestet.
- Paket-Installation getestet (19.11.2026, ohne Klick über die Auto-Suche in `~/Downloads/undertone-test/`):
  manipuliertes Paket (gleiche Größe, ein Byte geändert) → Staging angelegt und nach ca. 1 s wieder entfernt,
  nichts installiert; echtes Paket → `parakeet-ultra` installiert, `diff -rq` gegen den alten Ordner identisch,
  vorhandenes `silero-vad` unangetastet. App-Update-Test: neu gebaute App mit vorhandenem V3 gestartet,
  Onboarding-Flag blieb 1, keine Netzverbindung, Modellordner unverändert. Die Meldungstexte auf dem Bildschirm
  habe ich nicht gesehen. Nicht getestet: Platzhalter-Erkennung (kein OneDrive-Platzhalter vorhanden),
  Auswahl-Dialog, Drag & Drop, „Öffnen mit“, Cohere-Paket, Signatur mit eigenem Zertifikat.
- Archiv-Modus getestet (19.11.2026, lokaler `python3 -m http.server`): Parakeet Ultra aus `parakeet-ultra.zip`
  installiert, `diff -rq` gegen den vorherigen Ordner identisch; manipulierte ZIP (gleiche Größe, ein Byte
  geändert) → nichts installiert, Staging aufgeräumt; Cohere ohne Manifest-Eintrag → keine Anfrage an den
  Server. Die Meldungstexte im Einrichtungsbildschirm habe ich nicht gesehen (kein Bildschirmzugriff).
  VAD-Download aus `silero-vad.zip` nicht end-to-end getestet (gleicher Codepfad), Cohere-Archiv nicht getestet.
- Nach dem Entpacken lädt die App das Modell nicht testweise (anders als der HF-Weg, der es einmal
  kompiliert); die erste Aufnahme kann daher etwas länger dauern.
- Diktieren und die Oberfläche sind nicht von mir getestet. Geprüft (19.11.2026): Bau, Signatur,
  Start aus `dist/` (Prozess lief ohne Absturz, keine offenen Netzverbindungen), angelegter Modus „Diktat“
  (Parakeet V3, `de`, ohne KI) und fn-Taste als Aufnahmekürzel in den Defaults.
- Die Globus-Taste ist bei macOS standardmäßig mit Emoji/Diktat belegt; ggf. in den
  Systemeinstellungen auf „Keine Aktion“ stellen (Hinweis steht in den Einstellungen).
- Bestehende deutsche Texte von VoiceInk duzen, neue Texte der Org-Fassung siezen.
- Seiten Dictionary, Mikrofon, Transcribe Audio, Verlauf sind unverändert aus VoiceInk übernommen
  (bis auf ausgeblendete Modus-/KI-Elemente); dort können vereinzelt englische Texte oder
  „Learn more“-Links auf tryvoiceink.com auftauchen.
- App-Intents/Kurzbefehle tragen intern noch VoiceInk-Bezüge.
- Modell-Server ohne HF-API führt im HF-Weg bei Parakeet zu einem Download-Fehler; dafür den Archiv-Modus nehmen.
- Rückfall-Modellschritt: Der Internet-Weg (Hugging Face) startet nur per Klick, im Archiv-Modus automatisch.
  Die Paket-Suche in `~/Downloads` und `~/Library/CloudStorage` ist standardmäßig aus (macOS würde nach
  Ordnerzugriff fragen); nur per Klick oder mit `modelPackageAutoSearch`.
- Erster Start nach Umstieg: Vorhandene Modellordner ohne Marker werden einmal komplett gehasht (Ultra ca. 600 MB,
  auf dem Test-Mac wenige Sekunden); bis dahin startet die App etwas verzögert.
- Die App ist mit Modell 683 MB groß; jedes Update lädt das Modell erneut mit.
