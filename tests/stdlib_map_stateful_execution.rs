mod common;

use std::fmt::Write;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[derive(Clone, Copy)]
enum Kind {
    I32,
    U32,
    WideI64,
    WideU64,
}

impl Kind {
    fn module(self) -> &'static str {
        match self {
            Self::I32 => "map_i32_i32",
            Self::U32 => "map_u32_u32",
            Self::WideI64 => "map_wide_i64_wide_i64",
            Self::WideU64 => "map_wide_u64_wide_u64",
        }
    }

    fn map_type(self) -> &'static str {
        match self {
            Self::I32 => "MapI32I32",
            Self::U32 => "MapU32U32",
            Self::WideI64 => "MapWideI64WideI64",
            Self::WideU64 => "MapWideU64WideU64",
        }
    }

    fn value_type(self) -> &'static str {
        match self {
            Self::I32 => "i32",
            Self::U32 => "u32",
            Self::WideI64 => "core::wide_i64::WideI64",
            Self::WideU64 => "core::wide_u64::WideU64",
        }
    }

    fn values(self) -> [&'static str; 6] {
        match self {
            Self::I32 => ["-2147483648", "-1", "0", "1", "7", "2147483647"],
            Self::U32 => ["0", "1", "7", "2147483648", "4294967295", "42"],
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
            Self::I32 => "-123",
            Self::U32 => "123",
            Self::WideI64 => "core::wide_i64::from_i32(123)",
            Self::WideU64 => "core::wide_u64::from_u32(123)",
        }
    }

    fn equality(self) -> &'static str {
        match self {
            Self::I32 | Self::U32 => "left == right",
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

fn check_state(source: &mut String, module: &str, expected: &[(usize, usize)], step: usize) {
    let error = step + 1;
    writeln!(
        source,
        "    if (std::{module}::len(value) != {} || std::{module}::is_empty(value) != {}) {{ return {error}; }}",
        expected.len(),
        expected.is_empty(),
    )
    .unwrap();
    writeln!(
        source,
        "    if (std::{module}::capacity(value) < std::{module}::len(value)) {{ return {error}; }}"
    )
    .unwrap();
    writeln!(
        source,
        "    if (!same(std::{module}::key_at_or(value, -1, fallback), fallback) || !same(std::{module}::value_at_or(value, {}, fallback), fallback)) {{ return {error}; }}",
        expected.len()
    )
    .unwrap();
    for (ordinal, (key, item)) in expected.iter().enumerate() {
        writeln!(
            source,
            "    if (!same(std::{module}::key_at_or(value, {ordinal}, fallback), v{key}) || !same(std::{module}::value_at_or(value, {ordinal}, fallback), v{item})) {{ return {error}; }}"
        )
        .unwrap();
    }
    for key in 0..6 {
        if let Some((_, item)) = expected.iter().find(|(present, _)| *present == key) {
            writeln!(
                source,
                "    if (!std::{module}::contains_key(value, v{key}) || !same(std::{module}::get_or(value, v{key}, fallback), v{item})) {{ return {error}; }}"
            )
            .unwrap();
        } else {
            writeln!(
                source,
                "    if (std::{module}::contains_key(value, v{key}) || !same(std::{module}::get_or(value, v{key}, fallback), fallback)) {{ return {error}; }}"
            )
            .unwrap();
        }
    }
}

fn generate(kind: Kind) -> String {
    let module = kind.module();
    let map_type = kind.map_type();
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
        "    let value: std::{module}::{map_type} = std::{module}::new();"
    )
    .unwrap();
    let mut expected = Vec::<(usize, usize)>::new();
    let mut seed = 0xd00d_feed_cafe_babe_u64;
    for step in 0..40 {
        let draw = next(&mut seed);
        let mut key = ((draw >> 8) as usize) % 6;
        let mut item = ((draw >> 16) as usize) % 6;
        let operation = match step {
            0 => {
                key = 0;
                item = 1;
                0
            }
            1 => {
                key = 0;
                item = 2;
                0
            }
            2 => {
                key = 1;
                item = 2;
                0
            }
            3 => {
                key = 2;
                item = 3;
                0
            }
            4 => {
                key = 1;
                item = 4;
                1
            }
            5 => {
                key = 1;
                2
            }
            6 => 3,
            7 => 5,
            8 => 4,
            9 => 6,
            10 => {
                key = 4;
                item = 5;
                0
            }
            11 => {
                key = 3;
                2
            }
            _ => (draw % 8) as u32,
        };
        match operation {
            0 => {
                writeln!(
                    source,
                    "    value = std::{module}::try_insert(value, v{key}, v{item});"
                )
                .unwrap();
                if !expected.iter().any(|(present, _)| *present == key) {
                    expected.push((key, item));
                }
            }
            1 => {
                let present = expected.iter().any(|(present, _)| *present == key);
                writeln!(
                    source,
                    "    if (std::{module}::try_set(value, v{key}, v{item}) != {present}) {{ return {}; }}",
                    step + 1
                )
                .unwrap();
                if let Some(entry) = expected.iter_mut().find(|(present, _)| *present == key) {
                    entry.1 = item;
                }
            }
            2 => {
                writeln!(
                    source,
                    "    value = std::{module}::try_remove(value, v{key});"
                )
                .unwrap();
                expected.retain(|(present, _)| *present != key);
            }
            3 => {
                writeln!(
                    source,
                    "    let requested_{step}: i32 = std::{module}::capacity(value) + 1;"
                )
                .unwrap();
                writeln!(
                    source,
                    "    value = std::{module}::try_reserve(value, requested_{step});"
                )
                .unwrap();
                writeln!(
                    source,
                    "    if (std::{module}::capacity(value) != requested_{step}) {{ return {}; }}",
                    step + 1
                )
                .unwrap();
            }
            4 => {
                writeln!(
                    source,
                    "    value = std::{module}::try_shrink_to_fit(value);"
                )
                .unwrap();
                writeln!(
                    source,
                    "    if (std::{module}::capacity(value) != std::{module}::len(value)) {{ return {}; }}",
                    step + 1
                )
                .unwrap();
            }
            5 => {
                writeln!(source, "    let copy_{step}: std::{module}::{map_type} = std::{module}::try_clone(value);").unwrap();
                writeln!(
                    source,
                    "    if (std::{module}::len(copy_{step}) != {}) {{ return {}; }}",
                    expected.len(),
                    step + 1
                )
                .unwrap();
                if let Some((first_key, first_item)) = expected.first() {
                    let replacement = (first_item + 1) % 6;
                    writeln!(source, "    if (!std::{module}::try_set(copy_{step}, v{first_key}, v{replacement})) {{ return {}; }}", step + 1).unwrap();
                    writeln!(source, "    if (!same(std::{module}::get_or(value, v{first_key}, fallback), v{first_item}) || !same(std::{module}::get_or(copy_{step}, v{first_key}, fallback), v{replacement})) {{ return {}; }}", step + 1).unwrap();
                }
                writeln!(source, "    std::{module}::destroy(copy_{step});").unwrap();
            }
            6 => {
                writeln!(source, "    value = std::{module}::clear(value);").unwrap();
                expected.clear();
            }
            _ => {
                writeln!(
                    source,
                    "    let old_capacity_{step}: i32 = std::{module}::capacity(value);"
                )
                .unwrap();
                writeln!(source, "    value = std::{module}::try_reserve(value, -1);").unwrap();
                writeln!(
                    source,
                    "    value = std::{module}::try_reserve(value, 268435456);"
                )
                .unwrap();
                writeln!(source, "    if (std::{module}::capacity(value) != old_capacity_{step}) {{ return {}; }}", step + 1).unwrap();
            }
        }
        check_state(&mut source, module, &expected, step);
    }
    writeln!(source, "    std::{module}::destroy(value);").unwrap();
    source.push_str("    return 0;\n}\n");
    source
}

fn run(kind: Kind) {
    let name = kind.module();
    let source = generate(kind);
    let entry = common::TempArtifact::new("laniusc_map", name, Some("lani"));
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
fn signed_map_matches_insertion_order_reference() {
    run(Kind::I32);
}

#[test]
fn unsigned_map_matches_insertion_order_reference() {
    run(Kind::U32);
}

#[test]
fn signed_two_word_map_matches_insertion_order_reference() {
    run(Kind::WideI64);
}

#[test]
fn unsigned_two_word_map_matches_insertion_order_reference() {
    run(Kind::WideU64);
}
