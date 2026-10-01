"""Validate the built app, not merely the source configuration."""
from pathlib import Path
import plistlib
import sys

app = Path(sys.argv[1])
info = plistlib.loads((app / "Info.plist").read_bytes())
assert info["CFBundleShortVersionString"] == "3006.0.0"
assert info["CFBundleIdentifier"] == "eu.rjuhas.therapie", "Existing app identity must be preserved"
assert info["CFBundleVersion"] == "11", "Expected release build number"
assert info["UIDeviceFamily"] == [1], "Expected a native iPhone target"
assert info["UILaunchStoryboardName"] == "LaunchScreen"
assert (app / "LaunchScreen.storyboardc").is_dir(), "Compiled launch storyboard missing"
assert "UIApplicationSceneManifest" in info, "SwiftUI scene declaration missing"
assert (app / "Assets.car").is_file(), "Compiled asset catalog missing"
assert info.get("NSSupportsLiveActivities") is True, "Live Activity capability missing"
assert info.get("UIFileSharingEnabled") is True, "App folder not shared in Files"
assert info.get("LSSupportsOpeningDocumentsInPlace") is True, "Documents provider disabled"
backup_type = next(item for item in info["UTExportedTypeDeclarations"] if item["UTTypeIdentifier"] == "eu.rjuhas.therapie.backup")
assert "therapiebackup" in backup_type["UTTypeTagSpecification"]["public.filename-extension"]
extension = app / "PlugIns" / "TherapieLiveActivity.appex"
assert extension.is_dir(), "Live Activity extension not embedded"
widget = plistlib.loads((extension / "Info.plist").read_bytes())
assert widget["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension"
assert widget["CFBundleIdentifier"] == "eu.rjuhas.therapie.liveactivity"
assert widget["CFBundleShortVersionString"] == info["CFBundleShortVersionString"]
assert (extension / widget["CFBundleExecutable"]).is_file(), "Compiled Live Activity executable missing"
primary = info["CFBundleIcons"]["CFBundlePrimaryIcon"]
assert primary["CFBundleIconName"] == "AppIcon"
assert primary.get("CFBundleIconFiles"), "SpringBoard icon registration missing"
for suffix in ("@2x.png", "@3x.png"):
    assert (app / ("AppIcon60x60" + suffix)).is_file(), f"Home-screen icon {suffix} missing"
for key in ("NSAlarmKitUsageDescription", "NSCalendarsFullAccessUsageDescription", "NSLocationWhenInUseUsageDescription", "NSMicrophoneUsageDescription"):
    assert info.get(key), f"Permission description {key} missing"
print("Verified native iPhone target, compiled launch screen, scenes, 2x/3x icons, permissions and embedded Live Activity extension.")
