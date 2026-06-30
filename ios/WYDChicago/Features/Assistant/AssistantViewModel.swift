import SwiftUI

// MARK: - AssistantViewModel — drives the AI chat

@MainActor
final class AssistantViewModel: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var input = ""
    @Published var isTyping = false
    @Published var errorMessage: String?

    let memory: MemoryStore
    private let service: AssistantService
    private weak var backend: Backend?

    var usingLiveAI: Bool { service.usingLiveAI }

    init(memory: MemoryStore = MemoryStore(),
         service: AssistantService? = nil) {
        self.memory = memory
        self.service = service ?? AssistantConfig.makeAssistant(memory: memory)
    }

    /// Hook up the live backend so the AI can talk about real events.
    func bind(_ backend: Backend) {
        self.backend = backend
    }

    /// Opening bubbles shown before the user says anything.
    func greet() {
        guard messages.isEmpty else { return }
        let name = backend?.currentUser?.displayName.split(separator: " ").first.map(String.init)
        let hi = name.map { "heyy \($0.lowercased()) 👋" } ?? "heyy 👋"
        messages = [
            ChatMessage(role: .assistant, text: hi),
            ChatMessage(role: .assistant, text: "im your wyd buddy, ask me whats good tonight or what to do this weekend ✨")
        ]
    }

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isTyping else { return }

        Haptics.tap()
        withAnimation(WYDMotion.snappy) {
            messages.append(ChatMessage(role: .user, text: text))
        }
        input = ""
        errorMessage = nil

        let history = messages.map { ChatTurn(role: $0.role, text: $0.text) }
        let context = await buildContext()

        withAnimation(WYDMotion.fade) { isTyping = true }

        do {
            let bubbles = try await service.reply(history: history, context: context)
            await reveal(bubbles)
        } catch {
            withAnimation(WYDMotion.fade) { isTyping = false }
            Haptics.warning()
            errorMessage = (error as? AssistantError)?.errorDescription ?? error.localizedDescription
            withAnimation(WYDMotion.bouncy) {
                messages.append(ChatMessage(role: .assistant,
                    text: "my bad, i glitched for a sec 😵‍💫 try me again?"))
            }
        }
    }

    func clearMemory() {
        memory.forgetAll()
        Haptics.bump()
    }

    // MARK: Reveal bubbles one at a time, like real texting

    private func reveal(_ bubbles: [String]) async {
        guard !bubbles.isEmpty else {
            withAnimation(WYDMotion.fade) { isTyping = false }
            return
        }
        for (i, bubble) in bubbles.enumerated() {
            if i > 0 { withAnimation(WYDMotion.fade) { isTyping = true } }
            // "typing" delay scales with message length, clamped.
            let delay = min(1.1, 0.35 + Double(bubble.count) * 0.012)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            withAnimation(WYDMotion.fade) { isTyping = false }
            withAnimation(WYDMotion.bouncy) {
                messages.append(ChatMessage(role: .assistant, text: bubble))
            }
            Haptics.tap()
        }
    }

    private func buildContext() async -> AssistantContext {
        let name = backend?.currentUser?.displayName
        var summary: String?
        if let backend {
            let events = (try? await backend.listEvents(FeedQuery(sort: .soonest))) ?? []
            if !events.isEmpty {
                summary = events.prefix(5).map { ev in
                    "\(ev.title) (\(ev.whenChip), \(ev.approxArea))"
                }.joined(separator: "\n")
            }
        }
        return AssistantContext(userName: name, eventsSummary: summary)
    }
}
