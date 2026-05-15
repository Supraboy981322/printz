const std = @import("std");
const Hlp = @import("helpers.zig");
const Parser = @import("parser.zig");

const FormatSpecifiers = enum {
    s,
    d, @" d",
    c, @" c",
    x, X, @" x", @" X",
    e, E,
};

pub fn main(init:std.process.Init) !void {
    const alloc = init.gpa;

    var stdout_buf:[100]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    var stdout = &stdout_writer.interface;

    var stderr_buf:[100]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buf);
    const stderr = &stderr_writer.interface;

    var hlp:Hlp = .init(stderr, undefined);
    var parser:Parser = .init(stderr, &hlp);
    hlp.parser = &parser;

    const args = b: {
        var itr = try init.minimal.args.iterateAllocator(alloc);
        defer itr.deinit();

        var res = try std.ArrayList([]u8).initCapacity(alloc, 0);
        defer _ = res.deinit(alloc);

        while (itr.next()) |a| try res.append(
            alloc, try parser.parse_literal(
                alloc, std.mem.absorbSentinel(@constCast(a))[0..a.len]
            )
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

    var reader:std.Io.Reader = .fixed(args[1]);
    while (reader.takeByte() catch null) |b| {
        if (b == '{') {
            if (i == 1) {
                try res.append(alloc, b);
                i = 0;
                continue;
            }
            hlp.invalid_check(i > 0, "format string",
                "un-terminated specifier: {s}", .{mem[0..i]},
            );
            i = 1;
            continue;
        }

        if (b == '}') {
            hlp.invalid_check(i == 0, "format string",
                "missplaced '}}'; use '}}}}' for literal brace", .{}
            );
        }

        if (i > 0) {
            if (b != '}') {
                mem[@intCast(i-1)] = b;
                hlp.invalid_check(
                    @as(usize, @intCast(i)) + 1 > mem_len, "format string",
                    "unknown specifier (truncated): {s}", .{mem[0..i]},
                );
                i += 1;
                continue;
            }

            i -= 1;
            defer i = 0;

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

            try do_specifier(alloc, &res, args[a_no], &hlp, specifier, stderr, &parser);
            a_no += 1;
            continue;
        }
        try res.append(alloc, b);
    }

    if (i != 0)
        hlp.invalid_check(
            true, "format string",
            "un-terminated format specifier: |{s}|",
            .{if (i == 1) "[empty]" else mem[0..i-1]}
        );

    stdout.writeAll(res.items) catch {};
    stdout.flush() catch {};
}

pub fn do_specifier(
    alloc:std.mem.Allocator,
    res:*std.ArrayList(u8),
    arg:[]u8,
    hlp:*Hlp,
    specifier:FormatSpecifiers,
    stderr:*std.Io.Writer,
    parser:*Parser,
) !void {
    switch (specifier) {
        .s => try res.appendSlice(alloc, arg),

        .c => {
            hlp.invalid_check(
                (arg.len > 1 and !hlp.str_is_num(arg)), "format string",
                "more than one byte (can't use {{c}}): {s}", .{arg},
            );

            var char:u8 = undefined;
            if (arg.len == 1) {
                if (std.ascii.isAlphabetic(arg[0]))
                    char = arg[0];
            } else
                char = std.fmt.parseInt(u8, arg, 10) catch |e| {
                    try stderr.print("{t}: |{s}|", .{e, arg});
                    stderr.flush() catch {};
                    std.process.abort();
                    unreachable;
                };

            try res.print(alloc, "{c}", .{char});
        },

        .d => {
            hlp.invalid_check(
                (!hlp.str_is_num(arg) and arg.len > 1), "format string",
                "specified number, but provided arg isn't a number: {s}",
                .{ arg },
            );

            if (hlp.str_is_num(arg))
                try res.appendSlice(alloc, arg)
            else
                try res.print(alloc, "{d}", .{arg[0]});
        },

        inline .@" d", .@" c" => |s| {
            const fmt = @tagName(s)[1..];
            for (arg) |byte|
                try res.print(alloc, "{" ++ fmt ++ "} ", .{byte});
            _ = res.pop();
        },

        inline .x, .X, .@" x", .@" X" => |s| {
            const formatted = try hlp.fmt_hex(
                alloc, arg,
                .{
                    .caps = s == .X or s == .@" X",
                    .space = comptime std.mem.count(u8, @tagName(s), " ") > 0,
                }
            );
            defer alloc.free(formatted);
            try res.appendSlice(alloc, formatted);
        },

        inline .e, .E => |s| {
            const unescaped = try parser.unescape(
                alloc, arg, .{ .capital = s == .E }
            );
            defer alloc.free(unescaped);
            try res.appendSlice(alloc, unescaped);
        },

    }
}
