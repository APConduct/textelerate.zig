# Textelerate

A fast and efficient template engine for Zig that supports both runtime and compile-time template compilation.

## Features

- **Runtime Templates**: Parse and render templates at runtime with dynamic content
- **Compile-time Templates**: Zero-cost template compilation with compile-time variable validation
- **Simple Syntax**: Uses `{{variable}}` syntax for variable interpolation
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
const compileTemplate = @import("textelerate").compileTemplate;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    // Create compile-time template (zero runtime cost for parsing)
    const MyTemplate = compileTemplate("Welcome {{name}} to {{place}}!");
    
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
- Variables can contain letters, numbers, and underscores
- Whitespace around variable names is ignored: `{{ name }}` is the same as `{{name}}`

### Examples

```
Hello {{name}}!
{{greeting}} {{first_name}} {{last_name}}, you have {{message_count}} messages.
Welcome to {{place}}, the temperature is {{temperature}}°C.
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

### compileTemplate (Compile-time)

#### `compileTemplate(comptime template_str: []const u8) type`
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

```bash
# Run tests
zig test src/main.zig

# Run demo
zig run src/main.zig

# Build as library
zig build-lib src/main.zig
```

## Examples

See the `main()` function in `src/main.zig` for complete working examples.

## License

This project is available under the MIT license.

## Contributing

Contributions are welcome! Please ensure all tests pass before submitting a pull request.
