mod common;

use std::{path::PathBuf, process::Command};

fn laniusc_bin() -> PathBuf {
    option_env!("CARGO_BIN_EXE_laniusc")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/debug/laniusc"))
}

/// Type checks a fixture with call-inference tracing. Returns whether the
/// check passed, its stderr, and the number of inference rounds it took.
fn traced_check(fixture: &str) -> (bool, String, usize) {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(fixture);
    let mut command = Command::new(laniusc_bin());
    command
        .arg("check")
        .arg(&path)
        .env("LANIUS_TRACE_CALL_INFERENCE", "1");
    let output = common::command_output_with_timeout(fixture, &mut command);
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    let rounds = stderr
        .lines()
        .filter(|line| line.starts_with("[typecheck.call_inference]") && line.contains(" changed="))
        .count();
    (output.status.success(), stderr, rounds)
}

#[test]
fn nested_generic_literal_contexts_converge_in_a_few_inference_rounds() {
    let fixture = "tests/fixtures/stdlib_foundation/repro_nested_literal_context_convergence.lani";
    let (passed, stderr, rounds) = traced_check(fixture);
    assert!(passed, "{fixture} failed to type check:\n{stderr}");
    assert!((1..=8).contains(&rounds), "call inference took {rounds} rounds");
}

#[test]
fn array_literal_of_an_unknown_type_reports_it_after_a_few_inference_rounds() {
    let fixture = "tests/fixtures/stdlib_foundation/repro_unknown_array_element_convergence.lani";
    let (passed, stderr, rounds) = traced_check(fixture);
    assert!(!passed, "{fixture} type checked:\n{stderr}");
    assert!(stderr.contains("error[LNC0007]"), "expected an unknown type error:\n{stderr}");
    assert!((1..=8).contains(&rounds), "call inference took {rounds} rounds");
}
