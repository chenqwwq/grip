import EventKit
import Foundation
import Observation

@MainActor
@Observable
final class RemindersSync {
    private let eventStore = EKEventStore()
    var isAuthorized = false

    func refreshAuthorizationStatus() {
        isAuthorized = Self.currentAuthorizationStatusAllowsAccess
    }

    /// 请求 Reminders 权限
    func requestAccess() async -> Bool {
        if Self.currentAuthorizationStatusAllowsAccess {
            isAuthorized = true
            return true
        }

        do {
            isAuthorized = try await eventStore.requestFullAccessToReminders()
            return isAuthorized
        } catch {
            GripLogger.shared.error("请求 Reminders 权限失败: \(error.localizedDescription)")
            return false
        }
    }

    /// 同步单个任务到 Reminders
    func syncTask(_ task: GripTask) throws -> String? {
        guard isAuthorized else { return nil }

        if let eventId = task.remindersEventId,
           let existing = eventStore.calendarItem(withIdentifier: eventId) as? EKReminder {
            return try updateReminder(existing, from: task)
        }

        return try createReminder(from: task)
    }

    func fetchCompletionState(for task: GripTask) -> Bool? {
        guard isAuthorized,
              let eventId = task.remindersEventId,
              let reminder = eventStore.calendarItem(withIdentifier: eventId) as? EKReminder else {
            return nil
        }
        return reminder.isCompleted
    }

    /// 从 Reminders 删除
    func removeTask(_ task: GripTask) throws {
        guard isAuthorized,
              let eventId = task.remindersEventId,
              let reminder = eventStore.calendarItem(withIdentifier: eventId) as? EKReminder else {
            return
        }
        try eventStore.remove(reminder, commit: true)
    }

    private func createReminder(from task: GripTask) throws -> String? {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = task.title
        reminder.notes = task.detail
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        reminder.dueDateComponents = dueDateComponents(from: task.dueDate)

        reminder.priority = mapPriority(task.priority)
        reminder.isCompleted = task.status == .completed

        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    private func updateReminder(_ reminder: EKReminder, from task: GripTask) throws -> String? {
        reminder.title = task.title
        reminder.notes = task.detail
        reminder.priority = mapPriority(task.priority)
        reminder.isCompleted = task.status == .completed

        reminder.dueDateComponents = dueDateComponents(from: task.dueDate)

        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    private func mapPriority(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: return 1
        case .medium: return 5
        case .low: return 9
        case .none: return 0
        }
    }

    private func dueDateComponents(from date: Date?) -> DateComponents? {
        guard let date else { return nil }
        return Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
    }

    private static var currentAuthorizationStatusAllowsAccess: Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .writeOnly:
            return true
        case .authorized:
            return true
        case .notDetermined, .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }
}
