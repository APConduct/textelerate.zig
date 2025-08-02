const std = @import("std");

const Allocator = std.mem.Allocator;

const Error = @import("error.zig").TemplateError;

const Vec = std.ArrayList;

pub const Template = struct {
    source: []const u8,
    compiled: ?Compiled = null,
    allocator: std.mem.Allocator,

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

    const Fragment = union(enum) {
        text: []const u8,
        variable: u32,
    };

    const Variable = struct { name: []const u8 };

    pub fn init(allocator: Allocator, source: []const u8) Template {
        return Template{ .source = source, .allocator = allocator };
    }

    pub fn deinit(self: *Template) void {
        if (self.compiled) |compiled| {
            compiled.deinit();
        }
    }

    pub fn compile(self: *Template) !void {
        self.compiled = try Template.parse_template(self.source, self.allocator);
    }

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

    pub fn render_to_string(self: *Template, ctx: anytype, allocator: Allocator) ![]u8 {
        var buffer = Vec(u8).init(allocator);
        try self.render(ctx, buffer.writer());
        return buffer.toOwnedSlice();
    }

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

    fn compile_template(comptime template_str: []const u8) type {
        return struct {
            pub fn render(ctx: anytype, writer: anytype) !void {
                // TODO: implement code for fully parsed and optimized template, simple placeholder below
                const frags = parse_template_comptime(template_str);

                inline for (frags) |frag| {
                    switch (frag.tag) {
                        .text => try writer.writeAll(frag.data),
                        .variable => {
                            const value = @field(ctx, frag.data);
                            try writer.print("{any}", .{value});
                        },
                    }
                }
            }
        };
    }

    fn parse_template_comptime(comptime template_str: []const u8) []const struct { tag: enum { text, variable }, data: []const u8 } {
        // TODO; fuly implement parsing
        return &[_]struct { tag: enum { text, variable }, data: []const u8 }{
            .{ .tag = .text, .data = template_str },
        };
    }
};

pub fn main() !void {
    // // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    // std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // // stdout is for the actual output of your application, for example if you
    // // are implementing gzip, then only the compressed bytes should be sent to
    // // stdout, not any debugging messages.
    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();

    // try stdout.print("Run `zig build test` to run the tests.\n", .{});

    // try bw.flush(); // Don't forget to flush!

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
