"""Validate the built app, not merely the source configuration."""
from pathlib import Path
import plistlib
import sys

app = Path(sys.argv[1])
info = plistlib.loads((app / "Info.plist").read_bytes())
assert info["CFBundleShortVersionString"] == "3000.0.0"
assert info["UIDeviceFamily"] == [1], "Expected a native iPhone target"
assert info["UILaunchStoryboardName"] == "LaunchScreen"
assert (app / "LaunchScreen.storyboardc").is_dir(), "Compiled launch storyboard missing"
assert "UIApplicationSceneManifest" in info, "SwiftUI scene declaration missing"
assert (app / "Assets.car").is_file(), "Compiled asset catalog missing"
primary = info["CFBundleIcons"]["CFBundlePrimaryIcon"]
assert primary["CFBundleIconName"] == "AppIcon"
assert primary.get("CFBundleIconFiles"), "SpringBoard icon registration missing"
for suffix in ("@2x.png", "@3x.png"):
    assert (app / ("AppIcon60x60" + suffix)).is_file(), f"Home-screen icon {suffix} missing"
for key in ("NSAlarmKitUsageDescription", "NSCalendarsFullAccessUsageDescription", "NSLocationWhenInUseUsageDescription", "NSMicrophoneUsageDescription"):
    assert info.get(key), f"Permission description {key} missing"
print("Verified native iPhone target, compiled launch screen, scenes, 2x/3x icons and permissions.")
