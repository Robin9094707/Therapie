# Therapie 4000.0.0 · Therapie 4

Build 27, iPhone ab iOS 26.1. Bundle-ID bleibt `eu.rjuhas.therapie`. Datenformat **Schema 18** (additiv): Schema 1–17 und ältere Sicherungen werden unverändert übernommen. Vor der ersten Änderung bleibt die bisherige Datei als `therapy-data.pre-4000.json` erhalten. Zukünftige Schemata werden weiterhin abgelehnt, ohne Daten zu überschreiben.

## Aufgeräumt und einheitlich

- Profil wie die Einstellungen-App: Profilkopf mit Initialen, darunter gruppierte Glas-Abschnitte „Ich & meine Therapie“, „Alltag & Erinnerungen“, „Gestaltung“, „KI-Begleiter“ und „Daten & Privatsphäre“. Jede bisherige Karte hat eine eigene ruhige Unterseite; Funktionen sind unverändert.
- Alle 38 Formulare und Listen (Editoren, Einstellungen, Assistenten) nutzen über `therapyFormStyle()` denselben Hintergrund wie die übrigen Seiten.
- Heute: Schnellzugriffe als wischbare Kachelreihe; „Alles im Blick“ mit Duschtagen; Aufgabenkopf mit Filter, Erinnerungen und Timeline in einer Karte.
- Therapiestunde: neuer Zeitring mit Abschnittsfarben, vergangener Anteil voll eingefärbt.

## Duschtage

- Zielring und Wochenleiste (Mo–So: geduscht, geplant, ausgelassen, frei) auf der Karte.
- Ein gemeinsamer Verlauf für geplante und zusätzliche Duschtage. Pro Eintrag:
  - „Doch nicht geduscht“ bzw. „Doch geduscht“ für geplante Tage (Korrektur mit Verlauf, Erinnerungen werden nicht erneut geöffnet),
  - „Als falsch eingetragen markieren“ – bleibt durchgestrichen sichtbar, zählt nicht mehr, jederzeit aufhebbar,
  - Bearbeiten und Entfernen für zusätzliche Einträge.
- Neue Felder: `ShowerEntry.markedWrongAt`, `RoutineCompletion.markedWrong`. Beide sind Teil der verschlüsselten Sicherung, des lesbaren ZIP und der Textdateien.

## Dynamic Island / Live-Aktivität

- Die Live-Aktivität wird vor dem Einplanen der Mitteilungen angefordert. Zusätzlich holt die App sie beim Verlassen (inaktiv) nach. Vorher konnte sie fehlen, wenn man die App direkt nach dem Start verließ, weil iOS Live-Aktivitäten nur im Vordergrund startet.
- Neue Darstellung: Fortschrittsring, Restzeit und Abschnittsbalken sind vollständig timergesteuert und laufen im Hintergrund korrekt weiter. Der Abschnittsname aktualisiert sich über den Stale-Zeitpunkt an der nächsten Abschnittsgrenze.
- Nach dem Ende bleibt eine ruhige „Geschafft“-Karte 15 Minuten auf dem Sperrbildschirm.

## Prüfungen

CI: Modell-, Duschkorrektur-, Backup-, Speicher- und ZIP-Prüfungen (Schema 18), iPhone-Build und Bundle-Validierung. Darstellung der Dynamic Island und Live-Aktivität im Hintergrund lässt sich nur auf einem echten iPhone bestätigen.
