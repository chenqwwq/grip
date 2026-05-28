import SwiftUI

struct ContentView: View {
    @Environment(TaskManager.self) private var taskManager
    @Environment(LLMConfig.self) private var llmConfig
    @Environment(LLMService.self) private var llmService
    @Environment(InputCapture.self) private var inputCapture
    @Environment(StatusItemController.self) private var statusItemController
    @Environment(RemindersSync.self) private var remindersSync
    @Environment(PermissionManager.self) private var permissionManager

    @State private var coordinator: AppCoordinator?
    @State private var didPreparePermissions = false

    var body: some View {
        rootContent
            .preferredColorScheme(currentAppearanceMode.preferredColorScheme)
            .sheet(item: activeSheetBinding) { sheet in
                if let coordinator {
                    switch sheet {
                    case .detail(let task):
                        TaskDetailView(
                            task: task,
                            onSave: { task, title, detail, category, priority, dueDate in
                                try coordinator.saveTask(
                                    task,
                                    title: title,
                                    detail: detail,
                                    category: category,
                                    priority: priority,
                                    dueDate: dueDate
                                )
                            },
                            onDelete: { task in
                                try coordinator.deleteTask(task)
                            }
                        )
                            .environment(taskManager)
                    case .draft(let draft):
                        TaskDraftView(draft: draft) { updatedDraft in
                            do {
                                try coordinator.createTask(from: updatedDraft)
                            } catch {
                                GripLogger.shared.error("创建任务失败: \(error.localizedDescription)")
                            }
                        }
                    }
                } else {
                    EmptyView()
                }
            }
            .onAppear {
                if coordinator == nil {
                    llmService.config = llmConfig
                    let c = AppCoordinator(
                        taskManager: taskManager,
                        llmService: llmService,
                        inputCapture: inputCapture,
                        remindersSync: remindersSync,
                        llmConfig: llmConfig,
                        permissionManager: permissionManager
                    )
                    self.coordinator = c

                    statusItemController.onScreenshotCapture = {
                        Task { await c.handleScreenshotCapture() }
                    }
                    statusItemController.onClipboardCapture = {
                        Task { await c.handleClipboardCapture() }
                    }
                    statusItemController.onOpenMainWindow = {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
                    }
                    statusItemController.taskProvider = {
                        do {
                            return try taskManager.fetchTasks(date: Date())
                        } catch {
                            GripLogger.shared.error("加载菜单栏任务失败: \(error.localizedDescription)")
                            return []
                        }
                    }
                    statusItemController.onToggleTask = { task in
                        c.toggleCompletion(task)
                    }
                    statusItemController.onOpenTask = { task in
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
                        c.presentTask(task)
                    }
                }
            }
            .task {
                guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                guard !didPreparePermissions else { return }
                didPreparePermissions = true
                await permissionManager.prepareOnLaunch()
            }
    }

    private var rootContent: some View {
        ZStack {
            MainWindow(coordinator: coordinator)

            if let coordinator, coordinator.showOverlay {
                CreateTaskOverlay(
                    message: coordinator.overlayMessage,
                    isProcessing: coordinator.overlayIsProcessing
                )
            }

            if permissionManager.showRequiredPermissionAlert {
                requiredPermissionView
            }
        }
    }

    private var currentAppearanceMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: llmConfig.appearanceModeRawValue) ?? .system
    }

    private var requiredPermissionView: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "record.circle")
                        .font(.title2)
                        .foregroundStyle(.red)
                    Text("录屏权限尚未生效")
                        .font(.headline)
                }

                Text(permissionManager.screenCaptureGuidance)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(permissionManager.currentAppPath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .textSelection(.enabled)

                HStack {
                    Button("请求权限") {
                        _ = permissionManager.requestScreenCaptureAccessFromUserAction()
                    }
                    Button("打开系统设置") {
                        permissionManager.openScreenCaptureSettings()
                    }
                    Button("退出 Grip") {
                        permissionManager.quitApp()
                    }
                    Button("重新检查") {
                        Task { await permissionManager.retryRequiredPermissions() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(18)
            .frame(width: 380)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 20)
        }
    }

    private var activeSheetBinding: Binding<TaskSheet?> {
        Binding(
            get: { coordinator?.activeSheet },
            set: { coordinator?.activeSheet = $0 }
        )
    }
}
