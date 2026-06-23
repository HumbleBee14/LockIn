import SwiftUI

struct DisclosureCallout: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.mist)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mistDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.m)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
    }
}

enum Disclosures {
    static var cannotCancel: some View {
        DisclosureCallout(
            icon: "lock.fill", tint: Theme.ember,
            title: "A locked block can't be cancelled early",
            message: "Once started, it holds until the window ends — no off switch.")
    }

}
