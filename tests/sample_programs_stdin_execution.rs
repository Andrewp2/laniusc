// Stdin-driven top-level samples that no other test runs. Each sample is
// listed in sample_programs/DEDICATED.tsv with this file as its test.
mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_sample(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("sample_programs/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"))
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn run_with_stdin(name: &str, bytes: &[u8], cases: &[(&str, &[u8], i32, &[u8])]) {
    use std::os::unix::fs::PermissionsExt;

    let executable = common::TempArtifact::new("laniusc_sample_stdin", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path()).expect("stat sample").permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).expect("chmod sample");
    for (label, input, status, stdout) in cases {
        let file = common::TempArtifact::new("laniusc_sample_stdin_input", label, None);
        file.write_bytes(input);
        let output = common::short_process_output_with_timeout(
            format!("{name} {label}"),
            std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                std::fs::File::open(file.path()).expect("open sample input"),
            )),
        );
        assert_eq!(output.status.code(), Some(*status), "{name} {label}: {output:?}");
        assert_eq!(output.stdout, *stdout, "{name} {label}: {output:?}");
    }
}

#[test]
fn wide_signed_median_five_prints_the_full_width_median() {
    let bytes = compile_sample("wide_signed_median_five");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    run_with_stdin("wide_signed_median_five", &bytes, &[
        ("extremes", b"12\n-7\n9223372036854775807\n-9223372036854775808\n40\n", 0, b"12\n"),
        ("negative median", b"-5\n-1\n-9\n3\n-2\n", 0, b"-2\n"),
        ("four lines", b"1\n2\n3\n4\n", 2, b""),
        ("six lines", b"1\n2\n3\n4\n5\n6\n", 2, b""),
        ("not a number", b"1\n2\nx\n4\n5\n", 3, b""),
    ]);
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn wide_unsigned_median_five_prints_the_full_width_median() {
    let bytes = compile_sample("wide_unsigned_median_five");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    run_with_stdin("wide_unsigned_median_five", &bytes, &[
        ("extremes", b"18446744073709551615\n0\n4294967296\n7\n4294967295\n", 0, b"4294967295\n"),
        ("four lines", b"1\n2\n3\n4\n", 2, b""),
        ("negative", b"1\n2\n-3\n4\n5\n", 3, b""),
    ]);
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}
