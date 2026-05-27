import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class TaskManager {
    let modelContainer: ModelContainer
    let modelContext: ModelContext
    var changeToken = UUID()

    init(inMemory: Bool = false) {
        let schema = Schema([GripTask.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        self.modelContainer = try! ModelContainer(for: schema, configurations: [config])
        self.modelContext = modelContainer.mainContext
    }

    func createTask(_ task: GripTask) throws {
        modelContext.insert(task)
        try modelContext.save()
        changeToken = UUID()
    }

    func fetchTasks(
        status: TaskStatus? = nil,
        date: Date? = nil
    ) throws -> [GripTask] {
        let calendar = Calendar.current

        if let date = date {
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!

            if let status = status {
                let descriptor = FetchDescriptor<GripTask>(
                    predicate: #Predicate {
                        $0.status == status && $0.createdAt >= start && $0.createdAt < end
                    },
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )
                return try modelContext.fetch(descriptor)
            } else {
                let descriptor = FetchDescriptor<GripTask>(
                    predicate: #Predicate {
                        $0.createdAt >= start && $0.createdAt < end
                    },
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )
                return try modelContext.fetch(descriptor)
            }
        } else if let status = status {
            let descriptor = FetchDescriptor<GripTask>(
                predicate: #Predicate {
                    $0.status == status
                },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor)
        } else {
            let descriptor = FetchDescriptor<GripTask>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor)
        }
    }

    func updateTask(_ task: GripTask) throws {
        task.updatedAt = Date()
        try modelContext.save()
        changeToken = UUID()
    }

    func deleteTask(_ task: GripTask) throws {
        modelContext.delete(task)
        try modelContext.save()
        changeToken = UUID()
    }

    func completeTask(_ task: GripTask) throws {
        task.status = .completed
        task.completedAt = Date()
        task.updatedAt = Date()
        try modelContext.save()
        changeToken = UUID()
    }

    func markPending(_ task: GripTask) throws {
        task.status = .pending
        task.completedAt = nil
        task.updatedAt = Date()
        try modelContext.save()
        changeToken = UUID()
    }
}
