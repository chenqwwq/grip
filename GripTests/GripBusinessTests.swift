import EventKit
import XCTest
@testable import Grip

@MainActor
final class GripBusinessTests: XCTestCase {
    private static var retainedManagers: [TaskManager] = []
    private static var retainedObjects: [AnyObject] = []

    func testTaskManagerCreatesEditsAndDeletesTasks() throws {
        let manager = makeTaskManager()
        let task = GripTask(title: "写周报", detail: "整理本周进展", priority: .medium, category: "工作")

        try manager.createTask(task)
        XCTAssertEqual(try manager.fetchTasks().map(\.title), ["写周报"])

        task.title = "更新周报"
        task.status = .completed
        try manager.updateTask(task)
        let updated = try XCTUnwrap(manager.fetchTasks().first)
        XCTAssertEqual(updated.title, "更新周报")
        XCTAssertEqual(updated.status, .completed)

        try manager.deleteTask(task)
        XCTAssertTrue(try manager.fetchTasks().isEmpty)
    }

    func testLLMResponseParsesJSONInsideMarkdownFence() throws {
        let service = makeLLMService()
        let response = """
        {
          "choices": [
            {
              "message": {
                "content": "```json\\n{\\\"title\\\":\\\"交周报\\\",\\\"detail\\\":\\\"发给团队\\\",\\\"category\\\":\\\"工作\\\",\\\"priority\\\":\\\"high\\\",\\\"dueDate\\\":\\\"2026-05-29 15:00\\\"}\\n```"
              }
            }
          ]
        }
        """

        let parsed = try service.parseFullResponseTest(Data(response.utf8))

        XCTAssertEqual(parsed.title, "交周报")
        XCTAssertEqual(parsed.detail, "发给团队")
        XCTAssertEqual(parsed.category, "工作")
        XCTAssertEqual(parsed.priority, "high")
        XCTAssertEqual(parsed.dueDate, "2026-05-29 15:00")
    }

    func testDateParserAcceptsDayAndMinutePrecisionFormats() throws {
        let calendar = Calendar(identifier: .gregorian)

        let dayOnly = try XCTUnwrap(GripDateParser.parse("2026-05-29", calendar: calendar))
        XCTAssertEqual(calendar.component(.year, from: dayOnly), 2026)
        XCTAssertEqual(calendar.component(.month, from: dayOnly), 5)
        XCTAssertEqual(calendar.component(.day, from: dayOnly), 29)
        XCTAssertEqual(calendar.component(.hour, from: dayOnly), 0)
        XCTAssertEqual(calendar.component(.minute, from: dayOnly), 0)

        let minutePrecision = try XCTUnwrap(GripDateParser.parse("2026-05-29 15:30", calendar: calendar))
        XCTAssertEqual(calendar.component(.hour, from: minutePrecision), 15)
        XCTAssertEqual(calendar.component(.minute, from: minutePrecision), 30)

        XCTAssertNil(GripDateParser.parse("明天下午三点", calendar: calendar))
    }

    func testWriteOnlyRemindersAuthorizationDoesNotAllowReadWriteSync() {
        XCTAssertFalse(RemindersAuthorization.allowsReadWrite(.writeOnly))
        XCTAssertTrue(RemindersAuthorization.allowsReadWrite(.fullAccess))
    }

    func testSavingLinkedTaskPushesUpdatedFieldsToReminders() throws {
        let manager = makeTaskManager()
        let task = GripTask(title: "旧标题", detail: "旧详情", priority: .low)
        task.remindersEventId = "existing-reminder"
        task.isSynced = true
        try manager.createTask(task)

        let reminders = FakeRemindersSync()
        let coordinator = makeCoordinator(taskManager: manager, remindersSync: reminders)
        let dueDate = try XCTUnwrap(GripDateParser.parse("2026-05-29 09:45"))

        try coordinator.saveTask(
            task,
            title: "新标题",
            detail: "新详情",
            category: "工作",
            priority: .high,
            dueDate: dueDate
        )

        XCTAssertEqual(reminders.syncedTasks.map(\.title), ["新标题"])
        XCTAssertEqual(reminders.syncedTasks.first?.detail, "新详情")
        XCTAssertEqual(reminders.syncedTasks.first?.priority, .high)
        XCTAssertEqual(reminders.syncedTasks.first?.dueDate, dueDate)
        XCTAssertEqual(try manager.fetchTasks().first?.title, "新标题")
    }

    func testDeletingLinkedTaskRemovesReminderBeforeDeletingLocalTask() throws {
        let manager = makeTaskManager()
        let task = GripTask(title: "删掉这个")
        task.remindersEventId = "reminder-to-remove"
        task.isSynced = true
        try manager.createTask(task)

        let reminders = FakeRemindersSync()
        let coordinator = makeCoordinator(taskManager: manager, remindersSync: reminders)

        try coordinator.deleteTask(task)

        XCTAssertEqual(reminders.removedTaskIDs, ["reminder-to-remove"])
        XCTAssertTrue(try manager.fetchTasks().isEmpty)
    }

    func testExternalRemindersCompletionChangeMarksLinkedGripTaskCompletedWithoutCreatingUnlinkedTasks() throws {
        let manager = makeTaskManager()
        let linkedTask = GripTask(title: "系统提醒里完成")
        linkedTask.remindersEventId = "completed-reminder"
        linkedTask.isSynced = true
        let unlinkedTask = GripTask(title: "还没同步")
        try manager.createTask(linkedTask)
        try manager.createTask(unlinkedTask)

        let reminders = FakeRemindersSync()
        reminders.remoteCompletionStates["completed-reminder"] = true
        let coordinator = makeCoordinator(
            taskManager: manager,
            remindersSync: reminders,
            bidirectionalCompletionSyncEnabled: true
        )

        coordinator.handleExternalRemindersChange()

        XCTAssertEqual(linkedTask.status, .completed)
        XCTAssertNotNil(linkedTask.completedAt)
        XCTAssertEqual(unlinkedTask.status, .pending)
        XCTAssertTrue(reminders.syncedTasks.isEmpty)
    }

    func testCustomLogPathTreatsDirectorySelectionAsDailyLogFileInsideDirectory() {
        let directory = URL(fileURLWithPath: "/tmp/grip-logs", isDirectory: true)
        let fileURL = GripLogger.logFileURL(forCustomPath: directory.path, selectedPathIsDirectory: true, date: Date(timeIntervalSince1970: 1_779_984_000))

        XCTAssertEqual(fileURL.path, "/tmp/grip-logs/grip-2026-05-29.log")
    }

    func testAppearanceModesExposeStableStorageValuesAndDisplayNames() {
        XCTAssertEqual(AppAppearanceMode.system.rawValue, "system")
        XCTAssertEqual(AppAppearanceMode.system.displayName, "跟随系统")
        XCTAssertEqual(AppAppearanceMode.blueWhite.rawValue, "blueWhite")
        XCTAssertEqual(AppAppearanceMode.blueWhite.displayName, "蓝白")
        XCTAssertEqual(AppAppearanceMode.dark.rawValue, "dark")
        XCTAssertEqual(AppAppearanceMode.dark.displayName, "深色")
    }

    private func makeCoordinator(
        taskManager: TaskManager,
        remindersSync: FakeRemindersSync,
        bidirectionalCompletionSyncEnabled: Bool = false
    ) -> AppCoordinator {
        let config = LLMConfig()
        config.bidirectionalCompletionSyncEnabled = bidirectionalCompletionSyncEnabled
        let service = LLMService(config: config)
        let coordinator = AppCoordinator(
            taskManager: taskManager,
            llmService: service,
            inputCapture: InputCapture(),
            remindersSync: remindersSync,
            llmConfig: config
        )
        Self.retainedObjects.append(config)
        Self.retainedObjects.append(service)
        Self.retainedObjects.append(coordinator)
        return coordinator
    }

    private func makeTaskManager() -> TaskManager {
        let manager = TaskManager(inMemory: true)
        Self.retainedManagers.append(manager)
        return manager
    }

    private func makeLLMService() -> LLMService {
        let config = LLMConfig()
        let service = LLMService(config: config)
        Self.retainedObjects.append(config)
        Self.retainedObjects.append(service)
        return service
    }

}

@MainActor
private final class FakeRemindersSync: ReminderSyncing {
    var isAuthorized = true
    var syncedTasks: [TaskSnapshot] = []
    var removedTaskIDs: [String] = []
    var remoteCompletionStates: [String: Bool] = [:]

    func refreshAuthorizationStatus() {}

    func requestAccess() async -> Bool {
        isAuthorized
    }

    func syncTask(_ task: GripTask) throws -> String? {
        syncedTasks.append(TaskSnapshot(task))
        return task.remindersEventId ?? "created-reminder"
    }

    func fetchCompletionState(for task: GripTask) -> Bool? {
        guard let id = task.remindersEventId else { return nil }
        return remoteCompletionStates[id]
    }

    func removeTask(_ task: GripTask) throws {
        if let id = task.remindersEventId {
            removedTaskIDs.append(id)
        }
    }

    func observeExternalChanges(_ handler: @escaping @MainActor () -> Void) {}
}

private struct TaskSnapshot {
    let title: String
    let detail: String?
    let priority: TaskPriority
    let dueDate: Date?

    init(_ task: GripTask) {
        self.title = task.title
        self.detail = task.detail
        self.priority = task.priority
        self.dueDate = task.dueDate
    }
}
