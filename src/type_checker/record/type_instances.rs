// src/type_checker/record/type_instances.rs

use super::*;

pub(in crate::type_checker) fn record_type_instance_collection_passes_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    bind_groups: &ResidentTypeCheckBindGroups,
    hir_active_dispatch_args: &wgpu::Buffer,
    labels: &TypeInstanceCollectionTimerLabels,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.type_instances_collect,
        &bind_groups.type_instances.collect,
        "type_check.resident.type_instances_collect.pass",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, labels.scalar);
    record_compute_indirect(
        encoder,
        &passes.type_instances_collect_named,
        &bind_groups.type_instances.collect_named,
        "type_check.resident.type_instances_collect_named.pass",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, labels.named);
    record_compute_indirect(
        encoder,
        &passes.type_instances_collect_aggregate_refs,
        &bind_groups.type_instances.collect_aggregate_refs,
        "type_check.resident.type_instances_collect_aggregate_refs.pass",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, labels.aggregate_refs);
    record_compute_indirect(
        encoder,
        &passes.type_instances_collect_aggregate_details,
        &bind_groups.type_instances.collect_aggregate_details,
        "type_check.resident.type_instances_collect_aggregate_details.pass",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, labels.aggregate_details);

    Ok(())
}

pub(in crate::type_checker) fn record_hir_counted_u32_scan_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    n_blocks: u32,
    hir_active_dispatch_args: &wgpu::Buffer,
    scan: &U32ScanBindGroups,
    label: &'static str,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.counted_scan_local,
        &scan.local,
        label,
        hir_active_dispatch_args,
    )?;
    for bind_group in &scan.blocks {
        record_compute(
            encoder,
            &passes.counted_scan_blocks,
            bind_group,
            label,
            n_blocks.max(1),
        )?;
    }
    record_compute_indirect(
        encoder,
        &passes.counted_scan_apply,
        &scan.apply,
        label,
        hir_active_dispatch_args,
    )
}
