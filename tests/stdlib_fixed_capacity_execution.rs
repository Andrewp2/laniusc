mod common;

use std::fmt::Write;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn run(name: &str, path: std::path::PathBuf, expected: i32) {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(
            &path,
            &root.join("stdlib"),
        ))
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("fixed_capacity", name, &bytes);
        assert_eq!(output.status.code(), Some(expected), "{name}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        if matches!(name, "fixed_capacity_vec" | "fixed_capacity_set") {
            assert_no_allocator_syscalls(name, &bytes);
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = (bytes, expected);
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn assert_no_allocator_syscalls(name: &str, bytes: &[u8]) {
    use std::{os::unix::fs::PermissionsExt, process::Command};
    if Command::new("strace").arg("-V").output().is_err() {
        return;
    }
    let executable = common::TempArtifact::new("fixed_capacity", name, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("fixed_capacity", "allocation_trace", None);
    let output = common::short_process_output_with_timeout(
        format!("{name} no allocation"),
        Command::new("strace")
            .args(["-qq", "-e", "trace=brk,mmap,mremap,munmap", "-o"])
            .arg(trace.path())
            .arg(executable.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
    let calls = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        calls.trim().is_empty(),
        "{name} allocated or released heap memory: {calls}"
    );
}

#[test]
fn symbolic_const_free_api_and_method_control_execute() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for name in ["borrowed-free-control", "fixed-const-method-control"] {
        run(
            name,
            root.join(format!(
                "tests/fixtures/stdlib_compiler_state/fixed_capacity/{name}.lani"
            )),
            0,
        );
    }
    let entry =
        root.join("tests/fixtures/stdlib_compiler_state/fixed_capacity/symbolic-const-method.lani");
    let result = common::run_gpu_codegen_with_timeout("symbolic const method lookup", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(
            &entry,
            &root.join("stdlib"),
        ))
    });
    let error = result.expect_err("update the documented method dependency if this now executes");
    assert!(error.to_string().contains("LNC0027"), "{error}");
}

fn fixture(name: &str) {
    run(
        name,
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join(format!("tests/fixtures/stdlib_foundation/{name}.lani")),
        0,
    );
}

#[test]
fn vector_mutations_errors_copies_views_and_cursors_execute() {
    fixture("fixed_capacity_vec");
}
#[test]
fn set_uses_full_equality_for_wide_values_and_records() {
    fixture("fixed_capacity_set");
}
#[test]
fn payload_widths_nested_variants_and_manual_ownership_execute() {
    fixture("fixed_capacity_payloads");
}
#[test]
fn migrated_user_equality_implementation_executes() {
    run(
        "fixed_capacity_user_eq",
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/generics_matrix/p50_user_impl_of_stdlib_bound_trait.lani"),
        42,
    );
}

fn next(seed: &mut u64) -> u64 {
    *seed ^= *seed << 13;
    *seed ^= *seed >> 7;
    *seed ^= *seed << 17;
    *seed
}

// Model checked transitions include failed operations, returned displaced values,
// every active element, membership, insertion order, and independent copies.
#[test]
fn vector_and_set_match_independent_stateful_models() {
    let mut source = String::from("module app::main;\nimport core::vec;\nimport core::set;\nimport core::result;\nimport core::option;\nfn main()->i32 {\nlet v:core::vec::Vec<i32,5> = core::vec::from_storage([0,0,0,0,0]);\nlet s:core::set::Set<i32,5> = core::set::from_storage([0,0,0,0,0]);\n");
    let mut vector = Vec::<i32>::new();
    let mut set = Vec::<i32>::new();
    let mut seed = 0x8e37_100d_cafe_2026;
    let mut saw = [false; 8]; // full Vec, replace, remove, changing reverse/sort, full Set, duplicate, removal
    for step in 0..32 {
        let draw = next(&mut seed);
        let random_item = ((draw >> 16) % 9) as i32 - 4;
        let random_index = ((draw >> 32) % 9) as i32 - 2;
        // Guarantee meaningful states before the seeded exploration: distinct
        // entries, displaced values, shifts, ordering, full and failed writes.
        let (operation, item, index) = match step {
            0 => (0, 3, 0),
            1 => (0, 1, 0),
            2 => (0, 2, 0),
            3 => (4, 4, 1),
            4 => (3, 0, 0),
            5 => (7, 0, 0),
            6 => (6, 0, 0),
            7 => (5, 1, 1),
            8 => (0, -1, 0),
            9 => (0, 0, 0),
            10 => (0, 4, 0),
            11 => (5, 4, 0),
            12 => (4, 2, 4),
            13 => (3, 0, 1),
            14 => (2, 0, 0),
            15 => (8, 0, 0),
            _ => (draw % 9, random_item, random_index),
        };
        let error = step + 1;
        match operation {
            0 | 1 => {
                let success = vector.len() < 5;
                saw[0] |= !success;
                writeln!(
                    source,
                    "if(core::result::is_ok(core::vec::try_push(v.borrow(),{item})) != {success}){{return {error};}}"
                )
                .unwrap();
                if success {
                    vector.push(item);
                }
            }
            2 => {
                let expected = vector.pop();
                writeln!(
                    source,
                    "let p{step}:core::option::Option<i32> = core::vec::pop(v.borrow());"
                )
                .unwrap();
                check_option(&mut source, &format!("p{step}"), expected, error);
            }
            3 => {
                let expected = if index >= 0 && (index as usize) < vector.len() {
                    saw[2] = true;
                    Some(vector.remove(index as usize))
                } else {
                    None
                };
                writeln!(source,"let r{step}:core::result::Result<i32,core::vec::Error> = core::vec::try_remove(v.borrow(),{index});").unwrap();
                check_result(&mut source, &format!("r{step}"), expected, error);
            }
            4 => {
                let expected = if index >= 0 && (index as usize) < vector.len() {
                    saw[1] = true;
                    Some(std::mem::replace(&mut vector[index as usize], item))
                } else {
                    None
                };
                writeln!(source,"let r{step}:core::result::Result<i32,core::vec::Error> = core::vec::try_set(v.borrow(),{index},{item});").unwrap();
                check_result(&mut source, &format!("r{step}"), expected, error);
            }
            5 => {
                let valid = index >= 0 && index as usize <= vector.len();
                let expected = if valid && vector.len() < 5 {
                    vector.insert(index as usize, item);
                    Some(vector.len() as i32)
                } else {
                    None
                };
                writeln!(source,"let r{step}:core::result::Result<i32,core::vec::Error> = core::vec::try_insert(v.borrow(),{index},{item});").unwrap();
                check_result(&mut source, &format!("r{step}"), expected, error);
            }
            6 => {
                saw[3] |= vector.iter().ne(vector.iter().rev());
                vector.reverse();
                writeln!(source, "core::vec::reverse(v.borrow());").unwrap();
            }
            7 => {
                saw[4] |= !vector.is_sorted();
                vector.sort();
                writeln!(source, "core::vec::sort(v.borrow());").unwrap();
            }
            _ => {
                vector.clear();
                writeln!(source, "core::vec::clear(v.borrow());").unwrap();
            }
        }
        let (insert, item) = match step {
            0..=4 => (true, step as i32 - 2),
            5 => (true, 0),
            6 => (true, 3),
            7 => (false, 4),
            8 => (false, 1),
            9 => (true, 1),
            _ => (draw & 4 == 0, random_item),
        };
        if insert {
            let present = set.contains(&item);
            let success = present || set.len() < 5;
            saw[5] |= !success;
            saw[6] |= present;
            writeln!(source,"let s{step}:core::result::Result<bool,core::set::Error> = core::set::try_insert(s.borrow(),{item}); if(core::result::is_ok(s{step}) != {success}){{return {error};}}").unwrap();
            if success {
                writeln!(
                    source,
                    "if(core::result::unwrap(s{step}) != {}){{return {error};}}",
                    !present
                )
                .unwrap();
            }
            if !present && success {
                set.push(item);
            }
        } else {
            let expected = set.iter().position(|v| *v == item).map(|i| set.remove(i));
            saw[7] |= expected.is_some();
            writeln!(
                source,
                "let q{step}:core::option::Option<i32> = core::set::remove(s.borrow(),{item});"
            )
            .unwrap();
            check_option(&mut source, &format!("q{step}"), expected, error);
        }
        writeln!(source,"if(core::vec::len(v.borrow())!={} || core::set::len(s.borrow())!={} || core::vec::capacity(v.borrow())!=5 || core::set::capacity(s.borrow())!=5){{return {error};}}",vector.len(),set.len()).unwrap();
        for (index, value) in vector.iter().enumerate() {
            writeln!(
                source,
                "if(core::vec::get_or(v.borrow(),{index},99)!={value}){{return {error};}}"
            )
            .unwrap();
        }
        for (index, value) in set.iter().enumerate() {
            writeln!(
                source,
                "if(core::set::at_or(s.borrow(),{index},99)!={value}){{return {error};}}"
            )
            .unwrap();
        }
        for value in -4..=4 {
            writeln!(
                source,
                "if(core::vec::contains(v.borrow(),{value})!={} || core::set::contains(s.borrow(),{value})!={}){{return {error};}}",
                vector.contains(&value),
                set.contains(&value)
            )
            .unwrap();
        }
        if step % 16 == 0 {
            writeln!(source,"let c{step}:core::vec::Vec<i32,5> = v; core::vec::clear(c{step}.borrow()); if(core::vec::len(v.borrow())!={}){{return {error};}}",vector.len()).unwrap();
        }
    }
    assert!(
        saw.into_iter().all(|hit| hit),
        "model workload lost a required transition: {saw:?}"
    );
    source.push_str("return 0; }");
    let artifact = common::TempArtifact::new("fixed_capacity", "model", Some("lani"));
    artifact.write_str(&source);
    run(
        "fixed_capacity_model_seed_8e37100dcafe2026",
        artifact.path().to_path_buf(),
        0,
    );
}

fn check_option(source: &mut String, name: &str, expected: Option<i32>, error: usize) {
    writeln!(
        source,
        "if(core::option::is_some({name}) != {}){{return {error};}}",
        expected.is_some()
    )
    .unwrap();
    if let Some(value) = expected {
        writeln!(
            source,
            "if(core::option::unwrap({name})!={value}){{return {error};}}"
        )
        .unwrap();
    }
}
fn check_result(source: &mut String, name: &str, expected: Option<i32>, error: usize) {
    writeln!(
        source,
        "if(core::result::is_ok({name}) != {}){{return {error};}}",
        expected.is_some()
    )
    .unwrap();
    if let Some(value) = expected {
        writeln!(
            source,
            "if(core::result::unwrap({name})!={value}){{return {error};}}"
        )
        .unwrap();
    }
}
