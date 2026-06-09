import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: AppStore
    var onComplete: () -> Void

    @State private var currentPage = 0
    @State private var name = ""
    @State private var work = ""
    @State private var selectedGoals: Set<String> = []
    @State private var catNameDraft = ""
    @State private var selectedStyle = "简洁直接"

    private let totalPages = 4

    var body: some View {
        ZStack {
            Color(red: 0.984, green: 0.969, blue: 0.937)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { i in
                        Circle()
                            .fill(i == currentPage ? CreamTheme.green : CreamTheme.green.opacity(0.2))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 60)
                .padding(.bottom, 24)

                // Page content
                TabView(selection: $currentPage) {
                    namePage.tag(0)
                    workPage.tag(1)
                    catPersonaPage.tag(2)
                    goalPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                // Bottom buttons
                bottomButtons
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Page 1: Name

    private var namePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("LaunchCatFlower")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 188)

            Text(L.onboardingWelcome(store.resolvedCatName))
                .font(.title.weight(.bold))
                .foregroundStyle(CreamTheme.text)

            Text(L.onboardingWelcomeSub(store.resolvedCatName))
                .font(.body)
                .foregroundStyle(CreamTheme.text.opacity(0.6))

            VStack(alignment: .leading, spacing: 8) {
                Text(L.onboardingNamePrompt)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CreamTheme.text)

                TextField(L.onboardingNamePlaceholder, text: $name)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(CreamTheme.glassStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Page 2: Work

    private var workPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "briefcase")
                .font(.system(size: 48))
                .foregroundStyle(CreamTheme.green)

            Text(L.onboardingWorkPrompt)
                .font(.title2.weight(.bold))
                .foregroundStyle(CreamTheme.text)

            VStack(alignment: .leading, spacing: 8) {
                TextField(L.onboardingWorkPlaceholder, text: $work)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(CreamTheme.glassStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Page 3: Cat Persona

    private let styleOptions: [(label: String, key: String)] = [
        (L.styleWarm, "温柔体贴"),
        (L.styleDirect, "简洁直接"),
        (L.styleWitty, "幽默毒舌"),
        (L.styleCalm, "知性冷静"),
    ]

    private var catPersonaPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("LaunchCatFlower")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 141)

            Text(L.onboardingCatNamePrompt)
                .font(.title2.weight(.bold))
                .foregroundStyle(CreamTheme.text)

            VStack(alignment: .leading, spacing: 8) {
                TextField(L.onboardingCatNamePlaceholder, text: $catNameDraft)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(CreamTheme.glassStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            Text(L.onboardingStylePrompt)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CreamTheme.text.opacity(0.6))
                .padding(.top, 8)

            FlowLayout(spacing: 10) {
                ForEach(styleOptions, id: \.key) { option in
                    GoalChip(
                        title: option.label,
                        isSelected: selectedStyle == option.key,
                        action: { selectedStyle = option.key }
                    )
                }
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Page 4: Goals

    private var goalPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(CreamTheme.green)

            Text(L.onboardingGoalPrompt)
                .font(.title2.weight(.bold))
                .foregroundStyle(CreamTheme.text)

            let goals = [
                (L.onboardingGoalRecord, "记录生活"),
                (L.onboardingGoalTime, "管理时间"),
                (L.onboardingGoalHabits, "养成习惯"),
                (L.onboardingGoalFeelings, "梳理情绪"),
            ]

            FlowLayout(spacing: 10) {
                ForEach(goals, id: \.1) { label, key in
                    GoalChip(
                        title: label,
                        isSelected: selectedGoals.contains(key),
                        action: {
                            if selectedGoals.contains(key) {
                                selectedGoals.remove(key)
                            } else {
                                selectedGoals.insert(key)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        VStack(spacing: 12) {
            if currentPage < totalPages - 1 {
                Button {
                    withAnimation { currentPage += 1 }
                } label: {
                    Text(L.onboardingNext)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(CreamTheme.green)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    finishOnboarding()
                } label: {
                    Text(L.onboardingSkip)
                        .font(.subheadline)
                        .foregroundStyle(CreamTheme.text.opacity(0.5))
                }
            } else {
                Button {
                    finishOnboarding()
                } label: {
                    Text(L.onboardingDone)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(CreamTheme.green)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    // MARK: - Finish

    private func finishOnboarding() {
        // Build profile string from answers
        var parts: [String] = []

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            parts.append(trimmedName)
            // Also save to nickname
            UserDefaults.standard.set(trimmedName, forKey: "auth.user")
        }

        let trimmedWork = work.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedWork.isEmpty {
            parts.append(trimmedWork)
        }

        if !selectedGoals.isEmpty {
            parts.append("LifeOS 目标：" + selectedGoals.sorted().joined(separator: "、"))
        }

        if !parts.isEmpty {
            store.userProfile = parts.joined(separator: "\n")
        }

        let trimmedCatName = catNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCatName.isEmpty {
            store.catName = trimmedCatName
        }
        store.catStyle = selectedStyle

        store.isOnboardingCompleted = true
        onComplete()
    }
}

// MARK: - Goal Chip

private struct GoalChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? .white : CreamTheme.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? CreamTheme.green : CreamTheme.glassStrong)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangeResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return ArrangeResult(size: CGSize(width: maxWidth, height: totalHeight), positions: positions)
    }
}
