mod common;

use laniusc_compiler::compiler::{
    CompileError,
    EntrySourceRoots,
    compile_entry_to_x86_64_with_source_roots,
};

fn compile(entry: &str) -> Result<Vec<u8>, CompileError> {
    let repository = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let root = repository.join("tests/fixtures/stdlib_compiler_state/settings_array_view");
    let source = root.join(entry);
    let roots = EntrySourceRoots {
        stdlib_root: Some(repository.join("stdlib")),
        user_roots: vec![root.join("fields")],
    };
    common::run_gpu_codegen_with_timeout(
        &format!("array to slice record field {entry}"),
        move || pollster::block_on(compile_entry_to_x86_64_with_source_roots(&source, &roots)),
    )
}

fn execute(entry: &str, stdout: &[u8]) {
    let bytes = compile(entry).unwrap_or_else(|error| panic!("{entry}: {error}"));
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(entry, "array_slice_fields", &bytes);
        assert_eq!(output.status.code(), Some(0), "{entry}: {output:?}");
        assert_eq!(output.stdout, stdout, "{entry}: {output:?}");
        assert!(output.stderr.is_empty(), "{entry}: {output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = (bytes, stdout);
}

#[test]
fn native_array_slice_record_fields_preserve_descriptor_layout_and_aliases() {
    execute("fields/main.lani", b"");
}

#[test]
fn imported_text_view_matches_direct_array_vector_and_factory_controls() {
    execute("main.lani", b"6\n6\n6\n6\n");
}

#[test]
fn array_slice_record_fields_keep_element_types_invariant() {
    for entry in [
        "wrong_nominal.lani",
        "wrong_scalar.lani",
        "wrong_nested_extent.lani",
    ] {
        let error = compile(&format!("fields/{entry}"))
            .expect_err("array borrowing cannot change its element type")
            .to_string();
        assert!(error.contains("LNC0006"), "{entry}: {error}");
    }
}
