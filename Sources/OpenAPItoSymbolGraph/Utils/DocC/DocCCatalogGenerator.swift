import Foundation
import OpenAPI
import DocC
import Integration
import SymbolKit

// Helper function to get the schema type from JSONSchema
private func getSchemaType(_ schema: JSONSchema) -> String {
    switch schema {
    case .string: return "string"
    case .number: return "number"
    case .integer: return "integer"
    case .boolean: return "boolean"
    case .array: return "array"
    case .object: return "object"
    case .reference: return "reference"
    case .allOf: return "allOf"
    case .anyOf: return "anyOf"
    case .oneOf: return "oneOf"
    case .not: return "not"
    }
}

// Helper function to format a value for display
private func formatValue(_ value: Any) -> String {
    return String(describing: value)
}

// Helper function to format examples
private func formatExamples(examples: [String: Any]) -> String {
    var result = "Examples:\n"
    for (name, example) in examples {
        result += "### \(name)\n```\n\(formatValue(example))\n```\n\n"
    }
    return result
}

// Helper function to format a single example
private func formatExample(_ example: Any) -> String {
    return "Example:\n```\n\(formatValue(example))\n```\n\n"
}

/// A generator for DocC catalog files from OpenAPI documents
public struct DocCCatalogGenerator {
    /// The name to use for the module
    private let moduleName: String?
    /// Base URL for the API
    private let baseURL: URL?
    /// Output directory where the .docc catalog will be created
    private let outputDirectory: URL
    /// Whether to include examples in the documentation
    private let includeExamples: Bool

    /// Creates a new DocC catalog generator
    /// - Parameters:
    ///   - moduleName: The name to use for the module. If nil, the info.title from the OpenAPI document will be used
    ///   - baseURL: The base URL to use for the API
    ///   - outputDirectory: The directory where the .docc catalog will be created
    ///   - includeExamples: Whether to include examples in the documentation
    public init(moduleName: String? = nil, baseURL: URL? = nil, outputDirectory: URL, includeExamples: Bool = false) {
        self.moduleName = moduleName
        self.baseURL = baseURL
        self.outputDirectory = outputDirectory
        self.includeExamples = includeExamples
    }

    /// Generates a DocC catalog from an OpenAPI document
    /// - Parameters:
    ///   - document: The OpenAPI document to generate documentation from
    ///   - overwrite: Whether to overwrite existing files
    /// - Returns: The path to the generated .docc catalog
    /// - Throws: An error if the generation fails
    public func generateCatalog(from document: Document, overwrite: Bool = false) throws -> URL {
        // Create the catalog directory
        let catalogName = (moduleName ?? document.info.title)
            .replacingOccurrences(of: " ", with: "")
        let catalogDirectory = outputDirectory.appendingPathComponent("\(catalogName).docc")

        // Check if the catalog already exists
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: catalogDirectory.path) {
            if overwrite {
                try fileManager.removeItem(at: catalogDirectory)
            } else {
                throw CatalogGenerationError.catalogAlreadyExists(catalogDirectory.path)
            }
        }

        // Create the catalog directory
        try fileManager.createDirectory(at: catalogDirectory, withIntermediateDirectories: true)

        // Generate the root documentation file (ModuleName.md)
        try generateRootDocumentationFile(document: document, catalogDirectory: catalogDirectory)

        // Generate the symbol graph file
        try generateSymbolGraphFile(document: document, catalogDirectory: catalogDirectory)

        // Generate documentation files for endpoints
        try generateEndpointDocumentationFiles(document: document, catalogDirectory: catalogDirectory)

        // Generate documentation files for schemas
        try generateSchemaDocumentationFiles(document: document, catalogDirectory: catalogDirectory)

        return catalogDirectory
    }

    /// Resolves a reference in the OpenAPI document
    /// - Parameters:
    ///   - reference: The reference to resolve
    ///   - document: The OpenAPI document to resolve references in
    /// - Returns: The resolved schema, or nil if the reference could not be resolved
    private func resolveReference(_ reference: String, in document: Document) -> JSONSchema? {
        // Check if the reference is a schema reference
        if reference.hasPrefix("#/components/schemas/") {
            let schemaName = reference.replacingOccurrences(of: "#/components/schemas/", with: "")
            return document.components?.schemas?[schemaName]
        }
        // Add support for other reference types as needed
        return nil
    }

    /// Finds all schemas that reference the given schema
    /// - Parameters:
    ///   - schemaName: The name of the schema to find references to
    ///   - document: The OpenAPI document to search in
    /// - Returns: A dictionary mapping schema names to properties that reference the given schema
    private func findReferencesToSchema(_ schemaName: String, in document: Document) -> [String: [String]] {
        guard let components = document.components, let schemas = components.schemas else {
            return [:]
        }

        var references: [String: [String]] = [:]

        for (name, schema) in schemas {
            // Skip the schema itself
            if name == schemaName {
                continue
            }

            // Check if this schema has properties that reference our target schema
            if case .object(let objectSchema) = schema {
                for (propertyName, propertySchema) in objectSchema.properties {
                    if case .reference(let reference) = propertySchema {
                        if reference.ref == "#/components/schemas/\(schemaName)" {
                            references[name, default: []].append(propertyName)
                        }
                    }

                    // Check for arrays of references
                    if case .array(let arraySchema) = propertySchema {
                        if case .reference(let reference) = arraySchema.items {
                            if reference.ref == "#/components/schemas/\(schemaName)" {
                                references[name, default: []].append(propertyName)
                            }
                        }
                    }
                }
            }

            // Check for arrays that contain items of our target schema
            if case .array(let arraySchema) = schema {
                if case .reference(let reference) = arraySchema.items {
                    if reference.ref == "#/components/schemas/\(schemaName)" {
                        references[name, default: []].append("items")
                    }
                }
            }
        }

        return references
    }

    /// Generates the root documentation file for the catalog
    private func generateRootDocumentationFile(document: Document, catalogDirectory: URL) throws {
        let moduleTitle = moduleName ?? document.info.title
        let fileName = moduleTitle.replacingOccurrences(of: " ", with: "")
        let filePath = catalogDirectory.appendingPathComponent("\(fileName).md")

        var content = "# \(moduleTitle)\n\n"

        if let description = document.info.description {
            content += "\(description)\n\n"
        }

        // Add overview section
        content += "## Overview\n\n"

        // Count endpoints by tag or path
        var endpointsByTag: [String: Int] = [:]
        for (_, pathItem) in document.paths {
            for (method, operation) in pathItem.allOperations() {
                if let tags = operation.tags, !tags.isEmpty {
                    for tag in tags {
                        endpointsByTag[tag, default: 0] += 1
                    }
                } else {
                    endpointsByTag["Other", default: 0] += 1
                }
            }
        }

        // Add endpoint counts by tag
        for (tag, count) in endpointsByTag.sorted(by: { $0.key < $1.key }) {
            content += "- \(tag): \(count) endpoints\n"
        }
        content += "\n"

        // Add schema counts
        if let components = document.components, let schemas = components.schemas {
            content += "- \(schemas.count) data models\n\n"
        }

        // Add topics section with links to endpoints and schemas
        content += "## Topics\n\n"

        // Group endpoints by tag
        var endpointLinksByTag: [String: [String]] = [:]
        for (path, pathItem) in document.paths {
            for (method, operation) in pathItem.allOperations() {
                let operationId = operation.operationId ?? "\(method.rawValue)_\(path)"
                let sanitizedPath = operationId.replacingOccurrences(of: "/", with: "_")
                                            .replacingOccurrences(of: "{", with: "")
                                            .replacingOccurrences(of: "}", with: "")

                if let tags = operation.tags, !tags.isEmpty {
                    for tag in tags {
                        endpointLinksByTag[tag, default: []].append("- ``\(sanitizedPath)``")
                    }
                } else {
                    endpointLinksByTag["Endpoints", default: []].append("- ``\(sanitizedPath)``")
                }
            }
        }

        // Add endpoint links by tag
        for (tag, links) in endpointLinksByTag.sorted(by: { $0.key < $1.key }) {
            content += "### \(tag)\n\n"
            content += links.joined(separator: "\n") + "\n\n"
        }

        // Add schema links
        if let components = document.components, let schemas = components.schemas {
            content += "### Data Models\n\n"
            for (name, _) in schemas.sorted(by: { $0.key < $1.key }) {
                content += "- ``\(name)``\n"
            }
            content += "\n"
        }

        // Add documentation metadata
        if let version = document.info.version {
            content += "## Version\n\n"
            content += "Current version: \(version)\n\n"
        }

        if let contact = document.info.contact {
            content += "## Contact\n\n"
            if let name = contact.name {
                content += "- Name: \(name)\n"
            }
            if let email = contact.email {
                content += "- Email: \(email)\n"
            }
            if let url = contact.url {
                content += "- URL: \(url)\n"
            }
            content += "\n"
        }

        // Write the file
        try content.write(to: filePath, atomically: true, encoding: .utf8)
    }

    /// Generates a symbol graph file from the OpenAPI document
    private func generateSymbolGraphFile(document: Document, catalogDirectory: URL) throws {
        let converter = OpenAPIDocCConverter(moduleName: moduleName, baseURL: baseURL)
        let symbolGraph = converter.convert(document)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(symbolGraph)

        let fileName = (moduleName ?? document.info.title)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        let filePath = catalogDirectory.appendingPathComponent("\(fileName).symbols.json")
        try jsonData.write(to: filePath)
    }

    /// Generates documentation files for endpoints
    private func generateEndpointDocumentationFiles(document: Document, catalogDirectory: URL) throws {
        // Create the directory for endpoint documentation
        let endpointsDirectory = catalogDirectory.appendingPathComponent("Endpoints")
        try FileManager.default.createDirectory(at: endpointsDirectory, withIntermediateDirectories: true)

        // Generate a file for each endpoint
        for (path, pathItem) in document.paths {
            for (method, operation) in pathItem.allOperations() {
                let operationId = operation.operationId ?? "\(method.rawValue)_\(path)"
                let sanitizedPath = operationId.replacingOccurrences(of: "/", with: "_")
                                            .replacingOccurrences(of: "{", with: "")
                                            .replacingOccurrences(of: "}", with: "")

                let filePath = endpointsDirectory.appendingPathComponent("\(sanitizedPath).md")

                var content = "# \(method.rawValue.uppercased()) \(path)\n\n"

                if let summary = operation.summary {
                    content += "\(summary)\n\n"
                }

                if let description = operation.description {
                    content += "\(description)\n\n"
                }

                // Add parameters section
                if let parameters = operation.parameters, !parameters.isEmpty {
                    content += "## Parameters\n\n"

                    for parameter in parameters {
                        content += "### \(parameter.name)\n\n"

                        if let description = parameter.description {
                            content += "\(description)\n\n"
                        }
                    }

                    // Examples are not supported in the current MediaType model
                    /* if let examples = mediaTypeContent.examples {
                        content += formatExamples(examples: examples)
                    } else if let example = mediaTypeContent.example {
                        content += formatExample(example)
                    } */
                }

                // Add responses section
                if !operation.responses.isEmpty {
                    content += "## Responses\n\n"

                    for (statusCode, response) in operation.responses.sorted(by: { $0.key < $1.key }) {
                        content += "### \(statusCode)\n\n"
                        content += "\(response.description)\n\n"

                        if let contentDict = response.content {
                            for (mediaType, mediaTypeContent) in contentDict {
                                content += "#### Media Type: \(mediaType)\n\n"

                                switch mediaTypeContent.schema {
                                case .reference(let reference):
                                    let schemaName = reference.ref.components(separatedBy: "/").last ?? reference.ref
                                    content += "**Schema: ``\(schemaName)``**\n\n"

                                    // If possible, resolve the reference and add brief information
                                    if let resolvedSchema = resolveReference(reference.ref, in: document) {
                                        content += "Summary of `\(schemaName)`:\n\n"
                                        if let description = resolvedSchema.description {
                                            content += "\(description)\n\n"
                                        }
                                    }

                                case .array(let arraySchema):
                                    content += "**Schema type: Array**\n\n"
                                    content += "Items type: "

                                    switch arraySchema.items {
                                    case .reference(let reference):
                                        let refName = reference.ref.components(separatedBy: "/").last ?? reference.ref
                                        content += "``\(refName)``\n\n"

                                        // If possible, add brief info about the referenced type
                                        if let resolvedSchema = resolveReference(reference.ref, in: document) {
                                            content += "Summary of `\(refName)`:\n\n"
                                            if let description = resolvedSchema.description {
                                                content += "\(description)\n\n"
                                            }
                                        }

                                    case .string:
                                        content += "string\n\n"
                                    case .number:
                                        content += "number\n\n"
                                    case .integer:
                                        content += "integer\n\n"
                                    case .boolean:
                                        content += "boolean\n\n"
                                    case .array:
                                        content += "array (nested)\n\n"
                                    case .object:
                                        content += "object\n\n"
                                    case .allOf, .anyOf, .oneOf, .not:
                                        content += "complex type\n\n"
                                    }

                                case .object:
                                    content += "**Schema type: Object**\n\n"

                                    if case .object(let objectSchema) = mediaTypeContent.schema, !objectSchema.properties.isEmpty {
                                        content += "Properties:\n\n"
                                        for (propName, propSchema) in objectSchema.properties.sorted(by: { $0.key < $1.key }) {
                                            if case .reference(let reference) = propSchema {
                                                let refName = reference.ref.components(separatedBy: "/").last ?? reference.ref
                                                content += "- `\(propName)`: ``\(refName)``\n"
                                            } else {
                                                content += "- `\(propName)`: \(describeType(propSchema))\n"
                                            }
                                        }
                                    }

                                    content += "\n"

                                default:
                                    content += "**Schema type: \(describeType(mediaTypeContent.schema))**\n\n"
                                }

                                // Examples are not supported in the current MediaType model
                                /* if let examples = mediaTypeContent.examples {
                                    content += formatExamples(examples: examples)
                                } else if let example = mediaTypeContent.example {
                                    content += formatExample(example)
                                } */
                            }
                        }
                    }
                }

                // Add security information if available
                if let security = operation.security, !security.isEmpty {
                    content += "## Security\n\n"

                    for securityRequirement in security {
                        for (scheme, scopes) in securityRequirement {
                            content += "### \(scheme)\n\n"

                            if !scopes.isEmpty {
                                content += "Required scopes:\n\n"
                                for scope in scopes {
                                    content += "- \(scope)\n"
                                }
                            }

                            content += "\n"
                        }
                    }
                }

                // Write the file
                try content.write(to: filePath, atomically: true, encoding: .utf8)
            }
        }
    }

    // Implement missing generateSchemaDocumentationFiles method
    private func generateSchemaDocumentationFiles(document: Document, catalogDirectory: URL) throws {
        // Create the directory for schema documentation
        let schemasDirectory = catalogDirectory.appendingPathComponent("Schemas")
        try FileManager.default.createDirectory(at: schemasDirectory, withIntermediateDirectories: true)

        // Generate a file for each schema
        guard let components = document.components, let schemas = components.schemas else {
            return // No schemas to document
        }

        for (name, schema) in schemas {
            let filePath = schemasDirectory.appendingPathComponent("\(name).md")

            var content = "# \(name)\n\n"

            if let description = schema.description {
                content += "\(description)\n\n"
            }

            // Add schema type information
            content += "**Type: \(getSchemaType(schema))**\n\n"

            // Add properties section for object schemas
            if case .object(let objectSchema) = schema {
                content += "## Properties\n\n"

                for (propertyName, propertySchema) in objectSchema.properties.sorted(by: { $0.key < $1.key }) {
                    content += "### \(propertyName)\n\n"

                    if let description = propertySchema.description {
                        content += "\(description)\n\n"
                    }

                    let isRequired = objectSchema.required.contains(propertyName)
                    content += "**Type: \(describeType(propertySchema))**\n\n"
                    content += "**Required: \(isRequired ? "Yes" : "No")**\n\n"

                    // Add examples if they exist and includeExamples is true
                    if includeExamples, let example = getSchemaExample(propertySchema) {
                        content += formatExample(example)
                    }
                }
            }

            // Add related schemas section (schemas that reference this one)
            let referencingSchemas = findReferencesToSchema(name, in: document)
            if !referencingSchemas.isEmpty {
                content += "## Referenced By\n\n"

                for (schemaName, properties) in referencingSchemas.sorted(by: { $0.key < $1.key }) {
                    content += "- ``\(schemaName)``"
                    if !properties.isEmpty {
                        content += " (properties: \(properties.joined(separator: ", ")))"
                    }
                    content += "\n"
                }

                content += "\n"
            }

            // Write the file
            try content.write(to: filePath, atomically: true, encoding: .utf8)
        }
    }

    private func describeType(_ schema: JSONSchema) -> String {
        switch schema {
        case .string:
            return "string"
        case .number:
            return "number"
        case .integer:
            return "integer"
        case .boolean:
            return "boolean"
        case .array(let arraySchema):
            switch arraySchema.items {
            case .reference(let reference):
                let refName = reference.ref.components(separatedBy: "/").last ?? reference.ref
                return "array of ``\(refName)``"
            default:
                return "array of \(describeType(arraySchema.items))"
            }
        case .object:
            return "object"
        case .reference(let reference):
            let refName = reference.ref.components(separatedBy: "/").last ?? reference.ref
            return "``\(refName)``"
        case .allOf:
            return "allOf"
        case .anyOf:
            return "anyOf"
        case .oneOf:
            return "oneOf"
        case .not:
            return "not"
        }
    }

    /// Extracts and formats examples for documentation
    private func formatExamples(examples: [String: OpenAPIKit.OpenAPI.Example]?) -> String {
        guard let examples = examples, !examples.isEmpty else {
            return ""
        }

        var result = "## Examples\n\n"

        for (name, apiExample) in examples {
            // Convert to our compatible Example type
            let example = OpenAPIKit.OpenAPI.Example(from: apiExample)
            result += "### \(name)\n\n"

            if let summary = example.summary {
                result += "\(summary)\n\n"
            }

            if let description = example.description {
                result += "\(description)\n\n"
            }

            if let externalValue = example.externalValue {
                result += "External value: \(externalValue)\n\n"
            } else if let value = example.value {
                // Format the example value as JSON
                result += "```json\n\(formatValue(value))\n```\n\n"
            }
        }

        return result
    }

    /// Formats a generic value for display in documentation
    private func formatValue(_ value: Any?) -> String {
        guard let value = value else {
            return "null"
        }

        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }

        // Fallback if the value is not valid JSON
        return String(describing: value)
    }

    /// Formats a single example for documentation
    private func formatExample(_ example: Any?) -> String {
        guard let example = example else {
            return ""
        }

        return "## Example\n\n```json\n\(formatValue(example))\n```\n\n"
    }
}

// Helper function to get example from schema if available
private func getSchemaExample(_ schema: JSONSchema) -> Any? {
    switch schema {
    case .string(let stringSchema):
        return stringSchema.example
    case .number(let numberSchema):
        return numberSchema.example
    case .integer(let integerSchema):
        return integerSchema.example
    case .boolean(let booleanSchema):
        return booleanSchema.example
    case .array(let arraySchema):
        return arraySchema.example
    case .object(let objectSchema):
        return objectSchema.example
    case .reference(let reference):
        // No direct example available for references
        return nil
    case .allOf, .anyOf, .oneOf, .not:
        // These complex types don't have direct examples
        return nil
    }
}

/// Errors that can occur during catalog generation
public enum CatalogGenerationError: Error {
    case catalogAlreadyExists(String)
    case failedToCreateDirectory(String)
    case failedToWriteFile(String)
}
