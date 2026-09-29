mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn imported_narrow_integer_range_methods_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for width in ["i8", "i16", "u8", "u16"] {
        let module = std::fs::read_to_string(root.join(format!("stdlib/core/range_{width}.lani")))
            .expect("read narrow range module");
        let entry = root.join(format!(
            "tests/fixtures/stdlib_foundation/core_range_{width}_aggregate.lani"
        ));
        let fixture = std::fs::read_to_string(&entry).expect("read narrow range fixture");
        assert_eq!(
            module
                .lines()
                .filter(|line| line.starts_with("    pub fn "))
                .count(),
            14,
            "{width} receiver method count"
        );
        for (receiver, name) in [
            ("half", "start"),
            ("half", "end"),
            ("half", "is_empty"),
            ("half", "contains"),
            ("half", "overlaps"),
            ("closed", "start"),
            ("closed", "end"),
            ("closed", "is_empty"),
            ("closed", "contains"),
            ("closed", "overlaps"),
            ("from", "start"),
            ("from", "contains"),
            ("to", "end"),
            ("to", "contains"),
        ] {
            assert!(
                fixture.contains(&format!("{receiver}.{name}(")),
                "{width} {receiver}.{name} lacks a runtime call"
            );
        }
        let stdlib_root = root.join("stdlib");
        let bytes =
            common::run_gpu_codegen_with_timeout("narrow integer range methods", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
            })
            .unwrap_or_else(|error| panic!("{width} range method compilation: {error}"));
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                "narrow integer range methods",
                &format!("range_{width}_methods"),
                &bytes,
            );
            assert_eq!(output.status.code(), Some(0), "{width}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}
