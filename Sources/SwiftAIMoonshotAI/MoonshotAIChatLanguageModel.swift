import Foundation
import SwiftAIProvider
import SwiftAITransport
import SwiftAIProviderUtilities
import SwiftAIOpenAICompatible

/// Moonshot AI Chat Completions language model (upstream `MoonshotAIChatLanguageModel`).
public final class MoonshotAIChatLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: MoonshotAIModelConfiguration
    private let includeUsage: Bool

    /// Moonshot does not fetch external URLs; `ms://` Files API references are passed through.
    public let supportedURLs: [String: [AISupportedURLPattern]] = [
        "image/*": [AISupportedURLPattern { $0.hasPrefix("ms://") }],
        "video/*": [AISupportedURLPattern { $0.hasPrefix("ms://") }]
    ]

    public init(modelID: String, config: MoonshotAIModelConfiguration, includeUsage: Bool = true) {
        self.providerID = config.http.providerID
        self.modelID = modelID
        self.config = config
        self.includeUsage = includeUsage
    }

    private var providerOptionsName: String {
        String(providerID.split(separator: ".").first ?? "moonshotai").trimmingCharacters(in: .whitespaces)
    }

    /// Builds the unary request body and warnings without sending a request.
    public func prepareRequest(_ request: LanguageModelRequest) throws -> (body: JSONValue, warnings: [AIWarning]) {
        let prepared = try preparedBody(for: request, stream: false)
        return (.object(prepared.body), prepared.warnings)
    }

    private func preparedBody(for request: LanguageModelRequest, stream: Bool) throws -> (body: [String: JSONValue], warnings: [AIWarning]) {
        let args = try moonshotChatArgs(for: request, modelID: modelID)
        var body = args.body
        var warnings = args.warnings
        if stream {
            body["stream"] = true
            if includeUsage { body["stream_options"] = ["include_usage": true] }
        }
        body = config.transformRequestBody?(body) ?? body
        body = config.transformRequestBodyWithWarnings?(body, &warnings) ?? body
        return (body, warnings)
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try preparedBody(for: request, stream: false)
        let httpRequest = try config.http.request(path: "/chat/completions", modelID: modelID, body: .object(prepared.body), headers: request.headers, abortSignal: request.abortSignal)
        let response = try await config.http.transport.send(httpRequest)
        guard (200..<300).contains(response.statusCode) else {
            throw openAICompatibleHTTPStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        guard moonshotIsValidChatResponse(raw), let choice = raw["choices"]?.arrayValue?.first else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid Moonshot AI chat completion response.")
        }
        let message = choice["message"]
        var content: [AIResultContentPart] = []
        let reasoning = message?["reasoning_content"]?.stringValue ?? ""
        if !reasoning.isEmpty { content.append(.reasoning(reasoning)) }
        let rawToolCalls = message?["tool_calls"]?.arrayValue
        let toolCalls = (rawToolCalls ?? []).map { item in
            AIToolCall(
                id: resolvedToolCallID(item["id"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }, whenMissing: generateId()),
                name: item["function"]?["name"]?.stringValue ?? "",
                arguments: item["function"]?["arguments"]?.stringValue ?? "",
                rawValue: item
            )
        }
        content.append(contentsOf: toolCalls.map(AIResultContentPart.toolCall))
        let text = message?["content"]?.stringValue ?? ""
        if !text.isEmpty { content.append(.text(text)) }

        var metadata = moonshotCacheWriteTokens(headers: response.headers)
        if let logprobs = choice["logprobs"], logprobs != .null {
            metadata["logprobs"] = moonshotLogprobsObject(logprobs)
        }
        if let object = raw["object"], object != .null { metadata["responseObject"] = object }
        if let index = choice["index"], index != .null { metadata["choiceIndex"] = index }
        if let role = message?["role"], role != .null { metadata["messageRole"] = role }
        if let rawToolCalls {
            metadata["toolCallTypes"] = .array(rawToolCalls.compactMap { $0["type"] == nil || $0["type"] == .null ? nil : $0["type"] })
        }
        let finishReason = choice["finish_reason"]?.stringValue

        var result = TextGenerationResult(
            text: text,
            content: content,
            reasoning: reasoning,
            finishReason: moonshotFinishReason(finishReason),
            usage: moonshotConvertUsage(raw["usage"]),
            toolCalls: toolCalls,
            providerMetadata: [providerOptionsName: .object(metadata)],
            rawValue: raw,
            warnings: prepared.warnings,
            requestMetadata: AIRequestMetadata(body: .object(prepared.body), headers: request.headers, url: httpRequest.url.absoluteString),
            responseMetadata: aiResponseMetadata(from: raw, response: response, modelID: modelID)
        )
        result.content = content
        return result
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let prepared = try preparedBody(for: request, stream: true)
                    let body = JSONValue.object(prepared.body)
                    let httpRequest = try config.http.request(path: "/chat/completions", modelID: modelID, body: body, headers: request.headers, abortSignal: request.abortSignal)
                    let response = try await config.http.streamRequest(httpRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        throw openAICompatibleHTTPStatusError(provider: providerID, response: try await bufferedHTTPResponse(from: response, request: httpRequest))
                    }
                    let responseHead = httpResponseHead(from: response, request: httpRequest)
                    continuation.yield(.streamStart(warnings: prepared.warnings))
                    continuation.yield(.requestMetadata(AIRequestMetadata(body: body, headers: request.headers, url: httpRequest.url.absoluteString)))

                    var toolCalls = OpenAIStyleStreamingToolCalls()
                    // A clean end without the provider's completion signal is interrupted.
                    var finishReason = "interrupted"
                    var topLevelUsage: JSONValue?
                    var choiceUsage: JSONValue?
                    var contentLogprobs: [JSONValue] = []
                    var isFirstChunk = true
                    var isActiveReasoning = false
                    var isActiveText = false
                    var responseObject: JSONValue?
                    var choiceIndex: JSONValue?
                    var messageRole: JSONValue?
                    var toolCallTypes: [Int: JSONValue] = [:]

                    for try await event in serverSentEvents(from: response.body) {
                        if event.data == "[DONE]" { break }
                        let raw: JSONValue
                        do {
                            raw = try decodeJSONBody(Data(event.data.utf8))
                        } catch {
                            finishReason = "error"
                            continuation.yield(.error(message: error.localizedDescription))
                            continue
                        }
                        if request.includeRawChunks { continuation.yield(.raw(raw)) }
                        guard moonshotIsValidChatChunk(raw) else {
                            finishReason = "error"
                            if let error = moonshotStreamProviderError(from: raw) {
                                continuation.yield(.providerError(error))
                            } else {
                                continuation.yield(.error(message: "Invalid Moonshot AI chat completion chunk.", rawValue: raw))
                            }
                            continue
                        }
                        if isFirstChunk {
                            isFirstChunk = false
                            continuation.yield(.responseMetadata(aiResponseMetadata(from: raw, response: responseHead, modelID: modelID)))
                        }
                        if let usage = raw["usage"], usage != .null { topLevelUsage = usage }
                        if let object = raw["object"], object != .null { responseObject = object }
                        let choice = raw["choices"]?.arrayValue?.first
                        if let usage = choice?["usage"], usage != .null { choiceUsage = usage }
                        if let index = choice?["index"], index != .null { choiceIndex = index }
                        if let reason = choice?["finish_reason"]?.stringValue {
                            finishReason = moonshotFinishReason(reason)
                        }
                        if let logprobs = choice?["logprobs"]?["content"]?.arrayValue {
                            contentLogprobs.append(contentsOf: logprobs)
                        }
                        guard let delta = choice?["delta"], delta != .null else { continue }
                        if let role = delta["role"], role != .null { messageRole = role }

                        if let reasoning = delta["reasoning_content"]?.stringValue, !reasoning.isEmpty {
                            if !isActiveReasoning {
                                continuation.yield(.reasoningStart(id: "reasoning-0"))
                                isActiveReasoning = true
                            }
                            continuation.yield(.reasoningDeltaPart(id: "reasoning-0", delta: reasoning))
                        }
                        if let text = delta["content"]?.stringValue, !text.isEmpty {
                            if !isActiveText {
                                continuation.yield(.textStart(id: "txt-0"))
                                isActiveText = true
                            }
                            if isActiveReasoning {
                                continuation.yield(.reasoningEnd(id: "reasoning-0"))
                                isActiveReasoning = false
                            }
                            continuation.yield(.textDeltaPart(id: "txt-0", delta: text))
                        }
                        if let deltas = delta["tool_calls"]?.arrayValue, !deltas.isEmpty {
                            if isActiveReasoning {
                                continuation.yield(.reasoningEnd(id: "reasoning-0"))
                                isActiveReasoning = false
                            }
                            for (position, item) in deltas.enumerated() {
                                let index = item["index"]?.intValue ?? position
                                if let type = item["type"], type != .null { toolCallTypes[index] = type }
                                var indexed = item.objectValue ?? [:]
                                indexed["index"] = .number(Double(index))
                                let toolCallDelta = JSONValue.object(indexed)
                                if !toolCalls.hasMatchingBuffer(for: toolCallDelta) {
                                    guard let name = item["function"]?["name"]?.stringValue else {
                                        throw AIError.invalidResponse(provider: providerID, message: "Expected 'function.name' to be a string.")
                                    }
                                    // Blank names cannot start a usable call.
                                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                                    if item["id"]?.stringValue.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true {
                                        indexed["id"] = .string(generateId())
                                    }
                                }
                                for part in toolCalls.apply(delta: .object(indexed)) { continuation.yield(part) }
                            }
                        }
                    }
                    if isActiveReasoning { continuation.yield(.reasoningEnd(id: "reasoning-0")) }
                    if isActiveText { continuation.yield(.textEnd(id: "txt-0")) }
                    for part in toolCalls.finishedParts() { continuation.yield(part) }

                    var metadata = moonshotCacheWriteTokens(headers: response.headers)
                    if !contentLogprobs.isEmpty { metadata["logprobs"] = ["content": .array(contentLogprobs)] }
                    if let responseObject { metadata["responseObject"] = responseObject }
                    if let choiceIndex { metadata["choiceIndex"] = choiceIndex }
                    if let messageRole { metadata["messageRole"] = messageRole }
                    if !toolCallTypes.isEmpty {
                        metadata["toolCallTypes"] = .array(toolCallTypes.sorted { $0.key < $1.key }.map(\.value))
                    }
                    continuation.yield(.finishMetadata(
                        reason: finishReason,
                        usage: moonshotConvertUsage(topLevelUsage ?? choiceUsage),
                        providerMetadata: [providerOptionsName: .object(metadata)]
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

// MARK: - Response validation (upstream moonshotai-chat-api-types.ts)

private func moonshotIsNullish(_ value: JSONValue?) -> Bool { value == nil || value == .null }
private func moonshotIsNullishNumber(_ value: JSONValue?) -> Bool { moonshotIsNullish(value) || value?.doubleValue != nil && value?.boolValue == nil }
private func moonshotIsNullishString(_ value: JSONValue?) -> Bool { moonshotIsNullish(value) || value?.stringValue != nil }

private func moonshotIsValidUsage(_ usage: JSONValue?) -> Bool {
    guard !moonshotIsNullish(usage) else { return true }
    guard usage?.objectValue != nil else { return false }
    let numbers = ["prompt_tokens", "completion_tokens", "cached_tokens", "total_tokens"].allSatisfy { moonshotIsNullishNumber(usage?[$0]) }
    let prompt = usage?["prompt_tokens_details"]
    let promptValid = moonshotIsNullish(prompt) || prompt?.objectValue != nil
        && moonshotIsNullishNumber(prompt?["cached_tokens"]) && moonshotIsNullishNumber(prompt?["cache_write_tokens"])
    let completion = usage?["completion_tokens_details"]
    let completionValid = moonshotIsNullish(completion) || completion?.objectValue != nil
        && moonshotIsNullishNumber(completion?["reasoning_tokens"])
    return numbers && promptValid && completionValid
}

private func moonshotIsValidLogprobs(_ value: JSONValue?) -> Bool {
    guard !moonshotIsNullish(value) else { return true }
    guard value?.objectValue != nil else { return false }
    let content = value?["content"]
    return moonshotIsNullish(content) || content?.arrayValue != nil
}

private func moonshotIsValidMetadata(_ raw: JSONValue, object: String) -> Bool {
    moonshotIsNullishString(raw["id"]) && moonshotIsNullishNumber(raw["created"]) && moonshotIsNullishString(raw["model"])
        && (moonshotIsNullish(raw["object"]) || raw["object"]?.stringValue == object)
        && moonshotIsValidUsage(raw["usage"])
}

func moonshotIsValidChatResponse(_ raw: JSONValue) -> Bool {
    guard raw.objectValue != nil, moonshotIsValidMetadata(raw, object: "chat.completion"),
          let choices = raw["choices"]?.arrayValue else { return false }
    return choices.allSatisfy { choice in
        guard let message = choice["message"], message.objectValue != nil else { return false }
        let toolCallsValid: Bool = {
            guard let toolCalls = message["tool_calls"], toolCalls != .null else { return true }
            return toolCalls.arrayValue?.allSatisfy { call in
                moonshotIsNullishString(call["id"])
                    && (moonshotIsNullish(call["type"]) || call["type"] == "function")
                    && call["function"]?["name"]?.stringValue != nil
                    && call["function"]?["arguments"]?.stringValue != nil
            } ?? false
        }()
        return moonshotIsNullishNumber(choice["index"])
            && (moonshotIsNullish(message["role"]) || message["role"] == "assistant")
            && moonshotIsNullishString(message["content"])
            && moonshotIsNullishString(message["reasoning_content"])
            && toolCallsValid
            && moonshotIsValidLogprobs(choice["logprobs"])
            && moonshotIsNullishString(choice["finish_reason"])
    }
}

func moonshotIsValidChatChunk(_ raw: JSONValue) -> Bool {
    guard raw.objectValue != nil, moonshotIsValidMetadata(raw, object: "chat.completion.chunk"),
          let choices = raw["choices"]?.arrayValue else { return false }
    return choices.allSatisfy { choice in
        guard choice.objectValue != nil else { return false }
        let delta = choice["delta"]
        let deltaValid: Bool = {
            guard !moonshotIsNullish(delta) else { return true }
            guard delta?.objectValue != nil else { return false }
            let toolCalls = delta?["tool_calls"]
            let toolCallsValid = moonshotIsNullish(toolCalls) || toolCalls?.arrayValue?.allSatisfy { call in
                moonshotIsNullishNumber(call["index"])
                    && moonshotIsNullishString(call["id"])
                    && (moonshotIsNullish(call["type"]) || call["type"] == "function")
                    && call["function"]?.objectValue != nil
                    && moonshotIsNullishString(call["function"]?["name"])
                    && moonshotIsNullishString(call["function"]?["arguments"])
            } ?? false
            return (moonshotIsNullish(delta?["role"]) || delta?["role"] == "assistant")
                && moonshotIsNullishString(delta?["content"])
                && moonshotIsNullishString(delta?["reasoning_content"])
                && toolCallsValid
        }()
        return moonshotIsNullishNumber(choice["index"])
            && deltaValid
            && moonshotIsValidLogprobs(choice["logprobs"])
            && moonshotIsNullishString(choice["finish_reason"])
            && moonshotIsValidUsage(choice["usage"])
    }
}

private func moonshotLogprobsObject(_ value: JSONValue) -> JSONValue {
    guard let content = value["content"] else { return .object([:]) }
    return ["content": content]
}

/// Maps a Moonshot stream error envelope (`{"error": {...}}`) to a typed provider stream error.
func moonshotStreamProviderError(from raw: JSONValue) -> AIStreamProviderError? {
    guard let error = raw["error"], error.objectValue != nil, let message = error["message"]?.stringValue,
          moonshotIsNullishString(error["type"]), moonshotIsNullishString(error["code"]) else {
        return nil
    }
    let type = error["type"]?.stringValue
    let metadata: (Int?, Bool?)
    switch type {
    case "rate_limit_exceeded", "rate_limit_error": metadata = (429, true)
    case "server_error", "api_error", "internal_server_error": metadata = (500, true)
    case "overloaded_error", "service_unavailable": metadata = (503, true)
    case "timeout", "timeout_error": metadata = (504, true)
    case "authentication_error", "invalid_api_key": metadata = (401, false)
    case "permission_error": metadata = (403, false)
    case "not_found_error", "model_not_found": metadata = (404, false)
    case "bad_request", "context_length_exceeded", "invalid_request_error": metadata = (400, false)
    default: metadata = (nil, nil)
    }
    return AIStreamProviderError(
        message: message,
        type: type,
        code: error["code"]?.stringValue.map(JSONValue.string),
        statusCode: metadata.0,
        isRetryable: metadata.1,
        data: raw
    )
}
