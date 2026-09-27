mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn std_env_var_read_exact_into_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_env_checked.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_env_checked", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile bounded environment reader");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        let executable = common::TempArtifact::new("laniusc_std_env", "std_env_checked", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path())
            .expect("stat environment fixture")
            .permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions)
            .expect("chmod environment fixture");

        let output = common::short_process_output_with_timeout(
            "std_env_checked",
            std::process::Command::new(executable.path())
                .env("L", "bravo")
                .env("E", "")
                .env_remove("M"),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"bravo");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}
