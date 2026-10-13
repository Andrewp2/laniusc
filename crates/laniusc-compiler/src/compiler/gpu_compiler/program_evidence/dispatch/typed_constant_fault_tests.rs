//! Test-only pending-stage faults. Inputs are real compiler facts plus an
//! explicit copied constant recipe; production GPU kernels own all admission,
//! normalization, fitting, matching and publication decisions.
use std::collections::BTreeSet;
use super::*;
use super::super::{catalog::CatalogInput, proof_store::{PROOF_STORE_DIRECTORY, PROOF_STORE_PERSISTENT,
    PROOF_STORE_WIDTHS}};
use crate::compiler::{GpuCompiler, GpuSemanticInterfaceArtifact,
    gpu_compiler::typecheck::OriginalUnitFacts};

const NODES: usize = 0;
const EDGES: usize = 1;
const ROOTS: usize = 2;
const SUBSTITUTIONS: usize = 4;
const BINDINGS: usize = 5;
const REQUESTS: usize = 14;
const ATOM: u32 = 0x8000_0001;
const PROJECTION: u32 = 0x8000_0003;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum FaultKind { DuplicateBindingSpan, OrphanSubstitution, ObserveFold, CorruptFoldedChild,
    ObserveBindingFold, CorruptBindingFoldedChild }
#[derive(Clone)]
struct Observation {
    header: Vec<u32>,
    admitted_rows: Vec<Vec<u32>>,
    completed_serial: u32,
    accepted: [u32; PROOF_STORE_PERSISTENT],
    evidence: Vec<u32>,
    evidence_slice: Slice,
    writes: Vec<ArenaWrite>,
    expected_receipt: [Option<u32>; 4],
    allocated_nodes: u32,
    reachable_nodes: u32,
}
pub(super) struct ConstantAdmissionFault {
    kind: FaultKind,
    literal: Option<[u32; 3]>,
    binding_recipe_seeded: bool,
    observation: Option<Observation>,
}
pub(super) fn needs_normalization_boundary(packet: &GpuPacket) -> bool {
    packet.constant_admission_fault.borrow().as_ref().is_some_and(|fault|
        (matches!(fault.kind, FaultKind::ObserveFold | FaultKind::CorruptFoldedChild)
            && fault.observation.is_none()) || binding_recipe_needed(fault))
}
fn binding_recipe_needed(fault: &ConstantAdmissionFault) -> bool {
    matches!(fault.kind, FaultKind::ObserveBindingFold | FaultKind::CorruptBindingFoldedChild)
        && !fault.binding_recipe_seeded
}
pub(super) fn needs_binding_recipe_boundary(packet: &GpuPacket) -> bool {
    packet.constant_admission_fault.borrow().as_ref().is_some_and(binding_recipe_needed)
}

fn table_words(gpu: &GpuProgramEvidence, packet: &GpuPacket, table: usize,
    rows: u32, width: u32) -> Result<Vec<u32>> {
    if rows == 0 { return Ok(Vec::new()); }
    let slice = packet.packet.proof_store.layout().slices[table];
    let raw = gpu.readback.read_regions(&gpu.device, &gpu.queue, &[
        ReadbackRegion::from_buffer(&packet.proof.buffer, u64::from(slice.offset) * 4,
            arena::byte_len(mul(rows, width, "test table words")?)?, "constant fault table")?
    ], "constant fault table readback")?;
    words(&raw[0])
}
fn observe(gpu: &GpuProgramEvidence, packet: &GpuPacket, layout: &OutputLayout) -> Result<Observation> {
    let evidence_slice = layout.slices[5];
    ensure!(evidence_slice.count != 0, "fault fixture must have observable evidence roots");
    let raw = gpu.readback.read_regions(&gpu.device, &gpu.queue, &[
        ReadbackRegion::from_buffer(&packet.proof.buffer, 0,
            arena::byte_len(PROOF_STORE_FIXED_WORDS)?, "constant fault header")?,
        layout.region(&gpu.storage, &packet.output, 5, Span::new(0, evidence_slice.count)?)?,
    ], "constant fault before admission")?;
    let evidence = words(&raw[1])?;
    let old_obligations = packet.completed_suffix_counts[16] as usize;
    ensure!(old_obligations <= evidence.len() / 8, "previous evidence prefix disappeared");
    ensure!(evidence.chunks_exact(8).skip(old_obligations).all(|row| row[0] == 0),
        "no new root may precede this fault boundary");
    let header = words(&raw[0])?;
    let mut admitted_rows = Vec::with_capacity(PROOF_STORE_PERSISTENT);
    for table in 0..PROOF_STORE_PERSISTENT {
        let count = header[PROOF_STORE_DIRECTORY as usize + table * 6 + 3];
        admitted_rows.push(table_words(gpu, packet, table, count, PROOF_STORE_WIDTHS[table])?);
    }
    Ok(Observation { header, admitted_rows, completed_serial: packet.completed_serial,
        accepted: *packet.packet.proof_store.accepted_prefix(), evidence, evidence_slice,
        writes: Vec::new(), expected_receipt: [None; 4], allocated_nodes: 0, reachable_nodes: 0 })
}
fn upload_fault(gpu: &GpuProgramEvidence, packet: &GpuPacket, writes: &[ArenaWrite]) -> Result<()> {
    if writes.is_empty() { return Ok(()); }
    let mut encoder = gpu.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("constant admission fault upload"),
    });
    packet.proof.upload(&mut encoder, writes)?;
    gpu.queue.submit(Some(encoder.finish()));
    Ok(())
}
fn row_word(packet: &GpuPacket, table: usize, row: u32, width: u32) -> Result<u32> {
    add(packet.packet.proof_store.layout().slices[table].offset,
        mul(row, width, "fault row offset")?, "fault row address")
}

pub(super) fn inject_pending_substitution_fault(gpu: &GpuProgramEvidence, packet: &GpuPacket,
    layout: &OutputLayout, progress: &proof::ProofProgress) -> Result<()> {
    let mut armed = packet.constant_admission_fault.borrow_mut();
    let Some(fault) = armed.as_mut() else { return Ok(()); };
    if fault.observation.is_some() || !matches!(fault.kind,
        FaultKind::DuplicateBindingSpan | FaultKind::OrphanSubstitution |
        FaultKind::ObserveBindingFold | FaultKind::CorruptBindingFoldedChild) { return Ok(()); }
    let pending = progress.pending(SUBSTITUTIONS)?;
    if pending.count == 0 { return Ok(()); }
    let mut observation = observe(gpu, packet, layout)?;
    if fault.kind == FaultKind::DuplicateBindingSpan {
        let binding_span = progress.pending(BINDINGS)?;
        let bindings = table_words(gpu, packet, BINDINGS, progress.reserved[BINDINGS], 8)?;
        let nodes = table_words(gpu, packet, NODES, progress.reserved[NODES], 8)?;
        let mut pair = None;
        for second in binding_span.first..binding_span.first + binding_span.count {
            let b = &bindings[second as usize * 8..second as usize * 8 + 8];
            if b[5] != 1 || b[2] != ATOM { continue; }
            for first in binding_span.first..second {
                let a = &bindings[first as usize * 8..first as usize * 8 + 8];
                if a[5] != 1 || a[2] != ATOM || a[4] == b[4] { continue; }
                let left = &nodes[a[4] as usize * 8..a[4] as usize * 8 + 8];
                let right = &nodes[b[4] as usize * 8..b[4] as usize * 8 + 8];
                if left == right && left[0] == 6 { pair = Some((first, second)); break; }
            }
            if pair.is_some() { break; }
        }
        let Some((first, second)) = pair else { return Ok(()); };
        let a = &bindings[first as usize * 8..first as usize * 8 + 8];
        let mut b = bindings[second as usize * 8..second as usize * 8 + 8].to_vec();
        // Preserve parameter/backlink and allocation totals. Only the root and
        // owned span alias another byte-identical emitted request.
        b[3] = a[3]; b[4] = a[4];
        observation.writes.push(ArenaWrite {
            first_word: row_word(packet, BINDINGS, second, 8)?, words: b,
        });
        observation.expected_receipt = [Some(2), Some(66), Some(NODES as u32), Some(second)];
    } else if fault.kind == FaultKind::OrphanSubstitution {
        let substitutions = table_words(gpu, packet, SUBSTITUTIONS, progress.reserved[SUBSTITUTIONS], 4)?;
        let Some(original) = substitutions.chunks_exact(4).skip(pending.first as usize)
            .find(|row| row[2] == 0) else { return Ok(()); };
        let new_row = progress.reserved[SUBSTITUTIONS];
        ensure!(new_row < packet.packet.proof_store.layout().slices[SUBSTITUTIONS].capacity,
            "orphan fixture requires one spare substitution row");
        observation.writes.push(ArenaWrite {
            first_word: row_word(packet, SUBSTITUTIONS, new_row, 4)?, words: original.to_vec(),
        });
        observation.writes.push(ArenaWrite {
            first_word: PROOF_STORE_DIRECTORY + SUBSTITUTIONS as u32 * 6 + 1,
            words: vec![add(new_row, 1, "orphan reserved suffix")?],
        });
        let uncovered_word = pending.first + (new_row - pending.first) / 32 * 32;
        observation.expected_receipt = [Some(2), Some(66), Some(SUBSTITUTIONS as u32), Some(uncovered_word)];
    } else {
        ensure!(fault.binding_recipe_seeded, "binding fold ABI recipe was not installed");
        let binding_span = progress.pending(BINDINGS)?;
        let bindings = table_words(gpu, packet, BINDINGS, progress.reserved[BINDINGS], 8)?;
        let nodes = table_words(gpu, packet, NODES, progress.reserved[NODES], 8)?;
        let edges = table_words(gpu, packet, EDGES, progress.reserved[EDGES], 2)?;
        let literal = fault.literal.expect("binding ABI fixture retains copied literal bits");
        let expected_node = [6, literal[0], literal[1], literal[2], 0, 0, 0, 0];
        let binding = bindings.chunks_exact(8).skip(binding_span.first as usize)
            .take(binding_span.count as usize).find(|row| row[5] == 2 && row[2] == ATOM);
        let Some(binding) = binding else { return Ok(()); };
        let first = binding[4];
        ensure!(binding[3] == first && binding[6..8] == [0, 0], "unexpected folded Binding8 shape");
        for row in first..first + 2 {
            ensure!(nodes[row as usize * 8..row as usize * 8 + 8] == expected_node,
                "binding fixture did not emit the copied literal at every target");
        }
        let reachable = reachable_nodes([binding[2], binding[3]], &nodes, &edges);
        let owned_reachable = reachable.iter().filter(|&&row| row >= first && row - first < 2).count() as u32;
        ensure!(owned_reachable == 1 && !reachable.contains(&(first + 1)),
            "binding fixture must own an unreachable inner folded target");
        observation.allocated_nodes = 2;
        observation.reachable_nodes = owned_reachable;
        if fault.kind == FaultKind::CorruptBindingFoldedChild {
            let child = first + 1;
            let mut corrupted = expected_node.to_vec();
            corrupted[2] ^= 1; // Shape/scalar stay intact; replay must compare these bits.
            observation.writes.push(ArenaWrite {
                first_word: row_word(packet, NODES, child, 8)?, words: corrupted,
            });
            observation.expected_receipt = [Some(2), Some(68), Some(binding[1]), Some(child)];
        }
    }
    upload_fault(gpu, packet, &observation.writes)?;
    fault.observation = Some(observation);
    Ok(())
}

// Shape-only test inspection of already-emitted rows. This neither evaluates
// constants nor supplies any result to the GPU validators or host receipt API.
fn reachable_nodes(root: [u32; 2], nodes: &[u32], edges: &[u32]) -> BTreeSet<u32> {
    let mut seen = BTreeSet::new();
    let mut todo = vec![root];
    while let Some([tag, payload]) = todo.pop() {
        if !matches!(tag, 3 | ATOM | PROJECTION) { continue; }
        if !seen.insert(payload) { continue; }
        assert!(seen.len() <= 65_536, "test shape walk exceeded bound");
        let row = &nodes[payload as usize * 8..payload as usize * 8 + 8];
        match row[0] {
            1 => for edge in row[2]..row[2] + row[3] {
                todo.push(edges[edge as usize * 2..edge as usize * 2 + 2].try_into().unwrap());
            },
            2 => { todo.push([row[4], row[5]]); todo.push([row[6], row[7]]); }
            3..=5 => todo.push([row[4], row[5]]),
            6 => (),
            kind => panic!("unexpected emitted node kind {kind}"),
        }
    }
    seen
}

pub(super) fn inspect_pending_normalization(gpu: &GpuProgramEvidence, packet: &GpuPacket,
    layout: &OutputLayout, progress: &proof::ProofProgress) -> Result<()> {
    let mut armed = packet.constant_admission_fault.borrow_mut();
    let Some(fault) = armed.as_mut() else { return Ok(()); };
    if fault.observation.is_some() { return Ok(()); }
    let pending = progress.pending(REQUESTS)?;
    if pending.count == 0 { return Ok(()); }
    let requests = table_words(gpu, packet, REQUESTS, progress.reserved[REQUESTS], 8)?;
    let roots = table_words(gpu, packet, ROOTS, progress.reserved[ROOTS], 2)?;
    let nodes = table_words(gpu, packet, NODES, progress.reserved[NODES], 8)?;
    let edges = table_words(gpu, packet, EDGES, progress.reserved[EDGES], 2)?;
    let works = table_words(gpu, packet, proof::WORK, progress.admitted[proof::WORK], 16)?;
    let literal = fault.literal.expect("fold fixture retained the copied literal bits");
    for request in requests.chunks_exact(8).skip(pending.first as usize) {
        let root: [u32; 2] = roots[request[2] as usize * 2..request[2] as usize * 2 + 2].try_into()?;
        let reachable = reachable_nodes(root, &nodes, &edges);
        let owned_reachable = reachable.iter().filter(|&&row|
            row >= request[3] && row - request[3] < request[4]).count() as u32;
        if owned_reachable >= request[4] { continue; }
        let child = (request[3]..request[3] + request[4]).find(|row| {
            let node = &nodes[*row as usize * 8..*row as usize * 8 + 8];
            !reachable.contains(row) && node[0] == 6 && node[1..4] == literal
        });
        let Some(child) = child else { continue; };
        let mut observation = observe(gpu, packet, layout)?;
        observation.allocated_nodes = request[4];
        observation.reachable_nodes = owned_reachable;
        if fault.kind == FaultKind::CorruptFoldedChild {
            let mut corrupted = nodes[child as usize * 8..child as usize * 8 + 8].to_vec();
            corrupted[2] ^= 1; // Preserve shape/scalar; exact replay must detect the changed low bits.
            observation.writes.push(ArenaWrite {
                first_word: row_word(packet, NODES, child, 8)?, words: corrupted,
            });
            let work = &works[request[0] as usize * 16..request[0] as usize * 16 + 16];
            let predicate = combined_row(&packet.packet, 8, work[13]);
            let input_root = if request[1] == 0 { predicate[3] }
                else { predicate[4] + request[1] - 1 };
            let input = combined_row(&packet.packet, 7, input_root);
            observation.expected_receipt = [Some(2), Some(1), Some(input[1]), Some(child)];
        }
        upload_fault(gpu, packet, &observation.writes)?;
        fault.observation = Some(observation);
        break;
    }
    Ok(())
}

// Targeted consumer-ABI fixture, deliberately outside normal producer
// provenance: production normalization would canonicalize both projections.
// After phase 45 has admitted its exact rows, restore the copied projection
// recipe in that fixture before phase 46 hashes/admit-checks the pending goal.
// Real phases 46/47 and 53/54/55 still own semantic validation and publication.
// The host copies shape/scalar/limbs; it never computes fitting or a result.
pub(super) fn seed_binding_projection_recipe(gpu: &GpuProgramEvidence, packet: &GpuPacket,
    progress: &proof::ProofProgress, work: Span) -> Result<()> {
    let mut armed = packet.constant_admission_fault.borrow_mut();
    let fault = armed.as_mut().expect("binding ABI fixture must be armed");
    ensure!(binding_recipe_needed(fault), "binding ABI fixture seeded twice");
    let literal = fault.literal.expect("binding ABI fixture retains copied literal bits");
    let requests = table_words(gpu, packet, REQUESTS, progress.admitted[REQUESTS], 8)?;
    let roots = table_words(gpu, packet, ROOTS, progress.admitted[ROOTS], 2)?;
    let nodes = table_words(gpu, packet, NODES, progress.admitted[NODES], 8)?;
    let expected_node = [6, literal[0], literal[1], literal[2], 0, 0, 0, 0];
    for request in requests.chunks_exact(8) {
        if request[0] < work.first || request[0] - work.first >= work.count ||
            request[1] != 1 || request[4] != 4 || request[7] != 1 { continue; }
        let base = request[3];
        ensure!(roots[request[2] as usize * 2..request[2] as usize * 2 + 2] == [3, base],
            "binding ABI fixture root must own one array preorder");
        let mut array = nodes[base as usize * 8..base as usize * 8 + 8].to_vec();
        ensure!(array[0..4] == [2, 0, 0, 0] && array[4] == 1 &&
            array[6..8] == [ATOM, base + 1], "binding ABI fixture must have a folded array count");
        for row in base + 1..base + 4 {
            ensure!(nodes[row as usize * 8..row as usize * 8 + 8] == expected_node,
                "binding ABI fixture requires three byte-identical copied literal nodes");
        }
        array[6] = PROJECTION;
        let writes = [
            ArenaWrite { first_word: row_word(packet, NODES, base, 8)?, words: array },
            ArenaWrite { first_word: row_word(packet, NODES, base + 1, 8)?,
                words: vec![5, literal[0], 0, 0, PROJECTION, base + 2, 0, 0] },
            ArenaWrite { first_word: row_word(packet, NODES, base + 2, 8)?,
                words: vec![5, literal[0], 0, 0, ATOM, base + 3, 0, 0] },
        ];
        upload_fault(gpu, packet, &writes)?;
        fault.binding_recipe_seeded = true;
        return Ok(());
    }
    anyhow::bail!("binding ABI fixture did not reach its exact four-row normalized array shape")
}

fn facts(compiler: &GpuCompiler<'_>, key: [u32; 2], source: &str) -> OriginalUnitFacts {
    pollster::block_on(compiler.compile_pending_original_source_pack_unit(
        vec![source.to_owned()].into(), key[0], key[1],
        Vec::<Vec<GpuSemanticInterfaceArtifact>>::new().into(), None,
    )).expect("compile original facts before program implementation selection").facts().clone()
}
fn append_originals(packet: &mut GpuPacket) {
    let facts = packet.packet.catalog.snapshots.iter()
        .map(|snapshot| snapshot.original_facts.clone()).collect::<Vec<_>>();
    for facts in facts { packet.packet_mut().unwrap().append_original_unit_calls(&facts).unwrap(); }
}
fn job(compiler: &GpuCompiler<'_>, facts: &OriginalUnitFacts) -> (GpuProgramEvidence, GpuPacket) {
    let catalog = FrozenCatalog::freeze(&[CatalogInput { facts }]).unwrap();
    let gpu = GpuProgramEvidence::admit(compiler.program_evidence_workspace.checkout(), catalog).unwrap();
    let mut packet = gpu.new_packet().unwrap();
    append_originals(&mut packet);
    (gpu, packet)
}
fn combined_row(packet: &ProgramPacket, table: usize, row: u32) -> Vec<u32> {
    let prefix = packet.catalog.tables.count(table).unwrap();
    if row < prefix { packet.catalog.tables.row(table, row) }
    else { packet.tables.row(table, row - prefix) }.unwrap().to_vec()
}
fn wrap_literal_environment(packet: &mut GpuPacket) -> [u32; 3] {
    wrap_literal_environment_with_depth(packet, 1)
}
fn wrap_literal_environment_with_depth(packet: &mut GpuPacket, depth: u32) -> [u32; 3] {
    assert!(matches!(depth, 1 | 2));
    let packet = packet.packet_mut().unwrap();
    for binding in 0..packet.tables.count(12).unwrap() {
        let row = packet.tables.row(12, binding).unwrap().to_vec();
        let reference = combined_row(packet, 7, row[2]);
        if reference[0] != ATOM { continue; }
        let parameter = combined_row(packet, 1, row[1]);
        let literal = combined_row(packet, 1, reference[1]);
        if parameter[0] != 5 || parameter[2] != 1 || literal[0] != 12 { continue; }
        let target = parameter[4];
        assert_eq!(target, literal[1], "copy the already-declared literal scalar");
        let mut child = [reference[0], reference[1]];
        for _ in 0..depth {
            let node = packet.catalog.tables.count(5).unwrap() + packet.tables.count(5).unwrap();
            packet.tables.push(5, &[5, target, 0, 0, child[0], child[1], 0, 0]).unwrap();
            child = [PROJECTION, node];
        }
        let root = packet.catalog.tables.count(7).unwrap() + packet.tables.count(7).unwrap();
        packet.tables.push(7, &child).unwrap();
        packet.tables.row_mut(12, binding).unwrap()[2] = root;
        // The literal atom and both limbs remain byte-for-byte unchanged.
        assert_eq!(combined_row(packet, 1, reference[1]), literal);
        return literal[1..4].try_into().unwrap();
    }
    panic!("fold fixture needs a literal constant environment binding");
}

fn assert_failed_prefixes(gpu: &GpuProgramEvidence, packet: &GpuPacket,
    error: &anyhow::Error, observation: &Observation) {
    let failure = error.downcast_ref::<EvidenceDispatchFailure>().expect("owned GPU admission receipt");
    assert_eq!(failure.catalog[0], 1, "fault did not affect catalog admission");
    for (field, expected) in observation.expected_receipt.iter().enumerate() {
        if let Some(value) = expected { assert_eq!(failure.receipt[field], *value, "receipt={:?}", failure.receipt); }
    }
    let raw = gpu.readback.read_regions(&gpu.device, &gpu.queue, &[
        ReadbackRegion::from_buffer(&packet.proof.buffer, 0,
            arena::byte_len(PROOF_STORE_FIXED_WORDS).unwrap(), "failed constant directory").unwrap(),
        ReadbackRegion::from_buffer(&packet.output.buffer, u64::from(observation.evidence_slice.offset) * 4,
            arena::byte_len(observation.evidence_slice.count * 8).unwrap(), "failed constant evidence").unwrap(),
    ], "constant fault after rejection").unwrap();
    let after = words(&raw[0]).unwrap();
    // Stage 45 also publishes the transient normalization-request prefix.
    // Check all affected admitted counts, including that nonpersistent table.
    for table in (0..PROOF_STORE_PERSISTENT).chain(std::iter::once(REQUESTS)) {
        let base = PROOF_STORE_DIRECTORY as usize + table * 6;
        assert_eq!(after[base + 3], observation.header[base + 3], "table {table} admitted prefix advanced");
        assert_eq!(after[base + 4], observation.header[base + 4], "table {table} accepted prefix advanced");
    }
    for table in 0..PROOF_STORE_PERSISTENT {
        let count = observation.header[PROOF_STORE_DIRECTORY as usize + table * 6 + 3];
        assert_eq!(table_words(gpu, packet, table, count, PROOF_STORE_WIDTHS[table]).unwrap(),
            observation.admitted_rows[table], "table {table} admitted row contents changed");
    }
    assert_eq!(after[7], observation.header[7], "accepted serial advanced");
    assert_ne!(after[10], 1);
    assert_eq!(words(&raw[1]).unwrap(), observation.evidence, "evidence root escaped");
    for write in &observation.writes {
        let raw = gpu.readback.read_regions(&gpu.device, &gpu.queue, &[
            ReadbackRegion::from_buffer(&packet.proof.buffer, u64::from(write.first_word) * 4,
                arena::byte_len(write.words.len() as u32).unwrap(), "persisted constant fault").unwrap(),
        ], "verify injected bytes persist").unwrap();
        assert_eq!(words(&raw[0]).unwrap(), write.words, "fault did not reach the GPU");
    }
    assert_eq!(failure.receipt[6], observation.completed_serial + 1, "failure receipt is stale");
    assert_eq!(packet.completed_serial, observation.completed_serial);
    assert_eq!(packet.packet.proof_store.accepted_prefix(), &observation.accepted);
    assert!(packet.poisoned);
}
fn arm(packet: &GpuPacket, kind: FaultKind, literal: Option<[u32; 3]>) {
    *packet.constant_admission_fault.borrow_mut() = Some(ConstantAdmissionFault {
        kind, literal, binding_recipe_seeded: false, observation: None });
}
fn observation(packet: &GpuPacket) -> Observation {
    packet.constant_admission_fault.borrow().as_ref().unwrap().observation.clone()
        .expect("fixture reached the requested pending-stage shape; no vacuous fault test")
}

// Read by logical table and row count, because the next append may relocate
// storage. This observes transport bytes and never interprets constant values.
fn output_words(gpu: &GpuProgramEvidence, packet: &GpuPacket, table: usize,
    rows: u32) -> Result<Vec<u32>> {
    if rows == 0 { return Ok(Vec::new()); }
    let first = OUTPUT_DIRECTORY_WORD + table as u32 * 5;
    let raw = gpu.readback.read_regions(&gpu.device, &gpu.queue, &[
        ReadbackRegion::from_buffer(&packet.input.buffer, u64::from(first) * 4, 20,
            "retained result directory")?,
    ], "retained result location")?;
    let directory = words(&raw[0])?;
    ensure!(directory.len() == 5 && directory[0] == 1 && rows <= directory[2]
        && directory[4] == OUTPUT_WIDTHS[table], "retained result range changed");
    let raw = gpu.readback.read_regions(&gpu.device, &gpu.queue, &[
        ReadbackRegion::from_buffer(&packet.output.buffer, u64::from(directory[1]) * 4,
            arena::byte_len(mul(rows, directory[4], "retained result words")?)?,
            "retained result rows")?,
    ], "retained result contents")?;
    words(&raw[0])
}

struct AcceptedSnapshot {
    serial: u32,
    counts: [u32; PROOF_STORE_PERSISTENT],
    rows: Vec<Vec<u32>>,
    results: Vec<(usize, u32, Vec<u32>)>,
    evidence_inputs: Vec<Vec<u32>>,
    receipt: Vec<u32>,
}
fn accepted_snapshot(gpu: &GpuProgramEvidence, packet: &GpuPacket) -> AcceptedSnapshot {
    assert!(!packet.poisoned);
    assert!(packet.completed_serial != 0);
    let counts = *packet.packet.proof_store.accepted_prefix();
    // The first submission must retain real constant terms and bindings, as
    // well as a proof and goal; an empty accepted arena is not this fixture.
    for table in [NODES, 3, SUBSTITUTIONS, BINDINGS, 6] {
        assert!(counts[table] != 0, "accepted fixture has no table {table} rows");
    }
    let rows = (0..PROOF_STORE_PERSISTENT).map(|table|
        table_words(gpu, packet, table, counts[table], PROOF_STORE_WIDTHS[table]).unwrap()).collect();
    let results = [(2, 13), (3, 16), (4, 15), (5, 16)].into_iter().map(|(output, input)| {
        let count = packet.completed_suffix_counts[input];
        assert!(count != 0, "accepted fixture has no output {output} rows");
        (output, count, output_words(gpu, packet, output, count).unwrap())
    }).collect();
    let evidence_inputs = (0..packet.packet.tables.count(17).unwrap()).map(|row|
        packet.packet.tables.row(17, row).unwrap().to_vec()).collect::<Vec<_>>();
    assert!(!evidence_inputs.is_empty());
    let receipt = output_words(gpu, packet, 10, 1).unwrap();
    assert_eq!(receipt[0], 1);
    assert_eq!(receipt[6], packet.completed_serial);
    AcceptedSnapshot { serial: packet.completed_serial, counts, rows, results, evidence_inputs, receipt }
}
fn assert_accepted_snapshot(gpu: &GpuProgramEvidence, packet: &GpuPacket,
    error: &anyhow::Error, before: &AcceptedSnapshot) {
    assert_eq!(packet.completed_serial, before.serial);
    assert_eq!(packet.packet.proof_store.accepted_prefix(), &before.counts);
    for table in 0..PROOF_STORE_PERSISTENT {
        assert_eq!(table_words(gpu, packet, table, before.counts[table], PROOF_STORE_WIDTHS[table]).unwrap(),
            before.rows[table], "previous accepted table {table} bytes changed during append");
    }
    for (table, count, rows) in &before.results {
        assert_eq!(&output_words(gpu, packet, *table, *count).unwrap(), rows,
            "previous accepted output {table} receipt/root changed during append");
    }
    assert_eq!(packet.packet.tables.count(17).unwrap() as usize, before.evidence_inputs.len());
    for (row, expected) in before.evidence_inputs.iter().enumerate() {
        assert_eq!(packet.packet.tables.row(17, row as u32).unwrap(), expected,
            "retained host evidence input changed during failed append");
    }
    let failure = error.downcast_ref::<EvidenceDispatchFailure>().unwrap();
    let receipt = output_words(gpu, packet, 10, 1).unwrap();
    assert_eq!(receipt.as_slice(), failure.receipt.as_slice());
    assert_ne!(receipt, before.receipt, "append reused the earlier successful receipt");
    assert_eq!(receipt[6], before.serial + 1);
    assert_ne!(receipt[0], 1);
}

const PAIR: &str = r#"
module constant_faults::pair;
pub trait Pair<A,B> {}
pub impl<const N:u8,const M:u8> Pair<[i32;N],[i32;M]> for bool {}
pub fn require<T>()->i32 where T:Pair<[i32;3],[i32;3]> { return 0; }
fn main()->i32 { return require<bool>(); }
"#;
const MARKER: &str = r#"
module constant_faults::marker;
pub trait Mark {}
pub impl Mark for bool {}
pub fn require<T>()->i32 where T:Mark { return 0; }
fn main()->i32 { return require<bool>(); }
"#;
const FOLDED: &str = r#"
module constant_faults::folded;
pub trait Rel<A> {}
pub impl<const N:u8> Rel<[i32;N]> for bool {}
pub fn require<const N:u8>(a:[i32;N])->i32 where bool:Rel<[i32;N]> { return 0; }
fn main()->i32 { return require([1,2,3]); }
"#;

#[test]
fn gpu_rejects_duplicate_equal_binding_spans_before_publication() {
    let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
    let facts = facts(&compiler, [191, 0], PAIR);
    let (mut gpu, mut control) = job(&compiler, &facts);
    assert!(!gpu.check(&mut control).expect("valid equal binding requests").is_empty());
    let mut packet = gpu.new_packet().unwrap(); append_originals(&mut packet);
    arm(&packet, FaultKind::DuplicateBindingSpan, None);
    let error = gpu.check(&mut packet).expect_err("aliased binding allocations must fail");
    assert_failed_prefixes(&gpu, &packet, &error, &observation(&packet));
    assert!(packet.packet_mut().is_err());
}
#[test]
fn gpu_rejects_orphan_substitution_before_publication() {
    let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
    let facts = facts(&compiler, [191, 1], MARKER);
    let (mut gpu, mut control) = job(&compiler, &facts);
    assert!(!gpu.check(&mut control).expect("valid zero-binding substitution").is_empty());
    let mut packet = gpu.new_packet().unwrap(); append_originals(&mut packet);
    arm(&packet, FaultKind::OrphanSubstitution, None);
    let error = gpu.check(&mut packet).expect_err("unowned substitution must fail");
    assert_failed_prefixes(&gpu, &packet, &error, &observation(&packet));
    assert!(packet.packet_mut().is_err());
}
#[test]
fn gpu_validates_folded_projection_allocations_including_unreachable_child() {
    let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
    let facts = facts(&compiler, [191, 2], FOLDED);
    let (mut gpu, mut control) = job(&compiler, &facts);
    let literal = wrap_literal_environment(&mut control);
    arm(&control, FaultKind::ObserveFold, Some(literal));
    assert!(!gpu.check(&mut control).expect("valid projection must fold and publish").is_empty());
    let valid = observation(&control);
    assert!(valid.allocated_nodes > valid.reachable_nodes, "control must exercise a folded orphan allocation");
    assert_eq!(control.completed_serial, 1);
    let mut packet = gpu.new_packet().unwrap(); append_originals(&mut packet);
    assert_eq!(wrap_literal_environment(&mut packet), literal);
    arm(&packet, FaultKind::CorruptFoldedChild, Some(literal));
    let error = gpu.check(&mut packet).expect_err("unreachable allocated child still needs exact replay");
    let corrupted = observation(&packet);
    assert!(corrupted.allocated_nodes > corrupted.reachable_nodes);
    assert_failed_prefixes(&gpu, &packet, &error, &corrupted);
    assert!(packet.packet_mut().is_err());
}

#[test]
fn gpu_binding_abi_replays_unreachable_folded_allocation_before_publication() {
    let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
    let facts = facts(&compiler, [192, 2], FOLDED);
    let (mut gpu, mut control) = job(&compiler, &facts);
    let literal = wrap_literal_environment_with_depth(&mut control, 2);
    arm(&control, FaultKind::ObserveBindingFold, Some(literal));
    assert!(!gpu.check(&mut control).expect("valid admitted projection ABI fixture").is_empty());
    let valid = observation(&control);
    assert_eq!((valid.allocated_nodes, valid.reachable_nodes), (2, 1));
    assert_eq!(control.completed_serial, 1);

    let mut packet = gpu.new_packet().unwrap(); append_originals(&mut packet);
    assert_eq!(wrap_literal_environment_with_depth(&mut packet, 2), literal);
    arm(&packet, FaultKind::CorruptBindingFoldedChild, Some(literal));
    let error = gpu.check(&mut packet).expect_err("stage 54 must replay the unreachable owned binding row");
    let corrupted = observation(&packet);
    assert_eq!((corrupted.allocated_nodes, corrupted.reachable_nodes), (2, 1));
    assert_failed_prefixes(&gpu, &packet, &error, &corrupted);
    assert!(packet.packet_mut().is_err());
}

#[test]
fn gpu_rejected_append_preserves_accepted_constant_rows_and_receipts() {
    let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
    let first = facts(&compiler, [192, 0], PAIR);
    let appended = facts(&compiler, [192, 1], MARKER);
    let catalog = FrozenCatalog::freeze(&[CatalogInput { facts: &first },
        CatalogInput { facts: &appended }]).unwrap();
    let mut gpu = GpuProgramEvidence::admit(
        compiler.program_evidence_workspace.checkout(), catalog).unwrap();

    // A complete two-submission control establishes that appending the second
    // inventory is valid without any injected pending-store fault.
    let mut control = gpu.new_packet().unwrap();
    control.packet_mut().unwrap().append_original_unit_calls(&first).unwrap();
    assert!(!gpu.check(&mut control).expect("first accepted constant proof").is_empty());
    control.packet_mut().unwrap().append_original_unit_calls(&appended).unwrap();
    assert!(!gpu.check(&mut control).expect("valid appended marker proof").is_empty());
    assert_eq!(control.completed_serial, 2);

    let mut packet = gpu.new_packet().unwrap();
    packet.packet_mut().unwrap().append_original_unit_calls(&first).unwrap();
    assert!(!gpu.check(&mut packet).expect("accepted prefix before failed append").is_empty());
    let before = accepted_snapshot(&gpu, &packet);
    packet.packet_mut().unwrap().append_original_unit_calls(&appended).unwrap();
    arm(&packet, FaultKind::OrphanSubstitution, None);
    let error = gpu.check(&mut packet).expect_err("appended orphan substitution must fail");
    let fault = observation(&packet);
    assert_eq!(fault.completed_serial, before.serial);
    assert_failed_prefixes(&gpu, &packet, &error, &fault);
    assert_accepted_snapshot(&gpu, &packet, &error, &before);
    assert!(packet.packet_mut().is_err());
}
