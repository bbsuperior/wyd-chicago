import Foundation

// MARK: - WYD Assistant — an in-app AI buddy for finding stuff to do
//
// Same swap pattern as Backend: the app talks to the `AssistantService` protocol.
// `ClaudeAssistant` calls the real Claude Messages API (with web search +
// long-term memory) when an API key is present; otherwise `MockAssistant` keeps
// the chat working offline with zero config. See AssistantConfig.makeAssistant().

// MARK: Roles + turns

enum ChatRole: String, Codable {
    case user
    case assistant
}

/// One message in the visible chat transcript.
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: ChatRole
    var text: String
    var createdAt = Date()
}

/// A turn sent to the model (history).
struct ChatTurn {
    let role: ChatRole
    let text: String
}

/// Live app context handed to the assistant so it can talk about real events.
struct AssistantContext {
    var userName: String?
    var eventsSummary: String?
}

enum AssistantError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case network(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "AI isn't set up yet. Running in demo mode."
        case .http(let code, let msg): return "AI error (\(code)): \(msg)"
        case .network(let m): return "Network hiccup: \(m)"
        case .empty: return "Got an empty reply. Try again?"
        }
    }
}

// MARK: - The contract

/// The whole chat UI talks to this — never a concrete type.
@MainActor
protocol AssistantService: AnyObject {
    /// True when wired to the real Claude API (vs. the offline mock).
    var usingLiveAI: Bool { get }

    /// Produce the assistant's reply as a list of short "text message" bubbles.
    func reply(history: [ChatTurn], context: AssistantContext) async throws -> [String]
}

// MARK: - Long-term memory (persists across launches, on-device)

/// Small JSON-backed store of facts the assistant chooses to remember about the
/// user. Injected into every request's system prompt, so the AI stays personal
/// across sessions. The model writes to it via `remember: <fact>` lines.
final class MemoryStore {

    struct Item: Codable, Identifiable, Equatable {
        var id = UUID()
        var text: String
        var savedAt = Date()
    }

    private(set) var items: [Item] = []
    private let url: URL
    private let maxItems = 40

    init(filename: String = "wyd_assistant_memory.json") {
        let dir = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        self.url = dir.appendingPathComponent(filename)
        load()
    }

    /// Save a new fact (deduped, trimmed, capped).
    func remember(_ raw: String) {
        let fact = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fact.count >= 3 else { return }
        guard !items.contains(where: { $0.text.caseInsensitiveCompare(fact) == .orderedSame }) else { return }
        items.append(Item(text: fact))
        if items.count > maxItems { items.removeFirst(items.count - maxItems) }
        save()
    }

    func forget(_ item: Item) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func forgetAll() {
        items.removeAll()
        save()
    }

    /// A bullet list for the system prompt, or empty string when nothing's stored.
    func promptBlock() -> String {
        guard !items.isEmpty else { return "" }
        return items.map { "- \($0.text)" }.joined(separator: "\n")
    }

    // MARK: persistence

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Item].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Shared text shaping (multi-message + no-dashes)

enum AssistantText {

    /// Strip dashes per the house style: no em/en dashes, no hyphen punctuation.
    static func deDash(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "—", with: ", ")   // em dash
        out = out.replacingOccurrences(of: "–", with: ", ")   // en dash
        out = out.replacingOccurrences(of: " - ", with: ", ") // spaced hyphen as punctuation
        // Leading "- " bullet markers → nothing.
        out = out.replacingOccurrences(of: "^\\s*[-•]\\s+", with: "",
                                       options: .regularExpression)
        // Collapse any accidental ", ," doubling from the swaps.
        out = out.replacingOccurrences(of: ", ,", with: ",")
        return out
    }

    /// Split a raw reply into separate chat bubbles on blank lines (how the
    /// model is told to format texts). Falls back to single-newline splits if
    /// the model sent one block, and caps the count so it stays texty.
    static func bubbles(from raw: String, max: Int = 5) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Normalize blank-line separators to a single sentinel, then split.
        let normalized = trimmed.replacingOccurrences(
            of: "\\n[ \\t]*\\n+", with: "\u{1}", options: .regularExpression
        )
        var parts = normalized
            .components(separatedBy: "\u{1}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if parts.count == 1, trimmed.contains("\n") {
            parts = trimmed
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if parts.isEmpty { parts = [trimmed] }
        return Array(parts.prefix(max))
    }
}

// MARK: - Config: pick the real AI when a key exists, else the mock

enum AssistantConfig {

    /// Default model. Override at build time via the ANTHROPIC_MODEL Info.plist
    /// value (wired to a build setting in project.yml) without touching code.
    static let defaultModel = "claude-opus-4-8"

    /// API key resolution order: env var → Info.plist → Secrets.plist (git-ignored).
    static var apiKey: String? {
        if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty {
            return env
        }
        if let k = Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String,
           !k.isEmpty, !k.hasPrefix("$(") {
            return k
        }
        if let u = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let d = NSDictionary(contentsOf: u),
           let k = d["ANTHROPIC_API_KEY"] as? String, !k.isEmpty {
            return k
        }
        return nil
    }

    static var model: String {
        if let m = Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_MODEL") as? String,
           !m.isEmpty, !m.hasPrefix("$(") {
            return m
        }
        return defaultModel
    }

    @MainActor
    static func makeAssistant(memory: MemoryStore) -> AssistantService {
        if let key = apiKey {
            return ClaudeAssistant(apiKey: key, model: model, memory: memory)
        }
        return MockAssistant(memory: memory)
    }
}
