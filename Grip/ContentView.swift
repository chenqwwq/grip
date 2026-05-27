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
            .sheet(item: activeSheetBinding) { sheet in
                if let coordinator {
                    switch sheet {
                    case .detail(let task):
                        TaskDetailView(task: task)
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
                        llmConfig: llmConfig
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

    private var requiredPermissionView: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "record.circle")
                        .font(.title2)
                        .foregroundStyle(.red)
                    Text("需要录屏权限")
                        .font(.headline)
                }

                Text("Grip 需要录屏权限来截取屏幕区域并识别任务。请在系统设置中允许 Grip 录制屏幕，然后回到应用重试。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("打开系统设置") {
                        permissionManager.openScreenCaptureSettings()
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
