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

    private let remindersSync: RemindersSync
    private let defaults: UserDefaults
    private let remindersPromptedKey = "permissions.remindersPromptedOnce"

    init(remindersSync: RemindersSync, defaults: UserDefaults = .standard) {
        self.remindersSync = remindersSync
        self.defaults = defaults
    }

    func prepareOnLaunch() async {
        await requestRequiredScreenCaptureAccess()
        await requestOptionalRemindersAccessIfFirstLaunch()
    }

    func retryRequiredPermissions() async {
        await requestRequiredScreenCaptureAccess()
    }

    func openScreenCaptureSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func requestRequiredScreenCaptureAccess() async {
        if CGPreflightScreenCaptureAccess() {
            screenCaptureState = .authorized
            showRequiredPermissionAlert = false
            GripLogger.shared.info("启动权限检查: 录屏权限已授权")
            return
        }

        GripLogger.shared.info("启动权限检查: 开始请求录屏权限")
        let granted = CGRequestScreenCaptureAccess()
        screenCaptureState = granted ? .authorized : .denied
        showRequiredPermissionAlert = !granted
        GripLogger.shared.info("启动权限检查: 录屏权限请求结果: \(granted)")
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
