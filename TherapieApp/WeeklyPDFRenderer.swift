import Foundation
import CoreGraphics
import ImageIO
#if canImport(UIKit)
import UIKit
private typealias ReportFont = UIFont
private typealias ReportColor = UIColor
#else
import AppKit
private typealias ReportFont = NSFont
private typealias ReportColor = NSColor
#endif

struct ReportPhoto {
    let url: URL?
    let caption: String
}
struct WeeklyPDFResult {
    let url: URL
    let pages: Int
    let omittedRows: Int
    let shortenedRows: Int
    let missingPhotos: Int
}
enum WeeklyPDFRenderer {
    enum Failure: Error { case cannotCreate }
    static let pageSize = CGSize(width: 595.28, height: 841.89)
    static func render(_ plan: WeeklyPrintPlan, photos: [ReportPhoto], to url: URL) throws -> WeeklyPDFResult {
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, [kCGPDFContextTitle: "Meine Therapiewoche"] as CFDictionary) else { throw Failure.cannotCreate }
        let width: CGFloat = 507, left: CGFloat = 44
        let ink = ReportColor(red: 0.12, green: 0.15, blue: 0.24, alpha: 1)
        let subtle = ReportColor(red: 0.37, green: 0.40, blue: 0.47, alpha: 1)
        let accent = CGColor(red: 0.28, green: 0.32, blue: 0.64, alpha: 1)
        func attributes(_ size: CGFloat, bold: Bool = false, color: ReportColor? = nil) -> [NSAttributedString.Key: Any] {
            let style = NSMutableParagraphStyle(); style.lineSpacing = 2; style.lineBreakMode = .byWordWrapping
            return [.font: ReportFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: color ?? ink, .paragraphStyle: style]
        }
        func draw(_ text: String, _ rect: CGRect, size: CGFloat = 11, bold: Bool = false, color: ReportColor? = nil) {
            (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(size, bold: bold, color: color), context: nil)
        }
        func height(_ text: String, width: CGFloat, size: CGFloat, bold: Bool = false) -> CGFloat {
            ceil((text as NSString).boundingRect(with: CGSize(width: width, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(size, bold: bold), context: nil).height)
        }
        func shorten(_ text: String, to maxHeight: CGFloat, width: CGFloat, size: CGFloat, bold: Bool = false) -> (String, Bool) {
            let clean = text.replacingOccurrences(of: "\r", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard height(clean, width: width, size: size, bold: bold) > maxHeight else { return (clean, false) }
            var low = 0, high = min(clean.count, 2000)
            while low < high {
                let middle = (low + high + 1) / 2
                if height(String(clean.prefix(middle)) + " …", width: width, size: size, bold: bold) <= maxHeight { low = middle } else { high = middle - 1 }
            }
            return (String(clean.prefix(low)) + " …", true)
        }
        var index = 0, page = 0, shortened = 0, missingPhotos = 0, previousSection = ""
        let chosenPhotos = Array(photos.prefix(3))
        repeat {
            page += 1; context.beginPDFPage(nil)
            context.saveGState(); context.translateBy(x: 0, y: pageSize.height); context.scaleBy(x: 1, y: -1)
            #if canImport(UIKit)
            UIGraphicsPushContext(context)
            #else
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            #endif
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box)
            context.setFillColor(accent); context.fill(CGRect(x: left, y: 36, width: 36, height: 4))
            draw("MEINE THERAPIEWOCHE", CGRect(x: left, y: 52, width: width, height: 28), size: 19, bold: true)
            let name = plan.name.isEmpty ? "" : " · " + String(plan.name.prefix(65))
            draw(WeeklyPrintDateFormat.day(plan.period.start) + " – " + WeeklyPrintDateFormat.day(plan.period.end.addingTimeInterval(-1)) + name, CGRect(x: left, y: 84, width: width, height: 34), size: 10, color: subtle)
            var y: CGFloat = 130
            if page == 1 {
                draw(plan.summary, CGRect(x: left, y: y, width: width, height: 32), size: 12, bold: true); y += 40
                let plotted = plan.daily.filter { $0.mood != nil || $0.battery != nil }
                if !plotted.isEmpty {
                    draw("Tagesmittel · Stimmung (Indigo) / Akku (Türkis), auf Skala 1–5", CGRect(x: left, y: y, width: width, height: 20), size: 9, color: subtle); y += 24
                    let chart = CGRect(x: left + 22, y: y, width: width - 30, height: 68)
                    for value in 1...5 {
                        let gy = chart.maxY - CGFloat(value - 1) / 4 * chart.height
                        context.setStrokeColor(CGColor(gray: 0.88, alpha: 1)); context.setLineWidth(0.5); context.move(to: CGPoint(x: chart.minX, y: gy)); context.addLine(to: CGPoint(x: chart.maxX, y: gy)); context.strokePath()
                        draw("\(value)", CGRect(x: left, y: gy - 6, width: 18, height: 14), size: 8, color: subtle)
                    }
                    for (metric, color) in [(true, accent), (false, CGColor(red: 0.1, green: 0.52, blue: 0.48, alpha: 1))] {
                        var last: CGPoint?, lastDay: Int?
                        for row in plotted {
                            let day = Calendar.therapyCalendar.dateComponents([.day], from: plan.period.start, to: row.date).day ?? 0
                            guard let value = metric ? row.mood : row.battery else { last = nil; lastDay = nil; continue }
                            let point = CGPoint(x: chart.minX + CGFloat(day) / 6 * chart.width, y: chart.maxY - CGFloat(max(1, min(5, value)) - 1) / 4 * chart.height)
                            context.setStrokeColor(color); context.setFillColor(color); context.setLineWidth(1.8)
                            if let last, let lastDay, day - lastDay == 1 { context.move(to: last); context.addLine(to: point); context.strokePath() }
                            context.fillEllipse(in: CGRect(x: point.x - 2.7, y: point.y - 2.7, width: 5.4, height: 5.4)); last = point; lastDay = day
                        }
                    }
                    for day in 0..<7 {
                        let date = Calendar.therapyCalendar.date(byAdding: .day, value: day, to: plan.period.start)!
                        draw(WeeklyPrintDateFormat.weekday(date), CGRect(x: chart.minX + CGFloat(day) / 6 * chart.width - 12, y: chart.maxY + 8, width: 30, height: 16), size: 8, color: subtle)
                    }
                    y += 108
                }
            }
            let bottom: CGFloat = chosenPhotos.isEmpty ? 753 : 584
            var firstRow = true
            while index < plan.rows.count {
                let row = plan.rows[index]
                let sectionHeight: CGFloat = firstRow || row.section != previousSection ? 26 : 0
                let (title, titleCut) = shorten(row.title, to: 32, width: width, size: 11, bold: true)
                let (body, bodyCut) = shorten(row.text, to: 47, width: width, size: 10)
                let titleHeight = height(title, width: width, size: 11, bold: true)
                let bodyHeight = body.isEmpty ? 0 : height(body, width: width, size: 10)
                let total = sectionHeight + titleHeight + bodyHeight + (body.isEmpty ? 0 : 5) + 13
                if y + total > bottom { break }
                if sectionHeight > 0 {
                    draw(row.section.uppercased(), CGRect(x: left, y: y + 5, width: width, height: 20), size: 9, bold: true, color: subtle); y += 26
                }
                draw(title, CGRect(x: left, y: y, width: width, height: titleHeight + 1), bold: true); y += titleHeight + 5
                if !body.isEmpty { draw(body, CGRect(x: left, y: y, width: width, height: bodyHeight + 1), size: 10); y += bodyHeight }
                y += 13; if titleCut || bodyCut { shortened += 1 }
                previousSection = row.section; firstRow = false; index += 1
            }
            if plan.rows.isEmpty && page == 1 { draw("Keine Einträge in den ausgewählten Bereichen dieser Woche.", CGRect(x: left, y: y, width: width, height: 35), color: subtle) }
            if !chosenPhotos.isEmpty && (index == plan.rows.count || page == plan.maxPages) {
                draw("AUSGEWÄHLTE BILDER", CGRect(x: left, y: 602, width: width, height: 20), size: 9, bold: true, color: subtle)
                let cellWidth = (width - 20) / CGFloat(chosenPhotos.count)
                for (offset, photo) in chosenPhotos.enumerated() {
                    let frame = CGRect(x: left + CGFloat(offset) * (cellWidth + 10), y: 627, width: cellWidth, height: 105)
                    context.setFillColor(CGColor(gray: 0.96, alpha: 1)); context.fill(frame)
                    if let url = photo.url, let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 700] as CFDictionary) {
                        let ratio = min(frame.width / CGFloat(image.width), frame.height / CGFloat(image.height))
                        let size = CGSize(width: CGFloat(image.width) * ratio, height: CGFloat(image.height) * ratio)
                        let rect = CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
                        context.saveGState(); context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1); context.draw(image, in: CGRect(origin: .zero, size: size)); context.restoreGState()
                    } else { missingPhotos += 1; draw("Bild nicht verfügbar", frame.insetBy(dx: 8, dy: 15), size: 9, color: subtle) }
                    let caption = shorten(photo.caption, to: 26, width: cellWidth, size: 8).0
                    draw(caption, CGRect(x: frame.minX, y: 739, width: cellWidth, height: 27), size: 8, color: subtle)
                }
            }
            let last = page == plan.maxPages || index == plan.rows.count
            let omitted = last ? plan.rows.count - index : 0
            let status = omitted > 0 || shortened > 0 ? "Kurzbericht · \(shortened) Texte gekürzt · \(omitted) weitere Einträge nicht abgedruckt." : "Selbstbericht · Tagesmittel nur aus Angaben · fehlende Tage bleiben offen."
            draw(status, CGRect(x: left, y: 786, width: width - 32, height: 15), size: 8, color: subtle)
            draw("Routinen: eigene Bestätigungen. Aufgaben und Ziele: heutiger Stand.", CGRect(x: left, y: 802, width: width - 30, height: 14), size: 8, color: subtle)
            draw("\(page)", CGRect(x: pageSize.width - 55, y: 796, width: 20, height: 16), size: 9, color: subtle)
            #if canImport(UIKit)
            UIGraphicsPopContext()
            #else
            NSGraphicsContext.restoreGraphicsState()
            #endif
            context.restoreGState(); context.endPDFPage()
            if last { break }
        } while page < plan.maxPages
        context.closePDF()
        return .init(url: url, pages: page, omittedRows: plan.rows.count - index, shortenedRows: shortened, missingPhotos: missingPhotos)
    }
}
