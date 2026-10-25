#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};

fn samples(group: &str, names: &[&str]) {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let mut executables = Vec::new();
    for name in names {
        let entry = root.join(format!("sample_programs/{name}.lani"));
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(*name, move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .unwrap_or_else(|error| panic!("{name}: {error}"));
        let executable = common::TempArtifact::new("laniusc_checked_sample", name, None);
        executable.write_bytes(bytes);
        std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700))
            .unwrap();
        executables.push(executable);
    }
    let mut command = Command::new("python3");
    command
        .args([
            "-c",
            include_str!("fixtures/stdlib_foundation/checked_sample_migration_oracle.py"),
            group,
        ])
        .current_dir(root);
    for (name, executable) in names.iter().zip(&executables) {
        command.arg(name).arg(executable.path());
    }
    let result = common::process_output_with_timeout(
        format!("checked sample {group} model and resource faults"),
        &mut command,
        Duration::from_secs(45),
    );
    assert_eq!(result.status.code(), Some(0), "{group}: {result:?}");
    assert!(result.stderr.is_empty(), "{group}: {result:?}");
    println!("{}", String::from_utf8_lossy(&result.stdout));
}

#[test]
fn fixed_vector_samples_check_errors_and_complete_output() {
    samples(
        "fixed",
        &[
            "vector_halfword_checksum",
            "vector_unsigned_checksum",
            "vector_signed_byte_sum",
            "vector_signed_halfword_sum",
            "vector_true_count",
            "vector_square_sum",
            "vector_edit_checksum",
        ],
    );
}

#[test]
fn formerly_statusless_output_samples_report_host_failures() {
    samples(
        "output",
        &[
            "result_reading_total",
            "random_fill",
            "stdio_flush",
            "stdio_print_i32",
            "host_runtime_files",
        ],
    );
}

#[test]
fn unicode_vector_samples_preserve_scalars_limits_and_ownership() {
    samples("unicode", &["unicode_sort_unique", "unicode_text_report"]);
}

#[test]
fn represented_wide_vector_samples_match_integer_models_and_release_owners() {
    samples("wide", &["wide_signed_sum", "wide_unsigned_sum"]);
}

#[test]
fn top_scores_uses_checked_final_builder_and_preserves_priority_results() {
    samples("heap", &["top_scores"]);
}
