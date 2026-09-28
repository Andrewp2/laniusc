mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{name}: compile: {error}"))
}

#[test]
fn all_concrete_vector_resizes_execute_on_x86() {
    let bytes = compile_fixture("vec_resize_all");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("vec_resize_all", "vec_resize_all", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn each_concrete_vector_resize_has_a_runtime_case() {
    let fixture = include_str!("fixtures/stdlib_foundation/vec_resize_all.lani");
    for (module, source) in [
        ("vec_i32", include_str!("../stdlib/std/vec_i32.lani")),
        ("vec_u32", include_str!("../stdlib/std/vec_u32.lani")),
        ("vec_u8", include_str!("../stdlib/std/vec_u8.lani")),
        ("vec_i8", include_str!("../stdlib/std/vec_i8.lani")),
        ("vec_u16", include_str!("../stdlib/std/vec_u16.lani")),
        ("vec_i16", include_str!("../stdlib/std/vec_i16.lani")),
        ("vec_bool", include_str!("../stdlib/std/vec_bool.lani")),
    ] {
        assert!(
            source.contains("pub fn try_resize("),
            "{module} lacks try_resize"
        );
        let call = format!("std::{module}::try_resize(");
        assert!(fixture.contains(&call), "{call} lacks a runtime case");
    }
}

#[test]
fn resize_reallocation_failure_preserves_original_vector() {
    let bytes = compile_fixture("vec_resize_realloc_failure");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        let executable = common::TempArtifact::new("laniusc_vec_resize", "failure", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).unwrap();

        let normal = common::short_process_output_with_timeout(
            "vec resize normal allocation",
            &mut std::process::Command::new(executable.path()),
        );
        assert_eq!(normal.status.code(), Some(4), "{normal:?}");

        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_ok()
        {
            let trace = common::TempArtifact::new("laniusc_vec_resize", "trace", None);
            let injected = common::short_process_output_with_timeout(
                "vec resize injected reallocation failure",
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-o")
                    .arg(trace.path())
                    .arg("-e")
                    .arg("trace=mremap")
                    .arg("-e")
                    .arg("inject=mremap:error=ENOMEM:when=1")
                    .arg(executable.path()),
            );
            assert_eq!(injected.status.code(), Some(0), "{injected:?}");
            let trace_text = std::fs::read_to_string(trace.path()).unwrap();
            assert!(trace_text.contains("INJECTED"), "{trace_text}");
            assert!(trace_text.contains("ENOMEM"), "{trace_text}");
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}
