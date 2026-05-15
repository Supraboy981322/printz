const std = @import("std");
const Parser = @import("parser.zig");

const Hlp = @This();

stderr:*std.Io.Writer,
parser:*Parser,

pub fn init(stderr:*std.Io.Writer, parser:*Parser) Hlp {
    return .{
        .stderr = stderr,
        .parser = parser,
    };
}

pub fn is_alpha(_:*Hlp, b:u8) bool {
    return for ([_]bool{
        b >= 'a' and b <= 'z',
        b >= 'A' and b <= 'Z',
    }) |check| {
        if (check) break true;
    } else false;
}

pub fn is_num(_:*Hlp, b:u8) bool {
    return b >= '0' and b <= '9';
}

pub fn str_is_num(self:*Hlp, raw:[]u8) bool {
    const alloc = std.heap.page_allocator; //why're people scared of page allocation?
    const str = self.parser.parse_literal(alloc, raw) catch return false;
    defer alloc.free(str);
    return for (str) |b| {
        if (b > '9' or b < '0') break false;
    } else true;
}

pub fn min_len(self:*Hlp, str:[]u8, len:usize) void {
    if (str.len < len) {
        self.stderr.print(
            \\invalid escape:
            \\  expected {d} valid characters, but found {d}
            ++ "\n", .{len, str.len}
        ) catch {};
        std.process.exit(1);
    }
}

pub fn err_if_not(
    self:*Hlp,
    condition:bool,
    comptime msg:[]const u8,
    fmt:anytype,
) void {
    if (!condition) {
        self.stderr.print(msg ++ "\n", fmt) catch {};
        std.process.exit(1);
    }
}

pub fn invalid_check(
    self:*Hlp,
    condition:bool,
    comptime what:[]const u8,
    comptime additional:?[]const u8,
    fmt:anytype,
) void {
    self.err_if_not(
        !condition,
        "invalid " ++ what ++ "\n" ++ if (additional) |add| "\t" ++ add else "",
        fmt
    );
}

pub fn fmt_hex(
    _:*Hlp,
    alloc:std.mem.Allocator,
    msg:[]u8,
    comptime opts:struct {
        caps:bool = false,
        space:bool = false,
    }
) ![]u8 {
    var res = try std.ArrayList(u8).initCapacity(alloc, 0);
    defer _ = res.deinit(alloc);
    for (msg) |b| {
        if (comptime opts.caps)
            try res.print(alloc, "{X}", .{b})
        else
            try res.print(alloc, "{x}", .{b});
        if (comptime opts.space)
            try res.append(alloc, ' ');
    }
    if (comptime opts.space)
        _ = res.pop();
    return res.toOwnedSlice(alloc);
}
