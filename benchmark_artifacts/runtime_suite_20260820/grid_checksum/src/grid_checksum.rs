fn cell_score(x: i32, y: i32, salt: i32) -> i32 {
    let distance = if x > y { x - y } else { y - x };
    let mixed = (x * 17 + y * 31 + salt * 13) % 97;
    distance + mixed
}

fn grid_checksum(rows: i32, salt: i32) -> i32 {
    let mut total = 0;
    let mut y = 0;
    while y < rows {
        let mut x = 0;
        while x < 251 {
            total += cell_score(x, y, salt);
            if total > 100_000 { total -= 200_001; }
            if total < -100_000 { total += 200_001; }
            x += 1;
        }
        y += 1;
    }
    total
}

fn main() {
    let argc = std::env::args_os().count() as i32;
    println!("{}", grid_checksum(32000 + argc, argc));
}
