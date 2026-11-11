//! Inline Ring/InlineString/Vec additions and the LRU cache against a Python reference.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_fixed_capacity_lru/model")
        .join(name)
}

#[test]
fn fixed_capacity_containers_and_lru_match_python_reference_and_exact_eviction_order() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = fixture("model.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout("fixed-capacity lru model", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("fixed-capacity lru model: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_fixed_capacity_lru_model", "model", None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "independent fixed-capacity and lru reference",
        Command::new("python3")
            .arg("-B")
            .arg(fixture("oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(90),
    );
    common::assert_command_success("fixed-capacity lru model", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert_eq!(
        summary,
        "fixed-capacity-lru-model cases=96 commands=11346 ring_ops=2133 ring_full=306 ring_overwrites=87 ring_snapshots=313 ring_wrapped_views=77 ring_pulls=556 string_ops=1718 string_full=356 string_invalid_scalars=40 string_not_boundary=20 string_truncated_pushes=166 string_snapshots=253 vec_ops=1390 vec_extend_full=98 vec_self_extends=26 lru_resets=24 lru_probes=168 lru_ops=5913 lru_hits=741 lru_misses=3106 lru_replacements=282 lru_evictions=378 lru_snapshots=963 lru_snapshot_entries=3637 lru_pulls=1890 collide_eq_calls=1568 words=78931 controls=4 seed=0x51c020261031\n"
    );
    eprint!("{summary}");
}
