import Foundation
import SwiftData

enum TaskStatus: String, Codable, CaseIterable {
    case pending, completed, cancelled
}

enum TaskPriority: String, Codable, CaseIterable {
    case none, low, medium, high
}

enum TaskSourceType: String, Codable {
    case screenshot, clipboard, manual
}

@Model
final class GripTask: Identifiable {
    var id: UUID
    var title: String
    var detail: String?
    var status: TaskStatus
    var priority: TaskPriority
    var sourceType: TaskSourceType
    @Attribute(.externalStorage) var sourceContent: Data?
    var sourceText: String?
    var category: String?
    var dueDate: Date?
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var remindersEventId: String?
    var isSynced: Bool

    init(
        title: String,
        detail: String? = nil,
        status: TaskStatus = .pending,
        priority: TaskPriority = .none,
        sourceType: TaskSourceType = .manual,
        sourceContent: Data? = nil,
        sourceText: String? = nil,
        category: String? = nil,
        dueDate: Date? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.detail = detail
        self.status = status
        self.priority = priority
        self.sourceType = sourceType
        self.sourceContent = sourceContent
        self.sourceText = sourceText
        self.category = category
        self.dueDate = dueDate
        self.completedAt = nil
        self.createdAt = Date()
        self.updatedAt = Date()
        self.remindersEventId = nil
        self.isSynced = false
    }
}
