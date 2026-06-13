mod common;

use laniusc::compiler::{load_entry_path_manifest_with_stdlib, type_check_entry_with_stdlib};

#[test]
fn core_i64_between_exclusive_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_i64", "between_exclusive", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::i64;

fn main() {
    let low: i64 = 1;
    let high: i64 = 9;
    let inside_value: i64 = 5;
    let below_value: i64 = -3;
    let inside: bool = core::i64::between_exclusive(inside_value, low, high);
    let lower_edge: bool = between_exclusive(low, low, high);
    let upper_edge: bool = core::i64::between_exclusive(high, low, high);
    let below: bool = between_exclusive(below_value, low, high);
    if (!inside || lower_edge || upper_edge || below) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::i64 import");
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
        "GPU type check stdlib-root core::i64 between_exclusive helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::i64::between_exclusive should type check through --stdlib-root");
}
