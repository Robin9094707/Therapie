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
    assert data["schemaVersion"] == 7
    assert data["weeklyEnergyReviews"][0]["gives"][0]["title"] == "Freunde"
    assert data["guidedCheckIns"][0]["batteryPercent"] == 0
    assert data["routines"][0]["title"] == "Frühstück"
    assert data["routineCompletions"][0]["outcome"] == "skipped"
    for key in ("guidedCheckIns", "routines", "routineCompletions"):
        record = data[key][0]
        assert f"Eintraege/{key}/{record['id'].upper()}.txt" in names
    note = data["notes"][0]
    assert "zweite Zeile" in archive.read(f"Eintraege/notes/{note['id'].upper()}.txt").decode()
    assert archive.read("Recordings/empty.m4a") == b""
    assert archive.read("Media/p.jpg") == bytes(i % 251 for i in range(256 * 1024 * 2 + 5))
print("Independent Python ZIP64, CRC, attachment and human-readable record verification passed.")
