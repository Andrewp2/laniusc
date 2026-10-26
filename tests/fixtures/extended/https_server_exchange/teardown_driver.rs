#[test]
fn teardown_failures_keep_confirmed_output_and_authenticated_empty_cleans_before_event() {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    let executable = EXECUTABLE.get_or_init(|| cleanup_executable("teardown.lani", "teardown"));
    let output = run(Command::new("python3")
        .arg(fixture("teardown_oracle.py"))
        .arg(executable.path())
        .arg(certificates().path()));
    success(&output);
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.trim().ends_with(
            "https-server-exchange-teardown cases=8 absolute-timeout=2 cut-native-record=2 drain-overflow=2 authenticated-empty=2 teardown-ledger-controls=31"
        ),
        "{summary}"
    );
    println!("{summary}");
}
