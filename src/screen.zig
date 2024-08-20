const std = @import("std");
const mibu = @import("mibu");
const cursor = mibu.cursor;

pub const Screen = struct {
    allocator: std.mem.Allocator,
    termios: mibu.term.RawTerm,
    stdout: std.fs.File,

    // I use an ArrayList because depending on the screen size,
    // the buffer length may change.
    buffer: std.ArrayList(bool),

    w: u16,
    h: u16,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const stdin = std.io.getStdIn();
        const termios = try mibu.term.enableRawMode(stdin.handle, .nonblocking);

        const stdout = std.io.getStdOut();
        mibu.clear.all(stdout.writer()) catch {};

        // hide cursor
        try cursor.hide(stdout);

        var buffer = std.ArrayList(bool).init(allocator);

        var x: usize = 0;
        while (x < 64) : (x += 1) {
            var y: usize = 0;
            while (y < 32) : (y += 1) {
                try buffer.append(false);
            }
        }

        return .{
            .buffer = buffer,
            .allocator = allocator,
            .stdout = stdout,
            .termios = termios,
            .w = 64,
            .h = 32,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
        self.termios.disableRawMode() catch {};

        // console restoring
        cursor.show(self.stdout.writer()) catch {};
        cursor.goTo(self.stdout.writer(), 0, 0) catch {};
        mibu.clear.all(self.stdout.writer()) catch {};
    }

    fn getCellAt(self: *Self, x: usize, y: usize) bool {
        if (x > self.w or y > self.h) {
            std.debug.print("invalid cell\n", .{});
            return false;
        }

        return self.buffer.items[self.w * y + x];
    }

    pub fn setCellTo(self: *Self, x: usize, y: usize, value: bool) void {
        if (x > self.w or y > self.h) {
            std.debug.print("invalid cell\n", .{});
            return;
        }

        self.buffer.items[self.w * y + x] = value;
    }

    pub fn flush(self: *Self) void {
        var x: usize = 0;
        while (x < 64) : (x += 1) {
            var y: usize = 0;
            while (y < 32) : (y += 1) {
                var value: u21 = ' ';
                if (self.getCellAt(x, y)) {
                    value = '█';
                }
                self.stdout.writer().print("{s}{u}", .{ cursor.print.goTo(x, y), value }) catch unreachable;
            }
        }
    }
};
