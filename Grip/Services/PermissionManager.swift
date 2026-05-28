import AppKit
import CoreGraphics
import EventKit
import Observation

enum SystemPermissionState: Equatable {
    case unknown
    case authorized
    case denied
}

@MainActor
@Observable
final class PermissionManager {
    var screenCaptureState: SystemPermissionState = .unknown
    var remindersState: SystemPermissionState = .unknown
    var showRequiredPermissionAlert = false
    var currentAppPath: String {
        Bundle.main.bundlePath
    }
    var screenCaptureGuidance: String {
        if isRunningFromDerivedData {
            return "当前运行的是 Xcode DerivedData 里的调试包。此包目前没有稳定开发者签名，macOS 可能会把每次编译后的 Grip 当成不同应用，导致系统设置里已打开录屏权限但当前进程仍然拿不到权限。请在 Xcode 的 Signing & Capabilities 里配置 Team，或构建一个固定签名并固定路径运行的 Grip.app。"
        }

        return "系统设置里打开录屏权限后，macOS 通常需要退出并重新启动当前这个 Grip 才会让权限对运行中的进程生效。如果你已经授权，请先退出再重新打开。"
    }

    private let remindersSync: RemindersSync
    private let defaults: UserDefaults
    private let remindersPromptedKey = "permissions.remindersPromptedOnce"

    init(remindersSync: RemindersSync, defaults: UserDefaults = .standard) {
        self.remindersSync = remindersSync
        self.defaults = defaults
    }

    func prepareOnLaunch() async {
        refreshScreenCaptureAccess(presentAlertWhenDenied: false)
        await requestOptionalRemindersAccessIfFirstLaunch()
    }

    func retryRequiredPermissions() async {
        refreshScreenCaptureAccess(presentAlertWhenDenied: true)
    }

    func ensureScreenCaptureAccessForUserAction() -> Bool {
        requestScreenCaptureAccessFromUserAction()
    }

    func requestScreenCaptureAccessFromUserAction() -> Bool {
        if refreshScreenCaptureAccess(presentAlertWhenDenied: false) {
            return true
        }

        GripLogger.shared.info("用户触发录屏权限请求")
        let granted = CGRequestScreenCaptureAccess()
        GripLogger.shared.info("录屏权限请求返回: \(granted)")
        if granted, refreshScreenCaptureAccess(presentAlertWhenDenied: false) {
            return true
        }

        refreshScreenCaptureAccess(presentAlertWhenDenied: true)
        return false
    }

    func openScreenCaptureSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func quitApp() {
        NSApp.terminate(nil)
    }

    @discardableResult
    private func refreshScreenCaptureAccess(presentAlertWhenDenied: Bool) -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let bundlePath = Bundle.main.bundlePath

        if CGPreflightScreenCaptureAccess() {
            screenCaptureState = .authorized
            showRequiredPermissionAlert = false
            GripLogger.shared.info("启动权限检查: 录屏权限已授权, bundle: \(bundleID), path: \(bundlePath)")
            return true
        }

        screenCaptureState = .denied
        showRequiredPermissionAlert = presentAlertWhenDenied
        GripLogger.shared.info("录屏权限未授权或尚未对当前进程生效, bundle: \(bundleID), path: \(bundlePath), derivedData=\(isRunningFromDerivedData), presentAlert=\(presentAlertWhenDenied)")
        return false
    }

    private var isRunningFromDerivedData: Bool {
        currentAppPath.contains("/Library/Developer/Xcode/DerivedData/")
    }

    private func requestOptionalRemindersAccessIfFirstLaunch() async {
        remindersSync.refreshAuthorizationStatus()
        if remindersSync.isAuthorized {
            remindersState = .authorized
            GripLogger.shared.info("启动权限检查: Reminders 已授权")
            return
        }

        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .denied || status == .restricted {
            remindersState = .denied
            GripLogger.shared.info("启动权限检查: Reminders 权限不可用，状态: \(status.rawValue)")
            return
        }

        guard !defaults.bool(forKey: remindersPromptedKey) else {
            remindersState = .denied
            GripLogger.shared.info("启动权限检查: Reminders 已跳过重复请求")
            return
        }

        defaults.set(true, forKey: remindersPromptedKey)
        GripLogger.shared.info("启动权限检查: 首次请求 Reminders 权限")
        let granted = await remindersSync.requestAccess()
        remindersState = granted ? .authorized : .denied
        GripLogger.shared.info("启动权限检查: Reminders 权限请求结果: \(granted)")
    }
}
