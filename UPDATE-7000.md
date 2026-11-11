# Kompass 7000.0.0 · Kompass 7

Build 31, iPhone ab iOS 26.1. Enthält das KI-Update 6100 (PR #5). Bundle-ID `eu.rjuhas.therapie` und Datenordner `Therapiedaten` bleiben unverändert. Datenformat bleibt **Schema 19**; neu sind nur optionale Felder mit Standardwerten (`dashboard.simpleHome`, `dashboard.extraCards`, `skippedPhaseTitles`/`skippedPhaseIDs` einer Therapiestunde). Alle älteren Daten und Sicherungen öffnen unverändert, Containerformat bleibt v1.

## Fehlerbehebungen

- **App nach einem Wecker sofort bereit**: Startete ein Wecker oder Kurzbefehl die App im Hintergrund, las die Hintergrundschleife einen veralteten Szenenzustand. Routen und Pop-ups blieben liegen, bis man die App verließ und neu öffnete. Jetzt laufen Szene aktiv, UIKit „did become active“, Entsperren und Intent-Signal über eine gemeinsame Aktivierung; Pop-ups prüfen den echten App-Zustand. Nach einem Hintergrundstart entfällt der Startbildschirm, und die Oberfläche wird nur dann neu aufgebaut, wenn sie nicht sichtbar war (keine zurückgesetzte Navigation mehr).
- **Pause stoppt alle Wecker**: Pausieren, Fortsetzen und Überspringen entfernen die Mitteilungen der Stunde sofort (alle Abschnitte, nicht nur die ersten zwölf) und planen AlarmKit unmittelbar neu, statt auf die verzögerte Aktualisierung zu warten.
- **Keine Wecker-Stapel mehr**: Wecker, die innerhalb von 50 Sekunden klingeln würden (z. B. nach einer Ruhe), werden zu einem zusammengefasst („+1 weitere Erinnerung“). Aufsteh-Wecker haben Vorrang, dann die laufende Stunde. Einminütige Abschnitte bleiben getrennt.

## Therapiestunde

- **Schritte überspringen** mit Bestätigung: den aktuellen Schritt beenden (der nächste startet mit voller Zeit) oder einen späteren aus dem heutigen Ablauf nehmen bzw. direkt dorthin springen. Funktioniert auch pausiert.
- **Schritte auslassen beim Start** („Kaffee schon fertig“): Auswahl vor dem Start, mit Rückfrage. Die Vorlage bleibt unverändert; übersprungene Schritte stehen in der Stunde.
- Ruhigere Ablaufliste mit Status (erledigt, jetzt, übersprungen, kommt).

## Design

- Liquid Glass mit ruhigen, weitgehend deckenden Flächen (Sanftes Glas: 55–95 % Deckkraft), feiner Lichtkante, flachen getönten Symbolen und einem sanften, günstiger zu zeichnenden Hintergrund statt Mesh-Verlauf. Klares Glas und Matt bleiben wählbar.
- **Heute** ist standardmäßig eine kurze Seite: Begrüßung, Als Nächstes (Therapie, BeWo, Stunde starten), Wochenaufgaben mit Abhaken und direktem Hinzufügen, fällige Routinen, Schnell festhalten. Weitere Karten unter „Heute anpassen“; die klassische Kartenliste ist ein Schalter.
- Aufgeräumte Werkzeugleiste (Notfallplan, Ruhe, Mehr).
- **BeWo**: kompakte Aktionsleiste, Themen und Absprachen direkt unter dem nächsten Termin.
- **Ort im Verlauf**: Einträge mit Standort zeigen „Ort“; ein Tipp öffnet die Karte mit Ortsnamen und „In Karten öffnen“.

## Sicherung

Neue Felder sind Teil von `AppData` und damit in `.therapiebackup`, im lesbaren ZIP und im lesbaren Spiegel. BackupChecks prüfen das neue Heute-Layout.

## Prüfungen

CI: Modell-, KI-, Backup-, Speicher- und KompassChecks (neu: Überspringen/Springen inkl. Pause, ältere Stunden ohne Überspring-Daten, Zusammenfassen gleichzeitiger Wecker), unabhängiger ZIP-Leser, iPhone-Build und Bundle-Validierung. Nur auf dem iPhone prüfbar: Wecker-Start der App, AlarmKit, Live-Aktivität, Haptik und das Aussehen des Glases.
