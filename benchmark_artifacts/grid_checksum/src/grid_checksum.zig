const c = @cImport({
    @cInclude("stdio.h");
});

fn cell_score(x: i32, y: i32, seed: i32) i32 {
    const distance: i32 = if (x > y) x - y else y - x;
    const mixed: i32 = @mod(x * 17 + y * 31 + seed * 13, 97);
    if (mixed < 0) {
        return distance - mixed;
    }
    return distance + mixed;
}

fn checksum(width: i32, height: i32, seed: i32) i32 {
    var total: i32 = 0;
    var y: i32 = 0;
    while (y < height) : (y += 1) {
        var x: i32 = 0;
        while (x < width) : (x += 1) {
            total += cell_score(x, y, seed);
        }
    }
    return total;
}

pub fn main() void {
    _ = c.printf("%d\n", checksum(32, 24, 19));
}
