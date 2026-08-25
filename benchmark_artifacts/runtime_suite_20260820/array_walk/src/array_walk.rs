fn array_walk(rounds: i32, salt: i32) -> i32 {
    let mut values: [i32; 64] = [3, 20, 37, 54, 71, 88, 105, 122, 139, 156, 173, 190, 207, 224, 241, 258, 275, 292, 309, 326, 343, 360, 377, 394, 411, 428, 445, 462, 479, 496, 513, 530, 547, 564, 581, 598, 615, 632, 649, 666, 683, 700, 717, 734, 751, 768, 785, 802, 819, 836, 853, 870, 887, 904, 921, 938, 955, 972, 989, 1006, 1023, 1040, 1057, 1074];
    let mut checksum = 0;
    let mut round = 0;
    while round < rounds {
        let mut index = 0;
        while index < 64 {
            let value = (values[index] * 33 + round + index as i32 + salt) % 10_007;
            values[index] = value;
            checksum = (checksum + value) % 1_000_003;
            index += 1;
        }
        round += 1;
    }
    checksum
}

fn main() {
    let argc = std::env::args_os().count() as i32;
    println!("{}", array_walk(100000 + argc, argc));
}
