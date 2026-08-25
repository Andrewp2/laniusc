const std = @import("std");
const c = @cImport({ @cInclude("stdio.h"); });

fn arrayWalk(rounds: i32, salt: i32) i32 {
    var values = [_]i32{3, 20, 37, 54, 71, 88, 105, 122, 139, 156, 173, 190, 207, 224, 241, 258, 275, 292, 309, 326, 343, 360, 377, 394, 411, 428, 445, 462, 479, 496, 513, 530, 547, 564, 581, 598, 615, 632, 649, 666, 683, 700, 717, 734, 751, 768, 785, 802, 819, 836, 853, 870, 887, 904, 921, 938, 955, 972, 989, 1006, 1023, 1040, 1057, 1074};
    var checksum: i32 = 0;
    var round: i32 = 0;
    while (round < rounds) : (round += 1) {
        var index: usize = 0;
        while (index < 64) : (index += 1) {
            const value = @mod(values[index] * 33 + round + @as(i32, @intCast(index)) + salt, 10007);
            values[index] = value;
            checksum = @mod(checksum + value, 1000003);
        }
    }
    return checksum;
}

pub fn main(init: std.process.Init.Minimal) void {
    const argc: i32 = @intCast(init.args.vector.len);
    _ = c.printf("%d\n", arrayWalk(100000 + argc, argc));
}
