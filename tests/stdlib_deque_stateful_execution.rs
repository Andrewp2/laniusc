mod common;

use std::{collections::VecDeque, fmt::Write};

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[derive(Clone, Copy)]
enum Kind {
    Bool,
    I8,
    I16,
    U8,
    I32,
    U32,
    WideU64,
    WideI64,
}

impl Kind {
    fn module(self) -> &'static str {
        match self {
            Self::Bool => "deque_bool",
            Self::I8 => "deque_i8",
            Self::I16 => "deque_i16",
            Self::U8 => "deque_u8",
            Self::I32 => "deque_i32",
            Self::U32 => "deque_u32",
            Self::WideU64 => "deque_wide_u64",
            Self::WideI64 => "deque_wide_i64",
        }
    }

    fn deque_type(self) -> &'static str {
        match self {
            Self::Bool => "DequeBool",
            Self::I8 => "DequeI8",
            Self::I16 => "DequeI16",
            Self::U8 => "DequeU8",
            Self::I32 => "DequeI32",
            Self::U32 => "DequeU32",
            Self::WideU64 => "DequeWideU64",
            Self::WideI64 => "DequeWideI64",
        }
    }

    fn value_type(self) -> &'static str {
        match self {
            Self::Bool => "bool",
            Self::I8 => "i8",
            Self::I16 => "i16",
            Self::U8 => "u8",
            Self::I32 => "i32",
            Self::U32 => "u32",
            Self::WideU64 => "core::wide_u64::WideU64",
            Self::WideI64 => "core::wide_i64::WideI64",
        }
    }

    fn literal(self, bits: u64) -> String {
        match self {
            Self::Bool => (bits & 1 == 1).to_string(),
            Self::I8 => (bits as i8).to_string(),
            Self::I16 => (bits as i16).to_string(),
            Self::U8 => (bits as u8).to_string(),
            Self::I32 => (bits as i32).to_string(),
            Self::U32 => (bits as u32).to_string(),
            Self::WideU64 => format!(
                "core::wide_u64::from_words({}, {})",
                (bits >> 32) as u32,
                bits as u32
            ),
            Self::WideI64 => format!(
                "core::wide_i64::from_words({}, {})",
                (bits >> 32) as u32,
                bits as u32
            ),
        }
    }

    fn equal(self, left: &str, right: &str) -> String {
        match self {
            Self::Bool | Self::I8 | Self::I16 | Self::U8 | Self::I32 | Self::U32 => {
                format!("{left} == {right}")
            }
            Self::WideU64 => format!("core::wide_u64::eq({left}, {right})"),
            Self::WideI64 => format!("core::wide_i64::eq({left}, {right})"),
        }
    }
}

const VALUES: [u64; 10] = [
    0,
    1,
    2,
    3,
    0x8000_0000,
    0xffff_ffff,
    0x1_0000_0000,
    0x8000_0000_0000_0000,
    0xffff_ffff_ffff_ffff,
    0x7fff_ffff_ffff_ffff,
];

fn next(seed: &mut u64) -> u64 {
    *seed ^= *seed << 13;
    *seed ^= *seed >> 7;
    *seed ^= *seed << 17;
    *seed
}

fn generate(kind: Kind) -> String {
    let module = kind.module();
    let ty = kind.deque_type();
    let item_type = kind.value_type();
    let mut source = format!("module app::main;\nimport std::{module};\n");
    if matches!(kind, Kind::WideU64) {
        source.push_str("import core::wide_u64;\n");
    }
    if matches!(kind, Kind::WideI64) {
        source.push_str("import core::wide_i64;\n");
    }
    source.push_str("fn main() -> i32 {\n");
    for (index, bits) in VALUES.into_iter().enumerate() {
        writeln!(
            source,
            "    let v{index}: {item_type} = {};",
            kind.literal(bits)
        )
        .unwrap();
    }
    writeln!(
        source,
        "    let value: std::{module}::{ty} = std::{module}::new();"
    )
    .unwrap();
    let mut reference = VecDeque::<usize>::new();
    let mut seed = 0xd00d_feed_cafe_babe_u64;
    for step in 0..48 {
        let draw = next(&mut seed);
        let item = ((draw >> 8) as usize) % VALUES.len();
        let operation = match step {
            0..=2 => 0,
            3 => 4,
            4 => 0,
            5 => 2,
            6 => 6,
            7 => 2,
            8 => 5,
            9 => 7,
            10 => 10,
            _ => (draw % 11) as u32,
        };
        match operation {
            0 | 1 => {
                writeln!(
                    source,
                    "    value = std::{module}::try_push_back(value, v{item});"
                )
                .unwrap();
                reference.push_back(item);
            }
            2 | 3 => {
                writeln!(
                    source,
                    "    value = std::{module}::try_push_front(value, v{item});"
                )
                .unwrap();
                reference.push_front(item);
            }
            4 => {
                writeln!(source, "    value = std::{module}::try_pop_front(value);").unwrap();
                reference.pop_front();
            }
            5 => {
                writeln!(source, "    value = std::{module}::try_pop_back(value);").unwrap();
                reference.pop_back();
            }
            6 => {
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
            7 => {
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
            8 => {
                if reference.is_empty() {
                    writeln!(
                        source,
                        "    if (std::{module}::try_set(value, -1, v{item})) {{ return {}; }}",
                        step + 1
                    )
                    .unwrap();
                } else {
                    let index = ((draw >> 16) as usize) % reference.len();
                    writeln!(
                        source,
                        "    if (!std::{module}::try_set(value, {index}, v{item})) {{ return {}; }}",
                        step + 1
                    )
                    .unwrap();
                    reference[index] = item;
                }
            }
            9 => {
                if reference.len() < 2 {
                    writeln!(
                        source,
                        "    if (std::{module}::try_swap(value, -1, 0)) {{ return {}; }}",
                        step + 1
                    )
                    .unwrap();
                } else {
                    let last = reference.len() - 1;
                    writeln!(
                        source,
                        "    if (!std::{module}::try_swap(value, 0, {last})) {{ return {}; }}",
                        step + 1
                    )
                    .unwrap();
                    reference.swap(0, last);
                }
            }
            _ => {
                writeln!(
                    source,
                    "    let copy_{step}: std::{module}::{ty} = std::{module}::try_clone(value);"
                )
                .unwrap();
                writeln!(
                    source,
                    "    if (std::{module}::len(copy_{step}) != {}) {{ return {}; }}",
                    reference.len(),
                    step + 1
                )
                .unwrap();
                for (index, value_index) in reference.iter().enumerate() {
                    let observed = format!("std::{module}::at_or(copy_{step}, {index}, v0)");
                    let equality = kind.equal(&observed, &format!("v{value_index}"));
                    writeln!(source, "    if (!({equality})) {{ return {}; }}", step + 1).unwrap();
                }
                writeln!(source, "    std::{module}::destroy(copy_{step});").unwrap();
            }
        }
        writeln!(
            source,
            "    if (std::{module}::len(value) != {}) {{ return {}; }}",
            reference.len(),
            step + 1
        )
        .unwrap();
        writeln!(
            source,
            "    if (std::{module}::capacity(value) < std::{module}::len(value)) {{ return {}; }}",
            step + 1
        )
        .unwrap();
        for (index, value_index) in reference.iter().enumerate() {
            let observed = format!("std::{module}::at_or(value, {index}, v0)");
            let equality = kind.equal(&observed, &format!("v{value_index}"));
            writeln!(source, "    if (!({equality})) {{ return {}; }}", step + 1).unwrap();
        }
    }
    writeln!(source, "    std::{module}::destroy(value);").unwrap();
    source.push_str("    return 0;\n}\n");
    source
}

fn run(kind: Kind) {
    let name = kind.module();
    let source = generate(kind);
    let entry = common::TempArtifact::new("laniusc_deque", name, Some("lani"));
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
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn boolean_deque_matches_reference() {
    run(Kind::Bool);
}

#[test]
fn signed_byte_deque_matches_reference() {
    run(Kind::I8);
}

#[test]
fn signed_halfword_deque_matches_reference() {
    run(Kind::I16);
}

#[test]
fn byte_deque_matches_reference() {
    run(Kind::U8);
}

#[test]
fn signed_scalar_deque_matches_reference() {
    run(Kind::I32);
}

#[test]
fn unsigned_scalar_deque_matches_reference() {
    run(Kind::U32);
}

#[test]
fn unsigned_two_word_deque_matches_reference() {
    run(Kind::WideU64);
}

#[test]
fn signed_two_word_deque_matches_reference() {
    run(Kind::WideI64);
}
