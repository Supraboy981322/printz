const std = @import("std");
const Hlp = @import("helpers.zig");

const Parser = @This();

hlp:*Hlp,
stderr:*std.Io.Writer,

pub fn init(stderr:*std.Io.Writer, hlp:*Hlp) Parser {
    return .{
        .hlp = hlp,
        .stderr = stderr,
    };
}

pub fn parse_octal(self:*Parser, in:[]u8) u8 {
    var v:usize = 0;
    for (in) |b| {
        defer if (v > std.math.maxInt(u8)) {
            self.stderr.print(
                "octal escape is too large to be a byte;\n"
                    ++ "\t{d} doesn't fit within the range 0..{d}\n"
                    ++ "\t\tthe max supported octal is 'o377'\n",
                .{ v, std.math.maxInt(u8) }
            ) catch {};
            std.process.exit(1);
        };
        if (b > '7' or b < '0') {
            self.stderr.print(
                "invalid character in octal escape: {c}\n",
            .{b}) catch {};
            std.process.exit(1);
        }
        v *= 8;
        v += b - '0';
    }
    return @intCast(v);
}

pub fn parse_hex(self:*Parser, in:[]u8) u8 {
    var v:u8 = 0;
    for (in) |b| {
        v *= 16;
        v += switch (b) {
            '0'...'9' => b - '0',
            'a'...'f' => b - 'a' + 10,
            'A'...'F' => b - 'A' + 10,
            else =>  {
                self.stderr.print(
                    "invalid character in hex escape: {c}\n",
                .{b}) catch {};
                std.process.exit(1);
                unreachable;
            },
        };
    }
    return v;
}

pub fn parse_unicode(self:*Parser, i:*usize, in:[]u8, alloc:std.mem.Allocator) ![]u8 {
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
                self.stderr.print(
                    "invalid unicode escape: {s}\n", .{zig_dumb}
                ) catch {};
                std.process.exit(1);
            },
            else => @panic(@errorName(e)),
        }
    };
}

pub fn parse_num(self:*Parser, pos:*usize, in:[]u8, null_on_invalid:?bool) ?u8 {
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

    self.hlp.invalid_check(
        (v > std.math.maxInt(u8)), "base-10 number escape",
        "{d} is too large to print (must fit with an unsigned 8-bit integer)", .{v},
    );

    return @intCast(v);
}

pub fn parse_literal(self:*Parser, alloc:std.mem.Allocator, in:[]u8) ![]u8 {
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
                    self.hlp.min_len(in[i..], 2);
                    defer i += 2;
                    break :block self.parse_hex(in[i+1..i+3]);
                },
                
                //\0 should *ALWAYS* be a valid escape (in my opinion)
                '0'...'9' => self.parse_num(&i, in, null).?,

                //\o for octal
                'o', 'O' => block: {
                    defer i += 2;
                    i += 1;
                    self.hlp.min_len(in[i..], 3);
                    break :block self.parse_octal(in[i..i+3]);
                },

                //\u{...} for unicode
                'u', 'U' => {
                    if (b == 'U') in[i] = 'u';
                    i -= 1;
                    const foo = try self.parse_unicode(&i, in[i..], alloc);
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

pub fn unescape(
    _:*Parser,
    alloc:std.mem.Allocator,
    str:[]u8,
    comptime opts:struct{
        capital:bool = false
    }
) ![]u8 {
    var wr:std.Io.Writer.Allocating = .init(alloc);
    defer wr.deinit();
    for (str) |b| try wr.writer.writeAll(
        switch (b) {
            '\n' => "\\" ++ if (opts.capital) "N" else "n", //newline
            '\r' => "\\" ++ if (opts.capital) "R" else "r", //carrage return
            '\t' => "\\" ++ if (opts.capital) "T" else "t", //tab

            '\x1b' => "\\" ++ if (opts.capital) "E" else "e", //escape character
            '\x07' => "\\" ++ if (opts.capital) "A" else "a", //bell character
            '\x08' => "\\" ++ if (opts.capital) "B" else "b", //backspace
            '\x0c' => "\\" ++ if (opts.capital) "F" else "f", //formfeed
            '\x0b' => "\\" ++ if (opts.capital) "V" else "v", //vertical tab

            else =>
                if ((b <= '~' and b >= ' ') or std.ascii.isWhitespace(b))
                    @constCast(&[_]u8{b})
                else {
                    try wr.writer.writeAll("\\x");
                    const escaped = try std.fmt.allocPrint(
                        alloc, "{" ++ (if (opts.capital) "X" else "x") ++ "}", .{b}
                    );
                    defer alloc.free(escaped);
                    if (escaped.len == 1)
                        try wr.writer.writeAll("0");
                    try wr.writer.writeAll(escaped);
                    continue;
                },
        }
    );
    return try wr.toOwnedSlice();
}
