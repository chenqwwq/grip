import SwiftUI

extension AppAppearanceMode {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .blueWhite: .light
        case .dark: .dark
        }
    }
}

@main
struct GripApp: App {
    @State private var llmConfig: LLMConfig
    @State private var taskManager: TaskManager
    @State private var llmService: LLMService
    @State private var inputCapture = InputCapture()
    @State private var statusItemController = StatusItemController()
    @State private var remindersSync: RemindersSync
    @State private var permissionManager: PermissionManager

    init() {
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let config = LLMConfig()
        let remindersSync = RemindersSync()
        config.load()
        _llmConfig = State(initialValue: config)
        _taskManager = State(initialValue: TaskManager(inMemory: isRunningTests))
        _llmService = State(initialValue: LLMService(config: config))
        _remindersSync = State(initialValue: remindersSync)
        _permissionManager = State(initialValue: PermissionManager(remindersSync: remindersSync))
        if !isRunningTests {
            GripLogger.shared.customPath = config.logPath
            GripLogger.shared.enabled = config.logEnabled
            GripLogger.shared.info("Grip 启动")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(taskManager)
                .environment(llmConfig)
                .environment(llmService)
                .environment(inputCapture)
                .environment(statusItemController)
                .environment(remindersSync)
                .environment(permissionManager)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("区域截图创建任务") {
                    statusItemController.onScreenshotCapture?()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("从剪贴板创建任务") {
                    statusItemController.onClipboardCapture?()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(llmConfig)
                .preferredColorScheme((AppAppearanceMode(rawValue: llmConfig.appearanceModeRawValue) ?? .system).preferredColorScheme)
        }
    }
}
