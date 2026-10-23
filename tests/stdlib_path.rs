mod common;

use laniusc_compiler::compiler::{
    load_entry_path_manifest_with_stdlib,
    runtime_bound_api_diagnostic_info,
    type_check_entry_with_stdlib,
};

#[test]
fn path_rules_ascii_letter_helper_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_path", "ascii_letter", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::path_rules;

fn main() {
    let upper: PathByte = 65;
    let lower: core::path_rules::PathByte = 122;
    let before_upper: PathByte = 64;
    let after_upper: PathByte = 91;
    let before_lower: core::path_rules::PathByte = 96;
    let after_lower: PathByte = 123;
    let digit: core::path_rules::PathByte = 55;
    let upper_is_letter: PathCapability =
        path_byte_is_ascii_letter(upper);
    let lower_is_letter: core::path_rules::PathCapability =
        core::path_rules::path_byte_is_ascii_letter(lower);
    let before_upper_is_letter: PathCapability =
        path_byte_is_ascii_letter(before_upper);
    let after_upper_is_letter: core::path_rules::PathCapability =
        core::path_rules::path_byte_is_ascii_letter(after_upper);
    let before_lower_is_letter: PathCapability =
        path_byte_is_ascii_letter(before_lower);
    let after_lower_is_letter: core::path_rules::PathCapability =
        core::path_rules::path_byte_is_ascii_letter(after_lower);
    let digit_is_letter: PathCapability =
        path_byte_is_ascii_letter(digit);
    let drive_accepts_upper: core::path_rules::PathCapability =
        core::path_rules::path_byte_is_windows_drive_letter(upper);
    let drive_accepts_lower: PathCapability =
        path_byte_is_windows_drive_letter(lower);
    let drive_rejects_digit: core::path_rules::PathCapability =
        core::path_rules::path_byte_is_windows_drive_letter(digit);
    if (!upper_is_letter || !lower_is_letter || before_upper_is_letter || after_upper_is_letter) {
        return 1;
    }
    if (before_lower_is_letter || after_lower_is_letter || digit_is_letter) {
        return 1;
    }
    if (!drive_accepts_upper || !drive_accepts_lower || drive_rejects_digit) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::path_rules import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0
                && file.path == stdlib_root.join("core/path_rules.lani")),
        "path manifest should include core::path_rules from the stdlib root"
    );
    assert_eq!(
        manifest.standard_library_id,
        Some(0),
        "the stdlib-root loader names the library of stdlib-root files as the standard library"
    );
    assert!(
        runtime_bound_api_diagnostic_info("core::path_rules::path_byte_is_ascii_letter").is_none(),
        "core::path_rules::path_byte_is_ascii_letter is a source-level helper and must not claim a runtime binding"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::path_rules ASCII letter helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::path_rules ASCII letter helper should type check through --stdlib-root");
}

#[test]
fn path_rules_normal_relative_component_header_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_path", "normal_relative", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::path_rules;

fn main() {
    let dot: PathByte = core::path_rules::PATH_EXTENSION_SEPARATOR;
    let slash: core::path_rules::PathByte = core::path_rules::PATH_SEPARATOR_UNIX;
    let colon: PathByte = PATH_DRIVE_SEPARATOR;
    let nul: core::path_rules::PathByte = core::path_rules::PATH_NUL;
    let letter: PathByte = 97;
    let drive_letter: core::path_rules::PathByte = 67;
    let one: PathComponentLength = 1;
    let two: core::path_rules::PathComponentLength = 2;
    let three: PathComponentLength = 3;
    let empty: core::path_rules::PathComponentLength = 0;

    let name_component: core::path_rules::PathCapability =
        core::path_rules::path_component_header_is_normal_relative(letter, dot, three);
    let hidden_component: PathCapability =
        path_component_header_is_normal_relative(dot, letter, three);
    let empty_component: core::path_rules::PathCapability =
        path_component_header_is_normal_relative(letter, dot, empty);
    let root_separator: PathCapability =
        core::path_rules::path_component_header_is_normal_relative(slash, dot, one);
    let current_dir: core::path_rules::PathCapability =
        path_component_header_is_normal_relative(dot, letter, one);
    let parent_dir: PathCapability =
        core::path_rules::path_component_header_is_normal_relative(dot, dot, two);
    let windows_drive_prefix: core::path_rules::PathCapability =
        path_component_header_is_normal_relative(drive_letter, colon, two);
    let second_byte_boundary: PathCapability =
        core::path_rules::path_component_header_is_normal_relative(letter, slash, two);
    let nul_start: core::path_rules::PathCapability =
        path_component_header_is_normal_relative(nul, letter, two);

    if (!name_component || !hidden_component) {
        return 2;
    }
    if (empty_component || root_separator || current_dir || parent_dir) {
        return 3;
    }
    if (windows_drive_prefix || second_byte_boundary || nul_start) {
        return 4;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::path_rules import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0
                && file.path == stdlib_root.join("core/path_rules.lani")),
        "path manifest should include core::path_rules from the stdlib root"
    );
    assert!(
        runtime_bound_api_diagnostic_info("core::path_rules::path_component_header_is_normal_relative").is_none(),
        "core::path_rules::path_component_header_is_normal_relative is a source-level helper and must not claim a runtime binding"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::path_rules normal relative component helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect(
        "core::path_rules normal relative component helper should type check through --stdlib-root",
    );
}

#[test]
fn path_rules_lexically_rooted_header_contract_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_path", "rooted_header", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::path_rules;

fn main() {
    let slash: PathByte = core::path_rules::PATH_SEPARATOR_UNIX;
    let backslash: core::path_rules::PathByte = PATH_SEPARATOR_WINDOWS;
    let drive_letter: PathByte = 67;
    let colon: core::path_rules::PathByte = core::path_rules::PATH_DRIVE_SEPARATOR;
    let name_byte: PathByte = 110;
    let empty: core::path_rules::PathComponentLength = 0;
    let one: PathComponentLength = 1;
    let two: core::path_rules::PathComponentLength = 2;
    let three: PathComponentLength = 3;
    let five: core::path_rules::PathComponentLength = 5;

    let unix_root: PathCapability =
        core::path_rules::path_header_is_lexically_rooted(slash, name_byte, name_byte, one);
    let windows_root_relative: core::path_rules::PathCapability =
        path_header_is_lexically_rooted(backslash, name_byte, name_byte, one);
    let drive_root_with_slash: PathCapability =
        core::path_rules::path_header_is_lexically_rooted(drive_letter, colon, slash, three);
    let drive_root_with_backslash: core::path_rules::PathCapability =
        path_header_is_lexically_rooted(drive_letter, colon, backslash, three);

    let empty_header: PathCapability =
        core::path_rules::path_header_is_lexically_rooted(name_byte, colon, slash, empty);
    let bare_drive_prefix: core::path_rules::PathCapability =
        path_header_is_lexically_rooted(drive_letter, colon, slash, two);
    let drive_relative: PathCapability =
        core::path_rules::path_header_is_lexically_rooted(drive_letter, colon, name_byte, three);
    let relative_name: core::path_rules::PathCapability =
        path_header_is_lexically_rooted(name_byte, name_byte, name_byte, five);

    if (!unix_root || !windows_root_relative || !drive_root_with_slash || !drive_root_with_backslash) {
        return 10;
    }
    if (empty_header || bare_drive_prefix || drive_relative || relative_name) {
        return 11;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::path_rules import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0
                && file.path == stdlib_root.join("core/path_rules.lani")),
        "path manifest should include core::path_rules from the stdlib root"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::path_rules lexically rooted header contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect(
        "core::path_rules lexically rooted header contract should type check through --stdlib-root",
    );
}

#[test]
fn path_rules_absolute_header_contract_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_path", "absolute_header", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::path_rules;

fn main() {
    let slash: PathByte = core::path_rules::PATH_SEPARATOR_UNIX;
    let backslash: core::path_rules::PathByte = PATH_SEPARATOR_WINDOWS;
    let drive_letter: PathByte = 67;
    let colon: core::path_rules::PathByte = core::path_rules::PATH_DRIVE_SEPARATOR;
    let name_byte: PathByte = 110;
    let empty: core::path_rules::PathComponentLength = 0;
    let one: PathComponentLength = 1;
    let two: core::path_rules::PathComponentLength = 2;
    let three: PathComponentLength = 3;
    let five: core::path_rules::PathComponentLength = 5;

    let unix_absolute: PathCapability =
        core::path_rules::path_header_is_absolute(slash, name_byte, name_byte, one);
    let windows_absolute_with_slash: core::path_rules::PathCapability =
        path_header_is_absolute(drive_letter, colon, slash, three);
    let windows_absolute_with_backslash: PathCapability =
        core::path_rules::path_header_is_absolute(drive_letter, colon, backslash, three);

    let empty_header: core::path_rules::PathCapability =
        path_header_is_absolute(name_byte, colon, slash, empty);
    let bare_drive_prefix: PathCapability =
        core::path_rules::path_header_is_absolute(drive_letter, colon, slash, two);
    let windows_drive_relative: core::path_rules::PathCapability =
        path_header_is_absolute(drive_letter, colon, name_byte, three);
    let windows_root_relative: PathCapability =
        core::path_rules::path_header_is_absolute(backslash, name_byte, name_byte, five);
    let relative_name: core::path_rules::PathCapability =
        path_header_is_absolute(name_byte, name_byte, name_byte, five);

    if (!unix_absolute || !windows_absolute_with_slash || !windows_absolute_with_backslash) {
        return 12;
    }
    if (empty_header || bare_drive_prefix || windows_drive_relative || windows_root_relative || relative_name) {
        return 13;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::path_rules import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0
                && file.path == stdlib_root.join("core/path_rules.lani")),
        "path manifest should include core::path_rules from the stdlib root"
    );
    assert!(
        runtime_bound_api_diagnostic_info("core::path_rules::path_header_is_absolute").is_none(),
        "core::path_rules::path_header_is_absolute is a source-level helper and must not claim a runtime binding"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::path_rules absolute header contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::path_rules absolute header contract should type check through --stdlib-root");
}

#[test]
fn path_rules_windows_component_header_contract_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_path", "windows_component", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::path_rules;

fn main() {
    let name_first: PathByte = 110;
    let name_second: core::path_rules::PathByte = 97;
    let dot: PathByte = core::path_rules::PATH_EXTENSION_SEPARATOR;
    let colon: core::path_rules::PathByte = PATH_DRIVE_SEPARATOR;
    let slash: PathByte = PATH_SEPARATOR_UNIX;
    let backslash: core::path_rules::PathByte = PATH_SEPARATOR_WINDOWS;
    let quote: PathByte = core::path_rules::PATH_WINDOWS_RESERVED_DOUBLE_QUOTE;
    let pipe: core::path_rules::PathByte = core::path_rules::PATH_WINDOWS_RESERVED_PIPE;
    let control: PathByte = 31;
    let delete_byte: core::path_rules::PathByte = core::path_rules::PATH_ASCII_DELETE;
    let empty: PathComponentLength = 0;
    let one: core::path_rules::PathComponentLength = 1;
    let two: PathComponentLength = 2;
    let three: core::path_rules::PathComponentLength = 3;

    let normal_name: core::path_rules::PathCapability =
        core::path_rules::path_component_header_is_normal_windows_relative(name_first, name_second, three);
    let hidden_name: PathCapability =
        path_component_header_is_normal_windows_relative(dot, name_first, three);
    let dot_byte_can_start: core::path_rules::PathCapability =
        core::path_rules::path_byte_can_start_windows_component(dot);
    let name_byte_can_continue: PathCapability =
        path_byte_can_continue_windows_component(name_second);

    let empty_component: core::path_rules::PathCapability =
        path_component_header_is_normal_windows_relative(name_first, name_second, empty);
    let current_dir: PathCapability =
        core::path_rules::path_component_header_is_normal_windows_relative(dot, name_second, one);
    let parent_dir: core::path_rules::PathCapability =
        path_component_header_is_normal_windows_relative(dot, dot, two);
    let drive_prefix: PathCapability =
        core::path_rules::path_component_header_is_normal_windows_relative(name_second, colon, two);
    let slash_start: core::path_rules::PathCapability =
        path_component_header_is_normal_windows_relative(slash, name_second, two);
    let backslash_start: PathCapability =
        core::path_rules::path_component_header_is_normal_windows_relative(backslash, name_second, two);
    let reserved_second: core::path_rules::PathCapability =
        path_component_header_is_normal_windows_relative(name_first, quote, two);

    let quote_reserved: PathCapability =
        core::path_rules::path_byte_is_windows_component_reserved(quote);
    let pipe_reserved: core::path_rules::PathCapability =
        path_byte_is_windows_component_reserved(pipe);
    let control_reserved: PathCapability =
        core::path_rules::path_byte_is_windows_component_reserved(control);
    let delete_reserved: core::path_rules::PathCapability =
        path_byte_is_windows_component_reserved(delete_byte);
    let colon_reserved: PathCapability =
        core::path_rules::path_byte_is_windows_component_reserved(colon);
    let slash_reserved: core::path_rules::PathCapability =
        path_byte_is_windows_component_reserved(slash);
    let backslash_reserved: PathCapability =
        core::path_rules::path_byte_is_windows_component_reserved(backslash);

    if (!normal_name || !hidden_name || !dot_byte_can_start || !name_byte_can_continue) {
        return 5;
    }
    if (!quote_reserved || !pipe_reserved || !control_reserved || !delete_reserved) {
        return 6;
    }
    if (!colon_reserved || !slash_reserved || !backslash_reserved) {
        return 7;
    }
    if (empty_component || current_dir || parent_dir || drive_prefix) {
        return 8;
    }
    if (slash_start || backslash_start || reserved_second) {
        return 9;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::path_rules import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0
                && file.path == stdlib_root.join("core/path_rules.lani")),
        "path manifest should include core::path_rules from the stdlib root"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::path_rules Windows component header contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::path_rules Windows component header contract should type check through --stdlib-root");
}
