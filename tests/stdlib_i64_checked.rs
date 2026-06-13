mod common;

use laniusc::compiler::{load_entry_path_manifest_with_stdlib, type_check_entry_with_stdlib};

#[test]
fn core_i64_checked_abs_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry =
        common::TempArtifact::new("laniusc_stdlib_i64_checked", "checked_abs", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::i64;
import core::option;

fn main() {
    let positive: core::option::Option<i64> = core::i64::checked_abs(7);
    let negative: core::option::Option<i64> = checked_abs(-7);
    let min_value: core::option::Option<i64> = core::i64::checked_abs(core::i64::MIN);
    let positive_value: i64 = core::option::unwrap_or(positive, 0);
    let negative_value: i64 = unwrap_or(negative, 0);
    let min_is_none: bool = core::option::is_none(min_value);
    if (positive_value != 7 || negative_value != 7 || !min_is_none) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core i64 and option imports");
    for relative_path in ["core/i64.lani", "core/option.lani", "core/result.lani"] {
        assert!(
            manifest
                .files
                .iter()
                .any(|file| file.library_id == 0 && file.path == stdlib_root.join(relative_path)),
            "path manifest should include {relative_path} from the stdlib root"
        );
    }

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::i64 checked_abs helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::i64::checked_abs should type check through --stdlib-root as Option<i64>");
}

#[test]
fn core_i64_checked_arithmetic_option_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_i64_checked",
        "checked_arithmetic",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::i64;
import core::option;

fn main() {
    let sum: core::option::Option<i64> = core::i64::checked_add(40, 2);
    let high_overflow: core::option::Option<i64> =
        checked_add(core::i64::MAX, 1);
    let low_overflow: core::option::Option<i64> =
        core::i64::checked_add(core::i64::MIN, -1);
    let diff: core::option::Option<i64> = core::i64::checked_sub(42, 4);
    let high_sub_overflow: core::option::Option<i64> =
        checked_sub(core::i64::MAX, -1);
    let low_sub_overflow: core::option::Option<i64> =
        core::i64::checked_sub(core::i64::MIN, 1);

    let sum_value: i64 = core::option::unwrap_or(sum, 0);
    let diff_value: i64 = core::option::unwrap_or(diff, 0);
    let high_add_is_none: bool = core::option::is_none(high_overflow);
    let low_add_is_none: bool = is_none(low_overflow);
    let high_sub_is_none: bool = core::option::is_none(high_sub_overflow);
    let low_sub_is_none: bool = is_none(low_sub_overflow);

    if (sum_value != 42 || diff_value != 38) {
        return 1;
    }
    if (!high_add_is_none || !low_add_is_none || !high_sub_is_none || !low_sub_is_none) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core i64 and option imports");
    for relative_path in ["core/i64.lani", "core/option.lani", "core/result.lani"] {
        assert!(
            manifest
                .files
                .iter()
                .any(|file| file.library_id == 0 && file.path == stdlib_root.join(relative_path)),
            "path manifest should include {relative_path} from the stdlib root"
        );
    }

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::i64 checked arithmetic Option helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::i64 checked arithmetic should type check through --stdlib-root as Option<i64>");
}

#[test]
fn core_i64_saturating_arithmetic_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_i64_saturating",
        "saturating_arithmetic",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::i64;

fn main() {
    let high_add: i64 = core::i64::saturating_add(core::i64::MAX, 1);
    let low_add: i64 = saturating_add(core::i64::MIN, -1);
    let normal_add: i64 = core::i64::saturating_add(40, 2);
    let high_sub: i64 = saturating_sub(core::i64::MAX, -1);
    let low_sub: i64 = core::i64::saturating_sub(core::i64::MIN, 1);
    let normal_sub: i64 = saturating_sub(42, 4);
    let normal_distance: i64 = core::i64::saturating_abs_diff(42, 4);
    let reverse_distance: i64 = saturating_abs_diff(4, 42);
    let clamped_distance: i64 =
        core::i64::saturating_abs_diff(core::i64::MIN, core::i64::MAX);

    if (high_add != core::i64::MAX || low_add != core::i64::MIN) {
        return 1;
    }
    if (high_sub != core::i64::MAX || low_sub != core::i64::MIN) {
        return 1;
    }
    if (normal_add != 42 || normal_sub != 38) {
        return 1;
    }
    if (normal_distance != 38 || reverse_distance != 38 || clamped_distance != core::i64::MAX) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core i64 import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/i64.lani")),
        "path manifest should include core/i64.lani from the stdlib root"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::i64 saturating arithmetic helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::i64 saturating arithmetic and distance helpers should type check through --stdlib-root");
}
