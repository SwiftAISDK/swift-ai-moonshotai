import Foundation
import SwiftAIProvider
import SwiftAITransport
import SwiftAIOpenAICompatible
import SwiftAIProviderUtilities

public struct MoonshotAIProviderSettings: Sendable {
    public var apiKey: String?
    public var baseURL: String?
    public var headers: [String: String]
    public var queryParams: [String: String]
    public var supportsStructuredOutputs: Bool
    public var supportsMultiPartToolContent: Bool
    public var maxEmbeddingsPerCall: Int?
    public var transformRequestBody: (@Sendable ([String: JSONValue]) -> [String: JSONValue])?
    public var transformRequestBodyWithWarnings: (@Sendable ([String: JSONValue], inout [AIWarning]) -> [String: JSONValue])?
    public var transport: any AITransport

    public init(apiKey: String? = nil, baseURL: String? = nil, headers: [String: String] = [:],
                queryParams: [String: String] = [:], transport: any AITransport = URLSessionTransport.shared,
                supportsStructuredOutputs: Bool = false, supportsMultiPartToolContent: Bool = false, maxEmbeddingsPerCall: Int? = nil, transformRequestBody: (@Sendable ([String: JSONValue]) -> [String: JSONValue])? = nil, transformRequestBodyWithWarnings: (@Sendable ([String: JSONValue], inout [AIWarning]) -> [String: JSONValue])? = nil) {
        self.apiKey = apiKey; self.baseURL = baseURL; self.headers = headers
        self.queryParams = queryParams; self.transport = transport
        self.supportsStructuredOutputs = supportsStructuredOutputs; self.supportsMultiPartToolContent = supportsMultiPartToolContent; self.maxEmbeddingsPerCall = maxEmbeddingsPerCall; self.transformRequestBody = transformRequestBody; self.transformRequestBodyWithWarnings = transformRequestBodyWithWarnings
    }
}

public final class MoonshotAIProvider: AIProvider, Sendable {
    public let providerID = "moonshotai"
    public let supportedCapabilities: Set<ModelCapability> = [.language]
    private let config: MoonshotAIModelConfiguration

    public init(configuration: MoonshotAIProviderSettings = .init()) throws {
        let names = ["MOONSHOT_API_KEY"]
        guard let key = configuration.apiKey ?? environmentValue(names) else {
            throw AIError.missingAPIKey(provider: "moonshotai", environmentVariables: names)
        }
        var headers = configuration.headers
        headers["Authorization"] = headers["Authorization"] ?? "Bearer \(key)"
        headers = withUserAgentSuffix(headers, "ai-sdk-moonshotai/3.0.78")
        let baseURL = withoutTrailingSlash(configuration.baseURL ?? "https://api.moonshot.ai/v1")
        let http = AIProviderHTTPClient(providerID: "moonshotai", headers: headers, transport: configuration.transport,
            url: { _, path in try providerURL("\(baseURL)\(path)", queryParams: configuration.queryParams) })
        config = MoonshotAIModelConfiguration(http: http, baseURL: baseURL ,supportsStructuredOutputs: configuration.supportsStructuredOutputs, supportsMultiPartToolContent: configuration.supportsMultiPartToolContent, maxEmbeddingsPerCall: configuration.maxEmbeddingsPerCall, transformRequestBody: configuration.transformRequestBody, transformRequestBodyWithWarnings: configuration.transformRequestBodyWithWarnings)
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        var wire = compatibleConfiguration(surface: "chat")
        configureMoonshotChat(&wire)
        return OpenAICompatibleChatModel(modelID: modelID, config: wire)
    }

    public func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .embedding, modelID: modelID)
    }

    public func imageModel(_ modelID: String) throws -> any ImageModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .image, modelID: modelID)
    }

    public func transcriptionModel(_ modelID: String) throws -> any TranscriptionModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .transcription, modelID: modelID)
    }

    public func speechModel(_ modelID: String) throws -> any SpeechModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .speech, modelID: modelID)
    }

    public func videoModel(_ modelID: String) throws -> any VideoModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .video, modelID: modelID)
    }

    public func rerankingModel(_ modelID: String) throws -> any RerankingModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .reranking, modelID: modelID)
    }

    private func compatibleConfiguration(surface: String) -> OpenAICompatibleModelConfiguration {
        var http = config.http
        http.providerID = "moonshotai.\(surface)"
        var wire = OpenAICompatibleModelConfiguration(http: http, baseURL: config.baseURL)
        wire.includeUsage = true
        wire.usesGenericOpenAICompatibleProviderOptions = false
        wire.allowsEmptyTextResponse = false
        wire.supportsStructuredOutputs = config.supportsStructuredOutputs
        wire.supportsMultiPartToolContent = config.supportsMultiPartToolContent
        wire.maxEmbeddingsPerCall = config.maxEmbeddingsPerCall
        wire.transformRequestBody = config.transformRequestBody
        wire.transformRequestBodyWithWarnings = config.transformRequestBodyWithWarnings
        wire.errorHandler = { apiCallError(provider: "moonshotai.\(surface)", response: $0) }
        return wire
    }

    public func chatModel(_ modelID: String) throws -> any LanguageModel { try languageModel(modelID) }
}

public extension AIProviders {
    static func moonshotAI(configuration: MoonshotAIProviderSettings) throws -> MoonshotAIProvider {
        try MoonshotAIProvider(configuration: configuration)
    }
}

public struct MoonshotAIModelConfiguration: AIProviderHTTPConfiguration {
    public var http: AIProviderHTTPClient
    public var baseURL: String
    public var supportsStructuredOutputs: Bool
    public var supportsMultiPartToolContent: Bool
    public var maxEmbeddingsPerCall: Int?
    public var transformRequestBody: (@Sendable ([String: JSONValue]) -> [String: JSONValue])?
    public var transformRequestBodyWithWarnings: (@Sendable ([String: JSONValue], inout [AIWarning]) -> [String: JSONValue])?
    public init(http: AIProviderHTTPClient, baseURL: String ,supportsStructuredOutputs: Bool = false, supportsMultiPartToolContent: Bool = false, maxEmbeddingsPerCall: Int? = nil, transformRequestBody: (@Sendable ([String: JSONValue]) -> [String: JSONValue])? = nil, transformRequestBodyWithWarnings: (@Sendable ([String: JSONValue], inout [AIWarning]) -> [String: JSONValue])? = nil) {
        self.http = http; self.baseURL = withoutTrailingSlash(baseURL)
        self.supportsStructuredOutputs = supportsStructuredOutputs
        self.supportsMultiPartToolContent = supportsMultiPartToolContent
        self.maxEmbeddingsPerCall = maxEmbeddingsPerCall
        self.transformRequestBody = transformRequestBody
        self.transformRequestBodyWithWarnings = transformRequestBodyWithWarnings
    }
}
