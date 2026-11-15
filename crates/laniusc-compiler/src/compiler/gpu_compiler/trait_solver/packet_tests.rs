//! Storage and authority tests over retained record fixtures. Success-dependent
//! cases use real GPU catalog, batch and proof admission. Pure host cases check
//! input rejection, storage plans and diagnostic mapping; no host solver runs.

use super::super::dispatch::{GpuPacket, GpuTraitSolver};
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
        instance_closure: None,
        solver_closed: false,
        facts_elided: false,
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
            resident_bytes: Default::default(),
        },
        object: CompiledSourcePackObject::X86_64(GpuX86RelocatableObject {
            version: GPU_X86_OBJECT_VERSION,
            library_id: key[0],
            unit_id: key[1],
            entry_offset: None,
            body: None,
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
        trait_requirement: false,
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
    dispatcher: GpuTraitSolver,
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
    let dispatcher = GpuTraitSolver::admit(
        compiler.trait_solver_workspace.checkout(),
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
fn admitted(fixture: &mut GpuFixture) -> Vec<ValidatedSolverResult> {
    fixture
        .dispatcher
        .check(&mut fixture.packet)
        .expect("GPU admits complete fixture batch")
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
    rejected(packet.admitted_unit_calls(0), "no terminal result");
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
        first.admitted_unit_calls(snapshot),
        "not GPU-admitted",
    );
    let mut pending = new_packet(catalog.clone(), &[&unit]);
    pending.prepare_submission().unwrap();
    rejected(
        pending.admitted_unit_calls(snapshot),
        "no terminal result",
    );
    admitted(&mut first);
    let origin = first.admitted_unit_calls(snapshot).unwrap().remove(0);
    assert!(origin.is_concrete());
    assert_eq!(
        origin.source().snapshot,
        catalog.snapshots[snapshot as usize].id
    );
    assert_eq!(origin.source().actual_function_hir, CALLER);
    assert_eq!(origin.source().call_hir, unit.generic_calls[0].call_hir);
    assert_eq!(origin.checked_call(), &unit.generic_calls[0]);
    let (_, target_snapshot, target_hir, obligations) = first.concrete_origin(&origin).unwrap();
    assert_eq!((target_snapshot, target_hir), (snapshot, CALLEE));
    assert_eq!(obligations.count, 1);

    // Both arenas accepted the same source and checked facts. Source identity
    // and equal row numbers cannot transfer authority between them.
    let mut second = new_gpu_packet(catalog, &[&unit]);
    admitted(&mut second);
    let second_origin = second
        .admitted_unit_calls(snapshot)
        .unwrap()
        .remove(0);
    assert_eq!(origin.source(), second_origin.source());
    assert_eq!(origin.checked_call(), second_origin.checked_call());
    rejected(second.concrete_origin(&origin), "another catalog or arena");
    second.concrete_origin(&second_origin).unwrap();
    first.concrete_origin(&origin).unwrap();

    // Even the same retained units frozen into a separate catalog own a fresh
    // private snapshot identity and cannot borrow the first catalog's handle.
    let mut independent = new_gpu_packet(freeze(&[&unit]), &[&unit]);
    admitted(&mut independent);
    rejected(
        independent.concrete_origin(&origin),
        "another catalog or arena",
    );
}

#[test]
fn implementation_application_mint_requires_exact_obligation_and_current_projection() {
    use super::super::dispatch::ImplProjectionLimits;
    let mut unit = bound_unit();
    let mut calls = unit.generic_calls.to_vec();
    let mut sibling = calls[0].clone();
    sibling.call_hir += 1;
    calls.push(sibling);
    unit.generic_calls = calls.into();
    let mut owners = unit.checked_call_owners.to_vec();
    owners.push(CheckedCallOwner { call_hir: 501, function_hir: CALLER });
    unit.checked_call_owners = owners.into();
    let mut fixture = new_gpu_packet(freeze(&[&unit]), &[&unit]);
    let evidence = admitted(&mut fixture);
    let origins = fixture.admitted_unit_calls(0).unwrap();
    assert_eq!((origins.len(), evidence.len()), (2, 2));
    assert_eq!(fixture.packet.uploaded_retained_evidence_rows(), 0,
        "freshly accepted root evidence is not a GPU table-17 input yet");
    assert_eq!(fixture.tables.count(17).unwrap(), 2,
        "the CPU retained exact evidence rows after the accepted readback");
    // Equal goals and selected implementations do not identify an occurrence.
    rejected(fixture.request_implementation_application(&origins[0], &evidence[1]),
        "exact origin obligation span");
    let request = fixture.request_implementation_application(&origins[0], &evidence[0]).unwrap();
    let projection = fixture.dispatcher.project_implementation_applications(
        &fixture.packet, std::slice::from_ref(&request), ImplProjectionLimits::production(),
    ).unwrap().remove(0);
    admitted(&mut fixture);
    // The old root is still accepted, but its old raw projection is not a new receipt.
    rejected(fixture.admit_implementation_application(request, projection, vec![]),
        "another submission");
    let request = fixture.request_implementation_application(&origins[0], &evidence[0]).unwrap();
    let projection = fixture.dispatcher.project_implementation_applications(
        &fixture.packet, std::slice::from_ref(&request), ImplProjectionLimits::production(),
    ).unwrap().remove(0);
    let application = fixture.admit_implementation_application(request, projection, vec![]).unwrap();
    admitted(&mut fixture);
    application.validate_retained(&fixture).unwrap();
    let foreign = new_packet(fixture.catalog.clone(), &[&unit]);
    assert_eq!(foreign.tables.words[15], fixture.tables.words[15]);
    assert_eq!(foreign.tables.words[16], fixture.tables.words[16]);
    rejected(application.validate_retained(&foreign), "another catalog or arena");
    let mut foreign_evidence = evidence[0].clone();
    foreign_evidence.arena_id = foreign.arena_id;
    rejected(fixture.request_implementation_application(&origins[0], &foreign_evidence),
        "another catalog or arena");
}


// These object records exercise only the private replay publication boundary.
// They are not native code execution or evidence that GPU selection succeeds.
const REPLAY_SIBLING: u32 = 460;


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
