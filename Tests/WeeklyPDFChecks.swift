import Foundation
import AppKit
import PDFKit

@main struct WeeklyPDFChecks {
    enum Failure: Error { case assertion(String) }
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws { count += 1; if !value() { throw Failure.assertion(message) } }
    static func main() throws {
        NSTimeZone.default = TimeZone(identifier: "Europe/Berlin")!
        let now = ISO8601DateFormatter().date(from: "2026-09-30T12:00:00Z")!
        let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/therapie-pdf-fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var data = AppData(); data.profile.userName = "Robin"
        for offset in 0..<7 {
            let day = Calendar.therapyCalendar.date(byAdding: .day, value: offset, to: now.therapyWeekStart)!
            data.moodCheckIns.append(MoodCheckIn(date: day, mood: 2 + offset % 4, battery: 2 + offset % 3, moodPercent: 35 + offset * 8))
            data.batteryPoints.append(BatteryPoint(date: day, title: offset % 2 == 0 ? "Technik" : "Spaziergang", direction: .gives, note: "Ein ruhiger Moment, der meinem Akku gutgetan hat."))
            data.batteryPoints.append(BatteryPoint(date: day, title: "Lärm", direction: .takes, note: "Ich brauche eine Pause, wenn zu viele Reize zusammenkommen."))
            data.guidedCheckIns.append(GuidedCheckIn(date: day, kind: .evening, mood: 4, batteryPercent: 60, summary: "Heute habe ich mir Zeit für eine kleine Pause genommen.", smallWin: "Frühstück vorbereitet", nextNeed: "Etwas Ruhe und weniger Termine", therapyQuestion: "Wie kann ich meine Pausen leichter einplanen?", isDraft: false, moodPercent: 73))
        }
        let week = now.therapyWeek
        data.weeklyTasks = [WeeklyTask(createdAt: now, weekOfYear: week.week, yearForWeekOfYear: week.year, title: "Frühstück für die Arbeit vorbereiten", details: "Abends eine Kleinigkeit bereitlegen", smallStep: "Brot aus dem Schrank nehmen")]
        data.therapyGoals = [TherapyGoal(title: "Einen ruhigeren Morgen gestalten", progress: 35, smallStep: "Am Vorabend vorbereiten")]
        data.notes = [TherapyNote(createdAt: now, title: "Für den nächsten Termin", text: String(repeating: "Was mir diese Woche geholfen hat: Musik, ein Spaziergang und Zeit für mein Hobby. ", count: 18), tags: [], isImportant: true)]
        let image = NSImage(size: NSSize(width: 640, height: 400)); image.lockFocus(); NSColor.systemTeal.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 640, height: 400)).fill(); ("Ein ruhiger Moment" as NSString).draw(at: NSPoint(x: 90, y: 180), withAttributes: [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.white]); image.unlockFocus()
        let imageURL = directory.appendingPathComponent("fixture-photo.png")
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!; try bitmap.representation(using: .png, properties: [:])!.write(to: imageURL)
        for limit in 1...3 {
            let options = WeeklyPrintOptions(weekStart: now, maxPages: limit)
            let plan = WeeklyPrintPlan.make(data: data, options: options)
            let url = directory.appendingPathComponent("Therapiewoche-\(limit)-Seiten.pdf")
            let result = try WeeklyPDFRenderer.render(plan, photos: [ReportPhoto(url: imageURL, caption: "Mein ausgewähltes Bild · ein ruhiger Moment")], to: url)
            guard let pdf = PDFDocument(url: url) else { throw Failure.assertion("Unreadable PDF") }
            try expect(pdf.pageCount == limit && result.pages == limit, "Strict 1–3 page cap and actual PDF count")
            try expect(result.missingPhotos == 0, "Selected image decoded")
            try expect(pdf.string?.contains("MEINE THERAPIEWOCHE") == true && pdf.string?.contains("Robin") == true, "Title and selected profile rendered as text")
            try expect(pdf.string?.contains("AUSGEWÄHLTE BILDER") == true, "Photo section included")
            if limit == 1 { try expect(result.omittedRows > 0, "Omitted entries visibly counted in compact report") }
            for index in 0..<pdf.pageCount {
                let page = pdf.page(at: index)!, bounds = page.bounds(for: .mediaBox)
                try expect(abs(bounds.width - 595.28) < 0.1 && abs(bounds.height - 841.89) < 0.1, "A4 page size")
                let preview = page.thumbnail(of: NSSize(width: 1191, height: 1684), for: .mediaBox)
                let png = NSBitmapImageRep(data: preview.tiffRepresentation!)!.representation(using: .png, properties: [:])!
                try png.write(to: directory.appendingPathComponent("Therapiewoche-\(limit)-Seiten-\(index + 1).png"))
            }
        }
        var options = WeeklyPrintOptions(weekStart: now, includeName: false, includeMood: false, includeBattery: false, includeCheckIns: false, includeTasks: false, includeGoals: false, includeRoutines: false, includeNotes: false)
        options.maxPages = 1
        let empty = WeeklyPrintPlan.make(data: data, options: options)
        let privateURL = directory.appendingPathComponent("Nur-gewaehlte-Bereiche.pdf")
        _ = try WeeklyPDFRenderer.render(empty, photos: [], to: privateURL)
        let text = PDFDocument(url: privateURL)?.string ?? ""
        try expect(!text.contains("Robin") && !text.contains("Frühstück") && !text.contains("Hobby"), "Actual PDF respects content opt-outs")
        print("Passed \(count) native PDF rendering, A4, page limit, image and privacy checks. Fixtures: \(directory.path)")
    }
}
