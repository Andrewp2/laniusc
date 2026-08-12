// src/type_checker/record/type_instances.rs

use super::*;

/// Records scalar, named, aggregate-reference, and aggregate-detail type collection.
pub(in crate::type_checker) fn record_type_instance_collection_passes_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ResidentTypeCheckWorkspace,
    hir_active_dispatch_args: &LaniusBuffer<u32>,
    labels: &TypeInstanceCollectionTimerLabels,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/type/instances/01_collect"),
        &state.type_instances.collect,
        "type_check.resident.type_instances_collect.pass",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, labels.scalar);
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/type/instances/01b_collect_named_instances"),
        &state.type_instances.collect_named,
        "type_check.resident.type_instances_collect_named.pass",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, labels.named);
    if aggregate_passes_required(state.cache_key.parser_feature_flags) {
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/type/instances/01c_collect_aggregate_refs"),
            &state.type_instances.collect_aggregate_refs,
            "type_check.resident.type_instances_collect_aggregate_refs.pass",
            hir_active_dispatch_args,
        )?;
        stamp_typecheck_timer(&mut timer, encoder, labels.aggregate_refs);
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/type/instances/01d_collect_aggregate_details"),
            &state.type_instances.collect_aggregate_details,
            "type_check.resident.type_instances_collect_aggregate_details.pass",
            hir_active_dispatch_args,
        )?;
        stamp_typecheck_timer(&mut timer, encoder, labels.aggregate_details);
    }

    Ok(())
}

/// Records predicate-owner propagation, compact generic ingestion, and key sorts.
pub(in crate::type_checker) fn record_generic_param_record_passes_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    type_instances: &TypeInstanceBindGroups,
    hir_active_dispatch_args: &LaniusBuffer<u32>,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/type/instances/00a_mark_generic_param_records"),
        &type_instances.mark_generic_param_records,
        "type_check.resident.type_instances.mark_generic_param_records.pass",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.type_instances.generic_params.mark.done",
    );

    for bind_group in &type_instances.propagate_generic_decl_owner {
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/type/instances/00a1_propagate_generic_decl_owner"),
            bind_group,
            "type_check.resident.type_instances.propagate_generic_decl_owner.pass",
            hir_active_dispatch_args,
        )?;
    }
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.type_instances.generic_params.owner.done",
    );

    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/type/instances/00b_decl_generic_params"),
        &type_instances.decl_generic_params,
        "type_check.resident.type_instances.decl_generic_params.pass",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.type_instances.decl_generic_params.done",
    );

    type_instances.generic_parameter_index.record(encoder)?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.type_instances.generic_params.index.done",
    );
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.type_instances.generic_param_slots.compact.done",
    );

    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/type/instances/00e_generic_param_use_slots"),
        &type_instances.generic_param_use_slots,
        "type_check.resident.type_instances_generic_param_use_slots.pass",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.type_instances.generic_param_use_slots.done",
    );

    Ok(())
}

/// Builds the exact compact struct-field lookup.
pub(in crate::type_checker) fn record_struct_field_key_passes_with_passes(
    encoder: &mut wgpu::CommandEncoder,
    type_instances: &TypeInstanceBindGroups,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    type_instances.struct_field_index.record(encoder)?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.type_instances.struct_field_lookup.done",
    );

    Ok(())
}
