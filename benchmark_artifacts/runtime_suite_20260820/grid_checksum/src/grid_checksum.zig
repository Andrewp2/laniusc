const std = @import("std");
const c = @cImport({ @cInclude("stdio.h"); });

fn cellScore(x: i32, y: i32, salt: i32) i32 {
    const distance = if (x > y) x - y else y - x;
    const mixed = @mod(x * 17 + y * 31 + salt * 13, 97);
    return distance + mixed;
}

fn gridChecksum(rows: i32, salt: i32) i32 {
    var total: i32 = 0;
    var y: i32 = 0;
    while (y < rows) : (y += 1) {
        var x: i32 = 0;
        while (x < 251) : (x += 1) {
            total += cellScore(x, y, salt);
            if (total > 100000) total -= 200001;
            if (total < -100000) total += 200001;
        }
    }
    return total;
}

pub fn main(init: std.process.Init.Minimal) void {
    const argc: i32 = @intCast(init.args.vector.len);
    _ = c.printf("%d\n", gridChecksum(32000 + argc, argc));
}
