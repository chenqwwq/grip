import Foundation

struct TaskDraft: Identifiable {
    let id = UUID()
    var title: String
    var detail: String?
    var category: String?
    var priority: TaskPriority
    var dueDate: Date?
    var sourceType: TaskSourceType
    var sourceContent: Data?
    var sourceText: String?

    init(
        title: String,
        detail: String? = nil,
        category: String? = nil,
        priority: TaskPriority = .none,
        dueDate: Date? = nil,
        sourceType: TaskSourceType = .manual,
        sourceContent: Data? = nil,
        sourceText: String? = nil
    ) {
        self.title = title
        self.detail = detail
        self.category = category
        self.priority = priority
        self.dueDate = dueDate
        self.sourceType = sourceType
        self.sourceContent = sourceContent
        self.sourceText = sourceText
    }

    func makeTask() -> GripTask {
        GripTask(
            title: title,
            detail: detail,
            priority: priority,
            sourceType: sourceType,
            sourceContent: sourceContent,
            sourceText: sourceText,
            category: category,
            dueDate: dueDate
        )
    }
}
