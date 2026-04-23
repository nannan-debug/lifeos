import SwiftUI

enum CreamTheme {
    static let bgTop = Color(red: 0.96, green: 0.96, blue: 0.91)
    static let bgBottom = Color(red: 0.93, green: 0.97, blue: 0.92)
    static let text = Color(red: 0.15, green: 0.20, blue: 0.15)
    static let green = Color(red: 0.24, green: 0.65, blue: 0.36)
    static let glass = Color.white.opacity(0.72)
    static let glassStrong = Color.white.opacity(0.82)
    static let border = Color.white.opacity(0.7)
}

struct CreamBackground: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            LinearGradient(colors: [CreamTheme.bgTop, .white, CreamTheme.bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            content
        }
    }
}

extension View {
    func creamBackground() -> some View { modifier(CreamBackground()) }
}
