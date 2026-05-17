import Foundation

/// 把 LifeOS 核心数据打包成带版本的 JSON 备份文件。
/// UserDefaults 里多数值是 JSON 原生类型；Data（如第二大脑）以 base64 字符串存，
/// 并在信封的 base64Keys 里登记，便于完整还原。
enum DataArchive {
    static let formatTag = "lifeos-backup"
    static let version = 1

    /// payload 的 key 用稳定的基础键名（不含 userId 后缀）。
    static func makeJSON(payload: [String: Any], appVersion: String) -> Data? {
        var data: [String: Any] = [:]
        var base64Keys: [String] = []
        for (key, value) in payload {
            if let blob = value as? Data {
                data[key] = blob.base64EncodedString()
                base64Keys.append(key)
            } else {
                data[key] = value
            }
        }
        let envelope: [String: Any] = [
            "format": formatTag,
            "version": version,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "appVersion": appVersion,
            "base64Keys": base64Keys.sorted(),
            "data": data
        ]
        guard JSONSerialization.isValidJSONObject(envelope) else { return nil }
        return try? JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
    }

    /// 写到临时目录，返回可分享的文件 URL。
    static func writeToTemporary(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: .atomic)
        return url
    }
}
