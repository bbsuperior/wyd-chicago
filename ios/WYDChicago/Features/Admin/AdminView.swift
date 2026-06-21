import SwiftUI

// MARK: - AdminView — master dashboard (admin) / create form (host). canon §3.7

struct AdminView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm: AdminViewModel
    @State private var didLoad = false
    private let startOnCreate: Bool

    init(startOnCreate: Bool = false) {
        self.startOnCreate = startOnCreate
        _vm = StateObject(wrappedValue: AdminViewModel(backend: MockBackend()))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if vm.isAdmin {
                    tabPicker
                }
                switch vm.tab {
                case .create: createForm
                case .manage: manageList
                case .reports: reportsList
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(WYDBackground())
        .navigationTitle(vm.isAdmin ? "Master login 👑" : "New event")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: String.self) { id in EventDetailView(eventId: id) }
        .task {
            guard !didLoad else { return }
            didLoad = true
            vm.rebind(appState.backend)
            if startOnCreate { vm.tab = .create }
            await vm.load()
        }
        .overlay(alignment: .bottom) { toastView }
        .alert("Heads up", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
    }

    // MARK: Tabs

    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(AdminViewModel.Tab.allCases) { t in
                ChipView(label: t.rawValue, isSelected: vm.tab == t, accent: .wydBrand) {
                    vm.tab = t
                }
            }
        }
    }

    // MARK: Create form

    private var createForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            formField("Title") {
                TextField("e.g. Rooftop Kickback 🌆", text: $vm.draft.title)
                    .styledInput()
            }
            formField("What kind of event?") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.eventTypeTags) { tag in
                            ChipView(label: tag.label, emoji: tag.emoji,
                                     isSelected: vm.draft.eventType == tag.id,
                                     accent: Color(hex: tag.color)) {
                                vm.draft.eventType = tag.id
                            }
                        }
                    }
                }
            }
            formField("The vibe (description)") {
                TextField("Tell people what's up…", text: $vm.draft.description, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .styledInput()
            }
            formField("When") {
                DatePicker("", selection: $vm.draft.startAt)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(.wydBrand)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            formField("Approx area (shown before RSVP)") {
                TextField("e.g. Wicker Park", text: $vm.draft.approxArea).styledInput()
            }
            formField("Neighborhood") {
                TextField("e.g. Wicker Park", text: Binding(
                    get: { vm.draft.neighborhood ?? "" },
                    set: { vm.draft.neighborhood = $0.isEmpty ? nil : $0 }
                )).styledInput()
            }
            formField("Exact address (hidden until RSVP 🔒)") {
                TextField("Revealed only to people going", text: Binding(
                    get: { vm.draft.exactAddress ?? "" },
                    set: { vm.draft.exactAddress = $0.isEmpty ? nil : $0 }
                )).styledInput()
            }
            HStack(spacing: 12) {
                formField("Price ($)") {
                    TextField("0", text: $vm.priceDollars)
                        .keyboardType(.decimalPad).styledInput()
                }
                formField("Capacity") {
                    TextField("none", text: $vm.capacityText)
                        .keyboardType(.numberPad).styledInput()
                }
            }
            formField("Recommended for") {
                FlowChips(tags: vm.interestTags, selected: Set(vm.draft.tags)) { id in
                    vm.toggleDraftTag(id)
                }
            }

            PrimaryButton(
                title: vm.isAdmin ? "Publish event" : "Submit for review",
                systemImage: "paperplane.fill",
                isLoading: vm.isSaving,
                isEnabled: vm.canSubmitDraft
            ) {
                Task { await vm.submitDraft() }
            }

            if !vm.isAdmin {
                Text("Hosts' events go to an admin for review before they go live.")
                    .font(WYDFont.bodyMedium(12)).foregroundColor(.wydMuted)
            }
        }
    }

    // MARK: Manage list (admin)

    private var manageList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if vm.allEvents.isEmpty {
                EmptyStateView(title: "No events yet", subtitle: "Create one from the Create tab.")
            }
            ForEach(vm.allEvents) { ev in
                VStack(alignment: .leading, spacing: 10) {
                    NavigationLink(value: ev.id) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ev.title).font(WYDFont.bodySemibold(15)).foregroundColor(.wydText)
                                Text("\(ev.status.rawValue.capitalized) · \(ev.committedCount) going · 🔥 \(ev.voteScore)")
                                    .font(WYDFont.bodyMedium(12)).foregroundColor(.wydMuted)
                            }
                            Spacer()
                            statusDot(ev.status)
                        }
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 8) {
                        smallAction("Publish", .wydSuccess) { Task { await vm.setStatus(ev, .published) } }
                        smallAction("Draft", .wydMuted) { Task { await vm.setStatus(ev, .draft) } }
                        smallAction("Cancel", .wydDanger) { Task { await vm.setStatus(ev, .cancelled) } }
                        if ev.isFeatured {
                            Text("✨").font(.system(size: 14))
                        }
                    }
                }
                .padding(12)
                .wydCardBackground(.wydSurface)
            }
        }
    }

    // MARK: Reports list (admin)

    private var reportsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if vm.reports.isEmpty {
                EmptyStateView(emoji: "🛡️", title: "Queue's clear", subtitle: "No open reports. Nice.")
            }
            ForEach(vm.reports) { r in
                HStack(spacing: 12) {
                    Image(systemName: "flag.fill").foregroundColor(.wydDanger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(r.targetType.rawValue.capitalized) · \(r.reason)")
                            .font(WYDFont.bodySemibold(14)).foregroundColor(.wydText)
                        if !r.details.isEmpty {
                            Text(r.details).font(WYDFont.bodyMedium(12)).foregroundColor(.wydMuted)
                        }
                        Text("Status: \(r.status.rawValue)")
                            .font(WYDFont.bodyMedium(12)).foregroundColor(.wydMuted)
                    }
                    Spacer()
                }
                .padding(12)
                .wydCardBackground(.wydSurface)
            }
        }
    }

    // MARK: Bits

    private func formField<Content: View>(_ label: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(WYDFont.bodyMedium(13)).foregroundColor(.wydMuted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func smallAction(_ title: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(WYDFont.bodySemibold(13)).foregroundColor(color)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Color.wydSurface2))
                .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func statusDot(_ status: EventStatus) -> some View {
        let color: Color = {
            switch status {
            case .published: return .wydSuccess
            case .draft: return .wydGold
            case .cancelled: return .wydDanger
            }
        }()
        return Circle().fill(color).frame(width: 10, height: 10)
    }

    @ViewBuilder private var toastView: some View {
        if let toast = vm.toast {
            Text(toast)
                .font(WYDFont.bodyMedium(14)).foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Color.wydSurface2))
                .overlay(Capsule().stroke(Color.wydBorder, lineWidth: 1))
                .padding(.bottom, 20)
                .task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation { vm.toast = nil }
                }
        }
    }
}

// MARK: - Styled input helper

private extension View {
    func styledInput() -> some View {
        self
            .font(WYDFont.body(16))
            .foregroundColor(.wydText)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: WYDRadius.button).fill(Color.wydSurface2))
            .overlay(RoundedRectangle(cornerRadius: WYDRadius.button).stroke(Color.wydBorder, lineWidth: 1))
    }
}

#Preview("Admin — master") {
    NavigationStack { AdminView() }
        .environmentObject(AppState(backend: MockBackend.signedInAsAdmin()))
        .preferredColorScheme(.dark)
}

#Preview("Host — create only") {
    // A host user gets just the create form (no admin tabs).
    NavigationStack { AdminView(startOnCreate: true) }
        .environmentObject(AppState(backend: MockBackend.signedInAsHost()))
        .preferredColorScheme(.dark)
}
