mod common;

use std::fmt::Write;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[derive(Clone, Copy)]
enum Kind {
    I32,
    U32,
    Char,
    WideI64,
    WideU64,
}

impl Kind {
    fn module(self) -> &'static str {
        match self {
            Self::I32 => "set_i32",
            Self::U32 => "set_u32",
            Self::Char => "set_char",
            Self::WideI64 => "set_wide_i64",
            Self::WideU64 => "set_wide_u64",
        }
    }

    fn set_type(self) -> &'static str {
        match self {
            Self::I32 => "SetI32",
            Self::U32 => "SetU32",
            Self::Char => "SetChar",
            Self::WideI64 => "SetWideI64",
            Self::WideU64 => "SetWideU64",
        }
    }

    fn value_type(self) -> &'static str {
        match self {
            Self::I32 => "i32",
            Self::U32 => "u32",
            Self::Char => "char",
            Self::WideI64 => "core::wide_i64::WideI64",
            Self::WideU64 => "core::wide_u64::WideU64",
        }
    }

    fn values(self) -> [&'static str; 6] {
        match self {
            Self::I32 => ["-2147483648", "-1", "0", "1", "7", "2147483647"],
            Self::U32 => ["0", "1", "7", "2147483648", "4294967295", "42"],
            Self::Char => ["'\\0'", "'A'", "'é'", "'中'", "'😀'", "'\u{10FFFF}'"],
            Self::WideI64 => [
                "core::wide_i64::from_words(2147483648, 0)",
                "core::wide_i64::from_i32(-1)",
                "core::wide_i64::from_i32(0)",
                "core::wide_i64::from_i32(1)",
                "core::wide_i64::from_words(1, 0)",
                "core::wide_i64::from_words(2147483647, 4294967295)",
            ],
            Self::WideU64 => [
                "core::wide_u64::from_u32(0)",
                "core::wide_u64::from_u32(1)",
                "core::wide_u64::from_words(1, 0)",
                "core::wide_u64::from_words(2147483648, 0)",
                "core::wide_u64::from_words(4294967295, 4294967295)",
                "core::wide_u64::from_u32(42)",
            ],
        }
    }

    fn fallback(self) -> &'static str {
        match self {
            Self::I32 => "123",
            Self::U32 => "123",
            Self::Char => "'?'",
            Self::WideI64 => "core::wide_i64::from_i32(123)",
            Self::WideU64 => "core::wide_u64::from_u32(123)",
        }
    }

    fn equality(self) -> &'static str {
        match self {
            Self::I32 | Self::U32 | Self::Char => "left == right",
            Self::WideI64 => "core::wide_i64::eq(left, right)",
            Self::WideU64 => "core::wide_u64::eq(left, right)",
        }
    }
}

fn next(seed: &mut u64) -> u64 {
    *seed ^= *seed << 13;
    *seed ^= *seed >> 7;
    *seed ^= *seed << 17;
    *seed
}

fn check_set(source: &mut String, module: &str, name: &str, expected: &[usize], error: usize) {
    writeln!(source, "    if (std::{module}::len({name}) != {} || std::{module}::is_empty({name}) != {}) {{ return {error}; }}", expected.len(), expected.is_empty()).unwrap();
    writeln!(source, "    if (std::{module}::capacity({name}) < std::{module}::len({name})) {{ return {error}; }}").unwrap();
    writeln!(source, "    if (!same(std::{module}::at_or({name}, -1, fallback), fallback) || !same(std::{module}::at_or({name}, {}, fallback), fallback)) {{ return {error}; }}", expected.len()).unwrap();
    for (ordinal, item) in expected.iter().enumerate() {
        writeln!(source, "    if (!same(std::{module}::at_or({name}, {ordinal}, fallback), v{item})) {{ return {error}; }}").unwrap();
    }
    for item in 0..6 {
        writeln!(
            source,
            "    if (std::{module}::contains({name}, v{item}) != {}) {{ return {error}; }}",
            expected.contains(&item)
        )
        .unwrap();
    }
}

fn ordered_algebra(left: &[usize], right: &[usize]) -> [Vec<usize>; 4] {
    let mut union = left.to_vec();
    union.extend(right.iter().copied().filter(|item| !left.contains(item)));
    let intersection = left
        .iter()
        .copied()
        .filter(|item| right.contains(item))
        .collect();
    let difference = left
        .iter()
        .copied()
        .filter(|item| !right.contains(item))
        .collect();
    let mut symmetric: Vec<usize> = left
        .iter()
        .copied()
        .filter(|item| !right.contains(item))
        .collect();
    symmetric.extend(right.iter().copied().filter(|item| !left.contains(item)));
    [union, intersection, difference, symmetric]
}

fn check_algebra(
    source: &mut String,
    module: &str,
    set_type: &str,
    left: &[usize],
    right: &[usize],
    step: usize,
) {
    let error = step + 1;
    writeln!(source, "    if (std::{module}::is_subset(left, right) != {} || std::{module}::is_subset(right, left) != {} || std::{module}::is_disjoint(left, right) != {}) {{ return {error}; }}", left.iter().all(|item| right.contains(item)), right.iter().all(|item| left.contains(item)), left.iter().all(|item| !right.contains(item))).unwrap();
    for (operation, expected) in [
        "union",
        "intersection",
        "difference",
        "symmetric_difference",
    ]
    .into_iter()
    .zip(ordered_algebra(left, right))
    {
        let name = format!("{operation}_{step}");
        writeln!(source, "    let {name}: std::{module}::{set_type} = std::{module}::try_{operation}(left, right);").unwrap();
        check_set(source, module, &name, &expected, error);
        writeln!(source, "    std::{module}::destroy({name});").unwrap();
    }
}

fn generate(kind: Kind) -> String {
    let module = kind.module();
    let set_type = kind.set_type();
    let value_type = kind.value_type();
    let mut source = format!("module app::main;\nimport std::{module};\n");
    match kind {
        Kind::WideI64 => source.push_str("import core::wide_i64;\n"),
        Kind::WideU64 => source.push_str("import core::wide_u64;\n"),
        _ => {}
    }
    writeln!(
        source,
        "fn same(left: {value_type}, right: {value_type}) -> bool {{ return {}; }}",
        kind.equality()
    )
    .unwrap();
    source.push_str("fn main() -> i32 {\n");
    for (index, value) in kind.values().iter().enumerate() {
        writeln!(source, "    let v{index}: {value_type} = {value};").unwrap();
    }
    writeln!(
        source,
        "    let fallback: {value_type} = {};",
        kind.fallback()
    )
    .unwrap();
    writeln!(
        source,
        "    let left: std::{module}::{set_type} = std::{module}::new();"
    )
    .unwrap();
    writeln!(
        source,
        "    let right: std::{module}::{set_type} = std::{module}::new();"
    )
    .unwrap();
    let mut left = Vec::<usize>::new();
    let mut right = Vec::<usize>::new();
    let mut seed = 0xd00d_feed_cafe_babe_u64;
    for step in 0..32 {
        let draw = next(&mut seed);
        let mut item = ((draw >> 8) as usize) % 6;
        let operation = match step {
            0 => {
                item = 0;
                0
            }
            1 => {
                item = 1;
                1
            }
            2 => {
                item = 1;
                0
            }
            3 => {
                item = 0;
                1
            }
            4 => {
                item = 0;
                0
            }
            5 => {
                item = 1;
                2
            }
            6 => {
                item = 5;
                3
            }
            7 => 4,
            8 => 5,
            9 => 6,
            10 => 7,
            11 => 8,
            12 => 9,
            13 => 11,
            14 => {
                item = 2;
                1
            }
            15 => {
                item = 4;
                0
            }
            16 => 12,
            _ => (draw % 13) as u32,
        };
        match operation {
            0 | 1 => {
                let (name, expected) = if operation == 0 {
                    ("left", &mut left)
                } else {
                    ("right", &mut right)
                };
                writeln!(
                    source,
                    "    {name} = std::{module}::try_insert({name}, v{item});"
                )
                .unwrap();
                if !expected.contains(&item) {
                    expected.push(item);
                }
            }
            2 | 3 => {
                let (name, expected) = if operation == 2 {
                    ("left", &mut left)
                } else {
                    ("right", &mut right)
                };
                writeln!(
                    source,
                    "    {name} = std::{module}::try_remove({name}, v{item});"
                )
                .unwrap();
                expected.retain(|present| *present != item);
            }
            4 | 5 => {
                let name = if operation == 4 { "left" } else { "right" };
                writeln!(
                    source,
                    "    let requested_{step}: i32 = std::{module}::capacity({name}) + 1;"
                )
                .unwrap();
                writeln!(
                    source,
                    "    {name} = std::{module}::try_reserve({name}, requested_{step});"
                )
                .unwrap();
                writeln!(
                    source,
                    "    if (std::{module}::capacity({name}) != requested_{step}) {{ return {}; }}",
                    step + 1
                )
                .unwrap();
            }
            6 | 7 => {
                let name = if operation == 6 { "left" } else { "right" };
                writeln!(
                    source,
                    "    {name} = std::{module}::try_shrink_to_fit({name});"
                )
                .unwrap();
                writeln!(source, "    if (std::{module}::capacity({name}) != std::{module}::len({name})) {{ return {}; }}", step + 1).unwrap();
            }
            8 | 9 => {
                let (name, expected) = if operation == 8 {
                    ("left", &left)
                } else {
                    ("right", &right)
                };
                let clone = format!("copy_{step}");
                writeln!(source, "    let {clone}: std::{module}::{set_type} = std::{module}::try_clone({name});").unwrap();
                check_set(&mut source, module, &clone, expected, step + 1);
                if let Some(first) = expected.first() {
                    writeln!(
                        source,
                        "    {clone} = std::{module}::try_remove({clone}, v{first});"
                    )
                    .unwrap();
                    writeln!(source, "    if (!std::{module}::contains({name}, v{first}) || std::{module}::contains({clone}, v{first})) {{ return {}; }}", step + 1).unwrap();
                } else {
                    writeln!(
                        source,
                        "    {clone} = std::{module}::try_insert({clone}, v0);"
                    )
                    .unwrap();
                    writeln!(source, "    if (!std::{module}::is_empty({name}) || !std::{module}::contains({clone}, v0)) {{ return {}; }}", step + 1).unwrap();
                }
                writeln!(source, "    std::{module}::destroy({clone});").unwrap();
            }
            10 | 11 => {
                let (name, expected) = if operation == 10 {
                    ("left", &mut left)
                } else {
                    ("right", &mut right)
                };
                writeln!(source, "    {name} = std::{module}::clear({name});").unwrap();
                expected.clear();
            }
            12 => {
                let name = if draw & 1 == 0 { "left" } else { "right" };
                writeln!(
                    source,
                    "    let old_capacity_{step}: i32 = std::{module}::capacity({name});"
                )
                .unwrap();
                writeln!(
                    source,
                    "    {name} = std::{module}::try_reserve({name}, -1);"
                )
                .unwrap();
                writeln!(
                    source,
                    "    {name} = std::{module}::try_reserve({name}, 536870912);"
                )
                .unwrap();
                writeln!(source, "    if (std::{module}::capacity({name}) != old_capacity_{step}) {{ return {}; }}", step + 1).unwrap();
            }
            _ => unreachable!(),
        }
        check_set(&mut source, module, "left", &left, step + 1);
        check_set(&mut source, module, "right", &right, step + 1);
        if step % 4 == 3 {
            check_algebra(&mut source, module, set_type, &left, &right, step);
            check_set(&mut source, module, "left", &left, step + 1);
            check_set(&mut source, module, "right", &right, step + 1);
        }
    }
    writeln!(source, "    std::{module}::destroy(left);").unwrap();
    writeln!(source, "    std::{module}::destroy(right);").unwrap();
    source.push_str("    return 0;\n}\n");
    source
}

fn run(kind: Kind) {
    let name = kind.module();
    let source = generate(kind);
    let entry = common::TempArtifact::new("laniusc_set", name, Some("lani"));
    entry.write_str(&source);
    let path = entry.path().to_path_buf();
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{name}: compile: {error}"));
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(name, "stateful", &bytes);
        assert_eq!(
            output.status.code(),
            Some(0),
            "{name}: {output:?}\n{source}"
        );
        assert!(output.stdout.is_empty() && output.stderr.is_empty());
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn signed_set_matches_ordered_reference() {
    run(Kind::I32);
}
#[test]
fn unsigned_set_matches_ordered_reference() {
    run(Kind::U32);
}
#[test]
fn signed_two_word_set_matches_ordered_reference() {
    run(Kind::WideI64);
}
#[test]
fn unsigned_two_word_set_matches_ordered_reference() {
    run(Kind::WideU64);
}

#[test]
fn character_set_matches_ordered_reference() {
    run(Kind::Char);
}
