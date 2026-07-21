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
    // The first pass publishes compact declaration name-token -> dense-HIR
    // rows. The second pass joins raw propagation owners against that compact
    // table, avoiding semantic classification from raw parser item columns.
    record_compute_indirect(
        encoder,
        &passes.type_instances_mark_generic_param_records,
        &type_instances.mark_generic_param_records,
        "type_check.resident.type_instances.mark_generic_param_owners.pass",
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
        let steps = type_instances.sort_generic_param_key_scatter.len();
        debug_assert_eq!(steps, type_instances.sort_generic_param_slot_scatter.len());
        for i in 0..steps {
            count_recorded_compute_pass();
            let mut histogram = crate::gpu::passes_core::ComputePassBatch::begin(
                encoder,
                "type_check.type_instances.sort_generic_params.histogram.paired",
            );
            histogram.record_raw_indirect(
                &passes.type_instances_sort_generic_param_keys,
                &type_instances.sort_generic_param_key_histogram[i],
                &type_instances.generic_param_key_radix_dispatch_args,
            );
            histogram.record_raw_indirect(
                &passes.type_instances_sort_generic_param_slots,
                &type_instances.sort_generic_param_slot_histogram[i],
                &type_instances.generic_param_key_radix_dispatch_args,
            );
            drop(histogram);

            count_recorded_compute_pass();
            let mut prefix = crate::gpu::passes_core::ComputePassBatch::begin(
                encoder,
                "type_check.type_instances.sort_generic_params.prefix.paired",
            );
            prefix.record_raw(
                &passes.names_radix_bucket_prefix,
                &type_instances.sort_generic_param_key_bucket_prefix[i],
                NAME_RADIX_BUCKETS.saturating_mul(256),
            )?;
            prefix.record_raw(
                &passes.names_radix_bucket_prefix,
                &type_instances.sort_generic_param_slot_bucket_prefix[i],
                NAME_RADIX_BUCKETS.saturating_mul(256),
            )?;
            drop(prefix);

            count_recorded_compute_pass();
            let mut bases = crate::gpu::passes_core::ComputePassBatch::begin(
                encoder,
                "type_check.type_instances.sort_generic_params.bases.paired",
            );
            bases.record_raw(
                &passes.names_radix_bucket_bases,
                &type_instances.sort_generic_param_key_bucket_bases[i],
                256,
            )?;
            bases.record_raw(
                &passes.names_radix_bucket_bases,
                &type_instances.sort_generic_param_slot_bucket_bases[i],
                256,
            )?;
            drop(bases);

            count_recorded_compute_pass();
            let mut scatter = crate::gpu::passes_core::ComputePassBatch::begin(
                encoder,
                "type_check.type_instances.sort_generic_params.scatter.paired",
            );
            scatter.record_raw_indirect(
                &passes.type_instances_sort_generic_param_keys_scatter,
                &type_instances.sort_generic_param_key_scatter[i],
                &type_instances.generic_param_key_radix_dispatch_args,
            );
            scatter.record_raw_indirect(
                &passes.type_instances_sort_generic_param_slots_scatter,
                &type_instances.sort_generic_param_slot_scatter[i],
                &type_instances.generic_param_key_radix_dispatch_args,
            );
        }
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
        &passes.struct_field_radix_dispatch_args,
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
            &passes.struct_field_radix_bucket_local,
            &type_instances.sort_struct_field_key_bucket_local[i],
            "type_check.type_instances.sort_struct_field_keys_bucket_local",
            type_instances.struct_field_radix_prefix_work_items,
        )?;
        record_compute(
            encoder,
            &passes.struct_field_radix_bucket_chunks,
            &type_instances.sort_struct_field_key_bucket_chunks[i],
            "type_check.type_instances.sort_struct_field_keys_bucket_chunks",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            &passes.struct_field_radix_bucket_apply,
            &type_instances.sort_struct_field_key_bucket_apply[i],
            "type_check.type_instances.sort_struct_field_keys_bucket_apply",
            type_instances.struct_field_radix_prefix_work_items,
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
    _n_blocks: u32,
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
    for step in &scan.hierarchy_up {
        record_compute(
            encoder,
            &passes.counted_scan_hierarchy_up,
            &step.bind_group,
            label,
            step.work_items,
        )?;
    }
    for step in &scan.hierarchy_down {
        record_compute(
            encoder,
            &passes.counted_scan_hierarchy_down,
            &step.bind_group,
            label,
            step.work_items,
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

/// Records two independent counted scans stage-by-stage. Corresponding stages
/// share a compute pass, while pass boundaries remain between dependent scan
/// levels so storage visibility is unchanged.
pub(in crate::type_checker) fn record_counted_u32_scan_pair_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    _left_n_blocks: u32,
    left_dispatch_args: &wgpu::Buffer,
    left: &U32ScanBindGroups,
    _right_n_blocks: u32,
    right_dispatch_args: &wgpu::Buffer,
    right: &U32ScanBindGroups,
    label: &'static str,
) -> Result<()> {
    {
        count_recorded_compute_pass();
        let mut batch = crate::gpu::passes_core::ComputePassBatch::begin(encoder, label);
        batch.record_raw_indirect(&passes.counted_scan_local, &left.local, left_dispatch_args);
        batch.record_raw_indirect(
            &passes.counted_scan_local,
            &right.local,
            right_dispatch_args,
        );
    }
    let up_steps = left.hierarchy_up.len().max(right.hierarchy_up.len());
    for step_index in 0..up_steps {
        count_recorded_compute_pass();
        let mut batch = crate::gpu::passes_core::ComputePassBatch::begin(encoder, label);
        if let Some(step) = left.hierarchy_up.get(step_index) {
            batch.record_raw(
                &passes.counted_scan_hierarchy_up,
                &step.bind_group,
                step.work_items,
            )?;
        }
        if let Some(step) = right.hierarchy_up.get(step_index) {
            batch.record_raw(
                &passes.counted_scan_hierarchy_up,
                &step.bind_group,
                step.work_items,
            )?;
        }
    }
    let down_steps = left.hierarchy_down.len().max(right.hierarchy_down.len());
    for step_index in 0..down_steps {
        count_recorded_compute_pass();
        let mut batch = crate::gpu::passes_core::ComputePassBatch::begin(encoder, label);
        if let Some(step) = left.hierarchy_down.get(step_index) {
            batch.record_raw(
                &passes.counted_scan_hierarchy_down,
                &step.bind_group,
                step.work_items,
            )?;
        }
        if let Some(step) = right.hierarchy_down.get(step_index) {
            batch.record_raw(
                &passes.counted_scan_hierarchy_down,
                &step.bind_group,
                step.work_items,
            )?;
        }
    }
    {
        count_recorded_compute_pass();
        let mut batch = crate::gpu::passes_core::ComputePassBatch::begin(encoder, label);
        batch.record_raw_indirect(&passes.counted_scan_apply, &left.apply, left_dispatch_args);
        batch.record_raw_indirect(
            &passes.counted_scan_apply,
            &right.apply,
            right_dispatch_args,
        );
    }
    Ok(())
}
