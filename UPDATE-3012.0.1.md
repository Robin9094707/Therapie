# Therapie 3012.0.1 · Build 20

- Geführte Check-ins bleiben nach einer klaren Antwort nicht mehr an fehlenden KI-Steuerfeldern hängen. Ankommen übernimmt den ausdrücklich geschriebenen Gedanken auch ohne KI-Extraktion. Eindeutige Skalenwerte und ausdrücklich gewählte Antworten werden lokal verarbeitet. Zwischenfragen und Angaben zu späteren Modulen überspringen den aktuellen Schritt weiterhin nicht.
- Passende Antwortknöpfe erscheinen von Anfang an unter der angehefteten, aktuellen Frage. Stimmung, Akku, einzelne Akku-Wirkungen, Stress, Reize und Schlaf haben passende Werte. Fehlende Teile werden einzeln nachgefragt. Die Übersicht erfordert weiterhin eine ausdrückliche Speicherbestätigung.
- Eindeutige Auswahlantworten benötigen keinen zusätzlichen OpenAI-Aufruf. Freie Antworten und Hilfe beim Finden von Themen bleiben KI-gestützt. Lokale Auswahlantworten sind entsprechend gekennzeichnet.
- Therapie-, Tages- und freie Check-ins verwenden dieselbe Fortschrittslogik. Die freiwilligen Überspringen-Formulierungen werden zuverlässiger erkannt.
- Die Therapie-Terminverwaltung öffnet vom Startbildschirm und Therapiebereich aus über den stabilen Root-Präsentationspunkt. Rhythmus, Zusatztermine, Absagen und Urlaub haben einen gemeinsamen Präsentationsbesitzer außerhalb der Form-Zeilen. Schließen und Speichern betreffen nur den aktuellen Unterdialog und erhalten die Terminverwaltung.
- Bestehende App-ID, Daten und Backup-Formate bleiben erhalten; es gibt keine neuen Datenfelder und keine Löschung bestehender Entwürfe.

## Prüfung

Vier schnelle Kernprüfungen inklusive beider Backup-Formate und unabhängiger ZIP64-Prüfung. Zwei gezielte Simulatorprüfungen: Therapie-Check-in bis zur bestätigten Übersicht und Tages-Check-in ohne KI-Steuerfelder; verschachtelte Terminverwaltung mit Rhythmus, Zusatztermin, Absage und Wiederherstellung. Zusätzlich iPhone-Build und Prüfung des tatsächlich gebauten Bundles.

Die simulierten KI-Antworten lassen bewusst sämtliche Check-in-Felder aus. Echte OpenAI-Antworten und Geräteeigenschaften müssen zusätzlich im Alltag geprüft werden; die lokalen Schranken gelten unabhängig von Modell-Steuerfeldern.

## Rückkehrpunkte

Vor diesem Folgefix: `cda739175fb4738fd2149edcceb0662fb01c1128`, Branch `backup/pre-bugfix-3012-0-1-2026-10-02`.

Vor dem gesamten Bugfix-Update 3012: `aa58218b36b83bd9352b2e782775351491e7e9cd`, Branch `backup/pre-bugfix-3012-2026-10-02`.

Die Sicherungen betreffen den Quellcode. Unabhängige spätere Änderungen sollen bei einem Revert erhalten bleiben.
