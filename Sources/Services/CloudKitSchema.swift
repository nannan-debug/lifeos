import CloudKit
import Foundation

/// CloudKit 同步用到的固定标识与字段名。
enum CloudKitSchema {
    static let containerID = "iCloud.ai.anna.personalsystem"
    /// 所有同步记录放在一个自定义 zone，便于整体抓取变更。
    static let zoneName = "LifeOSZone"
    /// 每条记录把它的本地表示编码进这一个字段。
    static let payloadField = "payload"
    /// 打卡项配置是单例，用固定 recordName。
    static let dailyConfigRecordName = "daily-config.v1"

    enum RecordType: String, Codable, CaseIterable {
        case checkDay = "CheckDay"
        case timeEntry = "TimeEntry"
        case task = "Task"
        case turn = "Turn"
        case brainCard = "BrainCard"
        case dailyConfig = "DailyConfig"
    }

    static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }
}
