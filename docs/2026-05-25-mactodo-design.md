# Grip 实现方式整理

更新时间：2026-05-27

本文档记录 Grip 当前代码结构、核心流程和关键实现方式。

## 技术栈

- 平台：macOS
- UI：SwiftUI + AppKit
- 本地存储：SwiftData
- 菜单栏：NSStatusItem + NSMenu
- 截图：ScreenCaptureKit + 自定义 AppKit 选区窗口
- Reminders：EventKit
- API Key：Keychain Services
- 配置：UserDefaults
- 日志：`os.Logger` + 控制台输出 + 文件日志

## 应用入口

入口文件：`Grip/Grip/Grip/GripApp.swift`

启动时创建并注入以下对象：

- `LLMConfig`
- `TaskManager`
- `LLMService`
- `InputCapture`
- `StatusItemController`
- `RemindersSync`
- `PermissionManager`

`LLMConfig` 在启动时从 UserDefaults 加载，随后同时用于设置页和 `LLMService`，避免配置对象不一致。

主窗口由 `ContentView` 承载，设置页由 `SettingsView` 承载。

## 权限管理

实现文件：`Services/PermissionManager.swift`

权限分为两类：

1. 必要权限：录屏权限
   - 启动时调用 `CGPreflightScreenCaptureAccess()` 检查。
   - 未授权时调用 `CGRequestScreenCaptureAccess()` 请求。
   - 如果仍未授权，`ContentView` 显示阻塞式权限提示。
   - 提供打开系统设置和重新检查按钮。

2. 非必要权限：Reminders 权限
   - 启动时刷新 `EKEventStore.authorizationStatus(for: .reminder)`。
   - 如果尚未询问过，则首次启动时调用 `RemindersSync.requestAccess()`。
   - 使用 UserDefaults 的 `permissions.remindersPromptedOnce` 避免每次启动重复申请。
   - 后续同步时仍会按需检查授权。

权限提示 UI 位于 `ContentView.requiredPermissionView`。

## 输入捕获

实现文件：`Services/InputCapture.swift`

### 剪贴板

`readClipboard()`：

- 从 `NSPasteboard.general` 读取 `.string`。
- 自动去除首尾空白。
- 记录读取长度。

`readClipboardImage()`：

- 优先读取 `.png`。
- 其次读取 `.tiff`。
- 如有必要转换成 PNG。
- 记录图片大小。

### 区域截图

`captureArea()` 完整流程：

1. 检查录屏权限。
2. 打开自定义选区遮罩。
3. 用户拖拽选择区域。
4. 使用 ScreenCaptureKit 截取对应屏幕。
5. 根据选区裁剪 CGImage。
6. 转换为 PNG Data。

截图不再调用 `/usr/sbin/screencapture`，避免系统把外部截图工具或调试签名变化识别成新的权限主体。

选区实现：

- `ScreenSelectionController`
  - 为每块屏幕创建一个 borderless NSWindow。
  - 窗口 level 为 `.screenSaver`。
  - 支持多屏。
  - 使用 continuation 返回选区结果。

- `ScreenSelectionView`
  - 鼠标按下记录起点。
  - 拖拽更新当前点。
  - 鼠标抬起返回全局坐标选区。
  - Escape 取消。
  - 小于 8x8 的选区视为取消。

截图实现使用：

- `SCShareableContent.excludingDesktopWindows`
- `SCContentFilter`
- `SCStreamConfiguration`
- `SCScreenshotManager.captureImage`

## LLM 识别

实现文件：`Services/LLMService.swift`

`LLMService` 支持：

- `parseFromText(_:)`
- `parseFromImage(_:)`

文本识别：

- 从 `config.textAdapter` 获取 API URL、模型名、Keychain key。
- 从 Keychain 读取 API Key。
- 使用 OpenAI Chat Completions 兼容格式提交文本。

图片识别：

- 从 `config.imageAdapter` 获取 API URL、模型名、Keychain key。
- 图片转 base64。
- 按 `image_url` content 格式提交。

响应解析：

- 先解析 OpenAI 兼容响应的 `choices[0].message.content`。
- 支持模型返回纯 JSON 或 Markdown json code block。
- 解码为 `ParsedTask`。

要求模型返回字段：

- `title`
- `detail`
- `category`
- `priority`
- `dueDate`

日期解析后续由 `AppCoordinator.parseDate(_:)` 转换成本地 Date。

## 任务协调流程

实现文件：`Helpers/AppCoordinator.swift`

`AppCoordinator` 是主要业务编排层。

### 截图创建流程

1. 调用 `InputCapture.captureArea()`。
2. 显示“正在识别截图...” overlay。
3. 调用 `LLMService.parseFromImage`。
4. 识别成功后生成 `TaskDraft`。
5. 激活应用窗口。
6. 延迟 150ms 后显示确认面板。
7. 用户确认后创建 `GripTask`。

### 剪贴板创建流程

1. 优先调用 `InputCapture.readClipboard()`。
2. 如果有文字，走文本识别。
3. 如果没有文字，调用 `readClipboardImage()`。
4. 如果有图片，走图片识别。
5. 如果都没有，显示失败提示。

### 任务确认

识别结果先进入 `TaskDraft`，不会直接写入 SwiftData。

`TaskSheet` 统一承载：

- `.draft(TaskDraft)`
- `.detail(GripTask)`

这样确认面板和详情面板都通过根视图的 `.sheet(item:)` 展示，避免子视图 sheet 不稳定。

## 数据模型

实现文件：

- `Models/GripTask.swift`
- `Models/TaskDraft.swift`
- `Models/TaskSheet.swift`

### GripTask

SwiftData 模型字段：

- `id`
- `title`
- `detail`
- `status`
- `priority`
- `sourceType`
- `sourceContent`
- `sourceText`
- `category`
- `dueDate`
- `completedAt`
- `createdAt`
- `updatedAt`
- `remindersEventId`
- `isSynced`

`sourceContent` 使用 SwiftData external storage，适合存储截图或剪贴板图片。

### TaskDraft

用于识别结果确认阶段。

`makeTask()` 将草稿转换为 `GripTask`。

## 本地任务管理

实现文件：`Services/TaskManager.swift`

`TaskManager` 持有：

- `ModelContainer`
- `ModelContext`
- `changeToken`

提供方法：

- `createTask`
- `fetchTasks`
- `updateTask`
- `deleteTask`
- `completeTask`
- `markPending`

`changeToken` 每次数据变更后刷新，列表通过监听它重新加载。

任务按 `createdAt` 倒序排列。

按日期查询时使用当天起止时间过滤 `createdAt`。

## 主窗口 UI

实现文件：

- `Views/MainWindow.swift`
- `Views/TaskListView.swift`
- `Views/TaskRowView.swift`
- `Views/TaskDetailView.swift`
- `Views/TaskDraftView.swift`

### MainWindow

主结构：

- 顶部 toolbar
- 中间 TaskListView
- 底部 bottomBar

日期选择：

- 自定义按钮显示“今天 / 明天 / 昨天 / M月d日”。
- 点击弹出 graphical DatePicker。
- 左右箭头快速切换日期。

筛选：

- 使用 segmented Picker。
- 筛选值为 `TaskFilter`。

### TaskListView

加载所选日期任务后，在内存中过滤状态：

- all
- pending
- completed

这样避免 SwiftData 枚举 predicate 在部分情况下行为不稳定。

### TaskRowView

行结构：

- 左侧完成按钮。
- 中间标题、标签、优先级和截止时间。
- 右侧摘要、来源、同步状态、创建时间。
- 最右来源图标。

点击行为：

- 左侧圆圈只负责完成或恢复待处理。
- 其余整行点击打开详情。

分隔线：

- 使用 1px Rectangle。
- 左侧留出完成按钮宽度，避免横线穿过按钮。

### TaskDetailView 和 TaskDraftView

两者都包含详细描述 `TextEditor`。

输入框样式：

- body 字体
- 内部 padding
- text background
- 圆角边框

这样避免文字贴边或被遮挡。

## 菜单栏实现

实现文件：`Helpers/StatusItemController.swift`

使用：

- `NSStatusBar.system.statusItem`
- `NSMenu`
- `NSMenuDelegate`

菜单每次打开时通过 `menuWillOpen` 重建，保证任务列表是最新的。

菜单项：

- 今日任务
- 最多 10 个任务项
- 打开任务详情子菜单
- 区域截图创建
- 从剪贴板创建
- 打开主窗口
- 退出 Grip

任务菜单项：

- `representedObject` 保存 `GripTask`。
- 点击主任务项切换完成状态。
- 点击详情子菜单打开详情。
- `toolTip` 展示任务标题、状态、优先级、分类、截止时间、详细描述。

## Reminders 同步

实现文件：`Services/RemindersSync.swift`

使用 EventKit：

- `EKEventStore`
- `EKReminder`

授权：

- `refreshAuthorizationStatus()` 刷新当前状态。
- `requestAccess()` 在未授权时请求 Reminders 完整访问。
- 已授权时直接返回 true，避免重复请求。

同步：

- 如果任务已有 `remindersEventId`，尝试更新已有 reminder。
- 否则创建新的 reminder。
- 同步成功后将 `calendarItemIdentifier` 写回本地任务。

同步字段：

- title
- notes
- priority
- dueDateComponents
- isCompleted

双向完成状态同步：

- `AppCoordinator.syncTasks()` 中，如果开启双向同步，先从 Reminders 拉取完成状态。
- 本地状态不同则更新本地。
- 如果远端 reminder 不存在，清除本地同步关联，不删除本地任务。
- 本地完成状态变化后，满足条件时推送到 Reminders。

同步模式来自 `LLMConfig.syncMode`：

- automatic
- manual
- off

## 配置和 Keychain

实现文件：

- `Models/LLMConfig.swift`
- `Services/KeychainHelper.swift`
- `Views/SettingsView.swift`

`LLMConfig` 保存：

- 文本模型配置
- 图片模型配置
- 同步模式
- 双向完成状态同步开关
- 日志开关
- 日志路径

模型配置字段：

- name
- apiURL
- model
- keychainKey

API Key 存储：

- Keychain service 固定为 `cn.chenqwwq.Grip`。
- 使用 account 区分不同 key。
- 写入时优先 update，找不到再 add，避免删除后重建导致系统频繁询问钥匙串。
- 内存缓存已读取的字符串，减少重复 Keychain 访问。
- 支持迁移旧的 account-only Keychain 项。

## 日志实现

实现文件：`Helpers/GripLogger.swift`

日志输出：

- `os.Logger`
- `print` / stderr
- 文件日志

日志配置：

- `LLMConfig.logEnabled`
- `LLMConfig.logPath`

如果用户指定沙盒外路径，使用 bookmark 保持访问能力。

关键错误即使关闭文件日志，也会输出到控制台，方便排查识别和同步失败。

## 已处理的问题

当前实现已经覆盖以下问题：

- 剪贴板图片可识别。
- 文字识别和图片识别失败会输出日志并显示失败提示。
- API Key 不再因重复删除添加 Keychain 项而频繁请求钥匙串。
- 识别成功后先弹确认面板，再创建任务。
- 待处理 tab 能正确展示任务。
- 任务行除完成按钮外可整行点击。
- 菜单栏展示任务列表，并可完成任务。
- 菜单栏任务 hover 展示详情。
- Grip 和 Reminders 完成状态可双向同步，并由设置开关控制。
- 状态栏菜单支持退出 Grip。
- 日期选择改为点选式。
- 区域截图改为 ScreenCaptureKit，避免外部 screencapture 权限主体不稳定。
- 启动时统一处理必要和非必要系统权限。

## 构建验证

当前推荐验证命令：

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Grip/Grip/Grip.xcodeproj \
  -scheme Grip \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/grip-derived \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build
```

修改代码后必须保证编译通过。
