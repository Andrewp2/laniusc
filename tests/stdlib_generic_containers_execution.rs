mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn run_fixture(name: &str) {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{name}: compile: {error}"));
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("generic_containers", name, &bytes);
        assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

// One program uses core::vec over i32, char and core::pair::Pair<char, i32>,
// core::set over i32 and char, and the Option combinators, and exits 0.
#[test]
fn generic_vec_set_pair_and_option_consumer_executes() {
    run_fixture("generic_containers");
}

// User generics over Vec<T, N> with record T call core::vec from their own
// instances, so the library bodies are replayed with a type argument from
// the program: records, a record array, Option and Pair of a record, and a
// record inside a record.
#[test]
fn user_generics_over_record_vecs_execute() {
    run_fixture("generic_record_vec");
}

// Guard the generic modules against a public function with no call site in
// the consumer program.
#[test]
fn every_public_generic_container_function_has_a_runtime_case() {
    let fixture = include_str!("fixtures/stdlib_foundation/generic_containers.lani");
    let modules = [
        ("vec", include_str!("../stdlib/core/vec.lani")),
        ("set", include_str!("../stdlib/core/set.lani")),
        ("pair", include_str!("../stdlib/core/pair.lani")),
    ];
    for (module, source) in modules {
        for line in source.lines() {
            let Some(tail) = line.strip_prefix("pub fn ") else {
                continue;
            };
            let name = tail
                .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
                .next()
                .expect("function has a name");
            let call = format!("core::{module}::{name}(");
            assert!(fixture.contains(&call), "{call} lacks a runtime case");
        }
    }
}
