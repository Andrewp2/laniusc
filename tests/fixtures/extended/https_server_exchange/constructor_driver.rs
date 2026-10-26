fn constructor_executable() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(|| cleanup_executable("constructor.lani", "constructor"))
}
fn constructor_group(name: &str, expected: &str) {
    let output = run(Command::new("python3")
        .arg(fixture("constructor_oracle.py"))
        .arg(constructor_executable().path())
        .arg(certificates().path())
        .arg(name));
    success(&output);
    let summary = String::from_utf8(output.stdout).unwrap();
    assert_eq!(summary.trim(), expected);
    println!("{summary}");
}
#[test]
fn constructor_and_tls_io_quotas_fail_before_http_and_replay_without_native_io() {
    constructor_group(
        "constructor-quotas",
        "https-server-exchange-constructor-quotas cases=6 real-handshake-WANT_READ=2 constructor-ledger-controls=17",
    );
}
