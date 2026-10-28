//! `machine` items (docs/state-machines-design.md, M1): elaboration, the
//! rules R2-R5, and the elaborated code against the same machine by hand.

mod common;

use std::path::PathBuf;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile(fixture: &str) -> Result<Vec<u8>, String> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/machines").join(fixture);
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(fixture, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .map_err(|error| error.to_string())
}

fn assert_exit(fixture: &str, code: i32) {
    let bytes = compile(fixture).unwrap_or_else(|error| panic!("{fixture}: {error}"));
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("machines", fixture, &bytes);
        assert_eq!(output.status.code(), Some(code), "{fixture}: {output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = (bytes, code);
}

fn assert_rejected(fixture: &str, expected: &[&str]) {
    let error = compile(fixture).expect_err(fixture);
    for text in expected {
        assert!(error.contains(text), "{fixture}: expected `{text}` in:\n{error}");
    }
}

#[test]
fn the_door_machine_steps_through_its_states() {
    assert_exit("door.lani", 0);
}

#[test]
fn an_integer_event_machine_runs_without_output() {
    assert_exit("sum_numbers.lani", 0);
}

// R1: the machine is the code a programmer writes by hand, so it compiles to
// the same program.
#[test]
fn a_machine_compiles_to_the_same_program_as_its_hand_written_form() {
    let machine = compile("door.lani").unwrap();
    let by_hand = compile("door_by_hand.lani").unwrap();
    assert_eq!(machine.len(), by_hand.len(), "program sizes differ");
    assert!(machine == by_hand, "the programs differ");
}

#[test]
fn an_arm_ends_in_a_transition() {
    assert_rejected("reject_return.lani", &["LNC0076", "not `return`", "reject_return.lani:4"]);
    assert_rejected("reject_falls_through.lani", &["LNC0006", "the end of this block arm can be reached", "reject_falls_through.lani:4"]);
}

#[test]
fn every_state_handles_every_event() {
    assert_rejected("reject_missing_event.lani", &["LNC0076", "does not handle `E::B`"]);
    assert_rejected("reject_wildcard.lani", &["LNC0076", "list each event"]);
}

#[test]
fn every_state_is_reachable_and_dead_ends_are_final() {
    assert_rejected("reject_unreachable.lani", &["LNC0076", "state `Draining` is unreachable from `start S`"]);
    assert_rejected("reject_dead_end.lani", &["LNC0076", "state `Closed` has no `goto` to another state", "final state Closed"]);
}

#[test]
fn the_state_is_private() {
    assert_rejected("reject_reserved.lani", &["LNC0076", "reserved"]);
}
