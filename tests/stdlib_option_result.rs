mod common;

use laniusc_compiler::compiler::{
    load_entry_path_manifest_with_stdlib,
    runtime_bound_api_diagnostic_info,
    type_check_entry_with_stdlib,
};

#[test]
fn core_i32_checked_add_option_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry =
        common::TempArtifact::new("laniusc_stdlib_option_result", "checked_add", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::i32;
import core::option;

fn main() {
    let sum: core::option::Option<i32> = core::i32::checked_add(40, 2);
    let high_overflow: core::option::Option<i32> =
        checked_add(core::i32::MAX, 1);
    let low_overflow: core::option::Option<i32> =
        core::i32::checked_add(core::i32::MIN, -1);
    let sum_is_42: bool = core::option::contains_i32(sum, 42);
    let high_is_none: bool = core::option::is_none(high_overflow);
    let low_is_none: bool = is_none(low_overflow);
    if (!sum_is_42 || !high_is_none || !low_is_none) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core integer and option imports");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/i32.lani")),
        "path manifest should include core::i32 from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/option.lani")),
        "path manifest should include core::option from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/result.lani")),
        "path manifest should include core::result through the option import chain"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::i32 checked_add Option helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::i32::checked_add should type check through --stdlib-root as Option<i32>");
}

#[test]
fn core_i32_checked_sub_option_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_option_result",
        "i32_checked_sub",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::i32;
import core::option;

fn main() {
    let diff: core::option::Option<i32> = core::i32::checked_sub(42, 4);
    let high_overflow: core::option::Option<i32> =
        checked_sub(core::i32::MAX, -1);
    let low_overflow: core::option::Option<i32> =
        core::i32::checked_sub(core::i32::MIN, 1);
    let diff_is_38: bool = core::option::contains_i32(diff, 38);
    let high_is_none: bool = core::option::is_none(high_overflow);
    let low_is_none: bool = is_none(low_overflow);
    if (!diff_is_38 || !high_is_none || !low_is_none) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core integer and option imports");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/i32.lani")),
        "path manifest should include core::i32 from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/option.lani")),
        "path manifest should include core::option from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/result.lani")),
        "path manifest should include core::result through the option import chain"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::i32 checked_sub Option helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::i32::checked_sub should type check through --stdlib-root as Option<i32>");
}

#[test]
fn core_u32_checked_add_option_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_option_result",
        "u32_checked_add",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::option;
import core::u32;

fn main() {
    let sum: core::option::Option<u32> = core::u32::checked_add(40, 2);
    let overflow: core::option::Option<u32> = checked_add(core::u32::MAX, 1);
    let sum_is_42: bool = core::option::contains_u32(sum, 42);
    let overflow_is_42: bool = contains_u32(overflow, 42);
    let overflow_is_none: bool = core::option::is_none(overflow);
    if (!sum_is_42 || overflow_is_42 || !overflow_is_none) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core unsigned integer and option imports");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u32.lani")),
        "path manifest should include core::u32 from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/option.lani")),
        "path manifest should include core::option from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/result.lani")),
        "path manifest should include core::result through the option import chain"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u32 checked_add Option helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::u32::checked_add should type check through --stdlib-root as Option<u32>");
}

#[test]
fn core_u32_checked_sub_option_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_option_result",
        "u32_checked_sub",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::option;
import core::u32;

fn main() {
    let diff: core::option::Option<u32> = core::u32::checked_sub(42, 4);
    let underflow: core::option::Option<u32> = checked_sub(3, 4);
    let diff_is_38: bool = core::option::contains_u32(diff, 38);
    let underflow_is_38: bool = contains_u32(underflow, 38);
    let underflow_is_none: bool = core::option::is_none(underflow);
    if (!diff_is_38 || underflow_is_38 || !underflow_is_none) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core unsigned integer and option imports");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u32.lani")),
        "path manifest should include core::u32 from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/option.lani")),
        "path manifest should include core::option from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/result.lani")),
        "path manifest should include core::result through the option import chain"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u32 checked_sub Option helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::u32::checked_sub should type check through --stdlib-root as Option<u32>");
}

#[test]
fn core_u32_checked_next_power_of_two_option_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_option_result",
        "u32_checked_next_power_of_two",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::option;
import core::u32;

fn main() {
    let zero: core::option::Option<u32> = core::u32::checked_next_power_of_two(0);
    let one: core::option::Option<u32> = checked_next_power_of_two(1);
    let already_power: core::option::Option<u32> =
        core::u32::checked_next_power_of_two(1024);
    let rounded: core::option::Option<u32> = checked_next_power_of_two(1025);
    let highest: core::option::Option<u32> =
        core::u32::checked_next_power_of_two(2147483648);
    let overflow: core::option::Option<u32> =
        checked_next_power_of_two(core::u32::MAX);

    let zero_is_one: bool = core::option::contains_u32(zero, 1);
    let one_is_one: bool = contains_u32(one, 1);
    let already_is_same: bool = core::option::contains_u32(already_power, 1024);
    let rounded_is_next: bool = contains_u32(rounded, 2048);
    let highest_is_some: bool = core::option::contains_u32(highest, 2147483648);
    let overflow_is_none: bool = core::option::is_none(overflow);

    if (!zero_is_one || !one_is_one || !already_is_same || !rounded_is_next) {
        return 1;
    }
    if (!highest_is_some || !overflow_is_none) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core unsigned integer and option imports");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u32.lani")),
        "path manifest should include core::u32 from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/option.lani")),
        "path manifest should include core::option from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/result.lani")),
        "path manifest should include core::result through the option import chain"
    );
    assert!(
        runtime_bound_api_diagnostic_info("core::u32::checked_next_power_of_two").is_none(),
        "core::u32::checked_next_power_of_two is a source-level helper and must not claim a runtime binding"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u32 checked_next_power_of_two Option helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect(
        "core::u32::checked_next_power_of_two should type check through --stdlib-root as Option<u32>",
    );
}

#[test]
fn core_u8_checked_add_option_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_option_result",
        "u8_checked_add",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::option;
import core::u8;

fn main() {
    let sum: core::option::Option<u8> = core::u8::checked_add(40, 2);
    let overflow: core::option::Option<u8> = checked_add(core::u8::MAX, 1);
    let sum_is_42: bool = core::option::contains_u8(sum, 42);
    let overflow_is_42: bool = contains_u8(overflow, 42);
    let overflow_is_none: bool = core::option::is_none(overflow);
    if (!sum_is_42 || overflow_is_42 || !overflow_is_none) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core byte and option imports");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u8.lani")),
        "path manifest should include core::u8 from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/option.lani")),
        "path manifest should include core::option from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/result.lani")),
        "path manifest should include core::result through the option import chain"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u8 checked_add Option helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::u8::checked_add should type check through --stdlib-root as Option<u8>");
}

#[test]
fn core_u8_checked_sub_option_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_option_result",
        "u8_checked_sub",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::option;
import core::u8;

fn main() {
    let diff: core::option::Option<u8> = core::u8::checked_sub(42, 4);
    let underflow: core::option::Option<u8> = checked_sub(3, 4);
    let diff_is_38: bool = core::option::contains_u8(diff, 38);
    let underflow_is_38: bool = contains_u8(underflow, 38);
    let underflow_is_none: bool = core::option::is_none(underflow);
    if (!diff_is_38 || underflow_is_38 || !underflow_is_none) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core byte and option imports");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u8.lani")),
        "path manifest should include core::u8 from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/option.lani")),
        "path manifest should include core::option from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/result.lani")),
        "path manifest should include core::result through the option import chain"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u8 checked_sub Option helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::u8::checked_sub should type check through --stdlib-root as Option<u8>");
}

#[test]
fn result_contains_err_i32_type_checks() {
    let sources = [
        include_str!("../stdlib/core/result.lani"),
        r#"
module app::main;

import core::result;

fn main() {
    let ok: core::result::Result<bool, i32> = core::result::Ok(true);
    let err: core::result::Result<bool, i32> = core::result::Err(7);
    let ok_contains: bool = core::result::contains_err_i32(ok, 7);
    let err_contains: bool = core::result::contains_err_i32(err, 7);
    let err_miss: bool = core::result::contains_err_i32(err, 9);
    if (ok_contains || !err_contains || err_miss) {
        return 1;
    }
    return 0;
}
"#,
    ];

    common::type_check_source_pack_with_timeout(&sources)
        .expect("core::result::contains_err_i32 should type check for concrete error payloads");
}

#[test]
fn option_xor_type_checks() {
    let sources = [
        include_str!("../stdlib/core/result.lani"),
        include_str!("../stdlib/core/option.lani"),
        r#"
module app::main;

import core::option;

fn main() {
    let left: core::option::Option<i32> = core::option::Some(7);
    let right: core::option::Option<i32> = core::option::None;
    let selected: core::option::Option<i32> = core::option::xor(left, right);
    let selected_value: i32 = core::option::unwrap_or(selected, 0);
    let both_left: core::option::Option<i32> = core::option::Some(1);
    let both_right: core::option::Option<i32> = core::option::Some(2);
    let blocked: core::option::Option<i32> = core::option::xor(both_left, both_right);
    let blocked_value: i32 = core::option::unwrap_or(blocked, 0);
    if (selected_value != 7 || blocked_value != 0) {
        return 1;
    }
    return 0;
}
"#,
    ];

    common::type_check_source_pack_with_timeout(&sources)
        .expect("core::option::xor should type check for concrete option payloads");
}

#[test]
fn result_qualified_constructor_generic_return_type_checks() {
    let sources = [
        include_str!("../stdlib/core/result.lani"),
        r#"
module app::main;

import core::result;

fn wrap<T, E>(value: T) -> core::result::Result<T, E> {
    return core::result::Ok(value);
}

fn main() {
    let wrapped: core::result::Result<i32, bool> = wrap(7);
    let hit: bool = core::result::contains_i32(wrapped, 7);
    if (!hit) {
        return 1;
    }
    return 0;
}
"#,
    ];

    common::type_check_source_pack_with_timeout(&sources)
        .expect("qualified Result constructors should type check in generic returns");
}

#[test]
fn option_ok_or_type_checks() {
    let sources = [
        include_str!("../stdlib/core/result.lani"),
        include_str!("../stdlib/core/option.lani"),
        r#"
module app::main;

import core::option;
import core::result;

fn main() {
    let some: core::option::Option<i32> = core::option::Some(7);
    let none: core::option::Option<i32> = core::option::None;
    let ok: core::result::Result<i32, i32> = core::option::ok_or(some, 9);
    let err: core::result::Result<i32, i32> = core::option::ok_or(none, 9);
    let ok_hit: bool = core::result::contains_i32(ok, 7);
    let err_hit: bool = core::result::contains_err_i32(err, 9);
    if (!ok_hit || !err_hit) {
        return 1;
    }
    return 0;
}
"#,
    ];

    common::type_check_source_pack_with_timeout(&sources)
        .expect("core::option::ok_or should type check with concrete Result payloads");
}

#[test]
fn option_ok_err_result_conversions_type_check() {
    let sources = [
        include_str!("../stdlib/core/result.lani"),
        include_str!("../stdlib/core/option.lani"),
        r#"
module app::main;

import core::option;
import core::result;

fn main() {
    let ok_for_value: core::result::Result<i32, i32> = core::result::Ok(7);
    let err_for_value: core::result::Result<i32, i32> = core::result::Err(9);
    let ok_for_error: core::result::Result<i32, i32> = core::result::Ok(11);
    let err_for_error: core::result::Result<i32, i32> = core::result::Err(13);

    let value: core::option::Option<i32> = core::option::ok(ok_for_value);
    let missing_value: core::option::Option<i32> = core::option::ok(err_for_value);
    let missing_error: core::option::Option<i32> = core::option::err(ok_for_error);
    let error: core::option::Option<i32> = core::option::err(err_for_error);

    if (!core::option::contains_i32(value, 7)) {
        return 1;
    }
    if (!core::option::is_none(missing_value)) {
        return 1;
    }
    if (!core::option::is_none(missing_error)) {
        return 1;
    }
    if (!core::option::contains_i32(error, 13)) {
        return 1;
    }
    return 0;
}
"#,
    ];

    common::type_check_source_pack_with_timeout(&sources)
        .expect("core::option::ok and core::option::err should type check Result conversions");
}
