import SwiftAIOpenAICompatible
import Foundation
import SwiftAIProvider
import SwiftAITransport
import SwiftAIProviderUtilities


func moonshotChatBody(
    from input: [String: JSONValue],
    request: LanguageModelRequest,
    modelID: String,
    warnings: inout [AIWarning]
) throws -> [String: JSONValue] {
    var body = input
    if let nested = body.removeValue(forKey: "moonshotai")?.objectValue {
        body.merge(nested) { _, nested in nested }
    }
    if let nested = body.removeValue(forKey: "moonshotAI")?.objectValue {
        body.merge(nested) { _, nested in nested }
    }

    let providerOptions = try moonshotProviderOptions(from: request.providerOptions)
    body.merge(providerOptions) { _, providerValue in providerValue }

    if request.topK != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "topK"))
    }
    if body.removeValue(forKey: "seed") != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "seed"))
    }

    var thinking = body.removeValue(forKey: "thinking")?.objectValue ?? [:]
    if !thinking.isEmpty {
        var converted: [String: JSONValue] = [:]
        if let type = thinking["type"] { converted["type"] = type }
        if let budgetTokens = thinking["budgetTokens"] {
            converted["budget_tokens"] = budgetTokens
        } else if let budgetTokens = thinking["budget_tokens"] {
            converted["budget_tokens"] = budgetTokens
        }
        thinking = converted
    }

    if body.removeValue(forKey: "reasoningHistory")?.stringValue == "preserved" {
        if moonshotSupportsThinkingKeep(modelID: modelID) {
            thinking["keep"] = .string("all")
        } else {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "reasoningHistory 'preserved' is not supported by model \"\(modelID)\""
            ))
        }
    }
    body.removeValue(forKey: "reasoning_history")

    if !thinking.isEmpty {
        body["thinking"] = .object(thinking)
    }

    if let value = body.removeValue(forKey: "reasoningEffort") {
        body["reasoning_effort"] = value
    }
    if body["reasoning_effort"] == nil, let reasoning = request.reasoning {
        switch reasoning {
        case "provider-default":
            break
        case "none":
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "reasoning \"none\" (use providerOptions.moonshotai.thinking to control thinking)"
            ))
        case "minimal", "low":
            body["reasoning_effort"] = .string("low")
        case "medium", "high":
            body["reasoning_effort"] = .string("high")
        case "xhigh", "max":
            body["reasoning_effort"] = .string("max")
        default:
            warnings.append(AIWarning(type: "unsupported", feature: "reasoning effort \(reasoning)"))
        }
    }

    if let value = body.removeValue(forKey: "promptCacheKey") {
        body["prompt_cache_key"] = value
    }
    if let options = body.removeValue(forKey: "promptCacheOptions")?.objectValue {
        body["prompt_cache_options"] = .object(["mode": options["mode"] ?? "implicit"].merging(options) { _, value in value })
    }
    if let value = body.removeValue(forKey: "safetyIdentifier") {
        body["safety_identifier"] = value
    }
    if let tools = body["tools"]?.arrayValue {
        body["tools"] = .array(try tools.map(moonshotNormalizeTool))
    }

    try moonshotStripTopLevelDollarSchema(from: &body)

    return body
}

func moonshotSupportsStructuredOutputs(modelID: String) -> Bool {
    true
}

func moonshotSupportsThinkingKeep(modelID: String) -> Bool {
    modelID == "kimi-k2.6" || ["kimi-k3", "kimi-k3.1-pro", "kimi-k3.1-pro-highspeed"].contains(modelID) || modelID.hasPrefix("kimi-k2.7-code")
}

func moonshotProviderOptions(from providerOptions: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    if let value = providerOptions["moonshotai"] {
        if value != .null {
            guard let nested = value.objectValue else {
                throw AIError.invalidArgument(argument: "providerOptions.moonshotai", message: "MoonshotAI provider options must be an object.")
            }
            output.merge(try moonshotValidateLanguageProviderOptions(nested, argumentPrefix: "providerOptions.moonshotai")) { _, providerValue in providerValue }
        }
    }
    if let value = providerOptions["moonshotAI"] {
        if value != .null {
            guard let nested = value.objectValue else {
                throw AIError.invalidArgument(argument: "providerOptions.moonshotAI", message: "MoonshotAI provider options must be an object.")
            }
            output.merge(try moonshotValidateLanguageProviderOptions(nested, argumentPrefix: "providerOptions.moonshotAI")) { _, providerValue in providerValue }
        }
    }
    return output
}

func moonshotValidateLanguageProviderOptions(_ options: [String: JSONValue], argumentPrefix: String) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    if let thinking = options["thinking"] {
        guard let thinkingObject = thinking.objectValue else {
            throw AIError.invalidArgument(argument: "\(argumentPrefix).thinking", message: "MoonshotAI thinking must be an object.")
        }
        var mappedThinking: [String: JSONValue] = [:]
        if let type = thinkingObject["type"] {
            guard let typeValue = type.stringValue, typeValue == "enabled" || typeValue == "disabled" else {
                throw AIError.invalidArgument(argument: "\(argumentPrefix).thinking.type", message: "MoonshotAI thinking.type must be enabled or disabled.")
            }
            mappedThinking["type"] = .string(typeValue)
        }
        if let budgetTokens = thinkingObject["budgetTokens"] {
            guard let number = budgetTokens.doubleValue, moonshotIsInteger(number), number >= 1024 else {
                throw AIError.invalidArgument(argument: "\(argumentPrefix).thinking.budgetTokens", message: "MoonshotAI thinking.budgetTokens must be an integer greater than or equal to 1024.")
            }
            mappedThinking["budgetTokens"] = .number(number)
        }
        output["thinking"] = .object(mappedThinking)
    }
    if let reasoningHistory = options["reasoningHistory"] {
        guard let value = reasoningHistory.stringValue,
              value == "disabled" || value == "interleaved" || value == "preserved" else {
            throw AIError.invalidArgument(argument: "\(argumentPrefix).reasoningHistory", message: "MoonshotAI reasoningHistory must be disabled, interleaved, or preserved.")
        }
        output["reasoningHistory"] = .string(value)
    }
    if let reasoningEffort = options["reasoningEffort"] {
        guard let value = reasoningEffort.stringValue,
              value == "low" || value == "high" || value == "max" else {
            throw AIError.invalidArgument(argument: "\(argumentPrefix).reasoningEffort", message: "MoonshotAI reasoningEffort must be low, high, or max.")
        }
        output["reasoningEffort"] = .string(value)
    }
    if let cache = options["promptCacheOptions"] {
        guard let values = cache.objectValue else {
            throw AIError.invalidArgument(argument: "\(argumentPrefix).promptCacheOptions", message: "MoonshotAI promptCacheOptions must be an object.")
        }
        var mapped: [String: JSONValue] = [:]
        if let mode = values["mode"] {
            guard mode == "implicit" else { throw AIError.invalidArgument(argument: "\(argumentPrefix).promptCacheOptions.mode", message: "MoonshotAI cache mode must be implicit.") }
            mapped["mode"] = mode
        }
        if let ttl = values["ttl"] {
            guard ttl == "5m" || ttl == "1h" else { throw AIError.invalidArgument(argument: "\(argumentPrefix).promptCacheOptions.ttl", message: "MoonshotAI cache ttl must be 5m or 1h.") }
            mapped["ttl"] = ttl
        }
        output["promptCacheOptions"] = .object(mapped)
    }
    for key in ["promptCacheKey", "safetyIdentifier"] {
        if let option = options[key] {
            guard let value = option.stringValue else {
                throw AIError.invalidArgument(argument: "\(argumentPrefix).\(key)", message: "MoonshotAI \(key) must be a string.")
            }
            output[key] = .string(value)
        }
    }
    return output
}

func moonshotIsInteger(_ value: Double) -> Bool {
    value.rounded(.towardZero) == value
}

private func moonshotStripTopLevelDollarSchema(from body: inout [String: JSONValue]) throws {
    guard var responseFormat = body["response_format"]?.objectValue,
          var jsonSchema = responseFormat["json_schema"]?.objectValue,
          let rawSchema = jsonSchema["schema"] else {
        return
    }
    var schema = rawSchema
    if var object = schema.objectValue {
        object.removeValue(forKey: "$schema")
        schema = .object(object)
    }
    jsonSchema["schema"] = try moonshotNormalizeJSONSchemaForMFJS(schema)
    responseFormat["json_schema"] = .object(jsonSchema)
    body["response_format"] = .object(responseFormat)
}

func moonshotChatUsage(from raw: JSONValue) -> TokenUsage? {
    guard let usage = raw["usage"] else { return TokenUsage() }
    let inputTokens = usage["prompt_tokens"]?.intValue ?? usage["input_tokens"]?.intValue ?? 0
    let outputTokens = usage["completion_tokens"]?.intValue ?? usage["output_tokens"]?.intValue ?? 0
    let cacheReadTokens = usage["cached_tokens"]?.intValue
        ?? usage["prompt_tokens_details"]?["cached_tokens"]?.intValue
        ?? 0
    let cacheWriteTokens = usage["prompt_tokens_details"]?["cache_write_tokens"]?.intValue
    let reasoningTokens = usage["completion_tokens_details"]?["reasoning_tokens"]?.intValue ?? 0
    let totalTokens = usage["total_tokens"]?.intValue ?? {
        return inputTokens + outputTokens
    }()
    return TokenUsage(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: totalTokens,
        inputTokensNoCache: inputTokens - cacheReadTokens - (cacheWriteTokens ?? 0),
        inputTokensCacheRead: cacheReadTokens,
        inputTokensCacheWrite: cacheWriteTokens,
        outputTextTokens: outputTokens - reasoningTokens,
        outputReasoningTokens: reasoningTokens,
        rawValue: usage
    )
}

func moonshotChatMessages(from messages: [AIMessage]) throws -> [JSONValue] {
    var output: [JSONValue] = []
    for message in messages {
        switch message.role {
        case .system:
            output.append(.object(["role": .string("system"), "content": .string(message.combinedText)]))
        case .user:
            if message.content.count == 1, case let .text(text, _) = message.content[0] {
                output.append(.object(["role": .string("user"), "content": .string(text)]))
            } else {
                output.append(.object([
                    "role": .string("user"),
                    "content": .array(try message.content.map(moonshotUserContentPart))
                ]))
            }
        case .assistant:
            let text = message.content.compactMap { part -> String? in
                if case let .text(value, _) = part { value } else { nil }
            }.joined()
            let reasoningParts = message.content.compactMap { part -> String? in
                if case let .reasoning(value, _) = part { value } else { nil }
            }
            let reasoning = ([message.reasoning].compactMap { $0 } + reasoningParts).joined()
            let toolCalls = message.content.compactMap { part -> AIToolCall? in
                if case let .toolCall(call) = part { call } else { nil }
            }
            var converted: [String: JSONValue] = [
                "role": .string("assistant"),
                "content": toolCalls.isEmpty ? .string(text) : (text.isEmpty ? .null : .string(text))
            ]
            if !reasoning.isEmpty {
                converted["reasoning_content"] = .string(reasoning)
            }
            if !toolCalls.isEmpty {
                converted["tool_calls"] = .array(toolCalls.map { call in
                    .object([
                        "id": .string(call.id),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string(call.name),
                            "arguments": .string(call.arguments)
                        ])
                    ])
                })
            }
            output.append(.object(converted))
        case .tool:
            for part in message.content {
                guard case let .toolResult(result) = part else { continue }
                output.append(.object([
                    "role": .string("tool"),
                    "tool_call_id": .string(result.toolCallID),
                    "content": .string(moonshotToolResultContent(result))
                ]))
            }
        }
    }
    return output
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

private func moonshotUserContentPart(_ part: AIContentPart) throws -> JSONValue {
    switch part {
    case let .text(text, _):
        return .object(["type": .string("text"), "text": .string(text)])
    case let .imageURL(url, _):
        return moonshotURLPart(type: "image_url", url: url)
    case let .data(mimeType, data, _), let .file(mimeType, data, _, _):
        if mimeType.hasPrefix("image/") {
            return moonshotURLPart(type: "image_url", url: "data:\(mimeType);base64,\(data.base64EncodedString())")
        }
        if mimeType.hasPrefix("video/") {
            return moonshotURLPart(type: "video_url", url: "data:\(mimeType);base64,\(data.base64EncodedString())")
        }
        if mimeType.hasPrefix("text/") {
            return .object(["type": .string("text"), "text": .string(String(decoding: data, as: UTF8.self))])
        }
        throw AIError.invalidArgument(argument: "messages", message: "MoonshotAI file part media type \(mimeType) is not supported.")
    case let .providerReference(mimeType, reference, _, _):
        let value = try resolveProviderReference(reference, provider: "moonshotai")
        if mimeType.hasPrefix("image/") {
            return moonshotURLPart(type: "image_url", url: value)
        }
        if mimeType.hasPrefix("video/") {
            return moonshotURLPart(type: "video_url", url: value)
        }
        throw AIError.invalidArgument(argument: "messages", message: "MoonshotAI file part media type \(mimeType) is not supported.")
    case .reasoning, .reasoningFile, .custom, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
        throw AIError.invalidArgument(argument: "messages", message: "MoonshotAI user content part is not supported.")
    }
}

private func moonshotURLPart(type: String, url: String) -> JSONValue {
    .object([
        "type": .string(type),
        type: .object(["url": .string(url)])
    ])
}

private func moonshotNormalizeTool(_ tool: JSONValue) throws -> JSONValue {
    guard var object = tool.objectValue,
          var function = object["function"]?.objectValue,
          let parameters = function["parameters"] else {
        return tool
    }
    function["parameters"] = try moonshotNormalizeJSONSchemaForMFJS(parameters)
    object["function"] = .object(function)
    return .object(object)
}

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
        object["prefixItems"] = .array(try existing + tuple.map {
            try moonshotNormalizeJSONSchemaForMFJS($0, isRoot: false)
        })
        object.removeValue(forKey: "items")
    } else if let items = object["items"] {
        object["items"] = try moonshotNormalizeJSONSchemaForMFJS(items, isRoot: false)
    }

    if !isRoot, let parentType = object["type"]?.stringValue, let anyOf = object["anyOf"]?.arrayValue {
        object.removeValue(forKey: "type")
        object["anyOf"] = .array(try anyOf.map { branch in
            guard var branchObject = branch.objectValue else {
                return try moonshotNormalizeJSONSchemaForMFJS(branch, isRoot: false)
            }
            if branchObject["type"] == nil {
                branchObject["type"] = .string(parentType)
            }
            return try moonshotNormalizeJSONSchemaForMFJS(.object(branchObject), isRoot: false)
        })
    }

    for key in ["allOf", "anyOf", "oneOf", "prefixItems"] {
        if let values = object[key]?.arrayValue {
            object[key] = .array(try values.map { try moonshotNormalizeJSONSchemaForMFJS($0, isRoot: false) })
        }
    }
    for key in ["properties", "patternProperties", "$defs", "definitions", "dependentSchemas"] {
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

func moonshotCacheWriteMetadata(headers: [String: String], namespace: String?) -> [String: JSONValue] {
    func tokenCount(_ name: String) -> Int? {
        guard let raw = headers.first(where: { $0.key.lowercased() == name })?.value else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        return Int(value)
    }
    let short = tokenCount("msh-usage-cache-write-tokens-5m")
    let long = tokenCount("msh-usage-cache-write-tokens-1h")
    guard short != nil || long != nil else { return [:] }
    return [namespace ?? "moonshotai": ["cacheWriteTokens": ["ttl5m": .number(Double(short ?? 0)), "ttl1h": .number(Double(long ?? 0))]]]
}
/// Installs the Moonshot wire policy on a shared compatible chat configuration.
public func configureMoonshotChat(_ configuration: inout OpenAICompatibleModelConfiguration) {
    configuration.toolCallsBeforeText = true
    configuration.responseHeaderMetadata = { moonshotCacheWriteMetadata(headers: $0, namespace: $1) }
    configuration.convertMessages = moonshotChatMessages
    configuration.supportsStructuredOutputForModel = moonshotSupportsStructuredOutputs
    configuration.usage = moonshotChatUsage
    configuration.prepareBody = { body, request, modelID, warnings in
        try moonshotChatBody(from: body, request: request, modelID: modelID, warnings: &warnings)
    }
}
