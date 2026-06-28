use anyhow::Result;

use super::{
    super::{
        GpuX86ArrayMetadataBuffers,
        GpuX86CallMetadataBuffers,
        GpuX86CodeGenerator,
        GpuX86ExprMetadataBuffers,
        GpuX86FunctionMetadataBuffers,
        GpuX86StructMetadataBuffers,
        GpuX86TypeMetadataBuffers,
        support::reflected_bind_group,
    },
    bind_helpers::{StepNames, StepPairs, step_pair_groups},
};

/// Bind groups used to record semantic x86 layout and ownership metadata.
pub(super) struct SemanticRecordBindGroups {
    pub(super) enclosing_return_init: wgpu::BindGroup,
    pub(super) enclosing_return_step: Vec<wgpu::BindGroup>,
    pub(super) enclosing_let_init: wgpu::BindGroup,
    pub(super) enclosing_let_step: Vec<wgpu::BindGroup>,
    pub(super) enclosing_stmt_init: wgpu::BindGroup,
    pub(super) enclosing_stmt_step: Vec<wgpu::BindGroup>,
    pub(super) return_match_records: wgpu::BindGroup,
    pub(super) match_result_owner_init: wgpu::BindGroup,
    pub(super) match_result_owner_step: Vec<wgpu::BindGroup>,
    pub(super) match_ownership: wgpu::BindGroup,
    pub(super) match_pattern_owner_init: wgpu::BindGroup,
    pub(super) match_pattern_owner_step: Vec<wgpu::BindGroup>,
    pub(super) match_pattern_finalize: wgpu::BindGroup,
    pub(super) struct_records: wgpu::BindGroup,
    pub(super) array_records: wgpu::BindGroup,
    pub(super) decl_widths: wgpu::BindGroup,
    pub(super) decl_layout: wgpu::BindGroup,
}

/// Buffer inputs needed by x86 semantic-recording passes.
pub(super) struct SemanticRecordInputs<'a> {
    pub(super) params_buf: &'a wgpu::Buffer,
    pub(super) feature_params_buf: &'a wgpu::Buffer,
    pub(super) hir_status_buf: &'a wgpu::Buffer,
    pub(super) hir_kind_buf: &'a wgpu::Buffer,
    pub(super) parent_buf: &'a wgpu::Buffer,
    pub(super) subtree_end_buf: &'a wgpu::Buffer,
    pub(super) function_metadata: &'a GpuX86FunctionMetadataBuffers<'a>,
    pub(super) expr_metadata: &'a GpuX86ExprMetadataBuffers<'a>,
    pub(super) call_metadata: &'a GpuX86CallMetadataBuffers<'a>,
    pub(super) array_metadata: &'a GpuX86ArrayMetadataBuffers<'a>,
    pub(super) struct_metadata: &'a GpuX86StructMetadataBuffers<'a>,
    pub(super) type_metadata: &'a GpuX86TypeMetadataBuffers<'a>,
    pub(super) expr_resolved_final_buf: &'a wgpu::Buffer,
    pub(super) node_tree_status_buf: &'a wgpu::Buffer,
    pub(super) match_record_buf: &'a wgpu::Buffer,
    pub(super) match_return_node_buf: &'a wgpu::Buffer,
    pub(super) match_pattern_owner_buf: &'a wgpu::Buffer,
    pub(super) match_result_value_owner_buf: &'a wgpu::Buffer,
    pub(super) match_pattern_node_variant_buf: &'a wgpu::Buffer,
    pub(super) match_pattern_node_payload_decl_buf: &'a wgpu::Buffer,
    pub(super) match_pattern_first_use_node_buf: &'a wgpu::Buffer,
    pub(super) match_pattern_first_variant_node_buf: &'a wgpu::Buffer,
    pub(super) match_pattern_first_payload_node_buf: &'a wgpu::Buffer,
    pub(super) enclosing_return_node_a_buf: &'a wgpu::Buffer,
    pub(super) enclosing_return_node_b_buf: &'a wgpu::Buffer,
    pub(super) enclosing_return_link_a_buf: &'a wgpu::Buffer,
    pub(super) enclosing_return_link_b_buf: &'a wgpu::Buffer,
    pub(super) enclosing_return_steps: &'a [u32],
    pub(super) enclosing_let_node_a_buf: &'a wgpu::Buffer,
    pub(super) enclosing_let_node_b_buf: &'a wgpu::Buffer,
    pub(super) enclosing_let_link_a_buf: &'a wgpu::Buffer,
    pub(super) enclosing_let_link_b_buf: &'a wgpu::Buffer,
    pub(super) enclosing_let_steps: &'a [u32],
    pub(super) enclosing_let_step_final_buf: &'a wgpu::Buffer,
    pub(super) enclosing_stmt_node_a_buf: &'a wgpu::Buffer,
    pub(super) enclosing_stmt_node_b_buf: &'a wgpu::Buffer,
    pub(super) enclosing_stmt_link_a_buf: &'a wgpu::Buffer,
    pub(super) enclosing_stmt_link_b_buf: &'a wgpu::Buffer,
    pub(super) enclosing_stmt_steps: &'a [u32],
    pub(super) match_result_owner_a_buf: &'a wgpu::Buffer,
    pub(super) match_result_owner_b_buf: &'a wgpu::Buffer,
    pub(super) match_result_owner_link_a_buf: &'a wgpu::Buffer,
    pub(super) match_result_owner_link_b_buf: &'a wgpu::Buffer,
    pub(super) match_result_owner_steps: &'a [u32],
    pub(super) match_pattern_owner_a_buf: &'a wgpu::Buffer,
    pub(super) match_pattern_owner_b_buf: &'a wgpu::Buffer,
    pub(super) match_pattern_owner_link_a_buf: &'a wgpu::Buffer,
    pub(super) match_pattern_owner_link_b_buf: &'a wgpu::Buffer,
    pub(super) match_pattern_owner_steps: &'a [u32],
    pub(super) struct_type_record_buf: &'a wgpu::Buffer,
    pub(super) struct_access_record_buf: &'a wgpu::Buffer,
    pub(super) struct_store_record_buf: &'a wgpu::Buffer,
    pub(super) struct_record_status_buf: &'a wgpu::Buffer,
    pub(super) enum_type_record_buf: &'a wgpu::Buffer,
    pub(super) enum_record_status_buf: &'a wgpu::Buffer,
    pub(super) hir_param_record_buf: &'a wgpu::Buffer,
    pub(super) final_node_func_buf: &'a wgpu::Buffer,
    pub(super) node_inst_scan_input_buf: &'a wgpu::Buffer,
    pub(super) decl_node_by_token_buf: &'a wgpu::Buffer,
    pub(super) node_inst_scan_local_prefix_buf: &'a wgpu::Buffer,
    pub(super) final_node_inst_scan_prefix_buf: &'a wgpu::Buffer,
    pub(super) decl_layout_record_buf: &'a wgpu::Buffer,
    pub(super) decl_layout_status_buf: &'a wgpu::Buffer,
}

/// Creates bind groups for x86 semantic records, layouts, and ownership scans.
pub(super) fn create_semantic_record_bind_groups(
    generator: &GpuX86CodeGenerator,
    device: &wgpu::Device,
    inputs: SemanticRecordInputs<'_>,
) -> Result<SemanticRecordBindGroups> {
    let SemanticRecordInputs {
        params_buf,
        feature_params_buf,
        hir_status_buf,
        hir_kind_buf,
        parent_buf,
        subtree_end_buf,
        function_metadata,
        expr_metadata,
        call_metadata,
        array_metadata,
        struct_metadata,
        type_metadata,
        expr_resolved_final_buf,
        node_tree_status_buf,
        match_record_buf,
        match_return_node_buf,
        match_pattern_owner_buf,
        match_result_value_owner_buf,
        match_pattern_node_variant_buf,
        match_pattern_node_payload_decl_buf,
        match_pattern_first_use_node_buf,
        match_pattern_first_variant_node_buf,
        match_pattern_first_payload_node_buf,
        enclosing_return_node_a_buf,
        enclosing_return_node_b_buf,
        enclosing_return_link_a_buf,
        enclosing_return_link_b_buf,
        enclosing_return_steps,
        enclosing_let_node_a_buf,
        enclosing_let_node_b_buf,
        enclosing_let_link_a_buf,
        enclosing_let_link_b_buf,
        enclosing_let_steps,
        enclosing_let_step_final_buf,
        enclosing_stmt_node_a_buf,
        enclosing_stmt_node_b_buf,
        enclosing_stmt_link_a_buf,
        enclosing_stmt_link_b_buf,
        enclosing_stmt_steps,
        match_result_owner_a_buf,
        match_result_owner_b_buf,
        match_result_owner_link_a_buf,
        match_result_owner_link_b_buf,
        match_result_owner_steps,
        match_pattern_owner_a_buf,
        match_pattern_owner_b_buf,
        match_pattern_owner_link_a_buf,
        match_pattern_owner_link_b_buf,
        match_pattern_owner_steps,
        struct_type_record_buf,
        struct_access_record_buf,
        struct_store_record_buf,
        struct_record_status_buf,
        enum_type_record_buf,
        enum_record_status_buf,
        hir_param_record_buf,
        final_node_func_buf,
        node_inst_scan_input_buf,
        decl_node_by_token_buf,
        node_inst_scan_local_prefix_buf,
        final_node_inst_scan_prefix_buf,
        decl_layout_record_buf,
        decl_layout_status_buf,
    } = inputs;

    let enclosing_return_init = reflected_bind_group(
        device,
        Some("codegen.x86.enclosing_return_init.bind_group"),
        &generator.enclosing_return_init_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            ("x86_tree_parent", parent_buf.as_entire_binding()),
            (
                "x86_enclosing_return_node",
                enclosing_return_node_a_buf.as_entire_binding(),
            ),
            (
                "x86_enclosing_return_link",
                enclosing_return_link_a_buf.as_entire_binding(),
            ),
        ],
    )?;
    let enclosing_return_step = step_pair_groups(
        device,
        "codegen.x86.enclosing_return_step.bind_group",
        &generator.enclosing_return_step_pass,
        enclosing_return_steps,
        params_buf,
        hir_status_buf,
        &[],
        StepNames {
            first_in: "x86_enclosing_return_node_in",
            second_in: "x86_enclosing_return_link_in",
            first_out: "x86_enclosing_return_node_out",
            second_out: "x86_enclosing_return_link_out",
        },
        StepPairs {
            first_a: enclosing_return_node_a_buf,
            first_b: enclosing_return_node_b_buf,
            second_a: enclosing_return_link_a_buf,
            second_b: enclosing_return_link_b_buf,
        },
    )?;
    let enclosing_return_step_final_buf = if enclosing_return_steps.len() % 2 == 0 {
        enclosing_return_node_a_buf
    } else {
        enclosing_return_node_b_buf
    };
    let enclosing_let_init = reflected_bind_group(
        device,
        Some("codegen.x86.enclosing_let_init.bind_group"),
        &generator.enclosing_let_init_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            ("x86_tree_parent", parent_buf.as_entire_binding()),
            (
                "x86_enclosing_let_node",
                enclosing_let_node_a_buf.as_entire_binding(),
            ),
            (
                "x86_enclosing_let_link",
                enclosing_let_link_a_buf.as_entire_binding(),
            ),
        ],
    )?;
    let enclosing_let_step = step_pair_groups(
        device,
        "codegen.x86.enclosing_let_step.bind_group",
        &generator.enclosing_let_step_pass,
        enclosing_let_steps,
        params_buf,
        hir_status_buf,
        &[],
        StepNames {
            first_in: "x86_enclosing_let_node_in",
            second_in: "x86_enclosing_let_link_in",
            first_out: "x86_enclosing_let_node_out",
            second_out: "x86_enclosing_let_link_out",
        },
        StepPairs {
            first_a: enclosing_let_node_a_buf,
            first_b: enclosing_let_node_b_buf,
            second_a: enclosing_let_link_a_buf,
            second_b: enclosing_let_link_b_buf,
        },
    )?;
    let enclosing_stmt_init = reflected_bind_group(
        device,
        Some("codegen.x86.enclosing_stmt_init.bind_group"),
        &generator.enclosing_stmt_init_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            ("x86_tree_parent", parent_buf.as_entire_binding()),
            (
                "x86_enclosing_stmt_node",
                enclosing_stmt_node_a_buf.as_entire_binding(),
            ),
            (
                "x86_enclosing_stmt_link",
                enclosing_stmt_link_a_buf.as_entire_binding(),
            ),
        ],
    )?;
    let enclosing_stmt_step = step_pair_groups(
        device,
        "codegen.x86.enclosing_stmt_step.bind_group",
        &generator.enclosing_stmt_step_pass,
        enclosing_stmt_steps,
        params_buf,
        hir_status_buf,
        &[],
        StepNames {
            first_in: "x86_enclosing_stmt_node_in",
            second_in: "x86_enclosing_stmt_link_in",
            first_out: "x86_enclosing_stmt_node_out",
            second_out: "x86_enclosing_stmt_link_out",
        },
        StepPairs {
            first_a: enclosing_stmt_node_a_buf,
            first_b: enclosing_stmt_node_b_buf,
            second_a: enclosing_stmt_link_a_buf,
            second_b: enclosing_stmt_link_b_buf,
        },
    )?;
    let return_match_records = reflected_bind_group(
        device,
        Some("codegen.x86.return_match_records.bind_group"),
        &generator.return_match_records_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "x86_expr_resolved_node",
                expr_resolved_final_buf.as_entire_binding(),
            ),
            (
                "x86_enclosing_return_node",
                enclosing_return_step_final_buf.as_entire_binding(),
            ),
            (
                "x86_match_return_node",
                match_return_node_buf.as_entire_binding(),
            ),
        ],
    )?;
    let match_result_owner_init = reflected_bind_group(
        device,
        Some("codegen.x86.match_result_owner_init.bind_group"),
        &generator.match_result_owner_init_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("gX86Features", feature_params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            (
                "x86_match_result_root_owner",
                match_result_value_owner_buf.as_entire_binding(),
            ),
            ("x86_tree_parent", parent_buf.as_entire_binding()),
            (
                "x86_match_result_owner",
                match_result_owner_a_buf.as_entire_binding(),
            ),
            (
                "x86_match_result_owner_link",
                match_result_owner_link_a_buf.as_entire_binding(),
            ),
        ],
    )?;
    let match_result_owner_step = step_pair_groups(
        device,
        "codegen.x86.match_result_owner_step.bind_group",
        &generator.match_result_owner_step_pass,
        match_result_owner_steps,
        params_buf,
        hir_status_buf,
        &[],
        StepNames {
            first_in: "x86_match_result_owner_in",
            second_in: "x86_match_result_owner_link_in",
            first_out: "x86_match_result_owner_out",
            second_out: "x86_match_result_owner_link_out",
        },
        StepPairs {
            first_a: match_result_owner_a_buf,
            first_b: match_result_owner_b_buf,
            second_a: match_result_owner_link_a_buf,
            second_b: match_result_owner_link_b_buf,
        },
    )?;
    let match_ownership = reflected_bind_group(
        device,
        Some("codegen.x86.match_ownership.bind_group"),
        &generator.match_ownership_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "x86_expr_resolved_node",
                expr_resolved_final_buf.as_entire_binding(),
            ),
            (
                "x86_match_return_node",
                match_return_node_buf.as_entire_binding(),
            ),
            ("gX86Features", feature_params_buf.as_entire_binding()),
            ("x86_match_record", match_record_buf.as_entire_binding()),
            (
                "x86_match_pattern_owner",
                match_pattern_owner_buf.as_entire_binding(),
            ),
            (
                "x86_match_result_value_owner",
                match_result_value_owner_buf.as_entire_binding(),
            ),
        ],
    )?;
    let match_pattern_owner_init = reflected_bind_group(
        device,
        Some("codegen.x86.match_pattern_owner_init.bind_group"),
        &generator.match_pattern_owner_init_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("x86_tree_parent", parent_buf.as_entire_binding()),
            ("gX86Features", feature_params_buf.as_entire_binding()),
            ("x86_match_record", match_record_buf.as_entire_binding()),
            (
                "x86_match_pattern_owner",
                match_pattern_owner_buf.as_entire_binding(),
            ),
            (
                "x86_match_pattern_node_owner",
                match_pattern_owner_a_buf.as_entire_binding(),
            ),
            (
                "x86_match_pattern_owner_link",
                match_pattern_owner_link_a_buf.as_entire_binding(),
            ),
        ],
    )?;
    let match_pattern_owner_step = step_pair_groups(
        device,
        "codegen.x86.match_pattern_owner_step.bind_group",
        &generator.match_pattern_owner_step_pass,
        match_pattern_owner_steps,
        params_buf,
        hir_status_buf,
        &[],
        StepNames {
            first_in: "x86_match_pattern_node_owner_in",
            second_in: "x86_match_pattern_owner_link_in",
            first_out: "x86_match_pattern_node_owner_out",
            second_out: "x86_match_pattern_owner_link_out",
        },
        StepPairs {
            first_a: match_pattern_owner_a_buf,
            first_b: match_pattern_owner_b_buf,
            second_a: match_pattern_owner_link_a_buf,
            second_b: match_pattern_owner_link_b_buf,
        },
    )?;
    let match_pattern_finalize = reflected_bind_group(
        device,
        Some("codegen.x86.match_pattern_finalize.bind_group"),
        &generator.match_pattern_finalize_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            (
                "x86_match_pattern_node_variant",
                match_pattern_node_variant_buf.as_entire_binding(),
            ),
            (
                "x86_match_pattern_node_payload_decl",
                match_pattern_node_payload_decl_buf.as_entire_binding(),
            ),
            (
                "x86_match_pattern_first_use_node",
                match_pattern_first_use_node_buf.as_entire_binding(),
            ),
            (
                "x86_match_pattern_first_variant_node",
                match_pattern_first_variant_node_buf.as_entire_binding(),
            ),
            (
                "x86_match_pattern_first_payload_node",
                match_pattern_first_payload_node_buf.as_entire_binding(),
            ),
            ("gX86Features", feature_params_buf.as_entire_binding()),
            ("x86_match_record", match_record_buf.as_entire_binding()),
        ],
    )?;
    let struct_records = reflected_bind_group(
        device,
        Some("codegen.x86.struct_records.bind_group"),
        &generator.struct_records_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            (
                "hir_item_name_token",
                struct_metadata.item_name_token.as_entire_binding(),
            ),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "x86_expr_resolved_node",
                expr_resolved_final_buf.as_entire_binding(),
            ),
            (
                "hir_member_receiver_node",
                call_metadata.member_receiver_node.as_entire_binding(),
            ),
            (
                "hir_member_name_token",
                call_metadata.member_name_token.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_parent_lit",
                struct_metadata
                    .struct_lit_field_parent_lit
                    .as_entire_binding(),
            ),
            (
                "hir_struct_lit_head_node",
                struct_metadata.struct_lit_head_node.as_entire_binding(),
            ),
            (
                "hir_struct_lit_context_stmt_node",
                struct_metadata
                    .struct_lit_context_stmt_node
                    .as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_count",
                struct_metadata.struct_lit_field_count.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_start",
                struct_metadata.struct_lit_field_start.as_entire_binding(),
            ),
            (
                "hir_struct_decl_field_count",
                struct_metadata.struct_decl_field_count.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_value_node",
                struct_metadata
                    .struct_lit_field_value_node
                    .as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_next",
                struct_metadata.struct_lit_field_next.as_entire_binding(),
            ),
            (
                "member_result_field_ordinal",
                struct_metadata
                    .member_result_field_ordinal
                    .as_entire_binding(),
            ),
            (
                "struct_init_field_ordinal_by_node",
                struct_metadata
                    .struct_init_field_ordinal_by_node
                    .as_entire_binding(),
            ),
            (
                "hir_array_lit_first_element",
                array_metadata.lit_first_element.as_entire_binding(),
            ),
            (
                "hir_array_lit_element_count",
                array_metadata.lit_element_count.as_entire_binding(),
            ),
            (
                "hir_array_element_parent_lit",
                array_metadata.element_parent_lit.as_entire_binding(),
            ),
            (
                "hir_array_element_ordinal",
                array_metadata.element_ordinal.as_entire_binding(),
            ),
            (
                "hir_array_element_next",
                array_metadata.element_next.as_entire_binding(),
            ),
            ("x86_tree_parent", parent_buf.as_entire_binding()),
            (
                "x86_node_tree_status",
                node_tree_status_buf.as_entire_binding(),
            ),
            (
                "x86_enclosing_let_node",
                enclosing_let_step_final_buf.as_entire_binding(),
            ),
            (
                "x86_struct_type_record",
                struct_type_record_buf.as_entire_binding(),
            ),
            (
                "x86_struct_access_record",
                struct_access_record_buf.as_entire_binding(),
            ),
            (
                "x86_struct_store_record",
                struct_store_record_buf.as_entire_binding(),
            ),
            (
                "x86_struct_record_status",
                struct_record_status_buf.as_entire_binding(),
            ),
        ],
    )?;
    let array_records = reflected_bind_group(
        device,
        Some("codegen.x86.array_records.bind_group"),
        &generator.array_records_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "hir_node_decl_token",
                function_metadata.node_decl_token.as_entire_binding(),
            ),
            (
                "x86_expr_resolved_node",
                expr_resolved_final_buf.as_entire_binding(),
            ),
            (
                "hir_array_lit_first_element",
                array_metadata.lit_first_element.as_entire_binding(),
            ),
            (
                "hir_array_lit_element_count",
                array_metadata.lit_element_count.as_entire_binding(),
            ),
            (
                "hir_array_element_parent_lit",
                array_metadata.element_parent_lit.as_entire_binding(),
            ),
            (
                "hir_array_element_ordinal",
                array_metadata.element_ordinal.as_entire_binding(),
            ),
            (
                "hir_array_element_next",
                array_metadata.element_next.as_entire_binding(),
            ),
            (
                "x86_node_tree_status",
                node_tree_status_buf.as_entire_binding(),
            ),
            (
                "x86_enclosing_let_node",
                enclosing_let_step_final_buf.as_entire_binding(),
            ),
            (
                "x86_struct_access_record",
                struct_access_record_buf.as_entire_binding(),
            ),
            (
                "x86_struct_store_record",
                struct_store_record_buf.as_entire_binding(),
            ),
        ],
    )?;
    let decl_widths = reflected_bind_group(
        device,
        Some("codegen.x86.decl_widths.bind_group"),
        &generator.decl_widths_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "hir_call_callee_node",
                call_metadata.callee_node.as_entire_binding(),
            ),
            (
                "hir_member_name_token",
                call_metadata.member_name_token.as_entire_binding(),
            ),
            ("hir_type_form", expr_metadata.type_form.as_entire_binding()),
            (
                "hir_type_len_value",
                expr_metadata.type_len_value.as_entire_binding(),
            ),
            ("hir_param_record", hir_param_record_buf.as_entire_binding()),
            (
                "x86_expr_resolved_node",
                expr_resolved_final_buf.as_entire_binding(),
            ),
            ("x86_tree_parent", parent_buf.as_entire_binding()),
            ("x86_tree_subtree_end", subtree_end_buf.as_entire_binding()),
            (
                "x86_struct_access_record",
                struct_access_record_buf.as_entire_binding(),
            ),
            (
                "decl_type_ref_tag",
                type_metadata.decl_type_ref_tag.as_entire_binding(),
            ),
            (
                "decl_type_ref_payload",
                type_metadata.decl_type_ref_payload.as_entire_binding(),
            ),
            (
                "visible_type",
                type_metadata.visible_type.as_entire_binding(),
            ),
            (
                "type_instance_kind",
                type_metadata.type_instance_kind.as_entire_binding(),
            ),
            (
                "type_instance_decl_token",
                type_metadata.type_instance_decl_token.as_entire_binding(),
            ),
            (
                "type_instance_elem_ref_tag",
                type_metadata.type_instance_elem_ref_tag.as_entire_binding(),
            ),
            (
                "type_instance_elem_ref_payload",
                type_metadata
                    .type_instance_elem_ref_payload
                    .as_entire_binding(),
            ),
            (
                "type_instance_len_kind",
                type_metadata.type_instance_len_kind.as_entire_binding(),
            ),
            (
                "type_instance_len_payload",
                type_metadata.type_instance_len_payload.as_entire_binding(),
            ),
            (
                "x86_struct_type_record",
                struct_type_record_buf.as_entire_binding(),
            ),
            (
                "x86_struct_record_status",
                struct_record_status_buf.as_entire_binding(),
            ),
            (
                "x86_enum_type_record",
                enum_type_record_buf.as_entire_binding(),
            ),
            (
                "x86_enum_record_status",
                enum_record_status_buf.as_entire_binding(),
            ),
            (
                "call_return_type",
                call_metadata.call_return_type.as_entire_binding(),
            ),
            (
                "call_return_type_token",
                call_metadata.call_return_type_token.as_entire_binding(),
            ),
            (
                "x86_decl_width_by_node",
                node_inst_scan_input_buf.as_entire_binding(),
            ),
            (
                "x86_decl_node_by_token",
                decl_node_by_token_buf.as_entire_binding(),
            ),
        ],
    )?;
    let decl_layout = reflected_bind_group(
        device,
        Some("codegen.x86.decl_layout.bind_group"),
        &generator.decl_layout_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "hir_call_callee_node",
                call_metadata.callee_node.as_entire_binding(),
            ),
            (
                "hir_member_name_token",
                call_metadata.member_name_token.as_entire_binding(),
            ),
            ("hir_type_form", expr_metadata.type_form.as_entire_binding()),
            (
                "hir_type_len_value",
                expr_metadata.type_len_value.as_entire_binding(),
            ),
            ("hir_param_record", hir_param_record_buf.as_entire_binding()),
            (
                "x86_expr_resolved_node",
                expr_resolved_final_buf.as_entire_binding(),
            ),
            ("x86_node_func", final_node_func_buf.as_entire_binding()),
            ("x86_tree_parent", parent_buf.as_entire_binding()),
            ("x86_tree_subtree_end", subtree_end_buf.as_entire_binding()),
            (
                "x86_struct_access_record",
                struct_access_record_buf.as_entire_binding(),
            ),
            (
                "decl_type_ref_tag",
                type_metadata.decl_type_ref_tag.as_entire_binding(),
            ),
            (
                "decl_type_ref_payload",
                type_metadata.decl_type_ref_payload.as_entire_binding(),
            ),
            (
                "visible_type",
                type_metadata.visible_type.as_entire_binding(),
            ),
            (
                "type_instance_kind",
                type_metadata.type_instance_kind.as_entire_binding(),
            ),
            (
                "type_instance_decl_token",
                type_metadata.type_instance_decl_token.as_entire_binding(),
            ),
            (
                "type_instance_elem_ref_tag",
                type_metadata.type_instance_elem_ref_tag.as_entire_binding(),
            ),
            (
                "type_instance_elem_ref_payload",
                type_metadata
                    .type_instance_elem_ref_payload
                    .as_entire_binding(),
            ),
            (
                "type_instance_len_kind",
                type_metadata.type_instance_len_kind.as_entire_binding(),
            ),
            (
                "type_instance_len_payload",
                type_metadata.type_instance_len_payload.as_entire_binding(),
            ),
            (
                "x86_struct_type_record",
                struct_type_record_buf.as_entire_binding(),
            ),
            (
                "x86_struct_record_status",
                struct_record_status_buf.as_entire_binding(),
            ),
            (
                "x86_enum_type_record",
                enum_type_record_buf.as_entire_binding(),
            ),
            (
                "x86_enum_record_status",
                enum_record_status_buf.as_entire_binding(),
            ),
            (
                "x86_decl_width_by_node",
                node_inst_scan_input_buf.as_entire_binding(),
            ),
            (
                "x86_decl_node_by_token",
                decl_node_by_token_buf.as_entire_binding(),
            ),
            (
                "x86_decl_scan_local_prefix",
                node_inst_scan_local_prefix_buf.as_entire_binding(),
            ),
            (
                "x86_decl_scan_block_prefix",
                final_node_inst_scan_prefix_buf.as_entire_binding(),
            ),
            (
                "call_return_type",
                call_metadata.call_return_type.as_entire_binding(),
            ),
            (
                "call_return_type_token",
                call_metadata.call_return_type_token.as_entire_binding(),
            ),
            (
                "x86_decl_layout_record",
                decl_layout_record_buf.as_entire_binding(),
            ),
            (
                "x86_decl_layout_status",
                decl_layout_status_buf.as_entire_binding(),
            ),
        ],
    )?;

    Ok(SemanticRecordBindGroups {
        enclosing_return_init,
        enclosing_return_step,
        enclosing_let_init,
        enclosing_let_step,
        enclosing_stmt_init,
        enclosing_stmt_step,
        return_match_records,
        match_result_owner_init,
        match_result_owner_step,
        match_ownership,
        match_pattern_owner_init,
        match_pattern_owner_step,
        match_pattern_finalize,
        struct_records,
        array_records,
        decl_widths,
        decl_layout,
    })
}
