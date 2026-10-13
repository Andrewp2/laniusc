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
import core::option_i32;

fn main() {
    let sum: core::option_i32::OptionI32 = core::i32::checked_add(40, 2);
    let high_overflow: core::option_i32::OptionI32 =
        checked_add(core::i32::MAX, 1);
    let low_overflow: core::option_i32::OptionI32 =
        core::i32::checked_add(core::i32::MIN, -1);
    let sum_is_42: bool = core::option_i32::contains(sum, 42);
    let high_is_none: bool = core::option_i32::is_none(high_overflow);
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
            .any(|file| file.library_id == 0
                && file.path == stdlib_root.join("core/option_i32.lani")),
        "path manifest should include core::option_i32 from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0
                && file.path == stdlib_root.join("core/result_i32.lani")),
        "path manifest should include core::result through the option_i32 import chain"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::i32 checked_add Option helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::i32::checked_add should type check through --stdlib-root as OptionI32");
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
import core::option_i32;

fn main() {
    let diff: core::option_i32::OptionI32 = core::i32::checked_sub(42, 4);
    let high_overflow: core::option_i32::OptionI32 =
        checked_sub(core::i32::MAX, -1);
    let low_overflow: core::option_i32::OptionI32 =
        core::i32::checked_sub(core::i32::MIN, 1);
    let diff_is_38: bool = core::option_i32::contains(diff, 38);
    let high_is_none: bool = core::option_i32::is_none(high_overflow);
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
            .any(|file| file.library_id == 0
                && file.path == stdlib_root.join("core/option_i32.lani")),
        "path manifest should include core::option_i32 from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0
                && file.path == stdlib_root.join("core/result_i32.lani")),
        "path manifest should include core::result through the option_i32 import chain"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::i32 checked_sub Option helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::i32::checked_sub should type check through --stdlib-root as OptionI32");
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

import core::option_u32;
import core::u32;

fn main() {
    let sum: core::option_u32::OptionU32 = core::u32::checked_add(40, 2);
    let overflow: core::option_u32::OptionU32 = checked_add(core::u32::MAX, 1);
    let sum_is_42: bool = core::option_u32::contains(sum, 42);
    let overflow_is_42: bool = contains(overflow, 42);
    let overflow_is_none: bool = core::option_u32::is_none(overflow);
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
            .any(|file| file.library_id == 0
                && file.path == stdlib_root.join("core/option_u32.lani")),
        "path manifest should include core::option_u32 from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0
                && file.path == stdlib_root.join("core/result_u32.lani")),
        "path manifest should include core::result through the option_u32 import chain"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u32 checked_add Option helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::u32::checked_add should type check through --stdlib-root as OptionU32");
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

import core::option_u32;
import core::u32;

fn main() {
    let diff: core::option_u32::OptionU32 = core::u32::checked_sub(42, 4);
    let underflow: core::option_u32::OptionU32 = checked_sub(3, 4);
    let diff_is_38: bool = core::option_u32::contains(diff, 38);
    let underflow_is_38: bool = contains(underflow, 38);
    let underflow_is_none: bool = core::option_u32::is_none(underflow);
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
            .any(|file| file.library_id == 0
                && file.path == stdlib_root.join("core/option_u32.lani")),
        "path manifest should include core::option_u32 from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0
                && file.path == stdlib_root.join("core/result_u32.lani")),
        "path manifest should include core::result through the option_u32 import chain"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u32 checked_sub Option helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::u32::checked_sub should type check through --stdlib-root as OptionU32");
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

import core::option_u32;
import core::u32;

fn main() {
    let zero: core::option_u32::OptionU32 = core::u32::checked_next_power_of_two(0);
    let one: core::option_u32::OptionU32 = checked_next_power_of_two(1);
    let already_power: core::option_u32::OptionU32 =
        core::u32::checked_next_power_of_two(1024);
    let rounded: core::option_u32::OptionU32 = checked_next_power_of_two(1025);
    let highest: core::option_u32::OptionU32 =
        core::u32::checked_next_power_of_two(2147483648);
    let overflow: core::option_u32::OptionU32 =
        checked_next_power_of_two(core::u32::MAX);

    let zero_is_one: bool = core::option_u32::contains(zero, 1);
    let one_is_one: bool = contains(one, 1);
    let already_is_same: bool = core::option_u32::contains(already_power, 1024);
    let rounded_is_next: bool = contains(rounded, 2048);
    let highest_is_some: bool = core::option_u32::contains(highest, 2147483648);
    let overflow_is_none: bool = core::option_u32::is_none(overflow);

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
            .any(|file| file.library_id == 0
                && file.path == stdlib_root.join("core/option_u32.lani")),
        "path manifest should include core::option_u32 from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0
                && file.path == stdlib_root.join("core/result_u32.lani")),
        "path manifest should include core::result through the option_u32 import chain"
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
        "core::u32::checked_next_power_of_two should type check through --stdlib-root as OptionU32",
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

import core::option_u8;
import core::u8;

fn main() {
    let sum: core::option_u8::OptionU8 = core::u8::checked_add(40, 2);
    let overflow: core::option_u8::OptionU8 = checked_add(core::u8::MAX, 1);
    let sum_is_42: bool = core::option_u8::contains(sum, 42);
    let overflow_is_42: bool = contains(overflow, 42);
    let overflow_is_none: bool = core::option_u8::is_none(overflow);
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
        manifest.files.iter().any(
            |file| file.library_id == 0 && file.path == stdlib_root.join("core/option_u8.lani")
        ),
        "path manifest should include core::option_u8 from the stdlib root"
    );
    assert!(
        manifest.files.iter().any(
            |file| file.library_id == 0 && file.path == stdlib_root.join("core/result_u8.lani")
        ),
        "path manifest should include core::result through the option_u8 import chain"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u8 checked_add Option helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::u8::checked_add should type check through --stdlib-root as OptionU8");
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

import core::option_u8;
import core::u8;

fn main() {
    let diff: core::option_u8::OptionU8 = core::u8::checked_sub(42, 4);
    let underflow: core::option_u8::OptionU8 = checked_sub(3, 4);
    let diff_is_38: bool = core::option_u8::contains(diff, 38);
    let underflow_is_38: bool = contains(underflow, 38);
    let underflow_is_none: bool = core::option_u8::is_none(underflow);
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
        manifest.files.iter().any(
            |file| file.library_id == 0 && file.path == stdlib_root.join("core/option_u8.lani")
        ),
        "path manifest should include core::option_u8 from the stdlib root"
    );
    assert!(
        manifest.files.iter().any(
            |file| file.library_id == 0 && file.path == stdlib_root.join("core/result_u8.lani")
        ),
        "path manifest should include core::result through the option_u8 import chain"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u8 checked_sub Option helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::u8::checked_sub should type check through --stdlib-root as OptionU8");
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
