import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class TaskManager {
    let modelContainer: ModelContainer?
    let modelContext: ModelContext?
    var changeToken = UUID()
    private var memoryTasks: [GripTask]?

    init(inMemory: Bool = false) {
        let schema = Schema([GripTask.self])

        if inMemory {
            let config = ModelConfiguration(
                "GripInMemory-\(UUID().uuidString)",
                schema: schema,
                isStoredInMemoryOnly: true
            )
            let container = try! ModelContainer(for: schema, configurations: [config])
            self.modelContainer = container
            self.modelContext = container.mainContext
            self.memoryTasks = []
            return
        }

        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let container = try! ModelContainer(for: schema, configurations: [config])
        self.modelContainer = container
        self.modelContext = container.mainContext
    }

    func createTask(_ task: GripTask) throws {
        if memoryTasks != nil {
            memoryTasks?.append(task)
            changeToken = UUID()
            return
        }

        guard let modelContext else { return }
        modelContext.insert(task)
        try modelContext.save()
        changeToken = UUID()
    }

    func fetchTasks(
        status: TaskStatus? = nil,
        date: Date? = nil
    ) throws -> [GripTask] {
        let calendar = Calendar.current

        if let memoryTasks {
            return memoryTasks
                .filter { task in
                    let statusMatches = status.map { task.status == $0 } ?? true
                    let dateMatches: Bool
                    if let date {
                        let start = calendar.startOfDay(for: date)
                        let end = calendar.date(byAdding: .day, value: 1, to: start)!
                        dateMatches = task.createdAt >= start && task.createdAt < end
                    } else {
                        dateMatches = true
                    }
                    return statusMatches && dateMatches
                }
                .sorted { $0.createdAt > $1.createdAt }
        }

        guard let modelContext else { return [] }
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
        if memoryTasks != nil {
            changeToken = UUID()
            return
        }

        guard let modelContext else { return }
        try modelContext.save()
        changeToken = UUID()
    }

    func deleteTask(_ task: GripTask) throws {
        if memoryTasks != nil {
            memoryTasks?.removeAll { $0.id == task.id }
            changeToken = UUID()
            return
        }

        guard let modelContext else { return }
        modelContext.delete(task)
        try modelContext.save()
        changeToken = UUID()
    }

    func completeTask(_ task: GripTask) throws {
        task.status = .completed
        task.completedAt = Date()
        task.updatedAt = Date()
        if memoryTasks != nil {
            changeToken = UUID()
            return
        }

        guard let modelContext else { return }
        try modelContext.save()
        changeToken = UUID()
    }

    func markPending(_ task: GripTask) throws {
        task.status = .pending
        task.completedAt = nil
        task.updatedAt = Date()
        if memoryTasks != nil {
            changeToken = UUID()
            return
        }

        guard let modelContext else { return }
        try modelContext.save()
        changeToken = UUID()
    }
}
