"""Cross-check the Swift ZIP64 writer with an independent standard ZIP reader."""
import json
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    assert archive.testzip() is None, "ZIP CRC validation failed"
    names = archive.namelist()
    assert "LIES-MICH.txt" in names and "UEBERSICHT.md" in names
    assert len(names) == len(set(names))
    data = json.loads(archive.read("therapy-data.json"))
    manifest = json.loads(archive.read("manifest.json"))
    assert data == manifest["data"]
    assert data["schemaVersion"] == 13
    assert data["accentTheme"] == "purple"
    assert data["wellbeingPreferences"] == {"estimateBattery": True, "hourlyDecline": 2}
    assert data["aiSettings"]["speakReplies"] is True
    assert data["aiConversations"][0]["memory"] == "Familie und Pausen"
    assert data["notes"][0]["conversationTranscript"].startswith("Du: Meine Schwester")
    assert data["guidedCheckIns"][0]["satisfaction"] == 4
    assert data["aiSettings"]["weeklyReviewEnabled"] is True
    assert data["aiConversations"][0]["draftText"] == "Noch nicht gesendeter Gedanke"
    assert data["routines"][0]["repeatEveryWeeks"] == 2
    draft = data["editorDrafts"][0]
    assert "Mein nicht verlorener Entwurf" in archive.read(f"Eintraege/editorDrafts/{draft['id'].upper()}.txt").decode()
    assert data["aiSettings"]["model"] == "gpt-5.6-luna"
    assert data["aiMessages"][0]["text"] == "Mein KI-Rückblick"
    assert data["aiMessages"][0]["conversationID"] == data["aiConversations"][0]["id"]
    assert data["aiConversations"][0]["contextDays"] == 14
    assert data["guidedCheckIns"][0]["tags"] == ["Familie"]
    assert data["hashtagCatalog"] == ["Familie"]
    chat = data["aiConversations"][0]
    assert f"Eintraege/aiConversations/{chat['id'].upper()}.txt" in names
    assert data["schedule"]["recurrence"]["interval"] == 2
    assert data["therapyDiscussionAcknowledgedIDs"] == ["guided-discussed"]
    assert "apiKey" not in json.dumps(data)
    assert data["dashboard"]["pinnedRecordIDs"] == ["note-backup-test"]
    assert data["dashboard"]["showWidgetTitles"] is True
    assert data["archivePreferences"] == {"grouping": "Jahre", "oldestFirst": True}
    assert "note-backup-test" in archive.read("Eintraege/Einstellungen/dashboard.txt").decode()
    assert data["weeklyEnergyReviews"][0]["gives"][0]["title"] == "Freunde"
    assert data["guidedCheckIns"][0]["batteryPercent"] == 0
    assert data["routines"][0]["title"] == "Frühstück"
    assert data["routineCompletions"][0]["outcome"] == "skipped"
    assert data["companionSettings"]["checkInReminders"][0]["kind"] == "morning"
    assert data["routineCompletions"][0]["routineTitle"] == "Frühstück"
    assert data["routineCompletions"][0]["corrections"][0]["reason"] == "Falsche Angabe"
    assert "Check-in-Erinnerungen" in archive.read("Eintraege/Einstellungen/companionSettings.txt").decode()
    for key in ("guidedCheckIns", "routines", "routineCompletions"):
        record = data[key][0]
        assert f"Eintraege/{key}/{record['id'].upper()}.txt" in names
    note = data["notes"][0]
    assert "zweite Zeile" in archive.read(f"Eintraege/notes/{note['id'].upper()}.txt").decode()
    assert archive.read("Recordings/empty.m4a") == b""
    assert archive.read("Media/p.jpg") == bytes(i % 251 for i in range(256 * 1024 * 2 + 5))

    assert len(data["notes"][0]["mediaIDs"]) >= 2
    assert data["guidedCheckIns"][0]["moodPercent"] == 77
    assert data["guidedCheckIns"][0]["energyPoints"][0]["title"] == "Technik"
    assert data["companionSettings"]["taskAlarmsEnabled"] is True
    assert len(data["companionSettings"]["dayCheckInSlots"]) == 6
    assert data["sessionPreferences"]["namedLiveActivity"] is False
    assert "Echte Abschnittsnamen" in archive.read("Eintraege/Einstellungen/sessionPreferences.txt").decode()
    assert data["schedule"]["cancellations"][0]["reason"] == "therapist"
    assert data["schedule"]["therapyVacations"][0]["note"] == "Urlaub"
    assert data["schedule"]["therapyAlarmsEnabled"] is True
    assert data["companionSettings"]["sessionPhaseAlarmsEnabled"] is True
    assert data["schedule"]["alarmIDs"] == []
    assert "calendarEventIdentifier" not in data["schedule"]
    assert "Therapie-Absagen" in archive.read("Eintraege/Einstellungen/schedule.txt").decode()
print("Independent Python ZIP64, CRC, attachment and human-readable record verification passed.")
