const std = @import("std");
const Allocator = std.mem.Allocator;
const Vec = std.ArrayList;
const print = std.debug.print;

pub const Position = struct {
    line: u32,
    column: u32,
    offset: usize,
};

pub const TemplateError = error{
    NotCompiled,
    ParseError,
    MissingVar,
    InvalidSyntax,
    UnclosedBlock,
    UnknownFilter,
    PartialNotFound,
    ContextTypeMismatch,
    InvalidCondition,
    InvalidLoop,
} || Allocator.Error;

pub const DetailedError = struct {
    error_type: TemplateError,
    message: []const u8,
    position: ?Position = null,

    pub fn init(error_type: TemplateError, message: []const u8) DetailedError {
        return DetailedError{
            .error_type = error_type,
            .message = message,
        };
    }

    pub fn withPosition(error_type: TemplateError, message: []const u8, pos: Position) DetailedError {
        return DetailedError{
            .error_type = error_type,
            .message = message,
            .position = pos,
        };
    }

    pub fn format(self: DetailedError, writer: anytype) !void {
        if (self.position) |pos| {
            try writer.print("Error at line {}, column {}: {s}", .{ pos.line + 1, pos.column + 1, self.message });
        } else {
            try writer.print("Error: {s}", .{self.message});
        }
    }
};
