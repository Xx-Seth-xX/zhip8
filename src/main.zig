const std = @import("std");
const rand_gen = std.rand.DefaultPrng;
const ray = @cImport({
    @cInclude("raylib.h");
});

const Zhip8 = struct {
    const Self = @This();
    const hex_sprites = [_]u8{
        0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
        0x20, 0x60, 0x20, 0x20, 0x70, // 1
        0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
        0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
        0x90, 0x90, 0xF0, 0x10, 0x10, // 4
        0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
        0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
        0xF0, 0x10, 0x20, 0x40, 0x40, // 7
        0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
        0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
        0xF0, 0x90, 0xF0, 0x90, 0x90, // A
        0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
        0xF0, 0x80, 0x80, 0x80, 0xF0, // C
        0xE0, 0x90, 0x90, 0x90, 0xE0, // D
        0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
        0xF0, 0x80, 0xF0, 0x80, 0x80, // F
    };
    const memory_size = 0x1000;
    const screen_width = 64;
    const screen_height = 32;
    rnd: std.rand.Xoshiro256,
    stack: [16]u16,
    vmem: []u8,
    mem: []u8,
    rv: [16]u8,
    ri: u16,
    rdelay: u8,
    rsound: u8,
    sp: u8,
    pc: u16,
    const keycodes = [16]c_int{
        ray.KEY_X,
        ray.KEY_KP_1,
        ray.KEY_KP_2,
        ray.KEY_KP_3,
        ray.KEY_Q,
        ray.KEY_W,
        ray.KEY_E,
        ray.KEY_A,
        ray.KEY_S,
        ray.KEY_D,
        ray.KEY_Z,
        ray.KEY_C,
        ray.KEY_KP_4,
        ray.KEY_R,
        ray.KEY_F,
        ray.KEY_V,
    };
    inline fn get_addr_hex_sprite(val: u8) u16 {
        return 5 * val;
    }
    fn get_pixel(self: Self, x: usize, y: usize) u8 {
        const wrx = @mod(x, screen_width);
        const wry = @mod(y, screen_height);
        return self.vmem[wry * screen_width + wrx];
    }
    fn set_pixel(self: Self, x: usize, y: usize, val: u8) void {
        const wrx = @mod(x, screen_width);
        const wry = @mod(y, screen_height);
        self.vmem[wry * screen_width + wrx] = val;
    }
    fn init(alloc: std.mem.Allocator) !Self {
        const self = Self{
            .mem = try alloc.alloc(u8, memory_size),
            .vmem = try alloc.alloc(u8, screen_width * screen_height),
            .rv = [1]u8{0} ** 16,
            .ri = 0,
            .rdelay = 0,
            .rsound = 0,
            .sp = 0,
            .pc = 0x200,
            .stack = [1]u16{0} ** 16,
            .rnd = std.rand.Xoshiro256.init(0),
        };
        @memset(self.vmem, 0x00);
        @memset(self.mem, 0x00);
        @memcpy(self.mem[0..Self.hex_sprites.len], &Self.hex_sprites);

        return self;
    }
    fn load_program(self: *Self, program: []u8) void {
        // Program must be loaded at location 0x200
        @memcpy(self.mem[0x200..(0x200 + program.len)], program);
    }
    fn dump(self: Self) void {
        std.debug.print("Dumping registers: \n", .{});
        for (self.rv, 0..) |rv, i| {
            std.debug.print("    V{X}: 0x{X:0>2}\n", .{ i, rv });
        }
        std.debug.print("    PC: 0x{X:0>4}\n", .{self.pc});
        std.debug.print("    I : 0x{X:0>4}\n", .{self.ri});
        std.debug.print("    SP: 0x{X:0>2}\n", .{self.sp});
    }
    fn step(self: *Self) !void {
        const instr: u16 = @as(u16, self.mem[self.pc]) << 8 | @as(u16, self.mem[self.pc + 1]);

        // Variables
        const addr = instr & 0x0FFF;
        const nibble = instr & 0x000F;
        const x = (instr & 0x0F00) >> 8;
        const y = (instr & 0x00F0) >> 8;
        const kk: u8 = @intCast(instr & 0x00FF);

        self.rdelay -|= 1;
        self.rsound -|= 1;
        // std.log.debug("PC: 0x{X:0>4} instr: 0x{X:0>4}", .{ self.pc, instr });
        // Reference: http://devernay.free.fr/hacks/chip8/C8TECH10.HTM#0.0
        // Dispatch instructions
        switch ((instr & 0xF000) >> 12) {
            0 => {
                // 0nnn SYS addr, suppossed to be ignored
                switch (instr) {
                    // 0x00E0 CLS
                    0x00E0 => {
                        @memset(self.vmem, 0x00);
                    },
                    // 0x0EE
                    0x00EE => {
                        self.sp -= 1;
                        self.pc = self.stack[self.sp];
                    },
                    else => {
                        std.log.err("Unknown instruction: 0x{X:0>4}", .{instr});
                        return error.UnknownInstruction;
                    },
                }
                self.pc += 2;
            },
            // 1nnn JP addr
            1 => {
                std.log.debug("1nnn JP addr", .{});
                self.pc = addr;
            },
            // 2nnn CALL addr
            2 => {
                std.log.debug("2nnn CALL addr", .{});
                self.stack[self.sp] = self.pc;
                self.sp += 1;
                self.pc = addr;
            },
            // 3xkk SE Vx, byte
            3 => {
                std.log.debug("3xkk SE Vx, byte", .{});
                if (self.rv[x] == kk) {
                    self.pc += 4;
                } else {
                    self.pc += 2;
                }
            },
            // 4xkk SNE Vx, byte
            4 => {
                std.log.debug("4xkk SNE Vx, byte", .{});
                if (self.rv[x] != kk) {
                    self.pc += 4;
                } else {
                    self.pc += 2;
                }
            },
            // 6xkk LD Vx, byte
            6 => {
                std.log.debug("6xkk LD Vx, byte", .{});
                self.rv[x] = kk;
                self.pc += 2;
            },
            // 7xkk ADD Vx, byte
            7 => {
                std.log.debug("7xkk ADD Vx, byte", .{});
                self.rv[x] +%= kk;
                self.pc += 2;
            },
            // 8xy_
            8 => {
                switch (instr & 0x000F) {
                    // 8xy0 LD Vx, Vy
                    0 => {
                        std.log.debug("8xy0 LD Vx, Vy", .{});
                        self.rv[x] = self.rv[y];
                    },
                    // 8xy1 OR Vx, Vy
                    1 => {
                        std.log.debug("8xy1 OR Vx, Vy", .{});
                        self.rv[x] |= self.rv[y];
                    },
                    // 8xy2 AND Vx, Vy
                    2 => {
                        std.log.debug("8xy2 AND Vx, Vy", .{});
                        self.rv[x] &= self.rv[y];
                    },
                    // 8xy3 XOR Vx, Vy
                    3 => {
                        std.log.debug("8xy3 XOR Vx, Vy", .{});
                        self.rv[x] ^= self.rv[y];
                    },
                    // 8xy4 ADD Vx, Vy
                    4 => {
                        std.log.debug("8xy4 ADD Vx, Vy", .{});
                        const result = @addWithOverflow(self.rv[x], self.rv[y]);
                        self.rv[x] = result[0];
                        self.rv[0xf] = result[1];
                    },
                    // 8xy5 SUB Vx, Vy
                    5 => {
                        std.log.debug("8xy5 SUB Vx, Vy", .{});
                        const result = @subWithOverflow(self.rv[x], self.rv[y]);
                        self.rv[x] = result[0];
                        // Flag is set to 1 if not borrow
                        self.rv[0xf] = ~result[1];
                    },
                    // 8xy6 SHR Vx, Vy
                    6 => {
                        std.log.debug("8xy6 SHR Vx, Vy", .{});
                        self.rv[0xf] = self.rv[x] & 0b0000_0001;
                        self.rv[x] >>= 1;
                    },
                    // 8xy7 SUBN Vx, Vy
                    7 => {
                        std.log.debug("8xy7 SUBN Vx, Vy", .{});
                        const result = @subWithOverflow(self.rv[y], self.rv[x]);
                        self.rv[x] = result[0];
                        // Flag is set to 1 if not borrow
                        self.rv[0xf] = ~result[1];
                    },
                    // 8xyE SHL Vx, Vy
                    0xE => {
                        std.log.debug("8xyE SHL Vx, Vy", .{});
                        // 0b1000 = 0x8 implies 0xb1000_0000 = 0x80
                        self.rv[0xf] = (self.rv[x] & 0b1000_0000) >> 7;
                        self.rv[x] <<= 1;
                    },
                    else => {
                        std.log.err("Unknown instruction: 0x{X:0>4}", .{instr});
                        return error.UnknownInstruction;
                    },
                }
                self.pc += 2;
            },
            // LD I, addr
            0xA => {
                std.log.debug("Annn LD I, addr", .{});
                self.ri = addr;
                self.pc += 2;
            },
            // JP V0, addr
            0xB => {
                std.log.debug("Bnnn JP V0, addr", .{});
                self.pc = addr + self.rv[0];
            },
            // RND V0, byte
            0xC => {
                std.log.debug("Cnnn RND V0, byte", .{});
                self.rv[x] = self.rnd.random().int(u8) & kk;
                self.pc += 2;
            },
            // DRW Vx, Vy, nibble
            0xD => {
                std.log.debug("Dnnn DRW Vx, Vy", .{});
                var ov = false;
                for (0..nibble) |y_offset| {
                    const true_y: u8 = @intCast(self.rv[y] + y_offset);
                    const byte = self.mem[self.ri + y_offset];
                    // std.log.debug("{b:0>8}----", .{byte});
                    for (0..8) |x_offset| {
                        const true_x: u8 = @intCast(self.rv[x] + x_offset);
                        const bit: u8 = if ((byte >> (7 - @as(u3, @intCast(x_offset))) & 0x1) == 1)
                            0xFF
                        else
                            0x00;
                        const current_pix = self.get_pixel(true_x, true_y);
                        ov = ov or 0 != (bit | current_pix);
                        self.set_pixel(true_x, true_y, current_pix ^ bit);
                    }
                }
                self.rv[0xf] = @intFromBool(ov);
                self.pc += 2;
            },
            0xF => {
                switch (instr & 0x00FF) {
                    // LD Vx, DT
                    0x07 => {
                        std.log.debug("Fn07 LD Vx, DT", .{});
                        self.rv[x] = self.rdelay;
                    },
                    // LD Vx, K
                    0x0A => {
                        std.log.debug("Fn0A LD Vx, K", .{});
                        const key = ray.GetKeyPressed();
                        if (std.mem.indexOf(c_int, &keycodes, &[_]c_int{key})) |i| {
                            self.rv[x] = @intCast(i);
                        } else {
                            return;
                        }
                    },
                    // LD DT, Vx
                    0x15 => {
                        std.log.debug("Fn15 LD DT, Vx", .{});
                        self.rdelay = self.rv[x];
                    },
                    // LD ST, Vx
                    0x18 => {
                        std.log.debug("Fn18 LD ST, Vx", .{});
                        self.rsound = self.rv[x];
                    },
                    // ADD ST, Vx
                    0x1E => {
                        std.log.debug("Fn1E ADD ST, Vx", .{});
                        self.ri +%= self.rv[x];
                    },
                    // LD F, Vx
                    0x29 => {
                        std.log.debug("Fn29 LD F, Vx", .{});
                        self.ri = get_addr_hex_sprite(self.rv[x]);
                    },
                    // LD B, Vx
                    0x33 => {
                        std.log.debug("Fn33 LD B, Vx", .{});
                        // val = 123
                        const val = self.rv[x];
                        const aux = @rem(val, 100);
                        // aux = 23
                        const hundreds = (val - aux) / 100;
                        // hundreds = 1
                        const units = @rem(aux, 10);
                        // units = 3
                        const tens = (aux - units) / 10;

                        self.mem[self.ri] = @intCast(hundreds);
                        self.mem[self.ri + 1] = @intCast(tens);
                        self.mem[self.ri + 2] = @intCast(units);
                    },
                    // LD [I], Vx
                    0x55 => {
                        std.log.debug("Fn55 LD [I], Vx", .{});
                        for (self.rv[0..(x + 1)], 0..) |vrx, i| {
                            self.mem[self.ri + i] = vrx;
                        }
                    },
                    // LD Vx, [I]
                    0x65 => {
                        std.log.debug("Fn55 LD Vx, [I]", .{});
                        for (self.mem[self.ri..(self.ri + x)], 0..) |data, i| {
                            self.rv[i] = data;
                        }
                    },
                    else => {
                        std.log.err("Unknown instruction: 0x{X:0>4}", .{instr});
                        return error.UnknownInstruction;
                    },
                }
                self.pc += 2;
            },
            else => {
                std.log.err("Unknown instruction: 0x{X:0>4}", .{instr});
                return error.UnknownInstruction;
            },
        }
    }
};

const w_width = 1320;
const w_height = 640;

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var z8 = try Zhip8.init(alloc);
    const program = @embedFile("examples/GUESS");
    z8.load_program(@constCast(program));

    ray.InitWindow(w_width, w_height, "Zhip8");
    const screen_text = ray.LoadTextureFromImage(ray.Image{
        .data = @ptrCast(z8.vmem),
        .width = Zhip8.screen_width,
        .height = Zhip8.screen_height,
        .mipmaps = 1,
        .format = ray.PIXELFORMAT_UNCOMPRESSED_GRAYSCALE,
    });
    ray.SetTargetFPS(60);
    while (!ray.WindowShouldClose()) {
        z8.step() catch {
            z8.dump();
            std.os.nanosleep(2, 0);
            return 0xff;
        };

        ray.BeginDrawing();
        ray.UpdateTexture(screen_text, @ptrCast(z8.vmem));
        ray.DrawTexturePro(
            screen_text,
            ray.Rectangle{ .x = 0, .y = 0, .width = Zhip8.screen_width, .height = Zhip8.screen_height },
            ray.Rectangle{ .x = 0, .y = 0, .width = w_width, .height = w_height },
            ray.Vector2{ .x = 0, .y = 0 },
            0.0,
            ray.WHITE,
        );
        ray.EndDrawing();
    }
    return 0;
}
