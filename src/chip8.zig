const std = @import("std");
const SDL = @import("sdl");

pub const Chip8 = struct {
    // The first 512 bytes, from 0x000 to 0x1FF, are where the original
    // interpreter was located, and should not be used by programs.
    memory: [4096]u8,

    display: [64][32]u2,
    keyboard: [16]u2,

    // Chip-8 has 16 general purpose 8-bit registers, usually referred to as
    // Vx, where x is a hexadecimal digit (0 through F).
    v: [16]u8,

    // This register is generally used to store memory addresses, so only the
    // lowest (rightmost) 12 bits are usually used.
    i_register: u16,

    // When these registers are non-zero, they are automatically decremented
    // at a rate of 60Hz.
    delay_register: u8,
    sound_register: u8,

    // Used to store the currently executing address.
    pc: u16,

    // Used to store the address that the interpreter shoud return to when
    // finished with a subroutine.
    stack: [16]u16,

    // Used to point to the topmost level of the stack.
    sp: u8,

    // Internal variables
    is_running: bool,
    needs_redraw: bool,

    const Self = @This();

    pub fn init() Self {
        return .{
            .memory = .{0} ** 4096,
            .display = .{.{0} ** 32} ** 64,
            .keyboard = .{0} ** 16,
            .v = .{0} ** 16,
            .i_register = 0,
            .delay_register = 0,
            .sound_register = 0,
            .pc = 0x200,
            .stack = .{0} ** 16,
            .sp = 0,
            .is_running = true,
            .needs_redraw = false,
        };
    }

    pub fn load_rom(self: *Self, filepath: []const u8) !void {
        _ = try std.fs.cwd().readFile(filepath, self.memory[0x200..]);
    }

    pub fn next_instruction(self: *Self) !void {
        const left: u16 = self.memory[self.pc];
        const right: u16 = self.memory[self.pc + 1];

        const opcode = left << 8 | right;
        std.debug.print("{x:0^4}\n", .{opcode});

        switch (opcode & 0xF000) {
            0x0000 => switch (opcode & 0x0FFF) {
                // 00E0 - CLS
                // Clear the display.
                0x0E0 => {
                    self.display = .{.{0} ** 32} ** 64;
                    self.pc += 2;
                },

                // 00EE - RET
                // Return from a subroutine.
                0x0EE => {
                    self.sp -= 1;
                    self.pc = self.stack[self.sp];
                    self.pc += 2;
                },

                else => {
                    std.debug.print("unknown opcode: {x:0^4}\n", .{opcode});
                    std.process.exit(1);
                },
            },

            // 1nnn - JP addr
            // Jump to location nnn.
            0x1000 => self.pc = opcode & 0x0FFF,

            // 2nnn - CALL addr
            // Call subroutine at nnn.
            0x2000 => {
                self.stack[self.sp] = self.pc;
                self.sp += 1;
                self.pc = opcode & 0x0FFF;
            },

            // 3xkk - SE Vx, byte
            // Skip next instruction if Vx = kk.
            0x3000 => {
                const vx = self.v[(opcode & 0x0F00) >> 8];
                const kk = opcode & 0x00FF;

                if (vx == kk) {
                    self.pc += 2;
                }

                self.pc += 2;
            },

            // 4xkk - SNE Vx, byte
            // Skip next instruction if Vx != kk.
            0x4000 => {
                const vx = self.v[(opcode & 0x0F00) >> 8];
                const kk = opcode & 0x00FF;

                if (vx != kk) {
                    self.pc += 2;
                }

                self.pc += 2;
            },

            // 6xkk - LD Vx, byte
            // Set Vx = kk.
            0x6000 => {
                const x = (opcode & 0x0F00) >> 8;
                const kk = opcode & 0x00FF;
                self.v[x] = @intCast(kk);
                self.pc += 2;
            },

            // 7xkk - ADD Vx, byte
            // Set Vx = Vx + kk.
            // If an operation gives a value which is outside the range of an
            // 8-bit byte, we only preserve the lower 8 bits.
            0x7000 => {
                const x = (opcode & 0x0F00) >> 8;
                const kk = opcode & 0x00FF;
                const value = self.v[x] + kk;
                self.v[x] = @intCast(value & 0x00FF);

                self.pc += 2;
            },

            0x8000 => switch (opcode & 0x000F) {
                // 8xy0 - LD Vx, Vy
                // Set Vx = Vy.
                0x0000 => {
                    const x = (opcode & 0x0F00) >> 8;
                    const y = (opcode & 0x00F0) >> 4;
                    self.v[x] = self.v[y];

                    self.pc += 2;
                },

                // 8xy2 - AND Vx, Vy
                // Set Vx = Vx AND Vy.
                0x0002 => {
                    const x = (opcode & 0x0F00) >> 8;
                    const y = (opcode & 0x00F0) >> 4;
                    self.v[x] &= self.v[y];

                    self.pc += 2;
                },

                // 8xy3 - XOR Vx, Vy
                // Set Vx = Vx XOR Vy.
                0x0003 => {
                    const x = (opcode & 0x0F00) >> 8;
                    const y = (opcode & 0x00F0) >> 4;
                    self.v[x] ^= self.v[y];

                    self.pc += 2;
                },

                // 8xy4 - ADD Vx, Vy
                // Set Vx = Vx + Vy, set VF = carry.
                0x0004 => {
                    const x: u16 = (opcode & 0x0F00) >> 8;
                    const y: u16 = (opcode & 0x00F0) >> 4;
                    const value = @as(u16, self.v[x]) + self.v[y];
                    self.v[0xF] = 0;
                    if (value > 255) {
                        self.v[0xF] = 1;
                    }
                    self.v[x] = @intCast(value & 0x00FF);

                    self.pc += 2;
                },

                // 8xy5 - SUB Vx, Vy
                // Set Vx = Vx - Vy, set VF = NOT borrow.
                // If Vx > Vy, then VF is set to 1, otherwise 0. Then Vy is
                // subtracted from Vx, and the results stored in Vx.
                0x0005 => {
                    const x: u16 = (opcode & 0x0F00) >> 8;
                    const y: u16 = (opcode & 0x00F0) >> 4;
                    self.v[0xF] = 0;
                    if (self.v[x] > self.v[y]) {
                        self.v[0xF] = 1;
                    }

                    self.v[x] -= self.v[y];

                    self.pc += 2;
                },

                // 8xy6 - SHR Vx {, Vy}
                // Set Vx = Vx SHR 1.
                // If the least-significant bit of Vx is 1, then VF is set
                // to 1, otherwise 0. Then Vx is divided by 2.
                0x0006 => {
                    const x = (opcode & 0x0F00) >> 8;
                    self.v[0xF] = 0;
                    if (self.v[x] & 0x01 == 1) {
                        self.v[0xF] = 1;
                    }

                    // ojo!!!
                    self.v[x] /= 2;

                    self.pc += 2;
                },

                else => {
                    std.debug.print("unknown opcode: {x:0^4}\n", .{opcode});
                    std.process.exit(1);
                },
            },

            // Annn - LD I, addr
            // Set I = nnn.
            0xA000 => {
                self.i_register = opcode & 0x0FFF;
                self.pc += 2;
            },

            // Dxyn - DRW Vx, Vy, nibble
            // Display n-byte sprite starting at memory location I at (Vx, Vy), set VF = collision.
            // All sprites are 8 pixels wide (1 byte)
            0xD000 => {
                const start_x = self.v[(opcode & 0x0F00) >> 8];
                const start_y = self.v[(opcode & 0x00F0) >> 4];
                const height = opcode & 0x000F;
                const width = 8;

                self.v[0xF] = 0;
                var y: usize = 0;
                while (y < height) : (y += 1) {
                    var x: usize = 0;
                    const row = self.memory[self.i_register + y];
                    while (x < width) : (x += 1) {
                        if (row & (@as(u8, 0x80) >> @intCast(x)) != 0) {
                            // Check if there is collision
                            if (self.display[start_x + x][start_y + y] == 1) {
                                self.v[0xF] = 1;
                            }
                            self.display[start_x + x][start_y + y] ^= 1;
                        }
                    }
                }

                self.needs_redraw = true;
                self.pc += 2;
            },

            0xE000 => switch (opcode & 0x00FF) {
                // ExA1 - SKNP Vx
                // Skip next instruction if key with the value of Vx is not pressed.
                0x00A1 => {
                    const vx = self.v[(opcode & 0x0F00) >> 8];
                    if (self.keyboard[vx] == 0) {
                        self.pc += 2;
                    }

                    self.pc += 2;
                },

                // Ex9E - SKP Vx
                // Skip next instruction if key with the value of Vx is pressed.
                0x009E => {
                    const vx = self.v[(opcode & 0x0F00) >> 8];
                    if (self.keyboard[vx] == 1) {
                        self.pc += 2;
                    }
                    self.pc += 2;
                },
                else => {
                    std.debug.print("unknown opcode: {x:0^4}\n", .{opcode});
                    std.process.exit(1);
                },
            },

            0xF000 => switch (opcode & 0x00FF) {
                // Fx07 - LD Vx, DT
                // Set Vx = delay timer value.
                0x0007 => {
                    self.v[(opcode & 0x0F00) >> 8] = self.delay_register;
                    self.pc += 2;
                },

                // Fx0A - LD Vx, K
                // Wait for a key press, store the value of the key in Vx.
                0x000A => {
                    const x = (opcode & 0x0F00) >> 8;
                    var should_continue = false;
                    for (self.keyboard, 0..) |key, i| {
                        if (key == 1) {
                            self.v[x] = @intCast(i);
                            should_continue = true;
                        }
                    }
                    if (should_continue) {
                        self.pc += 2;
                    }
                },

                // Fx15 - LD DT, Vx
                // Set delay timer = Vx.
                0x0015 => {
                    self.delay_register = self.v[(opcode & 0x0F00) >> 8];
                    self.pc += 2;
                },

                // Fx18 - LD ST, Vx
                // Set sound timer = Vx.
                0x0018 => {
                    self.sound_register = self.v[(opcode & 0x0F00) >> 8];
                    self.pc += 2;
                },

                // Fx1E - ADD I, Vx
                // Set I = I + Vx.
                0x001E => {
                    self.i_register += self.v[(opcode & 0x0F00) >> 8];
                    self.pc += 2;
                },

                // Fx65 - LD Vx, [I]
                // Read registers V0 through Vx from memory starting at location I.
                0x0065 => {
                    const x = (opcode & 0x0F00) >> 8;

                    var i: usize = 0;
                    while (i <= x) : (i += 1) {
                        self.v[i] = self.memory[self.i_register + i];
                    }

                    self.pc += 2;
                },
                else => {
                    std.debug.print("unknown opcode: {x:0^4}\n", .{opcode});
                    std.process.exit(1);
                },
            },

            else => {
                std.debug.print("unknown opcode: {x:0^4}\n", .{opcode});
                std.process.exit(1);
            },
        }

        if (self.delay_register > 0) {
            self.delay_register -= 1;
        }

        if (self.sound_register > 0) {
            self.sound_register -= 1;
        }
    }

    pub fn handleEvents(self: *Self) void {
        while (SDL.pollEvent()) |ev| {
            switch (ev) {
                .quit => {
                    self.is_running = false;
                    break;
                },
                .key_down => |key| {
                    switch (key.scancode) {
                        .@"7" => self.keyboard[0] = 1,
                        .@"8" => self.keyboard[1] = 1,
                        .@"9" => self.keyboard[2] = 1,
                        .@"0" => self.keyboard[3] = 1,
                        .u => self.keyboard[4] = 1,
                        .i => self.keyboard[5] = 1,
                        .o => self.keyboard[6] = 1,
                        .p => self.keyboard[7] = 1,
                        .j => self.keyboard[8] = 1,
                        .k => self.keyboard[9] = 1,
                        .l => self.keyboard[10] = 1,
                        .semicolon => self.keyboard[11] = 1,
                        .m => self.keyboard[12] = 1,
                        .comma => self.keyboard[13] = 1,
                        .period => self.keyboard[14] = 1,
                        .backslash => self.keyboard[15] = 1,
                        else => {},
                    }
                },
                .key_up => |key| {
                    switch (key.scancode) {
                        .@"7" => self.keyboard[0] = 0,
                        .@"8" => self.keyboard[1] = 0,
                        .@"9" => self.keyboard[2] = 0,
                        .@"0" => self.keyboard[3] = 0,
                        .u => self.keyboard[4] = 0,
                        .i => self.keyboard[5] = 0,
                        .o => self.keyboard[6] = 0,
                        .p => self.keyboard[7] = 0,
                        .j => self.keyboard[8] = 0,
                        .k => self.keyboard[9] = 0,
                        .l => self.keyboard[10] = 0,
                        .semicolon => self.keyboard[11] = 0,
                        .m => self.keyboard[12] = 0,
                        .comma => self.keyboard[13] = 0,
                        .period => self.keyboard[14] = 0,
                        .backslash => self.keyboard[15] = 0,
                        else => {},
                    }
                },
                else => {},
            }
        }
    }
};
