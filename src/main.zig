const std = @import("std");
const mibu = @import("mibu");

const Screen = @import("screen.zig").Screen;
const Chip8 = @import("chip8.zig").Chip8;

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();
    const rom_file = args.next() orelse {
        std.debug.print("You must specify a path to a rom\n", .{});
        std.process.exit(1);
    };

    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    var screen = try Screen.init(allocator.allocator());
    defer screen.deinit();

    var chip8 = Chip8.init();
    _ = chip8.load_rom(rom_file) catch |err| {
        std.debug.print("err: {any}\n", .{err});
        std.process.exit(1);
    };

    var last_update_time = std.time.nanoTimestamp();

    while (chip8.is_running) {
        try chip8.next_instruction();

        chip8.handleEvents();

        if (chip8.needs_redraw) {
            chip8.needs_redraw = false;

            var x: usize = 0;
            while (x < 64) : (x += 1) {
                var y: usize = 0;
                while (y < 32) : (y += 1) {
                    screen.setCellTo(x, y, chip8.display[x][y] == 1);
                }
            }

            screen.flush();
        }

        // 60 fps
        if (std.time.nanoTimestamp() - last_update_time >= 16_666_666) {
            last_update_time = std.time.nanoTimestamp();

            if (chip8.delay_register > 0) {
                chip8.delay_register -= 1;
            }

            if (chip8.sound_register > 0) {
                chip8.sound_register -= 1;
            }
        }

        // 1500 hz (ns)
        std.time.sleep(666_666);
    }
}
