import Foundation

enum TaskIntentDetector {
    static func looksLikeTask(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }

        if containsAny(value, explicitInboxRoutingSignals) {
            return false
        }

        if containsAny(value, hardTaskSignals) { return true }

        let hasObservationSignal = containsAny(value, observationSignals)
        let hasActionSignal = containsAny(value, actionSignals)
        let hasScheduleSignal = containsAny(value, scheduleSignals)
        let hasFutureScheduleSignal = containsAny(value, futureScheduleSignals)
        let hasNeedSignal = containsAny(value, needSignals)

        if hasObservationSignal && !hasNeedSignal && !hasScheduleSignal {
            return false
        }
        if hasFutureScheduleSignal && hasActionSignal && !hasObservationSignal { return true }
        if hasScheduleSignal && hasActionSignal && hasNeedSignal { return true }
        if hasNeedSignal && (hasActionSignal || !hasObservationSignal) { return true }
        return false
    }

    private static let hardTaskSignals = [
        "待办", "todo", "to-do", "提醒我", "记得", "加入待办", "加到待办", "添加到待办", "这是我的 todo list"
    ]

    private static let explicitInboxRoutingSignals = [
        "记录在想法", "记到想法", "放到想法", "存到想法",
        "记录在感受", "记到感受", "放到感受", "存到感受",
        "记录在随手记", "记到随手记", "放到随手记", "存到随手记",
        "记录成想法", "记录成感受"
    ]

    private static let needSignals = [
        "要做", "需要", "必须", "得去", "得把", "要去", "要把", "我要", "我有一场", "有一场"
    ]

    private static let scheduleSignals = [
        "待会", "今天", "今晚", "明天", "后天", "下周", "周一", "周二", "周三",
        "周四", "周五", "周六", "周日", "星期一", "星期二", "星期三", "星期四",
        "星期五", "星期六", "星期日"
    ]

    private static let futureScheduleSignals = [
        "待会", "明天", "后天", "下周", "周一", "周二", "周三",
        "周四", "周五", "周六", "周日", "星期一", "星期二", "星期三",
        "星期四", "星期五", "星期六", "星期日"
    ]

    private static let actionSignals = [
        "买", "预约", "提交", "发给", "发送", "处理", "跟进", "联系", "回复",
        "整理", "完成", "报名", "缴费", "下单", "取", "寄", "确认", "更新",
        "写", "改", "修", "做", "准备", "打印", "上传", "下载", "取消",
        "面试", "会议", "开会", "视频"
    ]

    private static let observationSignals = [
        "感受", "感觉", "觉得", "焦虑", "开心", "兴奋", "难过", "感恩", "梦",
        "做梦", "想到", "想法"
    ]

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.localizedCaseInsensitiveContains($0) }
    }
}
