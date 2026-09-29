# Therapie – Autismus-Therapiebegleiter für iPhone

Eine private, lokal-first iOS-App zur Organisation von Therapieterminen, Wochenaufgaben, Notizen, Fotos, Sprachaufnahmen, Rückblicken und Erinnerungen.

## Schwerpunkte
- SwiftUI + Liquid Glass (iOS 26+)
- AlarmKit für prominente Therapie- und Aufgabenalarme
- EventKit für iPhone-Kalender-Synchronisierung
- Fotos, Dokumente und Sprachaufnahmen lokal in der App
- Optionales Backup in einen selbst gewählten iCloud-Drive-Ordner
- Wochenaufgaben, Energie-Check-ins, Timeline und Kalender
- Standort-Metadaten nur nach ausdrücklicher Berechtigung
- Sicherheitsabfrage vor vollständigem Löschen aller Daten

## Datenschutz
Therapiedaten bleiben standardmäßig auf dem Gerät. Kalender-, Standort- und Alarmzugriff werden nur nach Systemfreigabe verwendet. iCloud-Drive-Backups werden nur in einen vom Benutzer ausgewählten Ordner geschrieben.

## Build
GitHub Actions erzeugt eine unsignierte IPA, die anschließend mit einem eigenen Sideloading-/Signing-Werkzeug signiert/installiert werden kann.
