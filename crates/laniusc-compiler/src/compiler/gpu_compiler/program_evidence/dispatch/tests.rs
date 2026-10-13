//! GPU catalog admission tests over real accepted source-pack snapshots.
//! Integration: `#[cfg(test)] mod tests;` in program_evidence/dispatch/mod.rs.
//! These tests stop at catalog admission; they do not claim batch selection or
//! imported-body replay is implemented.

use std::collections::BTreeSet;

use super::{super::catalog::CatalogInput, *};
use crate::{
    codegen::x86::GpuX86ObjectSection,
    compiler::{
        GpuCompiler,
        GpuSemanticInterfaceArtifact,
        SourcePackArtifactTarget,
        gpu_compiler::typecheck::{CompiledSourcePackObject, CompiledSourcePackUnit, OriginalUnitFacts},
    },
};

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
    .expect("compile actual source-pack snapshot for catalog admission")
}

fn freeze_units(units: &[&CompiledSourcePackUnit]) -> Arc<FrozenCatalog> {
    let facts = units.iter().map(|unit| unit.original_facts().unwrap()).collect::<Vec<_>>();
    freeze_facts(&facts)
}

fn freeze_facts(facts: &[OriginalUnitFacts]) -> Arc<FrozenCatalog> {
    let inputs = facts.iter().map(|facts| CatalogInput { facts }).collect::<Vec<_>>();
    FrozenCatalog::freeze(&inputs).expect("freeze accepted unit snapshots")
}

fn admit_catalog(
    compiler: &GpuCompiler<'_>,
    catalog: Arc<FrozenCatalog>,
) -> Result<GpuProgramEvidence> {
    GpuProgramEvidence::admit(
        compiler.program_evidence_workspace.checkout(),
        catalog,
    )
}

fn assert_admitted(compiler: &GpuCompiler<'_>, catalog: Arc<FrozenCatalog>) {
    admit_catalog(compiler, catalog).expect("GPU admits the complete frozen catalog");
}

fn assert_rejected(compiler: &GpuCompiler<'_>, catalog: Arc<FrozenCatalog>, state: u32) {
    let error = match admit_catalog(compiler, catalog) {
        Ok(_) => panic!("GPU admitted a catalog expected to fail with state {state}"),
        Err(error) => error,
    };
    // Check the actual GPU receipt category, not a transport, shader-loading,
    // or host serialization error; row ordering within a failed phase may vary.
    let prefix = format!("program catalog GPU admission/coherence failed: [{state},");
    assert!(error.to_string().starts_with(&prefix), "{error:#}");
}

fn set_catalog_word(catalog: &mut FrozenCatalog, table: usize, row: u32, field: usize, value: u32) {
    assert!(row < catalog.slices[table].count);
    assert!(field < WIDTHS[table] as usize);
    catalog.tables.row_mut(table, row).unwrap()[field] = value;
    let word =
        catalog.slices[table].offset as usize + row as usize * WIDTHS[table] as usize + field;
    Arc::make_mut(&mut catalog.words)[word] = value;
}

fn marker_api(compiler: &GpuCompiler<'_>, key: [u32; 2]) -> CompiledSourcePackUnit {
    compile_unit(
        compiler,
        key,
        r#"
module catalog_cases::api;
pub trait Rel<A> {}
pub fn anchor()->i32 { return 0; }
"#,
        Vec::new(),
    )
}

fn marker_impl(
    compiler: &GpuCompiler<'_>,
    key: [u32; 2],
    module: &str,
    api: &CompiledSourcePackUnit,
    inner: u32,
    outer: u32,
) -> CompiledSourcePackUnit {
    compile_unit(
        compiler,
        key,
        &format!(
            r#"
module catalog_cases::{module};
import catalog_cases::api;
pub impl catalog_cases::api::Rel<[[i32;{inner}];{outer}]> for bool {{}}
pub fn marker()->i32 {{ return 19; }}
"#
        ),
        vec![vec![api.interface.clone()]],
    )
}

#[test]
fn gpu_catalog_distinguishes_nested_lengths_and_deduplicates_retained_units() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let api = marker_api(&compiler, [71, 0]);
    let first = marker_impl(&compiler, [71, 1], "first", &api, 2, 3);
    let inner = marker_impl(&compiler, [71, 2], "inner", &api, 3, 3);
    let outer = marker_impl(&compiler, [71, 3], "outer", &api, 2, 4);
    let catalog = freeze_units(&[&api, &first, &inner, &outer]);
    assert_eq!(catalog.tables.count(9).unwrap(), 3);
    assert_admitted(&compiler, catalog);

    // Cloning the exact immutable facts preserves original snapshot identity.
    // Repeated reachability is not a new implementation candidate.
    let api_facts = api.original_facts().unwrap();
    let first_facts = first.original_facts().unwrap();
    let repeated = freeze_facts(&[
        api_facts.clone(), first_facts.clone(), inner.original_facts().unwrap(),
        first_facts.clone(), outer.original_facts().unwrap(), api_facts, first_facts,
    ]);
    assert_eq!(repeated.snapshots.len(), 4);
    assert_eq!(repeated.tables.count(9).unwrap(), 3);
    assert_admitted(&compiler, repeated);
    assert_admitted(&compiler, freeze_units(&[&outer, &inner, &first, &api]));
}

#[test]
fn gpu_catalog_rejects_equal_keys_from_linked_unit_without_caller_import_edge() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let api = marker_api(&compiler, [72, 0]);
    let first = marker_impl(&compiler, [72, 1], "first", &api, 2, 3);
    let caller = compile_unit(
        &compiler,
        [72, 2],
        r#"
module catalog_cases::caller;
import catalog_cases::first;
fn main()->i32 { return catalog_cases::first::marker(); }
"#,
        vec![vec![api.interface.clone()], vec![first.interface.clone()]],
    );
    let conflicting = marker_impl(&compiler, [72, 3], "unimported", &api, 2, 3);
    assert!(
        caller
            .template_dependency_pages
            .iter()
            .flatten()
            .all(|page| [page.library_id, page.unit_id] != [72, 3])
    );
    assert!(
        caller.generic_calls.is_empty(),
        "catalog coherence does not depend on a pending call"
    );
    assert_admitted(&compiler, freeze_units(&[&api, &first, &caller]));

    let catalog = freeze_units(&[&api, &first, &caller, &conflicting]);
    assert_eq!(catalog.tables.count(9).unwrap(), 2);
    assert_ne!(
        catalog.tables.row(9, 0).unwrap()[0],
        catalog.tables.row(9, 1).unwrap()[0],
        "different accepted implementations have different definition identities"
    );
    assert_rejected(&compiler, catalog, 5); // COHERENCE_CONFLICT
    assert_rejected(
        &compiler,
        freeze_units(&[&conflicting, &caller, &first, &api]),
        5,
    );
    assert_admitted(&compiler, freeze_units(&[&api, &first, &caller]));
}

#[test]
fn gpu_catalog_preserves_public_private_method_targets_and_rejects_cross_wiring() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let unit = compile_unit(
        &compiler,
        [73, 0],
        r#"
module catalog_cases::methods;
pub trait Echo {
    pub fn copy(self, value:i32)->i32;
    fn secret(self, value:i32)->i32;
}
pub impl Echo for bool {
    pub fn copy(self, value:i32)->i32 { return value; }
    fn secret(self, value:i32)->i32 { return value; }
}
"#,
        Vec::new(),
    );
    let catalog = freeze_units(&[&unit]);
    assert_eq!(catalog.tables.count(10).unwrap(), 2);
    let CompiledSourcePackObject::X86_64(object) = &unit.object else {
        unreachable!()
    };
    let native_definitions = object
        .symbols
        .iter()
        .filter(|symbol| symbol.section == GpuX86ObjectSection::Text)
        .map(|symbol| {
            assert_eq!(symbol.identity_byte_len, 12);
            let start = symbol.identity_byte_start as usize;
            let bytes = &object.identity_bytes[start..start + 12];
            std::array::from_fn::<_, 3, _>(|i| {
                u32::from_le_bytes(bytes[i * 4..i * 4 + 4].try_into().unwrap())
            })
        })
        .collect::<BTreeSet<_>>();
    let mut visibility_kinds = BTreeSet::new();
    for binding in &unit.checked_contracts.implementations[0].method_bindings {
        assert!(native_definitions.contains(&binding.target));
        let snapshot = catalog.snapshot_by_unit[&[73, 0]];
        let owner = catalog.owner_by_hir[&(snapshot, binding.method_hir)];
        let callable = catalog.callable_by_native[&(snapshot, binding.target[2])];
        let callable = catalog.tables.row(4, callable).unwrap();
        let method = catalog.tables.words[10]
            .chunks_exact(6)
            .find(|row| row[1] == binding.required_symbol)
            .expect("retained method binding");
        assert_eq!((method[2], method[4]), (callable[0], owner));
        let implementation = catalog.tables.row(9, method[0]).unwrap();
        assert_eq!(catalog.tables.row(2, owner).unwrap()[3], implementation[1]);
        visibility_kinds.insert(catalog.atoms.keys[callable[0] as usize][0]);
    }
    assert_eq!(
        visibility_kinds,
        BTreeSet::from([8, 9]),
        "private methods named by public implementation bindings stay private callable atoms"
    );
    assert_admitted(&compiler, catalog);

    let mut crossed = freeze_units(&[&unit]);
    let other_target = crossed.tables.row(10, 1).unwrap()[2];
    set_catalog_word(Arc::get_mut(&mut crossed).unwrap(), 10, 0, 2, other_target);
    assert_rejected(&compiler, crossed, 2); // INVALID_INPUT: target belongs to another owner
    assert_admitted(&compiler, freeze_units(&[&unit]));
}

fn compiled_catalog_fixture(compiler: &GpuCompiler<'_>) -> CompiledSourcePackUnit {
    compile_unit(
        compiler,
        [74, 0],
        r#"
module catalog_cases::unused;
pub trait Rel<A> {}
pub impl Rel<[i32;2]> for bool {}
pub fn guarded<T>(value:T)->T where T:Rel<[i32;2]> { return value; }
pub fn unused()->i32 { return 0; }
"#,
        Vec::new(),
    )
}

fn frozen_fixture(unit: &CompiledSourcePackUnit) -> Arc<FrozenCatalog> {
    assert!(unit.generic_calls.is_empty());
    freeze_units(&[unit])
}

// Node count does not size the atom/implementation output index. Relocate only
// table5 and leave every existing row identity and output allocation intact.
fn append_catalog_nodes(catalog: &mut FrozenCatalog, rows: &[[u32; 8]]) -> u32 {
    let first = catalog.slices[5].count;
    for row in rows {
        catalog.tables.words[5].extend_from_slice(row);
    }
    let mut words = catalog.words.to_vec();
    let offset = u32::try_from(words.len()).unwrap();
    words.extend_from_slice(&catalog.tables.words[5]);
    let count = catalog.tables.count(5).unwrap();
    catalog.slices[5] = Slice {
        offset,
        count,
        capacity: count,
    };
    catalog.words = words.into();
    first
}

fn expect_gpu_admission_failure(
    result: Result<GpuProgramEvidence>,
    label: &str,
    state: u32,
    detail: u32,
) -> String {
    let error = match result {
        Ok(_) => panic!("malformed catalog was admitted: {label}"),
        Err(error) => error.to_string(),
    };
    assert!(
        error.starts_with(&format!(
            "program catalog GPU admission/coherence failed: [{state}, {detail},"
        )),
        "{label}: expected GPU admission status, not a build/device/transport failure: {error}"
    );
    error
}

#[test]
fn gpu_catalog_admission_rejects_unused_rows_and_broken_identity_relationships() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let unit = compiled_catalog_fixture(&compiler);
    admit_catalog(&compiler, frozen_fixture(&unit)).expect("valid catalog before corruptions");

    for corruption in [
        "unused malformed node",
        "borrowed predicate span",
        "duplicate atom",
    ] {
        let mut catalog = frozen_fixture(&unit);
        let packet = Arc::get_mut(&mut catalog).expect("one test owns this catalog");
        let detail = match corruption {
            "unused malformed node" => {
                // Node8 [reference-kind,0,0,0,child-tag,child-payload,0,0].
                // Its child tag is invalid and no predicate/root reaches it.
                append_catalog_nodes(packet, &[[4, 0, 0, 0, 0, 0, 0, 0]]);
                4 // PARAMETER_DOMAIN: whole-catalog row admission still rejects it.
            }
            "borrowed predicate span" => {
                assert_eq!(packet.slices[8].count, 1);
                let predicate_owner = packet.tables.row(8, 0).unwrap()[1];
                let other_owner = (0..packet.slices[2].count)
                    .find(|&owner| {
                        let row = packet.tables.row(2, owner).unwrap();
                        owner != predicate_owner && row[7] == 0 && row[8] != INVALID
                    })
                    .expect("unrelated callable without predicates");
                // Owner9 fields6/7 are first_predicate/predicate_count. The
                // predicate's own backlink remains its original exact owner.
                set_catalog_word(packet, 2, other_owner, 6, 0);
                set_catalog_word(packet, 2, other_owner, 7, 1);
                3 // OWNER_MISMATCH.
            }
            "duplicate atom" => {
                let callables = (0..packet.slices[1].count)
                    .filter(|&atom| packet.tables.row(1, atom).unwrap()[0] == 8)
                    .collect::<Vec<_>>();
                assert_eq!(callables.len(), 2);
                let identity = packet.tables.row(1, callables[0]).unwrap().to_vec();
                for (field, value) in identity.into_iter().enumerate() {
                    set_catalog_word(packet, 1, callables[1], field, value);
                }
                16 // CONFLICTING_IDENTITY: each public callable atom remains shape-valid.
            }
            _ => unreachable!(),
        };
        expect_gpu_admission_failure(admit_catalog(&compiler, catalog), corruption, 2, detail);
    }
    admit_catalog(&compiler, frozen_fixture(&unit)).expect("valid catalog after all rejections");
}

#[test]
fn gpu_catalog_admission_requires_valid_header_before_any_row_work() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let unit = compiled_catalog_fixture(&compiler);
    for field in [0usize, 1, 2, 3] {
        let mut catalog = frozen_fixture(&unit);
        let packet = Arc::get_mut(&mut catalog).unwrap();
        // Corrupt magic, version, or either epoch word while leaving every
        // physical span valid. Safe row addressing cannot authorize a packet
        // whose protocol header was never admitted.
        Arc::make_mut(&mut packet.words)[field] ^= 1;
        assert_rejected(&compiler, catalog, 0);
    }
    assert_admitted(&compiler, frozen_fixture(&unit));
}

#[test]
fn gpu_catalog_admission_enforces_the_reachable_graph_depth_boundary() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let unit = compiled_catalog_fixture(&compiler);
    for wrappers in [63u32, 64, 63] {
        let mut catalog = frozen_fixture(&unit);
        let packet = Arc::get_mut(&mut catalog).unwrap();
        let predicate = packet.tables.row(8, 0).unwrap().to_vec();
        assert_eq!(predicate[5], 1, "one trait operand in the compiled fixture");
        let root = predicate[4];
        let original = packet.tables.row(7, root).unwrap();
        assert_eq!(original[0], 3);
        let array = packet.tables.row(5, original[1]).unwrap();
        assert_eq!(array[0], 2);
        let mut child = [array[4], array[5]];
        assert_eq!(child[0], 1, "start from the accepted i32 leaf");
        let first = packet.slices[5].count;
        let mut nodes = Vec::new();
        for offset in 0..wrappers {
            nodes.push([4, 0, 0, 0, child[0], child[1], 0, 0]);
            child = [3, first + offset];
        }
        assert_eq!(append_catalog_nodes(packet, &nodes), first);
        set_catalog_word(packet, 7, root, 0, child[0]);
        set_catalog_word(packet, 7, root, 1, child[1]);
        let result = admit_catalog(&compiler, catalog);
        if wrappers == 63 {
            result.expect("63 reference nodes plus the scalar fit 64 traversal frames");
        } else {
            let error = expect_gpu_admission_failure(result, "65-frame root", 3, 6);
            assert!(
                error.ends_with(", 65, 64, 0, 0]"),
                "explicit required/available depth: {error}"
            );
        }
    }
}

#[test]
fn gpu_catalog_admission_rejects_shape_valid_reachable_cycles() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let unit = compiled_catalog_fixture(&compiler);
    assert_admitted(&compiler, frozen_fixture(&unit));

    let mut catalog = frozen_fixture(&unit);
    let packet = Arc::get_mut(&mut catalog).expect("one test owns this catalog");
    let predicate = packet.tables.row(8, 0).unwrap().to_vec();
    assert_eq!(predicate[5], 1, "the predicate has one array operand");
    let root = packet.tables.row(7, predicate[4]).unwrap();
    assert_eq!(root[0], 3);
    let node = root[1];
    assert_eq!(packet.tables.row(5, node).unwrap()[0], 2);
    // The array child remains an in-range type reference and its length is
    // unchanged. Row shape admission cannot prove this reachable graph acyclic.
    set_catalog_word(packet, 5, node, 4, 3);
    set_catalog_word(packet, 5, node, 5, node);
    expect_gpu_admission_failure(
        admit_catalog(&compiler, catalog),
        "shape-valid reachable array cycle",
        2,
        5, // INVALID_INPUT / GRAPH_CYCLE, not a row-shape failure.
    );

    assert_admitted(&compiler, frozen_fixture(&unit));
}

#[test]
fn gpu_catalog_admission_rejects_valid_parameters_from_another_lexical_owner() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let unit = compile_unit(
        &compiler,
        [75, 0],
        r#"
module catalog_cases::parameter_scope;
pub trait Rel<A> {}
pub fn guarded<T>(value:T)->T where T:Rel<T> { return value; }
pub fn independent<U>(value:U)->U { return value; }
pub fn anchor()->i32 { return 0; }
"#,
        Vec::new(),
    );
    assert!(unit.generic_calls.is_empty());
    assert_admitted(&compiler, frozen_fixture(&unit));

    let mut catalog = frozen_fixture(&unit);
    let packet = Arc::get_mut(&mut catalog).expect("one test owns this catalog");
    assert_eq!(packet.tables.count(8).unwrap(), 1);
    let predicate = packet.tables.row(8, 0).unwrap().to_vec();
    assert_eq!(predicate[5], 1);
    let owner = predicate[1];
    let operand_root = predicate[4];
    let operand = packet.tables.row(7, operand_root).unwrap().to_vec();
    assert_eq!(operand[0], 2, "the valid operand names guarded's own T");
    let own_parameter = packet.tables.words[3]
        .chunks_exact(4)
        .find(|row| row[0] == owner && row[1] == operand[1])
        .expect("the operand's accepted parameter belongs to guarded")
        .to_vec();
    let foreign_parameter = packet.tables.words[3]
        .chunks_exact(4)
        .find(|row| {
            row[0] != owner
                && row[2] == 0
                && row[3] == 0
                && packet.tables.row(2, row[0]).unwrap()[8] != INVALID
        })
        .expect("independent has a valid parameter in another callable owner")
        .to_vec();
    // Both are sibling callable scopes. In particular, the chosen foreign
    // parameter is not Rel<A>'s non-callable trait parameter or an ancestor.
    assert_eq!(packet.tables.row(2, owner).unwrap()[3], INVALID);
    assert_eq!(
        packet.tables.row(2, foreign_parameter[0]).unwrap()[3],
        INVALID
    );
    assert_eq!(&own_parameter[2..4], &[0, 0]);
    assert_eq!(&foreign_parameter[2..4], &[0, 0]);
    let own_atom = packet.tables.row(1, own_parameter[1]).unwrap();
    let foreign_atom = packet.tables.row(1, foreign_parameter[1]).unwrap();
    assert_eq!((own_atom[0], own_atom[2], own_atom[3]), (5, 0, 0));
    assert_eq!(
        (foreign_atom[0], foreign_atom[2], foreign_atom[3]),
        (5, 0, 0)
    );
    assert_ne!(
        own_atom[1], foreign_atom[1],
        "binding slot and ordinal do not identify a parameter"
    );
    // Every atom, parameter row and ownership backlink remains valid. Only
    // the predicate's contextual use changes to a different owner's atom.
    set_catalog_word(packet, 7, operand_root, 1, foreign_parameter[1]);
    expect_gpu_admission_failure(
        admit_catalog(&compiler, catalog),
        "valid parameter outside the predicate's lexical scope",
        2,
        3, // INVALID_INPUT / OWNER_MISMATCH, not malformed parameter metadata.
    );

    assert_admitted(&compiler, frozen_fixture(&unit));
}
#[test]
fn gpu_catalog_admission_rejects_malformed_input_directories_and_recovers() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let unit = compiled_catalog_fixture(&compiler);
    let catalog = frozen_fixture(&unit);
    let device = &compiler.gpu.device;
    let queue = &compiler.gpu.queue;
    let workspace = compiler.program_evidence_workspace.checkout();
    let kernels = kernels::CatalogKernels::load(device).expect("catalog kernels");
    let storage = Arena::from_words(&workspace, "directory_test.catalog", &catalog.words).unwrap();
    let (mut pristine, empty_output) = catalog_bootstrap(&catalog).unwrap();
    // Physical padding permits valid unused reservation and overlapping suffix
    // capacity cases without fabricating rows or changing the compiled fixture.
    pristine.resize(pristine.len() + 16, 0);
    let output = Arena::from_words(&workspace, "directory_test.output", &empty_output).unwrap();
    let readback = PagedReadback::new(device, "directory_test.receipt", 4096);
    let input_words = u32::try_from(pristine.len()).unwrap();
    let run = |header: &[u32], logical_words: u32| {
        let mut input = Arena::from_words(&workspace, "directory_test.input", header).unwrap();
        input.logical_words = logical_words;
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("directory_test.admit"),
        });
        // Match the production admission reset. An invalid output layout must
        // leave this fresh receipt UNPROCESSED, never a prior VALID receipt.
        passes_core::flush_deferred_compute(&mut encoder);
        for table in [0usize, 1] {
            let slice = catalog.outputs[table];
            if slice.count != 0 {
                storage.buffer.clear(
                    &mut encoder,
                    u64::from(slice.offset) * 4,
                    Some(u64::from(slice.count * OUTPUT_WIDTHS[table]) * 4),
                );
            }
        }
        // Only the actual uploaded header is untrusted. Dispatch coverage and
        // the receipt address retain the original catalog's checked metadata.
        kernels
            .record(device, &mut encoder, &catalog, &storage, &input, &output)
            .unwrap();
        passes_core::flush_deferred_compute(&mut encoder);
        queue.submit(Some(encoder.finish()));
        let region = ReadbackRegion::from_buffer(
            &storage.buffer,
            u64::from(catalog.outputs[0].offset) * 4,
            32,
            "directory_test.receipt",
        )
        .unwrap();
        let raw = readback
            .read_regions(device, queue, &[region], "directory test GPU receipt")
            .unwrap();
        one_status(&raw[0]).unwrap()
    };
    assert_eq!(run(&pristine, input_words)[0], 1, "valid initial directory");
    let reject = |label: &str, edits: &[(usize, usize, u32)], expected: [u32; 4]| {
        let mut words = pristine.clone();
        for &(table, field, value) in edits {
            assert!(table < TABLE_COUNT && field < 6);
            words[DIRECTORY_WORD as usize + table * 6 + field] = value;
        }
        assert_eq!(&run(&words, input_words)[..4], &expected, "{label}");
    };
    let unprocessed = [0, 0, 0, 0];
    // Descriptor shape failures are seen by the pre-BUILDING output-layout
    // scan of every input table. They leave the trusted reset receipt at zero.
    reject(
        "unused wrong width",
        &[(17, 5, WIDTHS[17] + 1)],
        unprocessed,
    );
    reject("unused zero width", &[(17, 5, 0)], unprocessed);
    reject(
        "reserved logical row count",
        &[(5, 1, u32::MAX)],
        unprocessed,
    );
    reject(
        "suffix logical count exceeds capacity",
        &[(17, 3, 1)],
        unprocessed,
    );
    reject(
        "suffix capacity overflow",
        &[(17, 2, BATCH_FIXED_WORDS), (17, 4, u32::MAX)],
        unprocessed,
    );
    reject(
        "catalog span past physical end",
        &[(5, 0, storage.logical_words)],
        unprocessed,
    );
    reject(
        "catalog address would wrap",
        &[(5, 0, u32::MAX - 3)],
        unprocessed,
    );
    reject(
        "unused suffix reservation crosses physical end",
        &[(17, 2, input_words - 4), (17, 4, 1)],
        unprocessed,
    );
    // These descriptors are individually shape-valid; the global directory
    // overlap checks must still run before any catalog row can be admitted.
    reject(
        "catalog overlaps protocol header",
        &[(5, 0, 0)],
        [2, 1, 5, INVALID],
    );
    assert!(catalog.slices[4].count != 0 && catalog.slices[5].count != 0);
    assert!(
        catalog.slices[4].offset + catalog.slices[5].count * WIDTHS[5] <= catalog.outputs[0].offset
    );
    reject(
        "catalog input tables overlap",
        &[(5, 0, catalog.slices[4].offset)],
        [2, 1, 5, 4],
    );
    reject(
        "unused suffix overlaps directory",
        &[(17, 4, 1)],
        [2, 1, 17, INVALID],
    );
    reject(
        "unused suffix capacities overlap",
        &[
            (11, 2, BATCH_FIXED_WORDS),
            (11, 4, 1),
            (12, 2, BATCH_FIXED_WORDS),
            (12, 4, 1),
        ],
        [2, 1, 12, 11],
    );

    // Allocation padding is not logical input. Conversely, claiming a logical
    // length beyond the actual binding must fail without reading outside it.
    let mut reserved = pristine.clone();
    let directory = DIRECTORY_WORD as usize + 17 * 6;
    reserved[directory + 2] = BATCH_FIXED_WORDS;
    reserved[directory + 4] = 1;
    assert_eq!(&run(&reserved, BATCH_FIXED_WORDS)[..4], &unprocessed);
    assert_eq!(&run(&pristine, input_words + 1)[..4], &unprocessed);
    assert_eq!(
        run(&reserved, input_words)[0],
        1,
        "valid unused capacity is admitted"
    );
    assert_eq!(
        run(&pristine, input_words)[0],
        1,
        "pristine recovery on the same GPU storage"
    );
}

#[test]
fn gpu_native_recipe_admission_rejects_stale_epoch_broken_groups_and_foreign_parameters() {
    let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
    let unit = compile_unit(
        &compiler,
        [78, 0],
        r#"
module catalog_cases::native_recipes;
pub struct Cell<T> { value: T }
struct Other<U> { value: U }
enum Envelope<V> { Empty, Value(Cell<V>) }
pub fn anchor() -> i32 { return 0; }
"#,
        Vec::new(),
    );
    assert!(unit.generic_calls.is_empty(), "unused definitions still require recipe admission");
    let recipe_row = |catalog: &FrozenCatalog, row: u32| -> [u32; 8] {
        let sidecar = &catalog.native_layout;
        assert!(row < sidecar.recipes.count);
        let first = (sidecar.recipes.offset + row * sidecar.recipes.width) as usize;
        sidecar.words[first..first + 8].try_into().unwrap()
    };
    let valid = frozen_fixture(&unit);
    assert_eq!(valid.native_layout.recipes.count, 3);
    assert_eq!(valid.native_layout.groups.count, 4, "empty enum variants remain ordered groups");
    assert_admitted(&compiler, valid);

    for (corruption, state, detail) in [
        ("stale recipe epoch", 0, 0),
        ("group backlink names another recipe", 2, 165),
        ("payload parameter belongs to another lexical owner", 2, 3),
    ] {
        let mut catalog = frozen_fixture(&unit);
        let packet = Arc::get_mut(&mut catalog).expect("test owns unpublished catalog");
        let records = (0..packet.native_layout.recipes.count)
            .filter(|&row| recipe_row(packet, row)[2] == 1)
            .collect::<Vec<_>>();
        assert_eq!(records.len(), 2);
        let own = recipe_row(packet, records[0]);
        let foreign = recipe_row(packet, records[1]);
        assert_eq!((own[4], foreign[4]), (1, 1));
        assert_ne!(own[1], foreign[1], "separate nominal binder owners");
        let group_word = (packet.native_layout.groups.offset
            + own[3] * packet.native_layout.groups.width) as usize;
        assert_eq!(packet.native_layout.words[group_word], records[0]);
        assert_eq!(packet.native_layout.words[group_word + 2], 1);
        match corruption {
            "stale recipe epoch" => {
                // Keep all physical directories valid and mutate only the
                // wire epoch. Host ownership must not authorize stale bytes.
                Arc::make_mut(&mut packet.native_layout.words)[2] ^= 1;
            }
            "group backlink names another recipe" => {
                Arc::make_mut(&mut packet.native_layout.words)[group_word] = records[1];
            }
            "payload parameter belongs to another lexical owner" => {
                let root = packet.native_layout.words[group_word + 1];
                let own_reference = packet.tables.row(7, root).unwrap().to_vec();
                assert_eq!(own_reference[0], 2, "record field names its own type parameter");
                let foreign_parameter = packet.tables.words[3].chunks_exact(4)
                    .find(|row| row[0] == foreign[1] && row[2] == 0 && row[3] == 0)
                    .expect("other nominal has an admitted type parameter")[1];
                assert_ne!(own_reference[1], foreign_parameter);
                assert_eq!(packet.tables.row(2, own[1]).unwrap()[3], INVALID);
                assert_eq!(packet.tables.row(2, foreign[1]).unwrap()[3], INVALID);
                // All atom and root rows remain shape-valid. Only contextual
                // lexical ownership is wrong, and only the recipe uses this
                // newly copied Root7 row.
                set_catalog_word(packet, 7, root, 1, foreign_parameter);
            }
            _ => unreachable!(),
        }
        let error = match admit_catalog(&compiler, catalog) {
            Ok(_) => panic!("native recipe corruption gained authority: {corruption}"),
            Err(error) => error.to_string(),
        };
        assert!(error.starts_with(&format!(
            "program native recipe GPU admission failed: [{state}, {detail},"
        )), "{corruption}: expected the recipe GPU receipt, not a catalog/build/device/transport failure: {error}");
    }
    assert_admitted(&compiler, frozen_fixture(&unit));
}
