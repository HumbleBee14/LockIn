import SwiftUI

// weekday chips + start/end time fields, shared by the rule editor and the lock-screen stack sheet
struct ScheduleWindowPicker: View {
    @Binding var window: ScheduleWindow

    private let weekdayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Days").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mistDim)
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(1...7, id: \.self) { day in
                        let on = window.weekdays.contains(day)
                        Button {
                            if on { window.weekdays.remove(day) } else { window.weekdays.insert(day) }
                        } label: {
                            Text(weekdayLabels[day - 1])
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .background(on ? Theme.ember : Theme.inkRaised)
                                .foregroundStyle(on ? .white : Theme.mistDim)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: Theme.Spacing.xl) {
                DatePicker("Start", selection: $window.start, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $window.end, displayedComponents: .hourAndMinute)
            }
            .datePickerStyle(.field)
        }
    }
}
