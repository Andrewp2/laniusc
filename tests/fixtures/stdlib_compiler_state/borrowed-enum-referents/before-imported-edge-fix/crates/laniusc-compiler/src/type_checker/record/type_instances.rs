// src/type_checker/record/type_instances.rs

use super::*;

/// Records scalar, named, aggregate-reference, and aggregate-detail type collection.
pub(in crate::type_checker) fn record_type_instance_collection_passes_with_passes(
    encoder: &mut wgpu::CommandEncoder,
    state: &ResidentTypeCheckWorkspace,
    parser_feature_flags: u32,
    labels: &TypeInstanceCollectionTimerLabels,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    let collection = &state.type_instances.collection;
    match labels.stage {
        TypeInstanceCollectionStage::Initial => collection.scalar.record(encoder)?,
        TypeInstanceCollectionStage::Projected => collection
            .scalar
            .record_invocation(encoder, &collection.projected_scalar)?,
    }
    stamp_typecheck_timer(&mut timer, encoder, labels.scalar);
    match labels.stage {
        TypeInstanceCollectionStage::Initial => collection.named.record(encoder)?,
        TypeInstanceCollectionStage::Projected => collection
            .named
            .record_invocation(encoder, &collection.projected_named)?,
    }
    stamp_typecheck_timer(&mut timer, encoder, labels.named);
    if aggregate_passes_required(parser_feature_flags) {
        match labels.stage {
            TypeInstanceCollectionStage::Initial => collection.aggregate_refs.record(encoder)?,
            TypeInstanceCollectionStage::Projected => collection
                .aggregate_refs
                .record_invocation(encoder, &collection.projected_aggregate_refs)?,
        }
        stamp_typecheck_timer(&mut timer, encoder, labels.aggregate_refs);
        match labels.stage {
            TypeInstanceCollectionStage::Initial => collection.aggregate_details.record(encoder)?,
            TypeInstanceCollectionStage::Projected => collection
                .aggregate_details
                .record_invocation(encoder, &collection.projected_aggregate_details)?,
        }
        stamp_typecheck_timer(&mut timer, encoder, labels.aggregate_details);
    }

    Ok(())
}

/// Records predicate-owner propagation, compact generic ingestion, and key sorts.
pub(in crate::type_checker) fn record_generic_param_record_passes_with_passes(
    encoder: &mut wgpu::CommandEncoder,
    type_instances: &TypeInstanceBindGroups,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    type_instances
        .generic_parameters
        .record(encoder, timer.take())
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
