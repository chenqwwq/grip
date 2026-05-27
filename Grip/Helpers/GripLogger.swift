import Foundation
import os

final class GripLogger {
    static let shared = GripLogger()
    private let logger = Logger(subsystem: "cn.chenqwwq.Grip", category: "general")

    private var logFileURL: URL?
    private var securityScopedURL: URL?

    var enabled: Bool = false {
        didSet {
            if enabled { prepareLogFile() }
        }
    }

    var customPath: String = "" {
        didSet {
            if enabled { prepareLogFile() }
        }
    }

    var currentLogPath: String {
        logFileURL?.path ?? ""
    }

    private let bookmarkKey = "com.grip.log-bookmark"

    private init() {}

    // MARK: - Bookmark

    func saveBookmark(for url: URL) {
        // 需要在 NSOpenPanel 的 context 中获取 security-scoped bookmark
        guard let data = try? url.bookmarkData() else { return }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    private func restoreBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
        if stale {
            if let newData = try? url.bookmarkData() {
                UserDefaults.standard.set(newData, forKey: bookmarkKey)
            }
        }
        return url
    }

    // MARK: - File Setup

    private func prepareLogFile() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil

        if !customPath.isEmpty {
            // 用户指定路径：通过 bookmark 获取沙盒外访问权限
            let url = URL(fileURLWithPath: customPath)
            let dir = url.deletingLastPathComponent().path

            if let bookmarkURL = restoreBookmark() {
                if bookmarkURL.startAccessingSecurityScopedResource() {
                    securityScopedURL = bookmarkURL
                }
            }

            do {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            } catch {
                logger.error("创建日志目录失败: \(error.localizedDescription)")
            }

            if !FileManager.default.fileExists(atPath: url.path) {
                let created = FileManager.default.createFile(atPath: url.path, contents: nil)
                if !created {
                    logger.error("创建日志文件失败: \(url.path)")
                }
            }

            logFileURL = url
        } else {
            // 默认路径：~/Library/Logs/Grip/（沙盒内容器）
            let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("Grip", isDirectory: true)

            do {
                try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            } catch {
                logger.error("创建默认日志目录失败: \(error.localizedDescription)")
            }

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let fileName = "grip-\(dateFormatter.string(from: Date())).log"

            let url = logsDir.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: url.path) {
                let created = FileManager.default.createFile(atPath: url.path, contents: nil)
                if !created {
                    logger.error("创建默认日志文件失败: \(url.path)")
                }
            }
            logFileURL = url
        }

        osLog("日志文件: \(logFileURL?.path ?? "未知")")
    }

    // MARK: - Log Methods

    func info(_ message: String) {
        logger.info("\(message)")
        console("[INFO] \(timestamp()) \(message)")
        write("[INFO] \(timestamp()) \(message)")
    }

    func error(_ message: String) {
        logger.error("\(message)")
        let line = "[ERROR] \(timestamp()) \(message)"
        console(line, isError: true)
        write(line, force: true)
    }

    func debug(_ message: String) {
        logger.debug("\(message)")
        console("[DEBUG] \(timestamp()) \(message)")
        write("[DEBUG] \(timestamp()) \(message)")
    }

    private func write(_ line: String, force: Bool = false) {
        guard enabled || force else { return }
        if logFileURL == nil {
            prepareLogFile()
        }
        guard let url = logFileURL else { return }
        let lineWithNewline = line + "\n"
        guard let data = lineWithNewline.data(using: .utf8) else { return }

        // 同步写入，避免 FileHandle 在不同线程出问题
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                handle.seekToEndOfFile()
                handle.write(data)
                try handle.close()
            } else {
                // 文件不存在，直接创建
                try data.write(to: url, options: .atomic)
            }
        } catch {
            logger.error("写入日志失败: \(error.localizedDescription)")
        }
    }

    private func osLog(_ message: String) {
        logger.info("\(message)")
    }

    private func console(_ line: String, isError: Bool = false) {
        if isError {
            fputs(line + "\n", stderr)
        } else {
            print(line)
        }
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
