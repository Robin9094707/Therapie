# Kompass 6100.0.0 · Das große KI-Update

Build 30, iPhone ab iOS 26.1. Datenformat bleibt **Schema 19**, alle Daten und KI-Einstellungen (Schlüssel im Schlüsselbund, Modell, Denktiefe, Gespräche) bleiben unverändert. Ohne eingerichtete KI ist die App vollständig nutzbar; alle KI-Knöpfe erscheinen nur bei aktivierter KI.

## Die KI kann mehr

- Neue Aktionen: **BeWo-Termin**, **BeWo-Thema**, **Absprache**, **BeWo-Ziel**, **Termin zusammenfassen**, **BeWo-Thema besprochen**, **Ruhe einschalten**, **Ruhe beenden** – zusätzlich zu allen bisherigen (Notizen, Stimmung, Aufgaben, Routinen, Therapie, Methoden, Notfallplan, Einstellungen …).
- **Terminerkennung**: „Dienstag um 10 kommt meine Betreuerin“, „am 12.11. um 14 Uhr Therapie“ oder „morgen Jobcenter um 9“ werden als passender Termin vorgeschlagen (BeWo, Therapie-Zusatztermin oder Aufgabe). Fehlt die Uhrzeit, fragt die KI nach.
- Über Betreutes Wohnen sprechen: Vorbereitung (Themen sortieren, Fragen, Unterlagen), Nachbereitung (Zusammenfassung, besprochene Themen, Absprachen).

## Interaktive Darstellung

- Vorschläge erscheinen als **Karten** mit Kalenderblatt, Details und **Übernehmen** / **Anpassen**. „**Alle übernehmen**“ speichert mehrere ergänzende Vorschläge auf einmal. Löschen, Abhaken und Änderungen an bestehenden Einträgen bleiben bewusst hinter der Prüfansicht.
- Nach dem Speichern führt „Ansehen“ direkt in den passenden Bereich.

## KI überall

- Heute: „Frag Kompass“ (Mein Tag, Wie geht's mir?, Woche planen, Ruhe planen) und „Mit KI besprechen & einordnen“ in „Schnell festhalten“.
- Therapie: Stunde vorbereiten, Nach der Stunde, Muster erkennen.
- BeWo: Termin vorbereiten, Nach dem Termin, Termin eintragen, Absprachen prüfen; in der Gesprächsbegleitung „Mit KI zusammenfassen“.
- Mitteilungen & Wecker: „Mit KI klären, was ruhen soll“. Suche: „Kompass-KI fragen“.

## Auch ohne KI

- „Schnell festhalten“ erkennt Datum und Uhrzeit lokal auf dem iPhone und trägt mit einem Tipp einen BeWo-Termin, Therapie-Zusatztermin oder eine Aufgabe ein.

## Sparsam

- Kontext nur für passende Bereiche (BeWo- und Ruhe-Details nur bei passender Frage, sonst eine Zeile im Lagebild).
- Gleichbleibende Anweisungen stehen unverändert vorn und nutzen OpenAIs Prompt-Caching (`prompt_cache_key`); Uhrzeit und Kontext stehen in der Nutzernachricht.

## Prüfungen

KompassChecks erweitert um KI-Aktionen (Gültigkeit, Anwenden, Doppelschutz, Standard-Termin für Absprachen), Schema, statische Anweisungen, Kontextauswahl und die lokale Terminerkennung (Wochentage, Datum, Monatsnamen, Jahreswechsel, Nachmittag, Fehltreffer, Sommerzeit-Lücke).
