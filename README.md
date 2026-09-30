# Therapie – Autismus-Therapiebegleiter für iPhone

Eine private, lokal-first iOS-App zur Organisation von Therapieterminen, Wochenaufgaben, Notizen, Fotos, Sprachaufnahmen, Rückblicken und Erinnerungen.

## Schwerpunkte
- SwiftUI + Liquid Glass (iOS 26+)
- AlarmKit für prominente Therapie- und Aufgabenalarme
- EventKit für iPhone-Kalender-Synchronisierung
- Fotos, Dokumente und Sprachaufnahmen lokal in der App
- Optionales Backup in einen selbst gewählten iCloud-Drive-Ordner
- Wochenaufgaben, Energie-Check-ins, Timeline und Kalender
- Standort-Metadaten nur nach ausdrücklicher Berechtigung
- Sicherheitsabfrage vor vollständigem Löschen aller Daten

## Datenschutz
Therapiedaten bleiben standardmäßig auf dem Gerät. Kalender-, Standort- und Alarmzugriff werden nur nach Systemfreigabe verwendet. iCloud-Drive-Backups werden nur in einen vom Benutzer ausgewählten Ordner geschrieben.

## Build
GitHub Actions erzeugt eine unsignierte IPA, die anschließend mit einem eigenen Sideloading-/Signing-Werkzeug signiert/installiert werden kann.

## Update 3003.0.0 – Dateien, lesbare ZIPs und Wochenenergie

- **Profil → Export & Import:** Wahl zwischen passwortgeschützter `.therapiebackup` und **unverschlüsseltem Klartext-ZIP**. Beide enthalten den kompletten Datenstand und portable Darstellungseinstellungen. Fotos, Audios und Dokumente bleiben einzeln wählbar; ausgeschlossene Dateien erhalten bearbeitbare Metadaten. Originale Klartext-ZIPs aus der App können nach vollständiger Prüfung und Bestätigung auch wieder importiert werden.
- ZIP64 im standardisierten Store-Format, ohne Kompression und ohne zusätzliche Bibliothek: gestreamte Dateien, CRC32 und SHA-256 für Anhänge; lesbare `LIES-MICH.txt`, `UEBERSICHT.md` und kategorisierte Einzeldateien in `Eintraege/`. JSON erhält alle IDs, Beziehungen und Daten für die Wiederherstellung. ZIP-Namen, doppelte Einträge, Größen, Prüfsummen und Manifest werden vor Installation geprüft. Andere ZIP-Formate, neu gepackte oder bearbeitete ZIPs werden nicht als App-Sicherung importiert; zum Lesen kann jedes übliche ZIP-Programm verwendet werden.
- **Dateien → Auf meinem iPhone → Therapie → Therapiedaten:** laufende JSON-Daten, Fotos, Dokumente, Audios und automatisch aktualisierte lesbare Einträge. Daten werden verlustfrei aus Application Support verschoben. Bei belegtem Ziel oder Fehler bleiben vorhandene Dateien erhalten. Du kannst den Ordner kopieren, ohne dass die App laufen muss. Er gehört trotzdem zur App und wird bei Deinstallation gelöscht: vorher an einen anderen Speicherort kopieren. Dateien der laufenden App nicht manuell verändern.
- **Aufgaben:** Zieltermin, Fortschritt, kleinster Schritt, Unterstützung und individuelle tägliche oder ausgewählte Erinnerungstage. Mitteilungen wiederholen sich auch bei geschlossener App bis zur Erledigung; Abschluss/Löschen entfernt ausstehende und angezeigte Hinweise. Titel auf Sperrbildschirm standardmäßig verborgen, Ton konfigurierbar. Aktionen: Erledigt, eine Stunde später, Weiterarbeiten; in der App zusätzlich Morgen. Verschieben ändert die regelmäßige Uhrzeit und ergänzt gegebenenfalls den gewählten Tag, wie in der Oberfläche erklärt.
- Benachrichtigungen benötigen iOS-Freigabe. Zukünftige Kalenderwochen-Aufgaben werden beim Öffnen in dieser Woche aktiviert. Maximal 40 Aufgaben-Hinweise lassen Platz für Sitzungen und Wochen-Impulse; tägliche Wiederholung braucht nur einen Hinweis pro Aufgabe. Kapazitäts- und Berechtigungsprobleme werden sichtbar gemeldet. Allgemeine ältere Aufgaben-Alarme werden beim Upgrade durch individuelle Mitteilungen ersetzt. Therapie-Termine bleiben AlarmKit-Alarme; neue Alarme werden zuerst eingerichtet, bevor bisherige gelöscht werden.
- **Wochenenergie:** sieben abgeschlossene Kalendertage bis zum Therapietag, große Akku-Auswahl, einzelne Geber/Nehmer mit Stärke, Kategorie und Notiz, Vorschläge, Übernahme vorhandener Akku-Punkte, Balkendiagramm, Fragen für die Therapeutin und nächster Schritt. Bearbeiten/Löschen in Stimmung → Wochen und im Archiv; zählt zur Wochen-Serie. Optionaler Hinweis folgt Therapietag/Uhrzeit mit einstellbarem Vorlauf.
- Therapieplanung: Ort und Vorbereitung werden im synchronisierten Kalendereintrag mitgeführt. Schema 6 erhält die Daten aus Schemas 1–5; neue Erinnerungsfelder und Wochenenergien werden automatisch in beiden Sicherungsarten mitgenommen.
- CI: bestehende Modellprüfungen, verschlüsselte Vollsicherung mit allen neuen Feldern, Documents-Migration, lesbare Einzeldateien, ZIP-Rundlauf und Manipulationen, unabhängige Python-ZIP64/CRC-Prüfung, Aufgabenplanung und Wochenenergie. Der Geräte-Build prüft zusätzlich die Files-Freigaben im tatsächlichen Bundle. Native Mitteilungsaktionen, Dateien-App-Anzeige und AlarmKit benötigen einen Test auf einem echten iPhone.

## Update 3002.0.0 – verschlüsselte, portable Vollsicherung

- Profil → **Export & Import öffnen**: Eine `.therapiebackup`-Datei mit frei gewähltem Passwort erstellen und über den nativen Dateien-Dialog in iCloud Drive, auf dem iPhone oder bei einem eingebundenen Dateien-Anbieter speichern.
- Standardmäßig sind alle `AppData`-Einträge sowie Darstellung, ruhige Oberfläche, Haptik und Konfetti enthalten. Bilder, Audios und Dokumente lassen sich einzeln ausschließen. Ihre Metadaten bleiben als bearbeitbare Einträge erhalten; ausgelassene Dateien sind klar gekennzeichnet.
- Import auch direkt im Einrichtungsbildschirm nach Neuinstallation. Erst entschlüsseln und vollständig prüfen, dann Datum, Version und Umfang ansehen und das **Ersetzen** ausdrücklich bestätigen. Es wird nicht zusammengeführt. Falsches Passwort oder beschädigte Datei verändern keine aktuellen Daten.
- Container v1: AES-256-GCM, PBKDF2-HMAC-SHA256 mit 600.000 Iterationen und zufälligem 16-Byte-Salt; 256-KiB-Blöcke, authentifizierte Header/Sequenzen, SHA-256 je Datei, Abschlussmarkierung und EOF-Prüfung. Namen, Eintragsdaten, Einstellungen und Anhänge sind verschlüsselt. Passwörter werden nie gespeichert; ohne Passwort gibt es keine Wiederherstellung.
- Anhänge werden gestreamt, auch beim Speichern über einen URL-basierten Dateien-Dialog. Eintrags- und Manifestdaten haben eine ausdrücklich geprüfte Grenze von 64 MiB, maximal 100.000 Anhänge. Die Bilder/Audios/Dokumente zählen nicht zu dieser 64-MiB-Grenze. Import braucht genug freien Platz für die entschlüsselte Sicherung; die vorherigen lokalen Daten bleiben als geschützte Wiederherstellungskopie erhalten.
- Private Zwischendateien und lokale Daten erhalten iOS-Dateischutz. Prüfung und Verschlüsselung laufen abseits der Oberfläche. Währenddessen das iPhone entsperrt lassen. Staging, geprüfte Pfade, Rücknahme bei Installationsfehlern und Wiederaufnahme nach einem unterbrochenen Verzeichnistausch schützen die bestehenden Daten.
- Berechtigungen, Dateien-Bookmarks und OS-Verknüpfungen werden nicht auf andere Geräte übertragen. Kalender/Alarme und automatische Ordnersicherung nach dem Import bei Bedarf erneut verbinden. Der ältere automatische Ordner-Backup ist weiterhin verfügbar und ausdrücklich **nicht passwortverschlüsselt**.
- Schema 5 übernimmt Schemas 1–4; die ursprüngliche Datendatei wird bei Migration als `therapy-data.pre-3002.json` erhalten. Container- und Datenschema sind getrennt versioniert. `AGENTS.md` und CI schreiben Backup-Prüfungen für kommende persistente Funktionen vor.
- Timer- und Archivaktionen passen sich schmalen Ansichten und großer Schrift besser an. Import ohne Bilder erzeugt verständliche Platzhalter statt nicht funktionierender Öffnen-Schaltflächen.
- CI prüft Datenmigration sowie vollständige Sicherung, alle drei Dateitypen einschließlich mehrerer Blöcke und leerer Dateien, Passwort, Manipulation, abgeschnittene/umgeordnete Daten, Pfade, Auslassungen, Darstellungseinstellungen und Unterbrechungswiederherstellung. Die tatsächlichen Dateien-Anbieter und Geräte-Haptik benötigen weiterhin einen Test auf einem echten iPhone.

## Update 3001.0.0 – Therapieraum und Stundenbegleiter

- Verschachtelte Themenordner mit frei wählbaren Symbolen, Umbenennen und Verschieben. Beim Löschen eines Ordners bleiben Inhalte erhalten und rücken eine Ebene nach oben.
- Eigene Themen in zwölf Bereichen, mit Priorität, aktuellem Fokus, hilfreichen Dingen, Hindernissen und nächstem Gesprächsschritt. Status: geplant, in Bearbeitung, pausiert, abgeschlossen; abgeschlossene Themen lassen sich wieder aufnehmen.
- Therapieziele mit selbst eingeschätztem Fortschritt, persönlicher Bedeutung, beobachtbaren Fortschritten, kleinem nächsten Schritt, Unterstützung und optionalem Wunschtermin.
- Wichtige angeheftete Notizen und ein eigener Bereich für Beiträge der Therapeutin/des Therapeuten. Verfasser werden als ich, Therapeutin/Therapeut oder gemeinsam gekennzeichnet; es ist ein lokaler Bereich auf demselben Handy, kein separates Benutzerkonto.
- Materialsammlung mit elf Kategorien, Beschreibung, Quelle, Tags, Thema und Ordner. Fotos, Dokumente und Audio lassen sich über die Systemvorschau öffnen.
- Alle gespeicherten Eintragsarten lassen sich in der Timeline öffnen, bearbeiten und mit Bestätigung löschen. Vorherige Energie-Checks und Rückblicke bleiben bearbeitbar. Verknüpfungen werden bei Löschvorgängen bereinigt.
- Feine abschaltbare Haptik beim Erstellen und Löschen. Kurzes Konfetti bei abgeschlossenen Aufgaben und Zielen; bei reduzierter Bewegung nur eine ruhige Bestätigung. Aufgaben können wieder geöffnet werden.
- Wiederverwendbare, duplizierbare Stundenpläne mit bis zu zwölf Phasen und frei anpassbaren Minuten, Namen, Farben und Reihenfolge. Die Beispielvorlage enthält 5 Minuten Kaffee, 5 Minuten AirTag, 10 Minuten Wochenrückblick und 40 Minuten Therapie.
- Persistenter Timer mit farbigen Zeitsegmenten und Zeiger, Pause/Fortsetzen, aktuellem und nächstem Abschnitt, Sitzungsverlauf und schnellen sitzungsbezogenen Notizen. Die Zeit basiert auf Zeitstempeln, nicht auf einem Hintergrund-Countdown.
- Echte eingebettete WidgetKit-Erweiterung für Live-Aktivitäten auf Sperrbildschirm und Dynamic Island. Restzeit und Gesamtfortschritt werden von iOS zeitgesteuert dargestellt; die ersten vier Phasen erscheinen als zeitgesteuerte Balken auf dem Sperrbildschirm. Standardmäßig neutrale Abschnittsnamen, keine Notizen im Widget. Die aktuelle Phasenbezeichnung wird in der App angezeigt.
- Optionale End- und Phasenmitteilungen. Beim Pausieren werden geplante Mitteilungen entfernt, beim Fortsetzen zeitlich verschoben.
- Migration von älteren Versionen auf Schema 4, mit zusätzlicher Datendatei `therapy-data.pre-3001.json`. Bundle-Kennung bleibt erhalten.

CI prüft die Timergrenzen, Pause/Fortsetzen, Wiederherstellung nach App-Beendigung, verschachtelte Ordner, Löschverknüpfungen und Migration. Die Bundle-Prüfung kontrolliert zusätzlich die tatsächliche Einbettung und Version der Live-Aktivitäts-Erweiterung. Systemfreigaben, Haptik, Sperrbildschirm und Dynamic Island benötigen ergänzend einen Test auf einem echten iPhone.

## Update 3000.0.0

- Eigener Stimmungsbereich mit kurzen und ausführlichen Check-ins: Stimmung, Akku, mehrere Gefühle, freiwilliger Stress, Reizbelastung, Schlaf, kleine Erfolge und nächster Bedarf.
- Beliebig viele einzelne Akku-Geber und -Nehmer, jeweils mit Datum, Kategorie, Wirkung und Notiz. Auch die letzte Woche lässt sich nachtragen.
- Interaktive Swift-Charts-Diagramme für 7, 30, 90 Tage, die letzte Kalenderwoche oder alle Einträge. Tagesmittelwerte, echte Lücken, Akku-Auswertung nach Kategorien und zugängliche Wertelisten.
- Wochen-Serie mit mindestens einem Eintrag pro Woche, längste Serie und freiwilliges Ziel von 1 bis 7 Check-in-Tagen. Eine noch offene aktuelle Woche beendet die bisherige Serie nicht.
- Wochenrückblicke mit hilfreichen und schwierigen Momenten, Erfolg, nächstem Schritt und Therapiefrage; vorhandene Akku-Punkte direkt im Rückblick ansehen.
- Bearbeiten, Favoriten, Suche, Richtungsfilter, Einbindung in Kalender und Timeline sowie CSV-Export für den gewählten Zeitraum.
- Freiwillige wöchentliche Erinnerung mit anpassbarem Tag und Uhrzeit, ohne sensible Inhalte auf dem Sperrbildschirm.
- Einmalige, automatische Einrichtung der benötigten Systemfreigaben beim Öffnen; nach Ablehnung bleibt der lokale Check-in nutzbar. Kein pauschaler Fotomediathek-Zugriff.
- Bestätigung vor dem Löschen von Aufgaben, Notizen, Medien, Check-ins, Akku-Punkten und Wochenrückblicken; Schutz vor dem Verwerfen ungespeicherter Änderungen.
- Bestehende Daten bleiben beim Upgrade erhalten. Vor der ersten neuen Speicherung wird `therapy-data.pre-3000.json` angelegt. Unlesbare oder neuere Daten werden vor automatischem Überschreiben geschützt.

CI prüft Migration, Jahres- und Sommerzeitgrenzen der Wochen-Serie, Diagramm-Aggregation und CSV-Sicherheit mit einem eigenständigen Swift-Testprogramm. Danach wird die iPhone-App gebaut und ihr tatsächlich kompiliertes Bundle auf Vollbild-Konfiguration, Version, Icons und Berechtigungsbeschreibungen geprüft. Die Simulatorprüfung ist wegen wiederholter Boot-Probleme der gehosteten Runner optional über `workflow_dispatch` aktivierbar; ein grüner Standard-Build behauptet deshalb keine ausgeführte UI-Prüfung.


## Version 1.2.0
- Native iPhone launch storyboard and explicit SwiftUI scene configuration.
- Complete opaque app-icon set, including 3x home-screen images; all images are checked in.
- Quiet, readable cards by default, optional glass, system/light/dark appearance.
- Weekly progress and today's latest energy check; open-task filter and archive search.
- Larger touch targets and layouts that adapt to Dynamic Type and rotation.
- CI validates the compiled device bundle, then boots and measures the actual app on two iPhone sizes in light/dark mode and large-text onboarding. Screenshots and viewport reports are available in the UI verification artifact. The XCTest suite remains available for interactive navigation regression checks.

The bundle identifier stays unchanged so an in-place update preserves existing data. The IPA is unsigned and must be signed by your installation tool.

A simulator first-boot timeout is reported separately as infrastructure unavailable; it does not invalidate the compiled device IPA. App launch failures and viewport mismatches still fail verification. Full interactive XCTest navigation checks can be run using the TherapieApp test scheme.
