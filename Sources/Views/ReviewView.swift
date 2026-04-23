import SwiftUI

struct ReviewView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("review.week.conclusion") private var weekConclusion = ""
    @AppStorage("review.next.action") private var nextAction = ""

    var body: some View {
        NavigationStack {
            List {
                Section("近7日复盘") {
                    HStack { Text("打卡完成率"); Spacer(); Text(store.weekDoneRateText) }
                    HStack { Text("专注总时长"); Spacer(); Text(store.weekFocusText) }
                    HStack { Text("随手记条数"); Spacer(); Text(store.weekInboxCountText) }
                }
                Section("本周1句话结论") {
                    TextField("例如：晚间精力下滑明显，上午效率更高", text: $weekConclusion, axis: .vertical)
                }
                Section("下周1个动作") {
                    TextField("例如：每天 9:00-10:30 只做最重要任务", text: $nextAction, axis: .vertical)
                }
                Section("复盘提示") {
                    Text("基于事实做复盘：本周做对了什么？哪里被拖慢？下周只保留一个杠杆动作。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("周复盘")
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.insetGrouped)
            .tint(CreamTheme.green)
            .scrollContentBackground(.hidden)
            .background(CreamTheme.glassStrong)
        }
        .creamBackground()
    }
}
