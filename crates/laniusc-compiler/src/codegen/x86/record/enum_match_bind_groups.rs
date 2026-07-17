use anyhow::Result;

use super::super::{
    GpuX86CallMetadataBuffers,
    GpuX86CodeGenerator,
    GpuX86EnumMetadataBuffers,
    GpuX86ExprMetadataBuffers,
    support::reflected_bind_group,
};

/// Bind groups used to record enum and match metadata for x86 lowering.
pub(super) struct EnumMatchBindGroups {
    pub(super) enum_records: wgpu::BindGroup,
    pub(super) match_records: wgpu::BindGroup,
    pub(super) match_patterns: wgpu::BindGroup,
}

/// Buffer inputs needed by enum and match metadata recording.
pub(super) struct EnumMatchBindGroupInputs<'a> {
    pub(super) params: &'a wgpu::Buffer,
    pub(super) feature_params: &'a wgpu::Buffer,
    pub(super) hir_status: &'a wgpu::Buffer,
    pub(super) hir_kind: &'a wgpu::Buffer,
    pub(super) expr_metadata: &'a GpuX86ExprMetadataBuffers<'a>,
    pub(super) enum_metadata: &'a GpuX86EnumMetadataBuffers<'a>,
    pub(super) call_metadata: &'a GpuX86CallMetadataBuffers<'a>,
    pub(super) expr_resolved_final: &'a wgpu::Buffer,
    pub(super) node_func: &'a wgpu::Buffer,
    pub(super) visible_decl: &'a wgpu::Buffer,
    pub(super) enum_type_record: &'a wgpu::Buffer,
    pub(super) enum_value_record: &'a wgpu::Buffer,
    pub(super) enum_record_status: &'a wgpu::Buffer,
    pub(super) match_record: &'a wgpu::Buffer,
    pub(super) match_arm_record: &'a wgpu::Buffer,
    pub(super) match_result_dense_owner: &'a wgpu::Buffer,
    pub(super) match_arm_owner: &'a wgpu::Buffer,
    pub(super) match_pattern_owner: &'a wgpu::Buffer,
    pub(super) match_pattern_node_owner: &'a wgpu::Buffer,
    pub(super) match_pattern_dense_owner: &'a wgpu::Buffer,
    pub(super) match_pattern_root_owner: &'a wgpu::Buffer,
    pub(super) match_pattern_node_variant: &'a wgpu::Buffer,
    pub(super) match_pattern_node_payload_decl: &'a wgpu::Buffer,
    pub(super) match_pattern_first_use_node: &'a wgpu::Buffer,
    pub(super) compact_executable_raw: &'a wgpu::Buffer,
    pub(super) match_pattern_first_variant_node: &'a wgpu::Buffer,
    pub(super) match_pattern_first_payload_node: &'a wgpu::Buffer,
}

/// Creates bind groups for enum records and match pattern records.
pub(super) fn create_enum_match_bind_groups(
    generator: &GpuX86CodeGenerator,
    device: &wgpu::Device,
    inputs: EnumMatchBindGroupInputs<'_>,
) -> Result<EnumMatchBindGroups> {
    let EnumMatchBindGroupInputs {
        params,
        feature_params,
        hir_status,
        hir_kind,
        expr_metadata,
        enum_metadata,
        call_metadata,
        expr_resolved_final,
        node_func,
        visible_decl,
        enum_type_record,
        enum_value_record,
        enum_record_status,
        match_record,
        match_arm_record,
        match_result_dense_owner,
        match_arm_owner,
        match_pattern_owner,
        match_pattern_node_owner,
        match_pattern_dense_owner,
        match_pattern_root_owner,
        match_pattern_node_variant,
        match_pattern_node_payload_decl,
        match_pattern_first_use_node,
        compact_executable_raw,
        match_pattern_first_variant_node,
        match_pattern_first_payload_node,
    } = inputs;

    let enum_records = reflected_bind_group(
        device,
        Some("codegen.x86.enum_records.bind_group"),
        &generator.enum_records_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "compact_variant_count",
                enum_metadata.compact_variant_count.as_entire_binding(),
            ),
            (
                "compact_variants",
                enum_metadata.compact_variants.as_entire_binding(),
            ),
            (
                "compact_variant_payload_count",
                enum_metadata.compact_variant_payload_count.as_entire_binding(),
            ),
            ("hir_status", hir_status.as_entire_binding()),
            ("hir_kind", hir_kind.as_entire_binding()),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "x86_expr_resolved_node",
                expr_resolved_final.as_entire_binding(),
            ),
            (
                "hir_call_callee_node",
                call_metadata.callee_node.as_entire_binding(),
            ),
            (
                "path_count_out",
                enum_metadata.path_count_out.as_entire_binding(),
            ),
            (
                "path_id_by_owner_hir",
                enum_metadata.path_id_by_owner_hir.as_entire_binding(),
            ),
            (
                "resolved_value_decl",
                enum_metadata.resolved_value_decl.as_entire_binding(),
            ),
            (
                "resolved_value_status",
                enum_metadata.resolved_value_status.as_entire_binding(),
            ),
            (
                "decl_count_out",
                enum_metadata.decl_count_out.as_entire_binding(),
            ),
            ("visible_decl", visible_decl.as_entire_binding()),
            ("decl_kind", enum_metadata.decl_kind.as_entire_binding()),
            (
                "decl_name_token",
                enum_metadata.decl_name_token.as_entire_binding(),
            ),
            (
                "decl_id_by_name_token",
                enum_metadata.decl_id_by_name_token.as_entire_binding(),
            ),
            (
                "decl_hir_node",
                enum_metadata.decl_hir_node.as_entire_binding(),
            ),
            (
                "decl_parent_type_decl",
                enum_metadata.decl_parent_type_decl.as_entire_binding(),
            ),
            ("x86_enum_type_record", enum_type_record.as_entire_binding()),
            (
                "x86_enum_value_record",
                enum_value_record.as_entire_binding(),
            ),
            (
                "x86_enum_record_status",
                enum_record_status.as_entire_binding(),
            ),
        ],
    )?;
    let match_records = reflected_bind_group(
        device,
        Some("codegen.x86.match_records.bind_group"),
        &generator.match_records_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("compact_hir_count", enum_metadata.compact_hir_count.as_entire_binding()),
            ("compact_hir_core", enum_metadata.compact_hir_core.as_entire_binding()),
            ("compact_hir_payload", enum_metadata.compact_hir_payload.as_entire_binding()),
            ("raw_to_compact_hir", enum_metadata.raw_to_compact_hir.as_entire_binding()),
            ("compact_match_arm_count", enum_metadata.compact_match_arm_count.as_entire_binding()),
            ("compact_match_arms", enum_metadata.compact_match_arms.as_entire_binding()),
            ("compact_match_payload_start", enum_metadata.compact_match_payload_start.as_entire_binding()),
            ("compact_match_payload_count", enum_metadata.compact_match_payload_count.as_entire_binding()),
            ("compact_match_payload_row_count", enum_metadata.compact_match_payload_row_count.as_entire_binding()),
            ("compact_match_payloads", enum_metadata.compact_match_payloads.as_entire_binding()),
            ("hir_kind", hir_kind.as_entire_binding()),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            ("x86_node_func", node_func.as_entire_binding()),
            ("gX86Features", feature_params.as_entire_binding()),
            ("x86_match_record", match_record.as_entire_binding()),
            ("x86_match_arm_record", match_arm_record.as_entire_binding()),
            (
                "x86_match_result_dense_owner",
                match_result_dense_owner.as_entire_binding(),
            ),
            ("x86_match_arm_owner", match_arm_owner.as_entire_binding()),
            ("x86_match_pattern_owner", match_pattern_owner.as_entire_binding()),
            (
                "x86_compact_executable_raw",
                compact_executable_raw.as_entire_binding(),
            ),
        ],
    )?;
    let match_patterns = reflected_bind_group(
        device,
        Some("codegen.x86.match_pattern_records.bind_group"),
        &generator.match_pattern_records_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "compact_variant_count",
                enum_metadata.compact_variant_count.as_entire_binding(),
            ),
            (
                "compact_variants",
                enum_metadata.compact_variants.as_entire_binding(),
            ),
            ("hir_status", hir_status.as_entire_binding()),
            ("hir_kind", hir_kind.as_entire_binding()),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "hir_token_pos",
                enum_metadata.hir_token_pos.as_entire_binding(),
            ),
            (
                "x86_expr_resolved_node",
                expr_resolved_final.as_entire_binding(),
            ),
            (
                "hir_call_callee_node",
                call_metadata.callee_node.as_entire_binding(),
            ),
            ("visible_decl", visible_decl.as_entire_binding()),
            (
                "path_count_out",
                enum_metadata.path_count_out.as_entire_binding(),
            ),
            (
                "path_id_by_owner_hir",
                enum_metadata.path_id_by_owner_hir.as_entire_binding(),
            ),
            (
                "resolved_value_decl",
                enum_metadata.resolved_value_decl.as_entire_binding(),
            ),
            (
                "resolved_value_status",
                enum_metadata.resolved_value_status.as_entire_binding(),
            ),
            (
                "decl_count_out",
                enum_metadata.decl_count_out.as_entire_binding(),
            ),
            ("decl_kind", enum_metadata.decl_kind.as_entire_binding()),
            (
                "decl_name_token",
                enum_metadata.decl_name_token.as_entire_binding(),
            ),
            (
                "decl_id_by_name_token",
                enum_metadata.decl_id_by_name_token.as_entire_binding(),
            ),
            (
                "decl_hir_node",
                enum_metadata.decl_hir_node.as_entire_binding(),
            ),
            (
                "decl_parent_type_decl",
                enum_metadata.decl_parent_type_decl.as_entire_binding(),
            ),
            ("gX86Features", feature_params.as_entire_binding()),
            ("compact_match_arm_count", enum_metadata.compact_match_arm_count.as_entire_binding()),
            ("raw_to_compact_hir", enum_metadata.raw_to_compact_hir.as_entire_binding()),
            ("x86_match_pattern_dense_owner", match_pattern_dense_owner.as_entire_binding()),
            ("x86_match_pattern_root_owner", match_pattern_root_owner.as_entire_binding()),
            ("compact_hir_links", enum_metadata.compact_hir_links.as_entire_binding()),
            ("compact_hir_core", enum_metadata.compact_hir_core.as_entire_binding()),
            ("x86_match_arm_record", match_arm_record.as_entire_binding()),
            (
                "x86_match_pattern_node_owner",
                match_pattern_node_owner.as_entire_binding(),
            ),
            (
                "x86_match_pattern_node_variant",
                match_pattern_node_variant.as_entire_binding(),
            ),
            (
                "x86_match_pattern_node_payload_decl",
                match_pattern_node_payload_decl.as_entire_binding(),
            ),
            (
                "x86_match_pattern_first_use_node",
                match_pattern_first_use_node.as_entire_binding(),
            ),
            (
                "x86_match_pattern_first_variant_node",
                match_pattern_first_variant_node.as_entire_binding(),
            ),
            (
                "x86_match_pattern_first_payload_node",
                match_pattern_first_payload_node.as_entire_binding(),
            ),
        ],
    )?;

    Ok(EnumMatchBindGroups {
        enum_records,
        match_records,
        match_patterns,
    })
}
