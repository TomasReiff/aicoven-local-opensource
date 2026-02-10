import Foundation

/// Represents a single chat message in the core LLM interface.
/// Conforms to Sendable since all properties are value types.
public struct LLMMessage: Sendable {
    public enum Role: String, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    public let id: UUID
    public let role: Role
    public let content: String

    public init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

/// High-level result of a chat completion.
/// Conforms to Sendable since all properties are Sendable.
public struct LLMChatResponse: Sendable {
    public let message: LLMMessage
    public let providerID: String
    public let modelID: String
    public let usage: LLMTokenUsage?

    public init(message: LLMMessage, providerID: String, modelID: String, usage: LLMTokenUsage?) {
        self.message = message
        self.providerID = providerID
        self.modelID = modelID
        self.usage = usage
    }
}

/// Simple token usage accounting for routing and UX.
/// Conforms to Sendable since all properties are value types.
public struct LLMTokenUsage: Sendable {
    public let promptTokens: Int
    public let completionTokens: Int

    public var totalTokens: Int { promptTokens + completionTokens }

    public init(promptTokens: Int, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

/// Options for chat completion requests.
/// Conforms to Sendable since all properties are value types.
public struct ChatOptions: Sendable {
    public let temperature: Double
    public let maxTokens: Int?
    public let stream: Bool

    public init(temperature: Double = 0.7, maxTokens: Int? = nil, stream: Bool = false) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.stream = stream
    }
}

/// Protocol for LLM clients that can perform chat completions and embeddings.
/// Marked as Sendable to allow safe use across actor boundaries.
public protocol LLMClient: Sendable {
    /// Performs a chat completion for the given messages and model identifier.
    func completeChat(messages: [LLMMessage], model: String, options: ChatOptions) async throws -> LLMChatResponse

    /// Computes embeddings for one or more texts using the specified embedding model.
    func embed(texts: [String], model: String) async throws -> [[Float]]
}
