const std = @import("std");
const SDL = @import("sdl");

const Chip8 = @import("chip8.zig").Chip8;

pub fn main() !void {
    std.debug.print("Chip8 emulator!!\n", .{});

    var args = std.process.args();
    _ = args.skip();
    const rom_file = args.next() orelse {
        std.debug.print("You must specify a path to a rom\n", .{});
        std.process.exit(1);
    };
    std.debug.print("rom file {s}\n", .{rom_file});

    var chip8 = Chip8.init();
    _ = chip8.load_rom(rom_file) catch |err| {
        std.debug.print("err: {any}\n", .{err});
        std.process.exit(1);
    };

    try SDL.init(.{ .video = true });
    defer SDL.quit();

    var window = try SDL.createWindow(
        "Chip8 emulator",
        .{ .centered = {} },
        .{ .centered = {} },
        1280,
        640,
        // .{ .resizable = true },
        .{},
    );
    defer window.destroy();

    var renderer = try SDL.createRenderer(window, null, .{ .accelerated = true });
    defer renderer.destroy();

    while (chip8.is_running) {
        try chip8.next_instruction();

        chip8.handleEvents();

        if (chip8.needs_redraw) {
            chip8.needs_redraw = false;

            try renderer.setColorRGB(0, 0, 0);
            try renderer.clear();

            try renderer.setColorRGB(255, 255, 255);
            var x: usize = 0;
            while (x < 64) : (x += 1) {
                var y: usize = 0;
                while (y < 32) : (y += 1) {
                    if (chip8.display[x][y] == 1) {
                        try renderer.fillRect(.{
                            .x = @intCast(x * 20),
                            .y = @intCast(y * 20),
                            .width = 20,
                            .height = 20,
                        });
                    }
                }
            }
        }

        renderer.present();
        SDL.delay(2);
    }
}
