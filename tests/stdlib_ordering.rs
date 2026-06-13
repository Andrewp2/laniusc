mod common;

use laniusc::compiler::{
    load_entry_path_manifest_with_stdlib,
    runtime_bound_api_diagnostic_info,
    type_check_entry_with_stdlib,
};

#[test]
fn core_ordering_predicates_check_through_stdlib_root() {
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

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::ordering predicates",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::ordering predicates should type check through --stdlib-root");
}

#[test]
fn core_ordering_integer_comparators_type_check_through_stdlib_root() {
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
    let i64_less: core::ordering::Ordering = core::ordering::compare_i64(-4, 3);
    let i64_equal: Ordering = compare_i64(9, 9);
    let i64_greater: core::ordering::Ordering = compare_i64(12, -8);

    let u32_less: Ordering = core::ordering::compare_u32(2, 5);
    let u32_equal: core::ordering::Ordering = compare_u32(7, 7);
    let u32_greater: Ordering = core::ordering::compare_u32(11, 4);

    let u8_less: core::ordering::Ordering = core::ordering::compare_u8(1, 2);
    let u8_equal: Ordering = compare_u8(8, 8);
    let u8_greater: core::ordering::Ordering = core::ordering::compare_u8(250, 3);

    let i64_less_ok: bool = core::ordering::is_less(i64_less);
    let i64_equal_ok: bool = core::ordering::is_equal(i64_equal);
    let i64_greater_ok: bool = core::ordering::is_greater(i64_greater);

    let u32_less_ok: bool = is_less(u32_less);
    let u32_equal_ok: bool = is_equal(u32_equal);
    let u32_greater_ok: bool = is_greater(u32_greater);

    let u8_less_ok: bool = core::ordering::is_less(u8_less);
    let u8_equal_ok: bool = core::ordering::is_equal(u8_equal);
    let u8_greater_ok: bool = core::ordering::is_greater(u8_greater);

    if (!i64_less_ok || !i64_equal_ok || !i64_greater_ok) {
        return 1;
    }
    if (!u32_less_ok || !u32_equal_ok || !u32_greater_ok) {
        return 1;
    }
    if (!u8_less_ok || !u8_equal_ok || !u8_greater_ok) {
        return 1;
    }
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
        "core::ordering::compare_i64",
        "core::ordering::compare_u32",
        "core::ordering::compare_u8",
    ] {
        assert!(
            runtime_bound_api_diagnostic_info(helper_name).is_none(),
            "{helper_name} is a source-level helper and must not claim a runtime binding"
        );
    }

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::ordering integer comparators",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::ordering integer comparators should type check through --stdlib-root");
}
