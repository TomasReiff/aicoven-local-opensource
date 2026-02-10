import Foundation

/// OpenAI-compatible implementation of LLMClient.
/// Marked @unchecked Sendable because all stored properties are immutable
/// after init and URLSession is thread-safe.
final class OpenAILLMClient: LLMClient, @unchecked Sendable {
    private let apiKey: String
    private let baseURL: URL
    private let urlSession: URLSession

    /// - Parameters:
    ///   - apiKey: OpenAI API key.
    ///   - baseURL: Base URL for the API (overridable for testing).
    ///   - urlSession: Optional custom URLSession used primarily for tests.
    init(apiKey: String,
         baseURL: URL = URL(string: "https://api.openai.com/v1")!,
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

    // MARK: - LLMClient

    func completeChat(messages: [LLMMessage], model: String, options: ChatOptions) async throws -> LLMChatResponse {
        struct RequestMessage: Encodable {
            let role: String
            let content: String
        }
        struct RequestBody: Encodable {
            let model: String
            let messages: [RequestMessage]
            let temperature: Double
        }
        struct ResponseBody: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let role: String
                    let content: String
                }
                let message: Message
            }
            struct UsageBody: Decodable {
                let prompt_tokens: Int?
                let completion_tokens: Int?
            }
            let choices: [Choice]
            let usage: UsageBody?
            let model: String
        }

        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let reqMessages = messages.map { msg in
            RequestMessage(role: msg.role.rawValue, content: msg.content)
        }
        let body = RequestBody(model: model, messages: reqMessages, temperature: options.temperature)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            let message = "OpenAI HTTP \(http.statusCode): \(bodyText)"
            throw NSError(domain: "OpenAILLMClient", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        guard !data.isEmpty else {
            throw NSError(domain: "OpenAILLMClient", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "OpenAI returned an empty response body."])
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let first = decoded.choices.first else {
            throw NSError(domain: "OpenAILLMClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No choices in response"])
        }

        let msg = LLMMessage(role: .assistant, content: first.message.content)
        let usage: LLMTokenUsage?
        if let u = decoded.usage {
            usage = LLMTokenUsage(promptTokens: u.prompt_tokens ?? 0, completionTokens: u.completion_tokens ?? 0)
        } else {
            usage = nil
        }

        return LLMChatResponse(message: msg, providerID: "openai", modelID: decoded.model, usage: usage)
    }

    func embed(texts: [String], model: String) async throws -> [[Float]] {
        struct EmbeddingRequest: Encodable {
            let model: String
            let input: [String]
        }
        struct EmbeddingResponse: Decodable {
            struct Item: Decodable { let embedding: [Float] }
            let data: [Item]
        }

        let url = baseURL.appendingPathComponent("embeddings")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = EmbeddingRequest(model: model, input: texts)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            let message = "OpenAI embeddings HTTP \(http.statusCode): \(bodyText)"
            throw NSError(domain: "OpenAILLMClient", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        guard !data.isEmpty else {
            throw NSError(domain: "OpenAILLMClient", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "OpenAI returned an empty embeddings response body."])
        }
        let decoded = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
        return decoded.data.map { $0.embedding }
    }
}