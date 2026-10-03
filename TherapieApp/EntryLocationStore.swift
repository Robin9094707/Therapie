import Foundation
import CoreLocation
import UIKit

extension AppStore {
    func captureLocations(from previous: AppData) {
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing"), data.captureEntryLocation != false, UIApplication.shared.applicationState == .active, storageReady, !undoInProgress else { return }
        guard EntryLocator.count(previous) != EntryLocator.count(data) else { return }
        let before = EntryLocator.recordIDs(previous), after = EntryLocator.recordIDs(data)
        let added = after.subtracting(before)
        guard !added.isEmpty else { return }
        for id in added where (data.preferences.includeLocationForNewMedia || !id.hasPrefix("media-")) && !data.entryLocations.contains(where: { $0.id == id }) { pendingLocationRecords[id] = Date() }
        entryLocationService.requestCurrentLocation()
    }
    func attachLocation(_ location: CLLocation) {
        let now = Date()
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing"), data.captureEntryLocation != false, storageReady, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 2000, abs(now.timeIntervalSince(location.timestamp)) < 60 else { return }
        let validIDs = EntryLocator.recordIDs(data)
        var snapshot = data
        for (id, requested) in pendingLocationRecords where now.timeIntervalSince(requested) < 90 && location.timestamp >= requested.addingTimeInterval(-60) && validIDs.contains(id) && !snapshot.entryLocations.contains(where: { $0.id == id }) {
            snapshot.entryLocations.append(EntryLocation(id: id, capturedAt: location.timestamp, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, accuracy: location.horizontalAccuracy))
        }
        pendingLocationRecords.removeAll()
        if snapshot != data { data = snapshot }
    }
}
