mod common;

use laniusc_compiler::compiler::type_check_entry_with_stdlib;

#[test]
fn core_i32_checked_abs_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_i32", "checked_abs", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::i32;
import core::option;

fn main() {
    let positive: core::option::Option<i32> = core::i32::checked_abs(7);
    let negative: core::option::Option<i32> = checked_abs(-7);
    let min_value: core::option::Option<i32> = core::i32::checked_abs(core::i32::MIN);
    let positive_is_7: bool = core::option::contains_i32(positive, 7);
    let negative_is_7: bool = core::option::contains_i32(negative, 7);
    let min_is_none: bool = core::option::is_none(min_value);
    if (!positive_is_7 || !negative_is_7 || !min_is_none) {
        return 1;
    }
    return 0;
}
"#,
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::i32 checked_abs helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::i32::checked_abs should type check through --stdlib-root as Option<i32>");
}

#[test]
fn core_i32_between_exclusive_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_i32", "between_exclusive", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::i32;

fn main() {
    let inside: bool = core::i32::between_exclusive(5, 1, 9);
    let lower_edge: bool = between_exclusive(1, 1, 9);
    let upper_edge: bool = core::i32::between_exclusive(9, 1, 9);
    if (!inside || lower_edge || upper_edge) {
        return 1;
    }
    return 0;
}
"#,
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::i32 between_exclusive helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::i32 between_exclusive should type check through --stdlib-root");
}

#[test]
fn core_i32_nonnegative_nonpositive_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_i32",
        "nonnegative_nonpositive",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::i32;

fn main() {
    let zero_nonnegative: bool = core::i32::is_nonnegative(0);
    let positive_nonnegative: bool = is_nonnegative(5);
    let negative_nonnegative: bool = core::i32::is_nonnegative(-1);
    let zero_nonpositive: bool = core::i32::is_nonpositive(0);
    let negative_nonpositive: bool = is_nonpositive(-5);
    let positive_nonpositive: bool = core::i32::is_nonpositive(1);
    if (!zero_nonnegative || !positive_nonnegative || negative_nonnegative) {
        return 1;
    }
    if (!zero_nonpositive || !negative_nonpositive || positive_nonpositive) {
        return 1;
    }
    return 0;
}
"#,
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::i32 nonnegative/nonpositive helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::i32 nonnegative/nonpositive helpers should type check through --stdlib-root");
}
