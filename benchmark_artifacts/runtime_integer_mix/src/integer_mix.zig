const std = @import("std");
const c = @cImport({ @cInclude("stdio.h"); });

fn integerMix(iterations: i32, salt: i32) i32 {
    var total: i32 = 0;
    var index: i32 = 0;
    while (index < iterations) : (index += 1) {
        const lane = @mod(index + salt, 1021);
        if (@mod(lane, 4) < 2) { total += lane; } else { total -= lane; }
        if (total > 100000) total -= 200001;
        if (total < -100000) total += 200001;
    }
    return total;
}

pub fn main(init: std.process.Init.Minimal) void {
    const argc: i32 = @intCast(init.args.vector.len);
    _ = c.printf("%d\n", integerMix(25000000 + argc, argc));
}
