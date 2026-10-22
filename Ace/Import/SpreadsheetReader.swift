import Compression
import Foundation

// Reads Ashley's spreadsheet for the Excel import (build step 7): an .xlsx
// file downloaded from Google Sheets or saved by Excel, or a .csv. Plain
// code, no outside libraries: an .xlsx is a zip of XML files.

/// One cell as the import needs it.
struct SheetCell {
    var text = ""
    /// The cell held a number (a price, a check number, a date).
    var number: Double?
    /// The number is shown as a date in the sheet.
    var isDate = false
    /// The cell is filled red: in Ashley's sheet, a price not paid yet.
    var isRed = false
}

/// One tab: rows of cells, each row indexed by column (0 = A).
struct SheetTab {
    var name: String
    var rows: [[Int: SheetCell]]
}

enum SpreadsheetError: LocalizedError {
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let why): return "The file could not be read. \(why)"
        }
    }
}

enum SpreadsheetReader {
    /// Every tab in the file, in order.
    static func read(_ url: URL) throws -> [SheetTab] {
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "csv" {
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw SpreadsheetError.unreadable("It is not plain text.")
            }
            return [SheetTab(name: url.deletingPathExtension().lastPathComponent, rows: CSV.rows(text))]
        }
        return try XLSX.tabs(ZipArchive(data))
    }
}

// MARK: - Zip

/// The files inside a zip archive, read with Apple's Compression library.
struct ZipArchive {
    private var entries: [String: (offset: Int, method: UInt16, compressed: Int, size: Int)] = [:]
    private let data: Data

    init(_ data: Data) throws {
        self.data = data
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        // The end-of-directory record sits in the last 64 KB.
        var end = -1
        var i = bytes.count - 22
        while i >= max(0, bytes.count - 65_557) {
            if u32(i) == 0x0605_4B50 { end = i; break }
            i -= 1
        }
        guard end >= 0 else { throw SpreadsheetError.unreadable("It is not an Excel (.xlsx) file.") }
        let count = u16(end + 10)
        var p = u32(end + 16)
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(p) == 0x0201_4B50 else { break }
            let method = UInt16(u16(p + 10))
            let compressed = u32(p + 20)
            let size = u32(p + 24)
            let nameLength = u16(p + 28)
            let extra = u16(p + 30)
            let comment = u16(p + 32)
            let local = u32(p + 42)
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLength)], as: UTF8.self)
            // The data starts after the local header and its own name and extra field.
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            entries[name] = (start, method, compressed, size)
            p += 46 + nameLength + extra + comment
        }
    }

    func file(_ name: String) -> Data? {
        guard let e = entries[name], e.offset + e.compressed <= data.count else { return nil }
        let raw = data.subdata(in: e.offset..<(e.offset + e.compressed))
        switch e.method {
        case 0:
            return raw
        case 8:
            var out = Data(count: max(e.size, 1))
            let written = out.withUnsafeMutableBytes { dst in
                raw.withUnsafeBytes { src in
                    compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, e.size,
                                              src.bindMemory(to: UInt8.self).baseAddress!, raw.count,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            return written == e.size ? out.prefix(written) : nil
        default:
            return nil
        }
    }
}

// MARK: - xlsx

private enum XLSX {
    static func tabs(_ zip: ZipArchive) throws -> [SheetTab] {
        guard let workbook = zip.file("xl/workbook.xml") else {
            throw SpreadsheetError.unreadable("It is not an Excel (.xlsx) file.")
        }
        let strings = zip.file("xl/sharedStrings.xml").map(SharedStrings.parse) ?? []
        let styles = zip.file("xl/styles.xml").map(Styles.parse) ?? Styles()
        let targets = zip.file("xl/_rels/workbook.xml.rels").map(Relationships.parse) ?? [:]
        return Workbook.parse(workbook).compactMap { sheet in
            let target = targets[sheet.id] ?? ""
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            guard let xml = zip.file(path) else { return nil }
            return SheetTab(name: sheet.name, rows: Worksheet.parse(xml, strings: strings, styles: styles))
        }
    }
}

/// Base for the small XML readers below: collects element text and hands
/// each element's start and end to `start` and `end`.
private class XMLReader: NSObject, XMLParserDelegate {
    var text = ""
    func run(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }
    func start(_ name: String, _ attributes: [String: String]) {}
    func end(_ name: String) {}

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        start(name, attributes)
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        end(name)
    }
}

private final class SharedStrings: XMLReader {
    private var items: [String] = []
    private var inText = false
    private var current = ""

    static func parse(_ data: Data) -> [String] {
        let reader = SharedStrings()
        reader.run(data)
        return reader.items
    }

    override func start(_ name: String, _ attributes: [String: String]) {
        if name == "si" { current = "" }
        if name == "t" { inText = true; text = "" }
    }

    override func end(_ name: String) {
        if name == "t" { current += text; inText = false }
        if name == "si" { items.append(current) }
    }
}

private final class Styles: XMLReader {
    /// For each cell style: is it a date format, and is it filled red.
    private(set) var dateStyles: Set<Int> = []
    private(set) var redStyles: Set<Int> = []
    private var customFormats: [Int: String] = [:]
    private var fills: [Bool] = []
    private var inFill = false
    private var fillIsRed = false
    private var inCellXfs = false
    private var xfIndex = 0

    static func parse(_ data: Data) -> Styles {
        let reader = Styles()
        reader.run(data)
        return reader
    }

    override func start(_ name: String, _ a: [String: String]) {
        switch name {
        case "numFmt":
            if let id = a["numFmtId"].flatMap(Int.init) { customFormats[id] = a["formatCode"] ?? "" }
        case "fill":
            inFill = true; fillIsRed = false
        case "fgColor" where inFill:
            if let rgb = a["rgb"], Self.isRed(rgb) { fillIsRed = true }
        case "cellXfs":
            inCellXfs = true; xfIndex = 0
        case "xf" where inCellXfs:
            let format = a["numFmtId"].flatMap(Int.init) ?? 0
            if Self.isDateFormat(format, custom: customFormats[format]) { dateStyles.insert(xfIndex) }
            if let fill = a["fillId"].flatMap(Int.init), fill < fills.count, fills[fill] { redStyles.insert(xfIndex) }
            xfIndex += 1
        default:
            break
        }
    }

    override func end(_ name: String) {
        if name == "fill" { fills.append(fillIsRed); inFill = false }
        if name == "cellXfs" { inCellXfs = false }
    }

    /// "FFFF0000", "FFEA4335": strong red, little green or blue.
    static func isRed(_ argb: String) -> Bool {
        let hex = argb.count == 8 ? String(argb.dropFirst(2)) : argb
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return false }
        let r = (value >> 16) & 0xFF, g = (value >> 8) & 0xFF, b = value & 0xFF
        return r >= 180 && g <= 110 && b <= 110
    }

    static func isDateFormat(_ id: Int, custom: String?) -> Bool {
        if (14...22).contains(id) || (45...47).contains(id) { return true }
        guard let code = custom?.lowercased() else { return false }
        // Quoted text and [colour] parts are not date letters.
        let plain = code
            .replacingOccurrences(of: "\"[^\"]*\"", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        return plain.contains("d") || plain.contains("y") || (plain.contains("m") && !plain.contains("0"))
    }
}

private final class Relationships: XMLReader {
    private var map: [String: String] = [:]

    static func parse(_ data: Data) -> [String: String] {
        let reader = Relationships()
        reader.run(data)
        return reader.map
    }

    override func start(_ name: String, _ a: [String: String]) {
        if name == "Relationship", let id = a["Id"], let target = a["Target"] { map[id] = target }
    }
}

private final class Workbook: XMLReader {
    private var sheets: [(name: String, id: String)] = []

    static func parse(_ data: Data) -> [(name: String, id: String)] {
        let reader = Workbook()
        reader.run(data)
        return reader.sheets
    }

    override func start(_ name: String, _ a: [String: String]) {
        if name == "sheet", let sheetName = a["name"], let id = a["r:id"] ?? a.first(where: { $0.key.hasSuffix(":id") })?.value {
            sheets.append((sheetName, id))
        }
    }
}

private final class Worksheet: XMLReader {
    private var rows: [[Int: SheetCell]] = []
    private var row: [Int: SheetCell] = [:]
    private var rowNumber = 0
    private var column = 0
    private var type = ""
    private var style = 0
    private var value = ""
    private var inline = ""
    private var strings: [String] = []
    private var styles = Styles()

    static func parse(_ data: Data, strings: [String], styles: Styles) -> [[Int: SheetCell]] {
        let reader = Worksheet()
        reader.strings = strings
        reader.styles = styles
        reader.run(data)
        return reader.rows
    }

    override func start(_ name: String, _ a: [String: String]) {
        switch name {
        case "row":
            row = [:]
            // Empty rows are left out of the file: keep the numbering.
            if let r = a["r"].flatMap(Int.init) {
                while rows.count < r - 1 { rows.append([:]) }
                rowNumber = r
            }
        case "c":
            type = a["t"] ?? ""
            style = a["s"].flatMap(Int.init) ?? 0
            column = a["r"].map(Self.columnIndex) ?? row.count
            value = ""; inline = ""
        case "v", "t":
            text = ""
        default:
            break
        }
    }

    override func end(_ name: String) {
        switch name {
        case "v":
            value = text
        case "t":
            inline += text
        case "c":
            var cell = SheetCell()
            cell.isRed = styles.redStyles.contains(style)
            switch type {
            case "s":
                cell.text = Int(value).flatMap { $0 < strings.count ? strings[$0] : nil } ?? ""
            case "inlineStr":
                cell.text = inline
            case "str", "e":
                cell.text = value
            case "b":
                cell.text = value == "1" ? "TRUE" : "FALSE"
            default:
                cell.number = Double(value)
                cell.text = value
                cell.isDate = cell.number != nil && styles.dateStyles.contains(style)
            }
            cell.text = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cell.text.isEmpty || cell.isRed { row[column] = cell }
        case "row":
            rows.append(row)
        default:
            break
        }
    }

    /// "B12" → 1.
    static func columnIndex(_ ref: String) -> Int {
        var index = 0
        for ch in ref.uppercased() {
            guard let ascii = ch.asciiValue, ascii >= 65, ascii <= 90 else { break }
            index = index * 26 + Int(ascii - 64)
        }
        return max(index - 1, 0)
    }
}

// MARK: - csv

private enum CSV {
    static func rows(_ text: String) -> [[Int: SheetCell]] {
        var rows: [[Int: SheetCell]] = []
        var row: [Int: SheetCell] = [:]
        var field = ""
        var quoted = false
        var column = 0
        var chars = Array(text)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        func endField() {
            let value = field.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { row[column] = SheetCell(text: value, number: Double(value.replacingOccurrences(of: ",", with: ""))) }
            field = ""; column += 1
        }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" {
                quoted = true
            } else if c == "," {
                endField()
            } else if c == "\n" || c == "\r" {
                if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                endField(); rows.append(row); row = [:]; column = 0
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { endField(); rows.append(row) }
        return rows
    }
}
