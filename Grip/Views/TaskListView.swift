import SwiftUI

struct TaskListView: View {
    @Environment(TaskManager.self) private var taskManager
    let filter: TaskFilter
    let date: Date
    let coordinator: AppCoordinator?
    @State private var tasks: [GripTask] = []

    var body: some View {
        List {
            ForEach(tasks) { task in
                TaskRowView(task: task, onToggleCompletion: {
                    coordinator?.toggleCompletion(task)
                }) {
                    coordinator?.presentTask(task)
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .id(filter)
        .onAppear {
            loadTasks()
        }
        .onChange(of: filter) {
            loadTasks()
        }
        .onChange(of: date) {
            loadTasks()
        }
        .onChange(of: taskManager.changeToken) {
            loadTasks()
        }
    }

    private func loadTasks() {
        do {
            let todayTasks = try taskManager.fetchTasks(date: date)
            tasks = switch filter {
            case .all:
                todayTasks
            case .pending:
                todayTasks.filter { $0.status == .pending }
            case .completed:
                todayTasks.filter { $0.status == .completed }
            }
        } catch {
            GripLogger.shared.error("加载任务列表失败: \(error.localizedDescription)")
            tasks = []
        }
    }
}
