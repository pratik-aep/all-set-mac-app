import CoreGraphics
import Foundation
import Observation

/// The AI calls the screenshot studio makes, injectable so tests can answer
/// slowly, fail, or answer after the document has changed.
public struct ScreenshotAI: Sendable {
    public var key: @Sendable (AIProvider) -> String?
    /// Claude: the instruction, the session so far and the key; the session after it and the reply.
    public var claude: @Sendable (String, ClaudeSession, String) async throws -> (ClaudeSession, ClaudeReply)
    /// ChatGPT: the picture, the instruction and the key; the new picture.
    public var openAI: @Sendable (CGImage, String, String) async throws -> CGImage

    public init(key: @escaping @Sendable (AIProvider) -> String?,
                claude: @escaping @Sendable (String, ClaudeSession, String) async throws -> (ClaudeSession, ClaudeReply),
                openAI: @escaping @Sendable (CGImage, String, String) async throws -> CGImage) {
        self.key = key
        self.claude = claude
        self.openAI = openAI
    }

    public static let live = ScreenshotAI(
        key: { AIKeychain.key(for: $0) },
        claude: { instruction, session, key in
            var session = session
            let reply = try await ClaudeImageEditor.ask(instruction, in: &session, key: key)
            return (session, reply)
        },
        openAI: { image, instruction, key in try await OpenAIImageEditor.edit(image, instruction: instruction, key: key) }
    )
}

/// A screenshot being edited, with each version kept for undo and the
/// conversation with the AI.
///
/// Claude always sees the picture as it started (or as ChatGPT last redrew
/// it), with the conversation so far. Its edits all refer to that picture and
/// are drawn onto it together, so the picture and history can come from
/// Claude's prompt cache on every follow-up instead of being sent afresh.
///
/// Each loaded picture is a new document (`generation`): an AI answer that
/// arrives after New Screenshot or Open is dropped, never applied to the new one.
@Observable @MainActor
public final class ScreenshotStudio {
    public struct Message: Identifiable, Equatable {
        public enum Role: Sendable { case user, assistant, problem }
        public let id = UUID()
        public let role: Role
        public let text: String
        /// Small print under a reply, like what it cost.
        public var detail: String?

        public init(role: Role, text: String, detail: String? = nil) {
            self.role = role
            self.text = text
            self.detail = detail
        }
    }

    /// One step, for undo.
    private struct State {
        var image: CGImage
        /// What Claude's edits are drawn on.
        var base: CGImage
        var edits: [ScreenshotEdit] = []
        var session: ClaudeSession?
    }

    private var states: [State] = []
    /// Versions kept for undo besides the original, by count and by size: each is
    /// a full-size picture (about 60 MB for a 5K screenshot). The oldest edits go
    /// first; the original never does.
    private static let undoDepth = 24
    public nonisolated static let historyByteBudget = 600 << 20

    private func push(_ state: State) {
        states.append(state)
        if states.count > Self.undoDepth + 1 { states.remove(at: 1) }
        while states.count > 2, historyBytes > historyBudget { states.remove(at: 1) }
    }

    /// Pixel bytes the kept versions hold (shared pictures counted once).
    public var historyBytes: Int {
        var seen = Set<ObjectIdentifier>()
        return states.flatMap { [$0.image, $0.base] }.reduce(0) { total, image in
            seen.insert(ObjectIdentifier(image)).inserted ? total + image.bytesPerRow * image.height : total
        }
    }

    public private(set) var messages: [Message] = []
    public private(set) var isWorking = false
    /// Goes up with every picture loaded; work started for an older one is dropped.
    public private(set) var generation = 0
    /// 2 for a Retina screenshot: Claude gets one pixel per point, which is plenty.
    private var pixelsPerPoint = 1.0
    private let ai: ScreenshotAI
    private let historyBudget: Int
    public var provider: AIProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: "screenshot.provider") }
    }

    public init(ai: ScreenshotAI = .live, historyBudget: Int = ScreenshotStudio.historyByteBudget) {
        self.ai = ai
        self.historyBudget = historyBudget
        provider = UserDefaults.standard.string(forKey: "screenshot.provider").flatMap(AIProvider.init) ?? .claude
    }

    public var image: CGImage? { states.last?.image }
    public var versionCount: Int { states.count }

    /// A new document: any answer still on its way for the previous one is dropped.
    public func load(_ image: CGImage, pixelsPerPoint: Double = 1) {
        generation += 1
        isWorking = false
        self.pixelsPerPoint = pixelsPerPoint
        states = [State(image: image, base: image)]
        messages = []
    }

    public func undo() {
        guard states.count > 1 else { return }
        states.removeLast()
        messages.append(Message(role: .assistant, text: "Undone."))
    }

    public func ask(_ instruction: String) async {
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, var state = states.last, !isWorking else { return }
        guard let key = ai.key(provider) else {
            messages.append(Message(role: .problem, text: "Add your \(provider.title) API key first."))
            return
        }
        let document = generation
        /// Whether the picture this request was about is still the one open.
        func stillCurrent() -> Bool { generation == document }
        messages.append(Message(role: .user, text: instruction))
        isWorking = true
        defer { if stillCurrent() { isWorking = false } }
        do {
            switch provider {
            case .claude:
                let ratio = pixelsPerPoint
                var session: ClaudeSession
                if let existing = state.session {
                    session = existing
                } else {
                    let base = state.base
                    guard let fresh = await Task.detached(operation: { ClaudeSession(image: base, pixelsPerPoint: ratio) }).value else {
                        throw AIEditError("The screenshot couldn't be prepared.")
                    }
                    session = fresh
                }
                let (answered, reply) = try await ai.claude(instruction, session, key)
                guard stillCurrent() else { return }
                state.session = answered
                if !reply.plan.edits.isEmpty {
                    state.edits += reply.plan.edits
                    let edits = state.edits
                    let base = state.base
                    let edited = await Task.detached(operation: { ScreenshotRenderer.apply(edits, to: base) }).value
                    guard stillCurrent() else { return }
                    if let edited { state.image = edited }
                }
                push(state)
                messages.append(Message(role: .assistant, text: reply.plan.reply.isEmpty ? "Done." : reply.plan.reply,
                                        detail: reply.usage.total > 0 ? reply.usage.summary : nil))
            case .openAI:
                let edited = try await ai.openAI(state.image, instruction, key)
                guard stillCurrent() else { return }
                // A new picture: Claude starts afresh on it.
                push(State(image: edited, base: edited))
                messages.append(Message(role: .assistant, text: "Here's the new version."))
            }
        } catch {
            // A failure for a picture that's no longer open belongs to nobody.
            guard stillCurrent() else { return }
            let text = (error as? AIEditError)?.description ?? error.localizedDescription
            messages.append(Message(role: .problem, text: text))
        }
    }
}
