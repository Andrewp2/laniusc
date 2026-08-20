fn integer_mix(iterations: i32, salt: i32) -> i32 {
    let mut total = 0;
    let mut index = 0;
    while index < iterations {
        let lane = (index + salt) % 1021;
        if lane % 4 < 2 { total += lane; } else { total -= lane; }
        if total > 100_000 { total -= 200_001; }
        if total < -100_000 { total += 200_001; }
        index += 1;
    }
    total
}

fn main() {
    let argc = std::env::args_os().count() as i32;
    println!("{}", integer_mix(25000000 + argc, argc));
}
