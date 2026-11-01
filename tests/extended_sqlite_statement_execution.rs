//! ext::sqlite_statement's transition table against the rules ext::sqlite
//! enforced before it routed every state change through the machine.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::path::PathBuf;

const READY: u32 = 0;
const ROW: u32 = 1;
const DONE: u32 = 2;
const FAILED: u32 = 3;
const FINALIZED: u32 = 4;

/// (next state, allowed) for each event, in Event's declaration order.
fn expected(state: u32, event: u32) -> (u32, bool) {
    let stepping = state == READY || state == ROW;
    match event {
        // Bind, ClearBindings: only while Ready.
        0 | 1 => (state, state == READY),
        // Step: Ready or Row; sqlite3_step's result comes next.
        2 => (state, stepping),
        // StepRow, StepDone, StepFailed: only after an allowed Step.
        3 if stepping => (ROW, true),
        4 if stepping => (DONE, true),
        5 if stepping => (FAILED, true),
        3..=5 => (state, false),
        // Column: only on a row. ColumnFailed (out of memory) fails a row.
        6 => (state, state == ROW),
        7 if state == ROW => (FAILED, true),
        7 => (state, false),
        // Reset: back to Ready unless finalized (a closed handle).
        8 if state == FINALIZED => (state, false),
        8 => (READY, true),
        // Finalize: always, and again is a no-op.
        9 => (FINALIZED, true),
        _ => unreachable!(),
    }
}

#[test]
fn every_state_event_pair_matches_the_statement_rules() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/extended/sqlite_statement/table.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("sqlite_statement table", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("sqlite_statement table: {error}"));
    let output = common::run_x86_64_elf_output("sqlite_statement", "table", &bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    let lines: Vec<u32> = String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(|line| line.trim().parse().unwrap())
        .collect();
    assert_eq!(lines.len(), 51, "{lines:?}");
    for state in 0..5 {
        for event in 0..10 {
            let (next, allowed) = expected(state, event);
            let cell = lines[(state * 10 + event) as usize];
            assert_eq!(cell, next * 10 + allowed as u32, "state {state}, event {event}");
        }
    }
    assert_eq!(lines[50], READY, "start");
}
