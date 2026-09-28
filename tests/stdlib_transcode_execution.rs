mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn portable_transcoding_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, source, expected_exit) in [
        (
            "core_transcode_complete",
            "tests/fixtures/stdlib_foundation/core_transcode_complete.lani",
            0,
        ),
        (
            "core_transcode_bounds",
            "tests/fixtures/stdlib_foundation/core_transcode_bounds.lani",
            101,
        ),
        (
            "core_transcode_dest_bounds",
            "tests/fixtures/stdlib_foundation/core_transcode_dest_bounds.lani",
            101,
        ),
    ] {
        let entry = root.join(source);
        let stdlib_root = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|error| panic!("{name}: {error}"));

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(expected_exit),
                "{name}: {output:?}"
            );
            assert!(output.stdout.is_empty(), "{name}: {output:?}");
            assert!(output.stderr.is_empty(), "{name}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = (bytes, expected_exit);
    }
}

#[test]
fn every_transcode_function_has_an_executable_case() {
    let source = include_str!("../stdlib/core/transcode.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/core_transcode_complete.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("transcode function has a name");
        let call = format!("core::transcode::{name}(");
        assert!(fixture.contains(&call), "{call} lacks an executable case");
        covered += 1;
    }
    assert_eq!(covered, 6);
}

#[test]
fn utf8_to_utf16_summary_uses_real_input() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/utf8_to_utf16_summary.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("UTF-8 to UTF-16 summary", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile UTF-8 to UTF-16 summary");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;
        let executable = common::TempArtifact::new("laniusc_transcode", "summary", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).unwrap();

        let maximum = vec![b'A'; 64];
        let oversized = vec![b'A'; 65];
        for (input_bytes, expected_exit, expected_output) in [
            (b"".as_slice(), 0, b"0\n0\n".as_slice()),
            (b"ABC".as_slice(), 0, b"3\n3\n".as_slice()),
            (
                b"A\xc2\xa2\xe2\x82\xac\xf0\x9f\x98\x80".as_slice(),
                0,
                b"5\n4\n".as_slice(),
            ),
            (maximum.as_slice(), 0, b"64\n64\n".as_slice()),
            (oversized.as_slice(), 3, b"".as_slice()),
            (b"\xc0\x80".as_slice(), 3, b"".as_slice()),
            (b"\xe2\x82".as_slice(), 3, b"".as_slice()),
            (b"A\xed\xa0\x80".as_slice(), 3, b"".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_transcode", "input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "UTF-8 to UTF-16 summary",
                std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).unwrap(),
                )),
            );
            assert_eq!(
                output.status.code(),
                Some(expected_exit),
                "{input_bytes:?}: {output:?}"
            );
            assert_eq!(
                output.stdout, expected_output,
                "{input_bytes:?}: {output:?}"
            );
            assert!(output.stderr.is_empty(), "{output:?}");
        }

        let full = std::fs::OpenOptions::new()
            .write(true)
            .open("/dev/full")
            .unwrap();
        let status = std::process::Command::new("timeout")
            .arg("5s")
            .arg(executable.path())
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::from(full))
            .status()
            .expect("run with /dev/full stdout");
        assert_eq!(status.code(), Some(4), "{status:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}
