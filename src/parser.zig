const std = @import("std");
const hlp = @import("helpers.zig");

pub fn parse_octal(in:[]u8, stderr:*std.Io.Writer) u8 {
    var v:usize = 0;
    for (in) |b| {
        defer if (v > std.math.maxInt(u8)) {
            stderr.print(
                "octal escape is too large to be a byte;\n"
                    ++ "\t{d} doesn't fit within the range 0..{d}\n"
                    ++ "\t\tthe max supported octal is 'o377'\n",
                .{ v, std.math.maxInt(u8) }
            ) catch {};
            std.process.exit(1);
        };
        if (b > '7' or b < '0') {
            stderr.print(
                "invalid character in octal escape: {c}\n",
            .{b}) catch {};
            std.process.exit(1);
        }
        v *= 8;
        v += b - '0';
    }
    return @intCast(v);
}

pub fn parse_hex(in:[]u8, stderr:*std.Io.Writer) u8 {
    var v:u8 = 0;
    for (in) |b| {
        v *= 16;
        v += switch (b) {
            '0'...'9' => b - '0',
            'a'...'f' => b - 'a' + 10,
            'A'...'F' => b - 'A' + 10,
            else =>  {
                stderr.print(
                    "invalid character in hex escape: {c}\n",
                .{b}) catch {};
                std.process.exit(1);
                unreachable;
            },
        };
    }
    return v;
}

pub fn parse_unicode(i:*usize, in:[]u8, alloc:std.mem.Allocator, stderr:*std.Io.Writer) ![]u8 {
    var j:usize = 0;
    defer i.* += j;
    while (j < in.len) : (j += 1)
        if (in[j] == '}') break;
    if (j == in.len) j -= 1;

    var zig_dumb = try alloc.alloc(u8, j+3);
    for (1..j+2) |k|
        zig_dumb[k] = in[k-1];
    zig_dumb[0], zig_dumb[j+2] = .{ '"', '"' };
    defer alloc.free(zig_dumb);

    return std.zig.string_literal.parseAlloc(alloc, zig_dumb) catch |e| {
        switch (e) {
            error.InvalidLiteral => {
                stderr.print(
                    "invalid unicode escape: {s}\n", .{zig_dumb}
                ) catch {};
                std.process.exit(1);
            },
            else => @panic(@errorName(e)),
        }
    };
}

pub fn parse_num(pos:*usize, in:[]u8, null_on_invalid:?bool, stderr:*std.Io.Writer) ?u8 {
    var i = pos.*;

    i -= 1;
    defer i += 1;

    var v:usize = 0;
    while (in[i] >= '0' and in[i] <= '9') : (i += 1) {
        v *= 10;
        v += in[i] - '0';
        if (in.len < i + 2) break;
    }

    if (null_on_invalid) |thing|
        if (thing and v > std.math.maxInt(u8))
            return null;

    hlp.invalid_check(
        (v > std.math.maxInt(u8)), "base-10 number escape",
        "{d} is too large to print (must fit with an unsigned 8-bit integer)", .{v},
        stderr,
    );

    return @intCast(v);
}

pub fn parse_literal(alloc:std.mem.Allocator, in:[]u8, stderr:*std.Io.Writer) ![]u8 {
    var arr = try std.ArrayList(u8).initCapacity(alloc, 0);
    defer _ = arr.deinit(alloc);
    var esc:bool = false;
    var i:usize = 0;
    loop: while (i < in.len) : (i += 1) {
        const b = in[i];
        if (esc) {
            esc = !esc;
            try arr.append(alloc, switch (b) {
                'n' => '\n', //newline
                'r' => '\r', //carrage return
                't' => '\t', //tab

                //every modern language should have these built-in
                //  (some of Zig's decisions are quite strange, in my opinion)
                'e' => '\x1b', //escape character
                'a' => '\x07', //bell character
                'b' => '\x08', //backspace
                'f' => '\x0c', //formfeed
                'v' => '\x0b', //vertical tab

                //\xXX for hex
                'x', 'X' => block: {
                    hlp.min_len(in[i..], 2, stderr);
                    defer i += 2;
                    break :block parse_hex(in[i+1..i+3], stderr);
                },
                
                //\0 should *ALWAYS* be a valid escape (in my opinion)
                '0'...'9' => parse_num(&i, in, null, stderr).?,

                //\o for octal
                'o', 'O' => block: {
                    defer i += 2;
                    i += 1;
                    hlp.min_len(in[i..], 3, stderr);
                    break :block parse_octal(in[i..i+3], stderr);
                },

                //\u{...} for unicode
                'u', 'U' => {
                    if (b == 'U') in[i] = 'u';
                    i -= 1;
                    const foo = try parse_unicode(&i, in[i..], alloc, stderr);
                    try arr.appendSlice(alloc, foo);
                    alloc.free(foo);
                    continue :loop;
                },

                else => b,
            });
            continue :loop;
        }
        switch (b) {
            '\\' => esc = true,
            else => try arr.append(alloc, b),
        }
    }
    return try arr.toOwnedSlice(alloc);
}
