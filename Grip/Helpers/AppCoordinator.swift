import SwiftUI
import Observation
import AppKit

@MainActor
@Observable
final class AppCoordinator {
    var activeSheet: TaskSheet?
    var showOverlay = false
    var overlayMessage = ""
    var overlayIsProcessing = true
    var syncMessage: String?
    var isSyncing = false

    private let taskManager: TaskManager
    private let llmService: LLMService
    private let inputCapture: InputCapture
    private let remindersSync: ReminderSyncing
    private let llmConfig: LLMConfig
    private let permissionManager: PermissionManager?

    init(
        taskManager: TaskManager,
        llmService: LLMService,
        inputCapture: InputCapture,
        remindersSync: ReminderSyncing,
        llmConfig: LLMConfig,
        permissionManager: PermissionManager? = nil
    ) {
        self.taskManager = taskManager
        self.llmService = llmService
        self.inputCapture = inputCapture
        self.remindersSync = remindersSync
        self.llmConfig = llmConfig
        self.permissionManager = permissionManager

        remindersSync.observeExternalChanges { [weak self] in
            self?.handleExternalRemindersChange()
        }
    }

    func handleScreenshotCapture() async {
        if let permissionManager,
           !permissionManager.ensureScreenCaptureAccessForUserAction() {
            GripLogger.shared.error("截图流程取消: 录屏权限未授权或尚未对当前进程生效")
            showFailure("录屏权限未授权或尚未生效，请按提示处理后重试")
            return
        }

        let imageData: Data
        do {
            imageData = try await inputCapture.captureArea()
        } catch InputCaptureError.screenshotCancelled {
            GripLogger.shared.info("截图流程取消")
            return
        } catch {
            GripLogger.shared.error("截图流程失败: \(error.localizedDescription)")
            showFailure(error.localizedDescription)
            return
        }

        showOverlay = true
        overlayIsProcessing = true
        overlayMessage = "正在识别截图..."
        GripLogger.shared.info("开始截图识别流程")

        do {
            let parsed = try await llmService.parseFromImage(imageData)
            GripLogger.shared.info("截图识别成功: \(parsed.title)")
            let draft = TaskDraft(
                title: parsed.title,
                detail: parsed.detail,
                category: parsed.category,
                priority: parsePriority(parsed.priority),
                dueDate: parseDate(parsed.dueDate),
                sourceType: .screenshot,
                sourceContent: imageData
            )
            showOverlay = false
            presentDraft(draft)
        } catch {
            GripLogger.shared.error("截图识别失败: \(error.localizedDescription)")
            showFailure("截图识别失败：\(error.localizedDescription)")
        }
    }

    func handleClipboardCapture() async {
        if let text = inputCapture.readClipboard(), !text.isEmpty {
            await handleClipboardText(text)
            return
        }

        if let imageData = inputCapture.readClipboardImage() {
            await handleClipboardImage(imageData)
            return
        }

        GripLogger.shared.info("剪贴板流程取消: 无文字或图片")
        showFailure("剪贴板没有可识别的文字或图片")
    }

    private func handleClipboardText(_ text: String) async {
        showOverlay = true
        overlayIsProcessing = true
        overlayMessage = "正在识别文本..."
        GripLogger.shared.info("开始文本识别流程")

        do {
            let parsed = try await llmService.parseFromText(text)
            GripLogger.shared.info("文本识别成功: \(parsed.title)")
            let draft = TaskDraft(
                title: parsed.title,
                detail: parsed.detail,
                category: parsed.category,
                priority: parsePriority(parsed.priority),
                dueDate: parseDate(parsed.dueDate),
                sourceType: .clipboard,
                sourceText: text
            )
            showOverlay = false
            presentDraft(draft)
        } catch {
            GripLogger.shared.error("文本识别失败: \(error.localizedDescription)")
            showFailure("文本识别失败：\(error.localizedDescription)")
        }
    }

    private func handleClipboardImage(_ imageData: Data) async {
        showOverlay = true
        overlayIsProcessing = true
        overlayMessage = "正在识别剪贴板图片..."
        GripLogger.shared.info("开始剪贴板图片识别流程")

        do {
            let parsed = try await llmService.parseFromImage(imageData)
            GripLogger.shared.info("剪贴板图片识别成功: \(parsed.title)")
            let draft = TaskDraft(
                title: parsed.title,
                detail: parsed.detail,
                category: parsed.category,
                priority: parsePriority(parsed.priority),
                dueDate: parseDate(parsed.dueDate),
                sourceType: .clipboard,
                sourceContent: imageData
            )
            showOverlay = false
            presentDraft(draft)
        } catch {
            GripLogger.shared.error("剪贴板图片识别失败: \(error.localizedDescription)")
            showFailure("图片识别失败：\(error.localizedDescription)")
        }
    }

    func presentTask(_ task: GripTask) {
        activeSheet = .detail(task)
    }

    private func presentDraft(_ draft: TaskDraft) {
        GripLogger.shared.info("准备显示任务确认面板: \(draft.title)")
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.forEach { window in
            window.makeKeyAndOrderFront(nil)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            GripLogger.shared.info("显示任务确认面板: \(draft.title)")
            activeSheet = .draft(draft)
        }
    }

    func createTask(from draft: TaskDraft) throws {
        let task = draft.makeTask()
        try taskManager.createTask(task)
        GripLogger.shared.info("任务已创建: \(task.title)")
        if llmConfig.syncMode == .automatic {
            Task { await syncTasks() }
        }
    }

    func saveTask(
        _ task: GripTask,
        title: String,
        detail: String?,
        category: String?,
        priority: TaskPriority,
        dueDate: Date?
    ) throws {
        task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        task.category = category?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        task.priority = priority
        task.dueDate = dueDate
        try taskManager.updateTask(task)

        if shouldPushTaskEdit(task) {
            try syncTaskAfterEnsuringAccess(task)
        }
    }

    func deleteTask(_ task: GripTask) throws {
        if task.remindersEventId != nil {
            try removeReminderAfterEnsuringAccess(for: task)
        }
        try taskManager.deleteTask(task)
        GripLogger.shared.info("任务已删除: \(task.title)")
    }

    func syncTasks() async {
        guard !isSyncing else { return }
        guard llmConfig.syncMode != .off else {
            showTransientMessage("Reminders 同步已关闭")
            return
        }
        isSyncing = true
        syncMessage = nil
        defer { isSyncing = false }

        do {
            if !remindersSync.isAuthorized {
                let granted = await remindersSync.requestAccess()
                guard granted else {
                    showTransientMessage("未获得 Reminders 权限")
                    return
                }
            }

            let tasks = try taskManager.fetchTasks()
            var syncedCount = 0
            for task in tasks where task.status != .cancelled {
                if llmConfig.bidirectionalCompletionSyncEnabled {
                    applyRemoteCompletionStateIfNeeded(to: task)
                }
                try syncTask(task)
                syncedCount += 1
            }
            showTransientMessage("已同步 \(syncedCount) 个任务")
        } catch {
            showTransientMessage("同步失败：\(error.localizedDescription)")
            GripLogger.shared.error("同步 Reminders 失败: \(error.localizedDescription)")
        }
    }

    func toggleCompletion(_ task: GripTask) {
        do {
            if task.status == .completed {
                try taskManager.markPending(task)
            } else {
                try taskManager.completeTask(task)
            }

            if shouldPushCompletionChange(task) {
                Task { await syncTaskAfterLocalCompletionChange(task) }
            }
        } catch {
            GripLogger.shared.error("切换任务状态失败: \(error.localizedDescription)")
        }
    }

    func handleExternalRemindersChange() {
        guard !isSyncing else { return }
        guard llmConfig.syncMode != .off else { return }
        guard llmConfig.bidirectionalCompletionSyncEnabled else { return }

        remindersSync.refreshAuthorizationStatus()
        guard remindersSync.isAuthorized else { return }

        do {
            let tasks = try taskManager.fetchTasks()
            for task in tasks where task.status != .cancelled && task.remindersEventId != nil {
                applyRemoteCompletionStateIfNeeded(to: task)
            }
        } catch {
            GripLogger.shared.error("处理 Reminders 外部变更失败: \(error.localizedDescription)")
        }
    }

    private func syncTask(_ task: GripTask) throws {
        if let reminderID = try remindersSync.syncTask(task) {
            task.remindersEventId = reminderID
            task.isSynced = true
            try taskManager.updateTask(task)
        }
    }

    private func syncTaskAfterLocalCompletionChange(_ task: GripTask) async {
        do {
            guard await ensureRemindersAccess() else { return }
            try syncTask(task)
        } catch {
            GripLogger.shared.error("同步任务完成状态到 Reminders 失败: \(error.localizedDescription)")
        }
    }

    private func syncTaskAfterEnsuringAccess(_ task: GripTask) throws {
        guard remindersSync.isAuthorized else {
            throw AppCoordinatorError.remindersAccessDenied
        }
        try syncTask(task)
    }

    private func removeReminderAfterEnsuringAccess(for task: GripTask) throws {
        guard remindersSync.isAuthorized else {
            throw AppCoordinatorError.remindersAccessDenied
        }
        try remindersSync.removeTask(task)
    }

    private func applyRemoteCompletionStateIfNeeded(to task: GripTask) {
        guard let isCompleted = remindersSync.fetchCompletionState(for: task) else {
            if task.remindersEventId != nil {
                task.remindersEventId = nil
                task.isSynced = false
                try? taskManager.updateTask(task)
                GripLogger.shared.info("Reminders 任务不存在，已保留 Grip 任务并清除同步关联: \(task.title)")
            }
            return
        }

        if isCompleted, task.status != .completed {
            try? taskManager.completeTask(task)
            GripLogger.shared.info("从 Reminders 同步完成状态: \(task.title)")
        } else if !isCompleted, task.status == .completed {
            try? taskManager.markPending(task)
            GripLogger.shared.info("从 Reminders 同步待处理状态: \(task.title)")
        }
    }

    private func ensureRemindersAccess() async -> Bool {
        if remindersSync.isAuthorized { return true }
        let granted = await remindersSync.requestAccess()
        if !granted {
            syncMessage = "未获得 Reminders 权限"
        }
        return granted
    }

    private func shouldPushCompletionChange(_ task: GripTask) -> Bool {
        guard llmConfig.syncMode != .off else { return false }
        return llmConfig.syncMode == .automatic || task.remindersEventId != nil
    }

    private func shouldPushTaskEdit(_ task: GripTask) -> Bool {
        guard llmConfig.syncMode != .off else { return false }
        return llmConfig.syncMode == .automatic || task.remindersEventId != nil
    }

    private func parsePriority(_ rawValue: String?) -> TaskPriority {
        guard let rawValue else { return .none }
        return TaskPriority(rawValue: rawValue) ?? .none
    }

    private func showFailure(_ message: String) {
        overlayIsProcessing = false
        overlayMessage = message
        showOverlay = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if overlayMessage == message {
                showOverlay = false
            }
        }
    }

    private func showTransientMessage(_ message: String) {
        overlayIsProcessing = false
        overlayMessage = message
        showOverlay = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if overlayMessage == message {
                showOverlay = false
            }
        }
    }

    private func parseDate(_ dateString: String?) -> Date? {
        GripDateParser.parse(dateString)
    }
}

enum AppCoordinatorError: LocalizedError {
    case remindersAccessDenied

    var errorDescription: String? {
        switch self {
        case .remindersAccessDenied:
            "未获得 Reminders 权限"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
