mod common;

use laniusc_compiler::compiler::{
    compile_entry_to_x86_64_with_stdlib,
    load_entry_path_manifest_with_stdlib,
    runtime_bound_api_diagnostic_info,
};

#[test]
fn core_ordering_direct_imported_variants_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_ordering_variant_import.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("imported ordering variants", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile direct imported fieldless enum variants");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported ordering variants",
            "repro_ordering_variant_import",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn core_ordering_unqualified_imported_variants_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_ordering_variant_unqualified.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("unqualified ordering variants", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile unqualified imported fieldless enum variants");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "unqualified ordering variants",
            "repro_ordering_variant_unqualified",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn core_ordering_inferred_imported_variant_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_ordering_variant_inferred.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("inferred ordering variant", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile an inferred local holding an imported variant");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "inferred ordering variant",
            "repro_ordering_variant_inferred",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn core_ordering_predicates_execute_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_ordering", "predicates", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::ordering;

fn main() {
    let less: core::ordering::Ordering = core::ordering::compare_i32(1, 2);
    let equal: Ordering = compare_i32(2, 2);
    let greater: core::ordering::Ordering = compare_i32(3, 2);
    let less_ok: bool = core::ordering::is_less(less);
    let equal_ok: bool = is_equal(equal);
    let greater_ok: bool = core::ordering::is_greater(greater);
    let reversed_less: core::ordering::Ordering = core::ordering::reverse(less);
    let reversed_equal: core::ordering::Ordering = reverse(equal);
    let fallback: core::ordering::Ordering = core::ordering::then(equal, greater);
    let kept: core::ordering::Ordering = then(less, greater);
    let less_rank: i32 = core::ordering::to_i32(less);
    let equal_rank: i32 = to_i32(equal);
    let greater_rank: i32 = core::ordering::to_i32(greater);
    let less_rejects_equal: bool = is_less(core::ordering::compare_i32(2, 2));
    let equal_rejects_greater: bool = core::ordering::is_equal(compare_i32(3, 2));
    let greater_rejects_less: bool = is_greater(core::ordering::compare_i32(1, 2));
    let less_or_equal_less: bool = core::ordering::is_less_or_equal(less);
    let less_or_equal_equal: bool = is_less_or_equal(equal);
    let less_or_equal_rejects_greater: bool = core::ordering::is_less_or_equal(greater);
    let greater_or_equal_greater: bool = core::ordering::is_greater_or_equal(greater);
    let greater_or_equal_equal: bool = is_greater_or_equal(equal);
    let greater_or_equal_rejects_less: bool = core::ordering::is_greater_or_equal(less);
    let not_equal_less: bool = core::ordering::is_not_equal(less);
    let not_equal_greater: bool = is_not_equal(greater);
    let not_equal_rejects_equal: bool = core::ordering::is_not_equal(equal);
    let reverse_less_ok: bool = core::ordering::is_greater(reversed_less);
    let reverse_equal_ok: bool = is_equal(reversed_equal);
    let fallback_ok: bool = core::ordering::is_greater(fallback);
    let kept_ok: bool = is_less(kept);
    if (!less_ok || !equal_ok || !greater_ok) {
        return 1;
    }
    if (!reverse_less_ok || !reverse_equal_ok || !fallback_ok || !kept_ok) {
        return 1;
    }
    if (less_rank != -1 || equal_rank != 0 || greater_rank != 1) {
        return 1;
    }
    if (less_rejects_equal || equal_rejects_greater || greater_rejects_less) {
        return 1;
    }
    if (!less_or_equal_less || !less_or_equal_equal || less_or_equal_rejects_greater) {
        return 1;
    }
    if (!greater_or_equal_greater || !greater_or_equal_equal || greater_or_equal_rejects_less) {
        return 1;
    }
    if (!not_equal_less || !not_equal_greater || not_equal_rejects_equal) {
        return 1;
    }
    return 0;
}
"#,
    );

    for helper_name in [
        "core::ordering::is_less",
        "core::ordering::is_equal",
        "core::ordering::is_greater",
        "core::ordering::is_less_or_equal",
        "core::ordering::is_greater_or_equal",
        "core::ordering::is_not_equal",
        "core::ordering::reverse",
        "core::ordering::then",
    ] {
        assert!(
            runtime_bound_api_diagnostic_info(helper_name).is_none(),
            "{helper_name} is a source-level helper and must not claim a runtime binding"
        );
    }

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::ordering import");
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("core/ordering.lani")
        }),
        "path manifest should include core::ordering from the stdlib root"
    );

    let entry_path = entry.path().to_path_buf();
    let bytes = common::run_gpu_codegen_with_timeout(
        "GPU compile stdlib-root core::ordering predicates",
        move || pollster::block_on(compile_entry_to_x86_64_with_stdlib(entry_path, stdlib_root)),
    )
    .expect("core::ordering predicates should compile through --stdlib-root");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("ordering predicates", "ordering_predicates", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn core_ordering_integer_comparators_execute_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_ordering",
        "integer_comparators",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::ordering;

fn main() {
    let u32_less: Ordering = core::ordering::compare_u32(2, 5);
    let u32_equal: core::ordering::Ordering = compare_u32(7, 7);
    let u32_greater: Ordering = core::ordering::compare_u32(11, 4);

    let u8_less: core::ordering::Ordering = core::ordering::compare_u8(1, 2);
    let u8_equal: Ordering = compare_u8(8, 8);
    let u8_greater: core::ordering::Ordering = core::ordering::compare_u8(250, 3);
    let u32_high: u32 = 2147483648;
    let u32_low: u32 = 2147483647;
    let u32_high_greater: bool = is_greater(compare_u32(u32_high, u32_low));

    let u32_less_ok: bool = is_less(u32_less);
    let u32_equal_ok: bool = is_equal(u32_equal);
    let u32_greater_ok: bool = is_greater(u32_greater);

    let u8_less_ok: bool = core::ordering::is_less(u8_less);
    let u8_equal_ok: bool = core::ordering::is_equal(u8_equal);
    let u8_greater_ok: bool = core::ordering::is_greater(u8_greater);

    if (!u32_less_ok || !u32_equal_ok || !u32_greater_ok) {
        return 1;
    }
    if (!u8_less_ok || !u8_equal_ok || !u8_greater_ok) {
        return 1;
    }
    if (!u32_high_greater) { return 3; }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::ordering import");
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("core/ordering.lani")
        }),
        "path manifest should include core::ordering from the stdlib root"
    );
    for helper_name in [
        "core::ordering::compare_u32",
        "core::ordering::compare_u8",
    ] {
        assert!(
            runtime_bound_api_diagnostic_info(helper_name).is_none(),
            "{helper_name} is a source-level helper and must not claim a runtime binding"
        );
    }

    let entry_path = entry.path().to_path_buf();
    let bytes = common::run_gpu_codegen_with_timeout(
        "GPU compile stdlib-root core::ordering integer comparators",
        move || pollster::block_on(compile_entry_to_x86_64_with_stdlib(entry_path, stdlib_root)),
    )
    .expect("core::ordering integer comparators should compile through --stdlib-root");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("ordering integers", "ordering_integers", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}
