import Foundation

/// Anthropic Claude implementation of LLMClient (messages API).
/// Marked @unchecked Sendable because all stored properties are immutable
/// after init and URLSession is thread-safe.
final class AnthropicLLMClient: LLMClient, @unchecked Sendable {
    private let apiKey: String
    private let baseURL: URL
    private let urlSession: URLSession

    /// - Parameters:
    ///   - apiKey: Anthropic API key.
    ///   - baseURL: Base URL for the API (overridable for testing).
    ///   - urlSession: Optional custom URLSession used primarily for tests.
    init(apiKey: String,
         baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
         urlSession: URLSession? = nil) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        if let urlSession {
            self.urlSession = urlSession
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 120
            self.urlSession = URLSession(configuration: config)
        }
    }

    func completeChat(messages: [LLMMessage], model: String, options: ChatOptions) async throws -> LLMChatResponse {
        struct MessageContent: Encodable { let type = "text"; let text: String }
        struct RequestMessage: Encodable { let role: String; let content: [MessageContent] }
        struct RequestBody: Encodable {
            let model: String
            let max_tokens: Int
            let messages: [RequestMessage]
            let temperature: Double
        }
        struct ResponseBody: Decodable {
            struct ContentBlock: Decodable { let text: String? }
            struct Usage: Decodable {
                let input_tokens: Int?
                let output_tokens: Int?
            }
            let content: [ContentBlock]
            let model: String
            let usage: Usage?
        }

        let url = baseURL.appendingPathComponent("messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let reqMessages = messages.map { msg in
            RequestMessage(
                role: msg.role == .user ? "user" : "assistant",
                content: [MessageContent(text: msg.content)]
            )
        }
        let body = RequestBody(model: model,
                               max_tokens: options.maxTokens ?? 1024,
                               messages: reqMessages,
                               temperature: options.temperature)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            let message = "Anthropic HTTP \(http.statusCode): \(bodyText)"
            throw NSError(domain: "AnthropicLLMClient", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        guard !data.isEmpty else {
            throw NSError(domain: "AnthropicLLMClient", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Anthropic returned an empty response body."])
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let text = decoded.content.compactMap { $0.text }.joined(separator: "\n")
        let msg = LLMMessage(role: .assistant, content: text)
        
        let usage = decoded.usage.map { u in
            LLMTokenUsage(
                promptTokens: u.input_tokens ?? 0,
                completionTokens: u.output_tokens ?? 0
            )
        }
        
        return LLMChatResponse(message: msg, providerID: "anthropic", modelID: decoded.model, usage: usage)
    }

    func embed(texts: [String], model: String) async throws -> [[Float]] {
        // Anthropic does not currently expose a general-purpose embeddings API
        // in the same way; for now this is unsupported.
        throw NSError(domain: "AnthropicLLMClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Embeddings are not supported for Anthropic in this client."])
    }
}