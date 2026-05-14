const std = @import("std");
const Hlp = @import("helpers.zig");
const Parser = @import("parser.zig");

const FormatSpecifiers = enum {
    s,
    d,
    c,
    x, X, @" x", @" X",
};

pub fn main(init:std.process.Init) !void {
    const alloc = init.gpa;

    var stdout_writer = std.Io.File.stdout().writer(init.io, &.{});
    var stdout = &stdout_writer.interface;

    var stderr_writer = std.Io.File.stderr().writer(init.io, &.{});
    var stderr = &stderr_writer.interface;

    var hlp:Hlp = .init(stderr, undefined);
    var parser:Parser = .init(stderr, &hlp);
    hlp.parser = &parser;

    const args = b: {
        var itr = try init.minimal.args.iterateAllocator(alloc);
        defer itr.deinit();

        var res = try std.ArrayList([]u8).initCapacity(alloc, 0);
        defer _ = res.deinit(alloc);

        while (itr.next()) |a| try res.append(
            alloc, try parser.parse_literal(alloc, std.mem.absorbSentinel(@constCast(a))[0..a.len])
        );

        break :b try res.toOwnedSlice(alloc);
    };

    defer {
        for(args) |a| alloc.free(a);
        alloc.free(args);
    }

    hlp.invalid_check(
        args.len < 2, "not enough args",
        "need something to print", .{},
    );

    var res = try std.ArrayList(u8).initCapacity(alloc, 0);
    defer _ = res.deinit(alloc);

    var i:u3 = 0;
    const mem_len = comptime std.math.maxInt(@TypeOf(i));
    var mem:[mem_len]u8 = undefined;
    var a_no:usize = 2;
    for (args[1]) |b| {
        if (b == '{') {
            i = if (i > 0) blk: {
                try res.append(alloc, b);
                break: blk 0;
            } else
                1;
        } else if (i > 0) if (b != '}') { 
            mem[@intCast(i-1)] = b;
            hlp.invalid_check(
                @as(usize, @intCast(i)) + 1 > mem_len, "format string",
                "unknown specifier (truncated): {s}", .{mem[0..i]},
            );
            i += 1;
        } else {
            defer i = 0;
            i -= 1;
            hlp.invalid_check(
                (args[1..].len < a_no), "format specifiers",
                "not enough args to populate all given specifiers", .{},
            );
            const specifier = std.meta.stringToEnum(
                FormatSpecifiers, mem[0..i]
            ) orelse {
                hlp.invalid_check(
                    true, "format string",
                    "unknown specifier: {{{s}}}", .{mem[0..i]},
                );
                unreachable;
            };
            switch (specifier) {
                .s => try res.appendSlice(alloc, args[a_no]),
                .c => {
                    hlp.invalid_check(
                        (args[a_no].len > 1 and !hlp.str_is_num(args[a_no])), "format string",
                        "more than one byte (can't use {{c}}): {s}", .{args[a_no]},
                    );
                    var char:u8 = undefined;
                    if (args[a_no].len == 1) {
                        if (std.ascii.isAlphabetic(args[a_no][0]))
                            char = args[a_no][0];
                    } else {
                        char = std.fmt.parseInt(u8, args[a_no], 10) catch |e| {
                            try stderr.print("{t}: |{s}|", .{e, args[a_no]});
                            std.process.abort();
                            unreachable;
                        };
                    }
                    try res.print(alloc, "{c}", .{char});
                },
                .d => {
                    hlp.invalid_check(
                        (!hlp.str_is_num(args[a_no]) and args[a_no].len > 1), "format string",
                        "specified number, but provided arg isn't a number: {s}",
                        .{ args[a_no] },
                    );
                    if (hlp.str_is_num(args[a_no]))
                        try res.appendSlice(alloc, args[a_no])
                    else
                        try res.print(alloc, "{d}", .{args[a_no][0]});
                },
                .x, .X, .@" x", .@" X" => {
                    const formatted = try hlp.fmt_hex(
                        alloc, args[a_no],
                        .{
                            .caps = specifier == .X or specifier == .@" X",
                            .space = specifier == .@" x" or specifier == .@" X",
                        }
                    );
                    defer alloc.free(formatted);
                    try res.appendSlice(alloc, formatted);
                },
            }
            a_no += 1;
        } else
            try res.append(alloc, b);
    }

    stdout.print("{s}", .{res.items}) catch {};
}
