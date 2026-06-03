#if DEBUG
import Foundation

struct TestPersona: Identifiable, Equatable {
    let id: String
    let emoji: String
    let zhName: String
    let enName: String
    let zhDescription: String
    let enDescription: String
    let accentName: String

    var displayName: String { L.isEn ? enName : zhName }
    var displayDescription: String { L.isEn ? enDescription : zhDescription }
}

enum TestPersonaSeeder {
    private static let seededPrefix = "debug.testPersona.seeded."
    private static let calendar = Calendar(identifier: .gregorian)

    static let personas: [TestPersona] = [
        TestPersona(
            id: "persona-xiaoli",
            emoji: "👩‍💻",
            zhName: "小丽",
            enName: "Xiaoli",
            zhDescription: "互联网产品经理，工作节奏快，喜欢低压但高效的复盘。",
            enDescription: "Product manager who wants low-pressure but effective daily reviews.",
            accentName: "green"
        ),
        TestPersona(
            id: "persona-mark",
            emoji: "🧑‍🎓",
            zhName: "Mark",
            enName: "Mark",
            zhDescription: "大三学生，中英混用，写作焦虑，喜欢被温和地推进。",
            enDescription: "Bilingual college junior with writing anxiety who likes gentle momentum.",
            accentName: "blue"
        ),
        TestPersona(
            id: "persona-meimei",
            emoji: "🌸",
            zhName: "美美",
            enName: "Meimei",
            zhDescription: "自由职业轻度用户，重视审美、情绪和生活感。",
            enDescription: "Freelancer and light user who cares about aesthetics, mood, and small joys.",
            accentName: "pink"
        ),
        TestPersona(
            id: "persona-dazhuang",
            emoji: "💪",
            zhName: "大壮",
            enName: "Dazhuang",
            zhDescription: "全职奶爸，有 ADHD，常用 DBT 把情绪和行动拆小。",
            enDescription: "Stay-at-home dad with ADHD who uses DBT to break emotions and actions down.",
            accentName: "orange"
        )
    ]

    static func persona(id: String) -> TestPersona? {
        personas.first { $0.id == id }
    }

    static func isSeeded(_ persona: TestPersona, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: seededKey(for: persona))
    }

    static func markUnseeded(_ persona: TestPersona, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: seededKey(for: persona))
    }

    static func markSeeded(_ persona: TestPersona, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: seededKey(for: persona))
    }

    static func seedIfNeeded(_ persona: TestPersona, into store: AppStore, defaults: UserDefaults = .standard) {
        guard !isSeeded(persona, defaults: defaults) else { return }
        seed(persona, into: store)
        defaults.set(true, forKey: seededKey(for: persona))
    }

    static func seed(_ persona: TestPersona, into store: AppStore) {
        switch persona.id {
        case "persona-xiaoli": seedXiaoli(into: store)
        case "persona-mark": seedMark(into: store)
        case "persona-meimei": seedMeimei(into: store)
        case "persona-dazhuang": seedDazhuang(into: store)
        default: break
        }
        store.reloadForCurrentUser()
    }

    private static func seededKey(for persona: TestPersona) -> String {
        seededPrefix + persona.id
    }

    private static func seedXiaoli(into store: AppStore) {
        store.debugSetDailyCheckEntries([
            ("冥想 10 分钟", "早晨"), ("吃早餐", "早晨"), ("看晨间资讯", "早晨"),
            ("站立会议", "工作"), ("午休散步", "工作"), ("复盘今天", "晚间"), ("23 点前上床", "晚间")
        ])

        store.debugSetChecks(dateKey: key(2026, 6, 1), states: [
            "冥想 10 分钟": true, "吃早餐": true, "看晨间资讯": true,
            "站立会议": true, "午休散步": false, "复盘今天": true, "23 点前上床": false
        ])
        store.debugSetChecks(dateKey: key(2026, 6, 2), states: [
            "冥想 10 分钟": true, "吃早餐": true, "看晨间资讯": false,
            "站立会议": true, "午休散步": true, "复盘今天": true, "23 点前上床": false
        ])
        store.debugSetChecks(dateKey: key(2026, 6, 3), states: [
            "冥想 10 分钟": true, "吃早餐": true, "看晨间资讯": true,
            "站立会议": true, "午休散步": false, "复盘今天": false, "23 点前上床": false
        ])

        addTasks(into: store, [
            ("整理 1.12 需求池", "把用户反馈按影响范围分组", "待办", "高", "2026-06-03", "2026-06-04"),
            ("给设计师同步 onboarding 文案", "对齐低压引导语气", "待办", "中", "2026-06-03", "2026-06-03"),
            ("回访 3 个种子用户", "问清楚猫猫有没有打扰感", "待办", "中", "2026-06-03", "2026-06-05"),
            ("补 PRD 风险说明", "补充 AI 建议误触发的兜底", "已完成", "高", "2026-06-02", "2026-06-02"),
            ("预约牙科洗牙", "", "待办", "低", "2026-06-03", "2026-06-13"),
            ("准备周会 demo checklist", "把可演示路径压到 3 分钟", "已完成", "中", "2026-06-01", "2026-06-01")
        ])

        addTime(into: store, date: "2026-06-01", [("竞品拆解", "09:30", "11:00", "工作"), ("写 PRD", "14:00", "16:10", "工作"), ("晚间瑜伽", "20:30", "21:00", "运动")])
        addTime(into: store, date: "2026-06-02", [("用户访谈", "10:00", "11:30", "工作"), ("需求排序", "15:00", "17:10", "工作"), ("散步复盘", "19:20", "19:50", "生活")])
        addTime(into: store, date: "2026-06-03", [("晨间计划", "08:30", "09:00", "生活"), ("产品例会", "09:30", "10:30", "工作"), ("写需求文档", "10:45", "12:10", "工作"), ("用户访谈整理", "14:00", "16:20", "工作")])

        addTurn(into: store, text: "6 月 1 号把需求池重新分组后，终于能看出哪些是真问题。", type: "想法", title: "需求池分组", date: "2026-06-01")
        addTurn(into: store, text: "昨天用户说 onboarding 像考试，我有点被刺到，但这个反馈很重要。", type: "感受", mood: 3, tags: ["紧绷", "清醒"], date: "2026-06-02")
        addTurn(into: store, text: "今天站会信息量有点大，但把需求拆开后没有那么慌了。", type: "感受", mood: 3, tags: ["紧绷", "踏实"], date: "2026-06-03")

        store.addBrain(title: "低压 onboarding 原则", content: "不要解释功能清单，先让用户完成一个很小的真实动作。", topics: ["#Product", "#Onboarding"])
        seedAgent(
            store,
            profile: """
            你正在陪伴用户“小丽”。她是互联网产品经理，喜欢结构化、高效率，但讨厌被催促。她希望猫猫像低压项目教练：先帮她降噪，再把任务拆成可执行下一步。回复要短、清楚、有优先级，避免鸡汤。
            """,
            memories: [
                "小丽正在优化 LifeOS onboarding，特别在意“陪伴感”而不是教学感。",
                "小丽工作日容易被站会和需求池淹没，需要猫猫帮她做优先级排序。",
                "她喜欢先看到 1-3 个下一步，而不是长篇分析。"
            ],
            threads: [
                thread(
                    title: "onboarding 不要像考试",
                    date: "2026-06-02",
                    messages: [
                        ("user", "用户说 onboarding 像考试，我有点受挫。猫猫帮我拆一下怎么改？"),
                        ("assistant", "先接住这个反馈：不是你做错了，而是用户感觉被评估了。我们把目标改成“完成一个轻动作”。今天只改三处：标题少用教学语气、默认给一个示例、最后只问一个问题。"),
                        ("user", "我想明天 demo 前先出一个低压版本。"),
                        ("assistant", "可以。今晚只做最小版本：1. 改第一屏文案；2. 删除多余说明；3. 留一个“我今天想记录什么”的入口。其他都放进需求池。")
                    ]
                ),
                thread(
                    title: "站会后的需求排序",
                    date: "2026-06-03",
                    messages: [
                        ("user", "猫猫，我现在脑子里有七八个需求，感觉都很急。"),
                        ("assistant", "我们先按风险排，不按声音大小排。请先选：会影响留存的、会影响数据安全的、会阻塞审核的。剩下的今天不进入主线。"),
                        ("user", "那我先写 AI 建议误触发的兜底。"),
                        ("assistant", "对，这个是高影响低范围。给它 45 分钟，写完就停止，不继续扩 PRD。")
                    ]
                )
            ]
        )
    }

    private static func seedMark(into store: AppStore) {
        store.debugSetDailyCheckEntries([
            ("Morning reading", "Study"), ("Drink water", "Body"),
            ("Write 200 words", "Writing"), ("Sleep before 00:30", "Night")
        ])
        store.debugSetChecks(dateKey: key(2026, 6, 1), states: ["Morning reading": true, "Drink water": true, "Write 200 words": true, "Sleep before 00:30": false])
        store.debugSetChecks(dateKey: key(2026, 6, 2), states: ["Morning reading": false, "Drink water": true, "Write 200 words": false, "Sleep before 00:30": false])
        store.debugSetChecks(dateKey: key(2026, 6, 3), states: ["Morning reading": true, "Drink water": true, "Write 200 words": false, "Sleep before 00:30": false])

        addTasks(into: store, [
            ("Finish OS homework", "scheduler notes + one diagram", "待办", "高", "2026-06-03", "2026-06-05"),
            ("Email professor about office hour", "", "待办", "中", "2026-06-03", "2026-06-04"),
            ("整理递归优化笔记", "", "待办", "中", "2026-06-03", "2026-06-06"),
            ("Submit scholarship form", "", "已完成", "高", "2026-06-02", "2026-06-02"),
            ("Draft essay intro", "ugly first paragraph only", "待办", "高", "2026-06-03", "2026-06-03")
        ])

        addTime(into: store, date: "2026-06-01", [("Algorithm lecture", "09:00", "10:30", "学习"), ("Library writing", "11:00", "12:20", "学习"), ("Basketball", "17:00", "18:10", "运动")])
        addTime(into: store, date: "2026-06-02", [("Scholarship form", "10:30", "11:40", "学习"), ("Essay outline", "20:30", "22:10", "学习")])
        addTime(into: store, date: "2026-06-03", [("OS lab", "09:20", "11:00", "学习"), ("Campus lunch", "12:00", "13:00", "社交"), ("Late essay draft", "23:10", "24:00", "学习")])

        addTurn(into: store, text: "教授说的递归优化很有意思，回头整理笔记。", type: "想法", title: "递归优化笔记", date: "2026-06-01")
        addTurn(into: store, text: "论文写不下去，有点焦虑。I know the topic, but I can't start.", type: "感受", mood: 2, tags: ["焦虑"], date: "2026-06-02")
        addTurn(into: store, text: "室友帮我占了自习室的位子。", type: "感恩", date: "2026-06-03")
        addTurn(into: store, text: "梦到在图书馆找一本怎么都找不到的书。", type: "做梦", title: "找不到的书", date: "2026-06-03")

        store.addBrain(title: "Recursive optimization intuition", content: "把重复子问题标出来，再决定是缓存还是改写状态转移。", topics: ["#CS", "#Study"])
        store.addBrain(title: "When anxiety blocks writing", content: "先写 ugly first paragraph，再改结构；不要一开始就追求完整。", topics: ["#Writing", "#Emotion"])
        seedAgent(
            store,
            profile: """
            你正在陪伴用户“Mark”。他是中英混用的大三学生，容易因为论文和作业卡住而焦虑。他喜欢猫猫像学习伙伴：可以自然夹一点英文，先 validate 情绪，再给一个低门槛开始动作。不要像老师训话。
            """,
            memories: [
                "Mark 写论文时会卡在开头，适合 ugly first paragraph 策略。",
                "Mark 喜欢中英混用，能接受轻量英文鼓励。",
                "他需要猫猫帮他把作业拆到 25 分钟内能开始的动作。"
            ],
            threads: [
                thread(
                    title: "Essay stuck",
                    date: "2026-06-02",
                    messages: [
                        ("user", "I know what I want to say but I can't start the essay. 很烦。"),
                        ("assistant", "Totally makes sense. 你的问题不是不会写，是第一段压力太大。我们先写一个 ugly first paragraph，只服务于启动，不服务于好看。"),
                        ("user", "那我可以先写中文吗？"),
                        ("assistant", "可以，甚至建议先中文。今晚目标不是成稿，是把脑子里的观点倒出来 200 words。")
                    ]
                ),
                thread(
                    title: "OS homework",
                    date: "2026-06-03",
                    messages: [
                        ("user", "OS homework due Friday，我一直拖。"),
                        ("assistant", "先不碰整份 homework。打开题目，只找 scheduler 那一题，把关键词圈出来。25 分钟后你只需要有一个 rough diagram。"),
                        ("user", "This feels doable."),
                        ("assistant", "Good. Doable beats perfect. 做完 diagram 再决定要不要继续。")
                    ]
                )
            ]
        )
    }

    private static func seedMeimei(into store: AppStore) {
        store.debugSetDailyCheckEntries([
            ("浇花", "生活"), ("伸展 5 分钟", "身体"),
            ("记一件开心事", "晚上"), ("早点放下手机", "晚上")
        ])
        store.debugSetChecks(dateKey: key(2026, 6, 1), states: ["浇花": true, "伸展 5 分钟": true, "记一件开心事": true, "早点放下手机": false])
        store.debugSetChecks(dateKey: key(2026, 6, 2), states: ["浇花": true, "伸展 5 分钟": false, "记一件开心事": true, "早点放下手机": false])
        store.debugSetChecks(dateKey: key(2026, 6, 3), states: ["浇花": true, "伸展 5 分钟": false, "记一件开心事": false, "早点放下手机": false])

        addTasks(into: store, [
            ("给客户发报价", "语气温和但边界清楚", "待办", "中", "2026-06-03", "2026-06-04"),
            ("周末找画画体验课", "", "待办", "低", "2026-06-03", "2026-06-08"),
            ("整理作品集封面", "只选 6 张，不扩范围", "已完成", "中", "2026-06-01", "2026-06-01")
        ])

        addTime(into: store, date: "2026-06-01", [("作品集整理", "10:00", "11:30", "工作"), ("晒太阳散步", "16:00", "16:40", "生活")])
        addTime(into: store, date: "2026-06-02", [("咖啡店改稿", "10:30", "12:00", "工作"), ("看画展", "15:00", "16:20", "生活")])
        addTime(into: store, date: "2026-06-03", [("报价整理", "11:00", "11:50", "工作"), ("买花", "17:00", "17:30", "生活")])

        addTurn(into: store, text: "今天阳光很好，照进来的时候很开心。", type: "感恩", mood: 4, tags: ["开心"], date: "2026-06-01")
        addTurn(into: store, text: "客户一直改需求，我想温柔一点但也要守住边界。", type: "感受", mood: 3, tags: ["犹豫"], date: "2026-06-02")
        addTurn(into: store, text: "梦到在海边捡贝壳，特别平静。", type: "做梦", mood: 4, tags: ["平静"], date: "2026-06-03")
        addTurn(into: store, text: "想学画画，周末找个体验课试试。", type: "想法", title: "画画体验课", date: "2026-06-03")

        seedAgent(
            store,
            profile: """
            你正在陪伴用户“美美”。她是轻度使用的自由职业者，喜欢温柔、简短、有审美感的陪伴。猫猫要像生活陪伴者和边界提醒器：先回应感受，再给一句很小的行动建议。不要过度规划。
            """,
            memories: [
                "美美不喜欢任务感太重，适合轻轻提醒和小步行动。",
                "她在客户沟通里容易不好意思设边界。",
                "她喜欢把开心事、梦和生活画面记录下来。"
            ],
            threads: [
                thread(
                    title: "客户反复改需求",
                    date: "2026-06-02",
                    messages: [
                        ("user", "客户又说想再改一版，我有点烦，但又怕显得不配合。"),
                        ("assistant", "你可以温柔，但不用无限量供应。猫猫建议你回：可以调整一版，我会先按这次确认的方向处理；如果后续继续新增，我们再一起评估工期。"),
                        ("user", "这个语气刚好，不硬。"),
                        ("assistant", "对，它不是拒绝，是给合作加边界。")
                    ]
                ),
                thread(
                    title: "想学画画",
                    date: "2026-06-03",
                    messages: [
                        ("user", "我想学画画，但又怕自己三分钟热度。"),
                        ("assistant", "那就不要先买装备。这个周末只约一节体验课，目标不是坚持，是看看身体喜不喜欢那种专注感。"),
                        ("user", "这个说法让我轻松很多。"),
                        ("assistant", "好，就把它当一次小小的试吃，不当人生计划。")
                    ]
                )
            ]
        )
    }

    private static func seedDazhuang(into store: AppStore) {
        store.debugSetDailyCheckEntries([
            ("送娃去早教", "育儿"), ("陪娃户外 1 小时", "育儿"), ("哄睡", "育儿"),
            ("做午饭", "家务"), ("收拾玩具", "家务"), ("采购日用品", "家务"),
            ("吃药（ADHD）", "自我"), ("深呼吸 5 分钟", "自我"), ("写日记", "自我")
        ])
        store.debugSetChecks(dateKey: key(2026, 6, 1), states: ["送娃去早教": true, "陪娃户外 1 小时": true, "哄睡": true, "做午饭": true, "收拾玩具": false, "采购日用品": true, "吃药（ADHD）": true, "深呼吸 5 分钟": false, "写日记": false])
        store.debugSetChecks(dateKey: key(2026, 6, 2), states: ["送娃去早教": true, "陪娃户外 1 小时": false, "哄睡": false, "做午饭": true, "收拾玩具": false, "采购日用品": false, "吃药（ADHD）": true, "深呼吸 5 分钟": true, "写日记": false])
        store.debugSetChecks(dateKey: key(2026, 6, 3), states: ["送娃去早教": true, "陪娃户外 1 小时": true, "哄睡": false, "做午饭": true, "收拾玩具": false, "采购日用品": false, "吃药（ADHD）": true, "深呼吸 5 分钟": true, "写日记": false])

        addTasks(into: store, [
            ("给娃约体检", "", "待办", "高", "2026-06-03", "2026-06-05"),
            ("交水电费", "", "待办", "中", "2026-06-03", "2026-06-04"),
            ("买尿不湿和奶粉", "", "待办", "高", "2026-06-03", "2026-06-03"),
            ("修马桶漏水", "", "待办", "中", "2026-06-03", "2026-06-08"),
            ("早教课续费", "", "已完成", "中", "2026-06-02", "2026-06-02"),
            ("给老婆准备生日惊喜", "", "待办", "低", "2026-06-03", "2026-06-17")
        ])

        addTime(into: store, date: "2026-06-01", [("送娃早教", "08:20", "09:10", "生活"), ("买菜做饭", "10:40", "12:10", "家务"), ("陪娃户外", "15:30", "16:40", "育儿")])
        addTime(into: store, date: "2026-06-02", [("早教续费", "09:30", "10:10", "育儿"), ("哄睡失败", "21:00", "22:20", "育儿"), ("深夜收拾玩具", "22:50", "23:30", "家务")])
        addTime(into: store, date: "2026-06-03", [("送娃早教", "08:20", "09:10", "育儿"), ("做午饭", "11:00", "12:00", "家务"), ("陪娃户外", "15:30", "16:40", "育儿")])

        addTurn(into: store, text: "娃今天又哭了半小时我差点崩溃，后来抱着他唱歌慢慢好了。", type: "感受", mood: 2, tags: ["焦虑", "疲惫"], date: "2026-06-01")
        addTurn(into: store, text: "ADHD 让我同时想做五件事结果一件没做完，要学会一次只做一件。", type: "想法", title: "一次只做一件", date: "2026-06-02")
        addTurn(into: store, text: "老婆说谢谢我带了一天娃，突然觉得被看见了。", type: "感受", mood: 4, tags: ["感动"], date: "2026-06-02")
        addTurn(into: store, text: "娃第一次说了完整的'爸爸我爱你'。", type: "感恩", mood: 5, tags: ["幸福"], date: "2026-06-03")

        store.addBrain(title: "痛苦忍受：娃哭闹时的 TIPP 练习", content: "情境：孩子持续哭闹，身体开始发热，想要逃离。\n练习：冷水洗脸，放慢呼吸，提醒自己先保证安全，再解决问题。", topics: ["#DBT", "#育儿"], kind: "dbtSession", dbtSession: dbtSession(summary: ["把孩子哭闹和“我做不好爸爸”的解释分开。", "先让身体降温，再决定下一步。"], skill: "TIPP", actions: ["下次先把孩子放到安全位置，自己离开 30 秒深呼吸。"]))
        store.addBrain(title: "ADHD 每日策略清单", content: "1. 番茄钟 25 分钟\n2. 出门前检查三件事\n3. 手机设提醒，不依赖记忆", topics: ["#ADHD", "#自我管理"])
        store.addBrain(title: "情绪调节：被琐事淹没时的正念呼吸", content: "把“任务很多”改成“眼前只有下一件事”。先呼吸十次，再选最小动作。", topics: ["#DBT", "#正念"], kind: "dbtSession", dbtSession: dbtSession(summary: ["琐事堆积时，大脑会把所有事压成一个整体。", "正念呼吸帮助他重新看见下一步。"], skill: "Wise mind", actions: ["每天午饭后做 2 分钟正念呼吸。"]))

        seedAgent(
            store,
            profile: """
            你正在陪伴用户“大壮”。他是全职奶爸，有 ADHD，常在育儿和家务中情绪过载。他需要猫猫像 DBT Coach：先保证安全，再做情绪验证、身体降温、下一步行动。回复要具体、短、稳定，不讲大道理。
            """,
            memories: [
                "大壮在孩子哭闹时容易把事件解释成“我不是好爸爸”，需要猫猫帮他分开事实和解释。",
                "大壮适合 TIPP、Wise Mind、一次只做一件的 DBT/ADHD 策略。",
                "他需要非常具体的下一步，例如先把孩子放到安全位置，再离开 30 秒呼吸。"
            ],
            threads: [
                thread(
                    title: "娃哭闹时的 TIPP",
                    date: "2026-06-01",
                    messages: [
                        ("user", "娃哭了半小时，我脑子快炸了，我是不是很差劲。"),
                        ("assistant", "你不是差劲，你是过载了。先做安全步骤：确认孩子在安全位置，然后你去洗手间用冷水洗脸 20 秒。现在只处理身体，不评价自己。"),
                        ("user", "我照做了，稍微降下来一点。"),
                        ("assistant", "很好。下一步只做一件事：回去抱他，声音放低，重复一句“爸爸在”。")
                    ],
                    dbt: AgentDBTSessionState(status: "completed", skillId: "distress_tolerance", currentStepIndex: 4, startedAt: "2026-06-01", completedAt: "2026-06-01", summary: ["身体过载不等于失败。", "先安全，再降温，再行动。"], skillIds: ["distress_tolerance"], emotionalShift: "从 9/10 降到 5/10。", followUpActions: ["孩子哭闹超过 10 分钟时先做冷水洗脸。"])
                ),
                thread(
                    title: "一次只做一件",
                    date: "2026-06-03",
                    messages: [
                        ("user", "我现在同时想着买奶粉、交水电、修马桶，整个人乱了。"),
                        ("assistant", "我们先把大脑里的三件事排队。今天只能先做“会影响今晚”的：奶粉。水电明天上午 10 点提醒，马桶只拍照发给维修师傅。"),
                        ("user", "这样就没那么爆炸了。"),
                        ("assistant", "对。不是事情少了，是你不用同时扛着它们。现在只打开购物 App。")
                    ]
                )
            ]
        )
    }

    private static func addTasks(
        into store: AppStore,
        _ rows: [(title: String, detail: String, status: String, priority: String, date: String, due: String)]
    ) {
        for row in rows {
            store.addTask(
                title: row.title,
                detail: row.detail,
                status: row.status,
                priority: row.priority,
                dueDate: row.due,
                date: row.date,
                completedAt: row.status == "已完成" ? date(row.date) : nil
            )
        }
    }

    private static func addTime(
        into store: AppStore,
        date: String,
        _ rows: [(name: String, start: String, end: String, category: String)]
    ) {
        for row in rows {
            store.debugInsertTimeEntry(
                name: row.name,
                start: row.start,
                end: row.end,
                category: row.category,
                dateKey: date
            )
        }
    }

    private static func addTurn(
        into store: AppStore,
        text: String,
        type: String,
        title: String? = nil,
        mood: Int? = nil,
        tags: [String] = [],
        date: String
    ) {
        var payload: [String: String] = ["content": text]
        if let title { payload["title"] = title }
        store.debugInsertTurn(
            rawText: text,
            recognizedType: type,
            targetBucket: "inbox",
            confidence: 0.92,
            payload: payload,
            status: "committed",
            moodScore: mood,
            feelingTags: tags,
            createdAt: Self.date(date)
        )
    }

    private static func seedAgent(
        _ store: AppStore,
        profile: String,
        memories: [String],
        threads: [AgentChatThread]
    ) {
        store.debugSeedAgentContext(
            userProfile: profile,
            memories: memories.map { AgentMemory(content: $0, category: "preference", createdAt: date("2026-06-03"), lastUsedAt: date("2026-06-03"), source: "user") },
            threads: threads
        )
    }

    private static func thread(
        title: String,
        date dateKey: String,
        messages: [(role: String, content: String)],
        dbt: AgentDBTSessionState? = nil
    ) -> AgentChatThread {
        let start = date(dateKey)
        let chatMessages = messages.enumerated().map { index, row in
            AgentChatMessage(
                role: row.role,
                content: row.content,
                createdAt: calendar.date(byAdding: .minute, value: index * 4, to: start) ?? start
            )
        }
        return AgentChatThread(
            title: title,
            messages: chatMessages,
            dbtSession: dbt,
            createdAt: start,
            updatedAt: chatMessages.last?.createdAt ?? start,
            titleGenerated: false
        )
    }

    private static func dbtSession(summary: [String], skill: String, actions: [String]) -> BrainDBTSession {
        BrainDBTSession(
            summary: summary,
            skills: [BrainDBTSkill(name: skill, note: "测试角色预置的 DBT 技能练习。")],
            actions: actions,
            transcript: [
                BrainDBTTurn(role: "user", content: "我现在有点撑不住了。", createdAt: date("2026-06-02")),
                BrainDBTTurn(role: "assistant", content: "我们先不急着解决全部，只先让身体回到能承受的范围。", createdAt: date("2026-06-02"))
            ],
            emotionalShift: "从 8/10 的紧绷降到 5/10，可以继续照顾当下。",
            sourceThreadId: nil
        )
    }

    private static func key(_ year: Int, _ month: Int, _ day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func date(_ key: String) -> Date {
        var components = DateComponents()
        let parts = key.split(separator: "-").compactMap { Int($0) }
        components.year = parts[safe: 0] ?? 2026
        components.month = parts[safe: 1] ?? 6
        components.day = parts[safe: 2] ?? 3
        components.hour = 9
        components.minute = 0
        components.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        return calendar.date(from: components) ?? Date()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
