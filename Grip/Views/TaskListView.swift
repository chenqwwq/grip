import SwiftUI

struct TaskListView: View {
    @Environment(TaskManager.self) private var taskManager
    let filter: TaskFilter
    let date: Date
    let coordinator: AppCoordinator?
    let theme: GripTheme
    @State private var tasks: [GripTask] = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(tasks) { task in
                    TaskRowView(task: task, theme: theme, onToggleCompletion: {
                        coordinator?.toggleCompletion(task)
                    }) {
                        coordinator?.presentTask(task)
                    }
                }

                if tasks.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .background(theme.windowBackground)
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

    private var emptyState: some View {
        VStack(spacing: 0) {
            Text("这一天还没有待办")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }
}
