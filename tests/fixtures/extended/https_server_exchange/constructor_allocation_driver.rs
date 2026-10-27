#[test]
fn constructor_reached_source_allocations_unwind_protocol_socket_and_native_session() {
    let output = run(Command::new("python3")
        .arg(fixture("constructor_allocations.py"))
        .arg(constructor_executable().path())
        .arg(certificates().path()));
    success(&output);
    let summary = String::from_utf8(output.stdout).unwrap();
    let fields: Vec<_> = summary.split_whitespace().collect();
    assert_eq!(fields.len(), 4, "{summary}");
    assert_eq!(fields[0], "https-server-exchange-constructor-allocations");
    let cases: usize = fields[1].strip_prefix("cases=").unwrap().parse().unwrap();
    let failures: usize = fields[2]
        .strip_prefix("reached-source-oom=")
        .unwrap()
        .parse()
        .unwrap();
    assert!(failures > 0 && cases == failures + 1, "{summary}");
    assert_eq!(fields[3], "constructor-ledger-controls=21");
    println!("{summary}");
}
