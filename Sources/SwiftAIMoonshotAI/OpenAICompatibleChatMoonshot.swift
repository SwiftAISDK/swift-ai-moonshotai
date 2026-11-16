import SwiftAIOpenAICompatible
import Foundation
import SwiftAIProvider
import SwiftAITransport
import SwiftAIProviderUtilities

// MARK: - Model catalog policy (upstream moonshotai-model-catalog.ts)

enum MoonshotModelFamily: String {
    case kimiK25 = "kimi-k2.5"
    case kimiK26 = "kimi-k2.6"
    case kimiK27 = "kimi-k2.7"
    case kimiK3 = "kimi-k3"
    case moonshotV1 = "moonshot-v1"
    case unknown
}

func moonshotModelFamily(_ modelID: String) -> MoonshotModelFamily {
    switch modelID {
    case "kimi-k2.5": return .kimiK25
    case "kimi-k2.6": return .kimiK26
    case "kimi-k2.7-code", "kimi-k2.7-code-highspeed": return .kimiK27
    case "kimi-k3", "kimi-k3.1-pro", "kimi-k3.1-pro-highspeed": return .kimiK3
    default: return modelID.hasPrefix("moonshot-v1-") ? .moonshotV1 : .unknown
    }
}

/// Kimi models fix their sampling parameters (`capabilities.language.sampling.temperature == false`).
func moonshotIsKimiModel(_ modelID: String) -> Bool {
    moonshotModelFamily(modelID).rawValue.hasPrefix("kimi-")
}

/// Upstream `capabilities.language.tools.required`.
func moonshotSupportsRequiredToolChoice(_ modelID: String) -> Bool {
    !["kimi-k2.6", "kimi-k2.7-code", "kimi-k2.7-code-highspeed"].contains(modelID)
}

func moonshotSupportsStructuredOutputs(modelID: String) -> Bool {
    true
}

private let moonshotSupportedImageMediaTypes: Set<String> = [
    "image/jpeg", "image/png", "image/gif", "image/webp", "image/bmp", "image/heic", "image/heif"
]

private let moonshotSupportedVideoMediaTypes: Set<String> = [
    "video/mp4", "video/mpeg", "video/mov", "video/avi", "video/x-flv", "video/mpg", "video/webm", "video/wmv", "video/3gpp"
]

private let moonshotReasoningEffortMap = ["low": "low", "high": "high", "max": "max"]

// MARK: - Provider options (upstream moonshotai-chat-options.ts)

func moonshotInvalidProviderOptions() -> AIError {
    .invalidArgument(argument: "providerOptions", message: "invalid moonshotai provider options")
}

func moonshotProviderOptions(from providerOptions: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for key in ["moonshotai", "moonshotAI"] {
        guard let value = providerOptions[key], value != .null else { continue }
        guard let nested = value.objectValue else { throw moonshotInvalidProviderOptions() }
        output.merge(try moonshotValidateLanguageProviderOptions(nested, argumentPrefix: "providerOptions.\(key)")) { _, providerValue in providerValue }
    }
    return output
}

func moonshotValidateLanguageProviderOptions(_ options: [String: JSONValue], argumentPrefix: String) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for key in ["strictJsonSchema", "logprobs"] {
        if let value = options[key] {
            guard value.boolValue != nil else { throw moonshotInvalidProviderOptions() }
            output[key] = value
        }
    }
    if let value = options["topLogprobs"] {
        guard let number = value.doubleValue, moonshotIsInteger(number), (0...20).contains(number) else {
            throw moonshotInvalidProviderOptions()
        }
        output["topLogprobs"] = .number(number)
    }
    if let value = options["reasoningEffort"] {
        guard let effort = value.stringValue, ["low", "high", "max"].contains(effort) else { throw moonshotInvalidProviderOptions() }
        output["reasoningEffort"] = .string(effort)
    }
    if let value = options["prediction"] {
        guard let prediction = value.objectValue, prediction["type"] == "content", let content = prediction["content"] else {
            throw moonshotInvalidProviderOptions()
        }
        if let text = content.stringValue {
            output["prediction"] = ["type": "content", "content": .string(text)]
        } else if let parts = content.arrayValue {
            let mapped: [JSONValue] = try parts.map { part in
                guard part["type"] == "text", let text = part["text"]?.stringValue else { throw moonshotInvalidProviderOptions() }
                return ["type": "text", "text": .string(text)]
            }
            output["prediction"] = ["type": "content", "content": .array(mapped)]
        } else {
            throw moonshotInvalidProviderOptions()
        }
    }
    if let thinking = options["thinking"] {
        guard let thinkingObject = thinking.objectValue else { throw moonshotInvalidProviderOptions() }
        var mappedThinking: [String: JSONValue] = [:]
        if let type = thinkingObject["type"] {
            guard let typeValue = type.stringValue, typeValue == "enabled" || typeValue == "disabled" else {
                throw moonshotInvalidProviderOptions()
            }
            mappedThinking["type"] = .string(typeValue)
        }
        if let budgetTokens = thinkingObject["budgetTokens"] {
            guard let number = budgetTokens.doubleValue, moonshotIsInteger(number), number >= 1024 else {
                throw moonshotInvalidProviderOptions()
            }
            mappedThinking["budgetTokens"] = .number(number)
        }
        output["thinking"] = .object(mappedThinking)
    }
    if let reasoningHistory = options["reasoningHistory"] {
        guard let value = reasoningHistory.stringValue, ["disabled", "interleaved", "preserved"].contains(value) else {
            throw moonshotInvalidProviderOptions()
        }
        output["reasoningHistory"] = .string(value)
    }
    if let cache = options["promptCacheOptions"] {
        guard let values = cache.objectValue else { throw moonshotInvalidProviderOptions() }
        var mapped: [String: JSONValue] = [:]
        if let mode = values["mode"] {
            guard mode == "implicit" else { throw moonshotInvalidProviderOptions() }
            mapped["mode"] = mode
        }
        if let ttl = values["ttl"] {
            guard ttl == "5m" || ttl == "1h" else { throw moonshotInvalidProviderOptions() }
            mapped["ttl"] = ttl
        }
        output["promptCacheOptions"] = .object(mapped)
    }
    for key in ["promptCacheKey", "safetyIdentifier"] {
        if let option = options[key] {
            guard let value = option.stringValue else { throw moonshotInvalidProviderOptions() }
            output[key] = .string(value)
        }
    }
    return output
}

func moonshotIsInteger(_ value: Double) -> Bool {
    value.rounded(.towardZero) == value
}

/// Message-level `providerOptions.moonshotai` (`name`, `partial`, `tools`).
struct MoonshotMessageOptions {
    var name: String?
    var partial = false
    var tools: [JSONValue]?
}

private func moonshotMessageOptions(_ message: AIMessage) throws -> MoonshotMessageOptions? {
    guard let value = message.providerMetadata["moonshotai"], value != .null else { return nil }
    guard let object = value.objectValue else { throw moonshotInvalidProviderOptions() }
    var options = MoonshotMessageOptions()
    if let name = object["name"] {
        guard let string = name.stringValue else { throw moonshotInvalidProviderOptions() }
        options.name = string
    }
    if let partial = object["partial"] {
        guard partial == .bool(true) else { throw moonshotInvalidProviderOptions() }
        options.partial = true
    }
    if let tools = object["tools"] {
        guard let array = tools.arrayValue else { throw moonshotInvalidProviderOptions() }
        options.tools = try array.map { tool in
            guard tool["type"] == "function",
                  tool["name"]?.stringValue != nil,
                  tool["inputSchema"]?.objectValue != nil,
                  tool["description"] == nil || tool["description"]?.stringValue != nil,
                  tool["strict"] == nil || tool["strict"]?.boolValue != nil else {
                throw moonshotInvalidProviderOptions()
            }
            return tool
        }
    }
    return options
}

// MARK: - Tools (upstream moonshotai-prepare-tools.ts)

private func moonshotFunctionTool(name: String, description: JSONValue?, inputSchema: JSONValue, strict: JSONValue?) throws -> JSONValue {
    var function: [String: JSONValue] = [
        "name": .string(name),
        "parameters": try moonshotNormalizeJSONSchemaForMFJS(inputSchema)
    ]
    if let description, description != .null { function["description"] = description }
    if let strict, strict != .null { function["strict"] = strict }
    return ["type": "function", "function": .object(function)]
}

private func moonshotRequestTools(_ request: LanguageModelRequest, modelID: String, warnings: inout [AIWarning]) throws -> (tools: JSONValue?, toolChoice: JSONValue?) {
    guard !request.tools.isEmpty else { return (nil, nil) }
    var tools: [JSONValue] = []
    for (name, schema) in request.tools.sorted(by: { $0.key < $1.key }) {
        let object = schema.objectValue
        if object?["type"]?.stringValue == "provider" || object?["id"]?.stringValue != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "provider-defined tool \(object?["id"]?.stringValue ?? name)"))
            continue
        }
        tools.append(try moonshotFunctionTool(
            name: name,
            description: object?["description"],
            inputSchema: aiFunctionToolInputSchema(schema),
            strict: object?["strict"]
        ))
    }

    let choiceInput = request.toolChoice ?? request.extraBody["toolChoice"]
    let type = choiceInput?.stringValue ?? choiceInput?["type"]?.stringValue
    var toolChoice: JSONValue?
    switch type {
    case nil:
        if let choiceInput, choiceInput != .null {
            warnings.append(AIWarning(type: "unsupported", feature: "tool choice type: undefined"))
        }
    case "auto", "none":
        toolChoice = .string(type!)
    case "required":
        if moonshotSupportsRequiredToolChoice(modelID) {
            toolChoice = "required"
        } else {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "tool choice \"required\" for model \"\(modelID)\"",
                message: "Moonshot AI rejects required tool choice for this model. The setting has been omitted; use \"auto\" or select a specific tool instead."
            ))
        }
    case "tool":
        if let toolName = choiceInput?["toolName"]?.stringValue ?? choiceInput?["tool_name"]?.stringValue {
            toolChoice = ["type": "function", "function": ["name": .string(toolName)]]
        }
    case let other?:
        warnings.append(AIWarning(type: "unsupported", feature: "tool choice type: \(other)"))
    }
    return (.array(tools), toolChoice)
}

// MARK: - Request arguments (upstream MoonshotAIChatLanguageModel.getArgs)

struct MoonshotChatArgs {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

func moonshotChatArgs(for request: LanguageModelRequest, modelID: String) throws -> MoonshotChatArgs {
    let providerOptions = try moonshotProviderOptions(from: request.providerOptions)
    // Swift-native raw escape hatch: `extraBody` keys (including nested `moonshotai`) pass through
    // and provide lower-precedence fallbacks for typed options.
    var extra = openAICompatibleProviderOptions(from: request.extraBody, providerID: "moonshotai.chat", includeCompatibilityNamespace: true)
    extra.removeValue(forKey: "toolChoice")
    func option(_ key: String, _ alternate: String? = nil) -> JSONValue? {
        let raw = extra.removeValue(forKey: key) ?? alternate.flatMap { extra.removeValue(forKey: $0) }
        return providerOptions[key] ?? raw
    }

    var warnings: [AIWarning] = []
    if request.topK != nil { warnings.append(AIWarning(type: "unsupported", feature: "topK")) }
    if request.seed != nil { warnings.append(AIWarning(type: "unsupported", feature: "seed")) }

    let supportsSampling = !moonshotIsKimiModel(modelID)
    if !supportsSampling {
        for (feature, value) in [("temperature", request.temperature), ("topP", request.topP), ("frequencyPenalty", request.frequencyPenalty), ("presencePenalty", request.presencePenalty)] where value != nil {
            warnings.append(AIWarning(type: "unsupported", feature: feature, message: "\(feature) is fixed by model \"\(modelID)\" and has been omitted."))
        }
    }

    var toolWarnings: [AIWarning] = []
    let tools = try moonshotRequestTools(request, modelID: modelID, warnings: &toolWarnings)

    let family = moonshotModelFamily(modelID)
    let requestedThinking = option("thinking")?.objectValue
    let requestedEffort = option("reasoningEffort", "reasoning_effort")?.stringValue
    let preserveReasoning = option("reasoningHistory")?.stringValue == "preserved"
    extra.removeValue(forKey: "reasoning_history")
    if providerOptions["thinking"] != nil, requestedThinking?["budgetTokens"] != nil {
        warnings.append(AIWarning(type: "deprecated", setting: "providerOptions.moonshotai.thinking.budgetTokens", message: "Moonshot Chat Completions does not support budget_tokens. Remove budgetTokens; the option has been omitted."))
    }
    let thinkingType = requestedThinking?["type"]?.stringValue
    var thinking: [String: JSONValue]?
    var reasoningEffort: String?
    func warnEffort() {
        if requestedEffort != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "reasoningEffort", message: "reasoningEffort is only supported by Kimi K3 and has been omitted for model \"\(modelID)\"."))
        }
    }
    func warnHistory() {
        if preserveReasoning {
            warnings.append(AIWarning(type: "unsupported", feature: "reasoningHistory 'preserved' is not supported by model \"\(modelID)\""))
        }
    }
    let portableThinking: String? = isCustomReasoning(request.reasoning) ? (request.reasoning == "none" ? "disabled" : "enabled") : nil
    switch family {
    case .kimiK3:
        if requestedThinking != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "thinking", message: "Kimi K3 always reasons and does not accept the thinking field. The option has been omitted."))
        }
        reasoningEffort = mapReasoningToProviderEffort(reasoning: request.reasoning, effortMap: moonshotReasoningEffortMap, warnings: &warnings, providerOptionsEffort: requestedEffort)
    case .kimiK27:
        warnEffort()
        if thinkingType == "disabled" {
            warnings.append(AIWarning(type: "unsupported", feature: "thinking.type \"disabled\"", message: "Kimi K2.7 thinking cannot be disabled."))
        } else if requestedThinking == nil, request.reasoning == "none" {
            warnings.append(AIWarning(type: "compatibility", feature: "reasoning", message: "reasoning \"none\" is not supported by Kimi K2.7; thinking cannot be disabled. Using thinking enabled instead."))
        } else if thinkingType == "enabled" {
            thinking = ["type": "enabled"]
        }
    case .kimiK26:
        warnEffort()
        let type = thinkingType ?? portableThinking
        if type != nil || preserveReasoning {
            thinking = ["type": .string(type ?? "enabled")]
            if preserveReasoning { thinking?["keep"] = "all" }
        }
    case .kimiK25:
        warnEffort()
        if let type = thinkingType ?? portableThinking { thinking = ["type": .string(type)] }
        warnHistory()
    case .moonshotV1:
        warnEffort()
        if requestedThinking != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "thinking", message: "thinking is not supported by model \"\(modelID)\" and has been omitted."))
        }
        if isCustomReasoning(request.reasoning), request.reasoning != "none" {
            warnings.append(AIWarning(type: "unsupported", feature: "reasoning", message: "reasoning is not supported by model \"\(modelID)\"."))
        }
        warnHistory()
    case .unknown:
        if let requestedEffort {
            reasoningEffort = requestedEffort
        } else if isCustomReasoning(request.reasoning), request.reasoning != "none" {
            reasoningEffort = mapReasoningToProviderEffort(reasoning: request.reasoning, effortMap: moonshotReasoningEffortMap, warnings: &warnings)
        }
        if let thinkingType {
            thinking = ["type": .string(thinkingType)]
        } else if request.reasoning == "none" {
            thinking = ["type": "disabled"]
        }
        warnHistory()
    }
    // Native raw extraBody escape hatch: an explicitly supplied raw thinking budget is retained.
    if providerOptions["thinking"] == nil, let budget = requestedThinking?["budgetTokens"] ?? requestedThinking?["budget_tokens"], thinking != nil {
        thinking?["budget_tokens"] = budget
    }

    var responseFormat: JSONValue?
    if case let .json(schema, name, _) = request.responseFormat {
        if let schema {
            var stripped = schema
            if var object = schema.objectValue {
                object.removeValue(forKey: "$schema")
                stripped = .object(object)
            }
            responseFormat = [
                "type": "json_schema",
                "json_schema": [
                    "name": .string(name ?? "response"),
                    "strict": providerOptions["strictJsonSchema"] ?? extra.removeValue(forKey: "strictJsonSchema") ?? .bool(true),
                    "schema": try moonshotNormalizeJSONSchemaForMFJS(stripped)
                ]
            ]
        } else {
            responseFormat = ["type": "json_object"]
        }
    }
    extra.removeValue(forKey: "strictJsonSchema")

    var messageWarnings: [AIWarning] = []
    let messages = try moonshotChatMessages(request.messages, modelID: modelID, responseFormat: responseFormat, warnings: &messageWarnings)
    warnings.append(contentsOf: messageWarnings)

    var body: [String: JSONValue] = ["model": .string(modelID), "messages": .array(messages)]
    let logprobs = option("logprobs")
    let topLogprobs = option("topLogprobs")
    if logprobs == .bool(true) || (topLogprobs != nil && topLogprobs != .null) { body["logprobs"] = true }
    if let topLogprobs, topLogprobs != .null { body["top_logprobs"] = topLogprobs }
    if let maxOutputTokens = request.maxOutputTokens { body["max_completion_tokens"] = .number(Double(maxOutputTokens)) }
    if supportsSampling {
        if let value = request.temperature { body["temperature"] = .number(value) }
        if let value = request.topP { body["top_p"] = .number(value) }
        if let value = request.frequencyPenalty { body["frequency_penalty"] = .number(value) }
        if let value = request.presencePenalty { body["presence_penalty"] = .number(value) }
    }
    if let responseFormat { body["response_format"] = responseFormat }
    if !request.stopSequences.isEmpty { body["stop"] = .array(request.stopSequences.map(JSONValue.string)) }
    if let toolsValue = tools.tools { body["tools"] = toolsValue }
    if let toolChoice = tools.toolChoice { body["tool_choice"] = toolChoice }
    if let prediction = option("prediction"), prediction != .null { body["prediction"] = prediction }
    if let thinking { body["thinking"] = .object(thinking) }
    if let reasoningEffort { body["reasoning_effort"] = .string(reasoningEffort) }
    if let value = option("promptCacheKey"), value != .null { body["prompt_cache_key"] = value }
    if let cache = option("promptCacheOptions")?.objectValue {
        var mapped: [String: JSONValue] = ["mode": cache["mode"] ?? "implicit"]
        if let ttl = cache["ttl"] { mapped["ttl"] = ttl }
        body["prompt_cache_options"] = .object(mapped)
    }
    if let value = option("safetyIdentifier"), value != .null { body["safety_identifier"] = value }
    // Remaining raw extraBody keys are forwarded unchanged.
    body.merge(extra) { _, raw in raw }
    return MoonshotChatArgs(body: body, warnings: warnings + toolWarnings)
}

// MARK: - Messages (upstream convert-to-moonshotai-chat-messages.ts)

func moonshotChatMessages(_ messages: [AIMessage], modelID: String?, responseFormat: JSONValue?, warnings: inout [AIWarning]) throws -> [JSONValue] {
    var output: [JSONValue] = []
    let family = modelID.map(moonshotModelFamily) ?? .unknown
    for (index, message) in messages.enumerated() {
        let options = try moonshotMessageOptions(message)
        if options?.partial == true, message.role != .assistant {
            throw AIError.invalidArgument(argument: "prompt", message: "Moonshot AI Partial Mode requires `partial: true` on an assistant message.")
        }
        if options?.tools != nil, message.role != .system {
            throw AIError.invalidArgument(argument: "prompt", message: "Moonshot dynamic tools must be configured on a system message.")
        }
        switch message.role {
        case .system:
            if let dynamicTools = options?.tools, !dynamicTools.isEmpty {
                guard message.combinedText.isEmpty else {
                    throw AIError.invalidArgument(argument: "prompt", message: "A Moonshot dynamic-tool system message must use empty content because the API forbids content alongside tools.")
                }
                guard family == .kimiK3 || family == .unknown else {
                    warnings.append(AIWarning(
                        type: "unsupported",
                        feature: "dynamic tool loading for model \"\(modelID ?? "")\"",
                        message: "Moonshot documents dynamic tool loading only for Kimi K3. The dynamic system message has been omitted."
                    ))
                    continue
                }
                let tools = try dynamicTools.map { tool in
                    try moonshotFunctionTool(name: tool["name"]?.stringValue ?? "", description: tool["description"], inputSchema: tool["inputSchema"] ?? .object([:]), strict: tool["strict"])
                }
                output.append(["role": "system", "tools": .array(tools)])
                continue
            }
            var converted: [String: JSONValue] = ["role": "system", "content": .string(message.combinedText)]
            if let name = options?.name { converted["name"] = .string(name) }
            output.append(.object(converted))
        case .user:
            var converted: [String: JSONValue] = ["role": "user"]
            if message.content.count == 1, case let .text(text, _) = message.content[0] {
                converted["content"] = .string(text)
            } else {
                converted["content"] = .array(try message.content.map(moonshotUserContentPart))
            }
            if let name = options?.name { converted["name"] = .string(name) }
            output.append(.object(converted))
        case .assistant:
            if options?.partial == true {
                if index != messages.count - 1 {
                    throw AIError.invalidArgument(argument: "prompt", message: "Moonshot AI Partial Mode requires the partial assistant message to be the final message.")
                }
                if responseFormat?["type"] == "json_object" {
                    throw AIError.invalidArgument(argument: "prompt", message: "Moonshot AI Partial Mode cannot be combined with JSON object response format.")
                }
            }
            var text = ""
            var reasoning = message.reasoning ?? ""
            var toolCalls: [JSONValue] = []
            for part in message.content {
                switch part {
                case let .text(value, _): text += value
                case let .reasoning(value, _): reasoning += value
                case let .toolCall(call):
                    toolCalls.append(["id": .string(call.id), "type": "function", "function": ["name": .string(call.name), "arguments": .string(call.arguments)]])
                default: break
                }
            }
            var converted: [String: JSONValue] = [
                "role": "assistant",
                "content": toolCalls.isEmpty ? .string(text) : (text.isEmpty ? .null : .string(text))
            ]
            if let name = options?.name { converted["name"] = .string(name) }
            if options?.partial == true { converted["partial"] = true }
            if !reasoning.isEmpty { converted["reasoning_content"] = .string(reasoning) }
            if !toolCalls.isEmpty { converted["tool_calls"] = .array(toolCalls) }
            output.append(.object(converted))
        case .tool:
            if options?.name != nil {
                warnings.append(AIWarning(type: "unsupported", feature: "message name on tool messages"))
            }
            for part in message.content {
                guard case let .toolResult(result) = part else { continue }
                output.append(["role": "tool", "tool_call_id": .string(result.toolCallID), "content": .string(moonshotToolResultContent(result))])
            }
        }
    }
    return output
}

/// Converts messages with the default Moonshot policy (no model-specific dynamic-tool filtering).
func moonshotChatMessages(from messages: [AIMessage]) throws -> [JSONValue] {
    var warnings: [AIWarning] = []
    return try moonshotChatMessages(messages, modelID: nil, responseFormat: nil, warnings: &warnings)
}

private func moonshotToolResultContent(_ result: AIToolResult) -> String {
    let output = result.modelOutput ?? result.result
    if let text = output.stringValue {
        return text
    }
    guard let object = output.objectValue, let type = object["type"]?.stringValue else {
        return canonicalJSONText(output) ?? ""
    }
    switch type {
    case "text", "error-text":
        return object["value"]?.stringValue ?? ""
    case "execution-denied":
        return object["reason"]?.stringValue ?? "Tool call execution denied."
    case "content", "json", "error-json":
        return canonicalJSONText(object["value"] ?? .null) ?? ""
    default:
        return canonicalJSONText(output) ?? ""
    }
}

private func moonshotUnsupportedMediaType(_ mediaType: String) -> AIError {
    .invalidArgument(argument: "messages", message: "MoonshotAI file part media type \(mediaType) is not supported.")
}

private func moonshotUserContentPart(_ part: AIContentPart) throws -> JSONValue {
    switch part {
    case let .text(text, _):
        return ["type": "text", "text": .string(text)]
    case let .imageURL(url, _):
        return moonshotURLPart(type: "image_url", url: url)
    case let .data(mimeType, data, _), let .file(mimeType, data, _, _):
        let topLevel = mimeType.split(separator: "/", maxSplits: 1).first.map(String.init)
        if topLevel == "image" || topLevel == "video" {
            let mediaType = try resolveFullMediaType(mediaType: mimeType, data: data)
            let supported = topLevel == "image" ? moonshotSupportedImageMediaTypes : moonshotSupportedVideoMediaTypes
            guard supported.contains(mediaType) else { throw moonshotUnsupportedMediaType(mediaType) }
            return moonshotURLPart(type: topLevel == "image" ? "image_url" : "video_url", url: "data:\(mediaType);base64,\(data.base64EncodedString())")
        }
        if topLevel == "text" {
            return ["type": "text", "text": .string(String(decoding: data, as: UTF8.self))]
        }
        throw moonshotUnsupportedMediaType(mimeType)
    case let .providerReference(mimeType, reference, _, _):
        let topLevel = mimeType.split(separator: "/", maxSplits: 1).first.map(String.init)
        guard topLevel == "image" || topLevel == "video" else { throw moonshotUnsupportedMediaType(mimeType) }
        let value = try resolveProviderReference(reference, provider: "moonshotai")
        guard value.hasPrefix("ms://") else {
            throw AIError.invalidArgument(argument: "messages", message: "Moonshot file provider references without an ms:// URL are not supported.")
        }
        return moonshotURLPart(type: topLevel == "image" ? "image_url" : "video_url", url: value)
    case .reasoning, .reasoningFile, .custom, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
        throw AIError.invalidArgument(argument: "messages", message: "MoonshotAI user content part is not supported.")
    }
}

private func moonshotURLPart(type: String, url: String) -> JSONValue {
    .object(["type": .string(type), type: .object(["url": .string(url)])])
}

// MARK: - MFJS schema normalization (upstream normalize-json-schema-for-mfjs.ts)

func moonshotNormalizeJSONSchemaForMFJS(_ schema: JSONValue, isRoot: Bool = true) throws -> JSONValue {
    guard var object = schema.objectValue else {
        if isRoot {
            throw AIError.invalidArgument(
                argument: "tools",
                message: "MoonshotAI tool and response schemas must be a JSON Schema object with type object."
            )
        }
        return schema
    }
    if isRoot, object["type"] == nil, moonshotIsObjectUnion(object) {
        object["type"] = "object"
    }
    if isRoot, object["type"]?.stringValue != "object" {
        throw AIError.invalidArgument(
            argument: "tools",
            message: "MoonshotAI tool and response schemas must be a JSON Schema object with type object."
        )
    }

    if let tuple = object["items"]?.arrayValue {
        let existing = object["prefixItems"]?.arrayValue ?? []
        // Traverse only in the generic pass below, preserving positional order.
        object["prefixItems"] = .array(existing + tuple)
        object.removeValue(forKey: "items")
    }

    if !isRoot, let parentType = object["type"]?.stringValue, let anyOf = object["anyOf"]?.arrayValue {
        object.removeValue(forKey: "type")
        object["anyOf"] = .array(anyOf.map { branch in
            guard var branchObject = branch.objectValue else { return branch }
            if branchObject["type"] == nil { branchObject["type"] = .string(parentType) }
            return .object(branchObject)
        })
    }

    for key in ["allOf", "anyOf", "oneOf", "prefixItems"] {
        if let values = object[key]?.arrayValue {
            object[key] = .array(try values.map { try moonshotNormalizeJSONSchemaForMFJS($0, isRoot: false) })
        }
    }
    // Upstream traverses `$defs` but leaves legacy `definitions` untouched.
    for key in ["properties", "patternProperties", "$defs", "dependentSchemas"] {
        if let values = object[key]?.objectValue {
            object[key] = .object(try values.mapValues { try moonshotNormalizeJSONSchemaForMFJS($0, isRoot: false) })
        }
    }
    for key in ["additionalProperties", "propertyNames", "items", "contains", "not", "if", "then", "else"] {
        if let value = object[key], value.objectValue != nil || value.boolValue != nil {
            object[key] = try moonshotNormalizeJSONSchemaForMFJS(value, isRoot: false)
        }
    }
    return .object(object)
}

private func moonshotIsObjectUnion(_ root: [String: JSONValue]) -> Bool {
    let unions = [root["anyOf"], root["oneOf"]].compactMap { $0 }
    return !unions.isEmpty && unions.allSatisfy { value in
        guard let branches = value.arrayValue, !branches.isEmpty else { return false }
        return branches.allSatisfy { branch in
            var resolved = branch
            if let ref = branch["$ref"]?.stringValue {
                let parts = ref.split(separator: "/", omittingEmptySubsequences: false)
                if parts.count == 3, parts[0] == "#", parts[1] == "$defs" || parts[1] == "definitions" {
                    resolved = root[String(parts[1])]?[String(parts[2])] ?? branch
                }
            }
            return resolved["type"] == "object" || resolved["type"] == nil && resolved["properties"]?.objectValue != nil
        }
    }
}

// MARK: - Usage and metadata (upstream convert-moonshotai-chat-usage.ts)

func moonshotConvertUsage(_ usage: JSONValue?) -> TokenUsage {
    guard let usage, usage != .null else { return TokenUsage() }
    let inputTokens = usage["prompt_tokens"]?.intValue ?? 0
    let outputTokens = usage["completion_tokens"]?.intValue ?? 0
    let cacheReadTokens = usage["cached_tokens"]?.intValue
        ?? usage["prompt_tokens_details"]?["cached_tokens"]?.intValue
        ?? 0
    let cacheWriteTokens = usage["prompt_tokens_details"]?["cache_write_tokens"]?.intValue
    let reasoningTokens = usage["completion_tokens_details"]?["reasoning_tokens"]?.intValue ?? 0
    return TokenUsage(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: usage["total_tokens"]?.intValue ?? inputTokens + outputTokens,
        inputTokensNoCache: inputTokens - cacheReadTokens - (cacheWriteTokens ?? 0),
        inputTokensCacheRead: cacheReadTokens,
        inputTokensCacheWrite: cacheWriteTokens,
        outputTextTokens: max(0, outputTokens - reasoningTokens),
        outputReasoningTokens: reasoningTokens,
        rawValue: usage
    )
}

func moonshotChatUsage(from raw: JSONValue) -> TokenUsage? {
    moonshotConvertUsage(raw["usage"])
}

func moonshotCacheWriteMetadata(headers: [String: String], namespace: String?) -> [String: JSONValue] {
    let values = moonshotCacheWriteTokens(headers: headers)
    guard !values.isEmpty else { return [:] }
    return [namespace ?? "moonshotai": .object(values)]
}

func moonshotCacheWriteTokens(headers: [String: String]) -> [String: JSONValue] {
    func tokenCount(_ name: String) -> Int? {
        guard let raw = headers.first(where: { $0.key.lowercased() == name })?.value else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        return Int(value)
    }
    let short = tokenCount("msh-usage-cache-write-tokens-5m")
    let long = tokenCount("msh-usage-cache-write-tokens-1h")
    guard short != nil || long != nil else { return [:] }
    return ["cacheWriteTokens": ["ttl5m": .number(Double(short ?? 0)), "ttl1h": .number(Double(long ?? 0))]]
}

func moonshotFinishReason(_ reason: String?) -> String {
    switch reason {
    case "stop": return "stop"
    case "length": return "length"
    case "content_filter": return "content-filter"
    case "function_call", "tool_calls": return "tool-calls"
    default: return "other"
    }
}

// MARK: - Shared compatible-chat hook (used by the umbrella generic provider)

/// Rebuilds a compatible Chat Completions body with the Moonshot request policy.
func moonshotChatBody(
    from input: [String: JSONValue],
    request: LanguageModelRequest,
    modelID: String,
    warnings: inout [AIWarning]
) throws -> [String: JSONValue] {
    let args = try moonshotChatArgs(for: request, modelID: modelID)
    var body = args.body
    for key in ["stream", "stream_options"] {
        if let value = input[key] { body[key] = value }
    }
    warnings = args.warnings + warnings.filter { !args.warnings.contains($0) }
    return body
}

/// Installs the Moonshot wire policy on a shared compatible chat configuration.
public func configureMoonshotChat(_ configuration: inout OpenAICompatibleModelConfiguration) {
    configuration.toolCallsBeforeText = true
    configuration.responseHeaderMetadata = { moonshotCacheWriteMetadata(headers: $0, namespace: $1) }
    configuration.convertMessages = moonshotChatMessages(from:)
    configuration.supportsStructuredOutputForModel = moonshotSupportsStructuredOutputs
    configuration.usage = moonshotChatUsage
    configuration.prepareBody = { body, request, modelID, warnings in
        try moonshotChatBody(from: body, request: request, modelID: modelID, warnings: &warnings)
    }
}
