import SwiftUI

enum TaskFilter: String, CaseIterable {
    case all = "全部"
    case pending = "待处理"
    case completed = "已完成"
}

struct MainWindow: View {
    @Environment(TaskManager.self) private var taskManager
    let coordinator: AppCoordinator?
    @State private var selectedFilter: TaskFilter = .all
    @State private var selectedDate: Date = Date()
    @State private var showDatePicker = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            TaskListView(filter: selectedFilter, date: selectedDate, coordinator: coordinator)
            Divider()
            bottomBar
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private var toolbar: some View {
        HStack {
            Text("今日待办")
                .font(.headline)
            dateSelector
            Spacer()
            Picker("", selection: $selectedFilter) {
                ForEach(TaskFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var dateSelector: some View {
        HStack(spacing: 4) {
            Button {
                shiftSelectedDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("前一天")

            Button {
                showDatePicker.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(dateButtonTitle)
                        .font(.callout.weight(.medium))
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                VStack(spacing: 10) {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { selectedDate },
                            set: {
                                selectedDate = $0
                                showDatePicker = false
                            }
                        ),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()

                    HStack {
                        Button("今天") {
                            selectedDate = Date()
                            showDatePicker = false
                        }
                        Spacer()
                    }
                }
                .padding(12)
                .frame(width: 280)
            }

            Button {
                shiftSelectedDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help("后一天")
        }
    }

    private var dateButtonTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) {
            return "今天"
        }
        if calendar.isDateInTomorrow(selectedDate) {
            return "明天"
        }
        if calendar.isDateInYesterday(selectedDate) {
            return "昨天"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: selectedDate)
    }

    private func shiftSelectedDate(by days: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
    }

    private var bottomBar: some View {
        HStack {
            Text("⌘⇧T 截图创建 · ⌘⇧V 剪贴板创建")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("同步到 Reminders") {
                guard let coordinator else { return }
                Task { await coordinator.syncTasks() }
            }
            .buttonStyle(.bordered)
            .disabled(coordinator?.isSyncing ?? true)
            if let message = coordinator?.syncMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SettingsLink {
                Text("设置")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
