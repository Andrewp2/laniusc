//! Storage and authority tests over retained record fixtures. Success-dependent
//! cases use real GPU catalog, batch and proof admission. Pure host cases check
//! input rejection, storage plans and diagnostic mapping; no host solver runs.

use super::super::dispatch::{GpuPacket, GpuProgramEvidence};
use super::{super::super::typecheck::CompiledSourcePackObject, *};
use crate::{
    codegen::x86::{GPU_X86_OBJECT_VERSION, GpuX86RelocatableObject},
    compiler::{GPU_SEMANTIC_INTERFACE_VERSION, GpuSemanticInterfaceArtifact},
    type_checker::{
        CheckedBinderIdentity, CheckedCallOwner, CheckedCallableOwner, CheckedContractOwner,
        CheckedGenericArgument, CheckedGenericConstant, CheckedGenericConstantValue,
        CheckedGenericParameter, CheckedGenericType, CheckedImplementationContract,
        CheckedNominalIdentity, CheckedParameterDomain, CheckedParameterIdentity,
        CheckedPredicateContract, CheckedUnitContracts,
    },
};
use std::ops::{Deref, DerefMut};

const UNIT: [u32; 2] = [7, 11];
const CALLER: u32 = 100;
const CALLEE: u32 = 200;
const UNUSED_BODY: u32 = 300;

fn empty_unit(key: [u32; 2]) -> CompiledSourcePackUnit {
    CompiledSourcePackUnit {
        body_native_layouts: None,
        owner_spans: None,
        instance_closure: None,
        interface: GpuSemanticInterfaceArtifact {
            version: GPU_SEMANTIC_INTERFACE_VERSION,
            library_id: key[0],
            unit_id: key[1],
            modules: vec![],
            module_segments: vec![],
            declarations: vec![],
            types: vec![],
            type_edges: vec![],
            members: vec![],
            predicates: vec![],
            predicate_arguments: vec![],
            implementations: vec![],
            implementation_arguments: vec![],
            implementation_method_bindings: vec![],
            name_bytes: vec![],
            closure_summary: None,
        },
        object: CompiledSourcePackObject::X86_64(GpuX86RelocatableObject {
            version: GPU_X86_OBJECT_VERSION,
            library_id: key[0],
            unit_id: key[1],
            entry_offset: None,
            text: vec![],
            rodata: vec![],
            relocations: vec![],
            symbols: vec![],
            identity_bytes: vec![],
        }),
        generic_calls: Vec::new().into(),
        checked_contracts: Arc::new(CheckedUnitContracts {
            source_unit: Some(key),
            ..Default::default()
        }),
        checked_call_owners: Vec::new().into(),
        native_call_hirs: Vec::new().into(),
        native_call_function_hirs: Vec::new().into(),
        // Opaque immutable provenance. These tests build checked records
        // directly; the text is never parsed to manufacture semantic facts.
        template_sources: vec!["module packet_fixture;".to_owned()].into(),
        template_source_paths: vec![None].into(),
        template_dependency_pages: vec![vec![]].into(),
    }
}

fn owner(hir: u32, token: u32, callable: bool) -> CheckedContractOwner {
    CheckedContractOwner {
        source_hir: hir,
        binder: CheckedBinderIdentity::SourceLocal {
            owner_kind: if callable { 3 } else { 35 },
            declaration_start_token: token,
        },
        callable: callable.then_some(CheckedCallableOwner {
            native_symbol: 0x4000_0000 | token,
        }),
        enclosing_owner: None,
        parameters: vec![],
    }
}

/// A private caller invokes one private generic definition with T=i32,
/// U=[i32;3], N=7. Only T has a marker predicate. U and N deliberately remain
/// unconstrained, so proof rows cannot serve as their replay authority.
fn bound_unit() -> CompiledSourcePackUnit {
    let mut unit = empty_unit(UNIT);
    let mut generic = owner(CALLEE, 20, true);
    generic.parameters = [
        (CheckedParameterDomain::Type, 0),
        (CheckedParameterDomain::Type, 1),
        (CheckedParameterDomain::Constant, 0),
    ]
    .into_iter()
    .enumerate()
    .map(
        |(ordinal, (domain, binding_slot))| CheckedGenericParameter {
            identity: CheckedParameterIdentity {
                unit: UNIT,
                binder: generic.binder,
                domain,
                source_ordinal: ordinal as u32,
            },
            binding_slot,
            constant_scalar: (domain == CheckedParameterDomain::Constant)
                .then_some(crate::primitive_types::SCALAR_U32),
        },
    )
    .collect();
    let subject = generic.parameters[0];
    let trait_identity = CheckedNominalIdentity::SourceLocal {
        unit: UNIT,
        declaration_token: 50,
    };
    unit.checked_contracts = Arc::new(CheckedUnitContracts {
        source_unit: Some(UNIT),
        binders: vec![
            owner(CALLER, 10, true),
            generic,
            owner(UNUSED_BODY, 30, true),
            owner(400, 40, false),
        ],
        predicates: vec![CheckedPredicateContract {
            source_row: 0,
            bound_hir: 210,
            owner: 1,
            public_index: None,
            trait_identity,
            subject: CheckedGenericType::Parameter(subject),
            arguments: vec![],
        }],
        implementations: vec![CheckedImplementationContract {
            source_row: 1,
            owner: 3,
            public_index: None,
            trait_identity,
            subject: CheckedGenericType::Scalar(3),
            arguments: vec![],
            method_bindings: vec![],
        }],
        nominal_recipes: vec![],
    });
    unit.generic_calls = vec![CheckedGenericCall {
        call_hir: 500,
        source_span: [0, 1],
        target: CheckedGenericTarget::Local {
            function_start_token: 20,
            generic_parameter_count: 2,
            native_symbol: 0x4000_0014,
            specialization_symbol: 20,
        },
        arguments: vec![
            CheckedGenericArgument {
                slot: 0,
                ty: CheckedGenericType::Scalar(3),
            },
            CheckedGenericArgument {
                slot: 1,
                ty: CheckedGenericType::Array {
                    element: Box::new(CheckedGenericType::Scalar(3)),
                    length: CheckedGenericConstantValue::count_literal(3),
                    words: Some(3),
                },
            },
        ],
        constants: vec![CheckedGenericConstant::literal(0, 7)],
        required_constant_parameters: Some(1),
        required_generic_parameters: Some(2),
    }]
    .into();
    unit.checked_call_owners = vec![CheckedCallOwner {
        call_hir: 500,
        function_hir: CALLER,
    }]
    .into();
    unit
}

fn freeze(units: &[&CompiledSourcePackUnit]) -> Arc<FrozenCatalog> {
    let facts = units
        .iter()
        .map(|unit| unit.original_facts().unwrap())
        .collect::<Vec<_>>();
    let inputs = facts
        .iter()
        .map(|facts| CatalogInput { facts })
        .collect::<Vec<_>>();
    FrozenCatalog::freeze(&inputs).unwrap()
}

fn new_packet(catalog: Arc<FrozenCatalog>, units: &[&CompiledSourcePackUnit]) -> ProgramPacket {
    let mut packet = ProgramPacket::new(catalog).unwrap();
    for unit in units {
        let key = [unit.interface.library_id, unit.interface.unit_id];
        let snapshot = packet.catalog.snapshot_by_unit[&key];
        let facts = packet.catalog.snapshots[snapshot as usize]
            .original_facts
            .clone();
        packet.append_original_unit_calls(&facts).unwrap();
    }
    packet
}

fn rejected<T>(result: Result<T>, expected: &str) {
    match result {
        Ok(_) => panic!("operation unexpectedly admitted: {expected}"),
        Err(error) => assert!(error.to_string().contains(expected), "{error}"),
    }
}

/// Own the physical arenas alongside the packet. Read-only access is descriptive;
/// only the real dispatcher's complete GPU readback can authorize success.
struct GpuFixture {
    dispatcher: GpuProgramEvidence,
    packet: GpuPacket,
}
impl Deref for GpuFixture {
    type Target = ProgramPacket;
    fn deref(&self) -> &Self::Target {
        self.packet.packet()
    }
}
impl DerefMut for GpuFixture {
    fn deref_mut(&mut self) -> &mut Self::Target {
        self.packet
            .packet_mut()
            .expect("fixture GPU packet is usable")
    }
}
fn new_gpu_packet(catalog: Arc<FrozenCatalog>, units: &[&CompiledSourcePackUnit]) -> GpuFixture {
    let compiler = pollster::block_on(crate::compiler::GpuCompiler::new()).expect("GPU compiler");
    let dispatcher = GpuProgramEvidence::admit(
        compiler.program_evidence_workspace.checkout(),
        catalog.clone(),
    )
    .expect("GPU admits fixture definition graphs");
    let mut packet = dispatcher.new_packet().expect("physical packet arenas");
    for unit in units {
        let key = [unit.interface.library_id, unit.interface.unit_id];
        let snapshot = catalog.snapshot_by_unit[&key];
        packet
            .packet_mut()
            .unwrap()
            .append_original_unit_calls(&catalog.snapshots[snapshot as usize].original_facts)
            .unwrap();
    }
    GpuFixture { dispatcher, packet }
}
fn admitted(fixture: &mut GpuFixture) -> Vec<ValidatedEvidence> {
    fixture
        .dispatcher
        .check(&mut fixture.packet)
        .expect("GPU admits complete fixture batch")
}

fn replay(packet: &mut ProgramPacket, evidence: &[ValidatedEvidence]) -> u32 {
    packet
        .replay_context(ReplayContextInput {
            snapshot: packet.catalog.snapshot_by_unit[&UNIT],
            selected_owner_hir: CALLEE,
            evidence,
            origin_call: 0,
        })
        .unwrap()
}

#[test]
fn every_original_unit_and_source_occurrence_is_required() {
    let unit = bound_unit();
    let empty = empty_unit([7, 12]);
    let catalog = freeze(&[&unit, &empty]);
    for omitted_empty in [true, false] {
        let included = if omitted_empty { &unit } else { &empty };
        let mut packet = new_packet(catalog.clone(), &[included]);
        rejected(packet.prepare_submission(), "missing an original unit");
    }
    for omit_call_too in [true, false] {
        let mut truncated = unit.clone();
        truncated.checked_call_owners = Vec::new().into();
        if omit_call_too {
            truncated.generic_calls = Vec::new().into();
        }
        let truncated_facts = truncated.original_facts().unwrap();
        if !omit_call_too {
            rejected(
                FrozenCatalog::freeze(&[CatalogInput {
                    facts: &truncated_facts,
                }]),
                "not bijective",
            );
        }
        let mut packet = ProgramPacket::new(catalog.clone()).unwrap();
        rejected(
            packet.append_original_unit_calls(&truncated_facts),
            "not the frozen immutable source snapshot",
        );
    }
    let mut complete = new_packet(catalog, &[&unit, &empty]);
    assert_eq!(complete.prepare_submission().unwrap().call_span.count, 1);
}

#[test]
fn replay_routing_and_provenance_are_checked_before_call_iteration() {
    let unit = bound_unit();
    let catalog = freeze(&[&unit]);
    let mut packet = new_gpu_packet(catalog.clone(), &[&unit]);
    let evidence = admitted(&mut packet);
    let context = replay(&mut packet, &evidence);
    // UNUSED_BODY is real and callable but has no calls. The old routing-only
    // check never visited it and incorrectly reused the admitted sibling call.
    rejected(
        packet.append_replay_unit_calls(&unit, UNUSED_BODY, context),
        "does not own the selected lexical body",
    );
    for changed_provenance in 0..3 {
        let mut packet = new_gpu_packet(catalog.clone(), &[&unit]);
        let evidence = admitted(&mut packet);
        let context = replay(&mut packet, &evidence);
        let mut foreign = unit.clone();
        match changed_provenance {
            0 => foreign.template_sources = unit.template_sources.to_vec().into(),
            1 => foreign.template_dependency_pages = unit.template_dependency_pages.to_vec().into(),
            _ => foreign.checked_contracts = Arc::new((*unit.checked_contracts).clone()),
        }
        rejected(
            packet.append_replay_unit_calls(&foreign, CALLEE, context),
            "frozen definition provenance",
        );
    }
    let empty = empty_unit([7, 12]);
    let mut packet = new_packet(freeze(&[&empty]), &[&empty]);
    rejected(
        packet.append_replay_unit_calls(&empty, CALLEE, 0),
        "was not retained",
    );
}

#[test]
fn replay_inherits_every_origin_binding_and_reuses_only_admitted_siblings() {
    let unit = bound_unit();
    let mut packet = new_gpu_packet(freeze(&[&unit]), &[&unit]);
    let evidence = admitted(&mut packet);
    let original_environment = packet.tables.row(15, 0).unwrap()[4];
    let original = packet
        .tables
        .row(11, original_environment)
        .unwrap()
        .to_vec();
    assert_eq!(original[2], 3, "T, unconstrained U, and unconstrained N");
    assert_eq!(
        (original[3], original[4]),
        (1, 0),
        "environment names its origin call"
    );
    let context = replay(&mut packet, &evidence);
    let body_environment = packet.tables.row(13, context).unwrap()[2];
    let body = packet.tables.row(11, body_environment).unwrap().to_vec();
    assert_eq!(
        (body[0], body[2], body[3], body[4]),
        (original[0], 3, 0, context)
    );
    let mut roots = Vec::new();
    for i in 0..3 {
        let source = packet.tables.row(12, original[1] + i).unwrap();
        let copied = packet.tables.row(12, body[1] + i).unwrap();
        assert_eq!(copied[0], body_environment);
        assert_eq!(
            &copied[1..],
            &source[1..],
            "exact parameter and immutable root retained"
        );
        roots.push(packet.combined_row(7, copied[2]).unwrap().to_vec());
    }
    assert_eq!(roots[0], vec![1, 3]);
    assert_eq!(roots[1][0], 3);
    let array = packet.combined_row(5, roots[1][1]).unwrap();
    assert_eq!(
        (array[0], array[4], array[5], array[6]),
        (2, 1, 3, 0x8000_0001)
    );
    assert_eq!(
        packet.combined_row(1, array[7]).unwrap(),
        &[12, crate::primitive_types::SCALAR_U32, 3, 0, 0, 0, 0, 0]
    );
    assert_eq!(roots[2][0], 0x8000_0001);
    assert_eq!(
        packet.combined_row(1, roots[2][1]).unwrap(),
        &[12, crate::primitive_types::SCALAR_U32, 7, 0, 0, 0, 0, 0]
    );
    // Fresh call readbacks are allowed; immutable definition Arcs are retained.
    let mut reparsed = unit.clone();
    reparsed.generic_calls = unit.generic_calls.to_vec().into();
    reparsed.checked_call_owners = unit.checked_call_owners.to_vec().into();
    assert_eq!(
        packet
            .append_replay_unit_calls(&reparsed, CALLEE, context)
            .unwrap()
            .count,
        0
    );
    assert_eq!(
        packet.tables.count(15).unwrap(),
        1,
        "sibling stays its admitted original occurrence"
    );
    assert_eq!(packet.prepare_submission().unwrap().context_span.count, 1);
}

#[test]
fn foreign_packet_submissions_and_evidence_cannot_authorize_replay() {
    let unit = bound_unit();
    let catalog = freeze(&[&unit]);
    let mut first = new_gpu_packet(catalog.clone(), &[&unit]);
    let mut second = new_gpu_packet(catalog.clone(), &[&unit]);
    // Equal catalogs and serials cannot transfer the physical arena to another
    // dispatcher. This rejects before any receipt or root can be produced.
    assert_eq!(first.next_serial, second.next_serial);
    rejected(
        first.dispatcher.check(&mut second.packet),
        "another device/dispatch owner",
    );
    let evidence = admitted(&mut first);
    admitted(&mut second);
    rejected(
        second.replay_context(ReplayContextInput {
            snapshot: 0,
            selected_owner_hir: CALLEE,
            evidence: &evidence,
            origin_call: 0,
        }),
        "different catalog or row arena",
    );
}

#[test]
fn every_empty_submission_resets_and_requires_its_own_receipt() {
    let unit = empty_unit(UNIT);
    let catalog = freeze(&[&unit]);
    // Inspect the initial plan without inventing a completion capability.
    let mut planned = new_packet(catalog.clone(), &[&unit]);
    let first = planned.prepare_submission().unwrap();
    assert!(
        first
            .plan
            .initialize_outputs
            .iter()
            .any(|range| range.table == 10 && range.first_row == 0 && range.row_count == 1)
    );
    rejected(planned.prepare_submission(), "no terminal result");

    let mut packet = new_gpu_packet(catalog, &[&unit]);
    assert!(admitted(&mut packet).is_empty());
    let next_serial = packet.next_serial;
    assert!(admitted(&mut packet).is_empty());
    assert_eq!(
        packet.next_serial,
        next_serial + 1,
        "an empty delta requires a new physical submission and acceptance"
    );
    assert!(packet.awaiting_result.is_none());
    let following = packet.prepare_submission().unwrap();
    assert_eq!(
        (
            following.call_span.count,
            following.context_span.count,
            following.obligation_span.count
        ),
        (0, 0, 0)
    );
    assert!(
        following
            .plan
            .initialize_outputs
            .iter()
            .any(|range| range.table == 10 && range.first_row == 0 && range.row_count == 1)
    );
    rejected(packet.admitted_unit_calls(0, None), "no terminal result");
    // Stale/incomplete receipt rejection is covered inside proof_store's
    // private validator tests; no synthetic physical readback is constructible.
}

#[test]
fn arena_growth_preserves_old_graph_references_after_physical_moves() {
    let mut tables = Tables::default();
    let mut arena = AppendArena::default();
    let original_node = [2, 0, 0, 0, 1, 3, 0x8000_0001, 3];
    assert_eq!(tables.push(5, &original_node).unwrap(), 0);
    assert_eq!(tables.push(7, &[3, 0]).unwrap(), 0);
    let mut memory = Vec::<u32>::new();
    let mut moved = false;
    for size in [1, 2, 3, 9] {
        while tables.count(5).unwrap() < size {
            let mut node = original_node;
            node[7] = tables.count(5).unwrap();
            tables.push(5, &node).unwrap();
            tables.push(7, &[3, 0]).unwrap();
        }
        let (copies, writes) = arena.prepare(&tables).unwrap();
        memory.resize(arena.next_word as usize, 0xdead_beef);
        for copy in copies {
            moved = true;
            memory.copy_within(
                copy.from_word as usize..(copy.from_word + copy.word_count) as usize,
                copy.to_word as usize,
            );
        }
        for write in writes {
            let start = write.first_word as usize;
            memory[start..start + write.words.len()].copy_from_slice(&write.words);
        }
        let root = arena.slices[7].offset as usize;
        assert_eq!(
            &memory[root..root + 2],
            &[3, 0],
            "logical root identity survives relocation"
        );
        let target = (arena.slices[5].offset + memory[root + 1] * WIDTHS[5]) as usize;
        assert_eq!(
            &memory[target..target + 8],
            &original_node,
            "referenced old node remains intact"
        );
    }
    assert!(moved, "the scenario must actually exercise a storage move");
}

#[test]
fn admitted_call_handles_require_the_exact_arena_and_terminal_admission() {
    let unit = bound_unit();
    let catalog = freeze(&[&unit]);
    let snapshot = catalog.snapshot_by_unit[&UNIT];
    let mut first = new_gpu_packet(catalog.clone(), &[&unit]);
    rejected(
        first.admitted_unit_calls(snapshot, None),
        "not GPU-admitted",
    );
    let mut pending = new_packet(catalog.clone(), &[&unit]);
    pending.prepare_submission().unwrap();
    rejected(
        pending.admitted_unit_calls(snapshot, None),
        "no terminal result",
    );
    admitted(&mut first);
    let origin = first.admitted_unit_calls(snapshot, None).unwrap().remove(0);
    assert!(origin.is_concrete());
    assert_eq!(
        origin.source().snapshot,
        catalog.snapshots[snapshot as usize].id
    );
    assert_eq!(origin.source().actual_function_hir, CALLER);
    assert_eq!(origin.source().call_hir, unit.generic_calls[0].call_hir);
    assert_eq!(origin.checked_call(), &unit.generic_calls[0]);
    let (_, target_snapshot, target_hir, obligations) = first.replay_origin(&origin).unwrap();
    assert_eq!((target_snapshot, target_hir), (snapshot, CALLEE));
    assert_eq!(obligations.count, 1);

    // Both arenas accepted the same source and checked facts. Source identity
    // and equal row numbers cannot transfer authority between them.
    let mut second = new_gpu_packet(catalog, &[&unit]);
    admitted(&mut second);
    let second_origin = second
        .admitted_unit_calls(snapshot, None)
        .unwrap()
        .remove(0);
    assert_eq!(origin.source(), second_origin.source());
    assert_eq!(origin.checked_call(), second_origin.checked_call());
    rejected(second.replay_origin(&origin), "another catalog or arena");
    second.replay_origin(&second_origin).unwrap();
    first.replay_origin(&origin).unwrap();

    // Even the same retained units frozen into a separate catalog own a fresh
    // private snapshot identity and cannot borrow the first catalog's handle.
    let mut independent = new_gpu_packet(freeze(&[&unit]), &[&unit]);
    admitted(&mut independent);
    rejected(
        independent.replay_origin(&origin),
        "another catalog or arena",
    );
}

#[test]
fn replay_occurrences_do_not_upgrade_an_original_symbolic_call_handle() {
    let mut unit = bound_unit();
    let parameter = unit.checked_contracts.binders[1].parameters[0];
    let mut calls = unit.generic_calls.to_vec();
    let mut nested = calls[0].clone();
    nested.call_hir = 501;
    nested.arguments[0].ty = CheckedGenericType::Parameter(parameter);
    calls.push(nested);
    unit.generic_calls = calls.into();
    // CALLER invokes CALLEE<i32,[i32;3],7>; inside CALLEE, a recursive
    // CALLEE<T,[i32;3],7> call is justified by the owner's T:Marker hypothesis.
    let mut owners = unit.checked_call_owners.to_vec();
    owners.push(CheckedCallOwner {
        call_hir: 501,
        function_hir: CALLEE,
    });
    unit.checked_call_owners = owners.into();
    let catalog = freeze(&[&unit]);
    let snapshot = catalog.snapshot_by_unit[&UNIT];
    let mut packet = new_gpu_packet(catalog, &[&unit]);
    assert_eq!(packet.tables.count(15).unwrap(), 2);
    assert_eq!(packet.tables.count(16).unwrap(), 2);
    let evidence = admitted(&mut packet);
    assert_eq!(evidence.len(), 2);
    assert!(evidence[0].is_concrete());
    assert!(
        !evidence[1].is_concrete(),
        "recursive generic call retains its hypothesis root"
    );
    let originals = packet.admitted_unit_calls(snapshot, None).unwrap();
    let original_symbolic = &originals[1];
    assert!(!original_symbolic.is_concrete());
    assert_eq!(original_symbolic.source().actual_function_hir, CALLEE);
    assert_eq!(original_symbolic.checked_call(), &unit.generic_calls[1]);
    rejected(
        packet.replay_origin(original_symbolic),
        "GPU-checked concrete origin",
    );

    let context = replay(&mut packet, &[evidence[0].clone()]);
    let mut fresh = unit.clone();
    let mut calls = fresh.generic_calls.to_vec();
    calls[1].arguments[0].ty = CheckedGenericType::Scalar(3);
    fresh.generic_calls = calls.into();
    assert_eq!(
        packet
            .append_replay_unit_calls(&fresh, CALLEE, context)
            .unwrap()
            .count,
        1
    );
    rejected(
        packet.admitted_unit_calls(snapshot, Some((CALLEE, context))),
        "not GPU-admitted",
    );
    admitted(&mut packet);
    let replayed = packet
        .admitted_unit_calls(snapshot, Some((CALLEE, context)))
        .unwrap();
    assert_eq!(replayed[0].source(), originals[0].source());
    assert_eq!(replayed[0].checked_call(), originals[0].checked_call());
    assert_eq!(replayed[1].source(), original_symbolic.source());
    assert!(replayed[1].is_concrete());
    assert_eq!(replayed[1].checked_call(), &fresh.generic_calls[1]);
    assert_ne!(replayed[1].checked_call(), original_symbolic.checked_call());
    packet.replay_origin(&replayed[1]).unwrap();
    // Equal source HIR and a later successful replay cannot upgrade the old
    // symbolic occurrence's proof or replace its retained checked arguments.
    rejected(
        packet.replay_origin(original_symbolic),
        "GPU-checked concrete origin",
    );
}

#[test]
fn replay_reuses_equal_sibling_facts_and_paths_but_rejects_changes() {
    let mut unit = bound_unit();
    unit.template_source_paths = vec![Some(PathBuf::from("provider.lani"))].into();
    let catalog = freeze(&[&unit]);
    for mutation in 0..3 {
        let mut packet = new_gpu_packet(catalog.clone(), &[&unit]);
        let evidence = admitted(&mut packet);
        let original = packet.admitted_unit_calls(0, None).unwrap().remove(0);
        let context = replay(&mut packet, &evidence);
        let mut fresh = unit.clone();
        fresh.generic_calls = unit.generic_calls.to_vec().into();
        fresh.checked_call_owners = unit.checked_call_owners.to_vec().into();
        fresh.template_source_paths = unit.template_source_paths.to_vec().into();
        match mutation {
            1 => {
                let mut calls = fresh.generic_calls.to_vec();
                // Change an unconstrained argument. Matching the bound's
                // subject alone must not permit original sibling proof reuse.
                calls[0].constants[0] = CheckedGenericConstant::literal(0, 8);
                fresh.generic_calls = calls.into();
            }
            2 => fresh.template_source_paths = vec![Some(PathBuf::from("another.lani"))].into(),
            _ => {}
        }
        let appended = packet.append_replay_unit_calls(&fresh, CALLEE, context);
        if mutation == 0 {
            assert_eq!(appended.unwrap().count, 0);
            admitted(&mut packet);
            let retained = packet
                .admitted_unit_calls(0, Some((CALLEE, context)))
                .unwrap()
                .remove(0);
            assert_eq!(retained.source(), original.source());
            assert_eq!(retained.checked_call(), original.checked_call());
            packet.replay_origin(&retained).unwrap();
            packet.replay_origin(&original).unwrap();
        } else {
            rejected(
                appended,
                if mutation == 1 {
                    "changed a non-selected callable"
                } else {
                    "frozen definition provenance"
                },
            );
            rejected(packet.prepare_submission(), "failed partial input");
            rejected(packet.admitted_unit_calls(0, None), "failed partial input");
        }
    }
}

#[test]
fn program_failure_diagnostics_require_an_exact_retained_file_span() {
    use super::super::{dispatch::EvidenceDispatchFailure, native_session::native_program_error};
    use crate::compiler::CompileError;

    let first = "module first;\n";
    let second = "module second;\nfn main()->i32 { return relay(3); }\n";
    let local_start = second.find("relay").unwrap();
    let global_start = (first.len() + local_start) as u32;
    let map_failure = |span: [u32; 2], state: u32| {
        let mut unit = bound_unit();
        unit.template_sources = vec![first.to_owned(), second.to_owned()].into();
        unit.template_source_paths = vec![
            Some(PathBuf::from("first.lani")),
            Some(PathBuf::from("nested/second.lani")),
        ]
        .into();
        let mut calls = unit.generic_calls.to_vec();
        calls[0].source_span = span;
        unit.generic_calls = calls.into();
        let mut packet = new_packet(freeze(&[&unit]), &[&unit]);
        let submission = packet.prepare_submission().unwrap();
        let call = submission.call_span.first;
        let obligation = submission.obligation_span.first;
        // A failure is descriptive data, not a fabricated successful proof.
        // Missing's payload need not contain its obligation index.
        let failure = EvidenceDispatchFailure {
            epoch: submission.epoch,
            arena_id: submission.arena_id,
            serial: submission.serial,
            catalog: [1, 0, 0, 0, 0, 0, 0, 0],
            receipt: [6, 0, call, obligation, 0, 0, submission.serial, 0],
            context: None,
            call: Some((call, [3, 0, call, obligation, 0, 0, 0, 0])),
            obligation: Some((obligation, [state, 0, INVALID, INVALID, INVALID, 0, 0, 0])),
        };
        let site = packet.retained_call_site(call).unwrap();
        let error = anyhow::Error::new(failure).context(site);
        let CompileError::Diagnostic(diagnostic) = native_program_error(error) else {
            panic!("program evidence failure must remain a structured diagnostic");
        };
        diagnostic
    };

    let diagnostic = map_failure([global_start, 5], 3);
    assert_eq!(diagnostic.code, "LNC0008");
    let label = diagnostic.primary_label.unwrap();
    assert_eq!(label.path, PathBuf::from("nested/second.lani"));
    assert_eq!(label.line, 2);
    assert_eq!(label.byte_start, Some(local_start));
    assert_eq!(label.byte_end, Some(local_start + 5));
    assert_eq!(label.message, "no matching impl satisfies this call");

    for span in [
        [global_start, 0],
        [first.len() as u32 - 1, 2],
        [(first.len() + second.len()) as u32, 1],
        [u32::MAX, 2],
    ] {
        let diagnostic = map_failure(span, 3);
        assert_eq!(diagnostic.code, "LNC0017", "malformed span: {span:?}");
        assert!(
            diagnostic.primary_label.is_none(),
            "no guessed source location"
        );
        assert!(diagnostic.message.contains("retained call source span"));
    }
    let non_missing = map_failure([global_start, 5], 4);
    assert_eq!(non_missing.code, "LNC0017");
    assert!(non_missing.primary_label.is_none());
    assert!(
        !non_missing.notes.is_empty(),
        "preserve the typed GPU failure detail"
    );
}

// These object records exercise only the private replay publication boundary.
// They are not native code execution or evidence that GPU selection succeeds.
const REPLAY_SIBLING: u32 = 460;

fn replay_emission_unit() -> CompiledSourcePackUnit {
    let mut unit = bound_unit();
    let mut contracts = unit.checked_contracts.as_ref().clone();
    let mut enclosing = owner(450, 45, false);
    enclosing.parameters = vec![CheckedGenericParameter {
        identity: CheckedParameterIdentity {
            unit: UNIT,
            binder: enclosing.binder,
            domain: CheckedParameterDomain::Type,
            source_ordinal: 0,
        },
        binding_slot: 0,
        constant_scalar: None,
    }];
    let mut sibling = owner(REPLAY_SIBLING, 46, true);
    sibling.enclosing_owner = Some(4);
    // This method declares no own parameters; its impl still makes it generic.
    contracts.binders.push(enclosing);
    contracts.binders.push(sibling);
    unit.checked_contracts = Arc::new(contracts);
    let mut calls = unit.generic_calls.to_vec();
    let mut owners = unit.checked_call_owners.to_vec();
    for (hir, function_hir) in [(501, CALLEE), (502, UNUSED_BODY), (503, REPLAY_SIBLING)] {
        let mut call = calls[0].clone();
        call.call_hir = hir;
        calls.push(call);
        owners.push(CheckedCallOwner {
            call_hir: hir,
            function_hir,
        });
    }
    unit.generic_calls = calls.into();
    unit.checked_call_owners = owners.into();
    unit
}

fn replay_emission_object(
    unit: &mut CompiledSourcePackUnit,
    definitions: &[u32],
    native_calls: &[(u32, u32)],
) {
    use crate::codegen::x86::{GpuX86ObjectSection, GpuX86ObjectSymbolRecord};
    let mut object = GpuX86RelocatableObject {
        version: GPU_X86_OBJECT_VERSION,
        library_id: UNIT[0],
        unit_id: UNIT[1],
        entry_offset: None,
        text: vec![0xc3; definitions.len()],
        rodata: vec![],
        relocations: vec![],
        symbols: vec![],
        identity_bytes: vec![],
    };
    let mut push = |identity: [u32; 3], section, offset, size| {
        let bytes = identity
            .into_iter()
            .flat_map(u32::to_le_bytes)
            .collect::<Vec<_>>();
        let (identity_hash_lo, identity_hash_hi) = crate::compiler::stable_name_hash(&bytes);
        let identity_byte_start = object.identity_bytes.len() as u32;
        object.identity_bytes.extend(bytes);
        object.symbols.push(GpuX86ObjectSymbolRecord {
            identity_hash_lo,
            identity_hash_hi,
            identity_byte_start,
            identity_byte_len: 12,
            section,
            offset,
            size,
            flags: 0,
        });
    };
    for _ in native_calls {
        push([9, 9, 1], GpuX86ObjectSection::Undefined, 0, 0);
    }
    for (offset, &hir) in definitions.iter().enumerate() {
        let symbol = unit
            .checked_contracts
            .binders
            .iter()
            .find(|owner| owner.source_hir == hir)
            .unwrap()
            .callable
            .unwrap()
            .native_symbol;
        push(
            [UNIT[0], UNIT[1], symbol],
            GpuX86ObjectSection::Text,
            offset as u32,
            1,
        );
    }
    object.validate().unwrap();
    unit.object = CompiledSourcePackObject::X86_64(object);
    unit.native_call_hirs = native_calls
        .iter()
        .map(|&(hir, _)| hir)
        .collect::<Vec<_>>()
        .into();
    unit.native_call_function_hirs = native_calls
        .iter()
        .map(|&(_, owner)| owner)
        .collect::<Vec<_>>()
        .into();
}

fn normalize_emission(catalog: &FrozenCatalog, unit: &mut CompiledSourcePackUnit) -> Result<()> {
    super::super::native_session::normalize_omitted_template_calls(
        catalog,
        catalog.snapshot_by_unit[&UNIT],
        CALLEE,
        unit,
    )
}

#[test]
fn replay_emission_rejects_a_nonselected_generic_definition_or_native_call() {
    let original = replay_emission_unit();
    let catalog = freeze(&[&original]);
    for (definitions, calls, message) in [
        (
            vec![CALLEE, REPLAY_SIBLING],
            vec![],
            "emitted a non-selected generic body",
        ),
        (
            vec![CALLEE],
            vec![(503, REPLAY_SIBLING)],
            "retained a call from a non-selected generic body",
        ),
        (
            vec![CALLEE],
            vec![(600, REPLAY_SIBLING)],
            "retained a call from a non-selected generic body",
        ),
    ] {
        let mut unit = original.clone();
        let mut facts = unit.generic_calls.to_vec();
        facts[3].constants[0] = CheckedGenericConstant::literal(0, 99);
        unit.generic_calls = facts.into();
        let before = unit.generic_calls.clone();
        replay_emission_object(&mut unit, &definitions, &calls);
        rejected(normalize_emission(&catalog, &mut unit), message);
        assert!(
            Arc::ptr_eq(&before, &unit.generic_calls),
            "a failed emission check cannot normalize away fresh facts"
        );
    }
}

#[test]
fn replay_emission_restores_only_omitted_template_facts_and_preserves_selected_calls() {
    let original = replay_emission_unit();
    let catalog = freeze(&[&original]);
    let mut packet = new_gpu_packet(catalog.clone(), &[&original]);
    let evidence = admitted(&mut packet);
    let context = replay(&mut packet, &evidence[..1]);
    let mut unit = original.clone();
    let mut facts = unit.generic_calls.to_vec();
    facts[1].constants[0] = CheckedGenericConstant::literal(0, 8);
    facts[3].constants[0] = CheckedGenericConstant::literal(0, 99);
    let selected = facts[1].clone();
    unit.generic_calls = facts.into();
    // 600 represents a real ordinary imported call with no generic fact; it
    // still has the checked native owner retained before generic-only pruning.
    replay_emission_object(
        &mut unit,
        &[CALLEE, UNUSED_BODY],
        &[(501, CALLEE), (600, UNUSED_BODY)],
    );
    normalize_emission(&catalog, &mut unit).unwrap();
    assert_eq!(
        unit.generic_calls[1], selected,
        "selected facts remain fresh"
    );
    assert_eq!(
        unit.generic_calls[3], original.generic_calls[3],
        "omitted sibling restores original context"
    );
    assert_eq!(
        unit.generic_calls[2], original.generic_calls[2],
        "ordinary helper is untouched"
    );
    assert_eq!(
        packet
            .append_replay_unit_calls(&unit, CALLEE, context)
            .unwrap()
            .count,
        1,
        "only the selected lexical body publishes a new occurrence"
    );
}

#[test]
fn replay_emission_cannot_normalize_a_changed_ordinary_helper() {
    let original = replay_emission_unit();
    let catalog = freeze(&[&original]);
    let mut packet = new_gpu_packet(catalog.clone(), &[&original]);
    let evidence = admitted(&mut packet);
    let context = replay(&mut packet, &evidence[..1]);
    let mut unit = original.clone();
    let mut facts = unit.generic_calls.to_vec();
    facts[2].constants[0] = CheckedGenericConstant::literal(0, 99);
    let changed = facts[2].clone();
    unit.generic_calls = facts.into();
    replay_emission_object(&mut unit, &[CALLEE, UNUSED_BODY], &[(502, UNUSED_BODY)]);
    normalize_emission(&catalog, &mut unit).unwrap();
    assert_eq!(
        unit.generic_calls[2], changed,
        "ordinary helper must remain subject to exact admission"
    );
    rejected(
        packet.append_replay_unit_calls(&unit, CALLEE, context),
        "changed a non-selected callable's checked call facts",
    );
}

fn add_generic_call(unit: &mut CompiledSourcePackUnit, call_hir: u32, function_hir: u32) {
    let mut calls = unit.generic_calls.to_vec();
    let mut call = calls[0].clone();
    call.call_hir = call_hir;
    calls.push(call);
    unit.generic_calls = calls.into();
    let mut owners = unit.checked_call_owners.to_vec();
    owners.push(CheckedCallOwner { call_hir, function_hir });
    unit.checked_call_owners = owners.into();
}

#[test]
fn replay_keeps_generic_calls_its_template_lacks_only_in_the_selected_body() {
    // A bound-member call that a replay routes to a generic impl method
    // (methods/09) is a generic call its template does not have.
    let original = replay_emission_unit();
    let catalog = freeze(&[&original]);
    let mut packet = new_gpu_packet(catalog.clone(), &[&original]);
    let evidence = admitted(&mut packet);
    let context = replay(&mut packet, &evidence[..1]);
    let mut unit = original.clone();
    add_generic_call(&mut unit, 601, CALLEE);
    add_generic_call(&mut unit, 602, REPLAY_SIBLING);
    replay_emission_object(&mut unit, &[CALLEE, UNUSED_BODY], &[(501, CALLEE), (601, CALLEE)]);
    let mut helper = unit.clone();
    add_generic_call(&mut helper, 603, UNUSED_BODY);
    rejected(
        normalize_emission(&catalog, &mut helper),
        "added a generic call outside the selected body",
    );
    normalize_emission(&catalog, &mut unit).unwrap();
    let hirs = unit.generic_calls.iter().map(|call| call.call_hir).collect::<Vec<_>>();
    assert_eq!(hirs, [500, 501, 502, 503, 601], "the omitted sibling's added call is dropped");
    assert!(unit.checked_call_owners.iter().all(|owner| owner.call_hir != 602));
    assert_eq!(
        packet.append_replay_unit_calls(&unit, CALLEE, context).unwrap().count,
        2,
        "the selected body's fresh occurrence and its added call"
    );
    admitted(&mut packet);
    let snapshot = packet.catalog.snapshot_by_unit[&UNIT];
    let calls = packet.admitted_context_calls(snapshot, context).unwrap();
    assert_eq!(calls.len(), 1);
    assert_eq!(
        (calls[0].source().call_hir, calls[0].source().actual_function_hir),
        (601, CALLEE)
    );
    assert!(calls[0].is_concrete());
    rejected(
        packet.append_context_calls(snapshot, context, CALLEE, unit.generic_calls.clone(), &[1]),
        "already a retained occurrence",
    );
}

#[test]
fn replay_emission_rejects_missing_or_conflicting_native_ownership() {
    let original = replay_emission_unit();
    let catalog = freeze(&[&original]);
    let mut unit = original.clone();
    replay_emission_object(&mut unit, &[CALLEE], &[(501, CALLEE)]);
    unit.native_call_function_hirs = Vec::new().into();
    rejected(
        normalize_emission(&catalog, &mut unit),
        "native owner inventory does not match",
    );
    replay_emission_object(&mut unit, &[CALLEE], &[(501, UNUSED_BODY)]);
    rejected(
        normalize_emission(&catalog, &mut unit),
        "native and generic call ownership disagree",
    );
    replay_emission_object(&mut unit, &[CALLEE], &[(600, 999)]);
    rejected(normalize_emission(&catalog, &mut unit), "was not retained");
}

#[test]
fn constant_packet_atoms_preserve_declared_scalar_and_every_bit() {
    use crate::{constant_value::CheckedConstantValue, primitive_types::*};
    let values = [
        (SCALAR_U32, [u32::MAX, 0]),
        (SCALAR_U64, [u32::MAX, 0]),
        (SCALAR_U64, [0, 1]),
        (SCALAR_U64, [u32::MAX, u32::MAX]),
        (SCALAR_I64, [0, 0x8000_0000]),
        (SCALAR_BOOL, [1, 0]),
        (SCALAR_CHAR, [0x10ffff, 0]),
        (SCALAR_F32, [0, 0]),
        (SCALAR_F32, [0x8000_0000, 0]),
        (SCALAR_F64, [0x0000_1234, 0x7ff8_0000]),
    ];
    let mut atoms = Atoms::default();
    let mut tables = Tables::default();
    let units = BTreeMap::new();
    let mut roots = Vec::new();
    {
        let mut copier = GraphCopier::new(&units, &mut atoms, &mut tables, [0; TABLE_COUNT]);
        for (scalar, words) in values {
            let value = CheckedGenericConstantValue::Literal(
                CheckedConstantValue::from_words(scalar, words).unwrap(),
            );
            roots.push(copier.constant_root(&value).unwrap());
        }
        let duplicate = CheckedGenericConstantValue::Literal(
            CheckedConstantValue::from_words(SCALAR_U64, [0, 1]).unwrap(),
        );
        roots.push(copier.constant_root(&duplicate).unwrap());
    }
    let mut identities = BTreeSet::new();
    for (root, (scalar, [lo, hi])) in roots.iter().zip(values) {
        let reference = tables.row(7, *root).unwrap();
        assert_eq!(reference[0], 0x8000_0001);
        assert!(
            identities.insert(reference[1]),
            "distinct typed values must have distinct atoms"
        );
        assert_eq!(
            atoms.keys[reference[1] as usize],
            [12, scalar, lo, hi, 0, 0, 0, 0]
        );
    }
    assert_eq!(
        tables.row(7, roots[2]).unwrap(),
        tables.row(7, roots[values.len()]).unwrap()
    );
}

#[test]
fn constant_packet_copies_projection_recipe_without_host_fitting() {
    use crate::{constant_value::CheckedConstantValue, primitive_types::*};
    let literal = CheckedGenericConstantValue::Literal(
        CheckedConstantValue::from_words(SCALAR_U64, [300, 0]).unwrap(),
    );
    let projection = CheckedGenericConstantValue::CountProjection {
        target_scalar: SCALAR_U64,
        source: Box::new(CheckedGenericConstantValue::CountProjection {
            target_scalar: SCALAR_U8,
            source: Box::new(literal),
        }),
    };
    let mut atoms = Atoms::default();
    let mut tables = Tables::default();
    let units = BTreeMap::new();
    let root = GraphCopier::new(&units, &mut atoms, &mut tables, [0; TABLE_COUNT])
        .constant_root(&projection)
        .unwrap();
    let reference = tables.row(7, root).unwrap();
    assert_eq!(reference[0], 0x8000_0003);
    let outer = tables.row(5, reference[1]).unwrap();
    assert_eq!(&outer[..5], &[5, SCALAR_U64, 0, 0, 0x8000_0003]);
    let inner = tables.row(5, outer[5]).unwrap();
    assert_eq!(&inner[..5], &[5, SCALAR_U8, 0, 0, 0x8000_0001]);
    assert_eq!(
        atoms.keys[inner[5] as usize],
        [12, SCALAR_U64, 300, 0, 0, 0, 0, 0]
    );
    // The GPU must reject the inner u8 fit. Copying its recipe is not admission.
    assert_eq!(tables.count(5).unwrap(), 2);
}
