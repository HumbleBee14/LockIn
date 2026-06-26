import SwiftUI

enum Theme {
    static let inkBase = Color(red: 0.078, green: 0.086, blue: 0.114)
    static let inkSurface = Color(red: 0.110, green: 0.122, blue: 0.161)
    static let inkRaised = Color(red: 0.145, green: 0.161, blue: 0.212)
    static let mist = Color(red: 0.906, green: 0.914, blue: 0.941)
    static let mistDim = Color(red: 0.541, green: 0.565, blue: 0.651)
    static let ember = Color(red: 0.910, green: 0.388, blue: 0.227)
    static let sage = Color(red: 0.435, green: 0.718, blue: 0.604)
    static let amber = Color(red: 0.914, green: 0.706, blue: 0.298)

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 40
    }

    static let cornerRadius: CGFloat = 14

    static func displayFont(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func monoFont(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.l)
            .background(Theme.inkSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}
