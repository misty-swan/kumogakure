import SwiftUI

/// Primary CTA button style with warm shinonome accent and subtle press feedback.
struct KumogakurePrimaryButtonStyle: ButtonStyle {
    var isEmphasized: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .serif, weight: .medium))
            .foregroundStyle(isEmphasized ? KumogakureColors.sumiBg : KumogakureColors.washiText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isEmphasized ? KumogakureColors.shinonomeAccent : KumogakureColors.yonagaSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isEmphasized ? Color.clear : KumogakureColors.mistBorder,
                        lineWidth: 1
                    )
            )
            .opacity(configuration.isPressed ? 0.84 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Secondary subtle text/ghost button style.
struct KumogakureSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(KumogakureTypography.subheadline)
            .foregroundStyle(KumogakureColors.washiText.opacity(configuration.isPressed ? 0.65 : 0.9))
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
    }
}

/// Pro lock badge showing both lock icon and "隠者" text (`design-system.md` §8).
struct ProBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("隠者")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(KumogakureColors.shinonomeAccent)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(KumogakureColors.shinonomeAccent.opacity(0.16))
        )
        .overlay(
            Capsule()
                .stroke(KumogakureColors.shinonomeAccent.opacity(0.45), lineWidth: 0.75)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("隠者プラン限定")
    }
}

/// Quiet selection chip used for durations and purposes.
struct KumogakureChip: View {
    let title: String
    let isSelected: Bool
    var showProBadge: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(KumogakureTypography.chipLabel)
                if showProBadge {
                    ProBadge()
                }
            }
            .foregroundStyle(isSelected ? KumogakureColors.sumiBg : KumogakureColors.washiText)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(isSelected ? KumogakureColors.shinonomeAccent : KumogakureColors.yonagaSurface.opacity(0.9))
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? KumogakureColors.shinonomeAccent : KumogakureColors.mistBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Quiet solidarity badge showing active participants or serene fallback copy (OQ-07).
struct QuietStatusBadge: View {
    let othersCount: Int?
    let zeroCopy: String

    init(othersCount: Int?, zeroCopy: String = "いま、穏やかな静寂が広がっています") {
        self.othersCount = othersCount
        self.zeroCopy = zeroCopy
    }

    private var message: String {
        if let othersCount, othersCount > 0 {
            return "現在、ほかに \(othersCount) 人が雲隠れしています"
        }
        return zeroCopy
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(KumogakureColors.asagiInfo)
                .frame(width: 6, height: 6)
            Text(message)
                .font(KumogakureTypography.caption)
                .foregroundStyle(KumogakureColors.usuzumiText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(KumogakureColors.yonagaSurface.opacity(0.75))
        )
        .overlay(
            Capsule()
                .stroke(KumogakureColors.mistBorder.opacity(0.8), lineWidth: 0.75)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Surface card container matching `yonagaSurface` + `mistBorder`.
struct KumogakureCardContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(KumogakureColors.yonagaSurface.opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(KumogakureColors.mistBorder, lineWidth: 1)
            )
    }
}
