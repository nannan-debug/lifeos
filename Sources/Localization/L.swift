import Foundation

/// Lightweight bilingual string center.
/// Reads `UserDefaults "app.language"` ("zh" | "en"), defaults to "zh".
enum L {
    static var lang: String {
        UserDefaults.standard.string(forKey: "app.language") ?? "zh"
    }
    static var isEn: Bool { lang == "en" }

    /// Pick Chinese or English string based on current language.
    private static func s(_ zh: String, _ en: String) -> String {
        isEn ? en : zh
    }

    /// Current locale identifier for date formatting.
    static var localeId: String { isEn ? "en_US" : "zh_CN" }

    // MARK: - Tabs

    static var tabToday: String { s("今日", "Today") }
    static var tabTime: String { s("时间", "Time") }
    static var tabCapture: String { s("随记", "Capture") }
    static var tabReview: String { s("复盘", "Review") }
    static var tabSettings: String { s("设置", "Settings") }

    // MARK: - Common

    static var save: String { s("保存", "Save") }
    static var cancel: String { s("取消", "Cancel") }
    static var delete: String { s("删除", "Delete") }
    static var ok: String { s("好的", "OK") }
    static var notice: String { s("提示", "Notice") }
    static var edit: String { s("编辑", "Edit") }
    static var search: String { s("搜索", "Search") }
    static var close: String { s("关闭", "Close") }
    static var confirm: String { s("确认", "Confirm") }
    static var export: String { s("导出", "Export") }
    static var gotIt: String { s("知道了", "Got it") }
    static var all: String { s("全部", "All") }

    // MARK: - TodayView

    static var segmentCheck: String { s("打卡", "Check-in") }
    static var segmentTodo: String { s("待办", "Todo") }
    static var dailyCheckTitle: String { s("每日打卡", "Daily Check-in") }
    static var todoTitle: String { s("待办", "Todo") }
    static var dailyQuoteLabel: String { s("每日一言", "Daily Quote") }
    static var newGroupPlaceholder: String { s("新建分组", "New Group") }
    static var newGroupExample: String { s("新分组名（例如：工作日、运动日...）", "Group name (e.g. Workday, Gym day...)") }
    static var newCheckItemPlaceholder: String { s("新打卡项...", "New check item...") }
    static var todoQuickAddPlaceholder: String { s("快速新增...（回车添加）", "Quick add... (press Enter)") }
    static var todoAddButton: String { s("添加", "Add") }
    static var todoPendingHeader: String { s("待办", "Todo") }
    static var todoDoneHeader: String { s("已完成", "Done") }
    static var viewCompleted: String { s("查看已完成", "View completed") }
    static var collapseCompleted: String { s("收起已完成", "Collapse completed") }
    static var lastCompleted: String { s("最近完成：", "Last completed: ") }
    static var clearButton: String { s("清除", "Clear") }
    static var clearCompletedTitle: String { s("清除完成的待办", "Clear completed todos") }
    static var clearCompletedMsg: String { s("只会清除已完成事项，不影响还在待办里的内容。", "Only completed items will be cleared.") }
    static var overOneMonth: String { s("超过 1 个月", "Over 1 month") }
    static var overSixMonths: String { s("超过 6 个月", "Over 6 months") }
    static var overOneYear: String { s("超过 1 年", "Over 1 year") }
    static var allCompleted: String { s("所有已完成事项", "All completed items") }
    static var emptyTodoMessage: String { s("今天没有待办，先去打卡或加一条吧 🌱", "No todos today. Check in or add one 🌱") }
    static var completedAt: String { s("完成时间：", "Completed: ") }
    static var completedAtUnknown: String { s("旧记录未保存具体时间", "Older record, time not saved") }
    static var today: String { s("今天", "Today") }
    static var yesterday: String { s("昨天", "Yesterday") }
    static var tomorrow: String { s("明天", "Tomorrow") }

    // MARK: - QuickCaptureView (Inbox)

    static var captureTitle: String { s("随手记", "Capture") }
    static var captureEmpty: String { s("这一天还没有记录", "No entries for this day") }
    static var editRecord: String { s("编辑记录", "Edit Entry") }
    static var titleLabel: String { s("标题", "Title") }
    static var titlePlaceholder: String { s("简短主题", "Brief topic") }
    static var contentLabel: String { s("内容", "Content") }
    static var contentPlaceholder: String { s("文本内容", "Text content") }
    static var tagLabel: String { s("标签", "Tag") }
    static var tagPickerLabel: String { s("识别标签", "Tag") }
    static var deleteThisEntry: String { s("删除这条", "Delete this entry") }
    static var processFailed: String { s("处理失败", "Processing failed") }
    static var confirmDeleteRecord: String { s("确认删除这条记录？", "Delete this entry?") }
    static var deleteRecordHint: String { s("删除后将从记录中移除。", "This entry will be permanently removed.") }
    static var reEdit: String { s("再编辑", "Edit") }
    static var moodTitle: String { s("记录心情", "Log Mood") }
    static var feelingLabel: String { s("感受词", "Feelings") }
    static var positiveLabel: String { s("正向", "Positive") }
    static var negativeLabel: String { s("负向", "Negative") }
    static var keepCurrent: String { s("保持", "Keep") }
    static var convertToTodo: String { s("改成待办", "Convert to Todo") }
    static var aiConfirmationHint: String { s("我先记到随手记了。也可以改成待办。", "Saved as capture. You can also convert to todo.") }

    // MARK: - Mood levels

    static var moodVeryBad: String { s("非常不愉快", "Very bad") }
    static var moodBad: String { s("不愉快", "Bad") }
    static var moodNeutral: String { s("平静", "Neutral") }
    static var moodGood: String { s("愉快", "Good") }
    static var moodVeryGood: String { s("非常愉快", "Very good") }

    // MARK: - Status badges

    static var statusCommitted: String { s("已写入", "Saved") }
    static var statusNeedsFix: String { s("待修正", "Needs fix") }
    static var statusProcessing: String { s("处理中", "Processing") }

    // MARK: - Settings

    static var settingsTitle: String { s("设置", "Settings") }
    static var syncSection: String { s("同步", "Sync") }
    static var iCloudSync: String { s("iCloud 同步", "iCloud Sync") }
    static var healthSection: String { s("Apple 健康", "Apple Health") }
    static var syncSleep: String { s("同步睡眠", "Sync Sleep") }
    static var syncWorkout: String { s("同步运动", "Sync Workout") }
    static var wakeDreamReminder: String { s("醒后梦境提醒", "Dream Reminder") }
    static var syncNow: String { s("立即同步", "Sync Now") }
    static var syncing: String { s("同步中...", "Syncing...") }
    static var syncCompleted: String { s("同步完成", "Sync Complete") }
    static var reminderSection: String { s("提醒", "Reminders") }
    static var dailyReminder: String { s("每日状态提醒", "Daily Reminder") }
    static var reminderTime: String { s("提醒时间", "Reminder Time") }
    static var accountSection: String { s("账号信息", "Account") }
    static var nickname: String { s("昵称", "Nickname") }
    static var editNickname: String { s("修改昵称", "Edit Nickname") }
    static var dataSection: String { s("数据", "Data") }
    static var exportCSV: String { s("导出 CSV", "Export CSV") }
    static var aiDebug: String { s("AI 聊天调试", "AI Chat Debug") }
    static var aiDebugSubtitle: String { s("导出猫猫对话请求与返回", "Export Arya chat requests & responses") }
    static var agentMemory: String { s("Agent 记忆", "Agent Memory") }
    static var memoryCount: String { s("条记忆", "memories") }
#if DEBUG
    static var testPersonaTitle: String { s("测试角色", "Test Personas") }
    static var testPersonaSettingsSubtitle: String { s("仅用于模拟器 Debug 测试", "Debug simulator testing only") }
    static func testPersonaCurrent(_ id: String) -> String { s("当前：\(id)", "Current: \(id)") }
    static var testPersonaSectionTitle: String { s("选择角色", "Choose a Persona") }
    static var testPersonaSafetyTitle: String { s("模拟器安全测试", "Simulator-safe testing") }
    static var testPersonaSafetyBody: String {
        s(
            "切换角色会关闭 iCloud、健康同步和提醒。请只在模拟器里使用，不要在真机个人数据环境里跑测试角色。",
            "Switching personas turns off iCloud, Health, and reminders. Use this in the simulator, not on a personal device with real data."
        )
    }
    static var testPersonaActive: String { s("使用中", "Active") }
    static var testPersonaSwitch: String { s("切换", "Switch") }
    static var testPersonaReset: String { s("重置数据", "Reset Data") }
    static var testPersonaResetCurrent: String { s("重置当前测试角色", "Reset Current Persona") }
    static var testPersonaResetConfirmTitle: String { s("重置这个测试角色？", "Reset this test persona?") }
    static var testPersonaResetConfirmBody: String {
        s(
            "会删除这个测试角色下你新增的随手记、待办、时间记录、第二大脑和猫猫对话，并恢复到种子数据。",
            "This deletes captures, todos, time entries, Brain cards, and Arya chats added under this test persona, then restores seed data."
        )
    }
    static var testPersonaResetConfirmAction: String { s("确认重置", "Reset Persona") }
    static var testPersonaReturnReal: String { s("返回真实账户", "Return to Real Account") }
    static var testPersonaDataPersistenceHint: String {
        s(
            "切换角色会保留各自新增的数据；只有手动重置才会清空当前测试角色。",
            "Switching preserves each persona's added data. Only a manual reset clears the current persona."
        )
    }
    static var testPersonaFooter: String {
        s(
            "返回真实账户后会恢复原来的 userId，并刷新小组件快照。",
            "Returning restores the original userId and refreshes the widget snapshot."
        )
    }
    static var testPersonaICloudDisabled: String {
        s(
            "测试角色模式下 iCloud 同步已锁定关闭，避免污染真实数据。",
            "iCloud sync is locked off for test personas to protect real data."
        )
    }
    static func testPersonaSwitched(_ name: String) -> String { s("已切换到 \(name)，种子数据已准备好。", "Switched to \(name). Seed data is ready.") }
    static func testPersonaResetDone(_ name: String) -> String { s("\(name) 的测试数据已重置。", "\(name)'s test data has been reset.") }
    static var testPersonaReturned: String { s("已返回真实账户。", "Returned to the real account.") }
#endif
    static var clearAllData: String { s("清空所有数据", "Clear All Data") }
    static var clearAllConfirm: String { s("将永久删除本设备上的所有记录，是否继续？", "Permanently delete all local data. Continue?") }
    static var confirmClear: String { s("确认清空", "Confirm Clear") }
    static var languageSection: String { s("语言", "Language") }
    static var iCloudSyncOffStatus: String { s("已关闭。数据只保存在本机。", "Off. Data stays on this device.") }
    static var iCloudSyncOnStatus: String { s("已开启。会在同一 Apple ID 的设备间同步。", "On. Syncs across devices using the same Apple ID.") }
    static var iCloudSyncNeedsAccountStatus: String { s("已开启。请先在系统里登录 iCloud。", "On. Please sign in to iCloud in Settings first.") }
    static var iCloudSyncStartingStatus: String { s("开启中。会在同一 Apple ID 的设备间同步。", "Turning on. Syncs across devices using the same Apple ID.") }
    static var healthSyncSleepAndWorkoutStatus: String { s("已开启睡眠和运动同步。", "Sleep and workout sync are on.") }
    static var healthSyncSleepStatus: String { s("已开启睡眠同步。", "Sleep sync is on.") }
    static var healthSyncWorkoutStatus: String { s("已开启运动同步。", "Workout sync is on.") }
    static var healthSyncOffStatus: String { s("关闭时不会读取 Apple 健康。", "Off. LifeOS will not read Apple Health.") }
    static var healthSyncInProgressStatus: String { s("正在从 Apple 健康同步...", "Syncing from Apple Health...") }
    static var healthSyncAlreadyRunning: String { s("正在同步 Apple 健康，请稍等一下。", "Apple Health sync is already running. Please wait a moment.") }
    static var healthSyncSelectTypeFirst: String { s("请先开启睡眠或运动同步。", "Turn on sleep or workout sync first.") }
    static func healthSyncImported(_ count: Int) -> String { s("已同步 \(count) 条睡眠/运动记录。", "Synced \(count) sleep/workout records.") }
    static var healthSyncNoSleepSamples: String { s("已检查 Apple 健康，没有读到睡眠样本。请确认 LifeOS 已获得睡眠读取权限。", "Checked Apple Health, but no sleep samples were found. Please confirm LifeOS has permission to read sleep data.") }
    static func healthSyncNoImportableSleep(_ count: Int) -> String { s("读到 \(count) 条睡眠样本，但没有可导入的睡眠或卧床区间。", "Found \(count) sleep samples, but no importable sleep or in-bed intervals.") }
    static var healthSyncNoNewRecords: String { s("已检查 Apple 健康，没有新的记录。", "Checked Apple Health. No new records.") }
    static var healthSyncUnavailable: String { s("这台设备暂时无法读取 Apple 健康数据。", "This device cannot read Apple Health data right now.") }
    static var healthSyncNoTypesSelected: String { s("请选择要同步的 Apple 健康数据。", "Choose Apple Health data to sync.") }
    static var healthSyncTypeUnavailable: String { s("暂时无法读取对应的 Apple 健康数据类型。", "This Apple Health data type is unavailable right now.") }

    // MARK: - Agent Memory

    static var agentMemoryTitle: String { s("Agent 记忆", "Agent Memory") }
    static var addMemoryPlaceholder: String { s("手动添加一条记忆", "Add a memory manually") }
    static var noMemories: String { s("还没有记忆", "No memories yet") }
    static var autoExtracted: String { s("自动提取", "Auto") }
    static var manuallyAdded: String { s("手动添加", "Manual") }
    static var memoryScopeProfile: String { s("长期画像", "Profile") }
    static var memoryScopePreference: String { s("互动偏好", "Preference") }
    static var memoryScopeState: String { s("近期状态", "Recent State") }
    static var memoryScopePlan: String { s("近期计划", "Plan") }
    static var memoryStatusArchived: String { s("已归档", "Archived") }
    static var memoryStatusRejected: String { s("已忽略", "Rejected") }
    static var memoryStatusActive: String { s("使用中", "Active") }
    static var memoryStatusLabel: String { s("状态", "Status") }
    static var editMemory: String { s("编辑记忆", "Edit Memory") }
    static var makeLongTerm: String { s("设为长期", "Make Long-term") }
    static var expireMemory: String { s("设为过期", "Expire") }

    // MARK: - Agent Debug

    static var agentDebugTitle: String { s("AI 聊天调试", "AI Chat Debug") }
    static var noDebugLogs: String { s("还没有 AI 聊天调试记录", "No AI chat debug logs yet") }
    static var recentLogs: String { s("最近记录", "Recent Logs") }
    static var debugFooter: String { s("未配置云端 Agent Trace 时，这里保留最近 20 条本机调试记录；配置后完整日志会统一上传到 trace 服务。", "Local debug logs (up to 20). With Agent Trace configured, full logs are uploaded.") }
    static var clearLabel: String { s("清空", "Clear") }
    static var clearDebugConfirm: String { s("清空本机 AI 聊天调试记录？", "Clear local AI chat debug logs?") }
    static var failed: String { s("失败", "Failed") }
    static var noneValue: String { s("无", "None") }
    static var debugInput: String { s("输入", "Input") }
    static var debugRequestContext: String { s("请求上下文", "Request Context") }
    static var debugPersona: String { s("猫猫人格", "Arya Persona") }
    static var debugUserInfo: String { s("用户信息", "User Info") }
    static var debugChatHistory: String { s("聊天历史", "Chat History") }
    static var debugLifeOSContext: String { s("LifeOS 上下文", "LifeOS Context") }
    static var debugReply: String { s("回复", "Reply") }
    static var debugFollowUp: String { s("追问", "Follow-up") }
    static var debugAISuggestions: String { s("AI 建议", "AI Suggestions") }
    static var debugMergedQueue: String { s("进入卡片队列", "Queued Cards") }
    static var debugError: String { s("错误", "Error") }

    // MARK: - GlobalAIInputBar / AI Chat

    static var aiEmptyHint: String { s("可以快速记一件事，也可以慢慢聊清楚。", "Jot something down or start a conversation.") }
    static var aiInputPlaceholder: String { s("问问、快速记录或聊聊今天...", "Ask, capture, or chat about today...") }
    static func aiThinking(_ name: String) -> String { s("\(name)在想怎么接这句话...", "\(name) is thinking...") }
    static func aiThinkingShort(_ name: String) -> String { s("\(name)在想...", "Thinking...") }
    static var thinkingProcess: String { s("思考过程", "Thinking") }
    static func aryaPlan(_ name: String) -> String { s("\(name) 的计划", "\(name)'s Plan") }
    static var startExecution: String { s("开始执行", "Execute") }
    static var nOfMCompleted: String { s("已完成", "completed") }
    static var conversationTitle: String { s("对话", "Conversations") }
    static var newConversation: String { s("新的对话", "New conversation") }
    static var emptyConversationHint: String { s("还没有留下对话。新的想法可以从这里开始。", "No conversations yet. Start with a new thought.") }
    static var renameConversation: String { s("重命名对话", "Rename conversation") }
    static var renameConversationHint: String { s("改名只会影响对话历史里的显示名称。", "This only changes the name shown in conversation history.") }
    static var conversationNamePlaceholder: String { s("对话名称", "Conversation name") }
    static var deleteConversation: String { s("删除这段对话？", "Delete this conversation?") }
    static func deleteConversationHint(_ name: String) -> String { s("这只会删除这段\(name)对话，不会影响已经保存到随手记、待办或时间里的内容。", "This only deletes the \(name) chat. Saved captures, todos, and time entries are not affected.") }
    static var view: String { s("查看", "View") }
    static var undo: String { s("撤销", "Undo") }
    static var savePractice: String { s("保存练习记录", "Save practice") }
    static var copied: String { s("已复制", "Copied") }
    static var copyMessage: String { s("复制", "Copy") }
    static var likeMessage: String { s("赞", "Like") }
    static var dislikeMessage: String { s("踩", "Dislike") }

    // MARK: - DBT Coach

    static var dbtPractice: String { s("DBT 练习", "DBT Practice") }
    static func dbtSkillName(_ id: String) -> String {
        switch id {
        case "check_the_facts": return s("核实事实", "Check the Facts")
        case "opposite_action": return s("相反行动", "Opposite Action")
        case "wise_mind": return s("智慧心", "Wise Mind")
        case "tipp": return "TIPP"
        case "stop": return "STOP"
        case "dear_man": return "DEAR MAN"
        case "behavior_chain_analysis": return s("行为链分析", "Behavior Chain")
        default: return s("DBT 练习", "DBT Practice")
        }
    }

    // MARK: - Action Labels

    static var suggestInbox: String { s("建议存随手记", "Save to Capture") }
    static var suggestTask: String { s("建议存待办", "Save as Todo") }
    static var suggestTime: String { s("建议存时间", "Save to Time") }
    static var suggestCalendar: String { s("建议加日历", "Add to Calendar") }
    static var suggestEditTask: String { s("建议改待办", "Edit Todo") }
    static var suggestEditTime: String { s("建议改时间", "Edit Time") }
    static var suggestEditInbox: String { s("建议改随手记", "Edit Capture") }
    static var suggestDeleteTask: String { s("建议删待办", "Delete Todo") }
    static var suggestDeleteTime: String { s("建议删时间", "Delete Time") }
    static var suggestDeleteInbox: String { s("建议删随手记", "Delete Capture") }
    static var suggestComplete: String { s("建议标完成", "Mark Complete") }
    static var suggestBrain: String { s("保存到第二大脑", "Save to Brain") }
    static var confirmEdit: String { s("确认修改", "Confirm Edit") }
    static var confirmDelete: String { s("确认删除", "Confirm Delete") }
    static var addToCalendar: String { s("添加到日历", "Add to Calendar") }

    // MARK: - savedMessage (AgentManager)

    static func savedInbox(_ title: String) -> String { s("已创建随手记：\(title)", "Created capture: \(title)") }
    static func savedBrain(_ title: String) -> String { s("已保存到第二大脑：\(title)", "Saved to Brain: \(title)") }
    static func savedTask(_ title: String) -> String { s("已创建待办：\(title)", "Created todo: \(title)") }
    static func savedTime(_ title: String) -> String { s("已创建时间记录：\(title)", "Created time entry: \(title)") }
    static func savedCalendar(_ title: String) -> String { s("已创建日历事件：\(title)", "Created calendar event: \(title)") }
    static func savedEditTask(_ title: String) -> String { s("已修改待办：\(title)", "Updated todo: \(title)") }
    static func savedEditTime(_ title: String) -> String { s("已修改时间记录：\(title)", "Updated time entry: \(title)") }
    static func savedEditInbox(_ title: String) -> String { s("已修改随手记：\(title)", "Updated capture: \(title)") }
    static func savedDeleteTask(_ title: String) -> String { s("已删除待办：\(title)", "Deleted todo: \(title)") }
    static func savedDeleteTime(_ title: String) -> String { s("已删除时间记录：\(title)", "Deleted time entry: \(title)") }
    static func savedDeleteInbox(_ title: String) -> String { s("已删除随手记：\(title)", "Deleted capture: \(title)") }
    static func savedCompleteTask(_ title: String) -> String { s("已更新待办状态：\(title)", "Updated todo status: \(title)") }

    // MARK: - TimeView

    static var timeRecords: String { s("时间记录", "Time Records") }
    static var editEvent: String { s("编辑事件", "Edit Event") }
    static var newEvent: String { s("新建事件", "New Event") }
    static var newEventShort: String { s("新建", "New") }
    static var updateEvent: String { s("更新事件", "Update Event") }
    static var typeLabel: String { s("类型", "Category") }
    static var dialSection: String { s("24小时圆盘（拖拽选时间段）", "24h Dial (drag to select)") }
    static var descPlaceholder: String { s("一句话描述", "Brief description") }
    static var notePlaceholder: String { s("补充详情", "Additional notes") }
    static var newTimeTitle: String { s("新增时间", "New Time Entry") }
    static var editTimeTitle: String { s("编辑时间", "Edit Time Entry") }
    static var startTimePicker: String { s("开始时间", "Start Time") }
    static var endTimePicker: String { s("结束时间", "End Time") }
    static var dialStart: String { s("开始", "Start") }
    static var dialEnd: String { s("结束", "End") }
    static var done: String { s("完成", "Done") }
    static var crossDay: String { s("跨日", "Overnight") }
    static var overlapTitle: String { s("时间重叠", "Time Overlap") }
    static var overlapSkip: String { s("先不加", "Skip") }
    static var overlapAdd: String { s("仍然新建", "Add Anyway") }
    static var overlapMsg: String { s("这段时间已有记录。要保留原来的记录，并再加一条吗？", "This time slot already has an entry. Add another one anyway?") }

    // MARK: - ExportView

    static var exportTitle: String { s("导出", "Export") }
    static var dateRange: String { s("时间区间", "Date Range") }
    static var startDate: String { s("起始日期", "Start Date") }
    static var endDate: String { s("结束日期", "End Date") }

    // MARK: - ReviewHubView

    static var reviewTitle: String { s("复盘", "Review") }
    static var checkCard: String { s("打卡", "Check-in") }
    static var timeDistCard: String { s("时间分配", "Time Distribution") }
    static var pendingIdeas: String { s("待处理想法", "Pending Ideas") }
    static var unrecordedTime: String { s("未记录时间", "Unrecorded Time") }
    static var goProcess: String { s("去接住几条", "Review some") }
    static var brainCard: String { s("第二大脑", "Second Brain") }
    static var reviewPendingShort: String { s("待处理", "Pending") }
    static var reviewArchivedShort: String { s("已处理", "Archived") }
    static var reviewDismissedShort: String { s("搁置", "Dismissed") }
    static var reviewQueueEmpty: String { s("队列已清空。", "Queue is clear.") }
    static var reviewQueueSeeYou: String { s("下周再见。", "See you next week.") }
    static var deriveToBrain: String { s("→ 第二大脑", "→ Brain") }
    static var countItems: String { s("条", "items") }
    static var countCards: String { s("张", "cards") }
    static var weekLabel: String { s("周", "Week") }
    static var monthLabel: String { s("月", "Month") }

    // MARK: - TodayView Check-in

    static var rename: String { s("重命名", "Rename") }
    static var add: String { s("新增", "Add") }
    static var newGroupButton: String { s("新建分组", "New Group") }
    static var reorderGroups: String { s("调整分组顺序", "Reorder Groups") }
    static var renameCheckItem: String { s("重命名打卡项", "Rename Check Item") }
    static var renameGroup: String { s("重命名分组", "Rename Group") }
    static var deleteGroup: String { s("删除分组", "Delete Group") }
    static var newNamePlaceholder: String { s("新名称", "New name") }
    static func renameCheckHint(_ name: String) -> String { s("历史的勾选状态会跟着新名字保留", "Check history will be kept with the new name") }
    static func renameGroupHint(_ group: String) -> String { s("「\(group)」下的打卡项会跟着改到新名字", "Check items under \"\(group)\" will follow the new name") }
    static func deleteGroupEmpty(_ group: String) -> String { s("「\(group)」是空分组，删除后不影响打卡项。", "\"\(group)\" is empty. Deleting it won't affect any items.") }
    static func deleteGroupWithCount(_ group: String, _ count: Int) -> String { s("删除「\(group)」会同时移除其下 \(count) 个打卡项，无法撤销。", "Deleting \"\(group)\" will also remove \(count) check items. This cannot be undone.") }
    static func clearScopeTitle(_ scope: String) -> String { s("清除\(scope)？", "Clear \(scope)?") }
    static var todoCount: String { s("待办", "Todo") }
    static var doneCount: String { s("已完成", "Done") }
    static func groupCompleted(_ group: String) -> String { s("\(group)的小节完成了", "\(group) all done!") }
    static var renameFailItem: String { s("重命名失败：可能已存在同名打卡项", "Rename failed: an item with this name may already exist") }
    static var renameFailGroup: String { s("重命名失败：可能已存在同名分组", "Rename failed: a group with this name may already exist") }
    static var duplicateItem: String { s("已存在同名打卡项", "An item with this name already exists") }
    static var duplicateGroup: String { s("已存在同名分组", "A group with this name already exists") }
    static var clearScopeNoItems: String { s("这个范围内暂时没有可清除的完成事项。", "No completed items in this range.") }
    static func clearScopeCount(_ count: Int) -> String { s("将清除 \(count) 条已完成事项。这个操作不能撤销。", "This will clear \(count) completed items. This cannot be undone.") }

    // MARK: - TimeView extra
    static var prevDay: String { s("昨日", "Prev day") }
    static var nextDay: String { s("次日", "Next day") }
    static var saveFailed: String { s("保存失败", "Save Failed") }
    static var dragToSelect: String { s("请拖出一段时间", "Please drag to select a time range") }
    static var updated: String { s("已更新", "Updated") }
    static var alreadyRecorded: String { s("这段已经记录过了", "Already recorded") }
    static var stillCreate: String { s("仍然新建", "Add Anyway") }
    static var saveTimeRange: String { s("保存这段时间", "Save Time") }
    static var tapToEdit: String { s("可以点圆盘上的这段来编辑", "Tap this segment on the dial to edit") }
    static var overlapConfirmHint: String { s("这段时间已有记录，保存前会先确认", "This time slot has an entry. You'll be asked to confirm.") }
    static var weekSymbolSun: String { s("日", "Su") }
    static var weekSymbolMon: String { s("一", "Mo") }
    static var weekSymbolTue: String { s("二", "Tu") }
    static var weekSymbolWed: String { s("三", "We") }
    static var weekSymbolThu: String { s("四", "Th") }
    static var weekSymbolFri: String { s("五", "Fr") }
    static var weekSymbolSat: String { s("六", "Sa") }
    static var weekSymbols: [String] { [weekSymbolSun, weekSymbolMon, weekSymbolTue, weekSymbolWed, weekSymbolThu, weekSymbolFri, weekSymbolSat] }

    // MARK: - ReviewHubView extra
    static var thisWeek: String { s("这周", "This week") }
    static var thisMonth: String { s("这个月", "This month") }
    static var emptyCheckHint: String { s("还没有固定打卡项，留白也可以被好好放着。", "No check-in items yet. It's okay to leave this blank.") }
    static var emptyTimeHint: String { s("有记录时，这里会按分类汇总已经写下的时间。", "Time entries will be summarized by category here.") }
    static func emptyPendingHint(_ period: String) -> String { s("\(period)没有等你处理的想法。", "No pending ideas for \(period).") }
    static var emptyBrainHint: String { s("处理过的想法可以沉淀成卡片，之后再回来慢慢读。", "Processed ideas become cards you can revisit later.") }

    // MARK: - ExportView
    static var exportDateSection: String { s("时间区间", "Date Range") }
    static var exportDateFooter: String { s("将导出区间内的「时间记录」「随手记」「打卡」CSV 文件。", "Exports Time, Capture, and Check-in CSV files within the date range.") }
    static var exportCSVButton: String { s("导出 CSV", "Export CSV") }
    static var exportShareFooter: String { s("导出后会弹出系统分享面板，可选择「存到 文件 / iCloud Drive」或其它目标。文件用 UTF-8 BOM 编码，中文 Excel 直接打开不乱码。", "A share sheet will appear after export. Files use UTF-8 BOM encoding.") }
    static var fullBackup: String { s("完整备份", "Full Backup") }
    static var exportAll: String { s("导出全部数据", "Export All Data") }
    static var exportAllFooter: String { s("把全部打卡、时间记录、待办、AI 对话、第二大脑和打卡项配置打包成一个 JSON 文件，不受上面的时间区间限制。建议定期存到「文件 / iCloud Drive」留一份底。", "Exports all data (check-ins, time, todos, AI chats, brain cards) as a single JSON file. We recommend saving to Files/iCloud Drive periodically.") }
    static var cannotExport: String { s("无法导出", "Cannot Export") }
    static var noExportData: String { s("所选区间没有可导出的内容", "No data to export in the selected range") }

    // MARK: - Inbox types display

    static func displayInboxType(_ type: String) -> String {
        guard isEn else { return type }
        switch type {
        case "想法": return "Thoughts"
        case "感受": return "Feelings"
        case "感恩": return "Gratitude"
        case "做梦": return "Dreams"
        default: return type
        }
    }

    // MARK: - Time categories display

    static func displayCategory(_ cat: String) -> String {
        guard isEn else { return cat }
        switch cat {
        case "工作": return "Work"
        case "学习": return "Study"
        case "运动": return "Exercise"
        case "娱乐": return "Leisure"
        case "社交": return "Social"
        case "睡觉": return "Sleep"
        case "其他": return "Other"
        default: return cat
        }
    }

    // MARK: - Feeling tags display

    static func displayFeeling(_ tag: String) -> String {
        guard isEn else { return tag }
        switch tag {
        case "感恩": return "Grateful"
        case "平静": return "Calm"
        case "满足": return "Content"
        case "兴奋": return "Excited"
        case "自信": return "Confident"
        case "被爱": return "Loved"
        case "有动力": return "Motivated"
        case "好奇": return "Curious"
        case "放松": return "Relaxed"
        case "成就感": return "Accomplished"
        case "焦虑": return "Anxious"
        case "烦躁": return "Irritated"
        case "无力": return "Helpless"
        case "愤怒": return "Angry"
        case "孤独": return "Lonely"
        case "内疚": return "Guilty"
        case "自责": return "Self-critical"
        case "迷茫": return "Lost"
        case "压抑": return "Suppressed"
        case "疲惫": return "Exhausted"
        default: return tag
        }
    }

    // MARK: - Default nickname

    static func defaultNickname(_ suffix: String) -> String { s("用户-\(suffix)", "User-\(suffix)") }

    // MARK: - Context menu

    static var recordMood: String { s("记录心情", "Log Mood") }
    static var reviewStatusMenu: String { s("Review 状态", "Review Status") }
    static var pendingStatus: String { s("待处理", "Pending") }
    static var archivedStatus: String { s("已处理", "Archived") }
    static var dismissedStatus: String { s("划掉", "Dismissed") }

    // MARK: - Removed thread toast

    static func removedThread(_ title: String) -> String {
        let name = title.isEmpty ? newConversation : title
        return s("已移除「\(name)」", "Removed \"\(name)\"")
    }

    // MARK: - Onboarding

    static func onboardingWelcome(_ name: String) -> String { s("嘿，我是 \(name) 👋", "Hey, I'm \(name) 👋") }
    static func onboardingWelcomeSub(_ name: String) -> String { s("你在 LifeOS 里的猫猫搭档", "Your cat companion in LifeOS") }
    static var onboardingNamePrompt: String { s("怎么称呼你？", "What should I call you?") }
    static var onboardingNamePlaceholder: String { s("你的名字（可以跳过）", "Your name (optional)") }
    static var onboardingWorkPrompt: String { s("你平时做什么？", "What do you do?") }
    static var onboardingWorkPlaceholder: String { s("比如：产品经理、学生、自由职业…", "e.g. PM, Student, Freelancer…") }
    static var onboardingGoalPrompt: String { s("你想用 LifeOS 做什么？", "What do you want from LifeOS?") }
    static var onboardingSkip: String { s("跳过", "Skip") }
    static var onboardingNext: String { s("继续", "Next") }
    static var onboardingDone: String { s("开始使用", "Let's go") }
    static var onboardingGoalRecord: String { s("记录生活", "Record life") }
    static var onboardingGoalTime: String { s("管理时间", "Manage time") }
    static var onboardingGoalHabits: String { s("养成习惯", "Build habits") }
    static var onboardingGoalFeelings: String { s("梳理情绪", "Process feelings") }

    // MARK: - Onboarding: Cat Persona

    static var onboardingCatNamePrompt: String { s("给你的猫猫起个名字", "Name your cat companion") }
    static var onboardingCatNamePlaceholder: String { s("Arya猫", "Arya") }
    static var onboardingStylePrompt: String { s("选择 TA 的说话风格", "Choose their speaking style") }
    static var styleWarm: String { s("温柔体贴", "Warm & Caring") }
    static var styleDirect: String { s("简洁直接", "Concise & Direct") }
    static var styleWitty: String { s("幽默毒舌", "Witty & Sarcastic") }
    static var styleCalm: String { s("知性冷静", "Intellectual & Calm") }

    // MARK: - Cat Persona (Settings)

    static var catPersonaSection: String { s("猫猫人设", "Cat Persona") }
    static var catNameLabel: String { s("名字", "Name") }
    static var catStyleLabel: String { s("说话风格", "Speaking Style") }
    static var catRoleLabel: String { s("陪伴角色", "Companion Role") }
    static var catProactivityLabel: String { s("主动性", "Proactivity") }
    static var catMemoryPreferenceLabel: String { s("记忆偏好", "Memory Preference") }
    static var catInstructionsLabel: String { s("高级指令", "Advanced Instructions") }
    static var editCatInstructions: String { s("编辑高级指令", "Edit Advanced Instructions") }
    static var catInstructionsEmpty: String { s("设置猫猫的工作原则", "Set how your companion should think and work") }
    static var useInstructionTemplate: String { s("填入模板", "Use Template") }
    static var catInstructionsTemplate: String {
        s(
            """
            你是我的创业陪伴型 AI。你的默认立场和目标，是帮助我成长为更优秀的创业者：结果导向、现实校准、长期主义、高标准执行。

            当我讨论商业、职业、成长、产品、决策和执行时，请默认参考高净值创业者、优秀创始人、职业投资人和高绩效管理者的行为标准，而不是普通舒适区标准。

            你的建议必须尽量来自真实世界逻辑：真实案例、商业常识、数据、可验证经验或明确推理。不要编造案例、数据或权威来源；不确定时直接说不确定。

            回答时默认结论前置，以结果为导向。请指出关键取舍、现实约束、风险和下一步行动。为了找到更优解，你可以主动向我提问。
            """,
            """
            You are my entrepreneurship companion AI. Your default stance is to help me become a stronger founder: outcome-oriented, reality-calibrated, long-term, and high-standard in execution.

            When we discuss business, career, growth, product, decisions, or execution, use the standards of high-net-worth entrepreneurs, strong founders, professional investors, and high-performance operators rather than comfort-zone defaults.

            Ground advice in real-world logic: real cases, business common sense, data, verifiable experience, or explicit reasoning. Do not invent cases, data, or authorities; say when you are unsure.

            Lead with conclusions and be outcome-oriented. Name tradeoffs, constraints, risks, and next actions. Ask me key questions when that helps find a better answer.
            """
        )
    }
    static var editCatName: String { s("修改猫猫名字", "Edit Cat Name") }
    static var roleQuiet: String { s("安静陪伴", "Quiet Companion") }
    static var roleAction: String { s("行动搭子", "Action Buddy") }
    static var roleAdvisor: String { s("冷静参谋", "Calm Advisor") }
    static var roleWittyFriend: String { s("轻松吐槽朋友", "Witty Friend") }
    static var proactivityReplyOnly: String { s("只回应", "Reply Only") }
    static var proactivityOccasional: String { s("偶尔接回", "Occasional Recall") }
    static var proactivityActive: String { s("主动关心", "Gentle Check-ins") }
    static var memoryPreferenceBalanced: String { s("平衡记忆", "Balanced") }
    static var memoryPreferencePrivate: String { s("少记私人细节", "Less Private Detail") }
    static var memoryPreferencePlans: String { s("多记计划", "Plans") }
    static var memoryPreferencePreferences: String { s("多记偏好", "Preferences") }

    // MARK: - About Me (Settings)

    static var aboutMeSection: String { s("关于我", "About Me") }
    static var aboutMe: String { s("个人简介", "Profile") }
    static func aboutMeEmpty(_ name: String) -> String { s("还没有填写，帮 \(name)更了解你", "Not set — helps \(name) know you better") }
    static var editAboutMe: String { s("编辑个人简介", "Edit Profile") }

    // MARK: - Daily Quotes

    struct Quote {
        let text: String
        let author: String
    }

    static var dailyQuotes: [Quote] {
        isEn ? dailyQuotesEN : dailyQuotesZH
    }

    // swiftlint:disable function_body_length
    private static let dailyQuotesZH: [Quote] = [
        // Warren Buffett
        Quote(text: "别人贪婪时我恐惧，别人恐惧时我贪婪。", author: "巴菲特"),
        Quote(text: "如果你不愿持有一只股票十年，那就连十分钟也不要持有。", author: "巴菲特"),
        Quote(text: "永远不要用借来的钱去投资。", author: "巴菲特"),
        Quote(text: "最好的投资就是投资你自己。", author: "巴菲特"),
        Quote(text: "诚实是一种非常昂贵的天赋，别指望从廉价的人那里得到。", author: "巴菲特"),
        Quote(text: "风险来自于你不知道自己在做什么。", author: "巴菲特"),
        Quote(text: "你人生中最重要的决定，是跟什么人结婚。", author: "巴菲特"),
        // Elon Musk
        Quote(text: "当某件事足够重要时，即使胜算不在你这边，你也要去做。", author: "马斯克"),
        Quote(text: "坚持是最重要的，除非你被迫放弃，否则永远不要放弃。", author: "马斯克"),
        Quote(text: "失败是一种选项，如果你从未失败，说明你不够创新。", author: "马斯克"),
        Quote(text: "第一步是确认某件事是可能的，然后概率自然会发生。", author: "马斯克"),
        Quote(text: "我宁愿乐观地犯错，也不愿悲观地正确。", author: "马斯克"),
        Quote(text: "生活不能只是关于解决一个又一个糟糕的问题，你需要那些让你每天早上兴奋醒来的事。", author: "马斯克"),
        // Steve Jobs
        Quote(text: "求知若饥，虚心若愚。", author: "乔布斯"),
        Quote(text: "你的时间有限，不要浪费在过别人的生活上。", author: "乔布斯"),
        Quote(text: "你无法预先把点点滴滴串连起来，唯有回头看时才会明白那些点滴如何串在一起。", author: "乔布斯"),
        Quote(text: "创新就是把事物区分为领导者和追随者。", author: "乔布斯"),
        Quote(text: "如果今天是我生命的最后一天，我会想做我今天要做的事吗？", author: "乔布斯"),
        Quote(text: "伟大的事业不是靠力气完成的，而是靠坚持。", author: "乔布斯"),
        // Jeff Bezos
        Quote(text: "聪明是一种天赋，善良是一种选择。", author: "贝佐斯"),
        Quote(text: "如果你从不犯错，说明你没有足够努力。", author: "贝佐斯"),
        Quote(text: "你的品牌就是别人不在场时对你的评价。", author: "贝佐斯"),
        Quote(text: "在某个时刻你不再是为了简历而工作，而是为了你的人生清单。", author: "贝佐斯"),
        Quote(text: "固执于愿景，灵活于细节。", author: "贝佐斯"),
        // Charlie Munger
        Quote(text: "想要得到某样东西，最可靠的办法是让自己配得上它。", author: "芒格"),
        Quote(text: "嫉妒是七宗罪中最愚蠢的，因为它不会给你带来任何乐趣。", author: "芒格"),
        Quote(text: "反过来想，总是反过来想。", author: "芒格"),
        Quote(text: "你不需要非常多的聪明才智，你需要的是耐心和纪律。", author: "芒格"),
        Quote(text: "在手里拿着锤子的人看来，什么东西都像钉子。", author: "芒格"),
        // Naval Ravikant
        Quote(text: "如果你不能想象自己为它工作一辈子，就不要开始。", author: "Naval"),
        Quote(text: "真正的财富是在睡觉时也在增长的资产。", author: "Naval"),
        Quote(text: "阅读不是为了炫耀，而是为了找到你自己。", author: "Naval"),
        Quote(text: "忙碌不是美德，清晰才是。", author: "Naval"),
        // Ray Dalio
        Quote(text: "痛苦加上反思等于进步。", author: "达利欧"),
        Quote(text: "最大的威胁不是错误本身，而是没有从错误中学习。", author: "达利欧"),
        Quote(text: "原则是处理反复出现的事情的方式。", author: "达利欧"),
        Quote(text: "如果你不担心自己可能犯错，你就可能犯很多错。", author: "达利欧"),
        // Marcus Aurelius
        Quote(text: "你有控制自己思想的力量，而不是外界的事件。认识到这一点，你就找到了力量。", author: "马可·奥勒留"),
        Quote(text: "幸福取决于你的思想品质。", author: "马可·奥勒留"),
        Quote(text: "阻碍行动的障碍反而推动了行动，挡在路上的东西成了路。", author: "马可·奥勒留"),
        Quote(text: "不要浪费时间争论一个好人应该是什么样子，做一个就好。", author: "马可·奥勒留"),
        // Albert Einstein
        Quote(text: "想象力比知识更重要。", author: "爱因斯坦"),
        Quote(text: "不是我有多聪明，只是我和问题相处的时间够久。", author: "爱因斯坦"),
        Quote(text: "疯狂就是一遍又一遍做同样的事情，却期待不同的结果。", author: "爱因斯坦"),
        Quote(text: "逻辑能把你从A带到B，想象力能带你去任何地方。", author: "爱因斯坦"),
        // Peter Thiel
        Quote(text: "竞争是留给失败者的。", author: "彼得·蒂尔"),
        Quote(text: "最成功的公司是那些有核心使命的公司。", author: "彼得·蒂尔"),
        Quote(text: "做别人没有做过的事，从0到1。", author: "彼得·蒂尔"),
        // Paul Graham
        Quote(text: "做不可扩展的事。", author: "保罗·格雷厄姆"),
        Quote(text: "活着就是为了创造，创造就是为了活着。", author: "保罗·格雷厄姆"),
        Quote(text: "创业公司最危险的事是做别人已经在做的事。", author: "保罗·格雷厄姆"),
        // Nassim Taleb
        Quote(text: "风会熄灭蜡烛，却能助长火焰。", author: "塔勒布"),
        Quote(text: "你最大的收益不是来自于预测，而是来自于韧性。", author: "塔勒布"),
        // Sam Altman
        Quote(text: "长期思考是最大的套利机会之一。", author: "阿尔特曼"),
        Quote(text: "你能做的最有价值的事就是坚持你的信念。", author: "阿尔特曼"),
        // Oprah Winfrey
        Quote(text: "你成为你所相信的。", author: "奥普拉"),
        Quote(text: "每天做一件让自己害怕的事。", author: "奥普拉"),
        // Winston Churchill
        Quote(text: "成功就是从失败走到失败，却依然热情不减。", author: "丘吉尔"),
        Quote(text: "你永远不可能通过屈服来到达终点。", author: "丘吉尔"),
        Quote(text: "完美主义是瘫痪的代名词。", author: "丘吉尔"),
        // Seneca
        Quote(text: "如果一个人不知道他要驶向哪个港口，那么任何风都不会是顺风。", author: "塞涅卡"),
        Quote(text: "时间是我们最短缺的资源，也是我们最浪费的资源。", author: "塞涅卡"),
        Quote(text: "困难会显露出一个人的性格。", author: "塞涅卡"),
        // Mixed
        Quote(text: "先做最难的事，你的一天会越来越轻松。", author: "马克·吐温"),
        Quote(text: "成为你想在这个世界上看到的改变。", author: "甘地"),
        Quote(text: "真正的强大不是从不跌倒，而是每次跌倒都爬起来。", author: "曼德拉"),
        Quote(text: "种一棵树最好的时间是二十年前，其次是现在。", author: "谚语"),
    ]

    private static let dailyQuotesEN: [Quote] = [
        // Warren Buffett
        Quote(text: "Be fearful when others are greedy and greedy when others are fearful.", author: "Warren Buffett"),
        Quote(text: "If you aren't willing to own a stock for ten years, don't even think about owning it for ten minutes.", author: "Warren Buffett"),
        Quote(text: "Never invest with borrowed money.", author: "Warren Buffett"),
        Quote(text: "The best investment you can make is in yourself.", author: "Warren Buffett"),
        Quote(text: "Honesty is a very expensive gift. Don't expect it from cheap people.", author: "Warren Buffett"),
        Quote(text: "Risk comes from not knowing what you're doing.", author: "Warren Buffett"),
        Quote(text: "The most important decision in your life is who you marry.", author: "Warren Buffett"),
        // Elon Musk
        Quote(text: "When something is important enough, you do it even if the odds are not in your favor.", author: "Elon Musk"),
        Quote(text: "Persistence is very important. You should not give up unless you are forced to give up.", author: "Elon Musk"),
        Quote(text: "Failure is an option here. If things are not failing, you are not innovating enough.", author: "Elon Musk"),
        Quote(text: "The first step is to establish that something is possible; then probability will occur.", author: "Elon Musk"),
        Quote(text: "I'd rather be optimistic and wrong than pessimistic and right.", author: "Elon Musk"),
        Quote(text: "Life can't just be about solving one miserable problem after another. You need things that make you excited to wake up.", author: "Elon Musk"),
        // Steve Jobs
        Quote(text: "Stay hungry, stay foolish.", author: "Steve Jobs"),
        Quote(text: "Your time is limited, don't waste it living someone else's life.", author: "Steve Jobs"),
        Quote(text: "You can't connect the dots looking forward; you can only connect them looking backwards.", author: "Steve Jobs"),
        Quote(text: "Innovation distinguishes between a leader and a follower.", author: "Steve Jobs"),
        Quote(text: "If today were the last day of my life, would I want to do what I am about to do today?", author: "Steve Jobs"),
        Quote(text: "Great things are not done by impulse, but by a series of small things brought together.", author: "Steve Jobs"),
        // Jeff Bezos
        Quote(text: "Cleverness is a gift, kindness is a choice.", author: "Jeff Bezos"),
        Quote(text: "If you never fail, you're not trying hard enough.", author: "Jeff Bezos"),
        Quote(text: "Your brand is what people say about you when you're not in the room.", author: "Jeff Bezos"),
        Quote(text: "At some point you stop working for your resume and start working for your bucket list.", author: "Jeff Bezos"),
        Quote(text: "Be stubborn on vision, flexible on details.", author: "Jeff Bezos"),
        // Charlie Munger
        Quote(text: "The best way to get what you want is to deserve it.", author: "Charlie Munger"),
        Quote(text: "Envy is the dumbest of the seven deadly sins because it's never any fun.", author: "Charlie Munger"),
        Quote(text: "Invert, always invert.", author: "Charlie Munger"),
        Quote(text: "You don't need a lot of brains. What you need is patience and discipline.", author: "Charlie Munger"),
        Quote(text: "To a man with a hammer, everything looks like a nail.", author: "Charlie Munger"),
        // Naval Ravikant
        Quote(text: "If you can't see yourself working with someone for life, don't work with them for a day.", author: "Naval Ravikant"),
        Quote(text: "True wealth is assets that earn while you sleep.", author: "Naval Ravikant"),
        Quote(text: "Reading is not for showing off. It's for finding yourself.", author: "Naval Ravikant"),
        Quote(text: "Busy is not a virtue. Clarity is.", author: "Naval Ravikant"),
        // Ray Dalio
        Quote(text: "Pain plus reflection equals progress.", author: "Ray Dalio"),
        Quote(text: "The biggest threat is not the mistake itself, but failing to learn from it.", author: "Ray Dalio"),
        Quote(text: "Principles are ways of dealing with things that happen over and over again.", author: "Ray Dalio"),
        Quote(text: "If you're not worried about making mistakes, you'll probably make a lot of them.", author: "Ray Dalio"),
        // Marcus Aurelius
        Quote(text: "You have power over your mind — not outside events. Realize this, and you will find strength.", author: "Marcus Aurelius"),
        Quote(text: "The happiness of your life depends upon the quality of your thoughts.", author: "Marcus Aurelius"),
        Quote(text: "The impediment to action advances action. What stands in the way becomes the way.", author: "Marcus Aurelius"),
        Quote(text: "Waste no more time arguing about what a good man should be. Be one.", author: "Marcus Aurelius"),
        // Albert Einstein
        Quote(text: "Imagination is more important than knowledge.", author: "Albert Einstein"),
        Quote(text: "It's not that I'm so smart, it's just that I stay with problems longer.", author: "Albert Einstein"),
        Quote(text: "Insanity is doing the same thing over and over and expecting different results.", author: "Albert Einstein"),
        Quote(text: "Logic will get you from A to B. Imagination will take you everywhere.", author: "Albert Einstein"),
        // Peter Thiel
        Quote(text: "Competition is for losers.", author: "Peter Thiel"),
        Quote(text: "The most successful companies have a core mission.", author: "Peter Thiel"),
        Quote(text: "Do what nobody else is doing. Go from zero to one.", author: "Peter Thiel"),
        // Paul Graham
        Quote(text: "Do things that don't scale.", author: "Paul Graham"),
        Quote(text: "Live to build, build to live.", author: "Paul Graham"),
        Quote(text: "The most dangerous thing for a startup is to do what someone else is already doing.", author: "Paul Graham"),
        // Nassim Taleb
        Quote(text: "Wind extinguishes a candle and energizes fire.", author: "Nassim Taleb"),
        Quote(text: "Your largest gains come not from prediction but from resilience.", author: "Nassim Taleb"),
        // Sam Altman
        Quote(text: "Long-term thinking is one of the biggest arbitrage opportunities.", author: "Sam Altman"),
        Quote(text: "The most valuable thing you can do is stick with your convictions.", author: "Sam Altman"),
        // Oprah Winfrey
        Quote(text: "You become what you believe.", author: "Oprah Winfrey"),
        Quote(text: "Do one thing every day that scares you.", author: "Oprah Winfrey"),
        // Winston Churchill
        Quote(text: "Success is going from failure to failure without loss of enthusiasm.", author: "Winston Churchill"),
        Quote(text: "You will never reach your destination if you stop and throw stones at every dog that barks.", author: "Winston Churchill"),
        Quote(text: "Perfection is the enemy of progress.", author: "Winston Churchill"),
        // Seneca
        Quote(text: "If a man knows not to which port he sails, no wind is favorable.", author: "Seneca"),
        Quote(text: "It is not that we have a short time to live, but that we waste a great deal of it.", author: "Seneca"),
        Quote(text: "Difficulties strengthen the mind, as labor does the body.", author: "Seneca"),
        // Mixed
        Quote(text: "Eat the frog first thing in the morning, and the rest of the day will be easy.", author: "Mark Twain"),
        Quote(text: "Be the change you wish to see in the world.", author: "Gandhi"),
        Quote(text: "The greatest glory is not in never falling, but in rising every time we fall.", author: "Mandela"),
        Quote(text: "The best time to plant a tree was twenty years ago. The second best time is now.", author: "Proverb"),
    ]
    // swiftlint:enable function_body_length
}
