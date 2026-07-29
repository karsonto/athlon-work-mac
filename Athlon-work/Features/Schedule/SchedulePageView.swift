import SwiftUI

struct SchedulePageView: View {
    @Environment(MainShellStore.self) private var store
    @State private var scheduleStore = ScheduleStore()
    @State private var selectedId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HSplitView {
                taskList
                    .frame(minWidth: 240, idealWidth: 280)
                editor
                    .frame(minWidth: 360)
            }
        }
        .background(store.themeManager.chrome.appBackground.color)
        .onAppear {
            scheduleStore = ScheduleStore(
                storage: FileStorageService(),
                runtimeProvider: { store.agentRuntime }
            )
            scheduleStore.reload()
            scheduleStore.start()
            selectedId = scheduleStore.settings.tasks.first?.id
        }
        .onDisappear {
            scheduleStore.stop()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(L10n.t("schedule.title", language: store.settings.ui.language))
                .font(.system(size: 18, weight: .semibold))
            Spacer()
            Toggle(
                L10n.t("schedule.enabled", language: store.settings.ui.language),
                isOn: Binding(
                    get: { scheduleStore.settings.enabled },
                    set: { scheduleStore.settings.enabled = $0; scheduleStore.persist() }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            Toggle(
                L10n.t("schedule.keepAwake", language: store.settings.ui.language),
                isOn: Binding(
                    get: { scheduleStore.settings.keepAwake },
                    set: { scheduleStore.settings.keepAwake = $0; scheduleStore.persist() }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            Button {
                scheduleStore.addTask()
                selectedId = scheduleStore.settings.tasks.first?.id
            } label: {
                Label(L10n.t("schedule.add", language: store.settings.ui.language), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .frame(height: AppLayoutMetrics.panelHeaderHeight)
    }

    private var taskList: some View {
        Group {
            if scheduleStore.settings.tasks.isEmpty {
                Text(L10n.t("schedule.empty", language: store.settings.ui.language))
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List(selection: $selectedId) {
                    ForEach(scheduleStore.settings.tasks) { task in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title.isEmpty ? "(untitled)" : task.title)
                                .font(.system(size: 13, weight: .medium))
                            Text("\(task.kind) · \(task.lastStatus.isEmpty ? "idle" : task.lastStatus)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .tag(task.id as String?)
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            let id = scheduleStore.settings.tasks[idx].id
                            scheduleStore.deleteTask(id: id)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(store.themeManager.chrome.panel.color)
    }

    @ViewBuilder
    private var editor: some View {
        if let id = selectedId,
           let idx = scheduleStore.settings.tasks.firstIndex(where: { $0.id == id }) {
            let binding = Binding(
                get: { scheduleStore.settings.tasks[idx] },
                set: { scheduleStore.updateTask($0) }
            )
            Form {
                TextField("Title", text: binding.title)
                Toggle("Enabled", isOn: binding.enabled)
                TextField("Prompt", text: binding.prompt, axis: .vertical)
                    .lineLimit(4...10)
                TextField("Workspace", text: binding.workspaceRoot)
                Picker("Kind", selection: binding.kind) {
                    Text("daily").tag("daily")
                    Text("interval").tag("interval")
                    Text("once").tag("once")
                }
                if binding.wrappedValue.kind == "interval" {
                    Stepper("Every \(binding.wrappedValue.everyMinutes) min", value: binding.everyMinutes, in: 1...1440)
                } else {
                    TextField("Time of day (HH:mm)", text: binding.timeOfDay)
                }
                LabeledContent("Next run", value: binding.wrappedValue.nextRunAt.isEmpty ? "—" : binding.wrappedValue.nextRunAt)
                LabeledContent("Last status", value: binding.wrappedValue.lastStatus.isEmpty ? "—" : binding.wrappedValue.lastStatus)
                Button(L10n.t("schedule.runNow", language: store.settings.ui.language)) {
                    scheduleStore.runNow(binding.wrappedValue)
                }
            }
            .formStyle(.grouped)
            .padding(8)
        } else {
            Text(L10n.t("schedule.empty", language: store.settings.ui.language))
                .foregroundStyle(.secondary)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

#Preview {
    SchedulePageView()
        .environment(MainShellStore())
}
