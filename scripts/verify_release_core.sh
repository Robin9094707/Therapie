#!/bin/bash
set -euo pipefail
# Compile shared domain code once, then run the four release-critical checks.
CHECK_ROOT=$(mktemp -d /tmp/therapie-core.XXXXXX)
trap 'rm -rf "$CHECK_ROOT"' EXIT
swiftc -parse-as-library -emit-library -emit-module -enable-testing -module-name TherapyDomain \
  TherapieApp/Models.swift TherapieApp/FeatureModels.swift TherapieApp/AIBuddyModels.swift TherapieApp/TherapyDiscussionModels.swift \
  TherapieApp/DashboardModels.swift TherapieApp/ArchiveModels.swift TherapieApp/WellnessModels.swift \
  TherapieApp/TherapyModels.swift TherapieApp/ReminderModels.swift TherapieApp/CompanionModels.swift \
  Shared/WidgetSnapshot.swift TherapieApp/WidgetSnapshotBuilder.swift \
  TherapieApp/InsightsModels.swift TherapieApp/AIBuddyAPI.swift TherapieApp/AIBuddyActions.swift \
  TherapieApp/BackupArchive.swift TherapieApp/ReadableBackup.swift \
  -emit-module-path "$CHECK_ROOT/TherapyDomain.swiftmodule" -o "$CHECK_ROOT/libTherapyDomain.dylib"
for CHECK in ModelChecks BuddyChecks BackupChecks StorageReminderChecks; do
  { echo '@testable import TherapyDomain'; cat "Tests/$CHECK.swift"; } > "$CHECK_ROOT/$CHECK.swift"
  swiftc -parse-as-library -I "$CHECK_ROOT" -L "$CHECK_ROOT" -lTherapyDomain \
    -Xlinker -rpath -Xlinker "$CHECK_ROOT" "$CHECK_ROOT/$CHECK.swift" -o "$CHECK_ROOT/$CHECK"
  "$CHECK_ROOT/$CHECK"
done
python3 scripts/verify_readable_zip.py /tmp/therapie-portable-check.zip
