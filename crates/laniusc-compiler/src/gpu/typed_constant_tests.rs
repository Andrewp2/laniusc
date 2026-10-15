//! Focused physical GPU execution of typed identity, owned inference and exact
//! allocation coverage. Rust supplies expected outcomes, never constant fitting
//! or an implementation of the production graph algorithms.
use super::{
    buffers::{readback_bytes, storage_rw_for_array},
    device,
    passes_core::{self, make_pass_data_from_shader_key, map_readback_blocking},
};

/// u32 words of a thread-scratch table holding `slots` slots: whole groups of
/// THREAD_SCRATCH_GROUP slots of THREAD_SCRATCH_CELLS uint4 cells.
pub(super) fn thread_scratch_words(slots: usize) -> usize {
    slots.div_ceil(32) * 32 * 1808 * 4
}

fn run_rows(key: &str, binding: &str, rows: usize, threads: u32) -> Vec<[u32; 4]> {
    assert!(!super::env::env_bool_truthy("LANIUS_ALLOW_SOFTWARE_ADAPTER", false),
        "this regression requires a physical GPU");
    let gpu = device::global();
    let word_count = rows * 4;
    let results = storage_rw_for_array::<u32>(&gpu.device, key, word_count);
    let pass = make_pass_data_from_shader_key(&gpu.device, key, "main", key).unwrap();
    assert_eq!(pass.thread_group_size, [threads, 1, 1]);
    // One thread-scratch slot per row (shaders/thread_scratch.slang).
    let scratch = storage_rw_for_array::<u32>(&gpu.device, "typed_constants.thread_scratch",
        thread_scratch_words(rows));
    // A probe that reaches the program-evidence abi (through a module it
    // tests) declares the abi's parameter block and tables. The probes never
    // read them; zeroed placeholders satisfy the exact binding contract.
    let evidence_params = gpu.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("typed_constants.evidence_params"),
        size: 32,
        usage: wgpu::BufferUsages::UNIFORM,
        mapped_at_creation: false,
    });
    let evidence_tables = ["program_evidence_catalog", "program_evidence_batch", "program_evidence_output"]
        .map(|name| (name, storage_rw_for_array::<u32>(&gpu.device, name, 4)));
    let mut entries = vec![(binding, results.as_entire_binding())];
    if passes_core::bind_group::declares_binding(&pass, 0, "thread_scratch") {
        entries.push(("thread_scratch", scratch.as_entire_binding()));
    }
    if passes_core::bind_group::declares_binding(&pass, 0, "program_evidence_params") {
        entries.push(("program_evidence_params", evidence_params.as_entire_binding()));
    }
    for (name, table) in &evidence_tables {
        if passes_core::bind_group::declares_binding(&pass, 0, name) {
            entries.push((*name, table.as_entire_binding()));
        }
    }
    passes_core::bind_group::validate_exact_binding_names(&pass, 0, &entries).unwrap();
    let group = passes_core::bind_group::create_bind_group_from_bindings(
        &gpu.device, Some(key), &pass, 0, &entries).unwrap();
    let readback = readback_bytes(&gpu.device, key, word_count * 4, word_count);
    let mut encoder = gpu.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some(key),
    });
    {
        let mut compute = passes_core::begin_counted_compute_pass(&mut encoder,
            &wgpu::ComputePassDescriptor { label: Some(key), timestamp_writes: None });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, Some(&group), &[]);
        passes_core::record_compute_dispatch();
        if !crate::gpu::passes_core::debug_operation_skipped() {
            compute.dispatch_workgroups((rows as u32).div_ceil(threads), 1, 1);
        }
    }
    results.copy_to(&mut encoder, 0, &readback, 0, (word_count * 4) as u64);
    gpu.queue.submit(Some(encoder.finish()));
    let slice = readback.slice(..);
    map_readback_blocking(&gpu.device, &slice, key).unwrap();
    let mapped = slice.get_mapped_range();
    let words: Vec<u32> = mapped.chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap())).collect();
    drop(mapped);
    readback.unmap();
    assert_eq!(words.len(), word_count);
    words.chunks_exact(4).map(|row| row.try_into().unwrap()).collect()
}

/// The scoped and concrete walkers and constant-reference identity on the
/// synthetic graphs of typed_constant_identity_fixture.slang. Cases 22-41 and
/// 44-63 tested the deleted inference engine (constant_constraints.slang);
/// call claims now go through ct_match and the checked claim kernels
/// (constant_claim_publication_tests.rs, ct_match_tests.rs).
fn assert_typed_constant_identity_family(key: &str, cases: &[usize]) {
    // Hash inequality is not required: different typed values may collide.
    // Hash validity and equal-value hash agreement are required independently.
    let mut expected = [([1, 1, 1], Some(1)); 64];
    for id in [1, 2, 11, 17, 18] { expected[id] = ([0, 1, 1], None); }
    for id in [4, 5, 10, 12, 13, 14, 15] { expected[id] = ([0, 0, 0], None); }
    expected[9] = ([0, 0, 1], None);
    expected[20] = ([1, 2, 1], Some(1)); // symbolic, pending fit
    expected[21] = ([1, 1, 0], Some(1)); // concrete, discharged fit
    let actual = run_rows(key, "results", 64, 64);
    for &id in cases {
        let row = actual[id];
        let (prefix, last) = expected[id];
        assert_eq!(row[..3], prefix, "typed identity case {id} in {key}: {row:?}");
        if let Some(last) = last {
            assert_eq!(row[3], last, "typed identity case {id} in {key}: {row:?}");
        }
    }
}

#[test]
fn physical_gpu_typed_constant_identity_and_claim_provenance_graph() {
    assert_typed_constant_identity_family("tests/typed_constant_identity_graph", &[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]);
}

#[test]
fn physical_gpu_typed_constant_identity_and_claim_provenance_scoped() {
    assert_typed_constant_identity_family("tests/typed_constant_identity_scoped", &[20, 21]);
}

#[test]
fn physical_gpu_typed_constant_identity_and_claim_provenance_depth() {
    assert_typed_constant_identity_family("tests/typed_constant_identity_depth", &[42, 43]);
}

const CHECKED_IDENTITY: &str = "tests/checked_type_identity";
const CHECKED_IDENTITY_CHECKS: usize = 50;

/// The identity cases above on canonical IDs (checked_type_identity.slang):
/// typed constant identity, folded and symbolic casts, count-class array
/// identity, closure and the walkers' operand admission. The shader interns
/// its own constants through the production key builders.
#[test]
fn physical_gpu_checked_type_identity_by_canonical_id() {
    assert!(!super::env::env_bool_truthy("LANIUS_ALLOW_SOFTWARE_ADAPTER", false),
        "this regression requires a physical GPU");
    let gpu = device::global();
    let (device, queue) = (&gpu.device, &gpu.queue);
    let key = CHECKED_IDENTITY;
    let pass = make_pass_data_from_shader_key(device, key, "main", key).unwrap();
    let buffers: Vec<_> = [
        ("ct_head", 1024 * 4),
        ("ct_meta", 1024 * 4),
        ("ct_extra", 1024 * 2),
        ("ct_args", 4096),
        ("ct_slot", 4096),
        ("ct_counts", 16),
        ("canonical_row", 16),
        ("canonical_atom", 16),
        ("canonical_projection", 16),
        ("canonical_dependency_type", 16),
        ("identity_errors", 4 + CHECKED_IDENTITY_CHECKS),
    ]
    .into_iter()
    .map(|(name, words)| (name, storage_rw_for_array::<u32>(device, name, words)))
    .collect();
    let entries: Vec<_> = buffers.iter().map(|(name, buffer)| (*name, buffer.as_entire_binding())).collect();
    passes_core::bind_group::validate_exact_binding_names(&pass, 0, &entries).unwrap();
    let group = passes_core::bind_group::create_bind_group_from_bindings(
        device, Some(key), &pass, 0, &entries).unwrap();
    let slots = &buffers.iter().find(|(name, _)| *name == "ct_slot").unwrap().1;
    let errors = &buffers.iter().find(|(name, _)| *name == "identity_errors").unwrap().1;
    let words = 4 + CHECKED_IDENTITY_CHECKS;
    let readback = readback_bytes(device, key, words * 4, words);
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(key) });
    encoder.clear_buffer(slots, 0, None);
    encoder.clear_buffer(errors, 0, None);
    {
        let mut compute = passes_core::begin_counted_compute_pass(&mut encoder,
            &wgpu::ComputePassDescriptor { label: Some(key), timestamp_writes: None });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, Some(&group), &[]);
        passes_core::record_compute_dispatch();
        if !crate::gpu::passes_core::debug_operation_skipped() {
            compute.dispatch_workgroups(1, 1, 1);
        }
    }
    errors.copy_to(&mut encoder, 0, &readback, 0, (words * 4) as u64);
    queue.submit(Some(encoder.finish()));
    let slice = readback.slice(..);
    map_readback_blocking(device, &slice, key).unwrap();
    let mapped = slice.get_mapped_range();
    let errors: Vec<u32> = mapped.chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap())).collect();
    drop(mapped);
    readback.unmap();
    let failed: Vec<_> = (0..CHECKED_IDENTITY_CHECKS)
        .filter(|check| errors[check / 32] & (1 << (check % 32)) != 0)
        .map(|check| format!("check {check}: {:#x}", errors[4 + check]))
        .collect();
    assert!(failed.is_empty(), "checked type identity failed: {}", failed.join(", "));
}

fn assert_owned(key: &str, expected: &[u32], threads: u32) {
    for (id, (row, &state)) in run_rows(key, "results", expected.len(), threads)
        .iter().zip(expected).enumerate()
    {
        assert_eq!(row[0], state, "{key} case {id}: {row:?}");
        assert_eq!(row[1], state, "{key} case {id}: shader/host expected state differs");
        assert_eq!(row[2], 1, "{key} case {id}: request/fit invariant failed: {row:?}");
    }
}
#[test]
fn physical_gpu_typed_owned_constant_matching() {
    assert_owned("tests/owned_typed_constants_match", &[1, 2, 2, 1, 1, 2, 2, 1, 2, 1, 1, 1], 16);
}
#[test]
fn physical_gpu_typed_owned_constant_overlap() {
    // Final case captures a compound type with a projected count, then revisits
    // the binding against the equivalent unprojected rigid count.
    assert_owned("tests/owned_typed_constants_overlap", &[2, 1, 1, 2, 1, 2, 1, 2, 1, 2, 2, 3, 1], 16);
}
#[test]
fn physical_gpu_typed_owned_constant_parameter_coverage() {
    assert_owned("tests/owned_typed_constants_coverage", &[1, 3, 1, 3], 4);
}
#[test]
fn physical_gpu_proof_span_exact_coverage() {
    let expected = [1, 1, 2, 1, 1, 2, 2, 2, 2, 2, 2, 2, 1, 2, 1, 1, 2, 3, 1, 3, 1, 2, 3, 2];
    for (id, (row, state)) in run_rows("tests/proof_span_coverage_probe", "coverage_results", 24, 24)
        .iter().zip(expected).enumerate()
    {
        assert_eq!(row[0], state, "coverage case {id}: {row:?}");
        assert_eq!(row[1], state, "coverage case {id}: shader/host expected state differs");
        assert_eq!(row[2], 1, "coverage case {id}: {row:?}");
        assert!(row[3] <= 65_536, "coverage case {id}: charged beyond budget");
    }
}
