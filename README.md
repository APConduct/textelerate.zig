# Textelerate

[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](https://github.com/APConduct/textelerate/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/APConduct/textelerate/blob/main/LICENSE)
[![Tests](https://img.shields.io/badge/tests-18%20passing-brightgreen.svg)](https://github.com/APConduct/textelerate/actions)
[![Zig](https://img.shields.io/badge/zig-0.14.1+-orange.svg)](https://ziglang.org/)

A fast and efficient template engine for Zig that supports both runtime and compile-time template compilation.

## Version

Current version: **0.1.0**

This project follows [Semantic Versioning](https://semver.org/):
- **MAJOR** version when you make incompatible API changes
- **MINOR** version when you add functionality in a backwards compatible manner
- **PATCH** version when you make backwards compatible bug fixes

## Features

- **Runtime Templates**: Parse and render templates at runtime with dynamic content
- **Compile-time Templates**: Zero-cost template compilation with compile-time variable validation
- **Simple Syntax**: Uses `{{variable}}` syntax for variable interpolation
- **Filter System**: Transform variables with filters like `{{name | uppercase}}`, `{{text | lowercase}}`
- **Escape Sequences**: Support for literal braces using backslash escaping (`\{\{`, `\}\}`, `\\`)
- **Type Safety**: Full compile-time type checking for template variables
- **Memory Efficient**: Minimal allocations and proper memory management
- **No Dependencies**: Pure Zig implementation with no external dependencies

## Quick Start

### Runtime Templates

```zig
const std = @import("std");
const Template = @import("textelerate").Template;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create and compile template
    var template = Template.init(allocator, "Hello {{name}}, you are {{age}} years old!");
    defer template.deinit();
    try template.compile();

    // Define context
    const Context = struct {
        name: []const u8,
        age: u32,
    };

    const context = Context{
        .name = "Alice",
        .age = 25,
    };

    // Render template
    const result = try template.render_to_string(context, allocator);
    defer allocator.free(result);

    std.debug.print("{s}\n", .{result}); // Output: Hello Alice, you are 25 years old!
}
```

### Compile-time Templates

```zig
const std = @import("std");
const compile_template = @import("textelerate").compile_template;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create compile-time template (zero runtime cost for parsing)
    const MyTemplate = compile_template("Welcome {{name}} to {{place}}!");

    const Context = struct {
        name: []const u8,
        place: []const u8,
    };

    const context = Context{
        .name = "Bob",
        .place = "Zig Land",
    };

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try MyTemplate.render(context, buffer.writer());
    std.debug.print("{s}\n", .{buffer.items}); // Output: Welcome Bob to Zig Land!
}
```

## Template Syntax

Textelerate uses a simple syntax with double curly braces:

- `{{variable}}` - Insert a variable value
- `{{variable | filter}}` - Apply a filter to transform the variable
- `{{variable | filter1 | filter2}}` - Chain multiple filters
- `{{#if condition}}...{{/if}}` - Conditional blocks
- `{{#if condition}}...{{else}}...{{/if}}` - Conditional blocks with else
- `{{#for item in collection}}...{{/for}}` - Loop over collections
- Variables can contain letters, numbers, and underscores
- Whitespace around variable names is ignored: `{{ name }}` is the same as `{{name}}`
- Use backslash escaping for literal braces: `\{\{` for `{{`, `\}\}` for `}}`, `\\` for `\`

### Filters

Transform variable values using the pipe (`|`) syntax:

- `{{name | uppercase}}` - Convert text to uppercase
- `{{name | lowercase}}` - Convert text to lowercase
- `{{name | filter1 | filter2}}` - Chain multiple filters

#### Available Filters

- **uppercase**: Converts text to uppercase letters
- **lowercase**: Converts text to lowercase letters

### Control Flow

Control the flow of template rendering with conditional blocks and loops:

- `{{#if variable}}content{{/if}}` - Render content if variable is truthy
- `{{#if variable}}content{{else}}fallback{{/if}}` - Conditional with else block
- `{{#for item in collection}}{{item}}{{/for}}` - Loop over collection items

#### Conditional Blocks

```
{{#if user_logged_in}}
  Welcome back, {{username}}!
{{else}}
  Please log in to continue.
{{/if}}
```

#### Loop Blocks

```
{{#for product in products}}
  Product: {{product}}
{{/for}}
```

### Escape Sequences

To include literal `{{` and `}}` in your templates, use backslash escaping:

- `\{\{` renders as literal `{{`
- `\}\}` renders as literal `}}`
- `\\` renders as literal `\`

### Examples

```
Hello {{name}}!
{{greeting}} {{first_name}} {{last_name}}, you have {{message_count}} messages.
Welcome to {{place}}, the temperature is {{temperature}}°C.
Filtered: {{name | uppercase}} and {{greeting | lowercase}}
{{#if show_welcome}}Welcome {{name}}!{{else}}Please sign up{{/if}}
{{#for item in items}}Item: {{item}} {{/for}}
Use \{\{ and \}\} for literal braces: \{\{not_a_variable\}\}
Backslash example: \\
```

## API Reference

### Template (Runtime)

#### `Template.init(allocator: Allocator, source: []const u8) Template`
Creates a new template with the given source string.

#### `template.compile() !void`
Compiles the template for rendering. Must be called before `render()`.

#### `template.render(ctx: anytype, writer: anytype) !void`
Renders the template with the given context to a writer.

#### `template.render_to_string(ctx: anytype, allocator: Allocator) ![]u8`
Renders the template to a newly allocated string. Caller must free the result.

#### `template.deinit() void`
Cleans up allocated memory.

### compile_template (Compile-time)

#### `compile_template(comptime template_str: []const u8) type`
Creates a compile-time optimized template. Returns a type with a `render()` method.

The returned type has:
- `render(ctx: anytype, writer: anytype) !void` - Renders the template

## Error Handling

Textelerate provides comprehensive error handling:

- `TemplateError.NotCompiled` - Template hasn't been compiled yet
- `TemplateError.ParseError` - Invalid template syntax
- `TemplateError.MissingVar` - Variable not found in context
- `TemplateError.InvalidSyntax` - Malformed template syntax
- `Allocator.Error` - Memory allocation errors

## Performance

### Runtime Templates
- Fast compilation with single-pass parsing
- Efficient rendering with minimal allocations
- Variable lookup optimized with pre-compiled indices

### Compile-time Templates
- Zero runtime parsing cost
- Compile-time variable validation
- Optimal code generation
- Type-safe variable access

## Building and Testing

**Requirements**: Zig 0.14.1 or later

```bash
# Run tests
zig test src/main.zig

# Run demo
zig run src/main.zig

# Build as library
zig build-lib src/main.zig

# Local CI/CD testing (fast)
./scripts/quick-test.sh quick

# Full local CI simulation
./scripts/quick-test.sh full
```

## Local Testing

Textelerate includes comprehensive local testing tools to validate your changes before pushing to GitHub:

### Quick Testing (Recommended)
```bash
# Fast smoke test (30 seconds)
./scripts/quick-test.sh quick

# Full CI simulation (3-5 minutes)
./scripts/quick-test.sh full

# Individual components
./scripts/quick-test.sh test        # Run test suite
./scripts/quick-test.sh format      # Check formatting
./scripts/quick-test.sh security    # Security checks
```

### Docker-based Testing with act
```bash
# Install act (GitHub Actions local runner)
brew install act  # macOS

# List available workflows
act --list

# Run specific job
act --job test --platform ubuntu-latest=catthehacker/ubuntu:act-latest

# Run full CI workflow
act --workflows .github/workflows/ci.yml
```

**See [LOCAL_TESTING.md](LOCAL_TESTING.md) for complete testing guide.**

## Examples

See the `main()` function in `src/main.zig` for complete working examples.

## License

This project is available under the MIT license.

## Development Roadmap

### ✅ Completed Features

- **Basic Template Parsing**: Variable interpolation with `{{variable}}` syntax
- **Runtime Templates**: Dynamic template compilation and rendering
- **Compile-time Templates**: Zero-cost template compilation with validation
- **Escape Sequences**: Support for literal braces (`\{\{`, `\}\}`, `\\`)
- **Filter System**: Variable transformation with `{{name | filter}}` syntax
  - `uppercase` - Convert text to uppercase
  - `lowercase` - Convert text to lowercase
  - Filter chaining support with `{{name | filter1 | filter2}}`
- **Template Inheritance**: Partial template inclusion
  - `{{> partial}}` - Include partial templates
  - Simplified partial loading system
- **Enhanced Error Reporting**: Line/column number tracking and detailed error messages
  - Position-aware error reporting
  - Descriptive error messages for common issues
  - Graceful error handling with proper cleanup
  - Memory leak prevention in error cases
  - Comprehensive error test coverage
- **Control Flow**: Advanced conditional and loop constructs
  - `{{#if condition}}...{{/if}}` - Conditional blocks
  - `{{#if condition}}...{{else}}...{{/if}}` - Conditional blocks with else
  - `{{#for item in collection}}...{{/for}}` - Loop constructs
  - Proper variable scoping within loops
  - Block content parsing and rendering
  - Memory-safe block management

### 🚧 Partially Implemented

- **Advanced Loop Variables**: Basic loop functionality complete, advanced variables planned
  - `{{@index}}`, `{{@first}}`, `{{@last}}` - Loop position variables (architecture ready)
  - Complex nested loop and conditional combinations (architecture ready)
- **Nested Control Flow**: Single-level blocks working, deep nesting planned
  - `{{#if outer}}{{#if inner}}...{{/if}}{{/if}}` - Multi-level nesting (foundation complete)

### 💡 Future Enhancements

- **Advanced Loop Variables**: `{{@index}}`, `{{@first}}`, `{{@last}}`, `{{@even}}`, `{{@odd}}`
- **Complex Nested Control Flow**: Deep nesting support for complex templates
- **Template Caching**: Compiled template caching system
- **Async Template Loading**: Support for async partial loading from files
- **Custom Delimiters**: Configurable template syntax
- **Additional Filters**: More built-in transformation filters
  - `trim` - Remove whitespace
  - `length` - Get string/array length
  - `capitalize` - Capitalize first letter
  - `date` - Date formatting filters
  - Custom filter registration system
- **Template Debugging**: Debug mode with detailed execution tracing
- **Performance Optimizations**: Further runtime and compile-time optimizations
- **Complex Conditionals**: `{{#if var1 && var2}}` with logical operators

## Current Status

**All 18 tests passing** ✅

The template engine now includes:
- ✅ **Variable interpolation** with filters and chaining
- ✅ **Escape sequences** for literal braces
- ✅ **Partial templates** with recursive loading
- ✅ **Error reporting** with line/column tracking and proper error handling
- ✅ **Memory management** with proper cleanup and leak prevention
- ✅ **Advanced control flow** with if/else blocks and for loops
- ✅ **Conditional else blocks** for complete branching logic

## Contributing

Contributions are welcome! Please ensure all tests pass before submitting a pull request.

### Development Guidelines

1. All new features should include comprehensive tests
2. Maintain compatibility with existing API
3. Follow Zig coding conventions
4. Update documentation for new features
5. Ensure memory safety and proper cleanup
6. Handle all error cases with appropriate cleanup
7. Maintain zero memory leaks in all code paths

### Architecture Notes

- Advanced control flow parsing infrastructure is complete
- Else block parsing and rendering fully implemented
- Filter system is extensible for additional transformations
- Partial loading system can be enhanced for file-based templates
- Error handling system provides comprehensive coverage
- Memory management ensures leak-free operation
- All 18 tests passing with full coverage of implemented features
- Control flow blocks working with proper variable scoping
- Memory-safe block parsing and rendering with else support
- Foundation ready for nested control flow and loop variables
