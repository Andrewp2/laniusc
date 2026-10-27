// Included by the Rust integration driver after its initial two gates finish.
fn cleanup_executable(entry_name: &str, label: &str) -> common::TempArtifact {
    let observer = common::TempArtifact::new("laniusc_https_server_cleanup", label, Some("o"));
    success(&run(Command::new("cc")
        .args(["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-c"])
        .arg(root().join("tests/fixtures/extended/openssl_tls_duplex/observer.c"))
        .arg("-o")
        .arg(observer.path())));
    let entry = fixture(entry_name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        libraries: vec!["ssl".into(), "crypto".into(), "dl".into()],
        objects: vec![observer.path().to_path_buf()],
        ..Default::default()
    };
    let bytes =
        common::run_gpu_codegen_with_timeout("HTTPS server cleanup native link", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry, &roots, &options,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("HTTPS server cleanup: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_https_server_cleanup", label, None);
    fs::write(executable.path(), bytes).unwrap();
    success(&run(Command::new("python3")
        .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
        .arg(executable.path())));
    let dynamic = run(Command::new("readelf").arg("-d").arg(executable.path()));
    success(&dynamic);
    let dependencies = String::from_utf8_lossy(&dynamic.stdout);
    assert!(
        dependencies.contains("libssl.so.3") && dependencies.contains("libcrypto.so.3"),
        "{dynamic:?}"
    );
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn cleanup_group(name: &str) {
    static PREPARATION: OnceLock<common::TempArtifact> = OnceLock::new();
    static CLOSE: OnceLock<common::TempArtifact> = OnceLock::new();
    let executable = if name == "preparation-abort" {
        PREPARATION.get_or_init(|| cleanup_executable("preparation_abort.lani", "preparation"))
    } else {
        CLOSE.get_or_init(|| cleanup_executable("normal_close.lani", "close"))
    };
    let output = run(Command::new("python3")
        .arg(fixture("cleanup_oracle.py"))
        .arg(executable.path())
        .arg(certificates().path())
        .arg(name));
    success(&output);
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("https-server-exchange-{name} cases=4"))
            && summary.contains("reached-close-EIO=2")
            && summary.contains("cleanup-ledger-controls=7"),
        "{summary}"
    );
    println!("{summary}");
}
#[test]
fn fatal_reply_preparation_abort_distinguishes_success_and_new_close_failure() {
    cleanup_group("preparation-abort");
}
#[test]
fn otherwise_successful_https_close_failure_has_one_canonical_primary() {
    cleanup_group("normal-close");
}
