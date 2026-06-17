mod common;

use laniusc_compiler::compiler::{
    load_entry_path_manifest_with_stdlib,
    runtime_bound_api_diagnostic_info,
    type_check_entry_with_stdlib,
};

#[test]
fn core_unsigned_between_exclusive_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_unsigned_ranges",
        "between_exclusive",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::u32;
import core::u8;

fn main() {
    let u32_low: u32 = 2;
    let u32_high: u32 = 8;
    let u32_inside: bool = core::u32::between_exclusive(5, u32_low, u32_high);
    let u32_lower_edge: bool = core::u32::between_exclusive(u32_low, u32_low, u32_high);
    let u32_upper_edge: bool = core::u32::between_exclusive(u32_high, u32_low, u32_high);
    let u32_below: bool = core::u32::between_exclusive(1, u32_low, u32_high);

    let u8_low: u8 = 3;
    let u8_high: u8 = 9;
    let u8_inside: bool = core::u8::between_exclusive(7, u8_low, u8_high);
    let u8_lower_edge: bool = core::u8::between_exclusive(u8_low, u8_low, u8_high);
    let u8_upper_edge: bool = core::u8::between_exclusive(u8_high, u8_low, u8_high);
    let u8_above: bool = core::u8::between_exclusive(12, u8_low, u8_high);

    if (!u32_inside || u32_lower_edge || u32_upper_edge || u32_below) {
        return 1;
    }
    if (!u8_inside || u8_lower_edge || u8_upper_edge || u8_above) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load unsigned range helper modules");
    for relative_path in ["core/u32.lani", "core/u8.lani"] {
        assert!(
            manifest
                .files
                .iter()
                .any(|file| file.library_id == 0 && file.path == stdlib_root.join(relative_path)),
            "path manifest should include {relative_path} from the stdlib root"
        );
    }
    for helper_name in [
        "core::u32::between_exclusive",
        "core::u8::between_exclusive",
    ] {
        assert!(
            runtime_bound_api_diagnostic_info(helper_name).is_none(),
            "{helper_name} is a source-level helper and must not claim a runtime binding"
        );
    }

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root unsigned between_exclusive helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("unsigned between_exclusive helpers should type check through --stdlib-root");
}

#[test]
fn core_u8_abs_diff_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_unsigned_ranges",
        "u8_abs_diff",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::u8;

fn main() {
    let low: u8 = 3;
    let high: u8 = 9;
    let forward: u8 = core::u8::abs_diff(high, low);
    let reverse: u8 = abs_diff(low, high);
    let equal: u8 = core::u8::abs_diff(high, high);
    if (forward != 6 || reverse != 6 || equal != 0) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::u8");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u8.lani")),
        "path manifest should include core::u8 from the stdlib root"
    );
    assert!(
        runtime_bound_api_diagnostic_info("core::u8::abs_diff").is_none(),
        "core::u8::abs_diff is a source-level helper and must not claim a runtime binding"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u8 abs_diff helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::u8::abs_diff should type check through --stdlib-root");
}

#[test]
fn core_u32_saturating_mul_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_unsigned_ranges",
        "u32_saturating_mul",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::u32;

fn main() {
    let zero: u32 = core::u32::saturating_mul(99, 0);
    let small: u32 = saturating_mul(6, 7);
    let capped_high: u32 = core::u32::saturating_mul(core::u32::MAX, 2);
    let capped_low: u32 = core::u32::saturating_mul(2, core::u32::MAX);

    if (zero != 0 || small != 42) {
        return 1;
    }
    if (capped_high != core::u32::MAX || capped_low != core::u32::MAX) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::u32");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u32.lani")),
        "path manifest should include core::u32 from the stdlib root"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u32 saturating_mul helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::u32::saturating_mul should type check through --stdlib-root");
}

#[test]
fn core_u32_is_multiple_of_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_unsigned_ranges",
        "u32_is_multiple_of",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::u32;

fn main() {
    let twelve: u32 = 12;
    let six: u32 = 6;
    let five: u32 = 5;
    let zero: u32 = 0;

    let exact: bool = core::u32::is_multiple_of(twelve, six);
    let not_exact: bool = is_multiple_of(twelve, five);
    let zero_divisor: bool = core::u32::is_multiple_of(twelve, zero);
    let zero_value: bool = is_multiple_of(zero, six);

    if (!exact || not_exact || zero_divisor || !zero_value) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::u32");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u32.lani")),
        "path manifest should include core::u32 from the stdlib root"
    );
    assert!(
        runtime_bound_api_diagnostic_info("core::u32::is_multiple_of").is_none(),
        "core::u32::is_multiple_of is a source-level helper and must not claim a runtime binding"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u32 is_multiple_of helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::u32::is_multiple_of should type check through --stdlib-root");
}

#[test]
fn core_u8_is_multiple_of_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_unsigned_ranges",
        "u8_is_multiple_of",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::u8;

fn main() {
    let twelve: u8 = 12;
    let six: u8 = 6;
    let five: u8 = 5;
    let zero: u8 = 0;

    let exact: bool = core::u8::is_multiple_of(twelve, six);
    let not_exact: bool = is_multiple_of(twelve, five);
    let zero_divisor: bool = core::u8::is_multiple_of(twelve, zero);
    let zero_value: bool = is_multiple_of(zero, six);

    if (!exact || not_exact || zero_divisor || !zero_value) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::u8");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u8.lani")),
        "path manifest should include core::u8 from the stdlib root"
    );
    assert!(
        runtime_bound_api_diagnostic_info("core::u8::is_multiple_of").is_none(),
        "core::u8::is_multiple_of is a source-level helper and must not claim a runtime binding"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u8 is_multiple_of helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::u8::is_multiple_of should type check through --stdlib-root");
}
