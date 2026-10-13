use anyhow::{Result, ensure};

use super::{
    super::{abi::Span, catalog::FrozenCatalog},
    OutputLayout,
    arena::{self, Arena},
};
use crate::gpu::passes_core::{self, PassData};

// Ordinary literals are required by laniusc-shaders/build.rs artifact discovery.
const CATALOG_KEYS: [&str; 12] = [
    "type_checker/program_evidence/entries/00_initialize",
    "type_checker/program_evidence/entries/01_clear_atom_index",
    "type_checker/program_evidence/entries/02_admit_catalog_rows",
    "type_checker/program_evidence/entries/03_build_atom_index",
    "type_checker/program_evidence/entries/04_check_atom_identity",
    "type_checker/program_evidence/entries/05_map_callables",
    "type_checker/program_evidence/entries/06_map_definition_identities",
    "type_checker/program_evidence/entries/07_check_method_targets",
    "type_checker/program_evidence/entries/08_clear_implementation_index",
    "type_checker/program_evidence/entries/09_build_implementation_index",
    "type_checker/program_evidence/entries/10_check_coherence",
    "type_checker/program_evidence/entries/11_freeze_catalog",
];

pub(super) struct CatalogKernels {
    passes: Vec<PassData>,
}
impl CatalogKernels {
    pub fn load(device: &wgpu::Device) -> Result<Self> {
        let passes = CATALOG_KEYS
            .iter()
            .map(|key| passes_core::make_pass_data_from_shader_key(device, key, "main", key))
            .collect::<Result<Vec<_>>>()?;
        Ok(Self { passes })
    }
    pub fn record(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        catalog: &FrozenCatalog,
        storage: &Arena,
        input: &Arena,
        output: &Arena,
    ) -> Result<()> {
        let count = |table: usize| catalog.slices[table].count;
        let work_rows = count(1).max(count(9));
        let buckets = super::super::abi::buckets(work_rows)?;
        let clear_count = work_rows.max(buckets); // >=1, even for empty catalog.
        let counts = [
            1,
            clear_count,
            (0..=10).map(count).max().unwrap_or(0),
            count(1),
            count(1),
            count(4),
            count(2).max(count(8)).max(count(9)),
            count(10),
            clear_count,
            count(9),
            count(9),
            1,
        ];
        for (phase, (pass, count)) in self.passes.iter().zip(counts).enumerate() {
            let threads = if matches!(phase, 0 | 11) { 1 } else { 256 };
            record_phase(
                device,
                encoder,
                pass,
                phase as u32,
                Span::new(0, count)?,
                threads,
                storage,
                input,
                output,
            )?;
        }
        Ok(())
    }
}

/// Each dispatch has immutable parameters. A separate compute pass is a WGPU
/// synchronization boundary; no following phase can observe a partially built
/// index. Extra boundaries between large chunks are harmless.
pub(super) fn record_phase(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    phase: u32,
    span: Span,
    threads: u32,
    catalog: &Arena,
    input: &Arena,
    output: &Arena,
) -> Result<()> {
    ensure!(
        pass.thread_group_size == [threads, 1, 1],
        "evidence shader thread size differs from dispatch contract"
    );
    ensure!(
        matches!(threads, 1 | 256),
        "unsupported evidence dispatch width"
    );
    if span.count == 0 {
        return Ok(());
    }
    let limits = device.limits();
    ensure!(
        threads <= limits.max_compute_invocations_per_workgroup
            && threads <= limits.max_compute_workgroup_size_x,
        "evidence kernel exceeds device workgroup limit"
    );
    // Current shader 2D flattening has fixed x width 65_535*256. Use bounded
    // one-dimensional chunks, valid even on devices with a smaller group limit.
    let max_groups = limits.max_compute_workgroups_per_dimension.min(65_535);
    ensure!(max_groups != 0, "device exposes no compute dispatch groups");
    let max_rows = max_groups
        .checked_mul(threads)
        .expect("bounded group product");
    let mut done = 0u32;
    while done < span.count {
        let count = (span.count - done).min(max_rows);
        let params = [
            span.first.checked_add(done).expect("checked span"),
            count,
            catalog.logical_words,
            input.logical_words,
            output.logical_words,
            phase,
            0,
            0,
        ];
        let uniform = arena::allocate(
            device,
            "program_evidence.params",
            8,
            wgpu::BufferUsages::UNIFORM,
            Some(&params),
        )?;
        // Some phases optimize an unused resource out. The existing reflected
        // constructor selects active names and rejects unknown required names.
        // These four resources are always distinct physical allocations.
        let resources = [
            ("program_evidence_params", uniform.as_entire_binding()),
            (
                "program_evidence_catalog",
                catalog.buffer.as_entire_binding(),
            ),
            ("program_evidence_batch", input.buffer.as_entire_binding()),
            ("program_evidence_output", output.buffer.as_entire_binding()),
        ];
        let bindings = passes_core::bind_group::create_bind_group_from_bindings(
            device,
            Some("program_evidence.bindings"),
            pass,
            0,
            &resources,
        )?;
        passes_core::flush_deferred_compute(encoder);
        {
            let mut compute = passes_core::begin_counted_compute_pass(
                encoder,
                &wgpu::ComputePassDescriptor {
                    label: Some(&pass.shader_id),
                    timestamp_writes: None,
                },
            );
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, Some(&bindings), &[]);
            passes_core::record_compute_dispatch();
            compute.dispatch_workgroups(count.div_ceil(threads), 1, 1);
        }
        done += count;
    }
    Ok(())
}

// This is deliberately a rejecting integration seam, not an empty successful
// selector. GPU author has not yet published the batch entry/phase contract.
pub(super) struct BatchKernels;
impl BatchKernels {
    pub fn load(_device: &wgpu::Device) -> Result<Self> {
        anyhow::bail!("program evidence batch GPU phases are not registered in this scratch draft")
    }
    pub fn record(
        &self,
        _device: &wgpu::Device,
        _encoder: &mut wgpu::CommandEncoder,
        _submission: &super::super::packet::Submission,
        _layout: &OutputLayout,
        _catalog: &Arena,
        _input: &Arena,
        _output: &Arena,
    ) -> Result<()> {
        anyhow::bail!("program evidence batch GPU phase recording is not implemented")
    }
}
