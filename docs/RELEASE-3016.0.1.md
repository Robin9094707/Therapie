# Therapie 3016.0.1 · Build 25

Performance-Fix für wiederkehrende kurze Blockierungen nach Version 3016.0.0.

- Apple-Erinnerungen werden nur noch bei tatsächlichen Änderungen gespeichert. Ein unveränderter Durchlauf führt keinen EventKit-Commit aus.
- Beim Zurücklesen ergänzte Kalender-, Zeitzonen- und Null-Sekunden-Felder führen nicht länger zu einem erneuten Schreiben derselben Fälligkeit.
- EventKit-Änderungsserien werden zusammengefasst; zwischen Abgleichen liegen mindestens drei Sekunden. Eigene Schreibvorgänge können einen lesenden Kontrollabgleich auslösen, aber keine ungebremste Schleife.
- Gleiche Statusmeldungen werden nicht wiederholt an die gesamte Oberfläche veröffentlicht. Notizen, Therapiepass und KI-Einstellungen lösen keinen Erinnerungsabgleich mehr aus.
- Widget-Neuladen ohne App-Gruppenrechte ist begrenzt; regelmäßige Wartung läuft nur bei aktiver Oberfläche.

App-Kennung und Datenformat bleiben unverändert. Bestehende Daten aus 3016.0.0 benötigen keine neue Migration. Als Update mit derselben App-Kennung installieren; vorher persönlichen Datenexport erstellen und die App nicht löschen.

Vorheriger Stand: ff0cb46cd78f9089bf2e336973eca614fd44fb01.
Die Rückkopplung wurde im Quellcode gefunden; die tatsächlichen Hänger auf dem Nutzer-iPhone können ohne Gerätetrace nicht abschließend zugeordnet oder gemessen werden.
