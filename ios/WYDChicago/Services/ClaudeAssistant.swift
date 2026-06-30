import Foundation

// MARK: - ClaudeAssistant — real Claude Messages API client
//
// Native Swift (URLSession) over raw HTTPS, since there's no official Anthropic
// Swift SDK. Uses the Messages API with the web_search server tool, and injects
// the user's long-term memory + live app context into the system prompt. The
// model can save new memories by ending its reply with `remember: <fact>` lines,
// which we parse out before showing the text.

@MainActor
final class ClaudeAssistant: AssistantService {

    let usingLiveAI = true

    private let apiKey: String
    private let model: String
    private let memory: MemoryStore
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    init(apiKey: String, model: String, memory: MemoryStore) {
        self.apiKey = apiKey
        self.model = model
        self.memory = memory
    }

    // MARK: Public

    func reply(history: [ChatTurn], context: AssistantContext) async throws -> [String] {
        // The API requires the first message to be a user turn.
        let trimmed = dropLeadingAssistant(history)
        guard !trimmed.isEmpty else { return [] }

        var messages: [[String: Any]] = trimmed.map {
            ["role": $0.role.rawValue, "content": $0.text]
        }

        // Server-tool loop: web search may pause the turn; resume until done.
        var finalContent: [[String: Any]] = []
        for _ in 0..<5 {
            let (content, stop) = try await send(messages: messages, system: systemPrompt(context))
            finalContent = content
            if stop == "pause_turn" {
                messages.append(["role": "assistant", "content": content])
                continue
            }
            break
        }

        let raw = textBlocks(from: finalContent)
        guard !raw.isEmpty else { throw AssistantError.empty }

        let cleaned = extractMemories(from: raw)
        let deDashed = AssistantText.deDash(cleaned)
        let bubbles = AssistantText.bubbles(from: deDashed)
        guard !bubbles.isEmpty else { throw AssistantError.empty }
        return bubbles
    }

    // MARK: Networking

    private func send(messages: [[String: Any]], system: String) async throws
        -> (content: [[String: Any]], stop: String?) {

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": system,
            "tools": [["type": "web_search_20260209", "name": "web_search"]],
            "messages": messages
        ]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw AssistantError.network(error.localizedDescription)
        }

        guard let http = resp as? HTTPURLResponse else {
            throw AssistantError.network("no response")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard http.statusCode == 200 else {
            let msg = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "request failed"
            throw AssistantError.http(http.statusCode, msg)
        }
        let content = (json?["content"] as? [[String: Any]]) ?? []
        let stop = json?["stop_reason"] as? String
        return (content, stop)
    }

    // MARK: Helpers

    private func dropLeadingAssistant(_ turns: [ChatTurn]) -> [ChatTurn] {
        guard let firstUser = turns.firstIndex(where: { $0.role == .user }) else { return [] }
        return Array(turns[firstUser...])
    }

    private func textBlocks(from content: [[String: Any]]) -> String {
        content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pull `remember: ...` lines into the memory store and strip them from the
    /// visible reply. Case-insensitive, one fact per line.
    private func extractMemories(from raw: String) -> String {
        var kept: [String] = []
        for line in raw.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if let range = t.range(of: "^remember\\s*:\\s*", options: [.regularExpression, .caseInsensitive]) {
                let fact = String(t[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                memory.remember(fact)
            } else {
                kept.append(line)
            }
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func systemPrompt(_ ctx: AssistantContext) -> String {
        var s = """
        You are the WYD Chicago assistant, a friendly guide for high schoolers \
        (ages 13 to 18) in the Chicago area who want to find events and figure out \
        what to do tonight or this weekend.

        VOICE
        Talk like a real teen texting a friend. Casual and warm. lowercase is fine. \
        a few emojis when they fit. keep it short, usually one or two sentences per message.

        HOW YOU REPLY (important)
        Reply the way people actually text: as a few short separate messages, not one \
        long block. Put a blank line between each separate message. Send 1 to 4 \
        messages, never more than 5.

        Never use dashes of any kind. No em dashes, no en dashes, and never use a \
        hyphen as punctuation or to join words. Use commas, periods, or short separate \
        sentences instead.

        MEMORY
        If you learn something worth remembering about this person (their name, school, \
        neighborhood, interests, plans, or vibe), add it at the very end of your reply \
        on its own line formatted exactly like: remember: the fact. Put each fact on \
        its own remember line. These lines are private notes the user never sees, so \
        keep them short.

        SAFETY
        This is for teens, keep it appropriate. Nothing about drugs, alcohol, weapons, \
        or anything unsafe. If someone seems in danger, gently point them to a trusted \
        adult or the 988 line. Never invent exact home addresses.

        You can search the web when you need current info like new events, today's \
        weather, or ticket prices.
        """

        let mem = memory.promptBlock()
        if !mem.isEmpty {
            s += "\n\nWhat you already remember about this person:\n\(mem)"
        }

        var nowLines: [String] = []
        if let name = ctx.userName, !name.isEmpty { nowLines.append("signed in as \(name)") }
        if let ev = ctx.eventsSummary, !ev.isEmpty { nowLines.append("events coming up:\n\(ev)") }
        if !nowLines.isEmpty {
            s += "\n\nRight now in the app:\n" + nowLines.joined(separator: "\n")
        }
        return s
    }
}
