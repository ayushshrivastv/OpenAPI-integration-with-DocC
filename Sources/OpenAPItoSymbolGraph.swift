import Foundation
import OpenAPIKit
import ArgumentParser
import Yams
import SymbolKit

struct OpenAPItoSymbolGraph: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "openapi-to-symbolgraph",
        abstract: "Convert OpenAPI documents to DocC symbol graphs",
        version: "1.0.0"
    )

    @Argument(help: "Path to the OpenAPI document")
    var inputPath: String

    @Option(name: .long, help: "Output path for the symbol graph")
    var outputPath: String = "openapi.symbolgraph.json"

    func run() throws {
        let inputURL = URL(fileURLWithPath: inputPath)
        let data = try Data(contentsOf: inputURL)
        let fileExtension = inputURL.pathExtension.lowercased()

        // Parse the OpenAPI document manually to avoid version parsing issues
        var rawDict: [String: Any]
        
        do {
            if fileExtension == "json" {
                print("Parsing JSON...")
                guard let jsonDict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw RunError.parsingError("Failed to parse JSON as dictionary")
                }
                rawDict = jsonDict
            } else if fileExtension == "yaml" || fileExtension == "yml" {
                print("Parsing YAML...")
                let yamlString = String(data: data, encoding: .utf8)!
                guard let yamlDict = try Yams.load(yaml: yamlString) as? [String: Any] else {
                    throw RunError.parsingError("Failed to parse YAML as dictionary")
                }
                rawDict = yamlDict
            } else {
                throw RunError.invalidFileType("Unsupported file type: \(fileExtension). Please use .json or .yaml/.yml")
            }
        } catch {
            print("Error during initial parsing: \(error)")
            throw error
        }
        
        // Manually extract key information
        let infoDict = rawDict["info"] as? [String: Any] ?? [:]
        let title = infoDict["title"] as? String ?? "API"
        let description = infoDict["description"] as? String
        let _ = infoDict["version"] as? String ?? "1.0.0"
        
        // Extract paths and components
        let pathsDict = rawDict["paths"] as? [String: Any] ?? [:]
        let componentsDict = rawDict["components"] as? [String: Any] ?? [:]
        let schemasDict = componentsDict["schemas"] as? [String: Any] ?? [:]
        
        // --- Symbol graph generation logic ---
        var symbols: [SymbolKit.SymbolGraph.Symbol] = []
        var relationships: [SymbolKit.SymbolGraph.Relationship] = []

        // Add API namespace
        let apiSymbol = SymbolKit.SymbolGraph.Symbol(
            identifier: SymbolKit.SymbolGraph.Symbol.Identifier(
                precise: "s:API",
                interfaceLanguage: "swift"
            ),
            names: SymbolKit.SymbolGraph.Symbol.Names(
                title: title,
                navigator: nil,
                subHeading: nil,
                prose: description ?? title
            ),
            pathComponents: ["API"],
            docComment: SymbolKit.SymbolGraph.LineList([
                SymbolKit.SymbolGraph.LineList.Line(text: description ?? title, range: nil)
            ]),
            accessLevel: SymbolKit.SymbolGraph.Symbol.AccessControl(rawValue: "public"),
            kind: SymbolKit.SymbolGraph.Symbol.Kind(rawIdentifier: "swift.module", displayName: "Module"),
            mixins: [:]
        )
        symbols.append(apiSymbol)

        // Process paths
        print("Processing paths...")
        for (path, pathItemObj) in pathsDict {
            guard let pathItem = pathItemObj as? [String: Any] else { continue }
            
            // Process operations
            for (method, operationObj) in pathItem {
                // Skip non-HTTP methods like parameters
                if !["get", "post", "put", "delete", "options", "head", "patch", "trace"].contains(method.lowercased()) {
                    continue
                }
                
                guard let operation = operationObj as? [String: Any] else { continue }
                
                let operationId = operation["operationId"] as? String ?? "\(method)_\(path.replacingOccurrences(of: "/", with: "_"))"
                let summary = operation["summary"] as? String ?? "Operation \(operationId)"
                let operationDescription = operation["description"] as? String
                
                // Build documentation
                var documentation = summary
                if let desc = operationDescription {
                    documentation += "\n\n\(desc)"
                }
                documentation += "\n\nPath: \(path)"
                documentation += "\nMethod: \(method.uppercased())"
                
                // Tags
                if let tags = operation["tags"] as? [String] {
                    documentation += "\n\nTags: \(tags.joined(separator: ", "))"
                }
                
                // Deprecated
                if let deprecated = operation["deprecated"] as? Bool, deprecated {
                    documentation += "\n\n⚠️ This endpoint is deprecated."
                }
                
                // Create operation symbol
                let opSymbol = SymbolKit.SymbolGraph.Symbol(
                    identifier: SymbolKit.SymbolGraph.Symbol.Identifier(
                        precise: "f:API.\(operationId)",
                        interfaceLanguage: "swift"
                    ),
                    names: SymbolKit.SymbolGraph.Symbol.Names(
                        title: operationId,
                        navigator: nil,
                        subHeading: nil,
                        prose: documentation
                    ),
                    pathComponents: ["API", operationId],
                    docComment: SymbolKit.SymbolGraph.LineList([
                        SymbolKit.SymbolGraph.LineList.Line(text: documentation, range: nil)
                    ]),
                    accessLevel: SymbolKit.SymbolGraph.Symbol.AccessControl(rawValue: "public"),
                    kind: SymbolKit.SymbolGraph.Symbol.Kind(rawIdentifier: "swift.func", displayName: "Function"),
                    mixins: [:]
                )
                symbols.append(opSymbol)
                
                // Create relationship
                let operationRelationship = SymbolKit.SymbolGraph.Relationship(
                    source: "s:API",
                    target: "f:API.\(operationId)",
                    kind: .memberOf,
                    targetFallback: nil
                )
                relationships.append(operationRelationship)
            }
        }
        
        // Process schemas
        print("Processing schemas...")
        for (schemaName, schemaObj) in schemasDict {
            guard let schema = schemaObj as? [String: Any] else { continue }
            let schemaType = schema["type"] as? String
            let schemaDescription = schema["description"] as? String ?? "Schema for \(schemaName)"
            
            // Extract property information for documentation
            var propertyDocs = ""
            if schemaType == "object", let properties = schema["properties"] as? [String: Any] {
                let requiredProps = schema["required"] as? [String] ?? []
                
                if !requiredProps.isEmpty {
                    propertyDocs += "Required properties: \(requiredProps.joined(separator: ", "))\n"
                }
                
                for (propName, propObj) in properties {
                    guard let propDict = propObj as? [String: Any] else { continue }
                    let propType = propDict["type"] as? String ?? "any"
                    let propFormat = propDict["format"] as? String
                    let propDescription = propDict["description"] as? String
                    
                    let swiftType = mapJsonTypeToSwift(type: propType, format: propFormat)
                    propertyDocs += "\(propName): \(swiftType)"
                    if let desc = propDescription {
                        propertyDocs += " - \(desc)"
                    }
                    propertyDocs += "\n"
                }
            }
            
            // Create schema symbol
            let schemaSymbolId = "s:API.\(schemaName)"
            let fullSchemaDoc = "\(schemaDescription)\n\nType Information:\n\(propertyDocs)"
            
            let schemaSymbol = SymbolKit.SymbolGraph.Symbol(
                identifier: SymbolKit.SymbolGraph.Symbol.Identifier(
                    precise: schemaSymbolId,
                    interfaceLanguage: "swift"
                ),
                names: SymbolKit.SymbolGraph.Symbol.Names(
                    title: schemaName,
                    navigator: nil,
                    subHeading: nil,
                    prose: fullSchemaDoc
                ),
                pathComponents: ["API", schemaName],
                docComment: SymbolKit.SymbolGraph.LineList([
                    SymbolKit.SymbolGraph.LineList.Line(text: fullSchemaDoc, range: nil)
                ]),
                accessLevel: SymbolKit.SymbolGraph.Symbol.AccessControl(rawValue: "public"),
                kind: SymbolKit.SymbolGraph.Symbol.Kind(rawIdentifier: "swift.struct", displayName: "Structure"),
                mixins: [:]
            )
            symbols.append(schemaSymbol)
            
            // Create schema relationship
            let schemaRelationship = SymbolKit.SymbolGraph.Relationship(
                source: "s:API",
                target: schemaSymbolId,
                kind: .memberOf,
                targetFallback: nil
            )
            relationships.append(schemaRelationship)
            
            // Create property symbols if it's an object
            if schemaType == "object", let properties = schema["properties"] as? [String: Any] {
                for (propName, propObj) in properties {
                    guard let propDict = propObj as? [String: Any] else { continue }
                    let propType = propDict["type"] as? String ?? "any"
                    let propFormat = propDict["format"] as? String
                    let propDescription = propDict["description"] as? String ?? "Property \(propName)"
                    
                    let swiftType = mapJsonTypeToSwift(type: propType, format: propFormat)
                    let propId = "\(schemaSymbolId).\(propName)"
                    let propDoc = "\(propDescription)\n\nType Information:\n\(swiftType)"
                    
                    let propertySymbol = SymbolKit.SymbolGraph.Symbol(
                        identifier: SymbolKit.SymbolGraph.Symbol.Identifier(
                            precise: propId,
                            interfaceLanguage: "swift"
                        ),
                        names: SymbolKit.SymbolGraph.Symbol.Names(
                            title: propName,
                            navigator: nil,
                            subHeading: nil,
                            prose: propDoc
                        ),
                        pathComponents: ["API", schemaName, propName],
                        docComment: SymbolKit.SymbolGraph.LineList([
                            SymbolKit.SymbolGraph.LineList.Line(text: propDoc, range: nil)
                        ]),
                        accessLevel: SymbolKit.SymbolGraph.Symbol.AccessControl(rawValue: "public"),
                        kind: SymbolKit.SymbolGraph.Symbol.Kind(rawIdentifier: "swift.property", displayName: "Property"),
                        mixins: [:]
                    )
                    symbols.append(propertySymbol)
                    
                    // Create property relationship
                    let propRelationship = SymbolKit.SymbolGraph.Relationship(
                        source: schemaSymbolId,
                        target: propId,
                        kind: .memberOf,
                        targetFallback: nil
                    )
                    relationships.append(propRelationship)
                }
            }
        }

        // Create symbol graph
        let symbolGraph = SymbolKit.SymbolGraph(
             metadata: SymbolKit.SymbolGraph.Metadata(
                 formatVersion: SymbolKit.SymbolGraph.SemanticVersion(major: 1, minor: 0, patch: 0),
                 generator: "OpenAPItoSymbolGraph"
             ),
             module: SymbolKit.SymbolGraph.Module(
                 name: "API",
                 platform: SymbolKit.SymbolGraph.Platform(
                     architecture: nil,
                     vendor: nil,
                     operatingSystem: SymbolKit.SymbolGraph.OperatingSystem(name: "macosx")
                 )
             ),
             symbols: symbols,
             relationships: relationships
         )

         // Write symbol graph to file
         let outputURL = URL(fileURLWithPath: outputPath)
         let encoder = JSONEncoder()
         encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
         let symbolGraphData = try encoder.encode(symbolGraph)
         try symbolGraphData.write(to: outputURL)

         print("Symbol graph generated at \(outputURL.path)")
    }

    // Helper function to map JSON types to Swift types
    func mapJsonTypeToSwift(type: String, format: String?) -> String {
        switch type.lowercased() {
        case "string":
            if let format = format {
                switch format.lowercased() {
                case "date": return "Date"
                case "date-time": return "Date" 
                case "email": return "String"
                case "uri": return "URL"
                case "uuid": return "UUID"
                case "binary", "byte": return "Data"
                default: return "String"
                }
            }
            return "String"
            
        case "integer":
            if let format = format {
                switch format.lowercased() {
                case "int32": return "Int32"
                case "int64": return "Int64"
                default: return "Int"
                }
            }
            return "Int"
            
        case "number":
            if let format = format {
                switch format.lowercased() {
                case "float": return "Float"
                case "double": return "Double"
                default: return "Double"
                }
            }
            return "Double"
            
        case "boolean":
            return "Bool"
            
        case "array":
            return "[Any]" // A more robust solution would extract the items type
            
        case "object":
            return "[String: Any]"
            
        default:
            return "Any"
        }
    }

    // Define custom error
    enum RunError: Error, CustomStringConvertible {
        case invalidFileType(String)
        case parsingError(String) // Kept for potential future use

        var description: String {
            switch self {
            case .invalidFileType(let msg): return msg
            case .parsingError(let msg): return msg
            }
        }
    }
}

@main
struct OpenAPIToSymbolGraphMain {
    static func main() {
        OpenAPItoSymbolGraph.main()
    }
}