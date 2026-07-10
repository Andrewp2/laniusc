use anyhow::Result;

use super::super::{
    GpuX86ArrayMetadataBuffers,
    GpuX86CodeGenerator,
    GpuX86EnumMetadataBuffers,
    GpuX86ExprMetadataBuffers,
    GpuX86StructMetadataBuffers,
    support::reflected_bind_group,
};

/// Bind groups used to generate virtual x86 instruction records from HIR nodes.
pub(super) struct InstGenBindGroups {
    pub(super) input_status: wgpu::BindGroup,
    pub(super) clear_dispatch_args: wgpu::BindGroup,
    pub(super) clear_virtual_insts: wgpu::BindGroup,
    pub(super) generate: wgpu::BindGroup,
    pub(super) function_params: wgpu::BindGroup,
    pub(super) host_calls: wgpu::BindGroup,
    pub(super) for_stmt: wgpu::BindGroup,
    pub(super) control_stmt: wgpu::BindGroup,
    pub(super) aggregate_return_flags: wgpu::BindGroup,
    pub(super) aggregate_return_copy: wgpu::BindGroup,
    pub(super) aggregate_copy: wgpu::BindGroup,
}

/// Buffer inputs needed by x86 virtual-instruction generation passes.
pub(super) struct InstGenBindGroupInputs<'a> {
    pub(super) params: &'a wgpu::Buffer,
    pub(super) feature_params: &'a wgpu::Buffer,
    pub(super) hir_kind: &'a wgpu::Buffer,
    pub(super) hir_token_pos: &'a wgpu::Buffer,
    pub(super) parent: &'a wgpu::Buffer,
    pub(super) expr_metadata: &'a GpuX86ExprMetadataBuffers<'a>,
    pub(super) array_metadata: &'a GpuX86ArrayMetadataBuffers<'a>,
    pub(super) enum_metadata: &'a GpuX86EnumMetadataBuffers<'a>,
    pub(super) struct_metadata: &'a GpuX86StructMetadataBuffers<'a>,
    pub(super) expr_resolved_final: &'a wgpu::Buffer,
    pub(super) visible_decl: &'a wgpu::Buffer,
    pub(super) visible_type: &'a wgpu::Buffer,
    pub(super) method_decl_param_offset: &'a wgpu::Buffer,
    pub(super) method_decl_receiver_mode: &'a wgpu::Buffer,
    pub(super) struct_type_record: &'a wgpu::Buffer,
    pub(super) struct_field_width_by_node: &'a wgpu::Buffer,
    pub(super) decl_layout_record: &'a wgpu::Buffer,
    pub(super) decl_layout_status: &'a wgpu::Buffer,
    pub(super) const_value_record: &'a wgpu::Buffer,
    pub(super) const_value_status: &'a wgpu::Buffer,
    pub(super) local_literal_record: &'a wgpu::Buffer,
    pub(super) local_literal_status: &'a wgpu::Buffer,
    pub(super) param_reg_record: &'a wgpu::Buffer,
    pub(super) param_reg_status: &'a wgpu::Buffer,
    pub(super) call_abi_record: &'a wgpu::Buffer,
    pub(super) call_abi_status: &'a wgpu::Buffer,
    pub(super) hir_call_arg_count: &'a wgpu::Buffer,
    pub(super) hir_call_callee_node: &'a wgpu::Buffer,
    pub(super) hir_member_receiver_node: &'a wgpu::Buffer,
    pub(super) call_arg_row_node: &'a wgpu::Buffer,
    pub(super) call_arg_row_start: &'a wgpu::Buffer,
    pub(super) call_arg_row_count: &'a wgpu::Buffer,
    pub(super) intrinsic_call_record: &'a wgpu::Buffer,
    pub(super) enum_value_record: &'a wgpu::Buffer,
    pub(super) match_record: &'a wgpu::Buffer,
    pub(super) match_arm_owner: &'a wgpu::Buffer,
    pub(super) match_return_node: &'a wgpu::Buffer,
    pub(super) match_result_value_owner: &'a wgpu::Buffer,
    pub(super) struct_access_record: &'a wgpu::Buffer,
    pub(super) struct_store_record: &'a wgpu::Buffer,
    pub(super) struct_record_status: &'a wgpu::Buffer,
    pub(super) node_inst_range_info: &'a wgpu::Buffer,
    pub(super) node_inst_location_record: &'a wgpu::Buffer,
    pub(super) node_inst_location_status: &'a wgpu::Buffer,
    pub(super) node_inst_subtree_bound_start: &'a wgpu::Buffer,
    pub(super) node_inst_subtree_bound_end: &'a wgpu::Buffer,
    pub(super) expr_semantic_type_final: &'a wgpu::Buffer,
    pub(super) node_inst_scan_input: &'a wgpu::Buffer,
    pub(super) node_inst_gen_input_status: &'a wgpu::Buffer,
    pub(super) node_inst_gen_node_record: &'a wgpu::Buffer,
    pub(super) active_virtual_inst_dispatch_args: &'a wgpu::Buffer,
    pub(super) enclosing_return_step_final: &'a wgpu::Buffer,
    pub(super) enclosing_let_step_final: &'a wgpu::Buffer,
    pub(super) enclosing_loop_step_final: &'a wgpu::Buffer,
    pub(super) for_iterable_node: &'a wgpu::Buffer,
    pub(super) short_circuit_rhs_step_final: &'a wgpu::Buffer,
    pub(super) index_source_owner_step_final: &'a wgpu::Buffer,
    pub(super) final_node_func: &'a wgpu::Buffer,
    pub(super) func_slot_by_node: &'a wgpu::Buffer,
    pub(super) virtual_inst_record: &'a wgpu::Buffer,
    pub(super) virtual_inst_args: &'a wgpu::Buffer,
    pub(super) virtual_inst_status: &'a wgpu::Buffer,
}

/// Creates bind groups for x86 virtual-instruction generation.
pub(super) fn create_inst_gen_bind_groups(
    generator: &GpuX86CodeGenerator,
    device: &wgpu::Device,
    inputs: InstGenBindGroupInputs<'_>,
) -> Result<InstGenBindGroups> {
    let InstGenBindGroupInputs {
        params,
        feature_params,
        hir_kind,
        hir_token_pos,
        parent,
        expr_metadata,
        array_metadata,
        enum_metadata,
        struct_metadata,
        expr_resolved_final,
        visible_decl,
        visible_type,
        method_decl_param_offset,
        method_decl_receiver_mode,
        struct_type_record,
        struct_field_width_by_node,
        decl_layout_record,
        decl_layout_status,
        const_value_record,
        const_value_status,
        local_literal_record,
        local_literal_status,
        param_reg_record,
        param_reg_status,
        call_abi_record,
        call_abi_status,
        hir_call_arg_count,
        hir_call_callee_node,
        hir_member_receiver_node,
        call_arg_row_node,
        call_arg_row_start,
        call_arg_row_count,
        intrinsic_call_record,
        enum_value_record,
        match_record,
        match_arm_owner,
        match_return_node,
        match_result_value_owner,
        struct_access_record,
        struct_store_record,
        struct_record_status,
        node_inst_range_info,
        node_inst_location_record,
        node_inst_location_status,
        node_inst_subtree_bound_start,
        node_inst_subtree_bound_end,
        expr_semantic_type_final,
        node_inst_scan_input,
        node_inst_gen_input_status,
        node_inst_gen_node_record,
        active_virtual_inst_dispatch_args,
        enclosing_return_step_final,
        enclosing_let_step_final,
        enclosing_loop_step_final,
        for_iterable_node,
        short_circuit_rhs_step_final,
        index_source_owner_step_final,
        final_node_func,
        func_slot_by_node,
        virtual_inst_record,
        virtual_inst_args,
        virtual_inst_status,
    } = inputs;

    let input_status = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_gen_inputs.bind_group"),
        &generator.node_inst_gen_inputs_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "x86_node_inst_location_status",
                node_inst_location_status.as_entire_binding(),
            ),
            (
                "x86_const_value_status",
                const_value_status.as_entire_binding(),
            ),
            (
                "x86_decl_layout_status",
                decl_layout_status.as_entire_binding(),
            ),
            (
                "x86_local_literal_status",
                local_literal_status.as_entire_binding(),
            ),
            ("x86_param_reg_status", param_reg_status.as_entire_binding()),
            ("call_abi_status", call_abi_status.as_entire_binding()),
            (
                "x86_struct_record_status",
                struct_record_status.as_entire_binding(),
            ),
            (
                "x86_node_inst_gen_input_status",
                node_inst_gen_input_status.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
        ],
    )?;
    let clear_dispatch_args = reflected_bind_group(
        device,
        Some("codegen.x86.virtual_inst_clear_dispatch_args.bind_group"),
        &generator.virtual_inst_clear_dispatch_args_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "x86_node_inst_gen_input_status",
                node_inst_gen_input_status.as_entire_binding(),
            ),
            (
                "active_virtual_inst_dispatch_args",
                active_virtual_inst_dispatch_args.as_entire_binding(),
            ),
        ],
    )?;
    let clear_virtual_insts = reflected_bind_group(
        device,
        Some("codegen.x86.virtual_inst_clear.bind_group"),
        &generator.virtual_inst_clear_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "x86_node_inst_gen_input_status",
                node_inst_gen_input_status.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_args",
                virtual_inst_args.as_entire_binding(),
            ),
        ],
    )?;
    let generate = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_gen.bind_group"),
        &generator.node_inst_gen_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
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
            ("hir_token_pos", hir_token_pos.as_entire_binding()),
            ("x86_tree_parent", parent.as_entire_binding()),
            (
                "x86_expr_resolved_node",
                expr_resolved_final.as_entire_binding(),
            ),
            (
                "hir_expr_int_value",
                expr_metadata.int_value.as_entire_binding(),
            ),
            (
                "hir_expr_float_bits",
                expr_metadata.float_bits.as_entire_binding(),
            ),
            (
                "hir_expr_string_len",
                expr_metadata.string_len.as_entire_binding(),
            ),
            ("visible_decl", visible_decl.as_entire_binding()),
            ("visible_type", visible_type.as_entire_binding()),
            (
                "member_result_field_node",
                struct_metadata.member_result_field_node.as_entire_binding(),
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
                "x86_decl_layout_record",
                decl_layout_record.as_entire_binding(),
            ),
            (
                "x86_const_value_record",
                const_value_record.as_entire_binding(),
            ),
            (
                "x86_local_literal_record",
                local_literal_record.as_entire_binding(),
            ),
            ("x86_param_reg_record", param_reg_record.as_entire_binding()),
            ("x86_call_abi_record", call_abi_record.as_entire_binding()),
            ("hir_call_arg_count", hir_call_arg_count.as_entire_binding()),
            (
                "hir_call_callee_node",
                hir_call_callee_node.as_entire_binding(),
            ),
            (
                "hir_member_receiver_node",
                hir_member_receiver_node.as_entire_binding(),
            ),
            ("call_arg_row_node", call_arg_row_node.as_entire_binding()),
            ("call_arg_row_start", call_arg_row_start.as_entire_binding()),
            ("call_arg_row_count", call_arg_row_count.as_entire_binding()),
            (
                "x86_intrinsic_call_record",
                intrinsic_call_record.as_entire_binding(),
            ),
            (
                "x86_enum_value_record",
                enum_value_record.as_entire_binding(),
            ),
            ("gX86Features", feature_params.as_entire_binding()),
            ("x86_match_record", match_record.as_entire_binding()),
            ("x86_match_arm_owner", match_arm_owner.as_entire_binding()),
            (
                "x86_match_result_value_owner",
                match_result_value_owner.as_entire_binding(),
            ),
            (
                "x86_struct_access_record",
                struct_access_record.as_entire_binding(),
            ),
            (
                "x86_struct_store_record",
                struct_store_record.as_entire_binding(),
            ),
            (
                "x86_node_inst_range_info",
                node_inst_range_info.as_entire_binding(),
            ),
            (
                "x86_node_inst_location_record",
                node_inst_location_record.as_entire_binding(),
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
                "x86_expr_semantic_type",
                expr_semantic_type_final.as_entire_binding(),
            ),
            (
                "x86_node_inst_gen_input_status",
                node_inst_gen_input_status.as_entire_binding(),
            ),
            (
                "x86_node_inst_gen_node_record",
                node_inst_gen_node_record.as_entire_binding(),
            ),
            (
                "x86_enclosing_loop_node",
                enclosing_loop_step_final.as_entire_binding(),
            ),
            (
                "x86_for_iterable_node",
                for_iterable_node.as_entire_binding(),
            ),
            (
                "x86_short_circuit_rhs_node",
                short_circuit_rhs_step_final.as_entire_binding(),
            ),
            (
                "x86_index_source_owner",
                index_source_owner_step_final.as_entire_binding(),
            ),
            (
                "x86_match_return_node",
                match_return_node.as_entire_binding(),
            ),
            (
                "x86_enclosing_let_node",
                enclosing_let_step_final.as_entire_binding(),
            ),
            (
                "x86_enclosing_return_node",
                enclosing_return_step_final.as_entire_binding(),
            ),
            ("x86_node_func", final_node_func.as_entire_binding()),
            (
                "x86_func_slot_by_node",
                func_slot_by_node.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_args",
                virtual_inst_args.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
        ],
    )?;
    let function_params = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_gen_function_params.bind_group"),
        &generator.node_inst_gen_function_params_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_kind", hir_kind.as_entire_binding()),
            (
                "x86_decl_layout_record",
                decl_layout_record.as_entire_binding(),
            ),
            (
                "x86_node_inst_location_record",
                node_inst_location_record.as_entire_binding(),
            ),
            (
                "x86_node_inst_gen_input_status",
                node_inst_gen_input_status.as_entire_binding(),
            ),
            (
                "x86_node_inst_gen_node_record",
                node_inst_gen_node_record.as_entire_binding(),
            ),
            ("x86_node_func", final_node_func.as_entire_binding()),
            (
                "x86_func_slot_by_node",
                func_slot_by_node.as_entire_binding(),
            ),
            ("x86_param_reg_record", param_reg_record.as_entire_binding()),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_args",
                virtual_inst_args.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
        ],
    )?;
    let host_calls = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_gen_host_calls.bind_group"),
        &generator.node_inst_gen_host_calls_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_kind", hir_kind.as_entire_binding()),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "hir_expr_result_root_node",
                expr_metadata.expr_result_root_node.as_entire_binding(),
            ),
            ("hir_token_pos", hir_token_pos.as_entire_binding()),
            (
                "x86_expr_resolved_node",
                expr_resolved_final.as_entire_binding(),
            ),
            (
                "hir_expr_string_len",
                expr_metadata.string_len.as_entire_binding(),
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
                "decl_name_token",
                enum_metadata.decl_name_token.as_entire_binding(),
            ),
            (
                "x86_decl_layout_record",
                decl_layout_record.as_entire_binding(),
            ),
            ("x86_param_reg_record", param_reg_record.as_entire_binding()),
            ("x86_call_abi_record", call_abi_record.as_entire_binding()),
            ("hir_call_arg_count", hir_call_arg_count.as_entire_binding()),
            (
                "hir_call_callee_node",
                hir_call_callee_node.as_entire_binding(),
            ),
            (
                "hir_member_receiver_node",
                hir_member_receiver_node.as_entire_binding(),
            ),
            ("call_arg_row_node", call_arg_row_node.as_entire_binding()),
            ("call_arg_row_start", call_arg_row_start.as_entire_binding()),
            ("call_arg_row_count", call_arg_row_count.as_entire_binding()),
            (
                "x86_intrinsic_call_record",
                intrinsic_call_record.as_entire_binding(),
            ),
            (
                "x86_node_inst_range_info",
                node_inst_range_info.as_entire_binding(),
            ),
            (
                "x86_node_inst_location_record",
                node_inst_location_record.as_entire_binding(),
            ),
            (
                "x86_node_inst_gen_input_status",
                node_inst_gen_input_status.as_entire_binding(),
            ),
            (
                "x86_node_inst_gen_node_record",
                node_inst_gen_node_record.as_entire_binding(),
            ),
            (
                "x86_short_circuit_rhs_node",
                short_circuit_rhs_step_final.as_entire_binding(),
            ),
            ("x86_node_func", final_node_func.as_entire_binding()),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_args",
                virtual_inst_args.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
        ],
    )?;
    let for_stmt = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_gen_for_stmt.bind_group"),
        &generator.node_inst_gen_for_stmt_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
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
            ("hir_token_pos", hir_token_pos.as_entire_binding()),
            ("x86_tree_parent", parent.as_entire_binding()),
            (
                "x86_expr_resolved_node",
                expr_resolved_final.as_entire_binding(),
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
                "decl_name_token",
                enum_metadata.decl_name_token.as_entire_binding(),
            ),
            (
                "x86_decl_layout_record",
                decl_layout_record.as_entire_binding(),
            ),
            ("x86_param_reg_record", param_reg_record.as_entire_binding()),
            (
                "x86_for_iterable_node",
                for_iterable_node.as_entire_binding(),
            ),
            (
                "x86_node_inst_range_info",
                node_inst_range_info.as_entire_binding(),
            ),
            (
                "x86_node_inst_location_record",
                node_inst_location_record.as_entire_binding(),
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
                "x86_node_inst_gen_input_status",
                node_inst_gen_input_status.as_entire_binding(),
            ),
            (
                "x86_node_inst_gen_node_record",
                node_inst_gen_node_record.as_entire_binding(),
            ),
            ("x86_node_func", final_node_func.as_entire_binding()),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_args",
                virtual_inst_args.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
        ],
    )?;
    let control_stmt = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_gen_control_stmt.bind_group"),
        &generator.node_inst_gen_control_stmt_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_kind", hir_kind.as_entire_binding()),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            (
                "hir_expr_result_root_node",
                expr_metadata.expr_result_root_node.as_entire_binding(),
            ),
            (
                "x86_expr_resolved_node",
                expr_resolved_final.as_entire_binding(),
            ),
            (
                "x86_node_inst_range_info",
                node_inst_range_info.as_entire_binding(),
            ),
            (
                "x86_node_inst_location_record",
                node_inst_location_record.as_entire_binding(),
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
                "x86_node_inst_gen_input_status",
                node_inst_gen_input_status.as_entire_binding(),
            ),
            (
                "x86_node_inst_gen_node_record",
                node_inst_gen_node_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_args",
                virtual_inst_args.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
        ],
    )?;
    let aggregate_return_flags = reflected_bind_group(
        device,
        Some("codegen.x86.aggregate_literal_return_copy_flags.bind_group"),
        &generator.aggregate_literal_return_copy_flags_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "hir_array_element_parent_lit",
                array_metadata.element_parent_lit.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_parent_lit",
                struct_metadata
                    .struct_lit_field_parent_lit
                    .as_entire_binding(),
            ),
            (
                "x86_enclosing_return_node",
                enclosing_return_step_final.as_entire_binding(),
            ),
            (
                "x86_node_inst_gen_flag",
                node_inst_scan_input.as_entire_binding(),
            ),
        ],
    )?;
    let aggregate_return_copy = reflected_bind_group(
        device,
        Some("codegen.x86.aggregate_literal_return_copy.bind_group"),
        &generator.aggregate_literal_return_copy_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
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
            ("x86_tree_parent", parent.as_entire_binding()),
            ("hir_token_pos", hir_token_pos.as_entire_binding()),
            (
                "x86_expr_resolved_node",
                expr_resolved_final.as_entire_binding(),
            ),
            ("x86_node_func", final_node_func.as_entire_binding()),
            ("visible_decl", visible_decl.as_entire_binding()),
            (
                "method_decl_param_offset",
                method_decl_param_offset.as_entire_binding(),
            ),
            (
                "method_decl_receiver_mode",
                method_decl_receiver_mode.as_entire_binding(),
            ),
            (
                "x86_decl_layout_record",
                decl_layout_record.as_entire_binding(),
            ),
            (
                "x86_struct_access_record",
                struct_access_record.as_entire_binding(),
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
                "hir_struct_lit_field_parent_lit",
                struct_metadata
                    .struct_lit_field_parent_lit
                    .as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_value_node",
                struct_metadata
                    .struct_lit_field_value_node
                    .as_entire_binding(),
            ),
            (
                "struct_init_field_ordinal_by_node",
                struct_metadata
                    .struct_init_field_ordinal_by_node
                    .as_entire_binding(),
            ),
            (
                "x86_enclosing_return_node",
                enclosing_return_step_final.as_entire_binding(),
            ),
            (
                "x86_node_inst_range_info",
                node_inst_range_info.as_entire_binding(),
            ),
            (
                "x86_node_inst_location_record",
                node_inst_location_record.as_entire_binding(),
            ),
            (
                "x86_node_inst_gen_input_status",
                node_inst_gen_input_status.as_entire_binding(),
            ),
            (
                "x86_node_inst_gen_node_record",
                node_inst_gen_node_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_args",
                virtual_inst_args.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
        ],
    )?;
    let aggregate_copy = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_gen_aggregate_copy.bind_group"),
        &generator.node_inst_gen_aggregate_copy_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_kind", hir_kind.as_entire_binding()),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "x86_expr_resolved_node",
                expr_resolved_final.as_entire_binding(),
            ),
            ("visible_decl", visible_decl.as_entire_binding()),
            (
                "member_result_field_node",
                struct_metadata.member_result_field_node.as_entire_binding(),
            ),
            (
                "x86_struct_field_width_by_node",
                struct_field_width_by_node.as_entire_binding(),
            ),
            (
                "x86_struct_access_record",
                struct_access_record.as_entire_binding(),
            ),
            (
                "x86_struct_store_record",
                struct_store_record.as_entire_binding(),
            ),
            (
                "x86_decl_layout_record",
                decl_layout_record.as_entire_binding(),
            ),
            ("x86_param_reg_record", param_reg_record.as_entire_binding()),
            (
                "x86_node_inst_range_info",
                node_inst_range_info.as_entire_binding(),
            ),
            (
                "x86_node_inst_location_record",
                node_inst_location_record.as_entire_binding(),
            ),
            (
                "x86_node_inst_gen_input_status",
                node_inst_gen_input_status.as_entire_binding(),
            ),
            (
                "x86_node_inst_gen_node_record",
                node_inst_gen_node_record.as_entire_binding(),
            ),
            ("x86_node_func", final_node_func.as_entire_binding()),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_args",
                virtual_inst_args.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
        ],
    )?;

    Ok(InstGenBindGroups {
        input_status,
        clear_dispatch_args,
        clear_virtual_insts,
        generate,
        function_params,
        host_calls,
        for_stmt,
        control_stmt,
        aggregate_return_flags,
        aggregate_return_copy,
        aggregate_copy,
    })
}
