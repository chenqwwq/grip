import SwiftUI

struct TaskDraftView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var detail: String
    @State private var category: String
    @State private var priority: TaskPriority
    @State private var dueDate: Date?

    let draft: TaskDraft
    let onCreate: (TaskDraft) -> Void

    init(draft: TaskDraft, onCreate: @escaping (TaskDraft) -> Void) {
        self.draft = draft
        self.onCreate = onCreate
        self._title = State(initialValue: draft.title)
        self._detail = State(initialValue: draft.detail ?? "")
        self._category = State(initialValue: draft.category ?? "")
        self._priority = State(initialValue: draft.priority)
        self._dueDate = State(initialValue: draft.dueDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("确认新任务")
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
                            .frame(minHeight: 86)
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

                    sourcePreview
                }
                .padding(16)
            }

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("创建") {
                    onCreate(updatedDraft())
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 420, height: 520)
    }

    @ViewBuilder
    private var sourcePreview: some View {
        if draft.sourceType == .screenshot, let imageData = draft.sourceContent {
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

        if let sourceText = draft.sourceText {
            VStack(alignment: .leading) {
                fieldLabel("原始文本")
                Text(sourceText)
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func updatedDraft() -> TaskDraft {
        TaskDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            detail: detail.isEmpty ? nil : detail,
            category: category.isEmpty ? nil : category,
            priority: priority,
            dueDate: dueDate,
            sourceType: draft.sourceType,
            sourceContent: draft.sourceContent,
            sourceText: draft.sourceText
        )
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
