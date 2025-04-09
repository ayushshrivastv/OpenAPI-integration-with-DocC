# OpenAPI to DocC Symbol Graph

A tool to convert OpenAPI documents into DocC symbol graphs, enabling seamless integration of API documentation with Swift's DocC documentation system.

## Features

- Converts OpenAPI documents (JSON/YAML) to DocC symbol graphs
- Supports all HTTP methods (GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS)
- Generates comprehensive documentation for:
  - API endpoints
  - Request parameters
  - Request bodies
  - Response types
- Preserves OpenAPI descriptions and metadata
- Command-line interface for easy integration

## Installation

### Requirements

- Swift 5.7 or later
- macOS 12.0 or later

### Building from Source

1. Clone the repository:
```bash
git clone https://github.com/yourusername/OpenAPItoSymbolGraph.git
cd OpenAPItoSymbolGraph
```

2. Build the package:
```bash
swift build -c release
```

3. The executable will be available at `.build/release/openapi-to-symbolgraph`

## Usage

```bash
openapi-to-symbolgraph <input-path> [--output-directory <directory>] [--output-file <filename>]
```

### Arguments

- `input-path`: Path to the OpenAPI document (JSON or YAML)
- `--output-directory`: Directory where the symbol graph will be saved (default: current directory)
- `--output-file`: Name of the output file (default: openapi.symbolgraph.json)

### Example

```bash
openapi-to-symbolgraph api.yaml --output-directory docs --output-file api.symbolgraph.json
```

## Integration with DocC

1. Generate the symbol graph:
```bash
openapi-to-symbolgraph api.yaml
```

2. Add the symbol graph to your DocC documentation:
```swift
import DocC

let documentation = Documentation(
    symbolGraphs: ["openapi.symbolgraph.json"]
)
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
