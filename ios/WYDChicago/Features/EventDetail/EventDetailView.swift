import SwiftUI

// MARK: - EventDetailView (canon §3)

struct EventDetailView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm: EventDetailViewModel
    @State private var didLoad = false
    @State private var celebrate = 0
    @State private var toast: ToastData?

    init(eventId: String) {
        _vm = StateObject(wrappedValue: EventDetailViewModel(eventId: eventId, backend: MockBackend()))
    }

    var body: some View {
        ScrollView {
            if let event = vm.event {
                VStack(alignment: .leading, spacing: 18) {
                    cover(event).appear(delay: 0.00, yOffset: 20)
                    header(event).appear(delay: 0.06)
                    rsvpBar.appear(delay: 0.12)
                    whenWhere(event).appear(delay: 0.18)
                    if !event.description.isEmpty { about(event).appear(delay: 0.24) }
                    attendeesSection.appear(delay: 0.30)
                    commentsSection.appear(delay: 0.36)
                    safetyRow(event).appear(delay: 0.42)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            } else if vm.isLoading {
                ProgressView().tint(.wydBrand).padding(.top, 60)
            } else {
                EmptyStateView(title: "Couldn't load this one", subtitle: "Pull to try again.")
            }
        }
        .background(WYDBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await vm.toggleSave()
                        if vm.errorMessage == nil {
                            Haptics.tap()
                            toast = vm.isSaved ? .info("Saved to your list") : .info("Removed from saved")
                        }
                    }
                } label: {
                    Image(systemName: vm.isSaved ? "bookmark.fill" : "bookmark")
                        .foregroundColor(vm.isSaved ? .wydGold : .wydText)
                        .scaleEffect(vm.isSaved ? 1.1 : 1)
                        .animation(WYDMotion.bouncy, value: vm.isSaved)
                }
            }
        }
        .refreshable { await vm.load() }
        .task {
            guard !didLoad else { return }
            didLoad = true
            vm.rebind(appState.backend)
            await vm.load()
        }
        .sheet(isPresented: $vm.showReportSheet) {
            ReportSheet { reason, details in
                Task { await vm.submitReport(reason: reason, details: details) }
            }
            .presentationDetents([.medium])
        }
        .alert("Heads up", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .overlay { ConfettiView(trigger: celebrate).ignoresSafeArea() }
        .wydToast($toast)
    }

    // MARK: Sections

    private func cover(_ event: Event) -> some View {
        ZStack {
            LinearGradient.cityNight.opacity(0.85)
            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: WYDRadius.card, style: .continuous))
        .overlay(alignment: .topLeading) {
            if event.isFeatured {
                Text("✨ Featured")
                    .font(WYDFont.bodySemibold(12))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.wydGold))
                    .foregroundColor(.black)
                    .padding(12)
            }
        }
    }

    private func header(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(event.title)
                .font(WYDFont.displayBold(26))
                .foregroundColor(.wydText)
            HStack(spacing: 8) {
                Text(event.hostName)
                    .font(WYDFont.bodyMedium(14))
                    .foregroundColor(.wydBrand)
                Text("·").foregroundColor(.wydMuted)
                Text(event.priceLabel)
                    .font(WYDFont.bodySemibold(14))
                    .foregroundColor(event.isFree ? .wydSuccess : .wydText)
            }
            VotePill(upvotes: event.upvotes, downvotes: event.downvotes, myVote: vm.myVote) { dir in
                Haptics.tap()
                Task { await vm.vote(dir) }
            }
        }
    }

    private var rsvpBar: some View {
        HStack(spacing: 10) {
            PrimaryButton(
                title: vm.myRsvp == .going ? "You're going 🎉" : "Going",
                systemImage: vm.myRsvp == .going ? "checkmark" : "bolt.fill"
            ) {
                let wasGoing = vm.myRsvp == .going
                Task {
                    await vm.setRsvp(.going)
                    if vm.myRsvp == .going && !wasGoing {
                        celebrate += 1
                        Haptics.success()
                        toast = .success("You're going 🎉 — address unlocked")
                    } else if vm.errorMessage == nil {
                        Haptics.select()
                    }
                }
            }
            SecondaryButton(
                title: vm.myRsvp == .interested ? "Interested ★" : "Interested",
                systemImage: nil,
                tint: vm.myRsvp == .interested ? .wydGold : .wydText
            ) {
                Task {
                    await vm.setRsvp(.interested)
                    if vm.errorMessage == nil {
                        Haptics.select()
                        if vm.myRsvp == .interested { toast = .info("Marked interested ★") }
                    }
                }
            }
        }
    }

    private func whenWhere(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow(icon: "calendar", title: "When", value: fullWhen(event))
            infoRow(
                icon: "mappin.and.ellipse",
                title: "Where",
                value: vm.canSeeExactAddress
                    ? (event.exactAddress ?? event.approxArea)
                    : "\(event.approxArea) — exact address unlocks when you RSVP Going 🔒"
            )
            HStack(spacing: 8) {
                ChipView(label: "Ages \(event.ageMin)–\(event.ageMax)", emoji: "🪪")
                if let cap = event.capacity {
                    ChipView(label: "Cap \(cap)", emoji: "👥")
                }
            }
        }
        .padding(14)
        .wydCardBackground(.wydSurface)
    }

    private func about(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The vibe").font(WYDFont.displaySemibold(18)).foregroundColor(.wydText)
            Text(event.description)
                .font(WYDFont.body(15))
                .foregroundColor(.wydMuted)
        }
    }

    private var attendeesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Who's in").font(WYDFont.displaySemibold(18)).foregroundColor(.wydText)
                Spacer()
                if let ev = vm.event {
                    Text("\(ev.committedCount) going · \(ev.interestedCount) interested")
                        .font(WYDFont.bodyMedium(13))
                        .foregroundColor(.wydMuted)
                }
            }
            if vm.attendees.isEmpty {
                Text("Be the first to tap in 👀")
                    .font(WYDFont.body(14)).foregroundColor(.wydMuted)
            } else {
                AvatarStackView(users: vm.attendees, size: 34, maxShown: 8)
            }
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments").font(WYDFont.displaySemibold(18)).foregroundColor(.wydText)
            ForEach(vm.comments) { c in
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.authorName).font(WYDFont.bodySemibold(13)).foregroundColor(.wydBrand)
                    Text(c.text).font(WYDFont.body(15)).foregroundColor(.wydText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .wydCardBackground(.wydSurface2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .animation(WYDMotion.snappy, value: vm.comments.count)
            HStack(spacing: 8) {
                TextField("Add a comment…", text: $vm.commentDraft)
                    .font(WYDFont.body(15))
                    .foregroundColor(.wydText)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: WYDRadius.button).fill(Color.wydSurface2))
                    .overlay(RoundedRectangle(cornerRadius: WYDRadius.button).stroke(Color.wydBorder, lineWidth: 1))
                    .submitLabel(.send)
                    .onSubmit { Task { await vm.postComment() } }
                Button {
                    Haptics.tap()
                    Task { await vm.postComment() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .padding(11)
                        .background(Circle().fill(LinearGradient.cityNight))
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private func safetyRow(_ event: Event) -> some View {
        HStack {
            ShareLink(item: shareText(event)) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(WYDFont.bodyMedium(14))
                    .foregroundColor(.wydBrand)
            }
            Spacer()
            Button { vm.showReportSheet = true } label: {
                Label("Report", systemImage: "flag")
                    .font(WYDFont.bodyMedium(14))
                    .foregroundColor(.wydDanger)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    // MARK: Helpers

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundColor(.wydBrand).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(WYDFont.bodyMedium(12)).foregroundColor(.wydMuted)
                Text(value).font(WYDFont.body(15)).foregroundColor(.wydText)
            }
            Spacer()
        }
    }

    private func fullWhen(_ event: Event) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d · h:mm a"
        var s = f.string(from: event.startAt)
        if let end = event.endAt {
            let ef = DateFormatter(); ef.dateFormat = "h:mm a"
            s += " – \(ef.string(from: end))"
        }
        return s
    }

    private func shareText(_ event: Event) -> String {
        "\(event.title) — \(event.whenChip) in \(event.approxArea). WYD? 👀 (WYD Chicago)"
    }
}

// MARK: - Report sheet

struct ReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reason = "Inappropriate"
    @State private var details = ""
    let onSubmit: (String, String) -> Void

    private let reasons = ["Inappropriate", "Spam", "Fake event", "Unsafe", "Other"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("What's wrong?")
                        .font(WYDFont.displaySemibold(18)).foregroundColor(.wydText)
                    ForEach(reasons, id: \.self) { r in
                        Button { reason = r } label: {
                            HStack {
                                Text(r).font(WYDFont.body(16)).foregroundColor(.wydText)
                                Spacer()
                                if reason == r {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.wydBrand)
                                }
                            }
                            .padding(14)
                            .wydCardBackground(.wydSurface2)
                        }
                        .buttonStyle(.plain)
                    }
                    TextField("Anything else? (optional)", text: $details, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .font(WYDFont.body(15)).foregroundColor(.wydText)
                        .padding(12)
                        .wydCardBackground(.wydSurface2)
                    PrimaryButton(title: "Send report", systemImage: "flag.fill") {
                        onSubmit(reason, details); dismiss()
                    }
                }
                .padding(16)
            }
            .background(WYDBackground())
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.wydMuted)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Event detail") {
    NavigationStack { EventDetailView(eventId: "e1") }
        .environmentObject(AppState(backend: MockBackend()))
        .preferredColorScheme(.dark)
}
