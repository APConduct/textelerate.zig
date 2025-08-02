const std = @import("std");

const Allocator = std.mem.Allocator;

const Error = @import("error.zig").TemplateError;
const DetailedError = @import("error.zig").DetailedError;
const Position = @import("error.zig").Position;

const Vec = std.ArrayList;
const print = std.debug.print;

/// A template engine that supports runtime and compile-time template parsing.
///
/// The template syntax uses double curly braces for variables: {{variable_name}}
/// Supports escaping: \{\{ for literal {{, \}\} for literal }}, \\ for literal \
/// Non-escapable characters after \ are treated as literal text
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
            // Free text fragments that were allocated for escape sequences
            for (self.fragments) |fragment| {
                if (fragment == .text) {
                    self.allocator.free(fragment.text);
                } else if (fragment == .variable) {
                    // Free filter names and filter arrays
                    for (fragment.variable.filters) |filter| {
                        self.allocator.free(filter.name);
                    }
                    if (fragment.variable.filters.len > 0) {
                        self.allocator.free(fragment.variable.filters);
                    }
                }
            }
            self.allocator.free(self.fragments);
            for (self.vars) |variable| {
                self.allocator.free(variable.name);
            }
            self.allocator.free(self.vars);
        }
    };

    /// A fragment represents different types of template content
    const Fragment = union(enum) {
        text: []const u8, // Static text content
        variable: VariableRef, // Variable with optional filters
    };

    /// Variable reference with optional filters
    const VariableRef = struct {
        var_index: u32, // Index into the variables array
        filters: []Filter,
    };

    /// Variable metadata containing the variable name.
    const Variable = struct { name: []const u8 };

    /// Filter definition
    const Filter = struct {
        name: []const u8,
        args: [][]const u8, // Filter arguments if any
    };

    /// Escape sequences supported in templates:
    /// - \{\{ produces literal {{
    /// - \}\} produces literal }}
    /// - \\ produces literal \
    /// - \<other> produces literal \<other>
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
                .variable => |var_ref| {
                    const var_name = compiled.vars[var_ref.var_index].name;

                    // Use reflection to check for field and get value
                    const type_info = @typeInfo(@TypeOf(ctx));
                    if (type_info != .@"struct") {
                        return Error.MissingVar;
                    }

                    var found = false;
                    var value: []const u8 = "";

                    inline for (type_info.@"struct".fields) |field| {
                        if (std.mem.eql(u8, field.name, var_name)) {
                            const val = @field(ctx, field.name);
                            found = true;

                            // Apply filters if any, otherwise render directly
                            if (var_ref.filters.len > 0) {
                                // Convert to string for filter processing
                                if (@TypeOf(val) == []const u8) {
                                    value = val;
                                } else {
                                    // For now, convert numbers to empty string
                                    value = "";
                                }

                                // Apply filters
                                var filtered_value = value;
                                for (var_ref.filters) |filter| {
                                    const new_value = try self.applyFilter(filtered_value, filter);
                                    // Free the previous filtered value if it was allocated
                                    if (filtered_value.ptr != value.ptr) {
                                        self.compiled.?.allocator.free(filtered_value);
                                    }
                                    filtered_value = new_value;
                                }

                                try writer.writeAll(filtered_value);

                                // Free the final filtered value if it was allocated
                                if (filtered_value.ptr != value.ptr) {
                                    self.compiled.?.allocator.free(filtered_value);
                                }
                            } else {
                                // No filters, render directly
                                if (@TypeOf(val) == []const u8) {
                                    try writer.writeAll(val);
                                } else {
                                    try writer.print("{any}", .{val});
                                }
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

    /// Apply a filter to a value
    fn applyFilter(self: *Template, value: []const u8, filter: Filter) ![]const u8 {
        const compiled = self.compiled orelse return Error.NotCompiled;
        const allocator = compiled.allocator;

        if (std.mem.eql(u8, filter.name, "uppercase")) {
            var result = try allocator.alloc(u8, value.len);
            for (value, 0..) |c, i| {
                result[i] = std.ascii.toUpper(c);
            }
            return result;
        } else if (std.mem.eql(u8, filter.name, "lowercase")) {
            var result = try allocator.alloc(u8, value.len);
            for (value, 0..) |c, i| {
                result[i] = std.ascii.toLower(c);
            }
            return result;
        }
        // Unknown filter, return value unchanged
        return value;
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
    /// Supports escaping: \{\{ for literal {{, \}\} for literal }}, \\ for literal \
    fn parse_template(source: []const u8, allocator: Allocator) !Template.Compiled {
        var fragments = Vec(Template.Fragment).init(allocator);
        var variables = Vec(Template.Variable).init(allocator);

        var processed_text = Vec(u8).init(allocator);
        defer processed_text.deinit();

        var i: usize = 0;
        var txt_start: usize = 0;

        while (i < source.len) {
            // Handle escape sequences
            if (source[i] == '\\' and i + 1 < source.len) {
                const next_char = source[i + 1];
                if (next_char == '{' or next_char == '}' or next_char == '\\') {
                    // Add text before escape sequence
                    if (i > txt_start) {
                        try processed_text.appendSlice(source[txt_start..i]);
                    }

                    // Add the escaped character
                    try processed_text.append(next_char);

                    // Create fragment with processed text if any
                    if (processed_text.items.len > 0) {
                        const owned_text = try allocator.dupe(u8, processed_text.items);
                        try fragments.append(.{ .text = owned_text });
                        processed_text.clearRetainingCapacity();
                    }

                    i += 2; // Skip both backslash and escaped character
                    txt_start = i;
                    continue;
                }
            }

            // Handle variable start
            if (i + 1 < source.len and source[i] == '{' and source[i + 1] == '{') {
                // Add any text before this variable (including processed escapes)
                if (i > txt_start) {
                    try processed_text.appendSlice(source[txt_start..i]);
                }
                if (processed_text.items.len > 0) {
                    const owned_text = try allocator.dupe(u8, processed_text.items);
                    try fragments.append(.{ .text = owned_text });
                    processed_text.clearRetainingCapacity();
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

                // Extract content (trim whitespace)
                const content = std.mem.trim(u8, source[var_start..var_end], " \t\n\r");

                // Parse variable with potential filters
                const fragment = try parseVariable(content, &variables, allocator);
                try fragments.append(fragment);

                i = var_end + 2; // Skip past }}
                txt_start = i;
            } else {
                i += 1;
            }
        }

        // Add any remaining text
        if (txt_start < source.len) {
            try processed_text.appendSlice(source[txt_start..]);
        }
        if (processed_text.items.len > 0) {
            const owned_text = try allocator.dupe(u8, processed_text.items);
            try fragments.append(.{ .text = owned_text });
        }

        return Template.Compiled{
            .fragments = try fragments.toOwnedSlice(),
            .vars = try variables.toOwnedSlice(),
            .allocator = allocator,
        };
    }

    /// Parse a variable with optional filters
    fn parseVariable(content: []const u8, variables: *Vec(Variable), allocator: Allocator) !Fragment {
        // Check for filters (pipe symbol)
        var parts_iter = std.mem.splitScalar(u8, content, '|');
        const var_part = std.mem.trim(u8, parts_iter.next() orelse content, " \t\n\r");

        // Find or create variable
        var var_idx: u32 = 0;
        var found = false;
        for (variables.items, 0..) |variable, idx| {
            if (std.mem.eql(u8, variable.name, var_part)) {
                var_idx = @intCast(idx);
                found = true;
                break;
            }
        }

        if (!found) {
            var_idx = @intCast(variables.items.len);
            const owned_name = try allocator.dupe(u8, var_part);
            try variables.append(.{ .name = owned_name });
        }

        // Parse filters
        var filters = Vec(Filter).init(allocator);
        while (parts_iter.next()) |filter_part| {
            const filter_name = std.mem.trim(u8, filter_part, " \t\n\r");
            if (filter_name.len > 0) {
                const owned_filter_name = try allocator.dupe(u8, filter_name);
                try filters.append(.{ .name = owned_filter_name, .args = &[_][]const u8{} });
            }
        }

        return Fragment{ .variable = .{ .var_index = var_idx, .filters = try filters.toOwnedSlice() } };
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
            var processed_text: []const u8 = "";

            var i: usize = 0;
            var txt_start: usize = 0;

            while (i < template_str.len) {
                // Handle escape sequences
                if (template_str[i] == '\\' and i + 1 < template_str.len) {
                    const next_char = template_str[i + 1];
                    if (next_char == '{' or next_char == '}' or next_char == '\\') {
                        // Add text before escape sequence
                        if (i > txt_start) {
                            processed_text = processed_text ++ template_str[txt_start..i];
                        }

                        // Add the escaped character
                        processed_text = processed_text ++ template_str[i + 1 .. i + 2];

                        // Create fragment with processed text if any
                        if (processed_text.len > 0) {
                            fragments = fragments ++ [_]ComptimeFragment{.{ .tag = .text, .data = processed_text }};
                            processed_text = "";
                        }

                        i += 2; // Skip both backslash and escaped character
                        txt_start = i;
                        continue;
                    }
                }

                // Handle variable start
                if (i + 1 < template_str.len and template_str[i] == '{' and template_str[i + 1] == '{') {
                    // Add any text before this variable (including processed escapes)
                    if (i > txt_start) {
                        processed_text = processed_text ++ template_str[txt_start..i];
                    }
                    if (processed_text.len > 0) {
                        fragments = fragments ++ [_]ComptimeFragment{.{ .tag = .text, .data = processed_text }};
                        processed_text = "";
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

                    // Check for control flow or filters
                    if (std.mem.startsWith(u8, var_name, "#if ")) {
                        // Handle if block - this is simplified for compile-time
                        fragments = fragments ++ [_]ComptimeFragment{.{ .tag = .variable, .data = var_name }};
                    } else if (std.mem.startsWith(u8, var_name, "#for ")) {
                        // Handle for block - this is simplified for compile-time
                        fragments = fragments ++ [_]ComptimeFragment{.{ .tag = .variable, .data = var_name }};
                    } else if (std.mem.startsWith(u8, var_name, "> ")) {
                        // Handle partial include
                        fragments = fragments ++ [_]ComptimeFragment{.{ .tag = .variable, .data = var_name }};
                    } else {
                        // Regular variable (possibly with filters)
                        fragments = fragments ++ [_]ComptimeFragment{.{ .tag = .variable, .data = var_name }};
                    }

                    i = var_end + 2; // Skip past }}
                    txt_start = i;
                } else {
                    i += 1;
                }
            }

            // Add any remaining text
            if (txt_start < template_str.len) {
                processed_text = processed_text ++ template_str[txt_start..];
            }
            if (processed_text.len > 0) {
                fragments = fragments ++ [_]ComptimeFragment{.{ .tag = .text, .data = processed_text }};
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

    // Escape sequences example
    print("\n3. Escape Sequences Example:\n", .{});
    const escape_template_source = "To show literal braces: \\{\\{ and \\}\\}. Variable: {{name}}. Backslash: \\\\";
    var escape_template = Template.init(allocator, escape_template_source);
    defer escape_template.deinit();

    try escape_template.compile();

    const EscapeContext = struct {
        name: []const u8,
    };

    const escape_ctx = EscapeContext{
        .name = "escaped",
    };

    const escape_result = try escape_template.render_to_string(escape_ctx, allocator);
    defer allocator.free(escape_result);
    print("Result: {s}\n", .{escape_result});

    // Filter functionality example
    print("\n4. Filter Functionality Example:\n", .{});
    const filter_template_source = "Original: {{name}}, Uppercase: {{name | uppercase}}, Lowercase: {{greeting | lowercase}}";
    var filter_template = Template.init(allocator, filter_template_source);
    defer filter_template.deinit();

    try filter_template.compile();

    const FilterContext = struct {
        name: []const u8,
        greeting: []const u8,
    };

    const filter_ctx = FilterContext{
        .name = "alice",
        .greeting = "HELLO WORLD",
    };

    const filter_result = try filter_template.render_to_string(filter_ctx, allocator);
    defer allocator.free(filter_result);
    print("Result: {s}\n", .{filter_result});

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

test "runtime template with escaped braces" {
    const allocator = std.testing.allocator;

    const template_source = "Use \\{\\{ and \\}\\} for literal braces, and {{name}} for variables. Also \\\\ for backslash.";
    var template = Template.init(allocator, template_source);
    defer template.deinit();

    try template.compile();

    const Context = struct {
        name: []const u8,
    };

    const context = Context{
        .name = "test",
    };

    const result = try template.render_to_string(context, allocator);
    defer allocator.free(result);

    const expected = "Use {{ and }} for literal braces, and test for variables. Also \\ for backslash.";
    try std.testing.expectEqualStrings(expected, result);
}

test "compile-time template with escaped braces" {
    const allocator = std.testing.allocator;

    const CompiledTemplate = Template.compile_template("Code: \\{\\{ {{variable}} \\}\\} and \\\\ backslash");

    const Context = struct {
        variable: []const u8,
    };

    const context = Context{
        .variable = "value",
    };

    var buffer = Vec(u8).init(allocator);
    defer buffer.deinit();

    try CompiledTemplate.render(context, buffer.writer());

    const expected = "Code: {{ value }} and \\ backslash";
    try std.testing.expectEqualStrings(expected, buffer.items);
}

test "edge cases for escape sequences" {
    const allocator = std.testing.allocator;

    // Test backslash at end of template
    var template1 = Template.init(allocator, "Text ends with \\");
    defer template1.deinit();
    try template1.compile();
    const result1 = try template1.render_to_string(.{}, allocator);
    defer allocator.free(result1);
    try std.testing.expectEqualStrings("Text ends with \\", result1);

    // Test multiple consecutive backslashes
    var template2 = Template.init(allocator, "Multiple backslashes: \\\\\\\\ and {{name}}");
    defer template2.deinit();
    try template2.compile();
    const Context = struct { name: []const u8 };
    const result2 = try template2.render_to_string(Context{ .name = "test" }, allocator);
    defer allocator.free(result2);
    try std.testing.expectEqualStrings("Multiple backslashes: \\\\ and test", result2);

    // Test escaped braces mixed with variables
    var template3 = Template.init(allocator, "\\{\\{{{name}}\\}\\} and {{value}}");
    defer template3.deinit();
    try template3.compile();
    const Context3 = struct { name: []const u8, value: []const u8 };
    const result3 = try template3.render_to_string(Context3{ .name = "var", .value = "val" }, allocator);
    defer allocator.free(result3);
    try std.testing.expectEqualStrings("{{var}} and val", result3);

    // Test backslash before non-escapable character
    var template4 = Template.init(allocator, "Normal \\a backslash and {{name}}");
    defer template4.deinit();
    try template4.compile();
    const result4 = try template4.render_to_string(Context{ .name = "test" }, allocator);
    defer allocator.free(result4);
    try std.testing.expectEqualStrings("Normal \\a backslash and test", result4);
}

test "basic filter functionality" {
    const allocator = std.testing.allocator;

    const template_source = "Hello {{name | uppercase}} and {{greeting | lowercase}}!";
    var template = Template.init(allocator, template_source);
    defer template.deinit();

    try template.compile();

    const Context = struct {
        name: []const u8,
        greeting: []const u8,
    };

    const context = Context{
        .name = "alice",
        .greeting = "WORLD",
    };

    const result = try template.render_to_string(context, allocator);
    defer allocator.free(result);

    // Now filters actually transform the text
    const expected = "Hello ALICE and world!";
    try std.testing.expectEqualStrings(expected, result);
}

test "chained filters functionality" {
    const allocator = std.testing.allocator;

    const template_source = "{{name | lowercase | uppercase}} should be uppercase";
    var template = Template.init(allocator, template_source);
    defer template.deinit();

    try template.compile();

    const Context = struct {
        name: []const u8,
    };

    const context = Context{
        .name = "MiXeD cAsE",
    };

    const result = try template.render_to_string(context, allocator);
    defer allocator.free(result);

    // Chained filters: first lowercase, then uppercase
    const expected = "MIXED CASE should be uppercase";
    try std.testing.expectEqualStrings(expected, result);
}
