import Foundation
import Testing
import SwiftAIProvider
import SwiftAITransport
@testable import SwiftAIMoonshotAI

@Suite struct Weekly20261101MoonshotBehaviorTests {
    @Test(arguments: [("kimi-k3", "none", "low"), ("kimi-k3", "xhigh", "high"), ("kimi-k3.1-pro", "medium", "low"), ("custom-model", "medium", "low")], [false, true])
    func closestPortableEffortIsUsed(_ fixture: (String, String, String), _ streaming: Bool) async throws {
        let raw = #"{"choices":[{"message":{"content":"done"},"delta":{"content":"done"},"finish_reason":"stop"}]}"#
        let transport = RecordingTransport(response: streaming ? sseResponse("data: " + raw) : jsonResponse(raw))
        let model = try MoonshotAIProvider(configuration: .init(apiKey: "key", transport: transport)).languageModel(fixture.0)
        let request = LanguageModelRequest(messages: [.user("Hi")], reasoning: fixture.1)
        var warnings: [AIWarning] = []
        if streaming { for try await part in model.stream(request) { if case let .streamStart(value) = part { warnings = value } } }
        else { warnings = try await model.generate(request).warnings }
        let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
        #expect(body["reasoning_effort"] == .string(fixture.2))
        #expect(warnings.contains { $0.type == "compatibility" && $0.feature == "reasoning" })
    }

    @Test func noneUsesFamilyPolicyAndExplicitThinkingRetainsPriority() throws {
        var warnings: [AIWarning] = []
        let k27 = try moonshotChatBody(from: [:], request: .init(messages: [], reasoning: "none"), modelID: "kimi-k2.7-code", warnings: &warnings)
        #expect(k27["thinking"] == nil && k27["reasoning_effort"] == nil)
        #expect(warnings == [.init(type: "compatibility", feature: "reasoning", message: #"reasoning "none" is not supported by Kimi K2.7; thinking cannot be disabled. Using thinking enabled instead."#)])
        warnings = []
        let custom = try moonshotChatBody(from: [:], request: .init(messages: [], reasoning: "none"), modelID: "custom-model", warnings: &warnings)
        #expect(custom["thinking"] == ["type": "disabled"])
        #expect(warnings.isEmpty)
        let explicit = try moonshotChatBody(from: [:], request: .init(messages: [], reasoning: "none", providerOptions: ["moonshotai": ["thinking": ["type": "enabled"]]]), modelID: "custom-model", warnings: &warnings)
        #expect(explicit["thinking"] == ["type": "enabled"])
        #expect(warnings.isEmpty)
    }

    @Test func preservedK3HistoryDoesNotInventAThinkingRequest() throws {
        var warnings: [AIWarning] = []
        let body = try moonshotChatBody(from: [:], request: .init(messages: [], providerOptions: ["moonshotai": ["reasoningHistory": "preserved"]]), modelID: "kimi-k3", warnings: &warnings)
        #expect(body["thinking"] == nil)
        #expect(warnings.isEmpty)
    }
}
