# Undertone: Häufige Fragen

## Installation und Start

**macOS sagt, Undertone könne nicht geöffnet werden.**
Undertone ist mit einem eigenen Zertifikat signiert, aber nicht von Apple notarisiert. Einmalig:
Systemeinstellungen → Datenschutz & Sicherheit → ganz unten bei „Undertone“ auf **Dennoch öffnen**.

**Wohin gehört die App?**
In den Ordner **Programme** Ihres Benutzers (Finder → Gehe zu → Benutzerordner → Programme). Auf vielen Firmen-Macs
ist der System-Ordner `/Programme` gesperrt; Undertone läuft von beiden Orten gleich. Bitte nur **eine** Kopie
behalten, sonst startet macOS womöglich die alte.

**Ich sehe Undertone nicht im Dock.**
Absicht: Undertone sitzt oben in der **Menüleiste** (Wellen-Symbol) und startet automatisch bei der Anmeldung.
Beides lässt sich in den Einstellungen ändern („Dock-Symbol ausblenden“, „Beim Anmelden starten“).

**Was braucht mein Mac?**
Apple-Chip (M1 oder neuer), macOS 15 oder neuer, etwa 1,5 GB frei. Eine Windows-Fassung gibt es nicht.

## Diktieren

**Die Globus-/fn-Taste öffnet Emojis oder das Diktat von macOS.**
Systemeinstellungen → Tastatur → „Taste 🌐 drücken für“ → **Keine Aktion**.

**Kann ich eine andere Taste nehmen?**
Ja: Undertone → Einstellungen → Tastenkürzel. Neben „gedrückt halten“ gibt es auch Umschalten (einmal drücken
startet, nochmal drücken stoppt).

**Die Diktiertaste reagiert nicht.**
Systemeinstellungen → Datenschutz & Sicherheit → **Bedienungshilfen**: Undertone mit „–“ entfernen, mit „+“ neu
hinzufügen (Benutzerordner → Programme → Undertone), Undertone neu starten. Das kann nach einem Wechsel von einer
sehr alten Fassung einmalig nötig sein; bei normalen Updates bleiben die Freigaben erhalten.

**Warum kommt der Live-Text in kleinen Blöcken?**
Das Sprachmodell wertet das Gesprochene etwa einmal pro Sekunde aus und bestätigt ein Wort erst, wenn es mehrfach
gleich erkannt wurde. Undertone blendet neue Wörter einzeln ein, damit es flüssiger wirkt. Maßgeblich ist der Text,
der nach dem Loslassen eingefügt wird; er kann im Detail vom Live-Text abweichen.

**Im Live-Text stehen „neuer Absatz“ oder „Smiley LOL“ noch als Wörter.**
Richtig: Sprachbefehle und Smileys werden erst beim Einfügen ersetzt. Die Liste steht in der
[README](../README.md#sprachbefehle-und-smileys) und in den Einstellungen unter „Sprachbefehle“.

**Warum gibt es keinen Befehl für Punkt und Komma?**
Satzzeichen setzt das Modell selbst, und „Punkt“ oder „Komma“ kommen im normalen Reden vor („Der Punkt ist …“).

**Undertone lässt „äh“ und „ähm“ weg. Kann ich das abschalten?**
Ja: Einstellungen → Text → „Füllwörter entfernen“. Dabei fallen auch direkt doppelte Wörter weg („das das“ →
„das“); bewusste Dopplungen wie „so so“, „sehr sehr“ oder „Können Sie sie …“ bleiben stehen.

**Was ist das Firmenwörterbuch?**
Eine gemeinsame Datei `Undertone-Woerterbuch.json` mit Fachbegriffen, Projektschlüsseln und Ersetzungen. Undertone
sucht sie beim Start und einmal täglich in OneDrive/SharePoint und in Downloads; alternativ Einstellungen →
Firmenwörterbuch → „Firmenwörterbuch importieren …“ oder im Finder „Öffnen mit → Undertone“. Ihre eigenen
Wörterbuch-Einträge bleiben davon unberührt. Liegt die Datei nur in OneDrive (Wolkensymbol), im Finder per
Rechtsklick „Immer auf diesem Gerät behalten“ wählen.

**Ich spreche Englisch. Geht das?**
Ja: Einstellungen → Diktat → Sprache „Englisch“, oder schnell über das Menüleisten-Symbol → „Sprache“. Bei Englisch
sind die deutschen Sprachbefehle und Smileys aus. „Automatisch“ überlässt die Sprache dem Modell; Parakeet erkennt
Deutsch und Englisch ohnehin selbst, die Einstellung wirkt vor allem auf Sprachbefehle und Füllwörter.

**Ich habe das Diktat in das falsche Fenster eingefügt.**
Ins richtige Fenster klicken und **⌃⌥V** drücken (oder Menüleisten-Symbol → „Letztes Diktat erneut einfügen“).
Das Tastenkürzel lässt sich unter Einstellungen → Tastenkürzel ändern.

## Zwischenablage, Ton und Meetings

**Ist danach meine Zwischenablage weg?**
Nein. Undertone merkt sich vor dem Einfügen den kompletten Inhalt (Text, Bilder, Dateien), fügt das Diktat per
⌘V ein und legt den alten Inhalt nach **2 Sekunden** zurück. Kopieren Sie in diesen 2 Sekunden selbst etwas,
bleibt Ihr neuer Inhalt. Einstellung: „Zwischenablage nach dem Einfügen wiederherstellen“ (ab Werk an).

**Ich drücke direkt nach dem Diktat ⌘V und bekomme das Diktat statt meines alten Inhalts.**
Das passiert innerhalb der 2 Sekunden, bevor Undertone den alten Inhalt zurückgelegt hat. Kurz warten.

**Mein Bluetooth-Headset klingt im Teams-Meeting plötzlich schlecht, sobald ich diktiere.**
Das passiert, wenn das Headset-Mikrofon benutzt wird: macOS schaltet es dann in den Telefonmodus. Undertone nimmt
deshalb ab Werk das eingebaute Mikrofon des Mac, wenn sonst ein Bluetooth-Gerät aufnehmen würde (Einstellungen →
Mikrofon → „Bluetooth-Headset nicht zum Diktieren verwenden“). Teams und das Standardmikrofon des Systems bleiben
unverändert. Ohne eingebautes Mikrofon (z. B. Mac mini) nimmt Undertone weiter das Headset.

**Wird das Meeting im Headset stumm, während ich diktiere?**
Nein, andere Töne laufen weiter. Wer über die eingebauten Lautsprecher arbeitet, kann in den Einstellungen
„Andere Töne während des Diktierens stummschalten“ einschalten, damit das Meeting nicht mit ins Diktat rutscht.

## Updates und Datenschutz

**Wie kommen Updates?**
Undertone prüft einmal täglich, ob eine neue Version vorliegt, und zeigt dann einen Hinweis mit den Neuerungen.
Installiert wird erst nach Ihrem Klick. Sofort prüfen: Menüleisten-Symbol → „Nach Updates suchen …“.
Jedes Update ist signiert; Undertone installiert nur passend signierte Archive.

**Geht etwas ins Internet?**
Die Spracherkennung läuft vollständig auf dem Mac; Ton und Text verlassen ihn nicht. Es gibt kein Konto und keine
Cloud. Die einzige Verbindung ist die tägliche Update-Prüfung (abschaltbar in den Einstellungen unter „Updates“).

**Wo liegen meine Diktate?**
Nur lokal unter `~/Library/Application Support/com.undertone.app` (Verlauf und Statistik). Im Verlauf lassen sie
sich einzeln oder gesammelt löschen.

## Feedback

Fehler und Wünsche gern über [GitHub Issues](https://github.com/AlverichSven/undertone/issues).
