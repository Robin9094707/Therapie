"""Boot and inspect the actual app without depending on the XCTest UI runner."""
import json
import plistlib
import subprocess
import time
from pathlib import Path

def run(*args, timeout=240, check=True):
    return subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          timeout=timeout, check=check).stdout

listing = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json"))
phones = [d for runtime, devices in listing["devices"].items()
          if "iOS-26" in runtime or "iOS-27" in runtime
          for d in devices if "iPhone" in d["name"]]
assert phones, "No compatible iPhone simulator available"
large = next((d for d in phones if "Pro Max" in d["name"]), phones[0])
compact = next((d for d in phones if "16e" in d["name"] or "17e" in d["name"]),
               next(d for d in phones if d["udid"] != large["udid"]))
app = Path("build-simulator/Build/Products/Debug-iphonesimulator/Therapie.app")
output = Path("build/simulator-verification")
output.mkdir(parents=True, exist_ok=True)

for label, device in [("large", large), ("compact", compact)]:
    identifier = device["udid"]
    print("Inspecting", label, device["name"], flush=True)
    if device["state"] != "Booted":
        run("xcrun", "simctl", "boot", identifier)
    run("xcrun", "simctl", "bootstatus", identifier, "-b")
    run("xcrun", "simctl", "install", identifier, str(app))
    container = Path(run("xcrun", "simctl", "get_app_container", identifier,
                         "eu.rjuhas.therapie", "data").strip())
    report_path = container / "Library/Application Support/TherapieUITests/ui-viewport.json"
    for mode, args, appearance in [
        ("dashboard-light", ["--ui-testing", "--show-dashboard"], "light"),
        ("dashboard-dark", ["--ui-testing", "--show-dashboard"], "dark"),
        ("onboarding-large-text", ["--ui-testing", "--large-text"], "light"),
    ]:
        run("xcrun", "simctl", "terminate", identifier, "eu.rjuhas.therapie", check=False)
        report_path.unlink(missing_ok=True)
        run("xcrun", "simctl", "ui", identifier, "appearance", appearance)
        run("xcrun", "simctl", "launch", identifier, "eu.rjuhas.therapie", *args)
        deadline = time.monotonic() + 40
        while not report_path.is_file() and time.monotonic() < deadline:
            time.sleep(1)
        assert report_path.is_file(), f"App did not report a rendered viewport: {label}/{mode}"
        report = json.loads(report_path.read_text())
        assert report["windowHeight"] > 700, f"Legacy screen height: {report}"
        for axis in ("Width", "Height"):
            assert abs(report["viewport" + axis] - report["window" + axis]) <= 1, report
            assert abs(report["window" + axis] * report["nativeScale"] - report["native" + axis]) <= 3, report
        (output / f"{label}-{mode}.json").write_text(json.dumps(report, indent=2))
        time.sleep(2)
        run("xcrun", "simctl", "io", identifier, "screenshot", str(output / f"{label}-{mode}.png"))
        print("Verified", label, mode, report, flush=True)
    run("xcrun", "simctl", "shutdown", identifier)
print("Native full-screen rendering verified on two iPhone sizes in light/dark mode and large-text onboarding.")
