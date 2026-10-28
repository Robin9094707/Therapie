# Therapie 5000.0.0 · Therapie 5

Build 28, iPhone ab iOS 26.1. Bundle-ID bleibt `eu.rjuhas.therapie`. Datenformat bleibt **Schema 18**: alle bisherigen Einträge, Fotos, Aufnahmen, Dokumente, Sicherungen und Einstellungen funktionieren unverändert. Neu ist nur ein additives Feld (`aiSettings.thinking`, Standard „ausgewogen“), das in der verschlüsselten Sicherung, im lesbaren ZIP und in den Textdateien enthalten ist. Beim ersten Start nach dem Update legt die App zusätzlich `therapy-data.pre-5000.json` als unveränderte Kopie an.

## Neue Struktur

- Vier Tabs statt fünf: **Heute**, **Therapie**, **Alltag**, **Verlauf** – plus der native **Such-Tab** von iOS 26.
- **Suche & alle Funktionen:** Jede Funktion der App erscheint als Symbol-Kachel, gruppiert nach Therapie, Alltag planen, Wenn es schwer wird, Festhalten, Rückblick sowie Profil & Daten. Die Suche findet zusätzlich Notizen, Aufgaben, Check-ins, Themen, Ziele, Medien und Stunden und öffnet sie direkt im Editor.
- **Alltag (neu):** Tagesstatus als Glas-Chips, heutige Routinen, Kacheln für Routinen, Aufgaben, Erinnerungen, Wecker, Duschtage, Timeline, Check-in-Zeiten, Notfallplan, 5-4-3-2-1, Methoden, KI sowie Stimmung, Notiz, Wochenenergie, Wochenrückblick, Foto und Sprachnotiz.
- **Therapie:** Stunden-Karte mit Live-Fortschritt (oder nächster Termin und Direktstart einer Vorlage), Kacheln für Termine, Kalender, Wochenaufgaben, Timeline, Therapiepass, Wochenbericht und Timer-Einstellungen, offene Gesprächspunkte und der Therapieraum mit Glas-Chips.
- **Verlauf:** Archiv („Einträge“) und Insights („Auswertung“) in einem Tab, umschaltbar in der Navigationsleiste.
- **Profil & Einstellungen** öffnen sich über den Avatar oben rechts auf jeder Seite.
- **Heute:** Begrüßung mit Status-Chips (laufende Stunde, nächste Therapie, offene Routinen und Aufgaben – jeweils antippbar), „Schnell erfassen“ mit sechs farbigen Kacheln (KI, Notiz, Stimmung, Rückblick, Foto, Sprachnotiz), „Heute gestalten“ und „Alle Funktionen“ am Seitenende.
- Während einer Therapiestunde zeigt eine **Mini-Leiste über der Tableiste** Abschnitt, Fortschrittsring und Restzeit; Antippen öffnet die Stunde, daneben Pause/Fortsetzen.

## Dynamic Island / Live-Aktivität

- Die Live-Aktivität wird **synchron** beim Start der Stunde angefordert – nicht mehr hinter einer „beschäftigt“-Sperre und der Mitteilungsplanung. Vorher konnte der Start verloren gehen, wenn man die App kurz nach dem Starten verließ.
- Beim Wechsel in den Hintergrund (inaktiv **und** Hintergrund) erhält die Aktivität frischen Inhalt; ein Hintergrund-Zeitfenster stellt sicher, dass die Aktualisierung vor dem Anhalten der App ankommt.
- Aktivitäten werden nie mehr beendet, solange die geschützten Daten noch nicht geladen sind (zuvor konnte ein Start bei gesperrtem Gerät die laufende Stunde aus der Dynamic Island entfernen).
- Aktualisierungen und Beenden laufen seriell und erfassen ihr Ziel vorab, damit eine ältere Bereinigung nie eine neue Aktivität beendet.
- Abschnittsname, „Abschnitt 2 von 4 · bis 15:20“ und „Zeit ist um“ werden beim Zeichnen durch iOS berechnet. Der Stale-Zeitpunkt liegt an der nächsten Abschnittsgrenze bzw. am Ende, sodass iOS genau dann neu zeichnet – auch ohne geöffnete App.
- Zusätzlich plant die App eine Hintergrundaktualisierung (`BGAppRefreshTask`) für die nächste Abschnittsgrenze; sie aktualisiert oder beendet die Aktivität allein aus deren Inhalt, ohne Zugriff auf die geschützten Daten. Den genauen Zeitpunkt bestimmt iOS.
- Abschnittsmitteilungen nennen den nächsten Abschnitt, wenn echte Namen eingeschaltet sind.

## KI

- **Lagebild** in jeder Anfrage: Vorname, Tageszeit und Wochentag, nächste Therapie (heute/morgen/in X Tagen), laufende Stunde mit Abschnitt und Restzeit, offene Aufgaben und Routinen, Duschstand, heutige Stimmung/Akku und aktuelle Themen.
- **Denkweise** in den Anweisungen: Anliegen erkennen, persönlich und konkret antworten, höchstens drei Punkte, ein kleiner nächster Schritt, höchstens eine Rückfrage, Muster nur mit Belegen, Zahlen/IDs/Daten vor dem Antworten gegen den Kontext prüfen; bei Krisenhinweisen Notfallplan anbieten und auf 112 sowie die TelefonSeelsorge (0800 111 0 111 / 0800 111 0 222) verweisen.
- **Denktiefe** (Schnell / Ausgewogen / Gründlich) in den KI-Einstellungen. Standard ist „Ausgewogen“ (Reasoning „low“); „Schnell“ entspricht dem bisherigen Verhalten.
- Zwei sehr komplexe Ausdrücke im Kontextaufbau und in der Tagesauswertung wurden in typisierte Teile zerlegt (gleiche Werte, schnellere und stabilere Kompilierung).

## Prüfungen

CI: Modell-, KI-, Backup-, Speicher- und ZIP-Prüfungen (inkl. Denktiefe in Sicherung, lesbarem ZIP und älteren Sicherungen), Live-Activity-Prüfungen jetzt bei jedem Lauf (Abschnittsposition, Ende-Zustand beim Neuzeichnen, Sitzungstitel), iPhone-Build und Bundle-Validierung (Version, Build, Hintergrundmodus und erlaubte Hintergrundaufgabe). Darstellung und Verhalten der Dynamic Island im Hintergrund, Liquid Glass, Haptik und Hintergrundaktualisierung lassen sich nur auf einem echten iPhone bestätigen.
