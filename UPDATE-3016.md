# Therapie 3016.0.0 · Apple-Integration und persönliche Hilfe

Build 24, iPhone ab iOS 26.1. Bundle-ID bleibt `eu.rjuhas.therapie`. Additives Datenformat 17; bestehende Formate 1–16 werden übernommen. Vor der ersten Änderung bleibt die bisherige JSON-Datei als `therapy-data.pre-3016.json` erhalten. Private iPhone-Daten sind nicht in der hier gelieferten Code-Sicherung enthalten.

## Direkter Einstieg

Auf der Startseite: Notfallplan links oben; in den Schnellzugriffen Wecker, Therapiepass und Apple-Integration. Alle Bereiche auch im Profil. Bei ausgeblendeten Schnellzugriffen diese unter Startseite anpassen einschalten.

- Notfallplan: kompakte Hilfekarten, eigene Texte/Symbole, sortieren/ausblenden, gespeicherte Gedankenstopps und Methoden direkt mit ihren Schritten. Bisherige Informationen und Bilder bleiben erhalten. Bei großer Systemschrift automatisch einspaltig.
- Therapiepass: eigener Name, Geburtsdatum mit berechnetem Alter, Größe, Medikamente/Einnahmeplan als eigener Text, Allergien, Kontakte und Hinweise; gespeicherte Methoden bleiben mit dem Pass verknüpft. Keine Dosierungsempfehlungen.
- Routinen: eigene Beschriftungen, Schlummerdauer/-anzahl, bis zu sechs frei belegbare Aktionsknöpfe (bestätigen, auslassen, später, Notfallplan, Home-Szene). Morgens und abends beliebige Eskalationsuhrzeit statt nur Abendvorgabe.
- Wecker: Wochentage, Wochenenden, Datumsausnahmen, Schlummerregeln und endliche Folgealarme. Aufgaben: Addition, Kameraobjekt mit freiwilliger KI-Prüfung, sanfte Bewegung, Schritte oder einfache Bestätigung. Ein einmaliger Fünf-Minuten-Notfallschlummer und ein bestätigter Notfall-Stopp bleiben erreichbar.

## Apple-Erinnerungen einrichten

Apple-Integration öffnen, Zugriff erlauben & verbinden. Die App legt „Therapie · Routinen“ an. Fällige aktive Routinen und offene Aufgaben mit Datum im acht Tage umfassenden Vorrat erhalten Einträge. Es werden höchstens 100 verwaltete Einträge veröffentlicht. Neutrale Titel sind Standard; persönliche Titel lassen sich freigeben. Nur eindeutig app-eigene Einträge in der eigenen Liste werden verändert. Eigene Apple-Listen werden nicht verändert.

Eine bestätigte Erinnerung wird beim nächsten Abgleich als erledigt in die App übernommen. Bestätigte app-eigene Erinnerungen können entfernt oder als erledigt behalten werden. Auslassen bleibt im internen Protokoll getrennt von Erledigt. Abschalten der Integration räumt die verwalteten Einträge auf; die leere Liste bleibt verfügbar.

Abgleich beim Öffnen, nach App-Änderungen und über EventKit-Änderungen während die App läuft. Eine geschlossene App kann Erinnerungen nicht kontinuierlich überwachen. Der optionale dringende Alarm wird daher vorab mit einer einstellbaren Verzögerung geplant. Eine externe Bestätigung verhindert ihn nur nach rechtzeitigem Abgleich. Keine behauptete minutengenaue Hintergrundprüfung.

## Wecker und iOS-Grenzen

AlarmKit gesondert erlauben. Geplante Alarme werden durch iOS ausgelöst. „Aufgabe öffnen“ führt in die App; dort beendet eine erfolgreiche Aufgabe die restlichen Alarme dieses Termins. Schlummern ersetzt diese Generation mit den neuen Zeiten. Maximal fünf Folgealarme pro Termin, insgesamt ein begrenzter Vorrat von 24 app-verwalteten Alarmen. Die Statusanzeige nennt Vorratsgrenzen; beim Öffnen wird nachgefüllt.

iOS behält seinen System-Stoppknopf. Ein Nutzer kann die App beenden oder Systemrechte entziehen. Kein endloser, unausschaltbarer Wecker; keine Garantie der Reaktivierung nach jeder Manipulation. Kamera-/Bewegungsaufgaben benötigen die geöffnete App. Keine HealthKit-Freigabe nötig: Schritte kommen von CoreMotion. Bei sensor- oder KI-bedingten Fehlern ist Notfall-Stopp verfügbar.

Fotoaufgaben akzeptieren ausschließlich ein frisches In-App-Kamerafoto. Erst die separate Sendetaste sendet das Foto und die Objektbeschreibung an OpenAI, ohne den Therapiepass oder das Tagebuch. KI und Bildfreigabe sowie eigener API-Schlüssel sind Voraussetzung. Das Foto wird nicht ins Archiv gespeichert. Die Erkennung kann falsch liegen.

## Widgets trotz Sideloading

Automatische eigene Live-Widgets brauchen dieselbe freigegebene App-Gruppe in Hauptapp und Erweiterung. Entitlement: `group.eu.rjuhas.therapie`. Wenn der Signaturdienst diese entfernt oder inkompatibel umbenennt, kann Öffnen der App diesen Zugriff nicht reparieren.

Drei Alternativen:

1. Apples Erinnerungen-Widget: die verbundene Liste „Therapie · Routinen“ wählen. Die angelegten Einträge werden von Apple angezeigt; der Abgleich der Therapie-App bleibt wie oben beschrieben.
2. Konfigurierbares Therapie-Widget: in der Widget-Einrichtung den Daten-Code kopieren, im Widget als Datenquelle „Kopierter Datenstand“ wählen und einfügen. Der tatsächliche minimale Anzeigestand wird mit Kopierzeit angezeigt. Nach Änderungen neu kopieren; keine Live-Synchronisierung.
3. „Hilfe · Schnellzugriff“: eigenständiges statisches Widget für Notfallplan, Sinnesübung und Pass, ohne gemeinsame App-Daten. Manuelle Termin-Widgets bleiben verfügbar.

## Kurzbefehle und Home

Zehn App-Schnellzugriffe plus parametrisierbare Kurzbefehle für Routine-Bestätigung/-Auslassen und Wecker-Aktivierung/-Deaktivierung/nächsten Termin aussetzen. Deep Links z. B. `therapie://emergency`, `therapie://medicalpass`, `therapie://alarms`, `therapie://grounding`.

HomeKit ist optional und benötigt ein passendes Signaturprofil mit `com.apple.developer.homekit`. Nur nach Laden/Freigeben werden Szenen abgefragt. Szenen pro Routine oder Wecker auswählen; sie laufen beim Öffnen des fälligen Termins oder per bewusst gestarteter Shortcut-Aktion. Hintergrundausführung beim Klingeln wird nicht garantiert. Für zeitgebundene Home-Automationen die Apple-Apps Home/Kurzbefehle verwenden. Szenen-IDs und Systemberechtigungen bleiben gerätegebunden und werden nicht exportiert.

## Update, Backup und Rücksetzpunkt

Die IPA wie bisher signieren und über die vorhandene App aktualisieren. Bestehende App zuerst vollständig in der App sichern; nicht deinstallieren, da iOS den App-Datenordner dabei entfernt. Gleiche Bundle-ID und kompatible Signierung sind für ein sauberes Update nötig.

Alle neuen Daten und Einstellungen werden vollständig verschlüsselt und im lesbaren ZIP gesichert. API-Schlüssel, Geräteberechtigungen und Home-/Erinnerungen-Systemkennungen bleiben ausgeschlossen. Ein älteres App-Build versteht Schema 17 nicht: vor einem Rücksetzen aktuelle Daten separat sichern und den vorigen Datenstand verwenden.

Gesicherter Code-/IPA-Stand: `66aec8c9763a28a90256684f87a601983c5d0406`, GitHub-Branch `backup/pre-apple-integration-2026-10-07`. Das ZIP „Therapie-v3015-vor-Apple-Update.zip“ enthält vorherige IPA, Quellcode und Rücksetznotiz.

## Apple-Quellen

- https://developer.apple.com/documentation/eventkit/accessing-the-event-store
- https://developer.apple.com/documentation/eventkit/retrieving-events-and-reminders
- https://developer.apple.com/documentation/alarmkit/alarmpresentation/alert-swift.struct/init(title:secondarybutton:secondarybuttonbehavior:)
- https://developer.apple.com/videos/play/wwdc2025/230/
- https://developer.apple.com/documentation/homekit/enabling-homekit-in-your-app
- https://developer.apple.com/documentation/Technotes/tn3125-inside-code-signing-provisioning-profiles

## Nachweis

Release-Kernprüfungen, vollständige verschlüsselte Roundtrips, unabhängiger Python-ZIP64-Leser, iPhone-Kompilierung und tatsächliche Bundle-Validierung im GitHub-Workflow. Geräteverhalten nach Signierung (Alarmton, Kamera, Bewegung, Widgets, HomeKit, Siri) muss am iPhone geprüft werden; CI-Kompilierung belegt diese Laufzeitrechte nicht.
