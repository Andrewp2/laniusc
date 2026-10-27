// Separate entry/helper keeps publication controls out of preparation compile.
use std::{os::unix::fs::PermissionsExt, path::Path, process::Command, time::Duration};

pub fn run(root: &Path) {
    let path = "tests/fixtures/extended/server_poll/publication.lani";
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = crate::common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    assert!(crate::common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = crate::common::TempArtifact::new("server_poll_publication", "native", None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = crate::common::process_output_with_timeout(
        "persistent Server publication/refill/reservations",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/server_poll/publication_oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(30),
    );
    crate::common::assert_command_success("persistent Server publication controls", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(output.stdout, b"server-poll-publication cases=4\n");
}
