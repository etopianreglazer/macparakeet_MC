import Foundation

/// One message in a persisted chat thread. The in-app LLM (and its chat UI)
/// was removed from Splay; this type remains because `Transcription` and
/// `ChatConversation` rows already persist arrays of these messages as JSON —
/// dormant data kept readable, never written to by new code.
public struct ChatMessage: Codable, Sendable, Equatable {
    public let role: Role
    public let content: String
    public let modelPromptOverride: String?

    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }

    public init(role: Role, content: String, modelPromptOverride: String? = nil) {
        self.role = role
        self.content = content
        self.modelPromptOverride = modelPromptOverride
    }
}
