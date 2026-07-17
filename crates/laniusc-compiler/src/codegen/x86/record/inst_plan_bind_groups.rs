use anyhow::Result;

use super::{
    super::{
        GpuX86CallMetadataBuffers,
        GpuX86CodeGenerator,
        GpuX86EnumMetadataBuffers,
        GpuX86ExprMetadataBuffers,
        GpuX86FunctionMetadataBuffers,
        GpuX86StructMetadataBuffers,
        GpuX86TypeMetadataBuffers,
        support::{UniformBindingArray, reflected_bind_group},
    },
    bind_helpers::{
        StepNames,
        StepOne,
        StepOneNames,
        StepPairs,
        scan_block_groups,
        step_one_groups,
        step_pair_groups,
    },
};

/// Bind groups used to plan x86 instruction counts, ordering, and worklists.
pub(super) struct InstPlanBindGroups {
    pub(super) aggregate_source_init: wgpu::BindGroup,
    pub(super) aggregate_source_step: Vec<wgpu::BindGroup>,
    pub(super) for_iterable_nodes: wgpu::BindGroup,
    pub(super) control_padding: wgpu::BindGroup,
    pub(super) postfix_operand_owner: wgpu::BindGroup,
    pub(super) counts: wgpu::BindGroup,
    pub(super) same_end_rank_init: wgpu::BindGroup,
    pub(super) same_end_rank_step: Vec<wgpu::BindGroup>,
    pub(super) end_counts: wgpu::BindGroup,
    pub(super) order: wgpu::BindGroup,
    pub(super) scan_local: wgpu::BindGroup,
    pub(super) scan_block: Vec<wgpu::BindGroup>,
    pub(super) prefix_scan: wgpu::BindGroup,
    pub(super) subtree_bounds: wgpu::BindGroup,
    pub(super) semantic_type_init: wgpu::BindGroup,
    pub(super) semantic_type_step: Vec<wgpu::BindGroup>,
    pub(super) locations: wgpu::BindGroup,
    pub(super) worklist_scatter: wgpu::BindGroup,
    pub(super) worklist_dispatch_args: wgpu::BindGroup,
    pub(super) short_circuit_rhs_init: wgpu::BindGroup,
    pub(super) short_circuit_rhs_step: Vec<wgpu::BindGroup>,
    pub(super) index_source_owner_init: wgpu::BindGroup,
    pub(super) index_source_owner_step: Vec<wgpu::BindGroup>,
}

/// Buffer inputs needed by x86 instruction-planning passes.
pub(super) struct InstPlanBindGroupInputs<'a> {
    pub(super) params: &'a wgpu::Buffer,
    pub(super) feature_params: &'a wgpu::Buffer,
    pub(super) node_inst_scan_params: &'a UniformBindingArray,
    pub(super) hir_status: &'a wgpu::Buffer,
    pub(super) hir_kind: &'a wgpu::Buffer,
    pub(super) parent: &'a wgpu::Buffer,
    pub(super) subtree_end: &'a wgpu::Buffer,
    pub(super) function_metadata: &'a GpuX86FunctionMetadataBuffers<'a>,
    pub(super) expr_metadata: &'a GpuX86ExprMetadataBuffers<'a>,
    pub(super) call_metadata: &'a GpuX86CallMetadataBuffers<'a>,
    pub(super) enum_metadata: &'a GpuX86EnumMetadataBuffers<'a>,
    pub(super) struct_metadata: &'a GpuX86StructMetadataBuffers<'a>,
    pub(super) type_metadata: &'a GpuX86TypeMetadataBuffers<'a>,
    pub(super) hir_param_record: &'a wgpu::Buffer,
    pub(super) expr_resolved_final: &'a wgpu::Buffer,
    pub(super) final_node_func: &'a wgpu::Buffer,
    pub(super) visible_decl: &'a wgpu::Buffer,
    pub(super) const_value_record: &'a wgpu::Buffer,
    pub(super) struct_type_record: &'a wgpu::Buffer,
    pub(super) struct_field_width_by_node: &'a wgpu::Buffer,
    pub(super) decl_node_by_token: &'a wgpu::Buffer,
    pub(super) decl_layout_record: &'a wgpu::Buffer,
    pub(super) decl_layout_status: &'a wgpu::Buffer,
    pub(super) param_reg_record: &'a wgpu::Buffer,
    pub(super) node_tree_status: &'a wgpu::Buffer,
    pub(super) enclosing_return_step_final: &'a wgpu::Buffer,
    pub(super) match_return_node: &'a wgpu::Buffer,
    pub(super) call_record: &'a wgpu::Buffer,
    pub(super) call_type_record: &'a wgpu::Buffer,
    pub(super) call_callee_root_call: &'a wgpu::Buffer,
    pub(super) call_callee_owner_step_final: &'a wgpu::Buffer,
    pub(super) call_record_status: &'a wgpu::Buffer,
    pub(super) intrinsic_call_record: &'a wgpu::Buffer,
    pub(super) intrinsic_call_status: &'a wgpu::Buffer,
    pub(super) enum_value_record: &'a wgpu::Buffer,
    pub(super) enum_record_status: &'a wgpu::Buffer,
    pub(super) match_record: &'a wgpu::Buffer,
    pub(super) match_arm_record: &'a wgpu::Buffer,
    pub(super) match_pattern_node_owner: &'a wgpu::Buffer,
    pub(super) match_result_value_owner: &'a wgpu::Buffer,
    pub(super) struct_access_record: &'a wgpu::Buffer,
    pub(super) struct_store_record: &'a wgpu::Buffer,
    pub(super) aggregate_source_node_a: &'a wgpu::Buffer,
    pub(super) aggregate_source_node_b: &'a wgpu::Buffer,
    pub(super) aggregate_source_offset_a: &'a wgpu::Buffer,
    pub(super) aggregate_source_offset_b: &'a wgpu::Buffer,
    pub(super) aggregate_source_steps: &'a [u32],
    pub(super) struct_record_status: &'a wgpu::Buffer,
    pub(super) for_iterable_node: &'a wgpu::Buffer,
    pub(super) node_control_padding: &'a wgpu::Buffer,
    pub(super) postfix_operand_owner: &'a wgpu::Buffer,
    pub(super) node_inst_count_info: &'a wgpu::Buffer,
    pub(super) node_inst_count_payload: &'a wgpu::Buffer,
    pub(super) node_inst_count_status: &'a wgpu::Buffer,
    pub(super) node_inst_same_end_link_a: &'a wgpu::Buffer,
    pub(super) node_inst_same_end_link_b: &'a wgpu::Buffer,
    pub(super) node_inst_same_end_rank_a: &'a wgpu::Buffer,
    pub(super) node_inst_same_end_rank_b: &'a wgpu::Buffer,
    pub(super) node_inst_same_end_rank_final: &'a wgpu::Buffer,
    pub(super) node_inst_same_end_rank_steps: &'a [u32],
    pub(super) node_inst_scan_input: &'a wgpu::Buffer,
    pub(super) node_inst_order_record: &'a wgpu::Buffer,
    pub(super) node_inst_same_end_bucket_count: &'a wgpu::Buffer,
    pub(super) node_inst_subtree_slot_bounds: &'a wgpu::Buffer,
    pub(super) node_inst_range_start: &'a wgpu::Buffer,
    pub(super) node_inst_range_info: &'a wgpu::Buffer,
    pub(super) node_inst_range_status: &'a wgpu::Buffer,
    pub(super) node_inst_order_status: &'a wgpu::Buffer,
    pub(super) node_inst_scan_local_prefix: &'a wgpu::Buffer,
    pub(super) node_inst_scan_block_sum: &'a wgpu::Buffer,
    pub(super) node_inst_scan_prefix_a: &'a wgpu::Buffer,
    pub(super) node_inst_scan_prefix_b: &'a wgpu::Buffer,
    pub(super) final_node_inst_scan_prefix: &'a wgpu::Buffer,
    pub(super) node_inst_subtree_bound_start: &'a wgpu::Buffer,
    pub(super) node_inst_subtree_bound_end: &'a wgpu::Buffer,
    pub(super) node_inst_subtree_bounds_status: &'a wgpu::Buffer,
    pub(super) expr_semantic_type_a: &'a wgpu::Buffer,
    pub(super) expr_semantic_type_b: &'a wgpu::Buffer,
    pub(super) expr_semantic_type_final: &'a wgpu::Buffer,
    pub(super) expr_semantic_type_steps: &'a [u32],
    pub(super) node_inst_location_record: &'a wgpu::Buffer,
    pub(super) node_inst_location_status: &'a wgpu::Buffer,
    pub(super) node_inst_gen_node_record: &'a wgpu::Buffer,
    pub(super) node_inst_gen_input_status: &'a wgpu::Buffer,
    pub(super) active_node_inst_gen_dispatch_args: &'a wgpu::Buffer,
    pub(super) short_circuit_rhs_node_a: &'a wgpu::Buffer,
    pub(super) short_circuit_rhs_node_b: &'a wgpu::Buffer,
    pub(super) short_circuit_rhs_link_a: &'a wgpu::Buffer,
    pub(super) short_circuit_rhs_link_b: &'a wgpu::Buffer,
    pub(super) short_circuit_rhs_steps: &'a [u32],
    pub(super) index_source_owner_a: &'a wgpu::Buffer,
    pub(super) index_source_owner_b: &'a wgpu::Buffer,
    pub(super) index_source_link_a: &'a wgpu::Buffer,
    pub(super) index_source_link_b: &'a wgpu::Buffer,
    pub(super) index_source_owner_steps: &'a [u32],
}

/// Creates bind groups for x86 instruction planning and node worklist construction.
pub(super) fn create_inst_plan_bind_groups(
    generator: &GpuX86CodeGenerator,
    device: &wgpu::Device,
    inputs: InstPlanBindGroupInputs<'_>,
) -> Result<InstPlanBindGroups> {
    let InstPlanBindGroupInputs {
        params,
        feature_params,
        node_inst_scan_params,
        hir_status,
        hir_kind,
        parent,
        subtree_end,
        function_metadata,
        expr_metadata,
        call_metadata,
        enum_metadata,
        struct_metadata,
        type_metadata,
        hir_param_record,
        expr_resolved_final,
        final_node_func,
        visible_decl,
        const_value_record,
        struct_type_record,
        struct_field_width_by_node,
        decl_node_by_token,
        decl_layout_record,
        decl_layout_status,
        param_reg_record,
        node_tree_status,
        enclosing_return_step_final,
        match_return_node,
        call_record,
        call_type_record,
        call_callee_root_call,
        call_callee_owner_step_final,
        call_record_status,
        intrinsic_call_record,
        intrinsic_call_status,
        enum_value_record,
        enum_record_status,
        match_record,
        match_arm_record,
        match_pattern_node_owner,
        match_result_value_owner,
        struct_access_record,
        struct_store_record,
        aggregate_source_node_a,
        aggregate_source_node_b,
        aggregate_source_offset_a,
        aggregate_source_offset_b,
        aggregate_source_steps,
        struct_record_status,
        for_iterable_node,
        node_control_padding,
        postfix_operand_owner,
        node_inst_count_info,
        node_inst_count_payload,
        node_inst_count_status,
        node_inst_same_end_link_a,
        node_inst_same_end_link_b,
        node_inst_same_end_rank_a,
        node_inst_same_end_rank_b,
        node_inst_same_end_rank_final,
        node_inst_same_end_rank_steps,
        node_inst_scan_input,
        node_inst_order_record,
        node_inst_same_end_bucket_count,
        node_inst_subtree_slot_bounds,
        node_inst_range_start,
        node_inst_range_info,
        node_inst_range_status,
        node_inst_order_status,
        node_inst_scan_local_prefix,
        node_inst_scan_block_sum,
        node_inst_scan_prefix_a,
        node_inst_scan_prefix_b,
        final_node_inst_scan_prefix,
        node_inst_subtree_bound_start,
        node_inst_subtree_bound_end,
        node_inst_subtree_bounds_status,
        expr_semantic_type_a,
        expr_semantic_type_b,
        expr_semantic_type_final,
        expr_semantic_type_steps,
        node_inst_location_record,
        node_inst_location_status,
        node_inst_gen_node_record,
        node_inst_gen_input_status,
        active_node_inst_gen_dispatch_args,
        short_circuit_rhs_node_a,
        short_circuit_rhs_node_b,
        short_circuit_rhs_link_a,
        short_circuit_rhs_link_b,
        short_circuit_rhs_steps,
        index_source_owner_a,
        index_source_owner_b,
        index_source_link_a,
        index_source_link_b,
        index_source_owner_steps,
    } = inputs;

    let aggregate_source_init = reflected_bind_group(
        device,
        Some("codegen.x86.aggregate_source_init.bind_group"),
        &generator.aggregate_source_init_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_status", hir_status.as_entire_binding()),
            ("hir_kind", hir_kind.as_entire_binding()),
            (
                "x86_expr_resolved_node",
                expr_resolved_final.as_entire_binding(),
            ),
            (
                "x86_struct_access_record",
                struct_access_record.as_entire_binding(),
            ),
            (
                "x86_aggregate_source_node_out",
                aggregate_source_node_a.as_entire_binding(),
            ),
            (
                "x86_aggregate_source_offset_out",
                aggregate_source_offset_a.as_entire_binding(),
            ),
        ],
    )?;
    let aggregate_source_step = step_pair_groups(
        device,
        "codegen.x86.aggregate_source_step.bind_group",
        &generator.aggregate_source_step_pass,
        aggregate_source_steps,
        params,
        hir_status,
        &[],
        StepNames {
            first_in: "x86_aggregate_source_node_in",
            second_in: "x86_aggregate_source_offset_in",
            first_out: "x86_aggregate_source_node_out",
            second_out: "x86_aggregate_source_offset_out",
        },
        StepPairs {
            first_a: aggregate_source_node_a,
            first_b: aggregate_source_node_b,
            second_a: aggregate_source_offset_a,
            second_b: aggregate_source_offset_b,
        },
    )?;

    let for_iterable_nodes = reflected_bind_group(
        device,
        Some("codegen.x86.for_iterable_nodes.bind_group"),
        &generator.for_iterable_nodes_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_status", hir_status.as_entire_binding()),
            ("hir_kind", hir_kind.as_entire_binding()),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "x86_for_iterable_node",
                for_iterable_node.as_entire_binding(),
            ),
        ],
    )?;
    let control_padding = reflected_bind_group(
        device,
        Some("codegen.x86.node_control_padding.bind_group"),
        &generator.node_control_padding_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("gX86Features", feature_params.as_entire_binding()),
            ("hir_status", hir_status.as_entire_binding()),
            ("hir_kind", hir_kind.as_entire_binding()),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            ("x86_match_record", match_record.as_entire_binding()),
            (
                "x86_match_return_node",
                match_return_node.as_entire_binding(),
            ),
            (
                "x86_match_result_value_owner",
                match_result_value_owner.as_entire_binding(),
            ),
            (
                "x86_for_iterable_node",
                for_iterable_node.as_entire_binding(),
            ),
            (
                "x86_decl_layout_record",
                decl_layout_record.as_entire_binding(),
            ),
            (
                "x86_node_control_padding",
                node_control_padding.as_entire_binding(),
            ),
        ],
    )?;
    let postfix_operand_owner_bind_group = reflected_bind_group(
        device,
        Some("codegen.x86.postfix_operand_owner.bind_group"),
        &generator.postfix_operand_owner_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_status", hir_status.as_entire_binding()),
            ("hir_kind", hir_kind.as_entire_binding()),
            (
                "hir_expr_result_root_node",
                expr_metadata.expr_result_root_node.as_entire_binding(),
            ),
            (
                "x86_postfix_operand_owner",
                postfix_operand_owner.as_entire_binding(),
            ),
        ],
    )?;
    let counts = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_counts.bind_group"),
        &generator.node_inst_counts_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_status", hir_status.as_entire_binding()),
            ("hir_kind", hir_kind.as_entire_binding()),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "hir_expr_result_root_node",
                expr_metadata.expr_result_root_node.as_entire_binding(),
            ),
            ("hir_param_record", hir_param_record.as_entire_binding()),
            ("x86_tree_parent", parent.as_entire_binding()),
            (
                "x86_expr_resolved_node",
                expr_resolved_final.as_entire_binding(),
            ),
            ("x86_node_func", final_node_func.as_entire_binding()),
            ("visible_decl", visible_decl.as_entire_binding()),
            (
                "member_result_field_node",
                struct_metadata.member_result_field_node.as_entire_binding(),
            ),
            (
                "x86_decl_node_by_token",
                decl_node_by_token.as_entire_binding(),
            ),
            (
                "x86_struct_field_width_by_node",
                struct_field_width_by_node.as_entire_binding(),
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
                "decl_name_token",
                enum_metadata.decl_name_token.as_entire_binding(),
            ),
            (
                "x86_struct_type_record",
                struct_type_record.as_entire_binding(),
            ),
            (
                "call_fn_index",
                call_metadata.call_fn_index.as_entire_binding(),
            ),
            (
                "x86_decl_layout_record",
                decl_layout_record.as_entire_binding(),
            ),
            (
                "x86_decl_layout_status",
                decl_layout_status.as_entire_binding(),
            ),
            (
                "x86_const_value_record",
                const_value_record.as_entire_binding(),
            ),
            ("x86_param_reg_record", param_reg_record.as_entire_binding()),
            ("x86_node_tree_status", node_tree_status.as_entire_binding()),
            (
                "x86_for_iterable_node",
                for_iterable_node.as_entire_binding(),
            ),
            (
                "x86_node_control_padding",
                node_control_padding.as_entire_binding(),
            ),
            (
                "x86_postfix_operand_owner",
                postfix_operand_owner.as_entire_binding(),
            ),
            (
                "x86_enclosing_return_node",
                enclosing_return_step_final.as_entire_binding(),
            ),
            (
                "x86_match_return_node",
                match_return_node.as_entire_binding(),
            ),
            ("x86_call_record", call_record.as_entire_binding()),
            (
                "x86_call_callee_root_call",
                call_callee_root_call.as_entire_binding(),
            ),
            (
                "x86_call_callee_owner_call",
                call_callee_owner_step_final.as_entire_binding(),
            ),
            ("call_record_status", call_record_status.as_entire_binding()),
            (
                "x86_intrinsic_call_record",
                intrinsic_call_record.as_entire_binding(),
            ),
            (
                "x86_intrinsic_call_status",
                intrinsic_call_status.as_entire_binding(),
            ),
            (
                "x86_enum_value_record",
                enum_value_record.as_entire_binding(),
            ),
            (
                "x86_enum_record_status",
                enum_record_status.as_entire_binding(),
            ),
            ("gX86Features", feature_params.as_entire_binding()),
            ("x86_match_record", match_record.as_entire_binding()),
            (
                "x86_match_pattern_node_owner",
                match_pattern_node_owner.as_entire_binding(),
            ),
            (
                "x86_match_result_value_owner",
                match_result_value_owner.as_entire_binding(),
            ),
            (
                "x86_struct_access_record",
                struct_access_record.as_entire_binding(),
            ),
            (
                "x86_aggregate_source_node",
                aggregate_source_node_a.as_entire_binding(),
            ),
            (
                "x86_aggregate_source_offset",
                aggregate_source_offset_a.as_entire_binding(),
            ),
            (
                "x86_struct_store_record",
                struct_store_record.as_entire_binding(),
            ),
            (
                "x86_struct_record_status",
                struct_record_status.as_entire_binding(),
            ),
            (
                "x86_node_inst_count_info",
                node_inst_count_info.as_entire_binding(),
            ),
            (
                "x86_node_inst_count_payload",
                node_inst_count_payload.as_entire_binding(),
            ),
            (
                "x86_node_inst_count_status",
                node_inst_count_status.as_entire_binding(),
            ),
        ],
    )?;
    let same_end_rank_init = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_same_end_rank_init.bind_group"),
        &generator.node_inst_same_end_rank_init_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_status", hir_status.as_entire_binding()),
            ("x86_tree_parent", parent.as_entire_binding()),
            ("x86_tree_subtree_end", subtree_end.as_entire_binding()),
            ("x86_node_tree_status", node_tree_status.as_entire_binding()),
            (
                "x86_node_inst_count_info",
                node_inst_count_info.as_entire_binding(),
            ),
            (
                "x86_node_inst_count_payload",
                node_inst_count_payload.as_entire_binding(),
            ),
            (
                "x86_node_inst_count_status",
                node_inst_count_status.as_entire_binding(),
            ),
            (
                "x86_node_inst_same_end_link",
                node_inst_same_end_link_a.as_entire_binding(),
            ),
            (
                "x86_node_inst_same_end_rank",
                node_inst_same_end_rank_a.as_entire_binding(),
            ),
        ],
    )?;
    let same_end_rank_step = step_pair_groups(
        device,
        "codegen.x86.node_inst_same_end_rank_step.bind_group",
        &generator.node_inst_same_end_rank_step_pass,
        node_inst_same_end_rank_steps,
        params,
        hir_status,
        &[],
        StepNames {
            first_in: "x86_node_inst_same_end_link_in",
            second_in: "x86_node_inst_same_end_rank_in",
            first_out: "x86_node_inst_same_end_link_out",
            second_out: "x86_node_inst_same_end_rank_out",
        },
        StepPairs {
            first_a: node_inst_same_end_link_a,
            first_b: node_inst_same_end_link_b,
            second_a: node_inst_same_end_rank_a,
            second_b: node_inst_same_end_rank_b,
        },
    )?;
    let end_counts = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_end_counts.bind_group"),
        &generator.node_inst_end_counts_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_status", hir_status.as_entire_binding()),
            ("x86_tree_subtree_end", subtree_end.as_entire_binding()),
            ("x86_node_tree_status", node_tree_status.as_entire_binding()),
            (
                "x86_node_inst_count_info",
                node_inst_count_info.as_entire_binding(),
            ),
            (
                "x86_node_inst_count_payload",
                node_inst_count_payload.as_entire_binding(),
            ),
            (
                "x86_node_inst_count_status",
                node_inst_count_status.as_entire_binding(),
            ),
            (
                "x86_node_inst_scan_input",
                node_inst_scan_input.as_entire_binding(),
            ),
        ],
    )?;
    let order = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_order.bind_group"),
        &generator.node_inst_order_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_status", hir_status.as_entire_binding()),
            ("x86_tree_subtree_end", subtree_end.as_entire_binding()),
            ("x86_node_tree_status", node_tree_status.as_entire_binding()),
            (
                "x86_node_inst_count_info",
                node_inst_count_info.as_entire_binding(),
            ),
            (
                "x86_node_inst_count_payload",
                node_inst_count_payload.as_entire_binding(),
            ),
            (
                "x86_node_inst_count_status",
                node_inst_count_status.as_entire_binding(),
            ),
            (
                "x86_node_inst_same_end_rank",
                node_inst_same_end_rank_final.as_entire_binding(),
            ),
            (
                "x86_node_inst_scan_local_prefix",
                node_inst_scan_local_prefix.as_entire_binding(),
            ),
            (
                "x86_node_inst_scan_block_prefix",
                final_node_inst_scan_prefix.as_entire_binding(),
            ),
            (
                "x86_node_inst_order_record",
                node_inst_order_record.as_entire_binding(),
            ),
            (
                "x86_node_inst_same_end_bucket_count",
                node_inst_same_end_bucket_count.as_entire_binding(),
            ),
            (
                "x86_node_inst_subtree_slot_bounds",
                node_inst_subtree_slot_bounds.as_entire_binding(),
            ),
            (
                "x86_node_inst_range_start",
                node_inst_range_start.as_entire_binding(),
            ),
            (
                "x86_node_inst_range_info",
                node_inst_range_info.as_entire_binding(),
            ),
            (
                "x86_node_inst_scan_input",
                node_inst_scan_input.as_entire_binding(),
            ),
            (
                "x86_node_inst_order_status",
                node_inst_order_status.as_entire_binding(),
            ),
        ],
    )?;
    let scan_local = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_scan_local.bind_group"),
        &generator.node_inst_scan_local_pass,
        0,
        &[
            ("gScan", node_inst_scan_params.binding(0)),
            (
                "x86_node_inst_scan_input",
                node_inst_scan_input.as_entire_binding(),
            ),
            (
                "x86_node_inst_scan_local_prefix",
                node_inst_scan_local_prefix.as_entire_binding(),
            ),
            (
                "x86_node_inst_scan_block_sum",
                node_inst_scan_block_sum.as_entire_binding(),
            ),
        ],
    )?;
    let scan_block = scan_block_groups(
        device,
        [
            "codegen.x86.node_inst_scan_blocks.even.bind_group",
            "codegen.x86.node_inst_scan_blocks.odd.bind_group",
        ],
        &generator.node_inst_scan_blocks_pass,
        node_inst_scan_params,
        "gNodeInstBlockScan",
        "x86_node_inst_scan_block_sum",
        "x86_node_inst_scan_block_prefix_in",
        "x86_node_inst_scan_block_prefix_out",
        node_inst_scan_block_sum,
        node_inst_scan_prefix_a,
        node_inst_scan_prefix_b,
    )?;
    let prefix_scan = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_prefix_scan.bind_group"),
        &generator.node_inst_prefix_scan_pass,
        0,
        &[
            ("gScan", node_inst_scan_params.binding(0)),
            (
                "x86_node_inst_order_record",
                node_inst_order_record.as_entire_binding(),
            ),
            (
                "x86_node_inst_count_info",
                node_inst_count_info.as_entire_binding(),
            ),
            (
                "x86_node_inst_count_payload",
                node_inst_count_payload.as_entire_binding(),
            ),
            (
                "x86_node_inst_order_status",
                node_inst_order_status.as_entire_binding(),
            ),
            (
                "x86_node_inst_scan_local_prefix",
                node_inst_scan_local_prefix.as_entire_binding(),
            ),
            (
                "x86_node_inst_scan_block_prefix",
                final_node_inst_scan_prefix.as_entire_binding(),
            ),
            (
                "x86_node_inst_range_start",
                node_inst_range_start.as_entire_binding(),
            ),
            (
                "x86_node_inst_range_info",
                node_inst_range_info.as_entire_binding(),
            ),
            (
                "x86_node_inst_range_status",
                node_inst_range_status.as_entire_binding(),
            ),
        ],
    )?;
    let subtree_bounds = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_subtree_bounds.bind_group"),
        &generator.node_inst_subtree_bounds_pass,
        0,
        &[
            ("gScan", node_inst_scan_params.binding(0)),
            (
                "x86_node_inst_subtree_slot_bounds",
                node_inst_subtree_slot_bounds.as_entire_binding(),
            ),
            (
                "x86_node_inst_range_status",
                node_inst_range_status.as_entire_binding(),
            ),
            (
                "x86_node_inst_scan_local_prefix",
                node_inst_scan_local_prefix.as_entire_binding(),
            ),
            (
                "x86_node_inst_scan_block_prefix",
                final_node_inst_scan_prefix.as_entire_binding(),
            ),
            (
                "x86_node_inst_subtree_bound_start",
                node_inst_subtree_bound_start.as_entire_binding(),
            ),
            (
                "x86_node_inst_subtree_bound_end",
                node_inst_subtree_bound_end.as_entire_binding(),
            ),
            (
                "x86_node_inst_subtree_bounds_status",
                node_inst_subtree_bounds_status.as_entire_binding(),
            ),
        ],
    )?;
    let semantic_type_init = reflected_bind_group(
        device,
        Some("codegen.x86.expr_semantic_type_init.bind_group"),
        &generator.expr_semantic_type_init_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_status", hir_status.as_entire_binding()),
            ("hir_kind", hir_kind.as_entire_binding()),
            (
                "hir_token_pos",
                function_metadata.hir_token_pos.as_entire_binding(),
            ),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "hir_expr_result_root_node",
                expr_metadata.expr_result_root_node.as_entire_binding(),
            ),
            ("visible_decl", visible_decl.as_entire_binding()),
            (
                "visible_type",
                type_metadata.visible_type.as_entire_binding(),
            ),
            (
                "call_return_type",
                call_metadata.call_return_type.as_entire_binding(),
            ),
            ("x86_call_type_record", call_type_record.as_entire_binding()),
            (
                "x86_decl_layout_record",
                decl_layout_record.as_entire_binding(),
            ),
            ("x86_param_reg_record", param_reg_record.as_entire_binding()),
            (
                "x86_struct_access_record",
                struct_access_record.as_entire_binding(),
            ),
            (
                "x86_expr_semantic_record",
                expr_semantic_type_a.as_entire_binding(),
            ),
        ],
    )?;
    let semantic_type_step = step_one_groups(
        device,
        "codegen.x86.expr_semantic_type_step.bind_group",
        &generator.expr_semantic_type_step_pass,
        expr_semantic_type_steps,
        params,
        hir_status,
        StepOneNames {
            in_name: "x86_expr_semantic_record_in",
            out_name: "x86_expr_semantic_record_out",
        },
        StepOne {
            a: expr_semantic_type_a,
            b: expr_semantic_type_b,
        },
    )?;
    let locations = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_locations.bind_group"),
        &generator.node_inst_locations_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_status", hir_status.as_entire_binding()),
            ("hir_kind", hir_kind.as_entire_binding()),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            ("hir_param_record", hir_param_record.as_entire_binding()),
            (
                "x86_expr_resolved_node",
                expr_resolved_final.as_entire_binding(),
            ),
            (
                "x86_expr_semantic_type",
                expr_semantic_type_final.as_entire_binding(),
            ),
            ("gX86Features", feature_params.as_entire_binding()),
            ("x86_match_record", match_record.as_entire_binding()),
            ("x86_match_arm_record", match_arm_record.as_entire_binding()),
            (
                "x86_for_iterable_node",
                for_iterable_node.as_entire_binding(),
            ),
            (
                "x86_decl_layout_record",
                decl_layout_record.as_entire_binding(),
            ),
            (
                "x86_node_inst_range_start",
                node_inst_range_start.as_entire_binding(),
            ),
            (
                "x86_node_inst_range_info",
                node_inst_range_info.as_entire_binding(),
            ),
            (
                "x86_node_inst_same_end_rank",
                node_inst_same_end_rank_final.as_entire_binding(),
            ),
            (
                "x86_node_inst_same_end_bucket_count",
                node_inst_same_end_bucket_count.as_entire_binding(),
            ),
            (
                "x86_node_inst_range_status",
                node_inst_range_status.as_entire_binding(),
            ),
            (
                "x86_node_inst_location_record",
                node_inst_location_record.as_entire_binding(),
            ),
            (
                "x86_node_inst_location_status",
                node_inst_location_status.as_entire_binding(),
            ),
            (
                "x86_node_inst_gen_flag",
                node_inst_scan_input.as_entire_binding(),
            ),
        ],
    )?;
    let worklist_scatter = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_gen_worklist_scatter.bind_group"),
        &generator.node_inst_gen_worklist_scatter_pass,
        0,
        &[
            ("gScan", node_inst_scan_params.binding(0)),
            (
                "x86_node_inst_gen_flag",
                node_inst_scan_input.as_entire_binding(),
            ),
            (
                "x86_node_inst_scan_local_prefix",
                node_inst_scan_local_prefix.as_entire_binding(),
            ),
            (
                "x86_node_inst_scan_block_prefix",
                final_node_inst_scan_prefix.as_entire_binding(),
            ),
            (
                "x86_node_inst_gen_node_record",
                node_inst_gen_node_record.as_entire_binding(),
            ),
            (
                "x86_node_inst_gen_input_status",
                node_inst_gen_input_status.as_entire_binding(),
            ),
        ],
    )?;
    let worklist_dispatch_args = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_gen_worklist_dispatch_args.bind_group"),
        &generator.node_inst_gen_worklist_dispatch_args_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "x86_node_inst_gen_input_status",
                node_inst_gen_input_status.as_entire_binding(),
            ),
            (
                "active_node_inst_gen_dispatch_args",
                active_node_inst_gen_dispatch_args.as_entire_binding(),
            ),
        ],
    )?;
    let short_circuit_rhs_init = reflected_bind_group(
        device,
        Some("codegen.x86.short_circuit_rhs_init.bind_group"),
        &generator.short_circuit_rhs_init_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_status", hir_status.as_entire_binding()),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "x86_expr_resolved_node",
                expr_resolved_final.as_entire_binding(),
            ),
            ("x86_tree_parent", parent.as_entire_binding()),
            (
                "x86_short_circuit_rhs_node",
                short_circuit_rhs_node_a.as_entire_binding(),
            ),
            (
                "x86_short_circuit_rhs_link",
                short_circuit_rhs_link_a.as_entire_binding(),
            ),
        ],
    )?;
    let short_circuit_rhs_step = step_pair_groups(
        device,
        "codegen.x86.short_circuit_rhs_step.bind_group",
        &generator.short_circuit_rhs_step_pass,
        short_circuit_rhs_steps,
        params,
        hir_status,
        &[],
        StepNames {
            first_in: "x86_short_circuit_rhs_node_in",
            second_in: "x86_short_circuit_rhs_link_in",
            first_out: "x86_short_circuit_rhs_node_out",
            second_out: "x86_short_circuit_rhs_link_out",
        },
        StepPairs {
            first_a: short_circuit_rhs_node_a,
            first_b: short_circuit_rhs_node_b,
            second_a: short_circuit_rhs_link_a,
            second_b: short_circuit_rhs_link_b,
        },
    )?;
    let index_source_owner_init = reflected_bind_group(
        device,
        Some("codegen.x86.index_source_owner_init.bind_group"),
        &generator.index_source_owner_init_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_status", hir_status.as_entire_binding()),
            ("hir_kind", hir_kind.as_entire_binding()),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "x86_expr_resolved_node",
                expr_resolved_final.as_entire_binding(),
            ),
            ("x86_tree_parent", parent.as_entire_binding()),
            (
                "x86_index_source_owner",
                index_source_owner_a.as_entire_binding(),
            ),
            (
                "x86_index_source_link",
                index_source_link_a.as_entire_binding(),
            ),
        ],
    )?;
    let index_source_owner_step = step_pair_groups(
        device,
        "codegen.x86.index_source_owner_step.bind_group",
        &generator.index_source_owner_step_pass,
        index_source_owner_steps,
        params,
        hir_status,
        &[],
        StepNames {
            first_in: "x86_index_source_owner_in",
            second_in: "x86_index_source_link_in",
            first_out: "x86_index_source_owner_out",
            second_out: "x86_index_source_link_out",
        },
        StepPairs {
            first_a: index_source_owner_a,
            first_b: index_source_owner_b,
            second_a: index_source_link_a,
            second_b: index_source_link_b,
        },
    )?;

    Ok(InstPlanBindGroups {
        aggregate_source_init,
        aggregate_source_step,
        for_iterable_nodes,
        control_padding,
        postfix_operand_owner: postfix_operand_owner_bind_group,
        counts,
        same_end_rank_init,
        same_end_rank_step,
        end_counts,
        order,
        scan_local,
        scan_block,
        prefix_scan,
        subtree_bounds,
        semantic_type_init,
        semantic_type_step,
        locations,
        worklist_scatter,
        worklist_dispatch_args,
        short_circuit_rhs_init,
        short_circuit_rhs_step,
        index_source_owner_init,
        index_source_owner_step,
    })
}
