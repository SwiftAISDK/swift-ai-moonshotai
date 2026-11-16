@testable import SwiftAIMoonshotAI
@testable import SwiftAIProvider
@testable import SwiftAIProviderUtilities
@testable import SwiftAITransport
import Foundation
import Testing

// Translated from packages/moonshotai/src/moonshotai-chat-language-model.test.ts
// (matching-release ref 8bc7652c). Fixtures are inlined from src/__fixtures__.

private enum Fixture {
    static let text = #"{"id":"chatcmpl-test-text","object":"chat.completion","created":1785880000,"model":"kimi-k3","choices":[{"index":0,"message":{"role":"assistant","content":"Hello, world!"},"finish_reason":"stop"}],"usage":{"prompt_tokens":9,"completion_tokens":5,"total_tokens":14}}"#
    static let reasoning = #"{"id":"chatcmpl-test-reasoning","object":"chat.completion","created":1785880001,"model":"kimi-k2.6","choices":[{"index":0,"message":{"role":"assistant","content":"There are three.","reasoning_content":"Let me count the letters carefully."},"finish_reason":"stop"}],"usage":{"prompt_tokens":20,"completion_tokens":30,"total_tokens":50,"cached_tokens":10,"completion_tokens_details":{"reasoning_tokens":22}}}"#
    static let toolCall = #"{"id":"chatcmpl-test-tool","object":"chat.completion","created":1785880002,"model":"kimi-k3","choices":[{"index":0,"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_abc123","type":"function","function":{"name":"get_weather","arguments":"{\"city\":\"Paris\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":30,"completion_tokens":12,"total_tokens":42}}"#
    static let logprobs = #"{"id":"chatcmpl-test-logprobs","object":"chat.completion","created":1787685804,"model":"moonshot-v1-8k","choices":[{"index":0,"message":{"role":"assistant","content":"OK!"},"finish_reason":"stop","logprobs":{"content":[{"token":"OK","logprob":-0.0004808938247151673,"bytes":[79,75],"top_logprobs":[{"token":"OK","logprob":-0.0004808938247151673,"bytes":[79,75]}]},{"token":"!","logprob":-0.01,"bytes":null,"top_logprobs":[{"token":"!","logprob":-0.01,"bytes":null}]}]}}],"usage":{"prompt_tokens":11,"completion_tokens":3,"total_tokens":14}}"#
    static let error = #"{"error":{"message":"Invalid request: invalid part type: file","type":"invalid_request_error","code":"invalid_parameter"}}"#

    static let streamChunks = [
        #"{"id":"chatcmpl-stream","created":1785880003,"model":"kimi-k3","choices":[{"index":0,"delta":{"role":"assistant","reasoning_content":"Thinking "},"finish_reason":null}]}"#,
        #"{"id":"chatcmpl-stream","created":1785880003,"model":"kimi-k3","choices":[{"index":0,"delta":{"reasoning_content":"aloud. "},"finish_reason":null}]}"#,
        #"{"id":"chatcmpl-stream","created":1785880003,"model":"kimi-k3","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}"#,
        #"{"id":"chatcmpl-stream","created":1785880003,"model":"kimi-k3","choices":[{"index":0,"delta":{"content":"!"},"finish_reason":"stop"}],"usage":{"prompt_tokens":9,"completion_tokens":12,"total_tokens":21,"completion_tokens_details":{"reasoning_tokens":7}}}"#
    ]
    static let toolCallChunks = [
        #"{"id":"chatcmpl-stream-tool","object":"chat.completion.chunk","created":1785880004,"model":"kimi-k3","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_abc123","type":"function","function":{"name":"get_weather","arguments":""}}]},"finish_reason":null}]}"#,
        #"{"id":"chatcmpl-stream-tool","object":"chat.completion.chunk","created":1785880004,"model":"kimi-k3","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"city\":\"Paris\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":30,"completion_tokens":12,"total_tokens":42}}"#
    ]
    static let logprobsChunks = [
        #"{"id":"chatcmpl-test-logprobs-stream","object":"chat.completion.chunk","created":1787685810,"model":"moonshot-v1-8k","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}"#,
        #"{"id":"chatcmpl-test-logprobs-stream","object":"chat.completion.chunk","created":1787685810,"model":"moonshot-v1-8k","choices":[{"index":0,"delta":{"content":"OK"},"logprobs":{"content":[{"token":"OK","logprob":-0.0004457433824427426,"bytes":[79,75],"top_logprobs":[{"token":"OK","logprob":-0.0004457433824427426,"bytes":[79,75]}]}]},"finish_reason":null}]}"#,
        #"{"id":"chatcmpl-test-logprobs-stream","object":"chat.completion.chunk","created":1787685810,"model":"moonshot-v1-8k","choices":[{"index":0,"delta":{"content":"!"},"logprobs":{"content":[{"token":"!","logprob":-0.01,"bytes":null,"top_logprobs":[{"token":"!","logprob":-0.01,"bytes":null}]}]},"finish_reason":null}]}"#,
        #"{"id":"chatcmpl-test-logprobs-stream","object":"chat.completion.chunk","created":1787685810,"model":"moonshot-v1-8k","choices":[{"index":0,"delta":{},"finish_reason":"stop","usage":{"prompt_tokens":11,"completion_tokens":3,"total_tokens":14}}]}"#,
        #"{"id":"chatcmpl-test-logprobs-stream","object":"chat.completion.chunk","created":1787685810,"model":"moonshot-v1-8k","choices":[],"usage":{"prompt_tokens":11,"completion_tokens":3,"total_tokens":14}}"#
    ]
    static let indexlessToolCallChunks = [
        #"{"id":"chatcmpl-indexless","object":"chat.completion.chunk","created":1787685025,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}"#,
        #"{"id":"chatcmpl-indexless","object":"chat.completion.chunk","created":1787685025,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"tool_calls":[{"id":"weather_0","type":"function","function":{"name":"weather","arguments":""}},{"id":"time_1","type":"function","function":{"name":"time","arguments":""}}]},"finish_reason":null}]}"#,
        #"{"id":"chatcmpl-indexless","object":"chat.completion.chunk","created":1787685025,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"tool_calls":[{"function":{"arguments":"{\"location\":\"San Francisco\"}"}},{"function":{"arguments":"{\"zone\":\"UTC\"}"}}]},"finish_reason":null}]}"#,
        #"{"id":"chatcmpl-indexless","object":"chat.completion.chunk","created":1787685025,"model":"kimi-k2.5","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls","usage":{"prompt_tokens":61,"completion_tokens":25,"total_tokens":86}}]}"#,
        #"{"id":"chatcmpl-indexless","object":"chat.completion.chunk","created":1787685025,"model":"kimi-k2.5","choices":[],"usage":{"prompt_tokens":61,"completion_tokens":25,"total_tokens":86}}"#
    ]
    static let explicitIndexChunks = [
        #"{"id":"c","object":"chat.completion.chunk","created":1787685025,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}"#,
        #"{"id":"c","object":"chat.completion.chunk","created":1787685025,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"reasoning_content":""},"finish_reason":null}]}"#,
        #"{"id":"c","object":"chat.completion.chunk","created":1787685025,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"weather_0","type":"function","function":{"name":"weather","arguments":""}}]},"finish_reason":null}]}"#,
        #"{"id":"c","object":"chat.completion.chunk","created":1787685025,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\""}}]},"finish_reason":null}]}"#,
        #"{"id":"c","object":"chat.completion.chunk","created":1787685025,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"location"}}]},"finish_reason":null}]}"#,
        #"{"id":"c","object":"chat.completion.chunk","created":1787685025,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\":"}}]},"finish_reason":null}]}"#,
        #"{"id":"c","object":"chat.completion.chunk","created":1787685025,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":" \""}}]},"finish_reason":null}]}"#,
        #"{"id":"c","object":"chat.completion.chunk","created":1787685025,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"San"}}]},"finish_reason":null}]}"#,
        #"{"id":"c","object":"chat.completion.chunk","created":1787685025,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":" Francisco"}}]},"finish_reason":null}]}"#,
        #"{"id":"c","object":"chat.completion.chunk","created":1787685025,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"}"}}]},"finish_reason":null}]}"#,
        #"{"id":"c","object":"chat.completion.chunk","created":1787685025,"model":"kimi-k2.5","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls","usage":{"prompt_tokens":61,"completion_tokens":19,"total_tokens":80,"completion_tokens_details":{"reasoning_tokens":1}}}]}"#
    ]
    static let malformedIndexChunks = [
        #"{"id":"chatcmpl-malformed","object":"chat.completion.chunk","created":1787685025,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"tool_calls":[{"index":"not-a-number","id":"weather_0","type":"function","function":{"name":"weather","arguments":"{}"}}]},"finish_reason":null}]}"#
    ]
    static let choiceUsageChunks = [
        #"{"id":"u","object":"chat.completion.chunk","created":1787685040,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}"#,
        #"{"id":"u","object":"chat.completion.chunk","created":1787685040,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"content":"OK"},"finish_reason":null}]}"#,
        #"{"id":"u","object":"chat.completion.chunk","created":1787685040,"model":"kimi-k2.5","choices":[{"index":0,"delta":{},"finish_reason":"stop","usage":{"prompt_tokens":12,"completion_tokens":5,"total_tokens":17,"completion_tokens_details":{"reasoning_tokens":1}}}]}"#
    ]
    static let usagePrecedenceChunks = [
        #"{"id":"p","object":"chat.completion.chunk","created":1787685040,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"content":"OK"},"finish_reason":null}]}"#,
        #"{"id":"p","object":"chat.completion.chunk","created":1787685040,"model":"kimi-k2.5","choices":[{"index":0,"delta":{},"finish_reason":"stop","usage":{"prompt_tokens":12,"completion_tokens":5,"total_tokens":17}}]}"#,
        #"{"id":"p","object":"chat.completion.chunk","created":1787685040,"model":"kimi-k2.5","choices":[],"usage":{"prompt_tokens":99,"completion_tokens":33,"total_tokens":132}}"#
    ]
}

private func chunks(_ lines: [String], headers: [String: String] = [:]) -> AIHTTPResponse {
    sseResponse((lines + ["[DONE]"]).map { "data: \($0)\n\n" }.joined(), headers: headers)
}

private func makeModel(_ modelID: String, _ response: AIHTTPResponse) throws -> (any LanguageModel, RecordingTransport) {
    let transport = RecordingTransport(response: response)
    let provider = try MoonshotAIProvider(configuration: .init(apiKey: "test-api-key", transport: transport))
    return (try provider.chatModel(modelID), transport)
}

private func sentBody(_ transport: RecordingTransport) async throws -> JSONValue {
    try decodeJSONBody(try #require(await transport.requests().first?.body))
}

private func collect(_ model: any LanguageModel, _ request: LanguageModelRequest) async throws -> [LanguageStreamPart] {
    var parts: [LanguageStreamPart] = []
    for try await part in model.stream(request) { parts.append(part) }
    return parts
}

private let hello = LanguageModelRequest(messages: [.user("Hello")])

private func withOptions(_ options: JSONValue, reasoning: String? = nil) -> LanguageModelRequest {
    LanguageModelRequest(messages: [.user("Hello")], reasoning: reasoning, providerOptions: ["moonshotai": options])
}

@Suite("Moonshot upstream doGenerate")
struct MoonshotUpstreamGenerateTests {
    @Test func sendsCorrectRequestBody() async throws {
        let (model, transport) = try makeModel("moonshot-v1-8k", jsonResponse(Fixture.text))
        _ = try await model.generate(LanguageModelRequest(
            messages: [.system("You are a helpful assistant."), .user("Hello")],
            temperature: 0.5,
            topP: 0.3
        ))
        #expect(try await sentBody(transport) == [
            "messages": [["content": "You are a helpful assistant.", "role": "system"], ["content": "Hello", "role": "user"]],
            "model": "moonshot-v1-8k",
            "temperature": 0.5,
            "top_p": 0.3
        ])
    }

    @Test func sendsMessageNames() async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        _ = try await model.generate(LanguageModelRequest(messages: [
            AIMessage(role: .system, content: [.text("You are a helpful assistant.")], providerMetadata: ["moonshotai": ["name": "guide"]]),
            AIMessage(role: .user, content: [.text("Hello")], providerMetadata: ["moonshotai": ["name": "alice"]]),
            AIMessage(role: .assistant, content: [.text("Hello, Alice.")], providerMetadata: ["moonshotai": ["name": "assistant"]])
        ]))
        #expect(try await sentBody(transport)["messages"] == [
            ["role": "system", "content": "You are a helpful assistant.", "name": "guide"],
            ["role": "user", "content": "Hello", "name": "alice"],
            ["role": "assistant", "content": "Hello, Alice.", "name": "assistant"]
        ])
    }

    @Test(arguments: [17, nil] as [Int?])
    func sendsMaxOutputTokensAsMaxCompletionTokens(_ maxOutputTokens: Int?) async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], maxOutputTokens: maxOutputTokens))
        let body = try await sentBody(transport)
        #expect(body["max_completion_tokens"] == maxOutputTokens.map { .number(Double($0)) })
        #expect(body["max_tokens"] == nil)
    }

    @Test(arguments: ["kimi-k2.5", "kimi-k2.6", "kimi-k2.7-code", "kimi-k2.7-code-highspeed", "kimi-k3", "kimi-k3.1-pro", "kimi-k3.1-pro-highspeed"])
    func omitsFixedSamplingOptionsAndWarns(_ modelID: String) async throws {
        let (model, transport) = try makeModel(modelID, jsonResponse(Fixture.text))
        let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], temperature: 0.2, topP: 0.4, presencePenalty: 0.6, frequencyPenalty: 0.5))
        #expect(try await sentBody(transport) == ["model": .string(modelID), "messages": [["role": "user", "content": "Hello"]]])
        let features: [String] = ["temperature", "topP", "frequencyPenalty", "presencePenalty"]
        #expect(result.warnings == features.map { (feature: String) in
            AIWarning(type: "unsupported", feature: feature, message: "\(feature) is fixed by model \"\(modelID)\" and has been omitted.")
        })
    }

    @Test func preservesSamplingOptionsForCustomModelIDs() async throws {
        let (model, transport) = try makeModel("custom-model", jsonResponse(Fixture.text))
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], temperature: 0.2, topP: 0.4, presencePenalty: 0.6, frequencyPenalty: 0.5))
        let body = try await sentBody(transport)
        #expect(body["temperature"] == 0.2 && body["top_p"] == 0.4 && body["frequency_penalty"] == 0.5 && body["presence_penalty"] == 0.6)
    }

    @Test func extractsTextFinishReasonAndUsage() async throws {
        let (model, _) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        let result = try await model.generate(hello)
        #expect(result.content == [.text("Hello, world!")])
        #expect(result.finishReason == "stop")
        #expect(result.usage?.inputTokens == 9 && result.usage?.inputTokensNoCache == 9 && result.usage?.inputTokensCacheRead == 0)
        #expect(result.usage?.outputTokens == 5 && result.usage?.outputTextTokens == 5 && result.usage?.outputReasoningTokens == 0)
        #expect(result.providerMetadata == ["moonshotai": ["responseObject": "chat.completion", "choiceIndex": 0, "messageRole": "assistant"]])
    }

    @Test(arguments: [true, false])
    func toleratesNullishResponseMetadataFields(_ useNull: Bool) async throws {
        var raw = try decodeJSONBody(Data(Fixture.text.utf8)).objectValue ?? [:]
        var choice = raw["choices"]?[0]?.objectValue ?? [:]
        var message = choice["message"]?.objectValue ?? [:]
        if useNull { raw["object"] = .null; choice["index"] = .null; message["role"] = .null }
        else { raw.removeValue(forKey: "object"); choice.removeValue(forKey: "index"); message.removeValue(forKey: "role") }
        choice["message"] = .object(message)
        raw["choices"] = [.object(choice)]
        let (model, _) = try makeModel("kimi-k3", jsonResponse(String(decoding: try encodeJSONBody(.object(raw)), as: UTF8.self)))
        #expect(try await model.generate(hello).providerMetadata == ["moonshotai": .object([:])])
    }

    @Test func preservesExtraFieldsInRawUsage() async throws {
        let usage = #"{"prompt_tokens":100,"completion_tokens":50,"total_tokens":150,"cached_tokens":20,"provider_usage_id":"usage-123","prompt_tokens_details":{"cached_tokens":20,"cache_type":"ephemeral"},"completion_tokens_details":{"reasoning_tokens":10,"billable_tokens":42}}"#
        let (model, _) = try makeModel("kimi-k3", jsonResponse(#"{"id":"chatcmpl-raw-usage","object":"chat.completion","created":1785880000,"model":"kimi-k3","choices":[{"index":0,"message":{"role":"assistant","content":"Hello"},"finish_reason":"stop"}],"usage":"# + usage + "}"))
        let result = try await model.generate(hello)
        #expect(result.usage?.inputTokensNoCache == 80 && result.usage?.inputTokensCacheRead == 20)
        #expect(result.usage?.outputTextTokens == 40 && result.usage?.outputReasoningTokens == 10)
        #expect(result.usage?.rawValue == (try decodeJSONBody(Data(usage.utf8))))
    }

    @Test func continuesValidatingKnownUsageFieldTypes() async throws {
        let (model, _) = try makeModel("kimi-k3", jsonResponse(#"{"id":"x","created":1785880000,"model":"kimi-k3","choices":[{"message":{"role":"assistant","content":"Hello"},"finish_reason":"stop"}],"usage":{"prompt_tokens":"100","completion_tokens":50,"total_tokens":150}}"#))
        await #expect(throws: AIError.self) { _ = try await model.generate(hello) }
    }

    @Test func sendsVideoDataPartsAsVideoURLDataURIs() async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        _ = try await model.generate(LanguageModelRequest(messages: [AIMessage(role: .user, content: [.text("Describe this video"), .data(mimeType: "video/mp4", data: Data([0, 1, 2, 3]))])]))
        #expect(try await sentBody(transport)["messages"]?[0]?["content"] == [
            ["type": "text", "text": "Describe this video"],
            ["type": "video_url", "video_url": ["url": "data:video/mp4;base64,AAECAw=="]]
        ])
    }

    @Test func sendsMsImageURLReferences() async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        #expect(isURLSupported(mediaType: "image/*", url: "ms://file-image", supportedURLs: model.supportedURLs))
        #expect(isURLSupported(mediaType: "video/*", url: "ms://file-video", supportedURLs: model.supportedURLs))
        #expect(!isURLSupported(mediaType: "image/*", url: "https://example.com/a.png", supportedURLs: model.supportedURLs))
        _ = try await model.generate(LanguageModelRequest(messages: [AIMessage(role: .user, content: [.imageURL("ms://file-image")])]))
        #expect(try await sentBody(transport)["messages"]?[0]?["content"] == [["type": "image_url", "image_url": ["url": "ms://file-image"]]])
    }

    @Test func sendsTextDataAndMoonshotProviderReferencesAsNativeContentParts() async throws {
        let (model, transport) = try makeModel("kimi-k2.6", jsonResponse(Fixture.text))
        _ = try await model.generate(LanguageModelRequest(messages: [AIMessage(role: .user, content: [
            .data(mimeType: "text/plain", data: Data("inline document text".utf8)),
            .providerReference(mimeType: "image/png", reference: ["moonshotai": "ms://image-file-123"]),
            .providerReference(mimeType: "video/mp4", reference: ["moonshotai": "ms://video-file-123"])
        ])]))
        #expect(try await sentBody(transport)["messages"]?[0]?["content"] == [
            ["type": "text", "text": "inline document text"],
            ["type": "image_url", "image_url": ["url": "ms://image-file-123"]],
            ["type": "video_url", "video_url": ["url": "ms://video-file-123"]]
        ])
    }

    @Test func rejectsProviderReferencesWithoutMsURL() async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        await #expect(throws: AIError.self) {
            _ = try await model.generate(LanguageModelRequest(messages: [AIMessage(role: .user, content: [.providerReference(mimeType: "image/png", reference: ["moonshotai": "file-123"])])]))
        }
        #expect(await transport.requests().isEmpty)
    }
}

@Suite("Moonshot upstream thinking options")
struct MoonshotUpstreamThinkingTests {
    @Test func omitsUnsupportedBudgetTokensAndWarns() async throws {
        let (model, transport) = try makeModel("kimi-k2.6", jsonResponse(Fixture.reasoning))
        let result = try await model.generate(withOptions(["thinking": ["type": "enabled", "budgetTokens": 2048]]))
        #expect(try await sentBody(transport)["thinking"] == ["type": "enabled"])
        #expect(result.warnings == [AIWarning(type: "deprecated", setting: "providerOptions.moonshotai.thinking.budgetTokens", message: "Moonshot Chat Completions does not support budget_tokens. Remove budgetTokens; the option has been omitted.")])
    }

    @Test func mapsReasoningHistoryPreservedToThinkingKeepAll() async throws {
        let (model, transport) = try makeModel("kimi-k2.6", jsonResponse(Fixture.reasoning))
        _ = try await model.generate(withOptions(["thinking": ["type": "enabled"], "reasoningHistory": "preserved"]))
        let body = try await sentBody(transport)
        #expect(body["thinking"] == ["type": "enabled", "keep": "all"])
        #expect(body["reasoning_history"] == nil)
    }

    @Test func doesNotSendReasoningHistoryForOtherValues() async throws {
        let (model, transport) = try makeModel("kimi-k2.6", jsonResponse(Fixture.reasoning))
        _ = try await model.generate(withOptions(["reasoningHistory": "interleaved"]))
        let body = try await sentBody(transport)
        #expect(body["reasoning_history"] == nil && body["thinking"] == nil)
    }

    @Test(arguments: [("low", nil, "low"), ("xhigh", nil, "high"), ("max", nil, "max"), (nil, "max", "max"), ("low", "high", "high")] as [(String?, String?, String)])
    func mapsReasoningAndExplicitEffort(_ reasoning: String?, _ explicit: String?, _ expected: String) async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.reasoning))
        _ = try await model.generate(withOptions(explicit.map { ["reasoningEffort": .string($0)] } ?? [:], reasoning: reasoning))
        #expect(try await sentBody(transport)["reasoning_effort"] == .string(expected))
    }

    @Test func mapsReasoningNoneToLowestEffortWithWarning() async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.reasoning))
        let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], reasoning: "none"))
        #expect(try await sentBody(transport)["reasoning_effort"] == "low")
        #expect(result.warnings == [AIWarning(type: "compatibility", feature: "reasoning", message: #"reasoning "none" is not directly supported by this model. mapped to effort "low"."#)])
    }

    @Test func mapsReasoningNoneToDisabledThinkingForUnknownModels() async throws {
        let (model, transport) = try makeModel("custom-model", jsonResponse(Fixture.reasoning))
        let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], reasoning: "none"))
        let body = try await sentBody(transport)
        #expect(body["thinking"] == ["type": "disabled"] && body["reasoning_effort"] == nil)
        #expect(result.warnings.isEmpty)
    }

    @Test(arguments: ["kimi-k3", "kimi-k3.1-pro", "kimi-k3.1-pro-highspeed"])
    func omitsThinkingForK3(_ modelID: String) async throws {
        let (model, transport) = try makeModel(modelID, jsonResponse(Fixture.reasoning))
        let result = try await model.generate(withOptions(["thinking": ["type": "disabled"], "reasoningHistory": "preserved"]))
        #expect(try await sentBody(transport)["thinking"] == nil)
        #expect(result.warnings == [AIWarning(type: "unsupported", feature: "thinking", message: "Kimi K3 always reasons and does not accept the thinking field. The option has been omitted.")])
    }

    @Test(arguments: ["kimi-k2.7-code", "kimi-k2.7-code-highspeed"])
    func doesNotDisableThinkingForK27(_ modelID: String) async throws {
        let (model, transport) = try makeModel(modelID, jsonResponse(Fixture.reasoning))
        let result = try await model.generate(withOptions(["thinking": ["type": "disabled"]]))
        #expect(try await sentBody(transport)["thinking"] == nil)
        #expect(result.warnings == [AIWarning(type: "unsupported", feature: "thinking.type \"disabled\"", message: "Kimi K2.7 thinking cannot be disabled.")])
    }

    @Test func reliesOnK27PreservedThinkingDefaults() async throws {
        let (model, transport) = try makeModel("kimi-k2.7-code", jsonResponse(Fixture.reasoning))
        let result = try await model.generate(withOptions(["reasoningHistory": "preserved"]))
        #expect(try await sentBody(transport)["thinking"] == nil)
        #expect(result.warnings.isEmpty)
    }

    @Test(arguments: ["kimi-k2.5", "kimi-k2.6"])
    func mapsGenericReasoningToThinkingForK2(_ modelID: String) async throws {
        for (reasoning, type) in [("low", "enabled"), ("none", "disabled")] {
            let (model, transport) = try makeModel(modelID, jsonResponse(Fixture.reasoning))
            _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], reasoning: reasoning))
            #expect(try await sentBody(transport)["thinking"] == ["type": .string(type)])
        }
    }

    @Test func omitsReasoningEffortForK2ModelsAndWarns() async throws {
        let (model, transport) = try makeModel("kimi-k2.6", jsonResponse(Fixture.reasoning))
        let result = try await model.generate(withOptions(["reasoningEffort": "high"]))
        #expect(try await sentBody(transport)["reasoning_effort"] == nil)
        #expect(result.warnings == [AIWarning(type: "unsupported", feature: "reasoningEffort", message: #"reasoningEffort is only supported by Kimi K3 and has been omitted for model "kimi-k2.6"."#)])
    }

    @Test func omitsThinkingAndReasoningForMoonshotV1() async throws {
        let (model, transport) = try makeModel("moonshot-v1-8k", jsonResponse(Fixture.reasoning))
        let result = try await model.generate(withOptions(["reasoningEffort": "high", "thinking": ["type": "enabled"], "reasoningHistory": "preserved"], reasoning: "high"))
        let body = try await sentBody(transport)
        #expect(body["reasoning_effort"] == nil && body["thinking"] == nil)
        #expect(result.warnings == [
            AIWarning(type: "unsupported", feature: "reasoningEffort", message: #"reasoningEffort is only supported by Kimi K3 and has been omitted for model "moonshot-v1-8k"."#),
            AIWarning(type: "unsupported", feature: "thinking", message: #"thinking is not supported by model "moonshot-v1-8k" and has been omitted."#),
            AIWarning(type: "unsupported", feature: "reasoning", message: #"reasoning is not supported by model "moonshot-v1-8k"."#),
            AIWarning(type: "unsupported", feature: #"reasoningHistory 'preserved' is not supported by model "moonshot-v1-8k""#)
        ])
    }

    @Test func extractsReasoningContentAndRemapsUsage() async throws {
        let (model, _) = try makeModel("kimi-k2.6", jsonResponse(Fixture.reasoning))
        let result = try await model.generate(hello)
        #expect(result.content == [.reasoning("Let me count the letters carefully."), .text("There are three.")])
        #expect(result.usage?.inputTokens == 20 && result.usage?.inputTokensNoCache == 10 && result.usage?.inputTokensCacheRead == 10)
        #expect(result.usage?.outputTokens == 30 && result.usage?.outputTextTokens == 8 && result.usage?.outputReasoningTokens == 22)
    }
}

@Suite("Moonshot upstream structured outputs, partial mode and tools")
struct MoonshotUpstreamStructuredTests {
    @Test func normalizesJSONSchemasAndEnablesStrictValidationByDefault() async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], responseFormat: .json(schema: [
            "$schema": "http://json-schema.org/draft-07/schema#",
            "type": "object",
            "properties": ["ingredients": ["type": "array", "items": [["type": "string"], ["type": "number"]]]]
        ], name: "recipe", description: "A recipe response.")))
        #expect(try await sentBody(transport)["response_format"] == [
            "type": "json_schema",
            "json_schema": ["name": "recipe", "strict": true, "schema": ["type": "object", "properties": ["ingredients": ["type": "array", "prefixItems": [["type": "string"], ["type": "number"]]]]]]
        ])
    }

    @Test func allowsStrictJSONSchemaValidationToBeDisabled() async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], responseFormat: .json(schema: ["type": "object", "properties": ["name": ["type": "string"]]]), providerOptions: ["moonshotai": ["strictJsonSchema": false]]))
        #expect(try await sentBody(transport)["response_format"] == ["type": "json_schema", "json_schema": ["name": "response", "strict": false, "schema": ["type": "object", "properties": ["name": ["type": "string"]]]]])
    }

    @Test func fallsBackToJSONObjectWithoutSchema() async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], responseFormat: .json(schema: nil)))
        #expect(try await sentBody(transport)["response_format"] == ["type": "json_object"])
    }

    @Test(arguments: ["moonshot-v1-8k", "moonshot-v1-auto", "moonshot-v1-128k-vision-preview", "custom-model-id", "moonshot-v2", "kimi-next"])
    func usesJSONSchemaForEveryModel(_ modelID: String) async throws {
        let (model, transport) = try makeModel(modelID, jsonResponse(Fixture.text))
        let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], responseFormat: .json(schema: ["type": "object", "properties": .object([:])], name: "response")))
        #expect(try await sentBody(transport)["response_format"] == ["type": "json_schema", "json_schema": ["name": "response", "schema": ["type": "object", "properties": .object([:])], "strict": true]])
        #expect(result.warnings.isEmpty)
    }

    @Test(arguments: [false, true])
    func sendsPartialTrueOnFinalAssistantMessage(_ streaming: Bool) async throws {
        let (model, transport) = try makeModel("kimi-k3", streaming ? chunks(Fixture.streamChunks) : jsonResponse(Fixture.text))
        let request = LanguageModelRequest(messages: [
            .user("Continue this prefix."),
            AIMessage(role: .assistant, content: [.text("The sky is")], providerMetadata: ["moonshotai": ["name": "writer", "partial": true]])
        ])
        if streaming { _ = try await collect(model, request) } else { _ = try await model.generate(request) }
        #expect(try await sentBody(transport)["messages"] == [["role": "user", "content": "Continue this prefix."], ["role": "assistant", "content": "The sky is", "name": "writer", "partial": true]])
    }

    @Test func rejectsPartialModeWithJSONObjectResponseFormatBeforeTheAPICall() async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        await #expect(throws: AIError.invalidArgument(argument: "prompt", message: "Moonshot AI Partial Mode cannot be combined with JSON object response format.")) {
            _ = try await model.generate(LanguageModelRequest(messages: [AIMessage(role: .assistant, content: [.text("{")], providerMetadata: ["moonshotai": ["partial": true]])], responseFormat: .json(schema: nil)))
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test func allowsPartialModeWithJSONSchemaResponseFormat() async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        _ = try await model.generate(LanguageModelRequest(messages: [AIMessage(role: .assistant, content: [.text("{")], providerMetadata: ["moonshotai": ["partial": true]])], responseFormat: .json(schema: ["type": "object", "properties": ["answer": ["type": "string"]]], name: "result")))
        let body = try await sentBody(transport)
        #expect(body["messages"]?[0]?["partial"] == true)
        #expect(body["response_format"]?["type"] == "json_schema")
    }

    @Test(arguments: ["kimi-k2.6", "kimi-k2.7-code", "kimi-k2.7-code-highspeed"])
    func omitsRequiredToolChoiceAndWarns(_ modelID: String) async throws {
        let (model, transport) = try makeModel(modelID, jsonResponse(Fixture.toolCall))
        let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], tools: ["get_weather": ["type": "object", "properties": .object([:]), "description": "Get the weather"]], toolChoice: ["type": "required"]))
        #expect(try await sentBody(transport)["tool_choice"] == nil)
        #expect(result.warnings == [AIWarning(type: "unsupported", feature: "tool choice \"required\" for model \"\(modelID)\"", message: "Moonshot AI rejects required tool choice for this model. The setting has been omitted; use \"auto\" or select a specific tool instead.")])
    }

    @Test(arguments: ["kimi-k3", "custom-kimi-model"])
    func preservesRequiredToolChoice(_ modelID: String) async throws {
        let (model, transport) = try makeModel(modelID, jsonResponse(Fixture.toolCall))
        let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], tools: ["get_weather": ["type": "object", "properties": .object([:]), "description": "Get the weather"]], toolChoice: ["type": "required"]))
        let body = try await sentBody(transport)
        #expect(body["tool_choice"] == "required")
        #expect(body["tools"] == [["type": "function", "function": ["name": "get_weather", "description": "Get the weather", "parameters": ["type": "object", "properties": .object([:])]]]])
        #expect(result.warnings.isEmpty)
    }

    @Test func sendsRootUnionsOfObjectsWithTypeObjectOnTheWire() async throws {
        let city: JSONValue = ["type": "object", "properties": ["city": ["type": "string"]], "required": ["city"]]
        let coords: JSONValue = ["properties": ["lat": ["type": "number"]], "required": ["lat"]]
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.toolCall))
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], responseFormat: .json(schema: ["anyOf": [city, coords]], name: "location"), tools: ["untyped": ["anyOf": [city, coords]], "typed": ["type": "object", "anyOf": [city, coords]]]))
        let body = try await sentBody(transport)
        for tool in body["tools"]?.arrayValue ?? [] {
            #expect(tool["function"]?["parameters"] == ["type": "object", "anyOf": [city, coords]])
        }
        #expect(body["response_format"]?["json_schema"]?["schema"] == ["type": "object", "anyOf": [city, coords]])
    }

    @Test func extractsToolCallsAndFinishReason() async throws {
        let (model, _) = try makeModel("kimi-k3", jsonResponse(Fixture.toolCall))
        let result = try await model.generate(hello)
        #expect(result.content.count == 1)
        #expect(result.toolCalls.map { [$0.id, $0.name, $0.arguments] } == [["call_abc123", "get_weather", #"{"city":"Paris"}"#]])
        #expect(result.finishReason == "tool-calls")
        #expect(result.providerMetadata == ["moonshotai": ["responseObject": "chat.completion", "choiceIndex": 0, "messageRole": "assistant", "toolCallTypes": ["function"]]])
    }

    @Test func warnsForUnsupportedTopKAndSeed() async throws {
        let (model, _) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], topK: 5, seed: 42))
        #expect(result.warnings == [AIWarning(type: "unsupported", feature: "topK"), AIWarning(type: "unsupported", feature: "seed")])
    }

    @Test(arguments: [false, true])
    func warnsWhenAMessageNameIsSetOnAToolMessage(_ streaming: Bool) async throws {
        let (model, transport) = try makeModel("kimi-k3", streaming ? chunks(Fixture.streamChunks) : jsonResponse(Fixture.text))
        let request = LanguageModelRequest(messages: [AIMessage(role: .tool, content: [.toolResult(AIToolResult(toolCallID: "call-1", toolName: "weather", result: .null, modelOutput: ["type": "text", "value": "sunny"]))], providerMetadata: ["moonshotai": ["name": "weather_tool"]])])
        let warnings: [AIWarning]
        if streaming {
            let parts = try await collect(model, request)
            guard case let .streamStart(value) = parts.first else { Issue.record("missing stream start"); return }
            warnings = value
        } else {
            warnings = try await model.generate(request).warnings
        }
        #expect(warnings == [AIWarning(type: "unsupported", feature: "message name on tool messages")])
        #expect(try await sentBody(transport)["messages"]?[0]?["name"] == nil)
    }
}

@Suite("Moonshot upstream provider options and caching")
struct MoonshotUpstreamProviderOptionTests {
    @Test(arguments: [JSONValue.string("Hello, world!"), [["type": "text", "text": "Hello"], ["type": "text", "text": ", world!"]]])
    func forwardsPredictedContentUnchanged(_ content: JSONValue) async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        _ = try await model.generate(withOptions(["prediction": ["type": "content", "content": content]]))
        #expect(try await sentBody(transport)["prediction"] == ["type": "content", "content": content])
    }

    @Test func omitsPredictionWhenNotConfigured() async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        _ = try await model.generate(hello)
        #expect(try await sentBody(transport)["prediction"] == nil)
    }

    @Test(arguments: [
        ["type": "text", "content": "Hello, world!"],
        ["type": "content", "content": [["type": "image", "text": "Hello, world!"]]],
        ["type": "content", "content": 123]
    ] as [JSONValue])
    func rejectsInvalidPredictedContentBeforeMakingARequest(_ prediction: JSONValue) async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        await #expect(throws: AIError.invalidArgument(argument: "providerOptions", message: "invalid moonshotai provider options")) {
            _ = try await model.generate(withOptions(["prediction": prediction]))
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test func forwardsPromptCacheKeyAndSafetyIdentifier() async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        _ = try await model.generate(withOptions(["promptCacheKey": "session-42", "safetyIdentifier": "user-hash-7"]))
        let body = try await sentBody(transport)
        #expect(body["prompt_cache_key"] == "session-42" && body["safety_identifier"] == "user-hash-7")
    }

    @Test func omitsTheTTLSplitWithoutTheUsageHeaders() async throws {
        let (model, _) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        #expect(try await model.generate(hello).providerMetadata["moonshotai"]?["cacheWriteTokens"] == nil)
    }

    @Test func sendsNormalizedDynamicToolsInAK3SystemMessage() async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.toolCall))
        _ = try await model.generate(LanguageModelRequest(messages: [
            .user("Calculate."),
            AIMessage(role: .system, content: [], providerMetadata: ["moonshotai": ["tools": [[
                "type": "function", "name": "calculator", "description": "Evaluate an expression",
                "inputSchema": ["type": "object", "properties": ["values": ["type": "array", "items": [["type": "number"], ["type": "number"]]]]]
            ]]]])
        ]))
        #expect(try await sentBody(transport)["messages"]?[1] == ["role": "system", "tools": [[
            "type": "function",
            "function": ["name": "calculator", "description": "Evaluate an expression", "parameters": ["type": "object", "properties": ["values": ["type": "array", "prefixItems": [["type": "number"], ["type": "number"]]]]]]
        ]]])
    }

    @Test func omitsDynamicMessagesAndWarnsForNonK3OfficialModels() async throws {
        let (model, transport) = try makeModel("kimi-k2.6", jsonResponse(Fixture.toolCall))
        let result = try await model.generate(LanguageModelRequest(messages: [
            AIMessage(role: .system, content: [], providerMetadata: ["moonshotai": ["tools": [["type": "function", "name": "calculator", "inputSchema": ["type": "object", "properties": .object([:])]]]]])
        ]))
        #expect(try await sentBody(transport)["messages"] == .array([]))
        #expect(result.warnings.contains(AIWarning(type: "unsupported", feature: "dynamic tool loading for model \"kimi-k2.6\"", message: "Moonshot documents dynamic tool loading only for Kimi K3. The dynamic system message has been omitted.")))
    }

    @Test(arguments: [false, true])
    func preservesDynamicMessagesForUnknownCustomModels(_ streaming: Bool) async throws {
        let (model, transport) = try makeModel(streaming ? "kimi-k3" : "custom-model", streaming ? chunks(Fixture.streamChunks) : jsonResponse(Fixture.toolCall))
        let request = LanguageModelRequest(messages: [
            AIMessage(role: .system, content: [], providerMetadata: ["moonshotai": ["tools": [["type": "function", "name": "calculator", "inputSchema": ["type": "object", "properties": .object([:])]]]]])
        ])
        if streaming { _ = try await collect(model, request) } else { _ = try await model.generate(request) }
        let message = try await sentBody(transport)["messages"]?[0]
        #expect(message?["role"] == "system")
        #expect(message?["tools"]?[0]?["function"]?["name"] == "calculator")
    }

    @Test func sendsLogprobsProviderOptions() async throws {
        for (options, logprobs, top) in [(["logprobs": true, "topLogprobs": 20] as JSONValue, JSONValue.bool(true), JSONValue.number(20)), (["topLogprobs": 0], true, 0)] {
            let (model, transport) = try makeModel("moonshot-v1-8k", jsonResponse(Fixture.logprobs))
            _ = try await model.generate(withOptions(options))
            let body = try await sentBody(transport)
            #expect(body["logprobs"] == logprobs && body["top_logprobs"] == top)
        }
    }

    @Test(arguments: [-1, 1.5, 21] as [Double])
    func rejectsInvalidTopLogprobs(_ value: Double) async throws {
        let (model, transport) = try makeModel("moonshot-v1-8k", jsonResponse(Fixture.logprobs))
        await #expect(throws: AIError.invalidArgument(argument: "providerOptions", message: "invalid moonshotai provider options")) {
            _ = try await model.generate(withOptions(["topLogprobs": .number(value)]))
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test func exposesLogprobsInProviderMetadataWithoutChangingText() async throws {
        let (model, _) = try makeModel("moonshot-v1-8k", jsonResponse(Fixture.logprobs))
        let result = try await model.generate(withOptions(["logprobs": true]))
        #expect(result.content == [.text("OK!")])
        let expected = try decodeJSONBody(Data(Fixture.logprobs.utf8))["choices"]?[0]?["logprobs"]
        #expect(result.providerMetadata["moonshotai"]?["logprobs"] == expected)
    }

    @Test func parsesANullLogprobsResponse() async throws {
        let (model, _) = try makeModel("moonshot-v1-8k", jsonResponse(Fixture.text.replacingOccurrences(of: #""finish_reason":"stop""#, with: #""finish_reason":"stop","logprobs":null"#)))
        #expect(try await model.generate(hello).providerMetadata == ["moonshotai": ["responseObject": "chat.completion", "choiceIndex": 0, "messageRole": "assistant"]])
    }

    @Test func rejectsUnsupportedMediaBeforeSendingARequest() async throws {
        let (model, transport) = try makeModel("kimi-k3", jsonResponse(Fixture.text))
        await #expect(throws: AIError.self) {
            _ = try await model.generate(LanguageModelRequest(messages: [AIMessage(role: .user, content: [.data(mimeType: "image/svg+xml", data: Data("<svg></svg>".utf8))])]))
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test(arguments: [Fixture.error, #"{"error":{"message":"Invalid request with nullable code","type":"invalid_request_error","code":null}}"#, #"{"error":{"message":"Invalid request"}}"#])
    func preservesTheMoonshotErrorEnvelope(_ data: String) async throws {
        let (model, _) = try makeModel("kimi-k3", AIHTTPResponse(statusCode: 400, headers: [:], body: Data(data.utf8)))
        let message = try decodeJSONBody(Data(data.utf8))["error"]?["message"]?.stringValue ?? ""
        await #expect(throws: AIError.apiCall(provider: "moonshotai.chat", statusCode: 400, body: message)) {
            _ = try await model.generate(hello)
        }
    }
}

@Suite("Moonshot upstream doStream")
struct MoonshotUpstreamStreamTests {
    @Test(arguments: [("missing", "interrupted"), ("unknown_reason", "other"), ("invalid-json", "error")])
    func handlesStreamEndings(_ ending: String, _ expected: String) async throws {
        var lines = [#"{"id":"response-1","object":"chat.completion.chunk","created":1,"model":"test-model","choices":[{"index":0,"delta":{"content":"Partial answer"},"finish_reason":null}]}"#]
        if ending == "invalid-json" { lines.append("{invalid-json}") }
        if ending == "unknown_reason" { lines.append(#"{"choices":[{"index":0,"delta":{},"finish_reason":"unknown_reason"}]}"#) }
        let (model, _) = try makeModel("kimi-k2-0905-preview", chunks(lines))
        let parts = try await collect(model, hello)
        #expect(parts.contains { if case .textDeltaPart(_, "Partial answer", _) = $0 { true } else { false } })
        #expect(parts.filter { if case .error = $0 { true } else { false } }.count == (ending == "invalid-json" ? 1 : 0))
        let finishes = parts.compactMap { part -> String? in if case let .finishMetadata(reason, _, _) = part { reason } else { nil } }
        #expect(finishes == [expected])
    }

    @Test func preservesAProviderErrorEnvelopeInStreamErrors() async throws {
        let (model, _) = try makeModel("kimi-k3", chunks([#"{"error":{"message":"Internal server error","type":"server_error","code":"upstream_failure"}}"#]))
        let error = try await collect(model, hello).compactMap(\.streamProviderError).first
        #expect(error?.message == "Internal server error")
        #expect(error?.type == "server_error")
        #expect(error?.code == "upstream_failure")
        #expect(error?.statusCode == 500)
        #expect(error?.isRetryable == true)
        #expect(error?.data == ["error": ["message": "Internal server error", "type": "server_error", "code": "upstream_failure"]])
    }

    @Test func streamsReasoningAndTextDeltasWithUsage() async throws {
        let (model, transport) = try makeModel("kimi-k3", chunks(Fixture.streamChunks))
        let parts = try await collect(model, hello)
        guard case let .streamStart(warnings) = parts.first else { Issue.record("missing stream start"); return }
        #expect(warnings.isEmpty)
        let lifecycle = parts.compactMap { part -> String? in
            switch part {
            case let .reasoningStart(id, _): "reasoning-start:\(id)"
            case let .reasoningDeltaPart(id, delta, _): "reasoning-delta:\(id):\(delta)"
            case let .reasoningEnd(id, _): "reasoning-end:\(id)"
            case let .textStart(id, _): "text-start:\(id)"
            case let .textDeltaPart(id, delta, _): "text-delta:\(id):\(delta)"
            case let .textEnd(id, _): "text-end:\(id)"
            default: nil
            }
        }
        #expect(lifecycle == ["reasoning-start:reasoning-0", "reasoning-delta:reasoning-0:Thinking ", "reasoning-delta:reasoning-0:aloud. ", "text-start:txt-0", "reasoning-end:reasoning-0", "text-delta:txt-0:Hello", "text-delta:txt-0:!", "text-end:txt-0"])
        guard case let .finishMetadata(reason, usage, _) = parts.last else { Issue.record("missing finish"); return }
        #expect(reason == "stop" && usage?.inputTokens == 9 && usage?.outputTokens == 12 && usage?.outputReasoningTokens == 7)
        let body = try await sentBody(transport)
        #expect(body["stream"] == true && body["stream_options"] == ["include_usage": true])
    }

    @Test func keepsReasoningActiveWhenDeltasIncludeEmptyToolCalls() async throws {
        let (model, _) = try makeModel("kimi-k2-thinking", chunks([
            #"{"id":"chatcmpl-test","object":"chat.completion.chunk","created":1,"model":"test-model","choices":[{"index":0,"delta":{"role":"assistant","content":"","reasoning_content":"Think ","tool_calls":[]},"finish_reason":null}]}"#,
            #"{"id":"chatcmpl-test","object":"chat.completion.chunk","created":1,"model":"test-model","choices":[{"index":0,"delta":{"content":"","reasoning_content":"more...","tool_calls":[]},"finish_reason":null}]}"#,
            #"{"id":"chatcmpl-test","object":"chat.completion.chunk","created":1,"model":"test-model","choices":[{"index":0,"delta":{"content":"Hello","reasoning_content":"","tool_calls":[]},"finish_reason":"stop"}]}"#
        ]))
        let reasoning = try await collect(model, hello).compactMap { part -> String? in
            switch part {
            case .reasoningStart: "start"
            case let .reasoningDeltaPart(_, delta, _): delta
            case .reasoningEnd: "end"
            default: nil
            }
        }
        #expect(reasoning == ["start", "Think ", "more...", "end"])
    }

    @Test(arguments: [false, true])
    func preservesExtraFieldsInStreamedRawUsage(_ separateUsageChunk: Bool) async throws {
        let usage = #"{"prompt_tokens":100,"completion_tokens":50,"total_tokens":150,"cached_tokens":20,"provider_usage_id":"usage-123","prompt_tokens_details":{"cached_tokens":20,"cache_type":"ephemeral"},"completion_tokens_details":{"reasoning_tokens":10,"billable_tokens":42}}"#
        var lines = [separateUsageChunk
            ? #"{"id":"chatcmpl-raw-usage","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#
            : #"{"id":"chatcmpl-raw-usage","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop","usage":"# + usage + "}]}"]
        if separateUsageChunk { lines.append(#"{"id":"chatcmpl-raw-usage","object":"chat.completion.chunk","choices":[],"usage":"# + usage + "}") }
        let (model, _) = try makeModel("kimi-k3", chunks(lines))
        guard case let .finishMetadata(_, finish, _) = try await collect(model, hello).last else { Issue.record("missing finish"); return }
        #expect(finish?.inputTokens == 100 && finish?.inputTokensNoCache == 80 && finish?.inputTokensCacheRead == 20)
        #expect(finish?.outputTokens == 50 && finish?.outputTextTokens == 40 && finish?.outputReasoningTokens == 10)
        #expect(finish?.rawValue == (try decodeJSONBody(Data(usage.utf8))))
    }

    @Test(arguments: [(Fixture.indexlessToolCallChunks, [["weather_0", "weather", #"{"location":"San Francisco"}"#], ["time_1", "time", #"{"zone":"UTC"}"#]]), (Fixture.explicitIndexChunks, [["weather_0", "weather", #"{"location": "San Francisco"}"#]])])
    func assemblesStreamedToolCalls(_ lines: [String], _ expected: [[String]]) async throws {
        let (model, _) = try makeModel("kimi-k3", chunks(lines))
        let parts = try await collect(model, hello)
        #expect(!parts.contains { if case .error = $0 { true } else { false } })
        #expect(parts.compactMap { part -> [String]? in if case let .toolCall(call) = part { [call.id, call.name, call.arguments] } else { nil } } == expected)
    }

    @Test(arguments: [(Fixture.choiceUsageChunks, 12, 5), (Fixture.usagePrecedenceChunks, 99, 33)])
    func selectsStreamUsage(_ lines: [String], _ input: Int, _ output: Int) async throws {
        let (model, _) = try makeModel("kimi-k3", chunks(lines))
        guard case let .finishMetadata(_, usage, _) = try await collect(model, hello).last else { Issue.record("missing finish"); return }
        #expect(usage?.inputTokens == input && usage?.outputTokens == output)
    }

    @Test func rejectsMalformedToolCallIndices() async throws {
        let (model, _) = try makeModel("kimi-k3", chunks(Fixture.malformedIndexChunks))
        #expect(try await collect(model, hello).contains { if case .error = $0 { true } else { false } })
    }

    @Test func collectsStreamedLogprobsInFinishProviderMetadata() async throws {
        let (model, transport) = try makeModel("moonshot-v1-8k", chunks(Fixture.logprobsChunks))
        let parts = try await collect(model, withOptions(["topLogprobs": 1]))
        let body = try await sentBody(transport)
        #expect(body["logprobs"] == true && body["top_logprobs"] == 1)
        #expect(parts.compactMap { part -> String? in if case let .textDeltaPart(_, delta, _) = part { delta } else { nil } }.joined() == "OK!")
        guard case let .finishMetadata(_, _, metadata) = parts.last else { Issue.record("missing finish"); return }
        let content = Fixture.logprobsChunks.compactMap { try? decodeJSONBody(Data($0.utf8))["choices"]?[0]?["logprobs"]?["content"]?.arrayValue }.flatMap { $0 }
        #expect(metadata == ["moonshotai": ["choiceIndex": 0, "logprobs": ["content": .array(content)], "messageRole": "assistant", "responseObject": "chat.completion.chunk"]])
    }

    @Test func reportsCacheWritesAndTheTTLSplitOnStream() async throws {
        let usage = #"{"prompt_tokens":22459,"completion_tokens":44,"total_tokens":22503,"prompt_tokens_details":{"cached_tokens":1024,"cache_write_tokens":21248}}"#
        let (model, _) = try makeModel("kimi-k3.1-pro", chunks([#"{"id":"chatcmpl-cache","created":1785880003,"model":"kimi-k3.1-pro","choices":[{"index":0,"delta":{"content":"OK"},"finish_reason":"stop"}],"usage":"# + usage + "}"], headers: ["msh-usage-cache-write-tokens-5m": "0", "msh-usage-cache-write-tokens-1h": "21248"]))
        guard case let .finishMetadata(_, finish, metadata) = try await collect(model, hello).last else { Issue.record("missing finish"); return }
        #expect(finish?.inputTokensCacheWrite == 21248 && finish?.inputTokensNoCache == 187)
        #expect(metadata["moonshotai"]?["cacheWriteTokens"] == ["ttl5m": 0, "ttl1h": 21248])
    }

    @Test func preservesResponseMetadataAndRawToolCallChunks() async throws {
        let (model, _) = try makeModel("kimi-k3", chunks(Fixture.toolCallChunks))
        let parts = try await collect(model, LanguageModelRequest(messages: [.user("Hello")], includeRawChunks: true))
        let raw = parts.compactMap { part -> JSONValue? in if case let .raw(value) = part { value } else { nil } }
        #expect(raw == Fixture.toolCallChunks.compactMap { try? decodeJSONBody(Data($0.utf8)) })
        #expect(parts.compactMap { part -> [String]? in if case let .toolCall(call) = part { [call.id, call.name, call.arguments] } else { nil } } == [["call_abc123", "get_weather", #"{"city":"Paris"}"#]])
        guard case let .finishMetadata(_, _, metadata) = parts.last else { Issue.record("missing finish"); return }
        #expect(metadata == ["moonshotai": ["responseObject": "chat.completion.chunk", "choiceIndex": 0, "messageRole": "assistant", "toolCallTypes": ["function"]]])
        let responseMetadata = parts.compactMap { part -> AIResponseMetadata? in if case let .responseMetadata(value) = part { value } else { nil } }.first
        #expect(responseMetadata?.id == "chatcmpl-stream-tool" && responseMetadata?.modelID == "kimi-k3")
    }

    @Test(arguments: [true, false])
    func toleratesNullishStreamedResponseMetadataFields(_ useNull: Bool) async throws {
        let line = useNull
            ? #"{"id":"chatcmpl-stream","object":null,"choices":[{"index":null,"delta":{"role":null,"content":"Hello"},"finish_reason":"stop"}]}"#
            : #"{"id":"chatcmpl-stream","choices":[{"delta":{"content":"Hello"},"finish_reason":"stop"}]}"#
        let (model, _) = try makeModel("kimi-k3", chunks([line]))
        guard case let .finishMetadata(_, _, metadata) = try await collect(model, hello).last else { Issue.record("missing finish"); return }
        #expect(metadata == ["moonshotai": .object([:])])
    }

    @Test func sendsMaxOutputTokensAsMaxCompletionTokensWhenStreaming() async throws {
        let (model, transport) = try makeModel("kimi-k3", chunks(Fixture.streamChunks))
        _ = try await collect(model, LanguageModelRequest(messages: [.user("Hello")], maxOutputTokens: 17))
        let body = try await sentBody(transport)
        #expect(body["max_completion_tokens"] == 17 && body["max_tokens"] == nil)
    }
}

// Translated from convert-to-moonshotai-chat-messages.test.ts and convert-moonshotai-chat-usage.test.ts.
@Suite("Moonshot upstream message and usage conversion")
struct MoonshotUpstreamConversionTests {
    private func convert(_ messages: [AIMessage], modelID: String? = nil, responseFormat: JSONValue? = nil) throws -> (messages: [JSONValue], warnings: [AIWarning]) {
        var warnings: [AIWarning] = []
        let converted = try moonshotChatMessages(messages, modelID: modelID, responseFormat: responseFormat, warnings: &warnings)
        return (converted, warnings)
    }

    @Test func rejectsANonStringName() {
        #expect(throws: AIError.invalidArgument(argument: "providerOptions", message: "invalid moonshotai provider options")) {
            _ = try convert([AIMessage(role: .user, content: [.text("Hello")], providerMetadata: ["moonshotai": ["name": 123]])])
        }
    }

    @Test func rejectsPartialOnNonAssistantOrNonFinalMessages() {
        #expect(throws: AIError.invalidArgument(argument: "prompt", message: "Moonshot AI Partial Mode requires `partial: true` on an assistant message.")) {
            _ = try convert([AIMessage(role: .user, content: [.text("Hello")], providerMetadata: ["moonshotai": ["partial": true]])])
        }
        #expect(throws: AIError.invalidArgument(argument: "prompt", message: "Moonshot AI Partial Mode requires the partial assistant message to be the final message.")) {
            _ = try convert([AIMessage(role: .assistant, content: [.text("A")], providerMetadata: ["moonshotai": ["partial": true]]), .user("B")])
        }
    }

    @Test(arguments: ["image/jpeg", "image/png", "image/gif", "image/webp", "image/bmp", "image/heic", "image/heif", "video/mp4", "video/mpeg", "video/mov", "video/avi", "video/x-flv", "video/mpg", "video/webm", "video/wmv", "video/3gpp"])
    func convertsSupportedMediaTypesToDataURIs(_ mediaType: String) throws {
        let type = mediaType.hasPrefix("image/") ? "image_url" : "video_url"
        let result = try convert([AIMessage(role: .user, content: [.data(mimeType: mediaType, data: Data([0, 1, 2, 3]))])])
        let part: JSONValue = .object(["type": .string(type), type: ["url": .string("data:\(mediaType);base64,AAECAw==")]])
        #expect(result.messages == [["role": "user", "content": [part]]])
    }

    @Test(arguments: ["image/svg+xml", "image/tiff", "video/quicktime", "audio/mpeg", "application/pdf", "application/octet-stream"])
    func rejectsUnsupportedFileMediaTypes(_ mediaType: String) {
        #expect(throws: AIError.self) { _ = try convert([AIMessage(role: .user, content: [.data(mimeType: mediaType, data: Data([0, 1]))])]) }
    }

    @Test func rejectsForeignOrNonMsProviderReferences() {
        #expect(throws: AINoSuchProviderReferenceError.self) { _ = try convert([AIMessage(role: .user, content: [.providerReference(mimeType: "image/png", reference: ["openai": "ms://image-file-123"])])]) }
        #expect(throws: AIError.self) { _ = try convert([AIMessage(role: .user, content: [.providerReference(mimeType: "image/png", reference: ["moonshotai": "https://example.com/image.png"])])]) }
        #expect(throws: AIError.self) { _ = try convert([AIMessage(role: .user, content: [.providerReference(mimeType: "application/pdf", reference: ["moonshotai": "ms://document-file-123"])])]) }
    }

    @Test func preservesAnOrdinarySystemMessageWhenToolsIsEmpty() throws {
        let result = try convert([AIMessage(role: .system, content: [.text("You are Kimi.")], providerMetadata: ["moonshotai": ["tools": JSONValue.array([JSONValue]())]])], modelID: "kimi-k3")
        #expect(result.messages == [["role": "system", "content": "You are Kimi."]])
        #expect(result.warnings.isEmpty)
    }

    @Test func rejectsInvalidDynamicToolConfigurations() {
        #expect(throws: AIError.invalidArgument(argument: "providerOptions", message: "invalid moonshotai provider options")) {
            _ = try convert([AIMessage(role: .system, content: [], providerMetadata: ["moonshotai": ["tools": [["type": "function", "name": "calculator"]]]])], modelID: "kimi-k3")
        }
        let tools: JSONValue = [["type": "function", "name": "calculator", "inputSchema": ["type": "object", "properties": .object([:])]]]
        #expect(throws: AIError.invalidArgument(argument: "prompt", message: "A Moonshot dynamic-tool system message must use empty content because the API forbids content alongside tools.")) {
            _ = try convert([AIMessage(role: .system, content: [.text("Do not send this.")], providerMetadata: ["moonshotai": ["tools": tools]])], modelID: "kimi-k3")
        }
        #expect(throws: AIError.invalidArgument(argument: "prompt", message: "Moonshot dynamic tools must be configured on a system message.")) {
            _ = try convert([AIMessage(role: .user, content: [.text("Hi")], providerMetadata: ["moonshotai": ["tools": tools]])], modelID: "kimi-k3")
        }
    }

    @Test func convertsAssistantReasoningAndToolCalls() throws {
        let call = AIToolCall(id: "call-1", name: "weather", arguments: #"{"city":"Paris"}"#)
        let result = try convert([
            AIMessage(role: .assistant, content: [.reasoning("Think"), .toolCall(call)]),
            AIMessage(role: .assistant, content: [.text("Checking"), .toolCall(call)])
        ])
        let toolCalls: JSONValue = [["id": "call-1", "type": "function", "function": ["name": "weather", "arguments": #"{"city":"Paris"}"#]]]
        #expect(result.messages == [
            ["role": "assistant", "content": .null, "reasoning_content": "Think", "tool_calls": toolCalls],
            ["role": "assistant", "content": "Checking", "tool_calls": toolCalls]
        ])
    }

    @Test func clampsTextTokensAtZeroWhenReasoningExceedsCompletion() {
        let usage = moonshotConvertUsage(["prompt_tokens": 10, "completion_tokens": 5, "completion_tokens_details": ["reasoning_tokens": 8]])
        #expect(usage.outputTextTokens == 0 && usage.outputReasoningTokens == 8)
    }

    @Test func reportsCacheWriteTokensAndExcludesThemFromNoCache() {
        let usage = moonshotConvertUsage(["prompt_tokens": 100, "completion_tokens": 5, "prompt_tokens_details": ["cached_tokens": 20, "cache_write_tokens": 30]])
        #expect(usage.inputTokensNoCache == 50 && usage.inputTokensCacheRead == 20 && usage.inputTokensCacheWrite == 30)
    }

    @Test(arguments: [nil, JSONValue.null])
    func handlesMissingUsage(_ value: JSONValue?) {
        #expect(moonshotConvertUsage(value) == TokenUsage())
    }

    @Test func leavesLegacyDefinitionsUntouchedLikeUpstream() throws {
        let schema: JSONValue = ["type": "object", "definitions": ["Pair": ["type": "array", "items": [["type": "number"]]]], "$defs": ["Pair": ["type": "array", "items": [["type": "number"]]]]]
        let normalized = try moonshotNormalizeJSONSchemaForMFJS(schema)
        #expect(normalized["definitions"] == schema["definitions"])
        #expect(normalized["$defs"]?["Pair"] == ["type": "array", "prefixItems": [["type": "number"]]])
    }
}
