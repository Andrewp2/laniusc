#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{cmp::Ordering, os::unix::fs::PermissionsExt, process::Command, time::Duration};

fn compile(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let exe = common::TempArtifact::new("laniusc_comparison", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn flags(equal: bool, less: bool, greater: bool) -> u32 {
    u32::from(equal)
        | (u32::from(!equal) << 1)
        | (u32::from(less) << 2)
        | (u32::from(less || equal) << 3)
        | (u32::from(greater) << 4)
        | (u32::from(greater || equal) << 5)
}
fn edges(width: u8) -> Vec<u64> {
    let (sign, inf, quiet, fraction) = if width == 32 {
        (1u64 << 31, 0x7f80_0000, 1u64 << 22, 23)
    } else {
        (1u64 << 63, 0x7ff0_0000_0000_0000, 1u64 << 51, 52)
    };
    let mut values = vec![
        0,
        1,
        2,
        (1u64 << fraction) - 1,
        1u64 << fraction,
        inf - 1,
        inf,
        inf + 1,
        inf + 2,
        inf + quiet - 1,
        inf + quiet,
        inf + quiet + 1,
        inf + quiet + 2,
        sign - 1,
    ];
    values.extend(values.clone().into_iter().map(|bits| bits | sign));
    values
}
#[test]
fn native_partial_and_total_float_key_comparisons_match_independent_oracles() {
    let exe = compile("tests/fixtures/stdlib_foundation/comparison_model.lani");
    let mut pairs = Vec::new();
    let mut seed = 0x16d3_d1f2_8ce3_a2b9u64;
    for width in [32, 64] {
        for a in edges(width) {
            for b in edges(width) {
                pairs.push((width, a, b));
            }
        }
        for index in 0..8000 {
            let mut next = || {
                seed ^= seed << 13;
                seed ^= seed >> 7;
                seed ^= seed << 17;
                if width == 32 {
                    seed as u32 as u64
                } else {
                    seed
                }
            };
            let a = next();
            let b = if index % 11 == 0 { a } else { next() };
            pairs.push((width, a, b));
        }
    }
    let mut hashes = std::collections::HashMap::new();
    for pairs in pairs.chunks(6000) {
        let mut bytes = Vec::new();
        for &(width, a, b) in pairs {
            bytes.push(width);
            bytes.extend(a.to_le_bytes());
            bytes.extend(b.to_le_bytes());
        }
        let input = common::TempArtifact::new("laniusc_comparison", "pairs", None);
        input.write_bytes(bytes);
        let output = common::process_output_with_timeout(
            "native comparison pair batch",
            Command::new(exe.path()).stdin(std::fs::File::open(input.path()).unwrap()),
            Duration::from_secs(15),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
        assert_eq!(output.stdout.len(), pairs.len() * 28);
        for (&(width, a, b), reply) in pairs.iter().zip(output.stdout.chunks_exact(28)) {
            let words: Vec<u32> = reply
                .chunks_exact(4)
                .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
                .collect();
            let (equal, less, greater, partial, total) = if width == 32 {
                let x = f32::from_bits(a as u32);
                let y = f32::from_bits(b as u32);
                (x == y, x < y, x > y, x.partial_cmp(&y), x.total_cmp(&y))
            } else {
                let x = f64::from_bits(a);
                let y = f64::from_bits(b);
                (x == y, x < y, x > y, x.partial_cmp(&y), x.total_cmp(&y))
            };
            let relation = match partial {
                Some(Ordering::Less) => -1,
                Some(Ordering::Equal) => 0,
                Some(Ordering::Greater) => 1,
                None => 2,
            };
            let label = format!("f{width} {a:#x} {b:#x}");
            assert_eq!(
                words[0],
                flags(equal, less, greater),
                "{label}: partial predicates"
            );
            assert_eq!(words[1] as i32, relation, "{label}: partial result");
            assert_eq!(
                words[2],
                flags(
                    total == Ordering::Equal,
                    total == Ordering::Less,
                    total == Ordering::Greater
                ),
                "{label}: total predicates"
            );
            assert_eq!(
                u64::from(words[5]) | (u64::from(words[6]) << 32),
                a,
                "{label}: bits"
            );
            if a == b {
                assert_eq!(words[3], words[4], "{label}: equal keys must hash equally");
            }
            for (bits, hash) in [(a, words[3]), (b, words[4])] {
                if let Some(previous) = hashes.insert((width, bits), hash) {
                    assert_eq!(previous, hash, "{label}: stable hash");
                }
            }
        }
    }
}
#[test]
fn generic_partial_membership_and_total_float_collections_execute() {
    for name in [
        "comparison_membership",
        "comparison_collections",
        "core_cmp_free",
    ] {
        let exe = compile(&format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        let output = common::short_process_output_with_timeout(name, &mut Command::new(exe.path()));
        assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{name}: {output:?}"
        );
    }
}
#[test]
fn native_floats_cannot_satisfy_lawful_key_or_sort_contracts() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for width in ["f32", "f64"] {
        for operation in ["sort", "tree", "set", "hash"] {
            let statement = match operation {
                "sort" => {
                    format!("let values: [{width};2] = [zero,one]; core::slice::sort(values,2);")
                }
                "tree" => format!(
                    "let map: alloc::tree_map::TreeMap<{width},i32> = alloc::tree_map::new(); map.try_insert(zero,1);"
                ),
                "set" => format!(
                    "let set: std::set::Set<{width}> = std::set::new(); std::set::try_insert(set,zero);"
                ),
                "hash" => format!(
                    "let map: alloc::hash_map::HashMap<{width},i32> = alloc::hash_map::new(); map.try_insert(zero,1);"
                ),
                _ => unreachable!(),
            };
            let entry = common::TempArtifact::new("laniusc_comparison", "reject", Some("lani"));
            entry.write_str(&format!(
                "module app::main; import core::slice; import alloc::tree_map; import alloc::hash_map; import std::set; fn main() -> i32 {{ let zero: {width} = 0.0; let one: {width} = 1.0; {statement} return 0; }}"
            ));
            let path = entry.path().to_path_buf();
            let stdlib = root.join("stdlib");
            let result = common::run_gpu_codegen_with_timeout(operation, move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&path, &stdlib),
                )
            });
            let error = result.expect_err(&format!("native {width} accepted as {operation}"));
            assert_eq!(
                error.to_public_diagnostic().code,
                "LNC0008",
                "{width} {operation}: {error:?}"
            );
        }
    }
}

#[test]
fn migrated_generic_range_slice_option_and_float_program_execute() {
    for name in ["core_range", "core_slice", "core_option_result"] {
        let exe = compile(&format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        let output = common::short_process_output_with_timeout(name, &mut Command::new(exe.path()));
        assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{name}: {output:?}"
        );
    }
    let exe = compile("sample_programs/floating_window_total.lani");
    let output =
        common::short_process_output_with_timeout("floating window", &mut Command::new(exe.path()));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(output.stdout, b"2\n");
    assert!(output.stderr.is_empty());
}
#[test]
fn migrated_owned_collection_callers_execute() {
    for name in [
        "std_map",
        "std_set",
        "std_vec_order",
        "alloc_vec_types",
        "alloc_deque_types",
        "binary_heap_types",
        "tree_map_types",
        "arena_types",
    ] {
        let exe = compile(&format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        let output = common::short_process_output_with_timeout(name, &mut Command::new(exe.path()));
        assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{name}: {output:?}"
        );
    }
}

#[test]
fn concrete_float_key_vector_access_and_generic_slice_control_execute() {
    for path in [
        "tests/fixtures/stdlib_foundation/comparison_vec_concrete.lani",
        "tests/fixtures/stdlib_compiler_state/comparison/generic-record-vec-slice-control.lani",
        "tests/fixtures/stdlib_compiler_state/comparison/generic-partial-cmp-match-control.lani",
    ] {
        let exe = compile(path);
        let output = common::short_process_output_with_timeout(path, &mut Command::new(exe.path()));
        assert_eq!(output.status.code(), Some(0), "{path}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{path}: {output:?}"
        );
    }
}
