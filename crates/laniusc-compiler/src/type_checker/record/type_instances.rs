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

    Ok(())
}

/// Records generic-parameter discovery, owner propagation, scans, and key sorts.
pub(in crate::type_checker) fn record_generic_param_record_passes_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    type_instances: &TypeInstanceBindGroups,
    hir_scan_n_blocks: u32,
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

    record_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        hir_scan_n_blocks,
        hir_active_dispatch_args,
        &type_instances.generic_param_scan,
        "type_check.type_instances.generic_param_record_scan",
    )?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.type_instances.generic_params.scan.done",
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

    record_compute(
        encoder,
        &passes.names_radix_dispatch_args,
        &type_instances.generic_param_key_radix_dispatch,
        "type_check.type_instances.generic_param_key_radix_dispatch_args",
        1,
    )?;
    if let Some(sort_generic_params_small) = &type_instances.sort_generic_params_small {
        record_compute_indirect(
            encoder,
            &passes.type_instances_sort_generic_params_small,
            sort_generic_params_small,
            "type_check.type_instances.sort_generic_params_small",
            &type_instances.generic_param_key_radix_dispatch_args,
        )?;
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
    } else {
        for i in 0..type_instances.sort_generic_param_key_scatter.len() {
            record_compute_indirect(
                encoder,
                &passes.type_instances_sort_generic_param_keys,
                &type_instances.sort_generic_param_key_histogram[i],
                "type_check.type_instances.sort_generic_param_keys_histogram",
                &type_instances.generic_param_key_radix_dispatch_args,
            )?;
            record_compute(
                encoder,
                &passes.names_radix_bucket_prefix,
                &type_instances.sort_generic_param_key_bucket_prefix[i],
                "type_check.type_instances.sort_generic_param_keys_bucket_prefix",
                NAME_RADIX_BUCKETS.saturating_mul(256),
            )?;
            record_compute(
                encoder,
                &passes.names_radix_bucket_bases,
                &type_instances.sort_generic_param_key_bucket_bases[i],
                "type_check.type_instances.sort_generic_param_keys_bucket_bases",
                256,
            )?;
            record_compute_indirect(
                encoder,
                &passes.type_instances_sort_generic_param_keys_scatter,
                &type_instances.sort_generic_param_key_scatter[i],
                "type_check.type_instances.sort_generic_param_keys_scatter",
                &type_instances.generic_param_key_radix_dispatch_args,
            )?;
        }
        stamp_typecheck_timer(
            &mut timer,
            encoder,
            "typecheck.type_instances.generic_params.sort.done",
        );

        for i in 0..type_instances.sort_generic_param_slot_scatter.len() {
            record_compute_indirect(
                encoder,
                &passes.type_instances_sort_generic_param_slots,
                &type_instances.sort_generic_param_slot_histogram[i],
                "type_check.type_instances.sort_generic_param_slots_histogram",
                &type_instances.generic_param_key_radix_dispatch_args,
            )?;
            record_compute(
                encoder,
                &passes.names_radix_bucket_prefix,
                &type_instances.sort_generic_param_slot_bucket_prefix[i],
                "type_check.type_instances.sort_generic_param_slots_bucket_prefix",
                NAME_RADIX_BUCKETS.saturating_mul(256),
            )?;
            record_compute(
                encoder,
                &passes.names_radix_bucket_bases,
                &type_instances.sort_generic_param_slot_bucket_bases[i],
                "type_check.type_instances.sort_generic_param_slots_bucket_bases",
                256,
            )?;
            record_compute_indirect(
                encoder,
                &passes.type_instances_sort_generic_param_slots_scatter,
                &type_instances.sort_generic_param_slot_scatter[i],
                "type_check.type_instances.sort_generic_param_slots_scatter",
                &type_instances.generic_param_key_radix_dispatch_args,
            )?;
        }
        stamp_typecheck_timer(
            &mut timer,
            encoder,
            "typecheck.type_instances.generic_param_slots.sort.done",
        );
    }

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
        &passes.names_radix_dispatch_args,
        &type_instances.struct_field_key_radix_dispatch,
        "type_check.type_instances.struct_field_key_radix_dispatch_args",
        1,
    )?;
    for i in 0..type_instances.sort_struct_field_key_scatter.len() {
        record_compute_indirect(
            encoder,
            &passes.type_instances_sort_struct_field_keys,
            &type_instances.sort_struct_field_key_histogram[i],
            "type_check.type_instances.sort_struct_field_keys_histogram",
            &type_instances.struct_field_key_radix_dispatch_args,
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_prefix,
            &type_instances.sort_struct_field_key_bucket_prefix[i],
            "type_check.type_instances.sort_struct_field_keys_bucket_prefix",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_bases,
            &type_instances.sort_struct_field_key_bucket_bases[i],
            "type_check.type_instances.sort_struct_field_keys_bucket_bases",
            256,
        )?;
        record_compute_indirect(
            encoder,
            &passes.type_instances_sort_struct_field_keys_scatter,
            &type_instances.sort_struct_field_key_scatter[i],
            "type_check.type_instances.sort_struct_field_keys_scatter",
            &type_instances.struct_field_key_radix_dispatch_args,
        )?;
    }
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.type_instances.struct_field_keys.sort.done",
    );

    Ok(())
}

/// Records the local, block-prefix, and apply stages of a counted `u32` scan.
pub(in crate::type_checker) fn record_counted_u32_scan_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    n_blocks: u32,
    dispatch_args: &wgpu::Buffer,
    scan: &U32ScanBindGroups,
    label: &'static str,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.counted_scan_local,
        &scan.local,
        label,
        dispatch_args,
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
        dispatch_args,
    )
}
