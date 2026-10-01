## Update 3006.0.0

- Insights bündelt Diagramme, persönliche Stimmungsvergleiche, Trends, Akku-Stichwörter und den Einstieg zum Wochenbericht. Das Stimmungsbarometer lässt sich von 0 bis 100 einstellen; frühere Werte bleiben erhalten.
- Morgen (5–11), Mittag (11–14), Nachmittag (14–18) und Abend (18–23) sind standardmäßig aktiv. Nacht (23–5) ist optional. Zeitfenster und eigene Check-ins sind einstellbar. Neue Tages-Check-ins sind außerhalb ihrer Fenster gesperrt; bestehende Entwürfe bleiben bearbeitbar.
- Geführte Check-ins unterstützen einzelne Akku-Stichwörter mit optionalem Satz und Wirkung. Beim Abschließen werden ihre Statistikdaten zusammen mit dem Check-in gespeichert; wiederholtes Speichern dupliziert sie nicht.
- Notizen haben einen größeren Editor, Listenhilfen, Fotos, Sprachaufnahmen und Archivanhänge. Lösen oder Löschen einer Notiz lässt Dateien im Archiv erhalten. Das Archiv nutzt denselben sicheren Notizeditor.
- Wochenberichte sind echte A4-PDFs mit maximal 1–3 Seiten, gewählten Bereichen und bis zu drei bewusst ausgewählten Bildern. Standard ist die letzte Kalenderwoche. Vorschau, Drucken und PDF-Teilen sind integriert. Kürzungen und nicht abgedruckte Einträge werden ausgewiesen; Aufgaben und Ziele zeigen den heutigen Stand.
- AlarmKit ist optional auch für Tages-Check-ins, Aufgaben und Wochenenergie verfügbar. Öffnen und Änderungen aktualisieren den begrenzten Vorrat unabhängig von der Mitteilungsfreigabe. Erledigte/entfernte Erinnerungen werden bereinigt. Geräte-Alarmkennungen bleiben lokal.
- Profilname und Tageszeit bestimmen die Begrüßung; die Animation berücksichtigt reduzierte Bewegung. Bestehende Verlaufs-, Therapie-, Backup- und Archivfunktionen bleiben erreichbar.
- Schema 8 importiert frühere Daten mit optionalen Ergänzungen. Vor dem Upgrade wird `therapy-data.pre-3006.json` angelegt. Der vorherige Quellstand liegt im Git-Branch `backup/before-3006-2026-10-01`.

CI prüft Migration, vollständige verschlüsselte Sicherungen, lesbaren ZIP-Export, Erinnerungsplanung, Tagesfenster und den tatsächlichen PDF-Renderer. Der iPhone-Build und sein Bundle werden validiert. Alarmzustellung, Mikrofon und Drucker benötigen einen Test auf dem iPhone; ein erfolgreicher Build ersetzt ihn nicht.

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

## Update 3004.0.0 – Check-ins und Alltag

- Neuer Eintragbereich auf **Heute**: geführte Morgen-, Abend-, Therapie- und freie Check-ins, Fotos, Stimmung, Akku-Punkte, Notizen und Audio. Acht freiwillige Schritte mit Animation, Zurück, Überspringen, persistiertem Entwurf und Fortsetzen. Ausgelassene Werte bleiben unbekannt. Therapieende (auch manuell) bietet optional einen Check-in an; bei geschlossener App beim nächsten Öffnen. Aufgaben mit Herkunft, kleinstem Schritt und Zieltermin werden beim ersten Abschluss gemeinsam gespeichert. Bilder sind mit dem Check-in verknüpft und bleiben einzelne Archivmaterialien. Check-ins sind bearbeitbar und mit Bestätigung löschbar; bereits erzeugte Aufgaben und Fotos bleiben beim Löschen erhalten.
- Energie-Akku **0–100 %**, direkt ziehbar, mit Slider und VoiceOver-Verstellung. Für ältere Diagramme wird Prozentenergie ausdrücklich auf die bisherige Skala 1–5 umgerechnet (0 % = 1, 100 % = 5); Originalwerte bleiben erhalten. Abgeschlossene Check-ins zählen für die Auswertung, Entwürfe nicht. Einzeln über das System-Teilen-Menü oder zusammen mit der bisherigen CSV-Auswertung teilen; keine automatische Übermittlung an eine Therapeutin.
- **Routinen & Ziele**: eigene Namen, Symbole, Hinweise, mehrere Tageszeiten, Wochentage und alternative Wochenendzeiten, individuelle Pause bis Datum, Urlaubsmodus pro Routine, Verknüpfung mit vorhandenen Zielen. Medikament, Duschen und Frühstück sind ausschließlich editierbare Vorlagen und werden nicht automatisch angelegt. Keine fest gespeicherten Personen- oder Medikamentennamen.
- Offene Termine: ausdrücklich **Erledigt** bestätigen, einmalig eine Stunde verschieben oder bewusst auslassen (getrenntes Protokoll mit optionalem Grund). Bestätigungen betreffen exakt eine Routine-Uhrzeit-Datum-Kombination und lassen Folgetermine aktiv. Erinnerungsabstand 5–180 Minuten, optional ab gewählter Stunde dichter, optionale Nachtruhe. Unbestätigte Termine schließen ihr Erinnerungsfenster zur gleichen Uhrzeit am Folgetag, ohne Erledigt zu behaupten. Keine Einnahme-/Dosierungsempfehlung und keine automatische Nachholaufforderung.
- Endlicher iOS-Vorrat mit sichtbarer Reichweite: maximal 48 gemeinsame Aufgaben-/Routine-/Wochenhinweise, 16 davon für Aufgaben bei aktivierten Routinen; Reserve für Sitzungshinweise. Nächste sieben Tage werden berechnet, zuerst erhält jeder fällige/kommende Termin einen Basis-Hinweis, danach werden die frühesten Wiederholungen ergänzt. Nicht eingeplante Termine und die erste Lücke im vollständigen Wiederholungsplan werden gemeldet. Erneuerung beim Öffnen, Speichern und Mitteilungsaktionen. **Öffnen & bestätigen** und **Eine Stunde später** sind native Mitteilungsaktionen. Maximal acht zusätzliche dringende AlarmKit-Wecker. Ein Stopp öffnet die Routine und bestätigt keine Erledigung; weitere bereits geplante Wecker bleiben aktiv. iOS erlaubt kein unbegrenztes Erzwingen: Mitteilungsfreigabe, Weckerfreigabe, Systemkapazität und regelmäßiges Öffnen bleiben erforderlich.
- Datenschema 7 übernimmt Schemas 1–6, gleicher Bundle-Identifier. Vor Migration bleibt `therapy-data.pre-3004.json` erhalten. Alle neuen Records und Einstellungen sind in verschlüsselten Backups, Klartext-ZIP und automatischem lesbarem Spiegel enthalten. Geräte-Wecker-IDs liegen außerhalb von AppData und reisen nicht durch Exporte.
- Rückkehr zum bisherigen **Quellcode**: Branch `backup/before-guided-update-2026-09-30`, Commit `b8b36d15239c13b6daeaed5f05081c55c9644b77`. Vor einem **App-Downgrade** eine ältere Datensicherung behalten: die vorige App kann Schema 7 nicht lesen. Der gesicherte Quellcode allein setzt keine lokalen Einträge zurück.
- CI prüft neue Migrationen und vollständige Backups, optionale Antworten, 0-%-Akku, stabile Reminder-IDs, exakte Terminbestätigungen, einmaliges Verschieben, Urlaub, Nachtruhe sowie Sommer-/Winterzeit und Jahreswechsel. Gerätebuild und tatsächliches Bundle werden validiert. Haptik, AlarmKit, Sperrbildschirmaktionen und Fotos benötigen zusätzliche Tests am echten iPhone.


### Update 3005.0.0

- Optionale Morgen-/Abend-Check-in-Mitteilungen mit eigenen Wochentagen, Wochenendzeiten und Urlaubspause. Maximal zwei pro Tag für sieben Tage; beim Öffnen und Speichern wird der Vorrat erneuert. Abgeschlossene Check-ins unterdrücken den Tageshinweis. Antippen öffnet den heutigen Entwurf oder den vorhandenen Tages-Check-in.
- Gesamter Routinenverlauf mit Suche, Zeitraum, Statusfilter und historischen Routinen-/Terminnamen. Angabe und Notiz können mit Pflichtgrund korrigiert werden; frühere Werte bleiben im exportierbaren Audit. Korrekturen öffnen keine Erinnerungen erneut.
- Therapieübersicht mit Datumsauswahl, einzeln wählbaren abgeschlossenen Check-ins, Akku-Verlauf und iOS-Teilen-Vorschau. Notizen, Namen und Routinen nur auf ausdrückliche Auswahl. Aufgaben und Ziele zeigen den aktuellen Stand; Fotos/Audio separat teilen. Fehlende Werte werden nicht geschätzt.
- Additive Schema-7-Felder: vorhandene Daten, verschlüsselte Backups und lesbare ZIPs bleiben kompatibel. Frühere Einstellungen lassen neue Erinnerungen ausgeschaltet. Bundle-ID unverändert.
- Quellcode vor diesem Update: Branch `backup/before-3005-2026-10-01`. Eine Quellcode-Sicherung ersetzt kein externes Datenbackup vor App-Deinstallation oder Downgrade.


### Update 3005.0.1

Behebt unsichere Listenbindungen beim Entfernen einer Check-in-Aufgabe: Editoren greifen über die stabile ID zu, verschwundene Zeilen lesen einen sicheren Snapshot und verspätete Tastaturereignisse ändern keine anderen Aufgaben. Dieselbe Absicherung gilt für Routinenzeiten, Wochenaufgaben und verschiebbare Stundenplan-Phasen. Neue Regressionen prüfen entfernte/verschobene Zeilen, nachträgliches Hinzufügen und Abschließen mit leerer Aufgabenliste. Eingabefelder im Check-in erhalten feste Beschriftungen, größere Innenabstände, dezente Konturen und eine sichtbare Fokusmarkierung. Datenformat und Bundle-ID bleiben unverändert. Vorheriger Code: `backup/before-3005-0-1-2026-10-01`.
