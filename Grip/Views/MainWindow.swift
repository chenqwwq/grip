import SwiftUI

enum TaskFilter: String, CaseIterable {
    case all = "全部"
    case pending = "待处理"
    case completed = "已完成"
}

struct GripTheme {
    let mode: AppAppearanceMode
    let colorScheme: ColorScheme

    var usesDarkPalette: Bool {
        mode == .dark || (mode == .system && colorScheme == .dark)
    }

    var windowBackground: Color {
        usesDarkPalette ? Color(red: 0.11, green: 0.12, blue: 0.14) : Color(red: 0.95, green: 0.97, blue: 1.00)
    }

    var panelBackground: Color {
        usesDarkPalette ? Color(red: 0.13, green: 0.14, blue: 0.16) : .white
    }

    var controlBackground: Color {
        usesDarkPalette ? Color.white.opacity(0.08) : Color(red: 0.90, green: 0.94, blue: 1.00)
    }

    var selectedControlBackground: Color {
        usesDarkPalette ? Color(red: 0.04, green: 0.45, blue: 0.95) : Color(red: 0.08, green: 0.47, blue: 1.00)
    }

    var separator: Color {
        usesDarkPalette ? Color.white.opacity(0.10) : Color(red: 0.79, green: 0.86, blue: 0.96)
    }

    var primaryText: Color {
        usesDarkPalette ? Color.white.opacity(0.88) : Color(red: 0.11, green: 0.16, blue: 0.24)
    }

    var secondaryText: Color {
        usesDarkPalette ? Color.white.opacity(0.54) : Color(red: 0.42, green: 0.49, blue: 0.60)
    }

    var tertiaryText: Color {
        usesDarkPalette ? Color.white.opacity(0.36) : Color(red: 0.58, green: 0.65, blue: 0.75)
    }

    var categoryBackground: Color {
        usesDarkPalette ? Color(red: 0.10, green: 0.22, blue: 0.34) : Color(red: 0.86, green: 0.93, blue: 1.00)
    }

    var categoryForeground: Color {
        usesDarkPalette ? Color(red: 0.72, green: 0.84, blue: 1.00) : Color(red: 0.10, green: 0.34, blue: 0.70)
    }
}

struct MainWindow: View {
    @Environment(TaskManager.self) private var taskManager
    @Environment(LLMConfig.self) private var config
    @Environment(\.colorScheme) private var colorScheme
    let coordinator: AppCoordinator?
    @State private var selectedFilter: TaskFilter = .all
    @State private var selectedDate: Date = Date()
    @State private var displayedMonth: Date = Date()
    @State private var showDatePicker = false
    @State private var isDateButtonHovered = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle()
                .fill(theme.separator)
                .frame(height: 1)
            TaskListView(filter: selectedFilter, date: selectedDate, coordinator: coordinator, theme: theme)
            Rectangle()
                .fill(theme.separator)
                .frame(height: 1)
            bottomBar
        }
        .background(theme.windowBackground)
        .frame(minWidth: 720, minHeight: 520)
    }

    private var theme: GripTheme {
        GripTheme(mode: AppAppearanceMode(rawValue: config.appearanceModeRawValue) ?? .system, colorScheme: colorScheme)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Text(toolbarTitle)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            dateSelector
            Spacer()
            filterControl
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }

    private var filterControl: some View {
        HStack(spacing: 0) {
            ForEach(TaskFilter.allCases, id: \.self) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selectedFilter == filter ? Color.white : theme.primaryText)
                        .frame(width: 82, height: 34)
                        .background(selectedFilter == filter ? theme.selectedControlBackground : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(theme.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var dateSelector: some View {
        HStack(spacing: 0) {
            Button {
                displayedMonth = selectedDate
                showDatePicker.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(dateButtonTitle)
                        .font(.system(size: 17, weight: .semibold))
                    Image(systemName: showDatePicker ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(showDatePicker ? theme.selectedControlBackground : theme.secondaryText)
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(dateButtonBackground)
                .foregroundStyle(showDatePicker ? theme.selectedControlBackground : theme.primaryText)
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(dateButtonBorderColor, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
            .onHover { isDateButtonHovered = $0 }
            .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                VStack(spacing: 14) {
                    CalendarMonthPicker(
                        selectedDate: $selectedDate,
                        displayedMonth: $displayedMonth
                    ) {
                        showDatePicker = false
                    }

                    HStack {
                        Button("今天") {
                            let today = Date()
                            selectedDate = today
                            displayedMonth = today
                            showDatePicker = false
                        }
                        .buttonStyle(.borderless)

                        Spacer()
                    }
                    .padding(.horizontal, 2)
                }
                .padding(18)
                .frame(width: 360)
            }
        }
    }

    private var toolbarTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) {
            return "今日待办"
        }
        if calendar.isDateInTomorrow(selectedDate) {
            return "明日待办"
        }
        if calendar.isDateInYesterday(selectedDate) {
            return "昨日待办"
        }
        return "待办"
    }

    private var dateButtonTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: selectedDate)
    }

    private var dateButtonBackground: Color {
        if showDatePicker {
            return theme.selectedControlBackground.opacity(theme.usesDarkPalette ? 0.18 : 0.11)
        }
        if isDateButtonHovered {
            return theme.controlBackground.opacity(0.82)
        }
        return theme.controlBackground
    }

    private var dateButtonBorderColor: Color {
        if showDatePicker {
            return theme.selectedControlBackground.opacity(0.50)
        }
        if isDateButtonHovered {
            return theme.separator.opacity(0.85)
        }
        return theme.separator
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            Text("⌘⇧T 截图创建 · ⌘⇧V 剪贴板创建")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryText)
            Spacer()
            if let message = coordinator?.syncMessage {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            } else {
                Text("已同步本日任务")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }
            Button("同步到 Reminders") {
                guard let coordinator else { return }
                Task { await coordinator.syncTasks() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(theme.selectedControlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .disabled(coordinator?.isSyncing ?? true)
            SettingsLink {
                Text("设置")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(theme.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }
}

private struct CalendarMonthPicker: View {
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date
    let onSelect: () -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 8))

                Spacer()

                Text(monthTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: 24)
                }

                ForEach(monthDays) { day in
                    Button {
                        selectedDate = day.date
                        displayedMonth = day.date
                        onSelect()
                    } label: {
                        Text("\(calendar.component(.day, from: day.date))")
                            .font(.system(size: 14, weight: day.isSelected ? .semibold : .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .foregroundStyle(dayForeground(day))
                            .background(dayBackground(day))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .disabled(!day.isInDisplayedMonth)
                }
            }
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: displayedMonth)
    }

    private var monthDays: [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastVisibleDate = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: lastVisibleDate) else {
            return []
        }

        var days: [CalendarDay] = []
        var cursor = firstWeek.start
        while cursor < lastWeek.end {
            let normalized = calendar.startOfDay(for: cursor)
            days.append(CalendarDay(
                date: normalized,
                isInDisplayedMonth: calendar.isDate(normalized, equalTo: displayedMonth, toGranularity: .month),
                isSelected: calendar.isDate(normalized, inSameDayAs: selectedDate),
                isToday: calendar.isDateInToday(normalized)
            ))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? lastWeek.end
        }
        return days
    }

    private func shiftMonth(by value: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth
    }

    private func dayForeground(_ day: CalendarDay) -> Color {
        if day.isSelected {
            return .white
        }
        if !day.isInDisplayedMonth {
            return .secondary.opacity(0.45)
        }
        if day.isToday {
            return .accentColor
        }
        return .primary
    }

    @ViewBuilder
    private func dayBackground(_ day: CalendarDay) -> some View {
        if day.isSelected {
            Color.accentColor
        } else if day.isToday {
            Color.accentColor.opacity(0.12)
        } else {
            Color.clear
        }
    }
}

private struct CalendarDay: Identifiable {
    let date: Date
    let isInDisplayedMonth: Bool
    let isSelected: Bool
    let isToday: Bool

    var id: Date { date }
}
