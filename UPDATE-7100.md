# Kompass 7100.0.0 · Kompass 7, vollendet

Build 32, iPhone ab iOS 26.1. Baut auf 7000.0.0 auf. Bundle-ID, Datenordner und **Schema 19** bleiben unverändert; keine neuen gespeicherten Felder, Containerformat v1.

## Therapie

- **Therapie-Tab neu geordnet**: Stunde, Gesprächsliste für die nächste Stunde, „Dein Therapieraum“ (Themen & Ordner, Ziele, wichtige Notizen, Materialien, Therapeut:in) und „Rund um die Therapie“ (Termine, Wochenaufgaben, Wochenbericht, Therapiepass, Kalender, To-do-Timeline, Timer) als ruhige Listen statt Kachelraster und Reiter. KI-Kurzwege stehen am Ende.
- **Therapiestunde**: Während einer laufenden Stunde verschwinden Vorlagen und Startknöpfe; frühere Stunden zeigen nur die letzten drei, alle weiteren auf einer eigenen Seite mit Bearbeiten und Wischen-zum-Löschen.

## Zuverlässigkeit

- Läuft eine zeitlich begrenzte Ruhe ab, während die App offen ist, werden Mitteilungen, wiederholende Aufgaben-Erinnerungen und AlarmKit-Wecker sofort neu geplant (statt bis zu fünf Minuten später).

## Flüssiger

- Die Stunden-Karte im Therapie-Tab zeichnet sich ohne laufende Stunde nur noch einmal pro Minute neu statt jede Sekunde.

## Verlauf

- Titel „Verlauf“ passend zum Tab, Karte direkt oben in der Leiste.

## Prüfungen

CI: Modell-, KI-, Backup-, Speicher- und KompassChecks, unabhängiger ZIP-Leser, iPhone-Build und Bundle-Validierung (7100.0.0, Build 32). Nur auf dem iPhone prüfbar: Wecker, Live-Aktivität, Haptik und Glas-Darstellung.
