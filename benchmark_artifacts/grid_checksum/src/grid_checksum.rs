fn cell_score(x: i32, y: i32, seed: i32) -> i32 {
    let distance = if x > y { x - y } else { y - x };
    let mixed = (x * 17 + y * 31 + seed * 13) % 97;
    if mixed < 0 {
        distance - mixed
    } else {
        distance + mixed
    }
}

fn checksum(width: i32, height: i32, seed: i32) -> i32 {
    let mut total = 0;
    let mut y = 0;
    while y < height {
        let mut x = 0;
        while x < width {
            total += cell_score(x, y, seed);
            x += 1;
        }
        y += 1;
    }
    total
}

fn main() {
    println!("{}", checksum(32, 24, 19));
}
