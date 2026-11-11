# Lanius language tour

This tour takes you from a clone of the repository to your own running
program. It covers the part of the language that works today on x86_64 Linux.
The last section lists what does not work yet.

`tests/language_tour.rs` compiles and runs every example on this page with the
`laniusc` binary and compares the result with the block that follows it.

## Build the compiler

You need:

- x86_64 Linux and a GPU with a Vulkan driver. The compiler runs on the GPU.
- A Rust toolchain that supports the 2024 edition.
- `slangc`, the Slang shader compiler, on `PATH` or named by `SLANGC`. The
  build compiles the compiler's shaders with it.

```sh
cargo build --release --bin laniusc
target/release/laniusc doctor
```

`doctor` prints a JSON report that says whether the compiler can run here.

## First program

Save this as `main.lani`:

```lanius
import std::io;

fn main() {
    std::io::println("Hello, world!");
}
```

Compile it and run the result:

```sh
target/release/laniusc --stdlib-root stdlib -o hello main.lani
./hello
```

```output
Hello, world!
```

- `-o` names the executable. It is a static x86_64 Linux ELF file.
- `--stdlib-root stdlib` tells the compiler where the library sources are.
  `import std::io;` reads `stdlib/std/io.lani`.
- `laniusc check --stdlib-root stdlib main.lani` reports errors without
  writing a file.
- `laniusc fmt main.lani` formats the file in place.

## Values, variables and arithmetic

```lanius
import std::console;

const LIMIT: i32 = 10;

fn main() -> i32 {
    let count = 3;
    let wide: i64 = 5000000000;
    let ratio: f64 = 0.5;
    let letter: char = 'L';
    let ready: bool = true;

    count = count + LIMIT;
    count += 1;
    print(count);
    print(17 % 5);
    print(-7 / 2);
    print(1 << 4);
    print(6 & 3);
    print(letter as i32);
    print((ratio * 10.0) as i32);
    if (ready && count > 5) { print(1); } else { print(0); }

    std::console::write_i64(wide * 2);
    std::console::write_str("\n");
    return 0;
}
```

```output
14
2
-3
16
2
76
5
1
10000000000
```

- `let` declares a variable. The type comes from the annotation or from the
  value. Every variable can be assigned again. There is no `mut` keyword on
  `let`.
- The integer types are `i8`, `i16`, `i32`, `i64`, `isize` and the unsigned
  `u8`, `u16`, `u32`, `u64`, `usize`. The float types are `f32` and `f64`.
  `bool`, `char` and `str` are the other built-in types.
- `as` converts between numeric types. There are no implicit conversions.
- Integer arithmetic wraps on overflow. Division truncates toward zero.
- `print(value)` writes an `i32`, `i16`, `i8`, `u16` or `u8` and a newline.
  For other types use `std::console`: `write_i64`, `write_u64`, `write_str`
  and `write_line`.
- The value `main` returns is the exit status of the process.

## Control flow

```lanius
fn classify(n: i32) -> i32 {
    if (n < 0) {
        return -1;
    } else if (n == 0) {
        return 0;
    } else {
        return 1;
    }
}

fn main() -> i32 {
    let total = 0;
    let i = 0;
    while (i < 5) {
        total += i;
        i += 1;
    }
    print(total);

    for n in 0..4 {
        if (n == 2) { continue; }
        print(n);
    }

    let values: [i32; 4] = [10, 20, 30, 40];
    for value in values {
        if (value > 30) { break; }
        print(value);
    }

    print(classify(-9));
    return 0;
}
```

```output
10
0
1
3
10
20
30
-1
```

- Conditions go in parentheses and must be `bool`. Arms need braces.
- `if` is a statement. Use `match` to compute a value from alternatives.
- `for n in 0..4` counts from 0 to 3. `for value in values` visits each
  element of an array.

## Arrays and slices

```lanius
fn fill(values: [i32], value: i32) {
    let count = slice_len(values) as i32;
    for index in 0..count { values[index] = value; }
}

fn double_first(values: [i32; 3]) -> i32 {
    values[0] = values[0] * 2;
    return values[0];
}

fn main() -> i32 {
    let row: [i32; 3] = [1, 2, 3];
    print(double_first(row));
    print(row[0]);
    fill(row, 9);
    print(row[0] + row[1] + row[2]);

    let grid: [[i32; 3]; 2] = [[1, 2, 3], [4, 5, 6]];
    print(grid[1][2]);
    let zeros: [i32; 8] = [0; 8];
    print(slice_len(zeros) as i32);
    return 0;
}
```

```output
2
1
27
6
8
```

- `[i32; 3]` is an array of three elements. A function that takes an array
  receives a copy, so `double_first` does not change `row`.
- `[i32]` is a slice: a view of someone else's elements. An array passes as a
  slice without a conversion, and `fill` writes through it into `row`.
- `slice_len(values)` returns the element count as a `usize`.
- Every index is checked when the program runs. See [Traps](#traps).

## Text

```lanius
import alloc::string;
import core::text;
import std::console;

fn main() -> i32 {
    let greeting: str = "hello, world";
    print(string_len(greeting) as i32);

    let text = core::text::from_str(greeting);
    if (text.starts_with(core::text::from_str("hello"))) {
        std::console::write_str("starts with hello\n");
    }
    let words = text.split(core::text::from_str(", "));
    while (true) {
        let word = words.next();
        if (word.is_none()) { break; }
        std::console::write_line(word.unwrap());
    }

    let name: String = alloc::string::new();
    if (name.try_append_str("Lan").is_err()) { return 1; }
    if (name.try_append_str("ius").is_err()) { return 1; }
    std::console::write_str("name: ");
    std::console::write_line(name.as_text());
    if (name.equals_str("Lanius")) { print(1); } else { print(0); }
    name.destroy();
    return 0;
}
```

```output
12
starts with hello
hello
world
name: Lanius
1
```

- `str` is the type of a string literal. `string_len` returns its length in
  bytes.
- `core::text::Text` is a view of UTF-8 bytes with the search and split
  methods. `core::text::from_str` makes one from a `str`.
- `String` from `alloc::string` owns its bytes and can grow. An append can
  fail when memory runs out, so it returns a `Result`.
- Memory is manual. Call `destroy()` on a `String` or a collection when you
  are done with it.

## Structs and methods

```lanius
struct Point {
    x: i32,
    y: i32,
}

impl Point {
    fn origin() -> Point {
        return Point { x: 0, y: 0 };
    }

    fn distance_squared(&self, other: Point) -> i32 {
        let dx = self.x - other.x;
        let dy = self.y - other.y;
        return dx * dx + dy * dy;
    }

    fn move_by(&mut self, dx: i32, dy: i32) {
        self.x += dx;
        self.y += dy;
    }
}

fn main() -> i32 {
    let p = Point { x: 3, y: 4 };
    print(p.distance_squared(Point::origin()));
    p.move_by(1, 1);
    print(p.x);
    p.y = 10;
    print(p.y);
    return 0;
}
```

```output
25
4
10
```

- A method with `&self` reads the value. A method with `&mut self` changes
  it. A function without `self` is called through the type: `Point::origin()`.
- A struct is a value. Passing or assigning one copies it.

## Enums and `match`

```lanius
enum Shape {
    Circle(i32),
    Rect(i32, i32),
    Empty,
}

fn area(shape: Shape) -> i32 {
    return match (shape) {
        Shape::Circle(radius) -> 3 * radius * radius,
        Shape::Rect(width, height) -> width * height,
        Shape::Empty -> 0,
    };
}

fn describe(n: i32) -> i32 {
    return match (n) {
        0 -> 100,
        1 -> 200,
        _ -> 300,
    };
}

fn main() -> i32 {
    print(area(Shape::Circle(2)));
    print(area(Shape::Rect(2, 5)));
    print(area(Shape::Empty));
    print(describe(1));
    print(describe(9));
    return 0;
}
```

```output
12
10
0
200
300
```

- `match` is an expression. Each arm is `pattern -> value`.
- An arm can also be a block, `pattern -> { statements }`. Every path through
  a block arm must end with `return`.
- `_` matches every value that the arms above it do not.
- A `match` must cover every value. On an enum that means an arm for each
  variant or a `_` arm, and on a bool both `true` and `false`. A variant
  inside a payload needs its own arms too: `Some(Shape::Circle(r))` covers
  one shape, not `Some`. A `match` on integer literals always needs a `_`
  arm. The compiler reports LNC0077 otherwise.

## `Option`, `Result` and `?`

```lanius
import core::option;
import core::result;

fn checked_div(a: i32, b: i32) -> Option<i32> {
    if (b == 0) { return None; }
    return Some(a / b);
}

fn parse_digit(c: char) -> Result<i32, i32> {
    let code = c as i32;
    if (code < 48 || code > 57) { return Err(code); }
    return Ok(code - 48);
}

fn sum_digits(a: char, b: char) -> Result<i32, i32> {
    let left = parse_digit(a)?;
    let right = parse_digit(b)?;
    return Ok(left + right);
}

fn total_or_negated_code(result: Result<i32, i32>) -> i32 {
    return match (result) {
        Ok(total) -> total,
        Err(code) -> -code,
    };
}

fn main() -> i32 {
    print(checked_div(10, 2).unwrap_or(-1));
    print(checked_div(1, 0).unwrap_or(-1));
    print(total_or_negated_code(sum_digits('4', '5')));
    print(total_or_negated_code(sum_digits('4', 'x')));
    return 0;
}
```

```output
5
-1
9
-120
```

- There are no exceptions and no null. A function that can fail returns
  `Option<T>` or `Result<T, E>`.
- `expr?` unwraps a success. On `None` or `Err` it returns that value from the
  enclosing function.

## Generics and traits

```lanius
trait Shape {
    fn area(&self) -> i32;
}

struct Square { side: i32 }
struct Rect { width: i32, height: i32 }

impl Shape for Square {
    fn area(&self) -> i32 { return self.side * self.side; }
}

impl Shape for Rect {
    fn area(&self) -> i32 { return self.width * self.height; }
}

fn larger<A: Shape, B: Shape>(a: A, b: B) -> i32 {
    if (a.area() > b.area()) { return a.area(); }
    return b.area();
}

struct Pair<T> { first: T, second: T }

fn swap<T>(pair: Pair<T>) -> Pair<T> {
    return Pair { first: pair.second, second: pair.first };
}

fn main() -> i32 {
    print(larger(Square { side: 3 }, Rect { width: 2, height: 5 }));
    let swapped = swap(Pair { first: 1, second: 2 });
    print(swapped.first);
    return 0;
}
```

```output
10
2
```

- A type parameter with a bound, `A: Shape`, accepts any type that implements
  the trait.
- Type arguments are inferred from the call's arguments.

## Closures

```lanius
import core::option::Option;
import core::option::Some;

fn twice<M>(mapper: &M, value: i32) -> i32
where M: core::function::Mapper<i32, i32> {
    return mapper.apply(mapper.apply(value));
}

fn main() -> i32 {
    let step: i32 = 3;
    print(twice(|x: i32| x + step, 1));

    let some: Option<i32> = Some(4);
    let doubled: Option<i32> = some.map(|x: i32| x * 2);
    print(doubled.unwrap());

    print(twice(|x: i32| -> i32 {
        let squared: i32 = x * x;
        return squared + step;
    }, 2));
    return 0;
}
```

```output
7
8
52
```

A closure written as above is a borrowed callback for the call it stands in.
`move` makes the closure an owned value, which a `let` or a generic struct
field can keep:

```lanius
struct Stepper<M> { step: M }

fn stepper<M>(step: M) -> Stepper<M>
where M: core::function::Mapper<i32, i32> {
    return Stepper { step: step };
}

fn run<M>(step: &M, start: i32) -> i32
where M: core::function::Mapper<i32, i32> {
    return step.apply(step.apply(start));
}

fn main() -> i32 {
    let by: i32 = 10;
    let kept = stepper(move |x: i32| x + by);
    print(run(kept.step.borrow(), 1));

    let next = move |x: i32| -> i32 { return x + 1; };
    print(next.apply(5) + next.apply(6));
    return 0;
}
```

```output
21
13
```

A generic field holds one closure type. A stored callback from
`alloc::callback` holds any `move` closure with the right signature, so a
function can return one and a struct can keep handlers of different types:

```lanius
import alloc::callback;

struct Click { x: i32, y: i32 }

struct Button { on_click: Handler<Click> }

fn adder(by: i32) -> Callback<i32, i32> {
    return callback(move |x: i32| -> i32 { return x + by; });
}

fn main() -> i32 {
    let add: Callback<i32, i32> = adder(10);
    print(add.apply(1));

    let base: i32 = 100;
    let button: Button = Button {
        on_click: handler(move |click: Click| {
            print(click.x + click.y + base);
        }),
    };
    button.on_click.accept(Click { x: 3, y: 4 });

    add.destroy();
    button.on_click.destroy();
    return 0;
}
```

```output
11
107
```

- `|x: T| expr` is a callback with one parameter. `|| expr` takes none. The
  parameter needs its type.
- A body in braces is a block of statements. With `-> Type` before the block
  it returns a value of that type. Without it the closure returns nothing.
- A closure reads the locals of its function. It copies each one when the
  closure is created. Such a local needs a declared type: `let step: i32`.
- A closure is passed where a function asks for a callback. The traits are in
  `core::function`:

  | Closure | Trait | Call |
  | --- | --- | --- |
  | `\|x: T\| expr`, `\|x: T\| -> U { ... }` | `Mapper<T, U>` | `apply(value)` |
  | `\|\| expr`, `\|\| -> U { ... }` | `Producer<U>` | `produce()` |
  | `\|x: T\| { ... }` | `Consumer<T>` | `accept(value)` |
  | `\|\| { ... }` | `Runnable` | `run()` |

  The library's `map`, `and_then` and `unwrap_or_else` take these.
- `alloc::callback` stores a `move` closure: `callback` gives a
  `Callback<T, U>`, `source` a `Source<U>`, `handler` a `Handler<T>` and
  `action` an `Action`. Each implements the trait in the same row above. A
  closure that returns a value must state `-> Type` to be stored. `destroy`
  frees a stored callback.

## Collections

```lanius
import alloc::hash_map;
import alloc::vec;
import core::option;

fn main() -> i32 {
    let squares: Vec<i32> = alloc::vec::new();
    for n in 0..5 {
        if (squares.try_push(n * n).is_err()) { return 1; }
    }
    print(squares.len());
    print(squares.at(3));
    print(squares.get(9).unwrap_or(-1));
    print(squares.pop().unwrap_or(0));
    squares.destroy();

    let ages: HashMap<i32, i32> = alloc::hash_map::new();
    if (ages.try_insert(1, 30).is_err()) { return 2; }
    if (ages.try_insert(2, 41).is_err()) { return 2; }
    print(ages.len());
    print(ages.get(2).unwrap_or(0));
    print(ages.get(7).unwrap_or(-1));
    ages.destroy();
    return 0;
}
```

```output
5
9
-1
16
2
41
-1
```

- `Vec<T>` and `HashMap<K, V>` allocate, so the calls that grow them return
  a `Result`.
- `at(index)` traps on a bad index. `get(index)` returns an `Option`.
- [`docs/library-overview.md`](library-overview.md) lists the rest of the
  library.

## Modules

A program can span several files. A file that another file imports starts
with a `module` line, and its path below the source root matches the module
name. The file with `main` needs no `module` line.

`src/app/geometry.lani`:

```lanius file=src/app/geometry.lani
module app::geometry;

pub struct Size { width: i32, height: i32 }

pub const UNIT: i32 = 1;

pub fn area(size: Size) -> i32 {
    return size.width * size.height;
}
```

`main.lani`:

```lanius
import app::geometry;
import app::geometry::area;

fn main() -> i32 {
    let size = app::geometry::Size { width: 4, height: 5 };
    print(area(size));
    print(app::geometry::UNIT);
    return 0;
}
```

```sh
target/release/laniusc --stdlib-root stdlib --source-root src -o app main.lani
```

```output
20
1
```

- `import app::geometry;` makes the module's public items usable by their
  full path. `import app::geometry::area;` also makes `area` usable by its
  short name.
- Only `pub` items are visible outside their module.
- A file without a `module` line is a module with no name. Nothing can import
  it.

## Traps

A trap ends the program. It writes one line that names the reason to standard
error.

```lanius
fn main() -> i32 {
    let values: [i32; 3] = [10, 20, 30];
    let index = 0;
    while (index < 4) {
        print(values[index]);
        index += 1;
    }
    return 0;
}
```

```output exit=101
10
20
30
```

```stderr
lanius: index out of range
```

| Cause | Line on standard error | How the process ends |
| --- | --- | --- |
| Index outside an array or slice | `lanius: index out of range` | exit status 101 |
| Shift amount outside the type's bit width | `lanius: shift amount out of range` | exit status 102 |
| Division or remainder by zero | `lanius: division by zero` | exit status 103 |
| Minimum signed value divided by -1 | `lanius: division overflow` | exit status 104 |
| `assert(false)` | `lanius: assertion failed` | signal SIGILL |

`assert(condition)` is built in. Use it for conditions that must hold. The
checked library calls use it too: `Vec::at` with a bad index ends the program
with `lanius: assertion failed`.

## Compile errors

The compiler stops at the first error and prints it with its source line:

```lanius
fn double(value: i32) -> i32 {
    return valeu * 2;
}

fn main() -> i32 {
    print(double(4));
    return 0;
}
```

```diagnostic
error[LNC0005]: unresolved identifier
 --> main.lani:2:12
  |
2 |     return valeu * 2;
  |            ^^^^^ not found in this scope
     = note: declare the value before using it or import its defining module
```

`laniusc diagnostics explain LNC0005` prints the registry entry for a code as
JSON.

## Not yet

These are known gaps. A program that needs one of them has to work around it
today.

- **One error per compile.** The compiler reports the first error and stops.
- **`for` forms.** `for` takes a named array or slice, or a range that starts
  at an integer literal and ends at a literal or a name. Other ranges and
  method calls need a `while` loop.
- **Closure limits.** A closure takes one parameter or none. It cannot use
  `self` or contain another closure, and a local it reads needs a declared
  type. There are no function types: a function takes a closure through a
  bound such as `Mapper`, and returns or stores one as an `alloc::callback`
  value. On Wasm a closure that reads a local and a call of a stored
  callback both fail with LNC0036.
- **No `if` expression.** `if` is a statement. Use `match` for a value.
- **Exhaustiveness follows one payload column.** The arms
  `Some(Shape::Circle(r))`, `Some(Shape::Empty)` and `None` cover every value
  when `Shape` has those two variants. A set of arms that splits two payloads
  of one variant at once, such as `Pair(Bit::Zero, Bit::One)`, counts as
  covering nothing. Add a `_` arm to such a match.
- **Literal payload patterns.** An arm such as `Some(1)` or `Some(true)`
  passes the type check and then fails in code generation (LNC0057). Bind the
  payload to a name and compare it in the arm.
- **Associated constructors of library types.** `Vec::new()` and
  `String::from(...)` do not resolve. Call the module function:
  `alloc::vec::new()`, `alloc::string::from_str(...)`.
- **`slice_len` on a reference.** `slice_len` takes `[T]`, not `&[T]`.
- **Trap messages have no location.** The line names the reason, not the
  source line.
- **No overflow checks.** Integer arithmetic wraps without a trap.
- **Wasm.** `--emit wasm` writes a module for a smaller set of programs and
  library modules. A compound assignment to a slice element, such as
  `values[0] += 1`, produces an invalid module. This tour does not cover
  running Wasm.
- **Targets.** x86_64 Linux and Wasm only.
- **Stability.** The language edition is `unstable-alpha`. Syntax and library
  names can change.

## Where to go next

- [`docs/language-ergonomics.md`](language-ergonomics.md): item imports, `?`,
  block arms, `else if` and trap messages in detail.
- [`docs/library-overview.md`](library-overview.md): the standard and extended
  libraries.
- `sample_programs/`: larger programs with their expected output.
