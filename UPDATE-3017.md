# Therapie 3017.0.0 · Liquid Glass

Build 26, iPhone ab iOS 26.1. Bundle-ID bleibt `eu.rjuhas.therapie`. **Keine Änderung am Datenformat** (Schema 17), an der verschlüsselten Sicherung oder am lesbaren ZIP. Alle vorhandenen Einträge, Fotos, Aufnahmen, Dokumente, Sicherungen und Einstellungen funktionieren unverändert weiter.

## Gestaltung

- Gemeinsames Designsystem in `TherapieApp/DesignSystem.swift`. Alle Karten (`GlassCard`), Statuschips, Schnellaktionen, Archiv-Auswahlchips, die Rückgängig-Taste, die „Geschafft!“-Bestätigung, Hinweisbanner und die Eingabeleisten im KI-Chat und Check-in verwenden jetzt Liquid Glass.
- Ein ruhiger Farbverlauf (MeshGradient) im Hintergrund leitet sich aus der gewählten Hauptfarbe und einem passenden zweiten Farbton ab. „Ruhige Oberfläche“ dämpft Verlauf und Glastönung. Mit der iOS-Bedienungshilfe „Transparenz reduzieren“ werden alle Glasflächen zu deckenden Flächen.
- Abschnittssymbole stehen in farbigen Kacheln mit Verlauf. Überschriften verwenden die gerundete Systemschrift und sind für VoiceOver als Überschrift markiert.
- Alle `bordered`/`borderedProminent`-Knöpfe nutzen die iOS-26-Stile `glass`/`glassProminent`.
- Die Heute-Begrüßung zeigt zusätzlich Wochentag und Datum.
- Die Tableiste nutzt die native `Tab`-API und verkleinert sich beim Scrollen nach unten (in UI-Tests deaktiviert).

## Startbildschirm und Neuigkeiten

- Der native Startbildschirm zeigt das abgerundete Therapie-Logo. Ein animierter Splash setzt exakt an dieser Stelle fort (Glasplatte, Farbverlauf, Titel) und blendet nach gut einer Sekunde aus. Antippen überspringt ihn; bei „Bewegung reduzieren“ wird nur kurz überblendet. Sheets aus Mitteilungen oder Kurzbefehlen erscheinen erst danach.
- Nach dem Update erscheint einmalig „Neu in Therapie“. Der zuletzt gesehene Versionsstand liegt ausschließlich als Gerätezustand in `therapy.lastSeenVersion` (wie `therapy.permissions3000`) und ist bewusst nicht Teil der Sicherung. Neuinstallationen markieren ihn beim Einrichten. Erneut aufrufbar unter Profil › Deine Oberfläche › „Neu in dieser Version“.

## Fehlerbehebungen

- Aufgaben, Archiv, Kalender, Insights und Therapieraum enthielten einen eigenen `NavigationStack`, obwohl sie auch aus anderen Stapeln geöffnet werden (Heute-Werkzeugleiste, „Alles im Blick“, KI-Navigation). Das ergab doppelte Navigationsleisten und ein unzuverlässiges Zurück. Diese Ansichten nutzen jetzt den Stapel ihres Tabs bzw. Präsentators.
- „Zuletzt festgehalten“ verglich die Trennlinie mit der unsortierten Notizliste und zeigte dadurch überzählige oder fehlende Trenner.

## Prüfungen

CI führt die bestehenden Modell-, Backup- und Speicherprüfungen aus, kompiliert die iPhone-App und prüft das tatsächliche Bundle. Optik, Glas-Rendering, Animationen und Haptik auf einem echten iPhone sind dadurch nicht nachgewiesen.
