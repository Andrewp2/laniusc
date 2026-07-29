// src/type_checker/record/type_instances.rs

use super::*;

/// Records scalar, named, aggregate-reference, and aggregate-detail type collection.
pub(in crate::type_checker) fn record_type_instance_collection_passes_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ResidentTypeCheckState,
    hir_active_dispatch_args: &wgpu::Buffer,
    labels: &TypeInstanceCollectionTimerLabels,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.type_instances_collect,
        &state.type_instances.collect,
        "type_check.resident.type_instances_collect.pass",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, labels.scalar);
    record_compute_indirect(
        encoder,
        &passes.type_instances_collect_named,
        &state.type_instances.collect_named,
        "type_check.resident.type_instances_collect_named.pass",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, labels.named);
    if aggregate_passes_required(state.cache_key.parser_feature_flags) {
        record_compute_indirect(
            encoder,
            &passes.type_instances_collect_aggregate_refs,
            &state.type_instances.collect_aggregate_refs,
            "type_check.resident.type_instances_collect_aggregate_refs.pass",
            hir_active_dispatch_args,
        )?;
        stamp_typecheck_timer(&mut timer, encoder, labels.aggregate_refs);
        record_compute_indirect(
            encoder,
            &passes.type_instances_collect_aggregate_details,
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
    hir_active_dispatch_args: &wgpu::Buffer,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.type_instances_mark_generic_param_records,
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
            &passes.type_instances_propagate_generic_decl_owner,
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
        &passes.type_instances_decl_generic_params,
        &type_instances.decl_generic_params,
        "type_check.resident.type_instances.decl_generic_params.pass",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.type_instances.decl_generic_params.done",
    );

    type_instances
        .generic_parameter_sorts
        .record(passes, encoder)?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.type_instances.generic_params.sort.done",
    );
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.type_instances.generic_param_slots.sort.done",
    );

    record_compute_indirect(
        encoder,
        &passes.type_instances_generic_param_use_slots,
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

/// Records struct-field key seeding and radix sorting for aggregate lookup.
pub(in crate::type_checker) fn record_struct_field_key_passes_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    type_instances: &TypeInstanceBindGroups,
    hir_active_dispatch_args: &wgpu::Buffer,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.type_instances_seed_struct_field_keys,
        &type_instances.seed_struct_field_keys,
        "type_check.resident.type_instances.seed_struct_field_keys.pass",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.type_instances.struct_field_keys.seed.done",
    );

    record_compute(
        encoder,
        &passes.struct_field_radix_dispatch_args,
        &type_instances.struct_field_key_radix_dispatch,
        "type_check.type_instances.struct_field_key_radix_dispatch_args",
        1,
    )?;
    type_instances.sort_struct_fields.record(encoder)?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.type_instances.struct_field_keys.sort.done",
    );

    Ok(())
}
