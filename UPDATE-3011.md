# Therapie 3011.0.0 · Geführte Gespräche

- Check-in: feste Fortschrittsleiste und Standardfrage, persönliche KI-Nachfragen, Übersicht jederzeit per Knopf oder „Bitte den Check-in speichern“. Die letzte Frage führt zur Übersicht. Korrekturen bleiben möglich; Speichern erfolgt ausdrücklich in der nativen Übersicht.
- Gespräche: Tage-/Wochengruppen nach letzter Aktivität, Filter, Suche in allen Chats und im einzelnen Chat, jeweils 40 weitere Gespräche/Nachrichten laden.
- Kontext: relevante Textauswahl, bis zu acht Nachrichten mit gemeinsamem Zeichenlimit und kurze Gesprächsnotiz. Tagesbezüge wie gestern/vorgestern berücksichtigen den lokalen Kalender. Bilder werden ausschließlich nach Auswahl und Kostenhinweis hochgeladen; die textliche Antwort bleibt im Chat erhalten.
- Tagebuch: beim Speichern KI-Zusammenfassung, Überschrift und bearbeitbare Tags. Vollständige Gesprächsdetails bleiben im Eintrag erhalten, auch nach Löschen des Chats. Abgeschlossene KI-Check-ins behalten ebenfalls ihre Gesprächsdetails. Bereits bestätigte alte KI-Vorschläge bleiben gegen doppelte Ausführung geschützt.
- Sprache: ein Tippen startet die Aufnahme, das zweite stoppt und transkribiert nach einmaliger Upload-Freigabe. Chattexte vor dem Senden bearbeiten; während einer Stunde unmittelbar als Notiz speichern. Hintergrundwechsel stoppt die Aufnahme ohne Upload; erneutes Transkribieren ist möglich. Antworten können mit der iPhone-Sprachausgabe einzeln oder automatisch vorgelesen werden.
- Native Aktionen: exakter Akku-Prozentwert, mehrere Uhrzeiten einer Routine, Ziele mit Datum/Priorität, echte Therapierunden-Vorlagen und kuratierte Hauptfarben mit Vorschau. Alle weiteren Einstellungen sind über passende native Bereichslinks erreichbar; API-Schlüssel und Upload-Freigaben werden nicht durch KI verändert. Modell und Transkriptionsmodell bleiben unverändert.
- Befinden: im Profil und bei Stimmung „Live / Heute / 7 Tage“ mit Akku, Stimmung, Stress, Reizen und optional selbstberichteter Zufriedenheit. Rot steht für geringe Energie bzw. hohe Belastung, Grün für hohe Energie. Eine ausdrücklich einschaltbare Akku-Schätzung beschreibt ihre Regel und ersetzt keine gemeldeten Werte.

Alle neuen Daten und Einstellungen gehören zum vollständigen AppData-Snapshot, zum verschlüsselten Backup, zum lesbaren ZIP und zum menschlich lesbaren Spiegel. Schema 1–12 bleibt importierbar; unbekannte zukünftige Versionen werden abgewiesen. API-Schlüssel werden weiterhin nicht exportiert.

Normale Builds führen nur die kurzen Kernprüfungen und den nativen iPhone-Build aus. Diese Veröffentlichung aktiviert zusätzlich zwei fokussierte Simulator-Bedienungstests; die langen Zusatzreihen bleiben optional. Echte OpenAI-Anfragen, Mikrofon, Wiedergabe und gerätegebundene Wecker müssen mit der installierten App auf einem iPhone geprüft werden. Die IPA wird wie bisher unsigniert gebaut.

## Wiederherstellung

Vorheriger Quellcode: `18c47210d698e8247551b8718a9d203d6517807c`, Branch `backup/v3010.0.0-before-guided-chat-2026-10-02`.

Die Veröffentlichung stellt den neuen Quellcode und einen ZIP-Snapshot dieses vorherigen Stands bereit. Ein Code-Rollback ersetzt keine persönlichen iPhone-Daten. Für die alte App-Version zusätzlich ein persönliches Backup von vor dem Update behalten; sie kann Schema 13 nicht lesen und soll es auch nicht überschreiben.
