import Foundation
import OpenAPIKit
import SymbolKit

/// Represents the different types of symbols we can create from OpenAPI elements
enum OpenAPISymbolKind {
    case namespace
    case endpoint
    case parameter
    case requestBody
    case response
    case schema
    case property
    case securityScheme
    case server
    case tag
    case enumCase
    case typeAlias
}

/// Maps OpenAPI elements to SymbolKit symbol kinds
struct SymbolMapper {
    /// Maps OpenAPI schema types to Swift types with enhanced documentation
    static func mapSchemaType(_ schema: OpenAPIKit.JSONSchema) -> (type: String, documentation: String) {
        var documentation = ""
        
        // Add format information if available - only when non-empty
        if let format = schema.formatString, !format.isEmpty {
            documentation += "Format: \(format)\n"
        }
        
        // Handle specific schema contexts based on jsonType
        if let jsonType = schema.jsonType {
            switch jsonType {
            case .string:
                if let stringSchema = schema.stringContext {
                    if let pattern = stringSchema.pattern {
                        documentation += "Pattern: \(pattern)\n"
                    }
                    // Only add minLength if it's not the default value (0)
                    if stringSchema.minLength > 0 {
                        documentation += "Minimum length: \(stringSchema.minLength)\n"
                    }
                    if let maxLength = stringSchema.maxLength {
                        documentation += "Maximum length: \(maxLength)\n"
                    }
                }
                
            case .number:
                if let numContext = schema.numberContext {
                    if let minimum = numContext.minimum {
                        // Format without decimal points for whole numbers
                        let minValue = minimum.value
                        let formattedMin = minValue.truncatingRemainder(dividingBy: 1) == 0 ? 
                            String(format: "%.0f", minValue) : String(minValue)
                        documentation += "Minimum value: \(formattedMin)\(minimum.exclusive ? " (exclusive)" : "")\n"
                    }
                    if let maximum = numContext.maximum {
                        // Format without decimal points for whole numbers
                        let maxValue = maximum.value
                        let formattedMax = maxValue.truncatingRemainder(dividingBy: 1) == 0 ? 
                            String(format: "%.0f", maxValue) : String(maxValue)
                        documentation += "Maximum value: \(formattedMax)\(maximum.exclusive ? " (exclusive)" : "")\n"
                    }
                    if let multipleOf = numContext.multipleOf {
                        // Format without decimal points for whole numbers
                        let formattedMultiple = multipleOf.truncatingRemainder(dividingBy: 1) == 0 ? 
                            String(format: "%.0f", multipleOf) : String(multipleOf)
                        documentation += "Must be multiple of: \(formattedMultiple)\n"
                    }
                }
                
            case .integer:
                if let intContext = schema.integerContext {
                    if let minimum = intContext.minimum {
                        documentation += "Minimum value: \(minimum.value)\(minimum.exclusive ? " (exclusive)" : "")\n"
                    }
                    if let maximum = intContext.maximum {
                        documentation += "Maximum value: \(maximum.value)\(maximum.exclusive ? " (exclusive)" : "")\n"
                    }
                    if let multipleOf = intContext.multipleOf {
                        documentation += "Must be multiple of: \(multipleOf)\n"
                    }
                }
                
            case .array:
                if let arrayContext = schema.arrayContext {
                    // Only add minItems if it's not the default value (0)
                    if arrayContext.minItems > 0 {
                        documentation += "Minimum items: \(arrayContext.minItems)\n"
                    }
                    if let maxItems = arrayContext.maxItems {
                        documentation += "Maximum items: \(maxItems)\n"
                    }
                    // Format array items documentation to match test expectations
                    if let items = arrayContext.items {
                        let (itemType, itemDocs) = mapSchemaType(items)
                        if !itemDocs.isEmpty {
                            documentation += "Array items:\ntype: \(itemType)\n"
                        }
                    }
                }
                
            case .object:
                if let objectContext = schema.objectContext {
                    let requiredProps = objectContext.requiredProperties
                    if !requiredProps.isEmpty {
                        documentation += "Required properties: \(requiredProps.joined(separator: ", "))\n"
                    }
                }
                
            default:
                break
            }
        }
        
        let type: String
        if let jsonType = schema.jsonType {
            switch jsonType {
            case .string:
                if let format = schema.formatString {
                    switch format {
                    case "date": type = "Date"
                    case "date-time": type = "Date"
                    case "email": type = "String"
                    case "hostname": type = "String"
                    case "ipv4": type = "String"
                    case "ipv6": type = "String"
                    case "uri": type = "URL"
                    case "uuid": type = "UUID"
                    case "password": type = "String"
                    case "byte": type = "Data"
                    case "binary": type = "Data"
                    default: type = "String"
                    }
                } else {
                    type = "String"
                }
                
            case .number:
                if let format = schema.formatString {
                    switch format {
                    case "float": type = "Float"
                    case "double": type = "Double"
                    default: type = "Double"
                    }
                } else {
                    type = "Double"
                }
                
            case .integer:
                if let format = schema.formatString {
                    switch format {
                    case "int32": type = "Int32"
                    case "int64": type = "Int64"
                    default: type = "Int"
                    }
                } else {
                    type = "Int"
                }
                
            case .boolean:
                type = "Bool"
                
            case .array:
                if let arrayContext = schema.arrayContext, let items = arrayContext.items {
                    let (itemType, _) = mapSchemaType(items)
                    type = "[\(itemType)]"
                    // Nothing needed here - array items documentation is handled in the jsonType switch case
                } else {
                    type = "[Any]"
                }
                
            case .object:
                if let objectContext = schema.objectContext {
                    let properties = objectContext.properties
                    if !properties.isEmpty {
                        var propertyTypes: [String] = []
                        for (name, property) in properties {
                            let (propType, propDocs) = mapSchemaType(property)
                            propertyTypes.append("\(name): \(propType)")
                            if !propDocs.isEmpty {
                                documentation += "\(name):\n\(propDocs)"
                            }
                        }
                        type = "(\(propertyTypes.joined(separator: ", ")))"
                    } else {
                        type = "[String: Any]"
                    }
                } else {
                    type = "[String: Any]"
                }
                
            case .null:
                type = "Void?" // Or another appropriate representation for null
                documentation += "Null schema type.\n"
            
            }
        } else {
            type = "Any"
            documentation += "Unknown or unspecified schema type.\n"
        }
        
        // Add enum values if available
        if let allowedValues = schema.allowedValues, !allowedValues.isEmpty {
            let values = allowedValues.compactMap { $0.value as? CustomStringConvertible }
                                    .map { $0.description }
            if !values.isEmpty {
                documentation += "Allowed values: \(values.joined(separator: ", "))\n"
            }
        }
        
        return (type, documentation)
    }
    
    /// Creates a symbol for an OpenAPI element with enhanced documentation
    static func createSymbol(
        kind: OpenAPISymbolKind,
        identifier: String,
        title: String,
        description: String?,
        pathComponents: [String],
        parentIdentifier: String? = nil,
        additionalDocumentation: String? = nil
    ) -> (symbol: SymbolGraph.Symbol, relationship: SymbolGraph.Relationship?) {
        // Map OpenAPI symbol kind to SymbolKit kind
        let symbolKind: SymbolGraph.Symbol.Kind
        switch kind {
        case .namespace:
            symbolKind = SymbolGraph.Symbol.Kind(rawIdentifier: "swift.module", displayName: "Module")
        case .endpoint:
            symbolKind = SymbolGraph.Symbol.Kind(rawIdentifier: "swift.func", displayName: "Function")
        case .parameter:
            symbolKind = SymbolGraph.Symbol.Kind(rawIdentifier: "swift.var", displayName: "Parameter")
        case .requestBody:
            symbolKind = SymbolGraph.Symbol.Kind(rawIdentifier: "swift.struct", displayName: "Structure")
        case .response:
            symbolKind = SymbolGraph.Symbol.Kind(rawIdentifier: "swift.enum", displayName: "Enumeration")
        case .schema:
            symbolKind = SymbolGraph.Symbol.Kind(rawIdentifier: "swift.struct", displayName: "Structure")
        case .property:
            symbolKind = SymbolGraph.Symbol.Kind(rawIdentifier: "swift.property", displayName: "Property")
        case .securityScheme:
            symbolKind = SymbolGraph.Symbol.Kind(rawIdentifier: "swift.protocol", displayName: "Protocol")
        case .server:
            symbolKind = SymbolGraph.Symbol.Kind(rawIdentifier: "swift.struct", displayName: "Structure")
        case .tag:
            symbolKind = SymbolGraph.Symbol.Kind(rawIdentifier: "swift.enum", displayName: "Enumeration")
        case .enumCase:
            symbolKind = SymbolGraph.Symbol.Kind(rawIdentifier: "swift.enum.case", displayName: "Case")
        case .typeAlias:
            symbolKind = SymbolGraph.Symbol.Kind(rawIdentifier: "swift.typealias", displayName: "Type Alias")
        }
        
        // Combine documentation
        var fullDescription = description ?? title
        if let additional = additionalDocumentation {
            fullDescription += "\n\n\(additional)"
        }
        
        // Create the symbol
        let symbol = SymbolGraph.Symbol(
            identifier: SymbolGraph.Symbol.Identifier(
                precise: identifier,
                interfaceLanguage: "swift"
            ),
            names: SymbolGraph.Symbol.Names(
                title: title,
                navigator: nil,
                subHeading: nil,
                prose: fullDescription
            ),
            pathComponents: pathComponents,
            docComment: SymbolGraph.LineList([
                SymbolGraph.LineList.Line(text: fullDescription, range: nil)
            ]),
            accessLevel: SymbolGraph.Symbol.AccessControl(rawValue: "public"),
            kind: symbolKind,
            mixins: [:]
        )
        
        // Create relationship if parent is provided
        let relationship = parentIdentifier.map { parentId in
            SymbolGraph.Relationship(
                source: parentId,
                target: identifier,
                kind: .memberOf,
                targetFallback: nil
            )
        }
        
        return (symbol, relationship)
    }
    
    /// Creates a symbol for an OpenAPI operation with enhanced documentation
    static func createOperationSymbol(
        operation: OpenAPI.Operation,
        path: String,
        method: String
    ) -> (symbol: SymbolGraph.Symbol, relationships: [SymbolGraph.Relationship]) {
        var relationships: [SymbolGraph.Relationship] = []
        
        // Create operation symbol
        let operationId = operation.operationId ?? "\(method.lowercased())\(path.replacingOccurrences(of: "/", with: "_"))"
        let identifier = "f:API.\(operationId)"
        
        // Build comprehensive documentation
        var documentation = ""
        if let summary = operation.summary {
            documentation += "\(summary)\n\n"
        }
        if let desc = operation.description {
            documentation += "\(desc)\n\n"
        }
        documentation += "Path: \(path)\n"
        documentation += "Method: \(method)\n"
        
        // Add tags if available
        if let tags = operation.tags, !tags.isEmpty {
            documentation += "\nTags: \(tags.joined(separator: ", "))\n"
        }
        
        // Add deprecated information
        if operation.deprecated {
            documentation += "\n⚠️ This endpoint is deprecated.\n"
        }
        
        let (symbol, _) = createSymbol(
            kind: .endpoint,
            identifier: identifier,
            title: operationId,
            description: documentation,
            pathComponents: ["API", operationId]
        )
        
        // Add relationship to API namespace
        relationships.append(
            SymbolGraph.Relationship(
                source: "s:API",
                target: identifier,
                kind: .memberOf,
                targetFallback: nil
            )
        )
        
        return (symbol, relationships)
    }
    
    /// Creates symbols for an OpenAPI schema with enhanced documentation
    static func createSchemaSymbol(
        name: String,
        schema: OpenAPIKit.JSONSchema
    ) -> (symbols: [SymbolGraph.Symbol], relationships: [SymbolGraph.Relationship]) {
        var symbols: [SymbolGraph.Symbol] = []
        var relationships: [SymbolGraph.Relationship] = []
        
        // Create schema symbol
        let identifier = "s:API.\(name)"
        let (_, typeDocs) = mapSchemaType(schema)
        
        var documentation = schema.description ?? "Schema for \(name)"
        if !typeDocs.isEmpty {
            documentation += "\n\nType Information:\n\(typeDocs)"
        }
        
        let (schemaSymbol, schemaRelationship) = createSymbol(
            kind: .schema,
            identifier: identifier,
            title: name,
            description: documentation,
            pathComponents: ["API", name],
            parentIdentifier: "s:API"
        )
        
        symbols.append(schemaSymbol)
        if let relationship = schemaRelationship {
            relationships.append(relationship)
        }
        
        // Create property symbols if this is an object schema
        if schema.jsonType == .object, let objectContext = schema.objectContext {
            let properties = objectContext.properties
            for (propertyName, property) in properties {
                let propertyIdentifier = "\(identifier).\(propertyName)"
                let (_, propertyDocs) = mapSchemaType(property)

                var propertyDocumentation = property.description ?? "Property \(propertyName)"
                if !propertyDocs.isEmpty {
                    propertyDocumentation += "\n\nType Information:\n\(propertyDocs)"
                }
                
                // Special handling for array properties to include type information
                if property.jsonType == .array {
                    if let arrayContext = property.arrayContext, let items = arrayContext.items {
                        let (itemType, _) = mapSchemaType(items)
                        propertyDocumentation += "\nArray items:\ntype: \(itemType)\n"
                    }
                }

                let (propertySymbol, propertyRelationship) = createSymbol(
                    kind: .property,
                    identifier: propertyIdentifier,
                    title: propertyName,
                    description: propertyDocumentation,
                    pathComponents: ["API", name, propertyName],
                    parentIdentifier: identifier
                )

                symbols.append(propertySymbol)
                if let relationship = propertyRelationship {
                    relationships.append(relationship)
                }
            }
        }
        
        return (symbols, relationships)
    }
} 