//! Physical GPU batch tests over real accepted compiler snapshots.
//! Integrate as `#[cfg(test)] mod batch_tests;` under program_evidence/dispatch.
//! These check packet selection and explicit replay contexts. They do not link
//! or execute native bodies, or claim caller-evidence scheduling is integrated.

use std::collections::BTreeSet;

use super::{
    super::{
        catalog::CatalogInput,
        packet::ReplayContextInput,
    },
    *,
};
use crate::{
    compiler::{
        gpu_compiler::typecheck::{CompiledSourcePackUnit, OriginalUnitFacts},
        GpuCompiler, GpuSemanticInterfaceArtifact,
        SourcePackArtifactTarget,
    },
    type_checker::{CheckedGenericCall, CheckedGenericType},
};

const PROVIDER: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../tests/fixtures/stdlib_compiler_state/trait-type-graphs/stdlib/core/contracts.lani"
));
const CALLER: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../tests/fixtures/stdlib_compiler_state/trait-type-graphs/imported-caller-impl.lani"
));
const FORWARDING: &str = r#"
module batch_cases::forward;
pub trait Mark {}
pub impl Mark for i32 {}
pub fn keep<T>(v:T)->T where T:Mark { return v; }
pub fn relay<T,U>(v:T)->T where T:Mark { return keep(v); }
fn main()->i32 {
    let first=relay<i32,bool>(19);
    let second=relay<i32,[i32;3]>(23);
    return first+second-42;
}
"#;

fn compile_unit(
    compiler: &GpuCompiler<'_>,
    key: [u32; 2],
    source: &str,
    pages: Vec<Vec<GpuSemanticInterfaceArtifact>>,
) -> CompiledSourcePackUnit {
    pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
        vec![source.to_owned()].into(),
        key[0],
        key[1],
        pages.into(),
        SourcePackArtifactTarget::X86_64,
    ))
    .expect("compile accepted original unit without native specialization/linking")
}

fn batch_job(
    compiler: &GpuCompiler<'_>,
    units: &[&CompiledSourcePackUnit],
) -> (GpuProgramEvidence, GpuPacket) {
    let facts = units.iter().map(|unit| unit.original_facts().unwrap()).collect::<Vec<_>>();
    let inputs = facts.iter().map(|facts| CatalogInput { facts }).collect::<Vec<_>>();
    let catalog = FrozenCatalog::freeze(&inputs).expect("freeze real accepted snapshots");
    let gpu = GpuProgramEvidence::admit(
        compiler.program_evidence_workspace.checkout(),
        catalog,
    )
    .expect("GPU admits the valid catalog before batch selection");
    let mut packet = gpu.new_packet().expect("owned GPU packet");
    append_originals(&mut packet);
    (gpu, packet)
}

fn append_originals(packet: &mut GpuPacket) {
    let facts = packet.packet.catalog.snapshots.iter()
        .map(|snapshot| snapshot.original_facts.clone()).collect::<Vec<_>>();
    for facts in facts {
        packet.packet_mut().unwrap().append_original_unit_calls(&facts).unwrap();
    }
}

fn gpu_failure(error: &anyhow::Error) -> &EvidenceDispatchFailure {
    error
        .downcast_ref::<EvidenceDispatchFailure>()
        .unwrap_or_else(|| {
            panic!("expected a GPU semantic receipt, not infrastructure failure: {error:#}")
        })
}

fn original_call_row(packet: &ProgramPacket, snapshot: u32, hir: u32) -> u32 {
    let found = (0..packet.tables.count(15).unwrap())
        .filter(|&row| {
            let call = packet.tables.row(15, row).unwrap();
            let context = packet.tables.row(13, call[0]).unwrap();
            call[1] == hir && context[0] == snapshot && context[5] == 0
        })
        .collect::<Vec<_>>();
    assert_eq!(found.len(), 1, "one admitted original source occurrence");
    found[0]
}

fn call_evidence(
    packet: &ProgramPacket,
    call: u32,
    original_results: &[ValidatedEvidence],
) -> ValidatedEvidence {
    let row = packet.tables.row(15, call).unwrap();
    assert_eq!(row[6], 1, "fixture callable owns one marker predicate");
    // The initial submission starts at obligation zero. This is an exact row
    // join to the GPU result, never host goal matching or witness selection.
    let proof = original_results[row[5] as usize].clone();
    assert!(proof.is_concrete(), "concrete origin evidence");
    proof
}

fn combined_row(packet: &ProgramPacket, table: usize, row: u32) -> &[u32] {
    let prefix = packet.catalog.tables.count(table).unwrap();
    if row < prefix {
        packet.catalog.tables.row(table, row).unwrap()
    } else {
        packet.tables.row(table, row - prefix).unwrap()
    }
}

fn type_binding(packet: &ProgramPacket, environment: u32, slot: u32) -> (u32, [u32; 2]) {
    let env = packet.tables.row(11, environment).unwrap();
    let parameters = packet.catalog.composed_parameters(env[0]).unwrap();
    let parameter = parameters
        .iter()
        .find(|p| p[3] == 0 && p[2] == slot)
        .expect("retained exact type parameter at composed slot")[1];
    let binding = (env[1]..env[1] + env[2])
        .find(|&row| packet.tables.row(12, row).unwrap()[1] == parameter)
        .unwrap();
    let root = packet.tables.row(12, binding).unwrap()[2];
    (binding, combined_row(packet, 7, root).try_into().unwrap())
}

fn forwarding_calls(unit: &CompiledSourcePackUnit) -> (u32, u32, Vec<CheckedGenericCall>) {
    let symbolic = unit
        .generic_calls
        .iter()
        .filter(|call| !call.has_closed_arguments())
        .collect::<Vec<_>>();
    assert_eq!(symbolic.len(), 1, "one abstract keep call inside relay");
    let inner_hir = symbolic[0].call_hir;
    let relay_hir = unit
        .checked_call_owners
        .iter()
        .find(|owner| owner.call_hir == inner_hir)
        .unwrap()
        .function_hir;
    let concrete = unit
        .generic_calls
        .iter()
        .filter(|call| call.has_closed_arguments())
        .cloned()
        .collect::<Vec<_>>();
    assert_eq!(
        concrete.len(),
        2,
        "two concrete relay calls with distinct unused U"
    );
    (inner_hir, relay_hir, concrete)
}

#[test]
fn gpu_batch_selects_imported_callers_nested_length_implementation() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let provider = compile_unit(&compiler, [81, 0], PROVIDER, vec![]);
    let caller = compile_unit(
        &compiler,
        [82, 0],
        CALLER,
        vec![vec![provider.interface.clone()]],
    );
    assert_eq!(caller.generic_calls.len(), 1);
    assert_eq!(provider.checked_contracts.implementations.len(), 1);
    assert_eq!(caller.checked_contracts.implementations.len(), 1);
    let (mut gpu, mut packet) = batch_job(&compiler, &[&provider, &caller]);
    let result = gpu
        .check(&mut packet)
        .expect("GPU selects caller's length-3 implementation");
    assert_eq!(result.len(), 1);
    assert!(result[0].is_concrete(),
        "GPU-owned proof discharges the caller's length-3 goal despite the provider's length-2 candidate");
}

#[test]
fn gpu_batch_missing_and_wrong_inner_implementations_are_semantic_failures() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let provider = compile_unit(&compiler, [83, 0], PROVIDER, vec![]);
    for (label, implementation) in [
        ("missing", ""),
        (
            "wrong inner scalar",
            "pub impl core::contracts::Rel<core::contracts::Cell<[bool;3]>> for bool {}",
        ),
    ] {
        let source = format!(
            r#"
import core::contracts;
{implementation}
fn main()->i32 {{
    if(core::contracts::keep(false,[19,23,24])) {{ return 1; }}
    return 0;
}}
"#
        );
        let caller = compile_unit(
            &compiler,
            [84, 0],
            &source,
            vec![vec![provider.interface.clone()]],
        );
        let (mut gpu, mut packet) = batch_job(&compiler, &[&provider, &caller]);
        let error = gpu
            .check(&mut packet)
            .expect_err("no exact implementation for this call");
        let failure = gpu_failure(&error);
        assert_eq!(failure.catalog[0], 1, "{label}: accepted catalog");
        assert_eq!(failure.receipt[0], 6, "{label}: batch obligation failure");
        assert_eq!(
            failure.obligation.expect("precise failed obligation").1[0],
            3,
            "{label}: MISSING_IMPLEMENTATION, not transport or malformed input"
        );
        assert_eq!(failure.call.expect("failed call").1[0], 3);
    }
}

#[test]
fn gpu_batch_forwards_hypotheses_and_keeps_two_replay_occurrences_separate() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let unit = compile_unit(&compiler, [85, 0], FORWARDING, vec![]);
    let (inner_hir, relay_hir, concrete) = forwarding_calls(&unit);
    let (mut gpu, mut packet) = batch_job(&compiler, &[&unit]);
    let original = gpu
        .check(&mut packet)
        .expect("GPU checks abstract forwarding and concrete origins");
    let snapshot = packet.packet.catalog.snapshot_by_unit[&[85, 0]];
    let symbolic_row = original_call_row(&packet.packet, snapshot, inner_hir);
    let symbolic_obligation = packet.packet.tables.row(15, symbolic_row).unwrap()[5];
    assert!(
        !original[symbolic_obligation as usize].is_concrete(),
        "original call retains hypothesis evidence"
    );
    assert_eq!(original.iter().filter(|proof| proof.is_concrete()).count(), 2);
    let mut replay_contexts = BTreeSet::new();
    let mut unused_roots = Vec::new();
    for call in &concrete {
        let origin = original_call_row(&packet.packet, snapshot, call.call_hir);
        let proof = call_evidence(&packet.packet, origin, &original);
        let context = packet
            .packet_mut()
            .unwrap()
            .replay_context(ReplayContextInput {
                snapshot,
                selected_owner_hir: relay_hir,
                evidence: std::slice::from_ref(&proof),
                origin_call: origin,
            })
            .unwrap();
        assert!(replay_contexts.insert(context));
        let body_env = packet.packet.tables.row(13, context).unwrap()[2];
        let origin_env = packet.packet.tables.row(15, origin).unwrap()[4];
        let (_, body_unused) = type_binding(&packet.packet, body_env, 1);
        let (_, origin_unused) = type_binding(&packet.packet, origin_env, 1);
        assert_eq!(
            body_unused, origin_unused,
            "unused U comes from this exact concrete origin"
        );
        unused_roots.push(body_unused);
        // Existing local replay supplies real fresh checked call environments.
        // The source owns its i32 marker impl, so this does not depend on the
        // unfinished imported-body caller-evidence scheduling integration.
        let fresh = pollster::block_on(compiler.compile_body_specialization(&unit, call))
            .expect("produce real concrete checked call facts for the selected local body");
        let calls = packet
            .packet_mut()
            .unwrap()
            .append_replay_unit_calls(&fresh, relay_hir, context)
            .unwrap();
        assert_eq!(calls.count, 1, "only selected body adds a call occurrence");
        let row = packet.packet.tables.row(15, calls.first).unwrap();
        assert_eq!((row[0], row[1]), (context, inner_hir));
        let replayed = gpu
            .check(&mut packet)
            .expect("GPU validates supplied evidence and concrete inner call");
        assert_eq!(replayed.len(), 1);
        assert!(
            replayed[0].is_concrete(),
            "replayed obligation has concrete evidence"
        );
    }
    assert_eq!(unused_roots.len(), 2);
    assert_ne!(
        unused_roots[0], unused_roots[1],
        "bool and array remain distinct unused arguments"
    );
    let contexts = (0..packet.packet.tables.count(15).unwrap())
        .filter_map(|row| {
            let call = packet.packet.tables.row(15, row).unwrap();
            (call[1] == inner_hir).then_some(call[0])
        })
        .collect::<BTreeSet<_>>();
    assert_eq!(
        contexts.len(),
        3,
        "one source call HIR has original and two concrete contexts"
    );
}

#[test]
fn gpu_batch_rejects_changed_unused_replay_binding_despite_matching_predicate() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let unit = compile_unit(&compiler, [86, 0], FORWARDING, vec![]);
    let (_, relay_hir, concrete) = forwarding_calls(&unit);
    let call = concrete
        .iter()
        .find(|call| call.arguments[1].ty == CheckedGenericType::Scalar(2))
        .expect("origin with unused U=bool");
    let (mut gpu, mut packet) = batch_job(&compiler, &[&unit]);
    let original = gpu.check(&mut packet).expect("valid original proof");
    let snapshot = packet.packet.catalog.snapshot_by_unit[&[86, 0]];
    let origin = original_call_row(&packet.packet, snapshot, call.call_hir);
    let proof = call_evidence(&packet.packet, origin, &original);
    let context = packet
        .packet_mut()
        .unwrap()
        .replay_context(ReplayContextInput {
            snapshot,
            selected_owner_hir: relay_hir,
            evidence: &[proof],
            origin_call: origin,
        })
        .unwrap();
    let body_env = packet.packet.tables.row(13, context).unwrap()[2];
    let (unused_binding, unused) = type_binding(&packet.packet, body_env, 1);
    let (subject_binding, subject) = type_binding(&packet.packet, body_env, 0);
    assert_eq!(unused, [1, 2]);
    assert_eq!(subject, [1, 3]);
    let wrong_root = packet.packet.tables.row(12, subject_binding).unwrap()[2];
    // Narrow corruption of an unpublished row. Both roots are accepted closed
    // scalars; T:Mark and its evidence are untouched. Only exact origin ownership
    // of the unused U is violated, so predicate-only checking would miss it.
    packet.packet.tables.row_mut(12, unused_binding).unwrap()[2] = wrong_root;
    let error = gpu
        .check(&mut packet)
        .expect_err("changed unused binding must invalidate replay");
    let failure = gpu_failure(&error);
    assert_eq!(
        &failure.receipt[..2],
        &[2, 9],
        "INVALID_INPUT / origin binding mismatch"
    );
}

#[test]
fn gpu_batch_empty_deltas_get_fresh_receipts_and_reject_unused_bad_roots() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let unit = compile_unit(
        &compiler,
        [87, 0],
        "module batch_cases::empty; pub fn anchor()->i32 { return 0; }",
        vec![],
    );
    assert!(unit.generic_calls.is_empty());
    let (mut gpu, mut packet) = batch_job(&compiler, &[&unit]);
    assert!(gpu
        .check(&mut packet)
        .expect("empty initial batch still admitted")
        .is_empty());
    let first_serial = packet.completed_serial;
    assert!(gpu
        .check(&mut packet)
        .expect("empty delta still admitted")
        .is_empty());
    assert_eq!(packet.completed_serial, first_serial + 1);
    let local = packet.packet.tables.push(7, &[0, INVALID]).unwrap();
    let root = packet.packet.catalog.tables.count(7).unwrap() + local;
    assert_eq!(packet.packet.tables.count(15).unwrap(), 0);
    assert_eq!(packet.packet.tables.count(16).unwrap(), 0);
    let error = gpu
        .check(&mut packet)
        .expect_err("unused malformed suffix row fails the whole batch");
    let failure = gpu_failure(&error);
    assert_eq!(
        &failure.receipt[..4],
        &[2, 4, root, 7],
        "GPU rejects invalid Root2 even with no obligations"
    );
    assert_eq!(
        failure.receipt[6],
        first_serial + 2,
        "failure is a new receipt, not prior success"
    );
}

const TWO_GOAL_FORWARDING: &str = r#"
module batch_cases::proof_provenance;
pub trait Mark {}
pub impl Mark for i32 {}
pub impl Mark for bool {}
pub fn keep<T>(v:T)->T where T:Mark { return v; }
pub fn relay<T,U>(v:T)->T where T:Mark { return keep(v); }
fn main()->i32 {
    let first=relay<i32,bool>(42);
    let second=relay<bool,[i32;3]>(false);
    if(second) { return 1; }
    return first-42;
}
"#;

fn scalar_origin_evidence(
    unit: &CompiledSourcePackUnit,
    packet: &ProgramPacket,
    snapshot: u32,
    results: &[ValidatedEvidence],
    scalar: u32,
) -> (u32, ValidatedEvidence, u32) {
    let call = unit
        .generic_calls
        .iter()
        .find(|call| {
            call.has_closed_arguments()
                && call.arguments[0].ty == CheckedGenericType::Scalar(scalar)
        })
        .expect("concrete relay origin for this scalar");
    let origin = original_call_row(packet, snapshot, call.call_hir);
    let proof = call_evidence(packet, origin, results);
    let obligation = packet.tables.row(15, origin).unwrap()[5];
    let rows = (0..packet.tables.count(17).unwrap())
        .filter(|&row| {
            let evidence = packet.tables.row(17, row).unwrap();
            evidence[0] == 1 && evidence[5] == origin && evidence[6] == obligation
        })
        .collect::<Vec<_>>();
    assert_eq!(
        rows.len(),
        1,
        "one retained concrete evidence row for the exact origin"
    );
    let evidence = packet.tables.row(17, rows[0]).unwrap();
    assert_ne!(evidence[3], INVALID, "retained proof has a closure root");
    assert_ne!(evidence[4], INVALID, "retained proof has an admitted conclusion");
    (origin, proof, rows[0])
}

#[test]
fn gpu_batch_rejects_changed_retained_witness_before_replay() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let unit = compile_unit(&compiler, [88, 0], TWO_GOAL_FORWARDING, vec![]);
    let (mut gpu, mut packet) = batch_job(&compiler, &[&unit]);
    let original = gpu
        .check(&mut packet)
        .expect("valid initial concrete selections");
    assert_eq!(original.iter().filter(|proof| proof.is_concrete()).count(), 2);
    let snapshot = packet.packet.catalog.snapshot_by_unit[&[88, 0]];
    let (_, _, evidence) = scalar_origin_evidence(&unit, &packet.packet, snapshot, &original, 3);
    let (_, _, other) = scalar_origin_evidence(&unit, &packet.packet, snapshot, &original, 2);
    let before: [u32; 8] = packet
        .packet
        .tables
        .row(17, evidence)
        .unwrap()
        .try_into()
        .unwrap();
    let other_proof_root = packet.packet.tables.row(17, other).unwrap()[3];
    assert_ne!(before[3], other_proof_root);
    assert_eq!(packet.completed_suffix_counts[17], 0);
    assert!(evidence < packet.packet.tables.count(17).unwrap());
    for table in [13, 15, 16] {
        assert_eq!(
            packet.completed_suffix_counts[table],
            packet.packet.tables.count(table).unwrap()
        );
    }
    let previous_serial = packet.completed_serial;
    // accept_submission just retained these GPU outputs on the host. They have
    // not been uploaded as Evidence17 inputs yet. Change only the witness to
    // another accepted proof root; all origin/obligation backlinks remain
    // valid. The normal next check must upload this new suffix and reject its
    // difference from the immutable GPU output, even without a replay context.
    packet.packet.tables.row_mut(17, evidence).unwrap()[3] = other_proof_root;
    let error = gpu
        .check(&mut packet)
        .expect_err("changed proof must fail exact GPU provenance");
    let failure = gpu_failure(&error);
    assert_eq!(&failure.receipt[..4], &[2, 13, evidence, before[6]]);
    assert_eq!(failure.receipt[6], previous_serial + 1);
    assert!(failure.context.is_none() && failure.call.is_none() && failure.obligation.is_none());
    assert!(
        packet.packet_mut().is_err(),
        "a failed arena cannot authorize another batch"
    );

    // Reuse the same frozen catalog and dispatcher after discarding the failed
    // arena. Untampered returned proofs must survive the same evidence-only
    // upload, without recompiling the source or readmitting the catalog.
    let mut fresh = gpu.new_packet().unwrap();
    append_originals(&mut fresh);
    let selected = gpu
        .check(&mut fresh)
        .expect("fresh arena selects both goals");
    assert_eq!(selected.iter().filter(|proof| proof.is_concrete()).count(), 2);
    assert!(
        gpu.check(&mut fresh)
            .expect("untampered retained evidence is accepted")
            .is_empty()
    );
    assert_eq!(fresh.completed_serial, 2);
    assert_eq!(
        fresh.completed_suffix_counts[17],
        fresh.packet.tables.count(17).unwrap()
    );
}

#[test]
fn gpu_batch_rejects_authentic_evidence_for_a_different_replay_goal() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let unit = compile_unit(&compiler, [89, 0], TWO_GOAL_FORWARDING, vec![]);
    let (_, relay_hir, _) = forwarding_calls(&unit);
    let (mut gpu, mut packet) = batch_job(&compiler, &[&unit]);
    // Reject the wrong goal, then accept a matching proof in a fresh arena on
    // the same dispatcher. Both cases use real original GPU selections.
    for wrong_goal in [true, false] {
        let original = gpu
            .check(&mut packet)
            .expect("valid initial concrete selections");
        assert_eq!(original.iter().filter(|proof| proof.is_concrete()).count(), 2);
        let snapshot = packet.packet.catalog.snapshot_by_unit[&[89, 0]];
        let (origin, proof, expected) =
            scalar_origin_evidence(&unit, &packet.packet, snapshot, &original, 3);
        let (other_origin, _, other) =
            scalar_origin_evidence(&unit, &packet.packet, snapshot, &original, 2);
        assert_ne!(origin, other_origin);
        assert_ne!(expected, other);
        let context = packet
            .packet_mut()
            .unwrap()
            .replay_context(ReplayContextInput {
                snapshot,
                selected_owner_hir: relay_hir,
                evidence: std::slice::from_ref(&proof),
                origin_call: origin,
            })
            .expect("construct a valid replay with the matching i32 proof");
        let row = packet.packet.tables.row(13, context).unwrap();
        assert_eq!(row[4], 1);
        let assumption = row[3];
        assert!(assumption >= packet.completed_suffix_counts[14]);
        assert_eq!(
            packet.packet.tables.row(14, assumption).unwrap()[3],
            expected
        );
        let retained_evidence = packet.packet.tables.words[17].clone();
        if wrong_goal {
            // Only change the supplied proof reference. The bool evidence is
            // an authentic output of another admitted origin in this arena;
            // it passes exact provenance, but cannot prove i32:Mark here.
            packet.packet.tables.row_mut(14, assumption).unwrap()[3] = other;
        }
        assert_eq!(packet.packet.tables.words[17], retained_evidence);
        for table in [15, 16] {
            assert_eq!(
                packet.completed_suffix_counts[table],
                packet.packet.tables.count(table).unwrap()
            );
        }
        if wrong_goal {
            let error = gpu
                .check(&mut packet)
                .expect_err("authentic wrong-goal proof must invalidate replay");
            let failure = gpu_failure(&error);
            assert_eq!(&failure.receipt[..4], &[2, 13, context, other]);
            let (failed_context, status) = failure
                .context
                .expect("new replay context failed goal comparison");
            assert_eq!(failed_context, context);
            assert_eq!(&status[..4], &[2, 13, context, other]);
            assert!(failure.call.is_none() && failure.obligation.is_none());
            packet = gpu.new_packet().unwrap();
            append_originals(&mut packet);
        } else {
            assert!(
                gpu.check(&mut packet)
                    .expect("matching proof validates the replay context")
                    .is_empty()
            );
            assert_eq!(packet.completed_serial, 2);
        }
    }
}

/// GpuPacket::retained_input_rewrite: the submission also uploads one retained
/// input row as the host tables now hold it, as a serializer that rewrote old
/// rows would. `row` is the host row of `table`.
pub(super) fn rewrite_retained_input(
    packet: &GpuPacket,
    layout: &OutputLayout,
    mut submission: Submission,
) -> Result<Submission> {
    if let Some((table, row)) = packet.retained_input_rewrite.take() {
        ensure!(row < packet.completed_suffix_counts[table], "rewrite needs a retained row");
        let words = packet.packet.tables.row(table, row)?.to_vec();
        let first_word = add(layout.input_offsets[table], mul(row, WIDTHS[table], "row")?, "row word")?;
        submission.plan.writes.push(ArenaWrite { first_word, words });
    }
    Ok(submission)
}

// Proof work selection and assumption-proof admission trust the assumption
// index that kernel 15 built when an assumption row was new. That is sound
// only while a retained row cannot change, so the lifecycle must refuse any
// submission that rewrites one, before a kernel reads the stale index.
#[test]
fn gpu_batch_refuses_rewritten_retained_assumption_row() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let unit = compile_unit(&compiler, [90, 0], TWO_GOAL_FORWARDING, vec![]);
    let (_, relay_hir, _) = forwarding_calls(&unit);
    let (mut gpu, mut packet) = batch_job(&compiler, &[&unit]);
    let original = gpu
        .check(&mut packet)
        .expect("valid initial concrete selections");
    let snapshot = packet.packet.catalog.snapshot_by_unit[&[90, 0]];
    let (origin, proof, _) = scalar_origin_evidence(&unit, &packet.packet, snapshot, &original, 3);
    let (_, _, other) = scalar_origin_evidence(&unit, &packet.packet, snapshot, &original, 2);
    let context = packet
        .packet_mut()
        .unwrap()
        .replay_context(ReplayContextInput {
            snapshot,
            selected_owner_hir: relay_hir,
            evidence: std::slice::from_ref(&proof),
            origin_call: origin,
        })
        .expect("construct a valid replay with the matching i32 proof");
    let assumption = packet.packet.tables.row(13, context).unwrap()[3];
    assert!(
        gpu.check(&mut packet)
            .expect("matching proof validates the replay context")
            .is_empty()
    );
    // The replay's caller assumption is now retained and indexed.
    assert!(assumption < packet.completed_suffix_counts[14]);
    let previous_serial = packet.completed_serial;
    // The authentic proof of another goal, as in the wrong-goal test above, but
    // as a rewrite of the retained row.
    packet.packet.tables.row_mut(14, assumption).unwrap()[3] = other;
    packet.retained_input_rewrite.set(Some((14, assumption)));
    let error = gpu
        .check(&mut packet)
        .expect_err("a rewritten retained row must be refused");
    assert!(
        format!("{error:#}").contains("rewrites retained input rows"),
        "unexpected refusal: {error:#}"
    );
    assert_eq!(packet.completed_serial, previous_serial);
    assert!(
        packet.packet_mut().is_err(),
        "a refused submission cannot authorize another batch"
    );
}

// Fault injection owns no semantic decision: it changes one already-emitted
// pending row and then resumes the exact production admission/commit schedule.
#[derive(Clone, Copy, Debug)]
enum ProofAdmissionFaultKind {
    AssumptionSubstitution,
    OriginalHypothesisClass,
    UnknownKind(u32),
}

#[derive(Clone)]
struct ProofAdmissionObservation {
    header: Vec<u32>,
    evidence: Vec<u32>,
    evidence_slice: Slice,
    proof_word: u32,
    corrupted: [u32; 8],
}

pub(super) struct ProofAdmissionFault {
    kind: ProofAdmissionFaultKind,
    observation: Option<ProofAdmissionObservation>,
}

/// Test-only seam after phase58 has completed and before either phase59 pass.
/// No validation stage is bypassed, replaced, or told the expected result.
pub(super) fn inject_pending_proof_fault(
    gpu: &GpuProgramEvidence,
    packet: &GpuPacket,
    layout: &OutputLayout,
    progress: &proof::ProofProgress,
) -> anyhow::Result<()> {
    let mut armed = packet.proof_admission_fault.borrow_mut();
    let Some(fault) = armed.as_mut() else {
        return Ok(());
    };
    if fault.observation.is_some() {
        return Ok(());
    }
    const PROOFS: usize = 6;
    let pending = progress.pending(PROOFS)?;
    if pending.count == 0 {
        return Ok(());
    }
    let proof_slice = packet.packet.proof_store.layout().slices[PROOFS];
    let first_word = add(
        proof_slice.offset,
        mul(pending.first, 8, "pending proof test offset")?,
        "pending proof test address",
    )?;
    let evidence_slice = layout.slices[5];
    let raw = gpu.readback.read_regions(
        &gpu.device,
        &gpu.queue,
        &[
            ReadbackRegion::from_buffer(
                &packet.proof.buffer,
                0,
                arena::byte_len(PROOF_STORE_FIXED_WORDS)?,
                "proof admission test directory",
            )?,
            ReadbackRegion::from_buffer(
                &packet.proof.buffer,
                u64::from(first_word) * 4,
                arena::byte_len(mul(pending.count, 8, "pending proof test words")?)?,
                "proof admission test pending rows",
            )?,
            layout.region(
                &gpu.storage,
                &packet.output,
                5,
                Span::new(0, evidence_slice.count)?,
            )?,
        ],
        "proof admission test before injection",
    )?;
    let rows = statuses(&raw[1])?;
    let Some((index, original)) = rows.iter().enumerate().find(|(_, row)| {
        row[0] == 2
            && row[7] == 2
            && packet
                .packet
                .tables
                .row(13, row[2])
                .is_ok_and(|context| context[5] == 0)
    }) else {
        return Ok(());
    };
    // This fixture must reach both validators in one wave. Selecting by row
    // kind/context avoids depending on atomic reservation order or proof IDs.
    assert!(
        rows.iter().any(|row| row[0] == 1),
        "mixed implementation/assumption wave"
    );
    assert_eq!(
        &original[4..7],
        &[INVALID, 0, 0],
        "valid assumption before injection"
    );
    let header = words(&raw[0])?;
    let evidence = words(&raw[2])?;
    assert!(
        evidence_slice.count > 0,
        "fixture has observable evidence roots"
    );
    assert!(
        evidence.chunks_exact(8).all(|row| row[0] == 0),
        "no root published before admission"
    );
    let mut corrupted = *original;
    let field = match fault.kind {
        ProofAdmissionFaultKind::AssumptionSubstitution => {
            corrupted[4] = 0; // Assumptions must have no substitution.
            4
        }
        ProofAdmissionFaultKind::OriginalHypothesisClass => {
            corrupted[7] = 1; // Original hypotheses must remain symbolic.
            7
        }
        ProofAdmissionFaultKind::UnknownKind(kind) => {
            assert!(!matches!(kind, 1 | 2));
            corrupted[0] = kind;
            0
        }
    };
    let proof_word = add(
        first_word,
        mul(u32::try_from(index)?, 8, "fault row")?,
        "fault proof",
    )?;
    let mut encoder = gpu
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("program_evidence.test_corrupt_pending_proof"),
        });
    packet.proof.upload(
        &mut encoder,
        &[ArenaWrite {
            first_word: add(proof_word, field as u32, "fault field")?,
            words: vec![corrupted[field]],
        }],
    )?;
    gpu.queue.submit(Some(encoder.finish()));
    fault.observation = Some(ProofAdmissionObservation {
        header,
        evidence,
        evidence_slice,
        proof_word,
        corrupted,
    });
    Ok(())
}

#[test]
fn gpu_batch_rejects_corrupted_pending_assumption_proofs_before_commit() {
    use super::super::proof_store::{PROOF_STORE_DIRECTORY, PROOF_STORE_PERSISTENT};

    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let unit = compile_unit(&compiler, [90, 0], FORWARDING, vec![]);
    let (mut gpu, mut control) = batch_job(&compiler, &[&unit]);
    let valid = gpu
        .check(&mut control)
        .expect("unmodified mixed proof wave succeeds");
    assert_eq!(valid.iter().filter(|proof| proof.is_concrete()).count(), 2);
    assert_eq!(valid.iter().filter(|proof| !proof.is_concrete()).count(), 1);
    assert_eq!(control.completed_serial, 1);

    for kind in [
        ProofAdmissionFaultKind::AssumptionSubstitution,
        ProofAdmissionFaultKind::OriginalHypothesisClass,
        ProofAdmissionFaultKind::UnknownKind(0),
        ProofAdmissionFaultKind::UnknownKind(3),
    ] {
        let mut packet = gpu.new_packet().expect("fresh fault-case arena");
        append_originals(&mut packet);
        *packet.proof_admission_fault.borrow_mut() = Some(ProofAdmissionFault {
            kind,
            observation: None,
        });
        let error = match gpu.check(&mut packet) {
            Ok(_) => panic!("{kind:?}: malformed pending proof gained authority"),
            Err(error) => error,
        };
        let observation = packet
            .proof_admission_fault
            .borrow()
            .as_ref()
            .unwrap()
            .observation
            .clone()
            .expect("fault reached a real pending original assumption");
        let failure = gpu_failure(&error);
        assert_eq!(failure.catalog[0], 1, "{kind:?}: catalog remains valid");
        assert_eq!(
            &failure.receipt[..2],
            &[2, 68],
            "{kind:?}: proof admission rejects malformed row"
        );

        // Read the actual device directory and output, independently of the
        // host receipt decoder and its ledger of successfully accepted rows.
        let raw = gpu
            .readback
            .read_regions(
                &gpu.device,
                &gpu.queue,
                &[
                    ReadbackRegion::from_buffer(
                        &packet.proof.buffer,
                        0,
                        arena::byte_len(PROOF_STORE_FIXED_WORDS).unwrap(),
                        "failed proof admission directory",
                    )
                    .unwrap(),
                    ReadbackRegion::from_buffer(
                        &packet.output.buffer,
                        u64::from(observation.evidence_slice.offset) * 4,
                        arena::byte_len(observation.evidence_slice.count * 8).unwrap(),
                        "failed proof admission evidence roots",
                    )
                    .unwrap(),
                    ReadbackRegion::from_buffer(
                        &packet.proof.buffer,
                        u64::from(observation.proof_word) * 4,
                        32,
                        "failed proof admission injected row",
                    )
                    .unwrap(),
                ],
                "proof admission test after rejection",
            )
            .expect("read failure without granting authority");
        let after = words(&raw[0]).unwrap();
        let before = &observation.header;
        assert_eq!(
            one_status(&raw[2]).unwrap(),
            observation.corrupted,
            "{kind:?}: injected word persisted"
        );
        let proof_directory = PROOF_STORE_DIRECTORY as usize + 6 * 6;
        assert!(
            before[proof_directory + 1] > before[proof_directory + 3],
            "{kind:?}: pending proof suffix existed"
        );
        for table in 0..PROOF_STORE_PERSISTENT {
            let base = PROOF_STORE_DIRECTORY as usize + table * 6;
            assert_eq!(
                after[base + 3],
                before[base + 3],
                "{kind:?}: table{table} admitted prefix did not advance"
            );
            assert_eq!(
                after[base + 4],
                before[base + 4],
                "{kind:?}: table{table} accepted prefix did not advance"
            );
        }
        assert_eq!(
            after[7], before[7],
            "{kind:?}: accepted serial did not advance"
        );
        assert_ne!(after[10], 1, "{kind:?}: arena did not become valid");
        assert_eq!(
            words(&raw[1]).unwrap(),
            observation.evidence,
            "{kind:?}: no evidence root published"
        );
        assert_eq!(
            packet.completed_serial, 0,
            "{kind:?}: host did not accept submission"
        );
        assert!(
            packet
                .packet
                .proof_store
                .accepted_prefix()
                .iter()
                .all(|&count| count == 0)
        );
        assert!(packet.poisoned, "{kind:?}: failed packet cannot be reused");
        assert!(
            packet.packet_mut().is_err(),
            "{kind:?}: mutation capability withheld"
        );
    }
}

// Blanket implementation selection belongs to the complete GPU program gate.
// Retain the checked definition facts from the pending-original producer; its
// native object is never released or used by these layout-only fixtures.
fn compile_native_layout_facts(
    compiler: &GpuCompiler<'_>,
    key: [u32; 2],
    source: &str,
) -> OriginalUnitFacts {
    let pending = pollster::block_on(compiler.compile_pending_original_source_pack_unit(
        vec![source.to_owned()].into(),
        key[0],
        key[1],
        Vec::<Vec<GpuSemanticInterfaceArtifact>>::new().into(),
        None,
    ))
    .expect("retain checked original facts before complete GPU implementation selection");
    pending.facts().clone()
}

fn native_layout_batch_job(
    compiler: &GpuCompiler<'_>,
    facts: &OriginalUnitFacts,
) -> (GpuProgramEvidence, GpuPacket) {
    let catalog = FrozenCatalog::freeze(&[CatalogInput { facts }])
        .expect("freeze checked original native-layout facts");
    let gpu = GpuProgramEvidence::admit(
        compiler.program_evidence_workspace.checkout(),
        catalog,
    )
    .expect("GPU admits native-layout catalog before blanket implementation selection");
    let mut packet = gpu.new_packet().expect("owned native-layout proof packet");
    append_originals(&mut packet);
    (gpu, packet)
}

fn native_layout_test_limits() -> super::super::native_layout_work::NativeLayoutWorkLimits {
    super::super::native_layout_work::NativeLayoutWorkLimits {
        nodes: 256, edges: 256, groups: 128, payload_roots: 256, visits: 4096,
    }
}

fn native_layout_source(packet: &GpuPacket, reference: [u32; 2])
    -> super::super::native_layout_work::NativeLayoutSource
{
    super::super::native_layout_work::NativeLayoutSource {
        epoch: packet.packet.catalog.epoch,
        arena_id: packet.arena_id.expect("admitted proof arena"),
        serial: packet.completed_serial,
        reference,
    }
}

// Read the exact accepted conclusion for each original occurrence. These rows
// were produced by the solver; the helper does not match or select a proof.
fn native_layout_goal_sources(
    gpu: &GpuProgramEvidence,
    packet: &GpuPacket,
    facts: &OriginalUnitFacts,
) -> Vec<([u32; 2], CheckedGenericType)> {
    let snapshot = packet.packet.catalog.snapshot_by_unit[
        &[facts.interface().library_id, facts.interface().unit_id]];
    let mut calls = facts.generic_calls().iter()
        .filter(|call| call.has_closed_arguments()).collect::<Vec<_>>();
    calls.sort_by_key(|call| call.source_span);
    let mut regions = Vec::new();
    for call in &calls {
        assert_eq!(call.arguments.len(), 1);
        let occurrence = original_call_row(&packet.packet, snapshot, call.call_hir);
        let call_row = packet.packet.tables.row(15, occurrence).unwrap();
        assert_eq!(call_row[6], 1, "one marker obligation per source occurrence");
        let evidence = packet.packet.tables.words[17].chunks_exact(8)
            .filter(|row| row[0] == 1 && row[5] == occurrence && row[6] == call_row[5])
            .collect::<Vec<_>>();
        assert_eq!(evidence.len(), 1, "one accepted proof for this occurrence");
        let goal = evidence[0][4];
        assert!(goal < packet.packet.proof_store.accepted_prefix()[3]);
        let offset = packet.packet.proof_store.layout().slices[3].offset + goal * 8;
        regions.push(ReadbackRegion::from_buffer(
            &packet.proof.buffer, u64::from(offset) * 4, 32, "native test accepted goal",
        ).unwrap());
    }
    let rows = gpu.readback.read_regions(
        &gpu.device, &gpu.queue, &regions, "native test accepted goal subjects",
    ).unwrap();
    rows.iter().zip(calls).map(|(raw, call)| {
        let row = words(raw).unwrap();
        assert_eq!(row.len(), 8);
        assert_eq!(row[6], 1, "accepted conclusion is closed");
        ([row[1], row[2]], call.arguments[0].ty.clone())
    }).collect()
}

// Compare the complete semantic graph, preserving nominal ownership, ordered
// operands, array lengths and scalar identities. Layout availability and replay
// coordinates may differ across independently owned artifacts.
fn native_layout_semantic_shape(mut ty: CheckedGenericType) -> CheckedGenericType {
    fn clear(ty: &mut CheckedGenericType) {
        use crate::type_checker::CheckedGenericApplicationArgument;
        match ty {
            CheckedGenericType::Nominal { arguments, words, local_replay, .. } => {
                *words = None;
                *local_replay = None;
                for argument in arguments {
                    if let CheckedGenericApplicationArgument::Type(child) = argument { clear(child); }
                }
            }
            CheckedGenericType::Array { element, words, .. } => { *words = None; clear(element); }
            CheckedGenericType::Reference(child) | CheckedGenericType::Slice(child) => clear(child),
            _ => {}
        }
    }
    clear(&mut ty);
    ty
}

#[test]
fn gpu_native_layout_materializes_nested_compositions_and_terminal_descriptors() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let facts = compile_native_layout_facts(&compiler, [120, 0], r#"
module batch_cases::native_layout;
pub trait Mark {}
pub impl<T> Mark for T {}
pub struct Cell<T> { value: T }
enum Packet<T> { Value(T), Wide([str; 2]), Empty }
struct Holder<T> { value: T, sentinel: i32 }
enum Void {}
pub fn inspect<T>() -> i32 where T: Mark { return 0; }
fn main() -> i32 {
    let array = inspect<[i32; 3]>();
    let record = inspect<Cell<[i32; 3]>>();
    let variant = inspect<Packet<Cell<[i32; 3]>>>();
    let nested = inspect<Holder<Packet<Cell<[i32; 3]>>>>();
    let repeated = inspect<[Cell<[i32; 3]>; 2]>();
    let empty = inspect<Cell<[i32; 0]>>();
    let reference = inspect<&Void>();
    let slice = inspect<[Void]>();
    return array + record + variant + nested + repeated + empty + reference + slice;
}
"#);
    let (mut gpu, mut packet) = native_layout_batch_job(&compiler, &facts);
    gpu.check(&mut packet).expect("GPU accepts every concrete marker goal");
    let expected = native_layout_goal_sources(&gpu, &packet, &facts);
    assert_eq!(expected.len(), 8);
    let sources = expected.iter().map(|(source, _)| *source).collect::<Vec<_>>();
    let values = gpu.materialize_proof_terms(&packet, &sources, native_layout_test_limits())
        .expect("GPU expands owned recipes and completes native layouts");
    assert_eq!(gpu.layout_query_slots.len(), 8, "one reserved role per concurrent root");
    let query_allocation_ids = |gpu: &GpuProgramEvidence| gpu.layout_query_slots.iter()
        .map(|slot| slot.buffer(1, wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC
            | wgpu::BufferUsages::COPY_DST, None).unwrap().allocation_id())
        .collect::<Vec<_>>();
    let allocations = query_allocation_ids(&gpu);
    assert_eq!(allocations.iter().copied().collect::<std::collections::BTreeSet<_>>().len(), 8,
        "simultaneously materialized roots must have distinct physical buffers");
    assert_eq!(values.len(), expected.len());
    for ((value, (reference, expected)), width) in values.iter().zip(&expected)
        .zip([3, 3, 5, 6, 6, 0, 1, 3])
    {
        assert_eq!(value.words(), width, "layout of {expected:?}");
        let actual = value.type_for(&packet.packet.catalog, native_layout_source(&packet, *reference))
            .expect("exact source provenance owns the decoded result");
        assert_eq!(native_layout_semantic_shape(actual.clone()),
            native_layout_semantic_shape(expected.clone()));
    }
    // The first job already checks that reading its completed array root does
    // not multiply by the length again. Repeat in a fresh job for isolation.
    let again = gpu.materialize_proof_terms(&packet, &sources[..1], native_layout_test_limits())
        .expect("a fresh layout job for the same accepted array");
    assert_eq!(again[0].words(), 3);
    assert_eq!(gpu.layout_query_slots.len(), 8, "a sequential query must not reserve another role");
    assert_eq!(query_allocation_ids(&gpu), allocations,
        "completed query scratch reuses the same physical allocations");
    let oversized = vec![sources[0]; 65];
    assert!(gpu.materialize_proof_terms(&packet, &oversized, native_layout_test_limits()).is_err());
    assert_eq!(query_allocation_ids(&gpu), allocations,
        "over-capacity rejection happens before any scratch allocation");
    assert_eq!(values[0].words(), 3, "later jobs preserve the earlier owned result");
    // LANIUS_DEBUG_CAPTURE_PASS only: save the selected materialization dispatch.
    crate::compiler::write_debug_dispatch_capture();
}

#[test]
fn gpu_native_layout_binds_gapped_parameter_identities_in_declared_operand_order() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let facts = compile_native_layout_facts(&compiler, [121, 0], r#"
module batch_cases::gapped_native_layout;
pub trait Mark {}
pub impl<T> Mark for T {}
pub struct Gap<T, const N: usize> { values: [T; N] }
pub fn inspect<T>() -> i32 where T: Mark { return 0; }
fn main() -> i32 { return inspect<Gap<i32, 3>>(); }
"#);
    let mut catalog = FrozenCatalog::freeze(&[CatalogInput { facts: &facts }]).unwrap();
    let image = Arc::get_mut(&mut catalog).unwrap();
    assert_eq!(image.native_layout.recipes.count, 1);
    let recipe = image.native_layout.recipes.offset as usize;
    let owner = image.native_layout.words[recipe + 1];
    let parameters = image.tables.words[3].chunks_exact(4)
        .filter(|row| row[0] == owner).map(|row| row[1]).collect::<Vec<_>>();
    assert_eq!(parameters.len(), 2);
    for (&atom, ordinal) in parameters.iter().zip([9, 17]) {
        let key = image.tables.row_mut(1, atom).unwrap();
        assert_eq!(key[0], 5);
        key[3] = ordinal;
        let word = image.slices[1].offset as usize + atom as usize * 8 + 3;
        Arc::make_mut(&mut image.words)[word] = ordinal;
        image.atoms.keys[atom as usize][3] = ordinal;
    }
    // Keep the host's descriptive atom map coherent with this unpublished
    // wire fixture. Accepted GPU owner order, not source ordinal, binds operands.
    let mut atoms = super::super::catalog::Atoms::default();
    for (index, key) in image.atoms.keys.iter().copied().enumerate() {
        assert_eq!(atoms.intern(key).unwrap(), index as u32);
    }
    image.atoms = atoms;
    let mut gpu = GpuProgramEvidence::admit(
        compiler.program_evidence_workspace.checkout(), catalog,
    ).expect("gapped exact source ordinals are valid catalog identities");
    let mut packet = gpu.new_packet().unwrap();
    append_originals(&mut packet);
    gpu.check(&mut packet).expect("closed Gap<i32,3> marker proof");
    let expected = native_layout_goal_sources(&gpu, &packet, &facts);
    assert_eq!(expected.len(), 1);
    let values = gpu.materialize_proof_terms(&packet, &[expected[0].0], native_layout_test_limits())
        .expect("source ordinals are identities, not operand indexes");
    assert_eq!(values[0].words(), 3);
    let actual = values[0].type_for(&packet.packet.catalog,
        native_layout_source(&packet, expected[0].0)).unwrap();
    assert_eq!(native_layout_semantic_shape(actual.clone()),
        native_layout_semantic_shape(expected[0].1.clone()));
    // LANIUS_DEBUG_CAPTURE_PASS only: save the selected materialization dispatch.
    crate::compiler::write_debug_dispatch_capture();
}

#[test]
fn gpu_native_layout_rejects_capacity_and_foreign_lexical_bindings_then_recovers() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let facts = compile_native_layout_facts(&compiler, [122, 0], r#"
module batch_cases::native_layout_failure;
pub trait Mark {}
pub impl<T> Mark for T {}
pub struct Cell<T> { value: T }
struct Other<U> { value: U }
pub fn inspect<T>() -> i32 where T: Mark { return 0; }
fn main() -> i32 { return inspect<Cell<[i32; 3]>>(); }
"#);
    let (mut gpu, mut packet) = native_layout_batch_job(&compiler, &facts);
    gpu.check(&mut packet).expect("accepted marker proof before layout jobs");
    let expected = native_layout_goal_sources(&gpu, &packet, &facts);
    assert_eq!(expected.len(), 1);
    let reference = expected[0].0;
    let provenance = native_layout_source(&packet, reference);
    let limited = super::super::native_layout_work::NativeLayoutWorkLimits {
        nodes: 0, ..native_layout_test_limits()
    };
    let error = gpu.materialize_proof_terms(&packet, &[reference], limited)
        .err().expect("nonempty semantic graph cannot fit zero node capacity");
    let failure = error.downcast_ref::<NativeLayoutFailure>()
        .unwrap_or_else(|| panic!("expected GPU capacity receipt: {error:#}"));
    assert_eq!(failure.source, provenance);
    assert_eq!(&failure.status[..3], &[3, 172, 0]);
    assert!(failure.status[4] > failure.status[5]);
    let valid = gpu.materialize_proof_terms(&packet, &[reference], native_layout_test_limits())
        .expect("capacity failure does not poison accepted proof storage");
    assert_eq!(valid[0].words(), 3);

    let catalog = &packet.packet.catalog;
    let sidecar = &catalog.native_layout;
    let recipes = (0..sidecar.recipes.count).map(|row| {
        let start = (sidecar.recipes.offset + row * sidecar.recipes.width) as usize;
        <[u32; 8]>::try_from(&sidecar.words[start..start + 8]).unwrap()
    }).collect::<Vec<_>>();
    let own = recipes.iter().find(|row| catalog.tables.row(1, row[0]).unwrap()[0] == 1).unwrap();
    let foreign = recipes.iter().find(|row| catalog.tables.row(1, row[0]).unwrap()[0] == 2).unwrap();
    let group = (sidecar.groups.offset + own[3] * sidecar.groups.width) as usize;
    assert_eq!(sidecar.words[group + 2], 1);
    let root = sidecar.words[group + 1];
    let own_reference = catalog.tables.row(7, root).unwrap();
    assert_eq!(own_reference[0], 2);
    let original_parameter = own_reference[1];
    let foreign_parameter = catalog.tables.words[3].chunks_exact(4)
        .find(|row| row[0] == foreign[1] && row[2] == 0 && row[3] == 0).unwrap()[1];
    assert_ne!(original_parameter, foreign_parameter);
    let own_key = catalog.tables.row(1, original_parameter).unwrap();
    let foreign_key = catalog.tables.row(1, foreign_parameter).unwrap();
    assert_eq!(&own_key[2..4], &foreign_key[2..4], "same domain and source ordinal");
    assert_ne!(own_key[1], foreign_key[1], "different lexical binders");
    let root_payload_word = catalog.slices[7].offset + root * 2 + 1;
    let write_payload = |value| {
        let mut encoder = gpu.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("native layout test recipe fault"),
        });
        gpu.storage.upload( &mut encoder, &[ArenaWrite {
            first_word: root_payload_word, words: vec![value],
        }]).unwrap();
        gpu.queue.submit(Some(encoder.finish()));
    };
    // Recipe admission already rejects this corruption. Inject after admission
    // solely to exercise the materializer's exact-identity substitution guard.
    write_payload(foreign_parameter);
    let error = gpu.materialize_proof_terms(&packet, &[reference], native_layout_test_limits())
        .err().expect("a sibling owner's parameter must not capture this operand");
    let failure = error.downcast_ref::<NativeLayoutFailure>()
        .unwrap_or_else(|| panic!("expected GPU lexical binding receipt: {error:#}"));
    assert_eq!(failure.source, provenance);
    assert_eq!(&failure.status[..2], &[2, 9]);
    let mut encoder = gpu.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("native layout test restore recipe"),
    });
    gpu.storage.upload( &mut encoder, &[ArenaWrite {
        first_word: root_payload_word, words: vec![original_parameter],
    }]).unwrap();
    gpu.queue.submit(Some(encoder.finish()));
    let recovered = gpu.materialize_proof_terms(&packet, &[reference], native_layout_test_limits())
        .expect("fresh work after restoring the admitted recipe");
    assert_eq!(recovered[0].words(), 3);
    assert_eq!(valid[0].words(), 3);
    assert_eq!(native_layout_source(&packet, reference), provenance);
    assert!(!packet.poisoned);
    // LANIUS_DEBUG_CAPTURE_PASS only: save the selected materialization dispatch.
    crate::compiler::write_debug_dispatch_capture();
}

#[test]
fn gpu_evidence_workspace_alternates_catalogs_rejects_stale_capabilities_and_recovers() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let rich = compile_unit(&compiler, [96, 0], FORWARDING, vec![]);
    let plain = compile_unit(&compiler, [97, 0], "fn main()->i32 { return 0; }", vec![]);
    let (_, relay_hir, concrete) = forwarding_calls(&rich);
    let call = &concrete[0];
    let (mut gpu, mut packet) = batch_job(&compiler, &[&rich]);
    let accepted = gpu.check(&mut packet).expect("first rich program");
    let snapshot = packet.packet.catalog.snapshot_by_unit[&[96, 0]];
    let origin = original_call_row(&packet.packet, snapshot, call.call_hir);
    let stale = call_evidence(&packet.packet, origin, &accepted);
    let storage_id = gpu.storage.buffer.allocation_id();
    let retained_catalog = gpu.catalog.clone();
    drop((gpu, packet));

    let (mut gpu, mut packet) = batch_job(&compiler, &[&plain]);
    assert_eq!(gpu.storage.buffer.allocation_id(), storage_id,
        "smaller catalog should reuse physical capacity");
    assert!(gpu.check(&mut packet).unwrap().is_empty());
    drop((gpu, packet));

    let facts = rich.original_facts().unwrap();
    let mut malformed = FrozenCatalog::freeze(&[CatalogInput { facts: &facts }]).unwrap();
    // Corrupt only the unpublished recipe header. This must fail GPU admission,
    // even though the reused storage previously held a successful receipt.
    Arc::make_mut(&mut Arc::get_mut(&mut malformed).unwrap().native_layout.words)[0] = 0;
    let failed = GpuProgramEvidence::admit(compiler.program_evidence_workspace.checkout(), malformed);
    match failed {
        Ok(_) => panic!("invalid native recipe header reused an old successful admission"),
        Err(error) => assert!(error.to_string().contains("native recipe GPU admission failed"), "{error:#}"),
    }

    // Reuse the exact immutable catalog object as well as its physical storage.
    // A different packet arena still must reject the old capability.
    let mut gpu = GpuProgramEvidence::admit(compiler.program_evidence_workspace.checkout(), retained_catalog)
        .expect("fresh catalog admission after failure");
    let mut packet = gpu.new_packet().unwrap();
    append_originals(&mut packet);
    assert_eq!(gpu.storage.buffer.allocation_id(), storage_id);
    gpu.check(&mut packet).expect("fresh success after failed admission");
    let snapshot = packet.packet.catalog.snapshot_by_unit[&[96, 0]];
    let origin = original_call_row(&packet.packet, snapshot, call.call_hir);
    let error = packet.packet_mut().unwrap().replay_context(ReplayContextInput {
        snapshot, selected_owner_hir: relay_hir, evidence: &[stale], origin_call: origin,
    }).expect_err("same physical storage cannot revive a prior program's capability");
    assert!(error.to_string().contains("different catalog or row arena"), "{error:#}");
    drop((gpu, packet));

    for iteration in 0..3 {
        let before = passes_core::this_thread_gpu_activity();
        let (mut gpu, mut packet) = batch_job(&compiler, &[&rich]);
        gpu.check(&mut packet).expect("valid program after stale-capability rejection");
        if iteration == 2 {
            let activity = passes_core::this_thread_gpu_activity().since(before);
            assert_eq!(activity.buffers_created, 0,
                "warm evidence admission must reuse buffers");
            assert_eq!(activity.bind_groups, 0,
                "warm evidence admission must reuse reflected bindings");
        }
    }

    pollster::block_on(compiler.release_resident_job_buffers());
    let (mut gpu, mut packet) = batch_job(&compiler, &[&rich]);
    assert_ne!(gpu.storage.buffer.allocation_id(), storage_id, "idle trim drops retained evidence capacity");
    gpu.check(&mut packet).expect("fresh admission after compiler trim");
}

// Two calls with the same unprovable bound, in two functions (two contexts).
const SOFT_PAIR: &str = r#"
import core::contracts;
fn helper()->i32 {
    if(core::contracts::keep(false,[19,23,24])) { return 1; }
    return 0;
}
fn main()->i32 {
    if(core::contracts::keep(false,[19,23,24])) { return 1; }
    return helper();
}
"#;

/// Every call row of the packet, in row order, with its context row.
fn call_contexts(packet: &ProgramPacket) -> Vec<(u32, u32)> {
    (0..packet.tables.count(15).unwrap())
        .map(|call| (call, packet.tables.row(15, call).unwrap()[0]))
        .collect()
}

fn context_snapshot(packet: &ProgramPacket, context: u32) -> u32 {
    packet.tables.row(13, context).unwrap()[0]
}

#[test]
fn gpu_batch_soft_context_admits_a_bound_that_holds() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let provider = compile_unit(&compiler, [85, 0], PROVIDER, vec![]);
    let caller = compile_unit(&compiler, [86, 0], CALLER, vec![vec![provider.interface.clone()]]);
    let (mut gpu, mut packet) = batch_job(&compiler, &[&provider, &caller]);
    let calls = call_contexts(&packet.packet);
    assert_eq!(calls.len(), 1, "one generic call");
    let (_, context) = calls[0];
    packet.packet_mut().unwrap().mark_context_soft(context).unwrap();
    let result = gpu.check(&mut packet).expect("a soft context whose bound holds is admitted");
    assert_eq!(result.len(), 1);
    assert!(result[0].is_concrete() && !result[0].is_refuted(), "the bound is proven");
    let snapshot = context_snapshot(&packet.packet, context);
    let admitted = packet.packet_mut().unwrap().admitted_unit_calls(snapshot, None).unwrap();
    assert_eq!(admitted.len(), 1);
    assert!(admitted[0].is_concrete() && !admitted[0].is_refuted(), "the call is admitted concrete");
}

#[test]
fn gpu_batch_soft_refutation_demotes_only_its_context_and_never_a_hard_failure() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let provider = compile_unit(&compiler, [87, 0], PROVIDER, vec![]);
    let caller = compile_unit(&compiler, [88, 0], SOFT_PAIR, vec![vec![provider.interface.clone()]]);

    // Both contexts soft: both calls are refuted, and the batch stays valid.
    let (mut gpu, mut packet) = batch_job(&compiler, &[&provider, &caller]);
    let calls = call_contexts(&packet.packet);
    assert_eq!(calls.len(), 2, "two generic calls");
    assert_ne!(calls[0].1, calls[1].1, "one context per function");
    for &(_, context) in &calls {
        packet.packet_mut().unwrap().mark_context_soft(context).unwrap();
    }
    let result = gpu.check(&mut packet).expect("soft refutations keep the batch valid");
    assert_eq!(result.len(), 2, "the evidence suffix covers every obligation");
    assert!(result.iter().all(|evidence| evidence.is_refuted() && !evidence.is_concrete()));
    let snapshot = context_snapshot(&packet.packet, calls[0].1);
    let admitted = packet.packet_mut().unwrap().admitted_unit_calls(snapshot, None).unwrap();
    assert_eq!(admitted.len(), 2);
    assert!(admitted.iter().all(|call| call.is_refuted() && !call.is_concrete()),
        "a refuted call is never admitted concrete");

    // Without soft contexts the batch fails as before.
    let (mut gpu, mut packet) = batch_job(&compiler, &[&provider, &caller]);
    let error = gpu.check(&mut packet).expect_err("hard contexts fail on the missing implementation");
    let failure = gpu_failure(&error);
    assert_eq!(failure.receipt[0], 6, "batch obligation failure");
    assert_eq!(failure.obligation.expect("failed obligation").1[0], 3);

    // One soft, one hard: the hard call alone fails the batch, with its own
    // obligation failure; the soft refutation is not reported.
    for soft in 0..2 {
        let (mut gpu, mut packet) = batch_job(&compiler, &[&provider, &caller]);
        let calls = call_contexts(&packet.packet);
        packet.packet_mut().unwrap().mark_context_soft(calls[soft].1).unwrap();
        let error = gpu.check(&mut packet).expect_err("the hard context still fails");
        let failure = gpu_failure(&error);
        assert_eq!(failure.catalog[0], 1, "accepted catalog");
        assert_eq!(failure.receipt[0], 6, "batch obligation failure");
        let (call, status) = failure.call.expect("failed call");
        assert_eq!(call, calls[1 - soft].0, "the report names the hard call");
        assert_eq!(status[0], 3, "MISSING_IMPLEMENTATION on the hard call");
        let (obligation, status) = failure.obligation.expect("failed obligation");
        assert_eq!(packet.packet().tables.row(16, obligation).unwrap()[0], calls[1 - soft].0,
            "the reported obligation belongs to the hard call");
        assert_eq!(status[0], 3);
    }
}

#[test]
fn gpu_batch_rejects_a_soft_marker_other_than_one() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let provider = compile_unit(&compiler, [89, 0], PROVIDER, vec![]);
    let caller = compile_unit(&compiler, [90, 0], CALLER, vec![vec![provider.interface.clone()]]);
    let (mut gpu, mut packet) = batch_job(&compiler, &[&provider, &caller]);
    let (_, context) = call_contexts(&packet.packet)[0];
    packet.packet_mut().unwrap().tables.row_mut(13, context).unwrap()[7] = 2;
    let error = gpu.check(&mut packet).expect_err("context word 7 is 0 or 1");
    let failure = gpu_failure(&error);
    assert_eq!(failure.receipt[0], 2, "invalid input");
    assert_eq!(failure.receipt[1], 21, "the context-marker detail");
}

/// `count` checked calls, each at its own marked struct: one distinct root
/// goal per call, so the proof tables grow with `count`.
fn distinct_marks(count: usize) -> String {
    let mut decls = String::new();
    let mut body = String::new();
    for k in 1..=count {
        decls.push_str(&format!("pub struct S{k} {{ v: i32 }}\npub impl Mark for S{k} {{}}\n"));
        body.push_str(&format!("    total = total + check<S{k}>();\n"));
    }
    format!(
        "module batch_cases::marked;\npub trait Mark {{}}\n{decls}\
         pub fn check<T>()->i32 where T:Mark {{ return 1; }}\n\
         fn main()->i32 {{\n    let total: i32 = 0;\n{body}    return total - {count};\n}}\n"
    )
}

#[test]
fn gpu_proof_store_floor_is_only_a_hint_bigger_jobs_still_grow_and_trim_clears_it() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let small = compile_unit(&compiler, [98, 0], FORWARDING, vec![]);
    let wide = compile_unit(&compiler, [99, 0], &distinct_marks(200), vec![]);
    let floor = || compiler.program_evidence_workspace.checkout().proof_capacity_floor();
    let solve = |unit: &CompiledSourcePackUnit| {
        let before = proof_store_growths();
        let (mut gpu, mut packet) = batch_job(&compiler, &[unit]);
        let outcome = gpu.check(&mut packet).expect("valid program").iter()
            .map(|evidence| (evidence.is_concrete(), evidence.is_refuted()))
            .collect::<Vec<_>>();
        drop((gpu, packet));
        let growths = proof_store_growths() - before;
        (outcome, growths)
    };

    pollster::block_on(compiler.release_resident_job_buffers());
    assert_eq!(floor(), [0; PROOF_STORE_TABLES], "a trimmed pool has no floor");
    solve(&small);
    let small_floor = floor();
    assert!(small_floor.iter().all(|&rows| rows >= 64), "a solve leaves its capacities: {small_floor:?}");

    // The small job's floor does not fit the wide job: its solve still grows
    // the store, and it proves every call.
    let (floored, growths) = solve(&wide);
    assert!(growths > 0, "the wide job outgrows the small job's floor");
    assert!(floored.len() >= 200 && floored.iter().all(|&(concrete, refuted)| concrete && !refuted),
        "{floored:?}");
    let wide_floor = floor();
    assert!(wide_floor.iter().zip(&small_floor).all(|(wide, small)| wide >= small)
        && wide_floor != small_floor, "{small_floor:?} -> {wide_floor:?}");

    // Warm, the floor covers the wide job: no growth, the same evidence.
    let (warm, growths) = solve(&wide);
    assert_eq!(growths, 0, "the floor sizes a repeated job's first attempt");
    assert_eq!(warm, floored);

    // A trim clears the floor; the same job grows again and agrees.
    pollster::block_on(compiler.release_resident_job_buffers());
    assert_eq!(floor(), [0; PROOF_STORE_TABLES], "a trim clears the floor");
    let (fresh, growths) = solve(&wide);
    assert!(growths > 0, "without a floor the wide job grows from the seed");
    assert_eq!(fresh, floored);
}
