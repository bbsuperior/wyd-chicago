import SwiftUI

// MARK: - FeedView — the core screen (canon §3). Also serves the Search tab.

struct FeedView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm: FeedViewModel
    @State private var didLoad = false
    private let startInSearch: Bool

    init(startInSearch: Bool = false) {
        self.startInSearch = startInSearch
        // VM is created with a placeholder; real backend is injected on appear.
        _vm = StateObject(wrappedValue: FeedViewModel(backend: MockBackend()))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if startInSearch {
                    searchField
                }
                filterChips
                sortRow

                if vm.isLoading && vm.events.isEmpty {
                    ProgressView().tint(.wydBrand).padding(.top, 40)
                } else if vm.events.isEmpty {
                    EmptyStateView(
                        emoji: "🌙",
                        title: "Nothing here yet",
                        subtitle: "Try a different filter, or check back later — the city's always cooking something up."
                    )
                } else {
                    ForEach(vm.events) { event in
                        NavigationLink(value: event.id) {
                            EventCardView(
                                event: event,
                                friendsGoing: vm.friendsGoingByEvent[event.id] ?? []
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(WYDBackground())
        .navigationTitle(startInSearch ? "Search" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !startInSearch { WYDLogo(size: 22, showCity: false) }
            }
        }
        .navigationDestination(for: String.self) { eventId in
            EventDetailView(eventId: eventId)
        }
        .refreshable { await vm.load() }
        .task {
            guard !didLoad else { return }
            didLoad = true
            vm.rebind(appState.backend)
            if startInSearch { vm.sort = .soonest }
            await vm.load()
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.wydMuted)
            TextField("Search what's good 👀", text: $vm.search)
                .font(WYDFont.body(16))
                .foregroundColor(.wydText)
                .submitLabel(.search)
                .onSubmit { vm.runSearch() }
            if !vm.search.isEmpty {
                Button {
                    vm.search = ""; vm.runSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.wydMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: WYDRadius.button, style: .continuous)
                .fill(Color.wydSurface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: WYDRadius.button, style: .continuous)
                .stroke(Color.wydBorder, lineWidth: 1)
        )
    }

    // MARK: Filters

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ChipView(label: "Tonight", emoji: "🌙",
                         isSelected: vm.selectedWhen == "tonight") {
                    vm.selectWhen("tonight")
                }
                ChipView(label: "Weekend", emoji: "🎉",
                         isSelected: vm.selectedWhen == "weekend") {
                    vm.selectWhen("weekend")
                }
                Divider().frame(height: 22).overlay(Color.wydBorder)
                ForEach(vm.eventTypeTags) { tag in
                    ChipView(label: tag.label, emoji: tag.emoji,
                             isSelected: vm.selectedType == tag.id,
                             accent: Color(hex: tag.color)) {
                        vm.selectType(tag.id)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Sort

    private var sortRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FeedSort.allCases) { s in
                    ChipView(label: s.label, isSelected: vm.sort == s, accent: .wydAccent) {
                        vm.setSort(s)
                    }
                }
                ChipView(label: "Friends going", emoji: "👥",
                         isSelected: vm.friendsOnly, accent: .wydSuccess) {
                    vm.friendsOnly.toggle()
                    vm.runSearch()
                }
            }
            .padding(.vertical, 2)
        }
    }
}

#Preview("Feed") {
    NavigationStack { FeedView() }
        .environmentObject(AppState(backend: MockBackend()))
        .preferredColorScheme(.dark)
}
