import Foundation

// MARK: - MockAssistant — offline, zero-config chat
//
// Keeps the assistant feeling alive with no API key: human-like, multi-message,
// lowercase, no dashes. It reads the live event context and remembers the user's
// name the same way the real model does, so memory still "works" in demo mode.

@MainActor
final class MockAssistant: AssistantService {

    let usingLiveAI = false
    private let memory: MemoryStore

    init(memory: MemoryStore) {
        self.memory = memory
    }

    func reply(history: [ChatTurn], context: AssistantContext) async throws -> [String] {
        // tiny pause so the typing indicator reads naturally
        try? await Task.sleep(nanoseconds: 250_000_000)

        let last = history.last(where: { $0.role == .user })?.text ?? ""
        let lower = last.lowercased()

        learnName(from: last)
        let name = knownName() ?? context.userName

        var out = compose(lower: lower, name: name, context: context)
        out = out.map { AssistantText.deDash($0) }
        return out
    }

    // MARK: Reply composition

    private func compose(lower: String, name: String?, context: AssistantContext) -> [String] {
        let hey = name.map { "heyy \($0.split(separator: " ").first.map(String.init)?.lowercased() ?? "") 👋" } ?? "heyy 👋"

        if containsAny(lower, ["hi", "hey", "hello", "yo", "wyd", "sup"]) && lower.count < 14 {
            return [hey, "im your wyd buddy", "wanna find something to get into tonight?"]
        }

        if containsAny(lower, ["bored", "nothing", "what do", "what should", "anything", "plans"]) {
            return boredReply(context)
        }

        if containsAny(lower, ["weekend", "saturday", "friday", "sunday"]) {
            return ["the weekend is looking kinda alive 🎉", suggestionLine(context, fallback: "tap the weekend filter on the feed and i bet something pops")]
        }

        if containsAny(lower, ["tonight", "today", "now"]) {
            return ["lemme see whats good tonight 🌙", suggestionLine(context, fallback: "check the tonight filter up top, a few things are happening")]
        }

        if containsAny(lower, ["thank", "thanks", "ty", "appreciate"]) {
            return ["anytime 🫶", "go have fun and be safe out there"]
        }

        if containsAny(lower, ["who are you", "what are you", "your name"]) {
            return ["im the wyd assistant", "basically your plug for stuff to do around chicago 🌃"]
        }

        // Default: warm, helpful, still texty.
        return [
            "ooh okay 👀",
            suggestionLine(context, fallback: "tell me your vibe (music, hoops, chill kickback) and ill point you somewhere"),
            "what are you feeling?"
        ]
    }

    private func boredReply(_ context: AssistantContext) -> [String] {
        if let s = firstEventLine(context) {
            return ["say less 😤", "\(s) is coming up and looks fun", "wanna tap in?"]
        }
        return ["say less 😤", "open the feed and sort by hype, the top one is usually a vibe", "or tell me what youre into"]
    }

    private func suggestionLine(_ context: AssistantContext, fallback: String) -> String {
        firstEventLine(context).map { "theres \($0), could be your move" } ?? fallback
    }

    private func firstEventLine(_ context: AssistantContext) -> String? {
        guard let summary = context.eventsSummary else { return nil }
        let first = summary.components(separatedBy: "\n").first?
            .trimmingCharacters(in: .whitespaces)
        guard let f = first, !f.isEmpty else { return nil }
        // strip a leading bullet if present
        return f.replacingOccurrences(of: "^\\s*[-•]\\s*", with: "", options: .regularExpression)
    }

    // MARK: Memory (name detection)

    private func learnName(from text: String) {
        let patterns = ["my name is ", "im ", "i'm ", "this is ", "call me "]
        let lower = text.lowercased()
        for p in patterns where lower.contains(p) {
            guard let r = lower.range(of: p) else { continue }
            let after = text[r.upperBound...]
            let word = after.prefix { $0.isLetter }
            let candidate = String(word)
            if candidate.count >= 2, candidate.count <= 20,
               !["bored", "here", "good", "back", "down", "free", "trying", "tryna"].contains(candidate.lowercased()) {
                let nice = candidate.prefix(1).uppercased() + candidate.dropFirst().lowercased()
                if knownName() == nil { memory.remember("their name is \(nice)") }
                return
            }
        }
    }

    private func knownName() -> String? {
        for item in memory.items {
            if let r = item.text.range(of: "name is ", options: .caseInsensitive) {
                return String(item.text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func containsAny(_ s: String, _ needles: [String]) -> Bool {
        needles.contains { s.contains($0) }
    }
}
