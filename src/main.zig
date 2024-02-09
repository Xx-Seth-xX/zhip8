const std = @import("std");
const ray = @cImport({
    @cInclude("raylib.h");
});

const Zhip8 = struct {
    const Self = @This();
    const memory_size = 0x1000;
    const screen_width = 64;
    const screen_height = 32;
    vmem: []u8,
    mem: []u8,
    rv: [16]u8,
    ri: u16,
    rdelay: u16,
    rsound: u16,
    sp: u8,
    pc: u16,
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
        };
        @memset(self.vmem, 0x00);
        @memset(self.mem, 0x00);
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
        _ = addr;
        const nibble = instr & 0x000F;
        _ = nibble;
        const x = (instr & 0x0F00) >> 8;
        const y = (instr & 0x00F0) >> 8;
        const kk: u8 = @intCast(instr & 0x00FF);

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
                        @memset(self.vmem, 0x00);
                    },
                    else => {
                        std.log.err("Unknown instruction: 0x{X:0>4}", .{instr});
                        return error.UnknownInstruction;
                    },
                }
                self.pc += 2;
            },
            4 => {},
            // 6xkk LD Vx, byte
            6 => {
                self.rv[x] = kk;
                self.pc += 2;
            },
            // 8xy_
            8 => {
                switch (instr & 0x000F) {
                    // 8xy0 LD Vx, Vy
                    0 => {
                        self.rv[x] = self.rv[y];
                    },
                    // 8xy1 OR Vx, Vy
                    1 => {
                        self.rv[x] |= self.rv[y];
                    },
                    // 8xy2 AND Vx, Vy
                    2 => {
                        self.rv[x] &= self.rv[y];
                    },
                    // 8xy3 XOR Vx, Vy
                    3 => {
                        self.rv[x] ^= self.rv[y];
                    },
                    // 8xy4 ADD Vx, Vy
                    4 => {
                        const result = @addWithOverflow(self.rv[x], self.rv[y]);
                        self.rv[x] = result[0];
                        self.rv[0xf] = result[1];
                    },
                    // 8xy5 SUB Vx, Vy
                    5 => {
                        const result = @subWithOverflow(self.rv[x], self.rv[y]);
                        self.rv[x] = result[0];
                        // Flag is set to 1 if not borrow
                        self.rv[0xf] = ~result[1];
                    },
                    // 8xy6 SHR Vx, Vy
                    6 => {
                        self.rv[0xf] = self.rv[x] & 0x01;
                        self.rv[x] >>= 1;
                    },
                    // 8xy7 SUBN Vx, Vy
                    7 => {
                        const result = @subWithOverflow(self.rv[y], self.rv[x]);
                        self.rv[x] = result[0];
                        // Flag is set to 1 if not borrow
                        self.rv[0xf] = ~result[1];
                    },
                    // 8xy8 SHL Vx, Vy
                    0xE => {
                        // 0b1000 = 0x8 implies 0xb1000_0000 = 0x80
                        self.rv[0xf] = self.rv[x] & 0x80;
                        self.rv[x] <<= 1;
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
