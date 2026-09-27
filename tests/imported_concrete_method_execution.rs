mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn imported_generic_method_uses_the_concrete_unsigned_receiver() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_u32_range_method.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_u32_range_method_root");
    let bytes = common::run_gpu_codegen_with_timeout("imported u32 method", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile imported u32 method");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("imported u32 method", "imported_u32_method", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_unsigned_slices_accept_backed_fixed_arrays() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let cases = [
        (
            "u8",
            "tests/fixtures/stdlib_foundation/repro_u8_imported_slice.lani",
            "tests/fixtures/stdlib_foundation/repro_u8_imported_root",
        ),
        (
            "u32",
            "tests/fixtures/stdlib_foundation/repro_u32_imported_slice.lani",
            "tests/fixtures/stdlib_foundation/repro_u32_imported_root",
        ),
    ];
    for (name, entry, stdlib_root) in cases {
        let entry = root.join(entry);
        let stdlib_root = root.join(stdlib_root);
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|error| panic!("compile imported {name} slice: {error}"));

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn imported_byte_slice_rejects_an_integer_element_array() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_u8_imported_slice_wrong_element.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_u8_imported_root");
    let result = common::run_gpu_codegen_with_timeout("wrong byte slice element", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    });
    assert!(
        result.is_err(),
        "an i32 array was accepted as an imported [u8]"
    );
}
