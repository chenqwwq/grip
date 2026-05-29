import AppKit
import CoreGraphics
import Observation
import ScreenCaptureKit

enum InputCaptureError: LocalizedError {
    case screenCapturePermissionDenied
    case screenshotCancelled
    case screenshotFileReadFailed

    var errorDescription: String? {
        switch self {
        case .screenCapturePermissionDenied:
            "未获得录屏权限，请在系统设置中允许 Grip 录制屏幕"
        case .screenshotCancelled:
            "截图已取消"
        case .screenshotFileReadFailed:
            "截图文件读取失败"
        }
    }
}

@MainActor
@Observable
final class InputCapture {

    /// 读取剪贴板文字
    func readClipboard() -> String? {
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let text {
            GripLogger.shared.info("读取剪贴板文字，长度: \(text.count)")
        } else {
            GripLogger.shared.debug("剪贴板无文字内容")
        }
        return text
    }

    /// 读取剪贴板图片
    func readClipboardImage() -> Data? {
        let pasteboard = NSPasteboard.general

        // 1. 尝试直接读取图片数据（截图工具、浏览器复制等）
        if let rawImage = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            let image = pngData(from: rawImage) ?? rawImage
            GripLogger.shared.info("读取剪贴板图片（原始数据），大小: \(image.count) bytes")
            return image
        }

        // 2. 尝试从文件 URL 读取（Finder 复制图片文件等）
        if let urlData = pasteboard.data(forType: .fileURL),
           let url = URL(dataRepresentation: urlData, relativeTo: nil),
           let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                GripLogger.shared.info("读取剪贴板图片（文件 URL），大小: \(png.count) bytes")
                return png
            }
        }

        // 3. 通过 NSImage 通用读取（兜底，覆盖更多粘贴场景）
        if let nsImage = NSImage(pasteboard: pasteboard) {
            if let png = pngDataFromNSImage(nsImage) {
                GripLogger.shared.info("读取剪贴板图片（NSImage 兜底），大小: \(png.count) bytes")
                return png
            }
        }

        GripLogger.shared.debug("剪贴板无图片内容")
        return nil
    }

    private func pngDataFromNSImage(_ nsImage: NSImage) -> Data? {
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// 区域截图：调用系统截图工具并获取结果
    func captureArea() async throws -> Data {
        GripLogger.shared.info("开始区域截图")
        let hasPermission = CGPreflightScreenCaptureAccess()
        GripLogger.shared.info("录屏权限预检结果: \(hasPermission), bundle: \(Bundle.main.bundleIdentifier ?? "unknown"), path: \(Bundle.main.bundlePath)")
        guard hasPermission else {
            GripLogger.shared.error("录屏权限未通过预检，已取消截图")
            throw InputCaptureError.screenCapturePermissionDenied
        }

        let selectionController = ScreenSelectionController()
        guard let selectedRect = await selectionController.selectArea() else {
            GripLogger.shared.info("截图流程取消")
            throw InputCaptureError.screenshotCancelled
        }
        GripLogger.shared.info("截图选区: \(selectedRect)")

        guard let data = try await capture(rect: selectedRect) else {
            GripLogger.shared.error("截图文件读取失败")
            throw InputCaptureError.screenshotFileReadFailed
        }

        GripLogger.shared.info("截图完成，大小: \(data.count) bytes")
        return data
    }

    private func capture(rect selectedRect: CGRect) async throws -> Data? {
        guard let screen = NSScreen.screens
            .max(by: { $0.frame.intersection(selectedRect).area < $1.frame.intersection(selectedRect).area }),
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            return nil
        }

        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let displayImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        let screenRect = screen.frame
        let clippedRect = selectedRect.intersection(screenRect)
        guard clippedRect.width > 1, clippedRect.height > 1 else {
            return nil
        }

        let scaleX = CGFloat(displayImage.width) / screenRect.width
        let scaleY = CGFloat(displayImage.height) / screenRect.height
        let cropRect = CGRect(
            x: (clippedRect.minX - screenRect.minX) * scaleX,
            y: (screenRect.maxY - clippedRect.maxY) * scaleY,
            width: clippedRect.width * scaleX,
            height: clippedRect.height * scaleY
        ).integral

        guard let croppedImage = displayImage.cropping(to: cropRect) else {
            return nil
        }

        return NSBitmapImageRep(cgImage: croppedImage)
            .representation(using: .png, properties: [:])
    }

    private func pngData(from data: Data) -> Data? {
        guard let nsImage = NSImage(data: data),
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}

@MainActor
private final class ScreenSelectionController: NSObject {
    private var continuation: CheckedContinuation<CGRect?, Never>?
    private var windows: [NSWindow] = []
    private var didFinish = false

    func selectArea() async -> CGRect? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            showOverlayWindows()
        }
    }

    private func showOverlayWindows() {
        windows = NSScreen.screens.map { screen in
            let view = ScreenSelectionView(screenFrame: screen.frame)
            view.onComplete = { [weak self] rect in
                self?.finish(with: rect)
            }
            view.onCancel = { [weak self] in
                self?.finish(with: nil)
            }

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            return window
        }

        windows.first?.makeKey()
    }

    private func finish(with rect: CGRect?) {
        guard !didFinish else { return }
        didFinish = true
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        continuation?.resume(returning: rect)
        continuation = nil
    }
}

private final class ScreenSelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let screenFrame: CGRect
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    init(screenFrame: CGRect) {
        self.screenFrame = screenFrame
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = globalPoint(from: event)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = globalPoint(from: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = globalPoint(from: event)
        guard let rect = selectionRect, rect.width >= 8, rect.height >= 8 else {
            onCancel?()
            return
        }
        onComplete?(rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let rect = selectionRect else { return }
        let localRect = CGRect(
            x: rect.minX - screenFrame.minX,
            y: rect.minY - screenFrame.minY,
            width: rect.width,
            height: rect.height
        )

        NSColor.clear.setFill()
        localRect.fill(using: .clear)

        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: localRect)
        path.lineWidth = 2
        path.stroke()
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }

    private func globalPoint(from event: NSEvent) -> CGPoint {
        CGPoint(
            x: screenFrame.minX + event.locationInWindow.x,
            y: screenFrame.minY + event.locationInWindow.y
        )
    }
}
