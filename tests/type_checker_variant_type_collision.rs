mod common;

use laniusc_compiler::compiler::{
    CompileError,
    EntrySourceRoots,
    compile_entry_to_x86_64_with_source_roots,
};

fn compile(case: &str, entry: &str) -> Result<Vec<u8>, CompileError> {
    let repository = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let root = repository
        .join("tests/fixtures/stdlib_compiler_state/variant_type_collision")
        .join(case);
    let entry = root.join(entry);
    let roots = EntrySourceRoots {
        stdlib_root: Some(repository.join("stdlib")),
        user_roots: vec![root],
    };
    common::run_gpu_codegen_with_timeout(&format!("variant/type collision {case}"), move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
}

fn execute(case: &str, entry: &str, status: i32) {
    let bytes = compile(case, entry).unwrap_or_else(|error| panic!("{case}/{entry}: {error}"));
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            format!("variant/type collision {case}"),
            "variant_type_collision",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(status), "{case}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{case}: {output:?}"
        );
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = (bytes, status);
}

#[test]
fn imported_enum_type_and_same_spelled_unit_variant_remain_distinct() {
    for case in ["enum_collision", "enum_control"] {
        execute(case, "main.lani", 3);
    }
}

#[test]
fn imported_unit_variant_does_not_replace_local_record_annotation() {
    for case in ["record_collision", "record_control"] {
        execute(case, "main.lani", 0);
    }
}

#[test]
fn local_type_annotations_and_qualified_unqualified_unit_values_execute() {
    execute("", "local.lani", 0);
}

#[test]
fn nominal_mismatches_and_unit_variant_type_annotations_are_rejected() {
    for (entry, diagnostic) in [
        ("wrong_nominal.lani", "LNC0006"),
        ("wrong_variant.lani", "LNC0006"),
        ("variant_as_type.lani", "LNC0007"),
    ] {
        let error = compile("enum_collision", entry)
            .expect_err("distinct nominal types and value-only variants cannot be types")
            .to_string();
        assert!(error.contains(diagnostic), "{entry}: {error}");
    }
}
