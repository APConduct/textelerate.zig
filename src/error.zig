const std = @import("std");
const Allocator = std.mem.Allocator;
const Vec = std.ArrayList;
const print = std.debug.print;

pub const TemplateError = error{ NotCompiled, ParsError, MissingVar, InvalidSyntax } || Allocator.Error;
