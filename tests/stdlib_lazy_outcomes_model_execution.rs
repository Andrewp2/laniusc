//! Complete lazy Option/Result compositions and exact selected callback effects.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_lazy_outcomes_model")
        .join(name)
}

#[test]
fn lazy_outcomes_match_composed_states_and_selected_callback_effects() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = fixture("model.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout("lazy outcomes composition model", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("lazy outcomes composition model: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_lazy_outcomes_model", "model", None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "independent lazy outcome composition reference",
        Command::new("python3")
            .arg("-B")
            .arg(fixture("oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(90),
    );
    common::assert_command_success("lazy outcomes composition model", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert_eq!(
        summary,
        "lazy-outcomes-model cases=16 actions=1536 api_calls=1044 free=536 method=508 selected=616 skipped=428 callbacks=616 producer_calls=148 callback_absence=60 callback_errors=52 apis=19 branch_routes=76 shapes=2 seed=0x1a2f0261119\n"
    );
    eprint!("{summary}");
}
