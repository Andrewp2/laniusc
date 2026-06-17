mod common;

use laniusc_compiler::compiler::{
    load_entry_path_manifest_with_stdlib,
    runtime_bound_api_diagnostic_info,
    type_check_entry_with_stdlib,
};

#[test]
fn core_f32_scalar_helpers_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_f32", "zero_predicates", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::f32;

fn main() {
    let zero_value: f32 = core::f32::ZERO;
    let positive_value: f32 = core::f32::ONE;
    let negative_value: f32 = -2.5;
    let zero_is_zero: bool = core::f32::is_zero(zero_value);
    let positive_is_nonzero: bool = is_nonzero(positive_value);
    let negative_is_nonzero: bool = core::f32::is_nonzero(negative_value);
    let positive_is_zero: bool = is_zero(positive_value);
    let negative_sign: f32 = core::f32::signum(negative_value);
    let zero_sign: f32 = signum(zero_value);
    let positive_sign: f32 = core::f32::signum(positive_value);
    let positive_root: f32 = core::f32::sqrt(positive_value);
    let zero_root: f32 = sqrt(zero_value);
    let between: bool = core::f32::between_exclusive(positive_value, zero_value, 2.0);
    let lower_edge: bool = between_exclusive(zero_value, zero_value, 2.0);
    let upper_edge: bool = core::f32::between_exclusive(2.0, zero_value, 2.0);
    let inclusive_lower_edge: bool = core::f32::between_inclusive(zero_value, zero_value, 2.0);
    let inclusive_upper_edge: bool = between_inclusive(2.0, zero_value, 2.0);
    let inclusive_outside: bool = core::f32::between_inclusive(2.5, zero_value, 2.0);
    if (!zero_is_zero || !positive_is_nonzero || !negative_is_nonzero || positive_is_zero) {
        return 1;
    }
    if (negative_sign != -1.0 || zero_sign != core::f32::ZERO || positive_sign != core::f32::ONE) {
        return 1;
    }
    if (positive_root <= zero_value || zero_root != core::f32::ZERO) {
        return 1;
    }
    if (!between || lower_edge || upper_edge) {
        return 1;
    }
    if (!inclusive_lower_edge || !inclusive_upper_edge || inclusive_outside) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::f32");
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/f32.lani")),
        "path manifest should include core::f32 from the stdlib root"
    );
    for helper_name in [
        "core::f32::is_zero",
        "core::f32::is_nonzero",
        "core::f32::sqrt",
        "core::f32::signum",
        "core::f32::between_exclusive",
        "core::f32::between_inclusive",
    ] {
        assert!(
            runtime_bound_api_diagnostic_info(helper_name).is_none(),
            "{helper_name} is a source-level helper and must not claim a runtime binding"
        );
    }

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::f32 scalar helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::f32 scalar helpers should type check through --stdlib-root");
}
