import SwiftUI

struct TaskRowView: View {
    let task: GripTask
    let theme: GripTheme
    let onToggleCompletion: () -> Void
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Button {
                    onToggleCompletion()
                } label: {
                    Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.status == .completed ? theme.selectedControlBackground : theme.secondaryText)
                        .font(.system(size: 23, weight: .medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Button {
                    onSelect()
                } label: {
                    HStack(alignment: .center, spacing: 22) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.system(size: 18, weight: .semibold))
                                .strikethrough(task.status == .completed)
                                .foregroundStyle(task.status == .completed ? theme.secondaryText : theme.primaryText)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 7) {
                                if let category = task.category {
                                    categoryTag(category)
                                }
                                priorityTag(task.priority)
                                if let due = task.dueDate {
                                    Text(formatDueDate(due))
                                        .font(.caption2)
                                        .foregroundStyle(due < Date() ? .red : .orange)
                                }
                            }
                        }
                        .frame(minWidth: 220, maxWidth: 360, alignment: .leading)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(summaryText)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 8) {
                                sourceBadge
                                if task.isSynced {
                                    metaBadge("已同步", systemImage: "arrow.triangle.2.circlepath", color: theme.secondaryText)
                                } else {
                                    metaBadge("未同步", systemImage: "icloud.slash", color: theme.tertiaryText)
                                }
                                Text(formatCreatedAt(task.createdAt))
                                    .font(.caption2)
                                    .foregroundStyle(theme.tertiaryText)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        sourceIcon
                            .frame(width: 20)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 22)

            HStack(spacing: 10) {
                Color.clear
                    .frame(width: 28)
                Rectangle()
                    .fill(theme.separator)
                    .frame(height: 1)
            }
        }
    }

    private func formatDueDate(_ date: Date) -> String {
        let f = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            f.dateFormat = "今天 HH:mm"
            return f.string(from: date)
        } else if cal.isDateInTomorrow(date) {
            f.dateFormat = "明天 HH:mm"
            return f.string(from: date)
        } else {
            f.dateFormat = "MM/dd HH:mm"
            return f.string(from: date)
        }
    }

    private func formatCreatedAt(_ date: Date) -> String {
        let f = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            f.dateFormat = "HH:mm 创建"
        } else {
            f.dateFormat = "MM/dd 创建"
        }
        return f.string(from: date)
    }

    private func categoryTag(_ category: String) -> some View {
        Text(category)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.categoryBackground)
            .foregroundStyle(theme.categoryForeground)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func priorityTag(_ priority: TaskPriority) -> some View {
        if priority != .none {
            Text(priority.rawValue)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(priorityColor(priority).opacity(0.15))
                .foregroundStyle(priorityColor(priority))
                .clipShape(Capsule())
        }
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high: .red
        case .medium: .orange
        case .low: .green
        case .none: .gray
        }
    }

    private var sourceIcon: some View {
        Group {
            switch task.sourceType {
            case .screenshot:
                Image(systemName: "photo")
            case .clipboard:
                Image(systemName: "doc.on.clipboard")
            case .manual:
                Image(systemName: "pencil")
            }
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(theme.secondaryText)
    }

    private var summaryText: String {
        if let detail = task.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
            return detail
        }
        if let sourceText = task.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceText.isEmpty {
            return sourceText
        }
        if let dueDate = task.dueDate {
            return "截止时间 \(formatDueDate(dueDate))"
        }
        return sourceDescription
    }

    private var sourceDescription: String {
        switch task.sourceType {
        case .screenshot:
            return "由截图识别创建"
        case .clipboard:
            return "由剪贴板内容创建"
        case .manual:
            return "手动创建"
        }
    }

    private var sourceBadge: some View {
        metaBadge(sourceLabel, systemImage: sourceSystemImage, color: theme.secondaryText)
    }

    private var sourceLabel: String {
        switch task.sourceType {
        case .screenshot:
            return "截图"
        case .clipboard:
            return "剪贴板"
        case .manual:
            return "手动"
        }
    }

    private var sourceSystemImage: String {
        switch task.sourceType {
        case .screenshot:
            return "photo"
        case .clipboard:
            return "doc.on.clipboard"
        case .manual:
            return "pencil"
        }
    }

    private func metaBadge(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
    }
}
