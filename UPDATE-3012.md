# Therapie 3012.0.0 · Bugfix-Update

- KI-Check-ins: Der gespeicherte Schritt steuert die nächste Frage. Explizite Antworten schließen höchstens ein Modul ab. Zwischenfragen, fehlende Werte und Angaben zu späteren Modulen überspringen den aktuellen Schritt nicht. Am Ende erscheint die Übersicht; „Check-in speichern“ öffnet sie jederzeit zur Bestätigung.
- Gefühlsakku: Benannte Geber und Nehmer werden als getrennte Stichwörter gesammelt, etwa Mila und Geld. Bereits bekannte Punkte werden aktualisiert. Fehlende Wirkungsstärke wird nachgefragt und bis zur Bestätigung nicht in die Akku-Schätzung eingerechnet. Abschluss erstellt reguläre, bearbeitbare Akku-Punkte ohne Duplikate.
- Hashtags: Konkrete Namen und Themen haben Vorrang, bis zu zwölf passende Tags. Generische KI-Begleitung-Tags werden vermieden.
- Heute-Seite: Die Erledigt-Bestätigung einer Routine wird vom stabilen Bildschirm gesteuert, außerhalb der aktualisierten Zeitansicht. Abbrechen verändert nichts; Bestätigen löst genau den fälligen Termin auf.
- AlarmKit-Start: Geschützter Dateizugriff wird vor Migration, Laden und Schreiben geprüft. Vorübergehende Zugriffssperren warten auf Entsperrung und werden erneut versucht. Alarmrouten bleiben bis zum erfolgreichen Laden erhalten. Bereits geladene, noch nicht gespeicherte Eingaben werden erneut gespeichert, ohne sie durch einen alten Dateistand zu ersetzen. Echte beschädigte oder nicht unterstützte Daten bleiben schreibgeschützt.
- Bestehende Daten, App-ID und vollständige Backups bleiben erhalten. Der neue optionale Bestätigungsstatus für Akku-Wirkungen wird in verschlüsselten und lesbaren Backups gesichert; alte Punkte behalten ihre bisherige Stärke.
- Erster Speicherzugriff: Auch ein nach dem Entsperren nachgeholtes erstes Schreiben legt die benötigten geschützten Ordner an. Ein neues KI-Gespräch bleibt dadurch nicht beim Vorbereiten hängen.

## Prüfung

Vier gemeinsam kompilierte Kernprüfungen (Modelle, KI, verschlüsselte Backups und Speicher/Erinnerungen), unabhängiger ZIP64-Leser, iPhone-Build und Prüfung des tatsächlichen App-Bundles. Für dieses Update zusätzlich nur zwei gezielte UI-Simulatorprüfungen: Erledigen auf Heute und geführter KI-Check-in. Umfangreiche PDF- und weitere Simulatorprüfungen bleiben optional.

AlarmKit beim Entsperren muss zusätzlich auf einem echten iPhone geprüft werden; ein Simulator kann den Geräteschutz und echte Wecker nicht vollständig nachstellen. Echte OpenAI-Antworten hängen vom Modell ab; die lokalen Modul- und Speicherschranken gelten unabhängig davon. Das optionale Live-Streaming wird in diesem Update nicht umgebaut, weil Nachrichten und native Knöpfe gemeinsam als validiertes JSON verarbeitet werden.

## Vollständiger Rückkehrpunkt

Ausgangs-Commit: `aa58218b36b83bd9352b2e782775351491e7e9cd`

Gesicherter Branch: `backup/pre-bugfix-3012-2026-10-02`

Ein späterer Revert dieses Updates stellt den vorherigen Quellcode wieder her. Unabhängige spätere Änderungen müssen dabei erhalten bleiben. Dies ist eine Quellcode-Sicherung, keine Kopie privater iPhone-Daten.
