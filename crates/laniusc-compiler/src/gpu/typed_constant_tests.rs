//! Focused physical GPU execution of typed identity, owned inference and exact
//! allocation coverage. Rust supplies expected outcomes, never constant fitting
//! or an implementation of the production graph algorithms.
use super::{
    buffers::{readback_bytes, storage_rw_for_array},
    device,
    passes_core::{self, make_pass_data_from_shader_key, map_readback_blocking},
};

fn run_rows(key: &str, binding: &str, rows: usize, threads: u32) -> Vec<[u32; 4]> {
    assert!(!super::env::env_bool_truthy("LANIUS_ALLOW_SOFTWARE_ADAPTER", false),
        "this regression requires a physical GPU");
    let gpu = device::global();
    let word_count = rows * 4;
    let results = storage_rw_for_array::<u32>(&gpu.device, key, word_count);
    let pass = make_pass_data_from_shader_key(&gpu.device, key, "main", key).unwrap();
    assert_eq!(pass.thread_group_size, [threads, 1, 1]);
    let entries = [(binding, results.as_entire_binding())];
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

fn assert_typed_constant_identity_family(key: &str, cases: &[usize]) {
    // Hash inequality is not required: different typed values may collide.
    // Hash validity and equal-value hash agreement are required independently.
    let mut expected = [([1, 1, 1], Some(1)); 64];
    for id in [1, 2, 11, 17, 18] { expected[id] = ([0, 1, 1], None); }
    for id in [4, 5, 10, 12, 13, 14, 15] { expected[id] = ([0, 0, 0], None); }
    expected[9] = ([0, 0, 1], None);
    expected[20] = ([1, 2, 1], Some(1)); // symbolic, pending fit
    expected[21] = ([1, 1, 0], Some(1)); // concrete, discharged fit
    expected[23] = ([0, 0, 1], Some(1)); // mismatch leaves slot unbound
    expected[25] = ([1, 0, 1], Some(1)); // different high limb conflicts
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
fn physical_gpu_typed_constant_identity_and_claim_provenance_inference() {
    assert_typed_constant_identity_family("tests/typed_constant_identity_inference", &[22, 23, 24, 25, 26, 27, 28, 29, 30]);
}

#[test]
fn physical_gpu_typed_constant_identity_and_claim_provenance_requests() {
    assert_typed_constant_identity_family("tests/typed_constant_identity_requests", &[31, 32, 33, 34, 35, 36, 37, 38, 39, 40]);
}

#[test]
fn physical_gpu_typed_constant_identity_and_claim_provenance_depth() {
    assert_typed_constant_identity_family("tests/typed_constant_identity_depth", &[41, 42, 43]);
}

#[test]
fn physical_gpu_typed_constant_identity_and_claim_provenance_array_constraints() {
    assert_typed_constant_identity_family("tests/typed_constant_identity_array_constraints", &[44, 45, 46, 47, 48, 49, 50, 51]);
}

#[test]
fn physical_gpu_typed_constant_identity_and_claim_provenance_claim_merge() {
    assert_typed_constant_identity_family("tests/typed_constant_identity_claim_merge", &[52, 53, 54, 55, 56, 57, 58, 59, 62]);
}

#[test]
fn physical_gpu_typed_constant_identity_and_claim_provenance_claim_priority() {
    assert_typed_constant_identity_family("tests/typed_constant_identity_claim_priority", &[60, 61, 63]);
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
