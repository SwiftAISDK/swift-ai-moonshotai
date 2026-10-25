@testable import SwiftAIMoonshotAI
@testable import SwiftAI
@testable import SwiftAIProvider
@testable import SwiftAIProviderUtilities
@testable import SwiftAITransport
import Foundation
import Testing

@Suite("WeeklyMoonshot20261025")
struct WeeklyMoonshot20261025Tests {
    @Test(arguments: ["kimi-k3.1-pro", "kimi-k3.1-pro-highspeed"], [false, true])
    func cacheOptionsUsageAndTTLMetadataWorkForNewKimiModels(_ modelID: String, _ streaming: Bool) async throws {
        let raw: JSONValue = ["id": "chat1", "model": .string(modelID), "choices": [["index": 0, "message": ["content": "OK"], "delta": ["content": "OK"], "finish_reason": "stop"]], "usage": ["prompt_tokens": 22_459, "completion_tokens": 44, "total_tokens": 22_503, "prompt_tokens_details": ["cached_tokens": 1024, "cache_write_tokens": 21_248]]]
        let headers = ["msh-usage-cache-write-tokens-5m": "0", "msh-usage-cache-write-tokens-1h": "21248"]
        let json = String(decoding: try encodeJSONBody(raw), as: UTF8.self)
        let transport = RecordingTransport(response: streaming ? sseResponse("data: " + json, headers: headers) : jsonResponse(json, headers: headers))
        let model = try AIProviders.moonshotAI(configuration: .init(apiKey: "offline-key", transport: transport)).languageModel(modelID)
        let request = LanguageModelRequest(messages: [.user("Hello")], providerOptions: ["moonshotai": ["promptCacheOptions": ["ttl": "1h"], "reasoningHistory": "preserved"]])
        let usage: TokenUsage?
        let metadata: [String: JSONValue]
        if streaming {
            var terminal: (TokenUsage?, [String: JSONValue])?
            for try await part in model.stream(request) {
                if case let .finishMetadata(_, currentUsage, currentMetadata) = part { terminal = (currentUsage, currentMetadata) }
            }
            usage = terminal?.0
            metadata = terminal?.1 ?? [:]
        } else {
            let result = try await model.generate(request)
            usage = result.usage
            metadata = result.providerMetadata
        }
        #expect(usage?.inputTokens == 22_459)
        #expect(usage?.inputTokensNoCache == 187)
        #expect(usage?.inputTokensCacheRead == 1024)
        #expect(usage?.inputTokensCacheWrite == 21_248)
        #expect(metadata["moonshotai"]?["cacheWriteTokens"] == ["ttl5m": 0, "ttl1h": 21_248])
        let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
        #expect(body["prompt_cache_options"] == ["mode": "implicit", "ttl": "1h"])
        #expect(body["thinking"]?["keep"] == "all")
    }

    @Test func emptyCacheOptionsDefaultModeAndAbsentOptionsStayAbsent() throws {
        let base: [String: JSONValue] = [:]
        var warnings: [AIWarning] = []
        let empty = try moonshotChatBody(from: base, request: .init(messages: [], providerOptions: ["moonshotai": ["promptCacheOptions": .object([:])]]), modelID: "kimi-k3", warnings: &warnings)
        #expect(empty["prompt_cache_options"] == ["mode": "implicit"])
        let absent = try moonshotChatBody(from: base, request: .init(messages: []), modelID: "kimi-k3", warnings: &warnings)
        #expect(absent["prompt_cache_options"] == nil)
    }

    @Test(arguments: [JSONValue.null, "bad", ["mode": "explicit"], ["ttl": "24h"], ["ttl": .null]])
    func invalidCacheOptionsFailBeforeNetwork(_ options: JSONValue) async throws {
        let transport = RecordingTransport(response: jsonResponse("{}"))
        let model = try AIProviders.moonshotAI(configuration: .init(apiKey: "offline-key", transport: transport)).languageModel("kimi-k3.1-pro")
        await #expect(throws: AIError.self) {
            _ = try await model.generate(.init(messages: [.user("Hello")], providerOptions: ["moonshotai": ["promptCacheOptions": options]]))
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test(arguments: [" 12 ", "0", "invalid", "-1", "1.5", ""])
    func cacheHeadersAcceptOnlyUnsignedDecimalCounts(_ value: String) {
        let metadata = moonshotCacheWriteMetadata(headers: ["MSH-Usage-Cache-Write-Tokens-1h": value], namespace: "moonshotai")
        if value == " 12 " || value == "0" {
            #expect(metadata["moonshotai"]?["cacheWriteTokens"] == ["ttl5m": 0, "ttl1h": value == "0" ? 0 : 12])
        } else {
            #expect(metadata.isEmpty)
        }
    }

    @Test(arguments: ["anyOf", "oneOf"], ["$defs", "definitions"])
    func objectUnionsResolveOneHopLocalReferences(_ union: String, _ definitions: String) throws {
        let root: JSONValue = [union: [["$ref": .string("#/\(definitions)/City")], ["properties": ["x": ["type": "number"]]]], definitions: ["City": ["type": "object", "properties": ["name": ["type": "string"]]]]]
        let normalized = try moonshotNormalizeJSONSchemaForMFJS(root)
        #expect(normalized["type"] == "object")
        #expect(normalized[union] == root[union])
    }

    @Test func rootObjectKeepsTypeWhileNestedAnyOfMovesTypeToBranches() throws {
        let input: JSONValue = ["type": "object", "anyOf": [["properties": ["x": ["type": "string"]]]], "properties": ["value": ["type": "string", "anyOf": [["enum": ["x"]], ["enum": ["y"]]]]]]
        let result = try moonshotNormalizeJSONSchemaForMFJS(input)
        #expect(result["type"] == "object")
        #expect(result["properties"]?["value"]?["type"] == nil)
        #expect(result["properties"]?["value"]?["anyOf"]?[0]?["type"] == "string")
    }

    @Test(arguments: [JSONValue.bool(true), ["type": "array"], ["anyOf": [["type": "object"], ["type": "string"]]], ["anyOf": [["type": ["object", "null"]]]], ["anyOf": .array([JSONValue]())]])
    func invalidMFJSRootsRemainRejected(_ root: JSONValue) {
        #expect(throws: AIError.self) { try moonshotNormalizeJSONSchemaForMFJS(root) }
    }

    @Test func objectUnionResponseSchemasAreNormalizedBeforeSending() async throws {
        let schema: JSONValue = ["anyOf": [["type": "object", "properties": ["name": ["type": "string"]]], ["type": "object", "properties": ["count": ["type": "number"]]]]]
        let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"{}"},"finish_reason":"stop"}]}"#))
        let model = try AIProviders.moonshotAI(configuration: .init(apiKey: "offline-key", transport: transport)).languageModel("kimi-k3.1-pro")
        _ = try await model.generate(.init(messages: [.user("Hello")], responseFormat: .json(schema: schema)))
        let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
        #expect(body["response_format"]?["json_schema"]?["schema"]?["type"] == "object")
    }

    @Test func booleanResponseSchemaFailsBeforeSending() async throws {
        let transport = RecordingTransport(response: jsonResponse("{}"))
        let model = try AIProviders.moonshotAI(configuration: .init(apiKey: "key", transport: transport)).languageModel("kimi-k3")
        await #expect(throws: AIError.self) {
            _ = try await model.generate(.init(messages: [.user("Hello")], responseFormat: .json(schema: true)))
        }
        #expect(await transport.requests().isEmpty)
    }
}
