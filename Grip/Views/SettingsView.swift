import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable {
    case llm = "LLM 配置"
    case sync = "同步设置"
    case general = "通用"
    case shortcuts = "快捷键"

    var icon: String {
        switch self {
        case .llm: "cpu"
        case .sync: "arrow.triangle.2.circlepath"
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        }
    }
}

struct SettingsView: View {
    @Environment(LLMConfig.self) private var config
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: SettingsTab = .llm

    @State private var textAPIURL: String = ""
    @State private var textModel: String = ""
    @State private var textAPIKey: String = ""
    @State private var imageAPIURL: String = ""
    @State private var imageModel: String = ""
    @State private var imageAPIKey: String = ""
    @State private var syncMode: SyncMode = .manual
    @State private var bidirectionalCompletionSyncEnabled: Bool = false
    @State private var appearanceMode: AppAppearanceMode = .system
    @State private var logEnabled: Bool = false
    @State private var logPath: String = ""
    @State private var logPathIsDirectory: Bool = false
    @State private var saveSuccess: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            topTabBar
            settingsContainer
        }
        .background(settingsBackground)
        .preferredColorScheme(currentAppearanceMode.preferredColorScheme)
        .frame(width: 720, height: 520)
        .onAppear {
            loadConfig()
        }
        .onChange(of: appearanceMode) { _, newMode in
            config.applyAppearanceMode(newMode)
        }
    }

    private var topTabBar: some View {
        VStack(spacing: 8) {
            Text("Grip 首选项")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .padding(.top, 12)

            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selectedTab == tab ? Color.white : theme.primaryText)
                            .frame(width: 104, height: 28)
                            .background(selectedTab == tab ? theme.selectedControlBackground : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(theme.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(theme.separator, lineWidth: 1)
            }
        }
        .padding(.bottom, 10)
    }

    private var settingsContainer: some View {
        content
            .font(.system(size: 13))
            .controlSize(.small)
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 34)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(panelBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(theme.separator, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
    }

    private var settingsBackground: Color {
        theme.windowBackground
    }

    private var panelBackground: Color {
        theme.panelBackground
    }

    private var currentAppearanceMode: AppAppearanceMode {
        appearanceMode
    }

    private var theme: GripTheme {
        GripTheme(mode: currentAppearanceMode, colorScheme: colorScheme)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .llm:
            LLMSettingsPane(
                textAPIURL: $textAPIURL,
                textModel: $textModel,
                textAPIKey: $textAPIKey,
                imageAPIURL: $imageAPIURL,
                imageModel: $imageModel,
                imageAPIKey: $imageAPIKey,
                saveSuccess: saveSuccess
            ) { saveConfig() }
        case .sync:
            SyncSettingsPane(
                syncMode: $syncMode,
                bidirectionalCompletionSyncEnabled: $bidirectionalCompletionSyncEnabled,
                saveSuccess: saveSuccess
            ) { saveConfig() }
        case .general:
            GeneralSettingsPane(
                appearanceMode: $appearanceMode,
                logEnabled: $logEnabled,
                logPath: $logPath,
                logPathIsDirectory: $logPathIsDirectory,
                saveSuccess: saveSuccess
            ) { saveConfig() }
        case .shortcuts:
            ShortcutSettingsPane()
        }
    }

    private func loadConfig() {
        config.load()
        textAPIURL = config.textAdapter.apiURL
        textModel = config.textAdapter.model
        textAPIKey = KeychainHelper.loadString(key: config.textAdapter.keychainKey) ?? ""
        imageAPIURL = config.imageAdapter.apiURL
        imageModel = config.imageAdapter.model
        imageAPIKey = KeychainHelper.loadString(key: config.imageAdapter.keychainKey) ?? ""
        syncMode = config.syncMode
        bidirectionalCompletionSyncEnabled = config.bidirectionalCompletionSyncEnabled
        appearanceMode = AppAppearanceMode(rawValue: config.appearanceModeRawValue) ?? .system
        logEnabled = config.logEnabled
        logPath = config.logPath
        logPathIsDirectory = false
    }

    private func saveConfig() {
        config.textAdapter.apiURL = textAPIURL
        config.textAdapter.model = textModel
        config.imageAdapter.apiURL = imageAPIURL
        config.imageAdapter.model = imageModel
        config.syncMode = syncMode
        config.bidirectionalCompletionSyncEnabled = bidirectionalCompletionSyncEnabled
        config.applyAppearanceMode(appearanceMode, persist: false)
        config.logEnabled = logEnabled
        config.logPath = logPath

        try? KeychainHelper.saveString(key: config.textAdapter.keychainKey, value: textAPIKey)
        try? KeychainHelper.saveString(key: config.imageAdapter.keychainKey, value: imageAPIKey)

        config.save()

        GripLogger.shared.customPath = logPath
        GripLogger.shared.customPathIsDirectory = logPathIsDirectory
        GripLogger.shared.enabled = logEnabled

        saveSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            saveSuccess = false
        }
    }
}

// MARK: - Sub-Views

private struct LLMSettingsPane: View {
    @Binding var textAPIURL: String
    @Binding var textModel: String
    @Binding var textAPIKey: String
    @Binding var imageAPIURL: String
    @Binding var imageModel: String
    @Binding var imageAPIKey: String
    let saveSuccess: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LLM 模型配置")
                .font(.system(size: 14, weight: .semibold))

            HStack(alignment: .top, spacing: 12) {
                AdapterCardView(
                    title: "文本模型",
                    icon: "doc.text",
                    apiURL: $textAPIURL,
                    model: $textModel,
                    apiKey: $textAPIKey
                )
                AdapterCardView(
                    title: "图片模型",
                    icon: "photo",
                    apiURL: $imageAPIURL,
                    model: $imageModel,
                    apiKey: $imageAPIKey
                )
            }

            Spacer()

            HStack {
                Spacer()
                Button {
                    onSave()
                } label: {
                    HStack(spacing: 4) {
                        if saveSuccess {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(saveSuccess ? "已保存" : "保存")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(saveSuccess ? .green : .blue)
                .animation(.easeInOut(duration: 0.2), value: saveSuccess)
            }
            .padding(.bottom, 2)
        }
    }
}

private struct AdapterCardView: View {
    let title: String
    let icon: String
    @Binding var apiURL: String
    @Binding var model: String
    @Binding var apiKey: String

    @State private var testState: TestState = .idle

    private enum TestState {
        case idle, testing, success(String), failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))

            fieldGroup("API URL", placeholder: "https://...", text: $apiURL)
            fieldGroup("Model", placeholder: "model-name", text: $model)

            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button {
                    testConnection()
                } label: {
                    HStack(spacing: 4) {
                        if case .testing = testState {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(testButtonLabel)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isTesting || apiURL.isEmpty || apiKey.isEmpty)

                if case .success(let msg) = testState {
                        Text(msg)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                } else if case .failure(let msg) = testState {
                    Text(msg)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
        }
    }

    private var isTesting: Bool {
        if case .testing = testState { return true }
        return false
    }

    private var testButtonLabel: String {
        switch testState {
        case .idle, .success, .failure: "测试连接"
        case .testing: "测试中..."
        }
    }

    private func testConnection() {
        testState = .testing

        let baseURL = apiURL
            .replacingOccurrences(of: "/chat/completions", with: "")
            .replacingOccurrences(of: "/completions", with: "")
            .replacingOccurrences(of: "/images/generations", with: "")

        let modelsURL = baseURL.hasSuffix("/")
            ? "\(baseURL)models"
            : "\(baseURL)/models"

        guard let url = URL(string: modelsURL) else {
            testState = .failure("URL 格式错误")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                if (200...299).contains(statusCode) {
                    testState = .success("连接成功")
                } else {
                    testState = .failure("HTTP \(statusCode)")
                }
            } catch {
                testState = .failure(error.localizedDescription)
            }
        }
    }

    private func fieldGroup(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct SyncSettingsPane: View {
    @Binding var syncMode: SyncMode
    @Binding var bidirectionalCompletionSyncEnabled: Bool
    let saveSuccess: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("同步设置")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 7) {
                Text("Reminders 同步模式")
                    .font(.system(size: 13, weight: .semibold))
                Text("控制 Grip 任务如何同步到系统提醒事项")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("", selection: $syncMode) {
                    ForEach(SyncMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 7) {
                Toggle("Reminders 完成状态双向同步", isOn: $bidirectionalCompletionSyncEnabled)
                    .toggleStyle(.switch)
                    .disabled(syncMode == .off)
                Text("开启后，同步时会从 Reminders 拉取完成/待处理状态；不会因为 Reminders 删除而删除 Grip 任务。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Spacer()
                Button {
                    onSave()
                } label: {
                    HStack(spacing: 4) {
                        if saveSuccess {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(saveSuccess ? "已保存" : "保存")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(saveSuccess ? .green : .blue)
                .animation(.easeInOut(duration: 0.2), value: saveSuccess)
            }
            .padding(.bottom, 2)
        }
    }
}

private struct GeneralSettingsPane: View {
    @Binding var appearanceMode: AppAppearanceMode
    @Binding var logEnabled: Bool
    @Binding var logPath: String
    @Binding var logPathIsDirectory: Bool
    let saveSuccess: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("通用")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 7) {
                Text("外观")
                    .font(.system(size: 13, weight: .semibold))
                Text("选择 Grip 的主窗口色调，也可以跟随系统浅色或深色模式。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("", selection: $appearanceMode) {
                    ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("启用文件日志")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Toggle("", isOn: $logEnabled)
                        .toggleStyle(.switch)
                }

                if logEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("日志文件路径")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            TextField("留空使用默认 ~/Library/Logs/Grip/", text: $logPath)
                                .textFieldStyle(.roundedBorder)
                            Button("选择") {
                                let panel = NSOpenPanel()
                                panel.title = "选择日志文件位置"
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = true
                                panel.allowsMultipleSelection = false
                                panel.canCreateDirectories = true
                                if panel.runModal() == .OK, let url = panel.url {
                                    logPath = url.path
                                    logPathIsDirectory = url.hasDirectoryPath
                                    GripLogger.shared.saveBookmark(for: url)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Text(logPath.isEmpty
                            ? "默认写入 ~/Library/Logs/Grip/ 按日期分文件"
                            : logPath)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack {
                        Button("打开日志文件夹") {
                            let path = logPath.isEmpty
                                ? GripLogger.shared.currentLogPath
                                : logPath
                            let url = URL(fileURLWithPath: path)
                            let dir = url.hasDirectoryPath
                                ? url
                                : url.deletingLastPathComponent()
                            NSWorkspace.shared.open(dir)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button {
                    onSave()
                } label: {
                    HStack(spacing: 4) {
                        if saveSuccess {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(saveSuccess ? "已保存" : "保存")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(saveSuccess ? .green : .blue)
                .animation(.easeInOut(duration: 0.2), value: saveSuccess)
            }
            .padding(.bottom, 2)
        }
    }
}

private struct ShortcutSettingsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷键")
                .font(.system(size: 14, weight: .semibold))

            shortcutRow(icon: "photo", title: "区域截图创建", shortcut: "⌘⇧T")
            shortcutRow(icon: "doc.on.clipboard", title: "从剪贴板创建", shortcut: "⌘⇧V")
            shortcutRow(icon: "plus.circle", title: "手动创建任务", shortcut: "⌘N")

            Spacer()

            Text("快捷键可在系统设置 → 键盘 → 键盘快捷键中修改")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
        }
    }

    private func shortcutRow(icon: String, title: String, shortcut: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Text(shortcut)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.vertical, 3)
    }
}

private struct SidebarButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(tab.rawValue, systemImage: tab.icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .foregroundStyle(isSelected ? Color.blue : Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
