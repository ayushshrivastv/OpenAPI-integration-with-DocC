// The Swift Programming Language
// https://docs.swift.org/swift-book
//Mit licence Copyright (c) 2024 Ayush Srivastava
import Foundation
import OpenAPIKit
import SymbolKit

//function to parse OpenAPI file
func parseOpenAPI(from filePath: String) throws -> OpenAPI.Document {
    let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
    let document = try JSONDecoder().decode(OpenAPI.Document.self, from: data)
    return document
}
//function to create SymbolGraph from OpenAPI document
func createSymbolGraph(from document: OpenAPI.Document) -> SymbolGraph {
    var symbols: [SymbolGraph.Symbol] = []
    var relationships: [SymbolGraph.Relationship] = []

    //maping schemas
    for (schemaName, _) in document.components.schemas {
        let structIdentifier = "s:\(schemaName.rawValue)"

        //created struct symbol for the schema
        let structSymbol = SymbolGraph.Symbol(
            identifier: SymbolGraph.Symbol.Identifier(
                precise: structIdentifier,
                interfaceLanguage: "swift"
            ),
            names: SymbolGraph.Symbol.Names(
                title: schemaName.rawValue,
                navigator: nil,
                subHeading: nil,
                prose: "Schema for \(schemaName.rawValue)"
            ),
            pathComponents: [schemaName.rawValue],
            docComment: nil,
            accessLevel: SymbolGraph.Symbol.AccessControl(rawValue: "public"),
            kind: SymbolGraph.Symbol.Kind(
                rawIdentifier: "swift.struct",
                displayName: "Structure"
            ),
            mixins: [:]
        )
        symbols.append(structSymbol)

        //we'll just create placeholder properties
        //we can extract properties from the schema
        let propertyNames = ["id", "name", "description"]
        for propertyName in propertyNames {
            let propertyIdentifier = "\(structIdentifier).\(propertyName)"

            let propertySymbol = SymbolGraph.Symbol(
                identifier: SymbolGraph.Symbol.Identifier(
                    precise: propertyIdentifier,
                    interfaceLanguage: "swift"
                ),
                names: SymbolGraph.Symbol.Names(
                    title: propertyName,
                    navigator: nil,
                    subHeading: nil,
                    prose: "Property \(propertyName)"
                ),
                pathComponents: [schemaName.rawValue, propertyName],
                docComment: nil,
                accessLevel: SymbolGraph.Symbol.AccessControl(rawValue: "public"),
                kind: SymbolGraph.Symbol.Kind(
                    rawIdentifier: "swift.property",
                    displayName: "Property"
                ),
                mixins: [:]
            )
            symbols.append(propertySymbol)

            relationships.append(
                SymbolGraph.Relationship(
                    source: structIdentifier,
                    target: propertyIdentifier,
                    kind: .memberOf,
                    targetFallback: nil
                ))
        }
    }
    //map operations
    for (path, _) in document.paths {
        //for simplicity, we'll just create a function for each path
        let operationId = "get\(path.rawValue.replacingOccurrences(of: "/", with: "_"))"
        let functionIdentifier = "f:\(operationId)"

        //create function symbol for the operation
        let functionSymbol = SymbolGraph.Symbol(
            identifier: SymbolGraph.Symbol.Identifier(
                precise: functionIdentifier,
                interfaceLanguage: "swift"
            ),
            names: SymbolGraph.Symbol.Names(
                title: operationId,
                navigator: nil,
                subHeading: nil,
                prose: "Operation for \(path.rawValue)"
            ),
            pathComponents: [operationId],
            docComment: nil,
            accessLevel: SymbolGraph.Symbol.AccessControl(rawValue: "public"),
            kind: SymbolGraph.Symbol.Kind(
                rawIdentifier: "swift.func",
                displayName: "Function"
            ),
            mixins: [:]
        )
        symbols.append(functionSymbol)

        //created placeholder parameters
        let paramNames = ["id", "query"]
        for paramName in paramNames {
            let paramIdentifier = "v:\(operationId).\(paramName)"

            let paramSymbol = SymbolGraph.Symbol(
                identifier: SymbolGraph.Symbol.Identifier(
                    precise: paramIdentifier,
                    interfaceLanguage: "swift"
                ),
                names: SymbolGraph.Symbol.Names(
                    title: paramName,
                    navigator: nil,
                    subHeading: nil,
                    prose: "Parameter \(paramName)"
                ),
                pathComponents: [operationId, paramName],
                docComment: nil,
                accessLevel: SymbolGraph.Symbol.AccessControl(rawValue: "public"),
                kind: SymbolGraph.Symbol.Kind(
                    rawIdentifier: "swift.var",
                    displayName: "Parameter"
                ),
                mixins: [:]
            )
            symbols.append(paramSymbol)

            relationships.append(
                SymbolGraph.Relationship(
                    source: functionIdentifier,
                    target: paramIdentifier,
                    kind: .memberOf,
                    targetFallback: nil
                ))
        }

        //created placeholder responses
        let responseEnumIdentifier = "e:\(operationId)Responses"
        let responseEnumSymbol = SymbolGraph.Symbol(
            identifier: SymbolGraph.Symbol.Identifier(
                precise: responseEnumIdentifier,
                interfaceLanguage: "swift"
            ),
            names: SymbolGraph.Symbol.Names(
                title: "\(operationId)Responses",
                navigator: nil,
                subHeading: nil,
                prose: "Possible responses for \(operationId)"
            ),
            pathComponents: ["\(operationId)Responses"],
            docComment: nil,
            accessLevel: SymbolGraph.Symbol.AccessControl(rawValue: "public"),
            kind: SymbolGraph.Symbol.Kind(
                rawIdentifier: "swift.enum",
                displayName: "Enumeration"
            ),
            mixins: [:]
        )
        symbols.append(responseEnumSymbol)

        //created placeholder response cases
        let statusCodes = ["200", "400", "500"]
        for statusCode in statusCodes {
            let caseIdentifier = "\(responseEnumIdentifier).\(statusCode)"
            let caseSymbol = SymbolGraph.Symbol(
                identifier: SymbolGraph.Symbol.Identifier(
                    precise: caseIdentifier,
                    interfaceLanguage: "swift"
                ),
                names: SymbolGraph.Symbol.Names(
                    title: statusCode,
                    navigator: nil,
                    subHeading: nil,
                    prose: "Response \(statusCode)"
                ),
                pathComponents: ["\(operationId)Responses", statusCode],
                docComment: nil,
                accessLevel: SymbolGraph.Symbol.AccessControl(rawValue: "public"),
                kind: SymbolGraph.Symbol.Kind(
                    rawIdentifier: "swift.enum.case",
                    displayName: "Case"
                ),
                mixins: [:]
            )
            symbols.append(caseSymbol)

            relationships.append(
                SymbolGraph.Relationship(
                    source: responseEnumIdentifier,
                    target: caseIdentifier,
                    kind: .memberOf,
                    targetFallback: nil
                ))
        }

        relationships.append(
            SymbolGraph.Relationship(
                source: functionIdentifier,
                target: responseEnumIdentifier,
                kind: .defaultImplementationOf,
                targetFallback: nil
            ))
    }

    //created the SymbolGraph
    let metadata = SymbolGraph.Metadata(
        formatVersion: SymbolGraph.SemanticVersion(major: 1, minor: 0, patch: 0),
        generator: "OpenAPItoSymbolGraph"
    )

    let module = SymbolGraph.Module(
        name: "API",
        platform: SymbolGraph.Platform(
            architecture: "x86_64",
            vendor: "apple",
            operatingSystem: .init(name: "macosx")
        )
    )

    let graph = SymbolGraph(
        metadata: metadata,
        module: module,
        symbols: symbols,
        relationships: relationships
    )

    return graph
}

//main execution
guard CommandLine.arguments.count > 1 else {
    print("Usage: openapi-to-symbolgraph <path-to-openapi.json>")
    exit(1)
}

let openAPIFilePath = CommandLine.arguments[1]

do {
    let openAPIDocument = try parseOpenAPI(from: openAPIFilePath)
    print("Successfully parsed OpenAPI file: \(openAPIFilePath)")

    let symbolGraph = createSymbolGraph(from: openAPIDocument)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted  // For readable JSON
    let jsonData = try encoder.encode(symbolGraph)
    try jsonData.write(to: URL(fileURLWithPath: "symbolgraph.json"))
    print("SymbolGraph saved to symbolgraph.json")
} catch {
    print("Error: \(error)")
    exit(1)
}
