# Kompass 6000.0.0 · Kompass 6

Build 29, iPhone ab iOS 26.1. **Therapie heißt jetzt Kompass.** Die Bundle-ID bleibt `eu.rjuhas.therapie`, der Datenordner bleibt `Therapiedaten` (in Dateien jetzt unter „Kompass“). Datenformat **Schema 19**: nur zusätzliche Felder mit Standardwerten, alle Schemas 1–18 bleiben lesbar. Beim ersten Start legt die App `therapy-data.pre-6000.json` als unveränderte Kopie an. Neuere, unbekannte Schemas werden abgelehnt, ohne Daten zu überschreiben.

## Mitteilungen & Wecker (neu)

- Ein nativer Bereich für alle aktuellen und künftigen Erinnerungen (Mond-Symbol auf Heute, Profil › Alltag & Erinnerungen, Suche „Ruhe“).
- **Ruhe**: 1 Std., 3 Std., bis morgen 8 Uhr, 24 Std., 3 Tage oder offen. Verlängern (+1/+3/+24 Std.) und **vorzeitig beenden**. Eine neue allgemeine Ruhe ersetzt die alte.
- **Bereiche** einzeln ruhen lassen oder dauerhaft stumm: Aufgaben, Routinen, Check-ins, Therapietermine, Therapiestunde, Aufsteh-Wecker, Stimmung & Energie, Betreutes Wohnen.
- **Einzelne Erinnerungen**: diesmal überspringen, 24 Std. stumm oder stumm bis zur Änderung – und wieder einschalten.
- **Tägliche Ruhezeiten** (z. B. 22–7 Uhr) mit wählbaren Bereichen.
- Aufsteh-Wecker und eine laufende Therapiestunde sind bei „Alles in Ruhe“ standardmäßig ausgenommen (umschaltbar). Am Ende einer Ruhe kommt ein Hinweis zum Öffnen der App.
- Übersicht der nächsten 7 Tage: jede geplante Mitteilung und jeder AlarmKit-Wecker mit Status („ruht bis …“), Filter, Direktsprung in die Einstellungen der Quelle, dazu was iOS tatsächlich bereithält.
- Technik: Ruhe filtert AlarmKit-Kandidaten und alle Mitteilungen der App. Wiederholende Aufgaben-Erinnerungen werden während einer zeitlich begrenzten Ruhe durch einen einmaligen Hinweis nach der Ruhe ersetzt; die Wiederholung läuft beim nächsten Öffnen wieder an (Status sichtbar).

## Betreutes Wohnen (neu)

- Eigener Tab **BeWo**: nächster Termin mit Countdown, Art (Hausbesuch, Telefon, Begleitung …), Betreuer:in und Themen.
- Einzelne Termine und **regelmäßige Termine** (Wochentag, Uhrzeit, alle x Wochen); einzelne fallen lassen oder zum Vorbereiten öffnen.
- **Gesprächsthemen** schnell sammeln, für den nächsten Termin vormerken, nach Bereichen (Ämter, Geld, Wohnung, Gesundheit …) ordnen.
- **Gesprächsbegleitung**: Stimmung vorher/nachher, Themen abhaken mit Ergebnis, Notizen und Absprachen (wer, bis wann).
- **Ziele** mit kleinen Schritten, Kontakte mit Anruf-Taste, Erinnerungen (Mitteilung, optional AlarmKit), neutrale Sperrbildschirm-Texte.
- Heute-Karte, Suche und KI kennen den neuen Bereich.

## Design

- **Sanftes Glas** ist neuer Standard: Liquid-Glass-Kanten mit ruhiger, weitgehend deckender Fläche. Alternativ **Klares Glas** (wie Therapie 5) oder **Matt**.
- Regler für Deckkraft, Farbtönung und Hintergrund-Farbverlauf, Voreinstellungen (Ruhig, Ausgewogen, Lebendig, Schlicht) und Live-Vorschau unter Darstellung & Glas.
- Tabs: **Heute · Therapie · BeWo · Verlauf · Suche**. Alltag (Routinen, Aufgaben, Wecker, Duschtage, Notfall, Methoden …) liegt direkt auf Heute.
- **Schnell festhalten** auf Heute: ein Feld für Notiz, Aufgabe, Therapie- oder BeWo-Thema; Stimmung per Gesicht.
- Neues Icon (Kompass mit Blatt-Nadel), neuer Startbildschirm und „Neu in Kompass“.

## Fehlerbehebungen

- Nach dem Beenden eines Weckers (Stopp/Kreuz) zeigt die App sofort den aktuellen Stand: Intents melden ihre Route direkt, und ein Start im Hintergrund baut die Oberfläche beim ersten Sichtbarwerden neu auf.
- Live-Aktivität / Dynamic Island: Das Blatt-Symbol lag über dem Kreis-Fortschritt. Kompakt und minimal zeigen jetzt nur ein Symbol, Sperrbildschirm und erweiterte Ansicht ein ruhiges rundes Abzeichen.

## Sicherung

Ruhemodus, Glas-Einstellungen und Betreutes Wohnen sind Teil von `AppData` und damit in der verschlüsselten `.therapiebackup`, im lesbaren ZIP und im lesbaren Spiegel (`Eintraege/assistedLiving…`, `Einstellungen/quietMode.txt`, `Einstellungen/surface.txt`). Containerformat unverändert (v1).

## Prüfungen

CI: Modell-, KI-, Backup-, Speicher-, ZIP- und neue `KompassChecks` (Migration Schema 18→19, Ruhe inkl. vorzeitigem Ende, Bereiche, einzelne Erinnerungen, Ruhezeiten über Sommerzeit und Jahreswechsel, Aufgaben- und Weckerplanung, BeWo-Rhythmen über Sommerzeit/Jahreswechsel, Themen, Absprachen, lesbarer Spiegel), unabhängiger Python-ZIP-Leser, iPhone-Build und Bundle-Validierung (Version, Build, Anzeigename). Dynamic Island, Wecker-Stopp, Haptik und Liquid-Glass-Darstellung lassen sich nur auf einem echten iPhone bestätigen.
