const std = @import("std");
const parser = @import("parser.zig");

const stderr = &@constCast(&std.fs.File.stderr().writer(&.{})).interface;

pub fn is_alpha(b:u8) bool {
    return for ([_]bool{
        b >= 'a' and b <= 'z',
        b >= 'A' and b <= 'Z',
    }) |check| {
        if (check) break true;
    } else false;
}

pub fn is_num(b:u8) bool {
    return b >= '0' and b <= '9';
}

pub fn str_is_num(raw:[]u8) bool {
    const alloc = std.heap.page_allocator; //why're people scared of page allocation?
    const str = parser.parse_literal(alloc, raw) catch return false;
    defer alloc.free(str);
    return for (str) |b| {
        if (b > '9' or b < '0') break false;
    } else true;
}

pub fn min_len(str:[]u8, len:usize) void {
    if (str.len < len) {
        stderr.print(
            \\invalid escape:
            \\  expected {d} valid characters, but found {d}
            ++ "\n", .{len, str.len}
        ) catch {};
        std.process.exit(1);
    }
}

pub fn err_if_not(condition:bool, comptime msg:[]const u8, fmt:anytype) void {
    if (!condition) {
        stderr.print(msg ++ "\n", fmt) catch {};
        std.process.exit(1);
    }
}

pub fn invalid_check(
    condition:bool,
    comptime what:[]const u8,
    comptime additional:?[]const u8,
    fmt:anytype
) void {
    err_if_not(
        !condition,
        "invalid " ++ what ++ "\n" ++ if (additional) |add| "\t" ++ add else "",
        fmt
    );
}
