import SwiftUI

struct FirstRunLaunchGate<Content: View>: View {
    @AppStorage("launch.slowGrowth.v3.seen") private var hasSeenSlowGrowthLaunch = false
    @State private var isShowingLaunch = false

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .accessibilityHidden(isShowingLaunch)

            if isShowingLaunch {
                PlantGrowthLaunchView {
                    hasSeenSlowGrowthLaunch = true
                    isShowingLaunch = false
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .onAppear {
            isShowingLaunch = !hasSeenSlowGrowthLaunch
        }
    }
}

struct PlantGrowthLaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var stemProgress: CGFloat = 0
    @State private var leafProgress: CGFloat = 0
    @State private var flowerScale: CGFloat = 0
    @State private var wordmarkOpacity = 0.0
    @State private var overlayOpacity = 1.0
    @State private var didStart = false

    let onFinished: () -> Void

    var body: some View {
        ZStack {
            LaunchPlantColors.background
                .ignoresSafeArea()

            VStack(spacing: 18) {
                LaunchPlantLayeredCanvas(
                    stem: stemProgress,
                    leaves: leafProgress,
                    flower: flowerScale
                )
                .frame(width: 144, height: 358)
                .scaleEffect(0.84)
                .frame(width: 144, height: 301)

                VStack(spacing: 4) {
                    Text("LifeOS")
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(LaunchPlantColors.text)

                    Text("观察生活，记录生活")
                        .font(.system(size: 12, weight: .light, design: .serif))
                        .foregroundStyle(LaunchPlantColors.green)
                }
                .opacity(wordmarkOpacity)
                .offset(y: CGFloat(6 * (1 - wordmarkOpacity)))
            }
            .offset(y: -18)
        }
        .opacity(overlayOpacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("LifeOS，观察生活，记录生活")
        .onAppear(perform: start)
    }

    private func start() {
        guard !didStart else { return }
        didStart = true

        if reduceMotion {
            stemProgress = 1
            leafProgress = 1
            flowerScale = 1
            wordmarkOpacity = 1

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                fadeOut()
            }
            return
        }

        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.6)) {
            stemProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.525)) {
                leafProgress = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.125) {
            withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.375)) {
                flowerScale = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.8)) {
                wordmarkOpacity = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            fadeOut()
        }
    }

    private func fadeOut() {
        withAnimation(.timingCurve(0.32, 0, 0.67, 0, duration: 0.3)) {
            overlayOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onFinished()
        }
    }
}

private enum LaunchPlantColors {
    static let background = Color(red: 251.0 / 255.0, green: 247.0 / 255.0, blue: 239.0 / 255.0)
    static let green = Color(red: 61.0 / 255.0, green: 166.0 / 255.0, blue: 92.0 / 255.0)
    static let text = Color(red: 38.0 / 255.0, green: 51.0 / 255.0, blue: 38.0 / 255.0)
}

private struct LaunchPlantLayeredCanvas: View {
    let stem: CGFloat
    let leaves: CGFloat
    let flower: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            plantImage("LaunchPlantPot", width: 102, height: 64)
                .position(x: 70.97, y: 326.5)

            plantImage("LaunchPlantStem", width: 49, height: 262)
                .mask(alignment: .bottom) {
                    Rectangle()
                        .frame(width: 49, height: max(1, 262 * stem))
                }
                .position(x: 71.45, y: 171)

            plantImage("LaunchPlantLeafLeft", width: 71, height: 80)
                .scaleEffect(leaves, anchor: UnitPoint(x: 0.93, y: 0.91))
                .opacity(leaves)
                .position(x: 37.46, y: 202.91)

            plantImage("LaunchPlantLeafRight", width: 71, height: 80)
                .scaleEffect(leaves, anchor: UnitPoint(x: 0.05, y: 0.91))
                .opacity(leaves)
                .position(x: 101, y: 161.5)

            plantImage("LaunchPlantFlowerV2", width: 144, height: 134)
                .scaleEffect(flower, anchor: UnitPoint(x: 0.49, y: 0.51))
                .opacity(flower)
                .position(x: 72, y: 67)
        }
        .frame(width: 144, height: 358)
    }

    private func plantImage(_ name: String, width: CGFloat, height: CGFloat) -> some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: width, height: height)
    }
}
