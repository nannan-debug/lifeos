import Foundation

enum CSVExporter {
    static let bom = "\u{FEFF}"

    static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\n") || field.contains("\r") || field.contains("\"") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    static func row(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    /// 拼出 RFC 4180 风格的 CSV 内容，带 UTF-8 BOM，兼容中文 Excel 直接打开。
    static func makeCSV(header: [String], rows: [[String]]) -> String {
        var lines: [String] = [row(header)]
        lines.append(contentsOf: rows.map(row))
        return bom + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// 把 CSV 文本写到临时目录的指定文件名，返回 URL。
    static func writeToTemporary(name: String, content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        try content.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
}
