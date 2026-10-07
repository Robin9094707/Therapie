# Therapie 3014.0.0 · Build 22

- Persönlicher Methodenkoffer mit mehreren Methoden und Gedankenstopps, Suche, Favoriten, Akkuthemen und konkreten Akku-Punkten.
- Interaktive Phasenübersicht: Vorbeugen, Eindämmen, Beruhigen. Zuordnungen stammen aus den eigenen Angaben.
- Groß lesbarer, frei bearbeitbarer Notfallplan, eigene Schritte und Unterstützung, Foto oder Archivbild, verknüpfte Methoden. Direkt von Heute erreichbar.
- 5-4-3-2-1 mit fünf begleiteten Sinnes-Schritten, optionalen Antworten, Überspringen und freiwilligem gespeicherten Verlauf.
- Feste Duschroutinen mit dem bestehenden Erinnerungs-/Alarm-System oder flexibel bestätigte Duschtage mit bearbeitbarem Verlauf.
- KI-Entwürfe für Methoden, Gedankenstopps und Notfallplan mit Vorschau und Bearbeitung vor dem Speichern; App-Kontext nur auf Wunsch. Der bestehende API-Schlüssel wird verwendet. Kein Bild wird automatisch an die KI gesendet.
- Begrüßung standardmäßig ganz oben; eigener Begrüßungssatz, ruhiges Layout, Vollansicht, ausblendbare Schnellzugriffe und KI-Impulse, verschiebbare Karten und einheitliche Hauptfarbe.
- Widgets: Aufgaben ohne aktivierte Mitteilungen sichtbar, Titelfilter bei neutralen Titeln ohne leere Anzeige, manueller Termin auch ohne Datum, zwei Cache-Lesewege, Aktualisierung bei App-Aktivierung, Hauptfarbe aus der App.

## Update und Sicherung
Bundle-ID eu.rjuhas.therapie und bisherige Datenspeicher bleiben erhalten. Schema 1–14 wird mit additiven leeren Standardwerten auf 15 gelesen. Vor der Migration wird therapy-data.pre-3014.json im App-Datenordner gesichert. Methoden, Übungen, Duschtage, Einstellungen und Notfallplan mit Archivbild sind in verschlüsseltem Backup und lesbarem ZIP enthalten. Die App zum Aktualisieren nicht löschen und dieselbe App-Identität beim Signieren erhalten.

Ausgangsstand: 51a521cde3f3230b51776dae8253df78f0ba6d9b
Sicherungsbranch: backup/pre-methods-2026-10-07
Die ältere App versteht Schema 15 nicht: für einen Rückbau zuerst ein aktuelles Backup sichern und den alten Datenstand gezielt wiederherstellen. Kein automatisches Überschreiben durch die ältere App.

## Installation und Widgets
Der vorhandene GitHub-Workflow baut eine **unsignierte IPA** zum anschließenden Signieren mit dem eigenen Installationsverfahren. App und Widget-Erweiterung benötigen beim Signieren dieselbe Berechtigung group.eu.rjuhas.therapie. Entfernt das Installationsverfahren App-Gruppen oder die Erweiterung, können automatische Widgets keine Daten austauschen. Die manuelle Datenquelle benötigt diesen gemeinsamen Zugriff nicht. Nach dem Update die App öffnen, in Profil / Widget-Einrichtung aktualisieren und das Widget bei Bedarf neu hinzufügen. Manuelle Timer-Widgets zeigen den gewählten Termin, keinen vorgetäuschten Live-Timer.

## Verifikation
Release-Workflow: vorhandene Modell-/KI-Prüfungen, verschlüsselte Backup-Rundreise, lesbare ZIP-Rundreise mit unabhängigem ZIP64-Leser, iPhone-Kompilierung und tatsächliche Bundle-Prüfung. Ergänzt sind gezielte Prüfungen für Migration, Methodenzuordnungen, Begrüßungsreihenfolge, neue Backup-Daten und Aufgaben-Widgets. Keine zusätzliche vollständige Simulator-Testserie.
Gerätesignierung, Widgets auf dem echten iPhone und tatsächliche KI-Antworten mit dem privaten Schlüssel sind nicht durch Kompilierung bewiesen.
