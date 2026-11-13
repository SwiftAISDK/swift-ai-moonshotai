import Foundation
import Testing
@testable import SwiftAIMoonshotAI
import SwiftAIProvider

@Suite("Weekly20261114 Moonshot MFJS traversal")
struct Weekly20261114TraversalTests {
    @Test(arguments: [false, true])
    func nestedArraysNormalizeOnceWithoutMutatingInput(_ tuple: Bool) throws {
        let leaf: JSONValue = ["type": "object", "properties": ["label": ["type": "string", "anyOf": [["minLength": 1], ["const": ""]]]]]
        let row: JSONValue = ["type": "array", "items": leaf]
        let schema: JSONValue = ["type": "object", "properties": ["rows": ["type": "array", "items": tuple ? .array([row]) : row]]]
        let normalized = try moonshotNormalizeJSONSchemaForMFJS(schema)
        let result = tuple ? normalized["properties"]?["rows"]?["prefixItems"]?[0] : normalized["properties"]?["rows"]?["items"]
        #expect(result?["items"]?["properties"]?["label"] == ["anyOf": [["type": "string", "minLength": 1], ["type": "string", "const": ""]]])
        #expect(leaf["properties"]?["label"]?["type"] == "string")
        #expect(schema["properties"]?["rows"]?["items"] == (tuple ? .array([row]) : row))
    }
    @Test func existingPrefixAndTupleKeepPositionalOrderAndBooleans() throws {
        let schema: JSONValue = ["type": "object", "properties": ["row": ["type": "array", "prefixItems": [["type": "string", "anyOf": [["minLength": 1]]], true], "items": [["type": "array", "items": [["type": "number"], false]]]], "flags": ["type": "array", "items": false]]]
        let result = try moonshotNormalizeJSONSchemaForMFJS(schema)
        #expect(result["properties"]?["row"]?["prefixItems"] == [["anyOf": [["type": "string", "minLength": 1]]], true, ["type": "array", "prefixItems": [["type": "number"], false]]])
        #expect(result["properties"]?["flags"]?["items"] == false)
    }
}
