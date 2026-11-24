import SwiftUI

/// 15-minute increment drum picker modal for custom session durations (`15...720` min).
struct CustomDurationPickerSheet: View {
    @Binding var selectedMinutes: Int
    let onConfirm: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftMinutes: Int = AppConfig.defaultDurationMinutes

    private var options: [Int] {
        stride(
            from: AppConfig.minDurationMinutes,
            through: AppConfig.maxDurationMinutes,
            by: AppConfig.durationStepMinutes
        ).map { $0 }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KumogakureColors.sumiBg.ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("雲隠れの時間を決める")
                        .font(KumogakureTypography.sectionHeading)
                        .foregroundStyle(KumogakureColors.washiText)

                    Text(DurationFormatter.japaneseDuration(minutes: draftMinutes))
                        .font(KumogakureTypography.heroTitle)
                        .foregroundStyle(KumogakureColors.shinonomeAccent)

                    Picker("時間", selection: $draftMinutes) {
                        ForEach(options, id: \.self) { minutes in
                            Text(DurationFormatter.japaneseDuration(minutes: minutes))
                                .foregroundStyle(KumogakureColors.washiText)
                                .tag(minutes)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxHeight: 200)
                    .sensoryFeedback(.selection, trigger: draftMinutes)

                    Button("この時間にする") {
                        selectedMinutes = draftMinutes
                        onConfirm(draftMinutes)
                        dismiss()
                    }
                    .buttonStyle(KumogakurePrimaryButtonStyle())
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundStyle(KumogakureColors.usuzumiText)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            let clamped = min(AppConfig.maxDurationMinutes, max(AppConfig.minDurationMinutes, selectedMinutes))
            let rounded = (clamped / AppConfig.durationStepMinutes) * AppConfig.durationStepMinutes
            draftMinutes = max(AppConfig.minDurationMinutes, rounded)
        }
    }
}
