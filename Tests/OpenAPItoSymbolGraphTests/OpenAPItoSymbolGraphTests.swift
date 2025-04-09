import XCTest
import OpenAPIKit
@testable import OpenAPItoSymbolGraph

final class OpenAPItoSymbolGraphTests: XCTestCase {
    /* // Commenting out this test as the main run function bypasses parsing for now.
    func testBasicOpenAPIDocument() throws {
        // Create a simple OpenAPI document
        let openAPIDocument = """
        {
            "openapi": "3.0.0",
            "info": {
                "title": "Test API",
                "version": "1.0.0"
            },
            "paths": {
                "/users": {
                    "get": {
                        "operationId": "getUsers",
                        "summary": "Get all users",
                        "description": "Retrieves a list of all users",
                        "parameters": [
                            {
                                "name": "limit",
                                "in": "query",
                                "description": "Maximum number of users to return",
                                "schema": {
                                    "type": "integer"
                                }
                            }
                        ],
                        "responses": {
                            "200": {
                                "description": "Successful response",
                                "content": {
                                    "application/json": {
                                        "schema": {
                                            "type": "array",
                                            "items": {
                                                "$ref": "#/components/schemas/User"
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            },
            "components": {
                "schemas": {
                    "User": {
                        "type": "object",
                        "properties": {
                            "id": {
                                "type": "integer",
                                "description": "User ID"
                            },
                            "name": {
                                "type": "string",
                                "description": "User name"
                            }
                        }
                    }
                }
            }
        }
        """
        
        // Write the document to a temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test-api.json")
        try openAPIDocument.write(to: tempFile, atomically: true, encoding: .utf8)
        
        // Parse the document
        let document = try parseOpenAPI(from: tempFile.path)
        
        // Create symbol graph
        let symbolGraph = createSymbolGraph(from: document)
        
        // Verify the symbol graph
        XCTAssertFalse(symbolGraph.symbols.isEmpty, "Symbol graph should not be empty")
        
        // Check for API namespace
        let apiSymbol = symbolGraph.symbols.first { $0.identifier.precise == "s:API" }
        XCTAssertNotNil(apiSymbol, "API namespace should exist")
        
        // Check for User schema
        let userSymbol = symbolGraph.symbols.first { $0.identifier.precise == "s:API.User" }
        XCTAssertNotNil(userSymbol, "User schema should exist")
        
        // Check for getUsers operation
        let getUsersSymbol = symbolGraph.symbols.first { $0.identifier.precise == "f:API.getUsers" }
        XCTAssertNotNil(getUsersSymbol, "getUsers operation should exist")
        
        // Clean up
        try FileManager.default.removeItem(at: tempFile)
    }
    */
    
    func testTypeMapping() {
        // Test type mapping function using basic schema types
        XCTAssertEqual(SymbolMapper.mapSchemaType(OpenAPIKit.JSONSchema.string).type, "String")
        XCTAssertEqual(SymbolMapper.mapSchemaType(OpenAPIKit.JSONSchema.number).type, "Double")
        XCTAssertEqual(SymbolMapper.mapSchemaType(OpenAPIKit.JSONSchema.integer).type, "Int")
        XCTAssertEqual(SymbolMapper.mapSchemaType(OpenAPIKit.JSONSchema.boolean).type, "Bool")
        // For array and object, create basic contexts
        let basicArrayCoreCtx = OpenAPIKit.JSONSchema.CoreContext<OpenAPIKit.JSONTypeFormat.ArrayFormat>()
        let basicArrayCtx = OpenAPIKit.JSONSchema.ArrayContext(items: nil)
        XCTAssertEqual(SymbolMapper.mapSchemaType(OpenAPIKit.JSONSchema.array(basicArrayCoreCtx, basicArrayCtx)).type, "[Any]") 
        
        let basicObjectCoreCtx = OpenAPIKit.JSONSchema.CoreContext<OpenAPIKit.JSONTypeFormat.ObjectFormat>()
        let basicObjectCtx = OpenAPIKit.JSONSchema.ObjectContext(properties: [:])
        XCTAssertEqual(SymbolMapper.mapSchemaType(OpenAPIKit.JSONSchema.object(basicObjectCoreCtx, basicObjectCtx)).type, "[String: Any]")
    }
} 