import AppKit
import SwiftUI

@MainActor
@Observable
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var taskMenuItems: [NSMenuItem] = []
    private var cachedTasks: [GripTask] = []

    var onScreenshotCapture: (() -> Void)?
    var onClipboardCapture: (() -> Void)?
    var onOpenMainWindow: (() -> Void)?
    var onToggleTask: ((GripTask) -> Void)?
    var onOpenTask: ((GripTask) -> Void)?
    var taskProvider: (() -> [GripTask])?

    override init() {
        super.init()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = Self.gripMenuBarImage()
            button.imagePosition = .imageOnly
            button.toolTip = "Grip"
        }

        menu = NSMenu()
        menu.delegate = self
        rebuildMenu()
        statusItem.menu = menu
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        taskMenuItems.removeAll()
        cachedTasks = taskProvider?() ?? []

        let titleItem = NSMenuItem(title: "今日任务", action: nil, keyEquivalent: "")
        titleItem.image = Self.gripMenuBarImage(size: NSSize(width: 14, height: 14))
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        if cachedTasks.isEmpty {
            let emptyItem = NSMenuItem(title: "暂无任务", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for (index, task) in cachedTasks.prefix(10).enumerated() {
                let item = NSMenuItem(
                    title: task.title,
                    action: #selector(toggleTaskFromMenu(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                item.state = task.status == .completed ? .on : .off
                item.toolTip = taskTooltip(for: task)
                item.representedObject = task
                menu.addItem(item)
                taskMenuItems.append(item)
            }

            if cachedTasks.count > 10 {
                let moreItem = NSMenuItem(title: "还有 \(cachedTasks.count - 10) 个任务...", action: nil, keyEquivalent: "")
                moreItem.isEnabled = false
                menu.addItem(moreItem)
            }

            let detailsMenu = NSMenu()
            for (index, task) in cachedTasks.prefix(10).enumerated() {
                let item = NSMenuItem(
                    title: task.title,
                    action: #selector(openTaskFromMenu(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                item.representedObject = task
                item.toolTip = taskTooltip(for: task)
                detailsMenu.addItem(item)
            }

            let detailsItem = NSMenuItem(title: "打开任务详情", action: nil, keyEquivalent: "")
            detailsItem.submenu = detailsMenu
            menu.addItem(detailsItem)
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "区域截图创建",
            action: #selector(screenshotCapture),
            keyEquivalent: ""
        ))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(
            title: "从剪贴板创建",
            action: #selector(clipboardCapture),
            keyEquivalent: ""
        ))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "打开主窗口",
            action: #selector(openMainWindow),
            keyEquivalent: ""
        ))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "退出 Grip",
            action: #selector(quitApp),
            keyEquivalent: "q"
        ))
        menu.items.last?.target = self
    }

    @objc private func screenshotCapture() {
        onScreenshotCapture?()
    }

    @objc private func clipboardCapture() {
        onClipboardCapture?()
    }

    @objc private func openMainWindow() {
        onOpenMainWindow?()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func toggleTaskFromMenu(_ sender: NSMenuItem) {
        guard let task = sender.representedObject as? GripTask else { return }
        onToggleTask?(task)
        rebuildMenu()
    }

    @objc private func openTaskFromMenu(_ sender: NSMenuItem) {
        guard let task = sender.representedObject as? GripTask else { return }
        onOpenTask?(task)
    }

    private func taskTooltip(for task: GripTask) -> String {
        var lines: [String] = [task.title]
        lines.append("状态：\(task.status == .completed ? "已完成" : "待处理")")

        if task.priority != .none {
            lines.append("优先级：\(task.priority.rawValue)")
        }
        if let category = task.category, !category.isEmpty {
            lines.append("分类：\(category)")
        }
        if let dueDate = task.dueDate {
            lines.append("截止：\(formatMenuDate(dueDate))")
        }
        if let detail = task.detail, !detail.isEmpty {
            lines.append("")
            lines.append(detail)
        }

        return lines.joined(separator: "\n")
    }

    private func formatMenuDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func gripMenuBarImage(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage? {
        let image = NSImage(named: NSImage.Name("MenuBarIcon"))?.copy() as? NSImage
            ?? NSImage(systemSymbolName: "app", accessibilityDescription: "Grip")
        image?.isTemplate = true
        image?.size = size
        return image
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
}
