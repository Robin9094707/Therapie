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


## Version 1.2.0
- Native iPhone launch storyboard and explicit SwiftUI scene configuration.
- Complete opaque app-icon set, including 3x home-screen images; all images are checked in.
- Quiet, readable cards by default, optional glass, system/light/dark appearance.
- Weekly progress and today's latest energy check; open-task filter and archive search.
- Larger touch targets and layouts that adapt to Dynamic Type and rotation.
- CI validates the compiled device bundle, then boots and measures the actual app on two iPhone sizes in light/dark mode and large-text onboarding. Screenshots and viewport reports are available in the UI verification artifact. The XCTest suite remains available for interactive navigation regression checks.

The bundle identifier stays unchanged so an in-place update preserves existing data. The IPA is unsigned and must be signed by your installation tool.
