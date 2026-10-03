# Therapie 3013.0.0 · Build 21

KI-Erinnerungen zeigen vor dem Speichern eine bearbeitbare Vorschau mit Tagen, Uhrzeiten, AlarmKit, einmaliger / wöchentlicher Wiederholung und erneutem Erinnern bis erledigt. Neue Erinnerungsroutinen verwenden standardmäßig AlarmKit und einen Hinweis pro Zeitpunkt. Dringlichkeit und Wiederholungsintervall werden ausdrücklich festgelegt. Das Karton-Beispiel erzeugt keine Daten.

Akku-Punkte bleiben einzelne Stichwörter. Explizite Prozentwirkungen werden in fünf Stufen übersetzt (50 %=3/5); mehrere Angaben in einer Antwort werden gemeinsam übernommen. Unklare Stärken bleiben offen. Prozentwirkungen einzelner Punkte sind kein Akku-Ladestand.

Heute zeigt mehrere Wochenaufgaben mit direkten Häkchen. Die gemeinsame To-do-Timeline verbindet Aufgaben, Routinen und Therapiefragen am nächsten Therapietermin. Inhaltsfilter, Suche und Seiten begrenzen die sichtbare Menge; Archiv und Chats laden ebenfalls in begrenzten Abschnitten. KI-Anfragen verwenden begrenzten relevanten Text und Gesprächsnotizen, keine vollständige Chat-Sammlung.

Im Chat: Plus für Bild / PDF / Textdatei mit Kosten- und Kontextinformation, rechts Audioaufnahme mit Halten, Hochwischen zum Sperren, Verwerfen, Anhören und Senden. Erst Senden transkribiert und beantwortet die Nachricht. Originalaudio und Dateiverknüpfungen bleiben lokal abspielbar; verschlüsselte und lesbare Backups sichern die vollständigen Medien. PDFs liefern höchstens 30 Seiten / 12.000 Zeichen Text, keine automatische Analyse gescannter Seiten; andere Binärdateien werden nicht als KI-Inhalt angeboten.

Persönliche Impulse berücksichtigen die letzten drei Tage, höchstens einmal täglich automatisch beim Öffnen. Eigene Neugenerierung und passende Rückantworten sind möglich. Abschaltbar im KI-Profil.

Neue Einträge erhalten nach iPhone-Standortfreigabe einen frischen ungefähren Ort. Kein Hintergrund-Tracking und keine nachträglichen Orte für alte Daten. Die Eintragskarte hat Zeitraumfilter, Suche und begrenzte Markerzahl. Auf ausdrückliche Ortsfragen bekommt die KI eine kleine Statistik der tatsächlich erfassten Standorte. Standortaufnahme ist auf der Karte abschaltbar.

Schema 14 erweitert bisherige Daten additiv; alte Sicherungen bleiben importierbar. Neue Datensätze erscheinen im kompletten JSON-Snapshot und im lesbaren Spiegel. Der Backup-Container / Verschlüsselungsrahmen bleibt kompatibel. Ausschluss von Audio-/Dateibytes wird weiter als nicht verfügbar gekennzeichnet.

Rollback vor dieser Erweiterung: `0fd7c20d6a5fbc3e7b99c9e6aaac207b89e386af`, Branch `backup/pre-features-3013-2026-10-03`. Dieser Code-Rollback ist keine Rücksetzung neu erstellter Nutzerdaten. Vor einer Installation der älteren App ein aktuelles Backup erhalten; ältere Apps überschreiben Schema 14 nicht.

Prüfung: vier gebündelte Domänen-/Backup-Prüfprogramme und ZIP64-Prüfung; iPhone-Release-Build und tatsächliche Bundle-Prüfung; zwei gezielte Simulatorfälle für Timeline/Karte und Chat-Audio/Anhangswarnung; zusätzlich wurden im vorhergehenden Build derselben Erweiterung bisheriger Check-in- und Terminablauf geprüft. AlarmKit-Freigabe, echte Alarme, Mikrofon-Gesten und GPS brauchen abschließend ein physisches iPhone.
