import CryptoKit
import Foundation
import RefereeLedger
import UIKit

enum SignedReportFileExporter {
    struct Result {
        let url: URL
        let checksum: String
        let generatedAt: Date
    }

    static func export(_ snapshot: SignedReportExportSnapshot, format: ReportExportFormat,
                       directory: URL) throws -> Result {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let generatedAt = Date()
        let data: Data
        switch format {
        case .pdf: data = PDFReportRenderer.render(snapshot, generatedAt: generatedAt)
        case .xlsx: data = try XLSXReportRenderer.render(snapshot, generatedAt: generatedAt)
        }
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let status = snapshot.report.status == .current ? "current" : "superseded"
        let unique = UUID().uuidString.prefix(8).lowercased()
        let base = "\(snapshot.report.kind.rawValue)-report-v\(snapshot.report.version)-\(status)-\(Int(generatedAt.timeIntervalSince1970 * 1_000))-\(unique)"
        let finalURL = directory.appendingPathComponent(base).appendingPathExtension(format.rawValue)
        let stagingURL = directory.appendingPathComponent(".\(UUID().uuidString).staging")
        do {
            try data.write(to: stagingURL, options: .atomic)
            try FileManager.default.moveItem(at: stagingURL, to: finalURL)
        } catch {
            try? FileManager.default.removeItem(at: stagingURL)
            throw error
        }
        return Result(url: finalURL, checksum: checksum, generatedAt: generatedAt)
    }
}

private enum PDFReportRenderer {
    static func render(_ snapshot: SignedReportExportSnapshot, generatedAt: Date) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            var y: CGFloat = 42
            func newPage() { context.beginPage(); y = 42 }
            func line(_ text: String, font: UIFont = .systemFont(ofSize: 10), colour: UIColor = .label,
                      spacing: CGFloat = 5) {
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
                let box = CGRect(x: 42, y: y, width: page.width - 84, height: 100)
                let height = (text as NSString).boundingRect(with: box.size, options: [.usesLineFragmentOrigin],
                                                              attributes: attributes, context: nil).height
                if y + height > page.height - 48 { newPage() }
                (text as NSString).draw(in: CGRect(x: 42, y: y, width: page.width - 84, height: height + 2),
                                        withAttributes: attributes)
                y += height + spacing
            }

            newPage()
            let report = snapshot.report
            let status = report.status == .current ? "SIGNED — CURRENT" : "SIGNED — SUPERSEDED"
            line(report.kind.rawValue.uppercased() + " REPORT", font: .boldSystemFont(ofSize: 22), spacing: 10)
            line(status, font: .boldSystemFont(ofSize: 13),
                 colour: report.status == .current ? .systemGreen : .systemOrange, spacing: 14)
            line("\(snapshot.fixture.homeTeamName)  \(report.validation.projectedScore.home) – \(report.validation.projectedScore.away)  \(snapshot.fixture.awayTeamName)",
                 font: .boldSystemFont(ofSize: 17), spacing: 10)
            line("Competition: \(snapshot.fixture.competition)")
            line("Venue: \(snapshot.fixture.venueName)")
            line("Scheduled: \(snapshot.fixture.scheduledAt.formatted(date: .long, time: .shortened))")
            line("Match ID: \(snapshot.fixture.matchID.uuidString)")
            line("Report version: \(report.version)  •  Content: \(report.contentVersion)  •  Template: \(report.templateVersion)")
            line("Signed: \(report.signedAt.formatted(date: .long, time: .standard)) by \(report.signer.displayName)")
            line("Generated: \(generatedAt.formatted(date: .long, time: .standard))", spacing: 14)
            line("REFEREE DECLARATION", font: .boldSystemFont(ofSize: 12), spacing: 6)
            line(report.declaration, spacing: 14)
            line("EVENT TIMELINE", font: .boldSystemFont(ofSize: 12), spacing: 8)
            if snapshot.events.isEmpty { line("No active projected events.", colour: .secondaryLabel) }
            for event in snapshot.events {
                let clock = event.effectiveMatchClockMs.map(formatClock) ?? "—"
                let detail = eventSummary(event)
                line("\(clock)  \(event.effectiveEventType.replacingOccurrences(of: "_", with: " ").uppercased())",
                     font: .boldSystemFont(ofSize: 10), spacing: 3)
                if !detail.isEmpty { line(detail, colour: .secondaryLabel, spacing: 3) }
                line("Event \(event.id.uuidString)" + (event.revisionOfEventID.map { "  •  revises \($0.uuidString)" } ?? ""),
                     font: .systemFont(ofSize: 8), colour: .tertiaryLabel, spacing: 7)
            }
            line("ATTACHMENTS", font: .boldSystemFont(ofSize: 12), spacing: 8)
            if snapshot.attachments.isEmpty { line("No attachments.", colour: .secondaryLabel) }
            for attachment in snapshot.attachments {
                line("\(attachment.originalFilename)  •  \(attachment.mediaType)  •  \(attachment.byteCount) bytes" +
                     (attachment.isRequired ? "  •  REQUIRED" : ""), font: .boldSystemFont(ofSize: 9), spacing: 3)
                line("SHA-256 \(attachment.checksum)", font: .systemFont(ofSize: 7),
                     colour: .tertiaryLabel, spacing: 6)
            }
            line("Source fingerprint: \(report.sourceFingerprint)", font: .systemFont(ofSize: 7),
                 colour: .tertiaryLabel)
        }
    }

    private static func formatClock(_ milliseconds: Int64) -> String {
        String(format: "%02lld:%02lld", milliseconds / 60_000, (milliseconds / 1_000) % 60)
    }

    private static func eventSummary(_ event: ReportExportEvent) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: Data(event.payloadJSON.utf8)) as? [String: Any] else {
            return event.payloadJSON
        }
        return [object["teamSide"], object["participantDisplayName"], object["colour"],
                object["disciplinaryReason"], object["cause"]]
            .compactMap { $0 as? String }.joined(separator: " • ")
    }
}

private enum XLSXReportRenderer {
    static func render(_ snapshot: SignedReportExportSnapshot, generatedAt: Date) throws -> Data {
        let files: [(String, Data)] = [
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(rootRelationships.utf8)),
            ("xl/workbook.xml", Data(workbook.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(workbookRelationships.utf8)),
            ("xl/styles.xml", Data(styles.utf8)),
            ("xl/worksheets/sheet1.xml", Data(sheet(snapshot, generatedAt: generatedAt).utf8))
        ]
        return StoredZIP.archive(files)
    }

    private static func sheet(_ snapshot: SignedReportExportSnapshot, generatedAt: Date) -> String {
        let headers = ["Match ID", "Report Kind", "Report Version", "Content Version", "Template Version", "Status",
                       "Signed At", "Generated At", "Event ID", "Source Event Type", "Effective Event Type",
                       "Recorded At", "Original Clock ms", "Effective Clock ms", "Revision Of Event ID",
                       "Team Side", "Participant", "Card Colour", "Disciplinary Reason", "Normalized X",
                       "Normalized Y", "Metres X", "Metres Y", "Pitch Length", "Pitch Width",
                       "Capture Method", "Accuracy", "Payload JSON", "Frozen Attachments JSON"]
        let report = snapshot.report
        let status = report.status == .current ? "SIGNED — CURRENT" : "SIGNED — SUPERSEDED"
        let metadata = [snapshot.fixture.matchID.uuidString, report.kind.rawValue, String(report.version),
                        String(report.contentVersion), report.templateVersion, status,
                        iso(report.signedAt), iso(generatedAt)]
        var rows: [[String]] = [headers]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let attachmentsJSON = (try? String(decoding: encoder.encode(snapshot.attachments), as: UTF8.self)) ?? "[]"
        let events: [ReportExportEvent?] = snapshot.events.isEmpty ? [nil] : snapshot.events.map(Optional.some)
        for event in events {
            let object = event.flatMap { try? JSONSerialization.jsonObject(with: Data($0.payloadJSON.utf8)) as? [String: Any] } ?? [:]
            let location = object["location"] as? [String: Any] ?? object
            var row = metadata
            row.append(contentsOf: [event?.id.uuidString ?? "", event?.sourceEventType ?? "",
                                    event?.effectiveEventType ?? "", event.map { iso($0.recordedAt) } ?? ""])
            row.append(event?.originalMatchClockMs.map(String.init) ?? "")
            row.append(event?.effectiveMatchClockMs.map(String.init) ?? "")
            row.append(event?.revisionOfEventID?.uuidString ?? "")
            row.append(contentsOf: [string(object["teamSide"]), string(object["participantDisplayName"]),
                                    string(object["colour"]), string(object["disciplinaryReason"])])
            row.append(contentsOf: [string(location["normalizedX"]), string(location["normalizedY"]),
                                    string(location["metresX"]), string(location["metresY"]),
                                    string(location["pitchLength"]), string(location["pitchWidth"]),
                                    string(location["captureMethod"]), string(location["accuracy"]),
                                    event?.payloadJSON ?? "", attachmentsJSON])
            rows.append(row)
        }
        let xmlRows = rows.enumerated().map { rowIndex, values in
            let cells = values.enumerated().map { columnIndex, value in
                let reference = columnName(columnIndex + 1) + String(rowIndex + 1)
                let style = rowIndex == 0 ? " s=\"1\"" : ""
                return "<c r=\"\(reference)\" t=\"inlineStr\"\(style)><is><t xml:space=\"preserve\">\(xml(value))</t></is></c>"
            }.joined()
            return "<row r=\"\(rowIndex + 1)\">\(cells)</row>"
        }.joined()
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight=\"15\"/><sheetData>\(xmlRows)</sheetData><autoFilter ref=\"A1:AC\(rows.count)\"/></worksheet>"
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }
    private static func xml(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
    private static func columnName(_ number: Int) -> String {
        var number = number, result = ""
        while number > 0 { number -= 1; result = String(UnicodeScalar(65 + number % 26)!) + result; number /= 26 }
        return result
    }

    private static let contentTypes = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/></Types>"
    private static let rootRelationships = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"
    private static let workbook = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Events\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"
    private static let workbookRelationships = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"
    private static let styles = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Aptos\"/></font><font><b/><sz val=\"11\"/><color rgb=\"FFFFFFFF\"/><name val=\"Aptos\"/></font></fonts><fills count=\"3\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill><fill><patternFill patternType=\"solid\"><fgColor rgb=\"FF1F4E78\"/><bgColor indexed=\"64\"/></patternFill></fill></fills><borders count=\"1\"><border/></borders><cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs><cellXfs count=\"2\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/><xf numFmtId=\"0\" fontId=\"1\" fillId=\"2\" borderId=\"0\" xfId=\"0\" applyFont=\"1\" applyFill=\"1\"/></cellXfs></styleSheet>"
}

private enum StoredZIP {
    private struct CentralEntry { let name: Data; let crc: UInt32; let size: UInt32; let offset: UInt32 }

    static func archive(_ files: [(String, Data)]) -> Data {
        var output = Data(), central: [CentralEntry] = []
        for (path, contents) in files {
            let name = Data(path.utf8), crc = crc32(contents), offset = UInt32(output.count), size = UInt32(contents.count)
            output.appendLE(UInt32(0x04034b50)); output.appendLE(UInt16(20)); output.appendLE(UInt16(0x0800))
            output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
            output.appendLE(crc); output.appendLE(size); output.appendLE(size)
            output.appendLE(UInt16(name.count)); output.appendLE(UInt16(0)); output.append(name); output.append(contents)
            central.append(CentralEntry(name: name, crc: crc, size: size, offset: offset))
        }
        let centralOffset = UInt32(output.count)
        for entry in central {
            output.appendLE(UInt32(0x02014b50)); output.appendLE(UInt16(20)); output.appendLE(UInt16(20))
            output.appendLE(UInt16(0x0800)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
            output.appendLE(entry.crc); output.appendLE(entry.size); output.appendLE(entry.size)
            output.appendLE(UInt16(entry.name.count)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
            output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt32(0)); output.appendLE(entry.offset)
            output.append(entry.name)
        }
        let centralSize = UInt32(output.count) - centralOffset
        output.appendLE(UInt32(0x06054b50)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
        output.appendLE(UInt16(central.count)); output.appendLE(UInt16(central.count))
        output.appendLE(centralSize); output.appendLE(centralOffset); output.appendLE(UInt16(0))
        return output
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xedb88320 & (0 &- (crc & 1))) }
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
