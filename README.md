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
