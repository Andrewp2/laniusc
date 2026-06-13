mod common;

use laniusc::compiler::{
    load_entry_path_manifest_with_stdlib,
    runtime_bound_api_diagnostic_info,
    type_check_entry_with_stdlib,
};

#[test]
fn core_range_overlap_helpers_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_range", "overlaps", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::range;

fn main() {
    let middle: core::range::Range<i32> = core::range::range_i32(2, 6);
    let overlapping: core::range::Range<i32> = range_i32(5, 9);
    let touching: core::range::Range<i32> = core::range::range_i32(6, 8);
    let empty_inside: core::range::Range<i32> = range_i32(4, 4);
    let reversed: core::range::Range<i32> = core::range::range_i32(9, 3);

    let free_overlap: bool = core::range::overlaps_i32(middle, overlapping);
    let free_touching: bool = overlaps_i32(middle, touching);
    let free_empty: bool = core::range::overlaps_i32(middle, empty_inside);
    let free_reversed: bool = overlaps_i32(middle, reversed);
    let method_overlap: bool = middle.overlaps(overlapping);
    let method_touching: bool = middle.overlaps(touching);

    let closed: core::range::RangeInclusive<i32> = range_inclusive_i32(2, 6);
    let closed_touching: core::range::RangeInclusive<i32> =
        core::range::range_inclusive_i32(6, 8);
    let closed_disjoint: core::range::RangeInclusive<i32> =
        range_inclusive_i32(7, 9);
    let closed_empty: core::range::RangeInclusive<i32> =
        core::range::range_inclusive_i32(8, 3);

    let inclusive_touching: bool =
        core::range::overlaps_inclusive_i32(closed, closed_touching);
    let inclusive_disjoint: bool =
        overlaps_inclusive_i32(closed, closed_disjoint);
    let inclusive_empty: bool =
        core::range::overlaps_inclusive_i32(closed, closed_empty);
    let inclusive_method_touching: bool = closed.overlaps(closed_touching);
    let inclusive_method_empty: bool = closed.overlaps(closed_empty);

    if (!free_overlap || free_touching || free_empty || free_reversed) {
        return 1;
    }
    if (!method_overlap || method_touching) {
        return 2;
    }
    if (!inclusive_touching || inclusive_disjoint || inclusive_empty) {
        return 3;
    }
    if (!inclusive_method_touching || inclusive_method_empty) {
        return 4;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::range import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/range.lani")),
        "path manifest should include core::range from the stdlib root"
    );
    for helper_name in [
        "core::range::overlaps_i32",
        "core::range::overlaps_inclusive_i32",
    ] {
        assert!(
            runtime_bound_api_diagnostic_info(helper_name).is_none(),
            "{helper_name} is a source-level helper and must not claim a runtime binding"
        );
    }

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::range overlap helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::range overlap helpers should type check through --stdlib-root");
}
