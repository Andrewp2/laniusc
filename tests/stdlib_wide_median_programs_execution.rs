mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn write_executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let executable = common::TempArtifact::new("laniusc_vec_wide", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).unwrap();
    executable
}

#[test]
fn wide_owned_median_programs_handle_full_width_input_and_failures() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, cases) in [
        (
            "sorted_wide_unsigned_median",
            [
                (
                    b"18446744073709551615\n0\n4294967296\n4294967296\n9223372036854775808\n"
                        .as_slice(),
                    0,
                    b"4294967296 2\n".as_slice(),
                ),
                (
                    b"0\n18446744073709551615\n".as_slice(),
                    0,
                    b"18446744073709551615 1\n".as_slice(),
                ),
                (b"7\n".as_slice(), 0, b"7 1\n".as_slice()),
                (b"".as_slice(), 2, b"".as_slice()),
                (b"\n".as_slice(), 2, b"".as_slice()),
                (b"1x\n".as_slice(), 3, b"".as_slice()),
                (b"18446744073709551616\n".as_slice(), 3, b"".as_slice()),
            ],
        ),
        (
            "sorted_wide_signed_median",
            [
                (
                    b"-9223372036854775808\n0\n-1\n-1\n9223372036854775807\n".as_slice(),
                    0,
                    b"-1 2\n".as_slice(),
                ),
                (
                    b"-9223372036854775808\n9223372036854775807\n".as_slice(),
                    0,
                    b"9223372036854775807 1\n".as_slice(),
                ),
                (b"-7\n".as_slice(), 0, b"-7 1\n".as_slice()),
                (b"".as_slice(), 2, b"".as_slice()),
                (b"\n".as_slice(), 2, b"".as_slice()),
                (b"1x\n".as_slice(), 3, b"".as_slice()),
                (b"9223372036854775808\n".as_slice(), 3, b"".as_slice()),
            ],
        ),
    ] {
        let entry = root.join(format!("sample_programs/{name}.lani"));
        let stdlib_root = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|error| panic!("{name}: compile: {error}"));

        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            let executable = write_executable(&bytes, name);
            for (input_bytes, expected_code, expected_stdout) in cases {
                let input = common::TempArtifact::new("laniusc_vec_wide", "median_input", None);
                input.write_bytes(input_bytes);
                let output = common::short_process_output_with_timeout(
                    name,
                    std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                        std::fs::File::open(input.path()).unwrap(),
                    )),
                );
                assert_eq!(
                    output.status.code(),
                    Some(expected_code),
                    "{name} {input_bytes:?}: {output:?}"
                );
                assert_eq!(
                    output.stdout, expected_stdout,
                    "{name} {input_bytes:?}: {output:?}"
                );
                assert!(
                    output.stderr.is_empty(),
                    "{name} {input_bytes:?}: {output:?}"
                );
            }
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = (bytes, cases);
    }
}
