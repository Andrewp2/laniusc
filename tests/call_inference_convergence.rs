mod common;

use std::{path::PathBuf, process::Command};

fn laniusc_bin() -> PathBuf {
    option_env!("CARGO_BIN_EXE_laniusc")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/debug/laniusc"))
}

/// Type checks a fixture with call-inference tracing and returns the number
/// of inference rounds it took.
fn inference_rounds(fixture: &str) -> usize {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(fixture);
    let mut command = Command::new(laniusc_bin());
    command
        .arg("check")
        .arg(&path)
        .env("LANIUS_TRACE_CALL_INFERENCE", "1");
    let output = common::command_output_with_timeout(fixture, &mut command);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(output.status.success(), "{fixture} failed to type check:\n{stderr}");
    stderr
        .lines()
        .filter(|line| line.starts_with("[typecheck.call_inference]"))
        .count()
}

#[test]
fn nested_generic_literal_contexts_converge_in_a_few_inference_rounds() {
    let rounds =
        inference_rounds("tests/fixtures/stdlib_foundation/repro_nested_literal_context_convergence.lani");
    assert!((1..=8).contains(&rounds), "call inference took {rounds} rounds");
}
