const std = @import("std");
const mibu = @import("mibu");
const cursor = mibu.cursor;

pub const Screen = struct {
    rt: mibu.term.RawTerm,
    stdout: std.fs.File,

    // I use an ArrayList because depending on the screen size,
    // the buffer length may change.
    buffers: [2][32 * 64]bool,
    buf_id: usize,

    w: u16,
    h: u16,
    term_size: mibu.term.TermSize,

    const Self = @This();

    pub fn init() !Self {
        const stdin = std.io.getStdIn();
        const term_size = try mibu.term.getSize(stdin.handle);
        if (term_size.height < 32 or term_size.width < 64) {
            return error.TerminalIsTooSmall;
        }

        const rt = try mibu.term.enableRawMode(stdin.handle);
        const stdout = std.io.getStdOut();
        try mibu.term.enterAlternateScreen(stdout.writer());

        mibu.clear.all(stdout.writer()) catch {};

        // hide cursor
        try cursor.hide(stdout);

        var buffers: [2][32 * 64]bool = undefined;
        buffers[0] = [_]bool{false} ** (32 * 64);
        buffers[1] = [_]bool{false} ** (32 * 64);

        return .{
            .buffers = buffers,
            .buf_id = 0,
            .stdout = stdout,
            .rt = rt,
            .w = 64,
            .h = 32,
            .term_size = term_size,
        };
    }

    pub fn deinit(self: *Self) void {
        self.rt.disableRawMode() catch undefined;
        mibu.term.exitAlternateScreen(self.stdout.writer()) catch undefined;

        // console restoring
        cursor.show(self.stdout.writer()) catch undefined;
        cursor.goTo(self.stdout.writer(), 0, 0) catch undefined;
        mibu.clear.all(self.stdout.writer()) catch undefined;
    }

    fn getCellAt(self: *Self, x: usize, y: usize) bool {
        if (x > self.w or y > self.h) {
            std.debug.print("invalid cell\n", .{});
            return false;
        }

        return self.buffers[self.buf_id][self.w * y + x];
    }

    fn diffCellAt(self: *Self, x: usize, y: usize) bool {
        return self.buffers[0][self.w * y + x] != self.buffers[1][self.w * y + x];
    }

    pub fn setCellTo(self: *Self, x: usize, y: usize, value: bool) void {
        if (x > self.w or y > self.h) {
            std.debug.print("invalid cell\n", .{});
            return;
        }
        self.buffers[self.buf_id][self.w * y + x] = value;
    }

    pub fn flush(self: *Self) void {

        // We want to center the screen

        // space - 64 - space
        const initialX = (self.term_size.width - 64) / 2;
        const initialY = (self.term_size.height - 32) / 2;

        var x: usize = 0;
        while (x < 64) : (x += 1) {
            var y: usize = 0;
            while (y < 32) : (y += 1) {
                if (!self.diffCellAt(x, y)) {
                    continue;
                }
                var value: u21 = ' ';
                if (self.getCellAt(x, y)) {
                    value = '█';
                }
                self.stdout.writer().print("{s}{u}", .{ cursor.print.goTo(initialX + x + 1, initialY + y + 1), value }) catch unreachable;
            }
        }

        self.buf_id = 1 - self.buf_id;
    }
};
