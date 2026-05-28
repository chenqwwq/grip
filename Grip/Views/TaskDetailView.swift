import SwiftUI

struct TaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TaskManager.self) private var taskManager

    @Bindable var task: GripTask
    @State private var title: String = ""
    @State private var detail: String = ""
    @State private var category: String = ""
    @State private var priority: TaskPriority = .none
    @State private var dueDate: Date? = nil

    let onSave: ((GripTask, String, String?, String?, TaskPriority, Date?) throws -> Void)?
    let onDelete: ((GripTask) throws -> Void)?

    init(
        task: GripTask,
        onSave: ((GripTask, String, String?, String?, TaskPriority, Date?) throws -> Void)? = nil,
        onDelete: ((GripTask) throws -> Void)? = nil
    ) {
        self.task = task
        self.onSave = onSave
        self.onDelete = onDelete
        self._title = State(initialValue: task.title)
        self._detail = State(initialValue: task.detail ?? "")
        self._category = State(initialValue: task.category ?? "")
        self._priority = State(initialValue: task.priority)
        self._dueDate = State(initialValue: task.dueDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    fieldSection("标题") {
                        TextField("任务标题", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }

                    fieldSection("详细描述") {
                        TextEditor(text: $detail)
                            .font(.body)
                            .padding(6)
                            .frame(minHeight: 76)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }

                    HStack(spacing: 16) {
                        VStack(alignment: .leading) {
                            fieldLabel("分类")
                            TextField("分类", text: $category)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading) {
                            fieldLabel("优先级")
                            Picker("", selection: $priority) {
                                ForEach(TaskPriority.allCases, id: \.self) { p in
                                    Text(p.rawValue).tag(p)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    VStack(alignment: .leading) {
                        fieldLabel("截止日期")
                        HStack {
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { dueDate ?? Date() },
                                    set: { dueDate = $0 }
                                ),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .labelsHidden()
                            Button("清除") {
                                dueDate = nil
                            }
                            .disabled(dueDate == nil)
                        }
                    }

                    if task.sourceType == .screenshot, let imageData = task.sourceContent {
                        VStack(alignment: .leading) {
                            fieldLabel("原始截图")
                            if let nsImage = NSImage(data: imageData) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }

                    if let sourceText = task.sourceText {
                        VStack(alignment: .leading) {
                            fieldLabel("原始文本")
                            Text(sourceText)
                                .font(.caption)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    HStack {
                        Text("创建：\(task.createdAt, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if task.isSynced {
                            Text("已同步 Reminders")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 420, height: 520)
    }

    private var header: some View {
        HStack {
            Text("任务详情")
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("取消") { dismiss() }
            Button("删除", role: .destructive) {
                if let onDelete {
                    try? onDelete(task)
                } else {
                    try? taskManager.deleteTask(task)
                }
                dismiss()
            }
            Button("保存") {
                if let onSave {
                    try? onSave(
                        task,
                        title,
                        detail.isEmpty ? nil : detail,
                        category.isEmpty ? nil : category,
                        priority,
                        dueDate
                    )
                } else {
                    task.title = title
                    task.detail = detail.isEmpty ? nil : detail
                    task.category = category.isEmpty ? nil : category
                    task.priority = priority
                    task.dueDate = dueDate
                    try? taskManager.updateTask(task)
                }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    private func fieldSection(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label)
            content()
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}
