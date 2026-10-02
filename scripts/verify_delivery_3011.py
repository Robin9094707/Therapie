import hashlib, json, plistlib, subprocess, sys, zipfile
from pathlib import Path
sha = "aa58218b36b83bd9352b2e782775351491e7e9cd"
old = "18c47210d698e8247551b8718a9d203d6517807c"
run = json.loads(Path("verified-run.json").read_text())
assert run["conclusion"] == "success" and run["status"] == "completed" and run["head_sha"] == sha
root = Path("delivery")
source = root / "Therapie-v3011.0.0-source.zip"
previous = root / "Therapie-v3010.0.0-vor-gefuehrten-Gespraechen-source.zip"
ipa = root / "Therapie-v3011.0.0.ipa"
for path, commit in [(source, sha), (previous, old)]:
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        assert archive.comment.decode() == commit
with zipfile.ZipFile(source) as archive:
    Path("validate-delivered-bundle.py").write_bytes(archive.read("scripts/validate_bundle.py"))
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None
    assert all(not name.startswith("/") and ".." not in Path(name).parts for name in archive.namelist())
    archive.extractall("verified-ipa")
app = Path("verified-ipa/Payload/Therapie.app")
subprocess.run([sys.executable, "validate-delivered-bundle.py", str(app)], check=True)
with (app / "Info.plist").open("rb") as file:
    info = plistlib.load(file)
assert info["CFBundleVersion"] == "18"
status = json.loads(Path("ui/status.json").read_text())
assert status["status"] == "passed", "The focused simulator checks must really have run"
log = Path("ui/test.log").read_text()
assert "Executed 2 tests, with 0 failures" in log
for name in ["testChatSendWithKeyboardNewChatAndReopen", "testGuidedAIKeepsDraftWhenSwitchingToNormal"]:
    assert any(name in line and " passed " in line for line in log.splitlines())
for path in [previous, source, ipa]:
    print(path.name, path.stat().st_size, hashlib.sha256(path.read_bytes()).hexdigest())
print("Verified exact commits, ZIP CRC, delivered IPA identity/build/extension and both actual simulator tests.")
