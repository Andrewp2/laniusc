use anyhow::Result;

use super::{
    super::{
        GpuX86CallMetadataBuffers,
        GpuX86CodeGenerator,
        GpuX86ExprMetadataBuffers,
        GpuX86FunctionMetadataBuffers,
        GpuX86TypeMetadataBuffers,
        support::reflected_bind_group,
    },
    bind_helpers::{StepNames, StepPairs, step_pair_groups},
};

/// Bind groups used to record calls, constants, parameter registers, and call ABI rows.
pub(super) struct CallRecordBindGroups {
    pub(super) call_records: wgpu::BindGroup,
    pub(super) call_callee_owner_init: wgpu::BindGroup,
    pub(super) call_callee_owner_step: Vec<wgpu::BindGroup>,
    pub(super) const_values: wgpu::BindGroup,
    pub(super) param_regs: wgpu::BindGroup,
    pub(super) local_literals: wgpu::BindGroup,
    pub(super) intrinsic_calls: wgpu::BindGroup,
    pub(super) call_abi: wgpu::BindGroup,
}

/// Buffer inputs needed by x86 call-recording passes.
pub(super) struct CallRecordInputs<'a> {
    pub(super) params_buf: &'a wgpu::Buffer,
    pub(super) feature_params_buf: &'a wgpu::Buffer,
    pub(super) hir_status_buf: &'a wgpu::Buffer,
    pub(super) hir_kind_buf: &'a wgpu::Buffer,
    pub(super) parent_buf: &'a wgpu::Buffer,
    pub(super) function_metadata: &'a GpuX86FunctionMetadataBuffers<'a>,
    pub(super) expr_metadata: &'a GpuX86ExprMetadataBuffers<'a>,
    pub(super) call_metadata: &'a GpuX86CallMetadataBuffers<'a>,
    pub(super) type_metadata: &'a GpuX86TypeMetadataBuffers<'a>,
    pub(super) visible_decl_buf: &'a wgpu::Buffer,
    pub(super) expr_resolved_final_buf: &'a wgpu::Buffer,
    pub(super) final_node_func_buf: &'a wgpu::Buffer,
    pub(super) call_record_buf: &'a wgpu::Buffer,
    pub(super) call_type_record_buf: &'a wgpu::Buffer,
    pub(super) call_callee_root_call_buf: &'a wgpu::Buffer,
    pub(super) call_record_status_buf: &'a wgpu::Buffer,
    pub(super) call_callee_owner_call_a_buf: &'a wgpu::Buffer,
    pub(super) call_callee_owner_call_b_buf: &'a wgpu::Buffer,
    pub(super) call_callee_owner_link_a_buf: &'a wgpu::Buffer,
    pub(super) call_callee_owner_link_b_buf: &'a wgpu::Buffer,
    pub(super) call_callee_owner_steps: &'a [u32],
    pub(super) const_value_record_buf: &'a wgpu::Buffer,
    pub(super) const_value_status_buf: &'a wgpu::Buffer,
    pub(super) fn_entrypoint_tag_buf: &'a wgpu::Buffer,
    pub(super) decl_node_by_token_buf: &'a wgpu::Buffer,
    pub(super) raw_to_compact_hir_buf: &'a wgpu::Buffer,
    pub(super) compact_hir_count_buf: &'a wgpu::Buffer,
    pub(super) compact_executable_raw_buf: &'a wgpu::Buffer,
    pub(super) compact_expr_wrapper_buf: &'a wgpu::Buffer,
    pub(super) decl_layout_record_buf: &'a wgpu::Buffer,
    pub(super) struct_type_record_buf: &'a wgpu::Buffer,
    pub(super) struct_record_status_buf: &'a wgpu::Buffer,
    pub(super) enum_type_record_buf: &'a wgpu::Buffer,
    pub(super) enum_value_record_buf: &'a wgpu::Buffer,
    pub(super) enum_record_status_buf: &'a wgpu::Buffer,
    pub(super) param_reg_record_buf: &'a wgpu::Buffer,
    pub(super) param_reg_status_buf: &'a wgpu::Buffer,
    pub(super) local_literal_record_buf: &'a wgpu::Buffer,
    pub(super) local_literal_status_buf: &'a wgpu::Buffer,
    pub(super) enclosing_stmt_step_final_buf: &'a wgpu::Buffer,
    pub(super) enclosing_let_step_final_buf: &'a wgpu::Buffer,
    pub(super) intrinsic_call_record_buf: &'a wgpu::Buffer,
    pub(super) intrinsic_call_status_buf: &'a wgpu::Buffer,
    pub(super) call_abi_record_buf: &'a wgpu::Buffer,
    pub(super) call_abi_status_buf: &'a wgpu::Buffer,
}

/// Creates bind groups for x86 call metadata recording.
pub(super) fn create_call_record_bind_groups(
    generator: &GpuX86CodeGenerator,
    device: &wgpu::Device,
    inputs: CallRecordInputs<'_>,
) -> Result<CallRecordBindGroups> {
    let CallRecordInputs {
        params_buf,
        feature_params_buf,
        hir_status_buf,
        hir_kind_buf,
        parent_buf,
        function_metadata,
        expr_metadata,
        call_metadata,
        type_metadata,
        visible_decl_buf,
        expr_resolved_final_buf,
        final_node_func_buf,
        call_record_buf,
        call_type_record_buf,
        call_callee_root_call_buf,
        call_record_status_buf,
        call_callee_owner_call_a_buf,
        call_callee_owner_call_b_buf,
        call_callee_owner_link_a_buf,
        call_callee_owner_link_b_buf,
        call_callee_owner_steps,
        const_value_record_buf,
        const_value_status_buf,
        fn_entrypoint_tag_buf,
        decl_node_by_token_buf,
        raw_to_compact_hir_buf,
        compact_hir_count_buf,
        compact_executable_raw_buf,
        compact_expr_wrapper_buf,
        decl_layout_record_buf,
        struct_type_record_buf,
        struct_record_status_buf,
        enum_type_record_buf,
        enum_value_record_buf,
        enum_record_status_buf,
        param_reg_record_buf,
        param_reg_status_buf,
        local_literal_record_buf,
        local_literal_status_buf,
        enclosing_stmt_step_final_buf,
        enclosing_let_step_final_buf,
        intrinsic_call_record_buf,
        intrinsic_call_status_buf,
        call_abi_record_buf,
        call_abi_status_buf,
    } = inputs;

    let call_records = reflected_bind_group(
        device,
        Some("codegen.x86.call_records.bind_group"),
        &generator.call_records_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("gX86Features", feature_params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            (
                "compact_hir_count",
                call_metadata.compact_hir_count.as_entire_binding(),
            ),
            (
                "compact_hir_core",
                call_metadata.compact_hir_core.as_entire_binding(),
            ),
            (
                "compact_hir_payload",
                call_metadata.compact_hir_payload.as_entire_binding(),
            ),
            (
                "compact_hir_links",
                call_metadata.compact_hir_links.as_entire_binding(),
            ),
            (
                "raw_to_compact_hir",
                raw_to_compact_hir_buf.as_entire_binding(),
            ),
            (
                "x86_compact_executable_raw",
                compact_executable_raw_buf.as_entire_binding(),
            ),
            (
                "x86_compact_expr_wrapper",
                compact_expr_wrapper_buf.as_entire_binding(),
            ),
            (
                "path_count_out",
                call_metadata.path_count_out.as_entire_binding(),
            ),
            (
                "path_id_by_owner_hir",
                call_metadata.path_id_by_owner_hir.as_entire_binding(),
            ),
            (
                "resolved_value_decl",
                call_metadata.resolved_value_decl.as_entire_binding(),
            ),
            (
                "resolved_value_status",
                call_metadata.resolved_value_status.as_entire_binding(),
            ),
            (
                "decl_name_token",
                call_metadata.decl_name_token.as_entire_binding(),
            ),
            (
                "hir_item_name_token",
                function_metadata.node_name_token.as_entire_binding(),
            ),
            (
                "x86_decl_node_by_token",
                decl_node_by_token_buf.as_entire_binding(),
            ),
            ("x86_node_func", final_node_func_buf.as_entire_binding()),
            ("x86_tree_parent", parent_buf.as_entire_binding()),
            (
                "call_fn_index",
                call_metadata.call_fn_index.as_entire_binding(),
            ),
            (
                "call_dependency_decl",
                call_metadata.call_dependency_decl.as_entire_binding(),
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
                "method_decl_receiver_mode",
                function_metadata
                    .method_decl_receiver_mode
                    .as_entire_binding(),
            ),
            ("x86_call_record", call_record_buf.as_entire_binding()),
            (
                "x86_call_type_record",
                call_type_record_buf.as_entire_binding(),
            ),
            (
                "x86_call_callee_root_call",
                call_callee_root_call_buf.as_entire_binding(),
            ),
            (
                "call_record_status",
                call_record_status_buf.as_entire_binding(),
            ),
        ],
    )?;
    let call_callee_owner_init = reflected_bind_group(
        device,
        Some("codegen.x86.call_callee_owner_init.bind_group"),
        &generator.call_callee_owner_init_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            ("x86_tree_parent", parent_buf.as_entire_binding()),
            (
                "hir_call_arg_parent_call",
                call_metadata.arg_parent_call.as_entire_binding(),
            ),
            (
                "hir_member_receiver_node",
                call_metadata.member_receiver_node.as_entire_binding(),
            ),
            (
                "x86_call_callee_root_call",
                call_callee_root_call_buf.as_entire_binding(),
            ),
            (
                "x86_call_callee_owner_call",
                call_callee_owner_call_a_buf.as_entire_binding(),
            ),
            (
                "x86_call_callee_owner_link",
                call_callee_owner_link_a_buf.as_entire_binding(),
            ),
        ],
    )?;
    let call_callee_owner_step = step_pair_groups(
        device,
        "codegen.x86.call_callee_owner_step.bind_group",
        &generator.call_callee_owner_step_pass,
        call_callee_owner_steps,
        params_buf,
        hir_status_buf,
        &[],
        StepNames {
            first_in: "x86_call_callee_owner_call_in",
            second_in: "x86_call_callee_owner_link_in",
            first_out: "x86_call_callee_owner_call_out",
            second_out: "x86_call_callee_owner_link_out",
        },
        StepPairs {
            first_a: call_callee_owner_call_a_buf,
            first_b: call_callee_owner_call_b_buf,
            second_a: call_callee_owner_link_a_buf,
            second_b: call_callee_owner_link_b_buf,
        },
    )?;
    let const_values = reflected_bind_group(
        device,
        Some("codegen.x86.const_values.bind_group"),
        &generator.const_values_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            (
                "compact_hir_count",
                expr_metadata.compact_hir_count.as_entire_binding(),
            ),
            (
                "compact_hir_core",
                expr_metadata.compact_hir_core.as_entire_binding(),
            ),
            (
                "compact_hir_payload",
                expr_metadata.compact_hir_payload.as_entire_binding(),
            ),
            (
                "compact_const_value",
                expr_metadata.compact_const_value.as_entire_binding(),
            ),
            (
                "x86_const_value_record",
                const_value_record_buf.as_entire_binding(),
            ),
            (
                "x86_const_value_status",
                const_value_status_buf.as_entire_binding(),
            ),
        ],
    )?;
    let param_regs = reflected_bind_group(
        device,
        Some("codegen.x86.param_regs.bind_group"),
        &generator.param_regs_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            (
                "hir_token_pos",
                function_metadata.hir_token_pos.as_entire_binding(),
            ),
            (
                "compact_hir_count",
                call_metadata.compact_hir_count.as_entire_binding(),
            ),
            (
                "compact_hir_core",
                call_metadata.compact_hir_core.as_entire_binding(),
            ),
            (
                "compact_hir_payload",
                call_metadata.compact_hir_payload.as_entire_binding(),
            ),
            (
                "compact_param_count",
                function_metadata.compact_param_count.as_entire_binding(),
            ),
            (
                "compact_params",
                function_metadata.compact_params.as_entire_binding(),
            ),
            (
                "x86_decl_node_by_token",
                decl_node_by_token_buf.as_entire_binding(),
            ),
            (
                "fn_entrypoint_tag",
                fn_entrypoint_tag_buf.as_entire_binding(),
            ),
            (
                "hir_fn_return_type_node",
                function_metadata.fn_return_type_node.as_entire_binding(),
            ),
            (
                "fn_return_ref_tag",
                function_metadata.fn_return_ref_tag.as_entire_binding(),
            ),
            (
                "fn_return_ref_payload",
                function_metadata.fn_return_ref_payload.as_entire_binding(),
            ),
            ("hir_type_form", expr_metadata.type_form.as_entire_binding()),
            (
                "hir_type_len_value",
                expr_metadata.type_len_value.as_entire_binding(),
            ),
            (
                "method_decl_param_offset",
                function_metadata
                    .method_decl_param_offset
                    .as_entire_binding(),
            ),
            (
                "method_decl_receiver_mode",
                function_metadata
                    .method_decl_receiver_mode
                    .as_entire_binding(),
            ),
            (
                "method_decl_receiver_ref_tag",
                function_metadata
                    .method_decl_receiver_ref_tag
                    .as_entire_binding(),
            ),
            (
                "method_decl_receiver_ref_payload",
                function_metadata
                    .method_decl_receiver_ref_payload
                    .as_entire_binding(),
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
                "call_param_type",
                call_metadata.call_param_type.as_entire_binding(),
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
                "x86_enum_value_record",
                enum_value_record_buf.as_entire_binding(),
            ),
            (
                "x86_enum_record_status",
                enum_record_status_buf.as_entire_binding(),
            ),
            (
                "x86_param_reg_record",
                param_reg_record_buf.as_entire_binding(),
            ),
            (
                "x86_param_reg_status",
                param_reg_status_buf.as_entire_binding(),
            ),
        ],
    )?;
    let local_literals = reflected_bind_group(
        device,
        Some("codegen.x86.local_literals.bind_group"),
        &generator.local_literals_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            ("x86_node_func", final_node_func_buf.as_entire_binding()),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "x86_expr_resolved_node",
                expr_resolved_final_buf.as_entire_binding(),
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
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            ("visible_decl", visible_decl_buf.as_entire_binding()),
            (
                "x86_const_value_record",
                const_value_record_buf.as_entire_binding(),
            ),
            (
                "x86_const_value_status",
                const_value_status_buf.as_entire_binding(),
            ),
            (
                "x86_local_literal_record",
                local_literal_record_buf.as_entire_binding(),
            ),
            (
                "x86_local_literal_status",
                local_literal_status_buf.as_entire_binding(),
            ),
        ],
    )?;
    let intrinsic_calls = reflected_bind_group(
        device,
        Some("codegen.x86.intrinsic_calls.bind_group"),
        &generator.intrinsic_calls_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            (
                "x86_enclosing_stmt_node",
                enclosing_stmt_step_final_buf.as_entire_binding(),
            ),
            ("x86_call_record", call_record_buf.as_entire_binding()),
            (
                "x86_call_type_record",
                call_type_record_buf.as_entire_binding(),
            ),
            (
                "call_record_status",
                call_record_status_buf.as_entire_binding(),
            ),
            (
                "call_intrinsic_tag",
                call_metadata.call_intrinsic_tag.as_entire_binding(),
            ),
            (
                "x86_intrinsic_call_record",
                intrinsic_call_record_buf.as_entire_binding(),
            ),
            (
                "x86_intrinsic_call_status",
                intrinsic_call_status_buf.as_entire_binding(),
            ),
        ],
    )?;
    let call_abi = reflected_bind_group(
        device,
        Some("codegen.x86.call_abi.bind_group"),
        &generator.call_abi_pass,
        0,
        &[
            ("gParams", params_buf.as_entire_binding()),
            ("gX86Features", feature_params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            (
                "hir_fn_return_type_node",
                function_metadata.fn_return_type_node.as_entire_binding(),
            ),
            ("hir_type_form", expr_metadata.type_form.as_entire_binding()),
            (
                "hir_type_len_value",
                expr_metadata.type_len_value.as_entire_binding(),
            ),
            (
                "x86_decl_node_by_token",
                decl_node_by_token_buf.as_entire_binding(),
            ),
            (
                "raw_to_compact_hir",
                raw_to_compact_hir_buf.as_entire_binding(),
            ),
            (
                "compact_hir_count",
                compact_hir_count_buf.as_entire_binding(),
            ),
            (
                "compact_hir_core",
                expr_metadata.compact_hir_core.as_entire_binding(),
            ),
            (
                "compact_hir_payload",
                expr_metadata.compact_hir_payload.as_entire_binding(),
            ),
            (
                "x86_compact_executable_raw",
                compact_executable_raw_buf.as_entire_binding(),
            ),
            (
                "x86_enclosing_let_node",
                enclosing_let_step_final_buf.as_entire_binding(),
            ),
            (
                "x86_decl_layout_record",
                decl_layout_record_buf.as_entire_binding(),
            ),
            ("x86_call_record", call_record_buf.as_entire_binding()),
            (
                "x86_call_type_record",
                call_type_record_buf.as_entire_binding(),
            ),
            (
                "call_record_status",
                call_record_status_buf.as_entire_binding(),
            ),
            (
                "call_intrinsic_tag",
                call_metadata.call_intrinsic_tag.as_entire_binding(),
            ),
            (
                "call_param_type",
                call_metadata.call_param_type.as_entire_binding(),
            ),
            (
                "name_id_by_token",
                call_metadata.name_id_by_token.as_entire_binding(),
            ),
            (
                "language_name_id",
                call_metadata.language_name_id.as_entire_binding(),
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
                "x86_enum_value_record",
                enum_value_record_buf.as_entire_binding(),
            ),
            (
                "x86_enum_record_status",
                enum_record_status_buf.as_entire_binding(),
            ),
            (
                "x86_call_abi_record",
                call_abi_record_buf.as_entire_binding(),
            ),
            ("call_abi_status", call_abi_status_buf.as_entire_binding()),
        ],
    )?;

    Ok(CallRecordBindGroups {
        call_records,
        call_callee_owner_init,
        call_callee_owner_step,
        const_values,
        param_regs,
        local_literals,
        intrinsic_calls,
        call_abi,
    })
}
