import Foundation

enum TaskSheet: Identifiable {
    case detail(GripTask)
    case draft(TaskDraft)

    var id: String {
        switch self {
        case .detail(let task):
            "detail-\(task.id.uuidString)"
        case .draft(let draft):
            "draft-\(draft.id.uuidString)"
        }
    }
}
