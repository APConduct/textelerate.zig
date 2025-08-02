const std = @import("std");

const Allocator = std.mem.Allocator;

const Error = @import("error.zig").TemplateError;

const Vec = std.ArrayList;
const print = std.debug.print;

/// A template engine that supports runtime and compile-time template parsing.
///
/// The template syntax uses double curly braces for variables: {{variable_name}}
///
/// Example usage:
/// ```zig
/// var template = Template.init(allocator, "Hello {{name}}!");
/// try template.compile();
/// const result = try template.render_to_string(context, allocator);
/// ```
pub const Template = struct {
    source: []const u8,
    compiled: ?Compiled = null,
    allocator: std.mem.Allocator,

    /// Internal compiled representation of a template.
    /// Contains parsed fragments and variable information.
    const Compiled = struct {
        fragments: []Fragment,
        vars: []Variable,
        allocator: Allocator,

        pub fn deinit(self: Compiled) void {
            self.allocator.free(self.fragments);
            for (self.vars) |variable| {
                self.allocator.free(variable.name);
            }
            self.allocator.free(self.vars);
        }
    };

    /// A fragment represents either static text or a variable placeholder.
    const Fragment = union(enum) {
        text: []const u8, // Static text content
        variable: u32, // Index into the variables array
    };

    /// Variable metadata containing the variable name.
    const Variable = struct { name: []const u8 };

    /// Initialize a new template with the given source string.
    /// The template must be compiled before it can be rendered.
    pub fn init(allocator: Allocator, source: []const u8) Template {
        return Template{ .source = source, .allocator = allocator };
    }

    /// Clean up any allocated memory used by the template.
    pub fn deinit(self: *Template) void {
        if (self.compiled) |compiled| {
            compiled.deinit();
        }
    }

    /// Compile the template for runtime rendering.
    /// This parses the template and prepares it for efficient rendering.
    pub fn compile(self: *Template) !void {
        self.compiled = try Template.parse_template(self.source, self.allocator);
    }

    /// Render the template with the given context to a writer.
    /// The context must be a struct with fields matching the template variables.
    pub fn render(self: *Template, ctx: anytype, writer: anytype) !void {
        const compiled = self.compiled orelse return Error.NotCompiled;

        for (compiled.fragments) |fragment| {
            switch (fragment) {
                .text => |text| try writer.writeAll(text),
                .variable => |idx| {
                    const var_name = compiled.vars[idx].name;

                    // Use reflection to check for field and get value
                    const type_info = @typeInfo(@TypeOf(ctx));
                    if (type_info != .@"struct") {
                        return Error.MissingVar;
                    }

                    var found = false;

                    inline for (type_info.@"struct".fields) |field| {
                        if (std.mem.eql(u8, field.name, var_name)) {
                            const val = @field(ctx, field.name);
                            found = true;
                            if (@TypeOf(val) == []const u8) {
                                try writer.writeAll(val);
                            } else {
                                try writer.print("{any}", .{val});
                            }
                            break;
                        }
                    }

                    if (!found) {
                        return Error.MissingVar;
                    }
                },
            }
        }
    }

    /// Render the template to a newly allocated string.
    /// The caller is responsible for freeing the returned string.
    pub fn render_to_string(self: *Template, ctx: anytype, allocator: Allocator) ![]u8 {
        var buffer = Vec(u8).init(allocator);
        try self.render(ctx, buffer.writer());
        return buffer.toOwnedSlice();
    }

    /// Parse a template source string into compiled fragments and variables.
    /// This is used internally for runtime template compilation.
    fn parse_template(source: []const u8, allocator: Allocator) !Template.Compiled {
        var fragments = Vec(Template.Fragment).init(allocator);
        var variables = Vec(Template.Variable).init(allocator);

        var i: usize = 0;
        var txt_start: usize = 0;

        while (i < source.len) {
            if (i + 1 < source.len and source[i] == '{' and source[i + 1] == '{') {
                // Add any text before this variable
                if (i > txt_start) {
                    try fragments.append(.{ .text = source[txt_start..i] });
                }

                // Find the end of the variable
                const var_start = i + 2;
                var var_end = var_start;

                // Look for closing }}
                while (var_end + 1 < source.len) {
                    if (source[var_end] == '}' and source[var_end + 1] == '}') {
                        break;
                    }
                    var_end += 1;
                } else {
                    return Error.InvalidSyntax;
                }

                // Extract variable name (trim whitespace)
                const var_name = std.mem.trim(u8, source[var_start..var_end], " \t\n\r");

                // Check if variable already exists
                var var_idx: u32 = 0;
                var found = false;
                for (variables.items, 0..) |variable, idx| {
                    if (std.mem.eql(u8, variable.name, var_name)) {
                        var_idx = @intCast(idx);
                        found = true;
                        break;
                    }
                }

                // Add new variable if not found
                if (!found) {
                    var_idx = @intCast(variables.items.len);
                    const owned_name = try allocator.dupe(u8, var_name);
                    try variables.append(.{ .name = owned_name });
                }

                try fragments.append(.{ .variable = var_idx });

                i = var_end + 2; // Skip past }}
                txt_start = i;
            } else {
                i += 1;
            }
        }
        if (txt_start < source.len) {
            try fragments.append(.{ .text = source[txt_start..] });
        }

        return Template.Compiled{
            .fragments = try fragments.toOwnedSlice(),
            .vars = try variables.toOwnedSlice(),
            .allocator = allocator,
        };
    }

    /// Compile a template at compile-time for optimal performance.
    /// Returns a type that can render the template efficiently.
    /// Variable existence is checked at compile-time.
    fn compile_template(comptime template_str: []const u8) type {
        const frags = parse_template_comptime(template_str);

        return struct {
            /// Render the compile-time template with the given context.
            /// All variable checks are performed at compile-time.
            pub fn render(ctx: anytype, writer: anytype) !void {
                inline for (frags) |frag| {
                    switch (frag.tag) {
                        .text => try writer.writeAll(frag.data),
                        .variable => {
                            // Use compile-time reflection to check if field exists
                            const type_info = @typeInfo(@TypeOf(ctx));
                            if (type_info != .@"struct") {
                                @compileError("Context must be a struct");
                            }

                            comptime var found = false;
                            inline for (type_info.@"struct".fields) |field| {
                                if (comptime std.mem.eql(u8, field.name, frag.data)) {
                                    const value = @field(ctx, field.name);
                                    if (@TypeOf(value) == []const u8) {
                                        try writer.writeAll(value);
                                    } else {
                                        try writer.print("{any}", .{value});
                                    }
                                    found = true;
                                    break;
                                }
                            }
                            if (!found) {
                                @compileError("Variable '" ++ frag.data ++ "' not found in context");
                            }
                        },
                    }
                }
            }
        };
    }

    const ComptimeFragment = struct { tag: enum { text, variable }, data: []const u8 };

    fn parse_template_comptime(comptime template_str: []const u8) []const ComptimeFragment {
        comptime {
            var fragments: []const ComptimeFragment = &[_]ComptimeFragment{};

            var i: usize = 0;
            var txt_start: usize = 0;

            while (i < template_str.len) {
                if (i + 1 < template_str.len and template_str[i] == '{' and template_str[i + 1] == '{') {
                    // Add any text before this variable
                    if (i > txt_start) {
                        fragments = fragments ++ [_]ComptimeFragment{.{ .tag = .text, .data = template_str[txt_start..i] }};
                    }

                    // Find the end of the variable
                    const var_start = i + 2;
                    var var_end = var_start;

                    // Look for closing }}
                    while (var_end + 1 < template_str.len) {
                        if (template_str[var_end] == '}' and template_str[var_end + 1] == '}') {
                            break;
                        }
                        var_end += 1;
                    } else {
                        @compileError("Unclosed variable in template");
                    }

                    // Extract variable name (trim whitespace)
                    const var_name = std.mem.trim(u8, template_str[var_start..var_end], " \t\n\r");
                    if (var_name.len == 0) {
                        @compileError("Empty variable name in template");
                    }

                    fragments = fragments ++ [_]ComptimeFragment{.{ .tag = .variable, .data = var_name }};

                    i = var_end + 2; // Skip past }}
                    txt_start = i;
                } else {
                    i += 1;
                }
            }

            // Add any remaining text
            if (txt_start < template_str.len) {
                fragments = fragments ++ [_]ComptimeFragment{.{ .tag = .text, .data = template_str[txt_start..] }};
            }

            return fragments;
        }
    }
};

/// Create a compile-time optimized template from a string literal.
/// This provides better performance than runtime templates as all parsing
/// and variable validation is done at compile-time.
///
/// Example:
/// ```zig
/// const MyTemplate = compileTemplate("Hello {{name}}!");
/// try MyTemplate.render(context, writer);
/// ```
pub fn compileTemplate(comptime template_str: []const u8) type {
    return Template.compile_template(template_str);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    print("=== Textelerate Template Engine Demo ===\n", .{});

    // Runtime template example
    print("\n1. Runtime Template Example:\n", .{});
    const template_source = "Hello {{name}}, welcome to {{place}}!";
    var template = Template.init(allocator, template_source);
    defer template.deinit();

    try template.compile();

    const RuntimeContext = struct {
        name: []const u8,
        place: []const u8,
    };

    const runtime_ctx = RuntimeContext{
        .name = "Alice",
        .place = "Zig Land",
    };

    const result = try template.render_to_string(runtime_ctx, allocator);
    defer allocator.free(result);
    print("Result: {s}\n", .{result});

    // Compile-time template example
    print("\n2. Compile-time Template Example:\n", .{});
    const CompiledTemplate = compileTemplate("{{greeting}} {{name}}! You have {{count}} messages.");

    const CompileTimeContext = struct {
        greeting: []const u8,
        name: []const u8,
        count: u32,
    };

    const compile_ctx = CompileTimeContext{
        .greeting = "Hi",
        .name = "Bob",
        .count = 42,
    };

    var buffer = Vec(u8).init(allocator);
    defer buffer.deinit();

    try CompiledTemplate.render(compile_ctx, buffer.writer());
    print("Result: {s}\n", .{buffer.items});

    print("\nDemo complete! Run `zig test src/main.zig` to see all tests.\n", .{});
}

test "basic template functionality" {
    const allocator = std.testing.allocator;

    const template_source = "Hello {{name}}, you are {{age}} years old!";
    var template = Template.init(allocator, template_source);
    defer template.deinit();

    try template.compile();

    const Context = struct {
        name: []const u8,
        age: u32,
    };

    const context = Context{
        .name = "Alice",
        .age = 25,
    };

    const result = try template.render_to_string(context, allocator);
    defer allocator.free(result);

    const expected = "Hello Alice, you are 25 years old!";
    try std.testing.expectEqualStrings(expected, result);
}

test "template with writer" {
    const allocator = std.testing.allocator;

    var template = Template.init(allocator, "Hi {{user}}!");
    defer template.deinit();

    try template.compile();

    const Context = struct {
        user: []const u8,
    };

    var buffer = Vec(u8).init(allocator);
    defer buffer.deinit();

    try template.render(Context{ .user = "Bob" }, buffer.writer());

    try std.testing.expectEqualStrings("Hi Bob!", buffer.items);
}

test "missing variable error" {
    const allocator = std.testing.allocator;

    var template = Template.init(allocator, "Hello {{missing}}!");
    defer template.deinit();

    try template.compile();

    const Context = struct {
        name: []const u8,
    };

    const context = Context{ .name = "Test" };

    var buffer = Vec(u8).init(allocator);
    defer buffer.deinit();

    const result = template.render(context, buffer.writer());
    try std.testing.expectError(Error.MissingVar, result);
}

test "compile-time template basic functionality" {
    const allocator = std.testing.allocator;

    const CompiledTemplate = Template.compile_template("Hello {{name}}, you are {{age}} years old!");

    const Context = struct {
        name: []const u8,
        age: u32,
    };

    const context = Context{
        .name = "Alice",
        .age = 25,
    };

    var buffer = Vec(u8).init(allocator);
    defer buffer.deinit();

    try CompiledTemplate.render(context, buffer.writer());

    const expected = "Hello Alice, you are 25 years old!";
    try std.testing.expectEqualStrings(expected, buffer.items);
}

test "compile-time template with only text" {
    const allocator = std.testing.allocator;

    const CompiledTemplate = Template.compile_template("This is just plain text with no variables.");

    const Context = struct {};
    const context = Context{};

    var buffer = Vec(u8).init(allocator);
    defer buffer.deinit();

    try CompiledTemplate.render(context, buffer.writer());

    const expected = "This is just plain text with no variables.";
    try std.testing.expectEqualStrings(expected, buffer.items);
}

test "compile-time template with multiple variables" {
    const allocator = std.testing.allocator;

    const CompiledTemplate = Template.compile_template("{{greeting}} {{name}}! Today is {{day}} and it's {{weather}}.");

    const Context = struct {
        greeting: []const u8,
        name: []const u8,
        day: []const u8,
        weather: []const u8,
    };

    const context = Context{
        .greeting = "Hello",
        .name = "World",
        .day = "Monday",
        .weather = "sunny",
    };

    var buffer = Vec(u8).init(allocator);
    defer buffer.deinit();

    try CompiledTemplate.render(context, buffer.writer());

    const expected = "Hello World! Today is Monday and it's sunny.";
    try std.testing.expectEqualStrings(expected, buffer.items);
}
