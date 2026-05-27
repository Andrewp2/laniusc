use anyhow::Result;

use super::{
    super::{
        GpuX86CodeGenerator,
        support::{
            UniformBindingArray,
            dispatch_compute_pass_indirect,
            dispatch_compute_pass_indirect_bind_group_steps,
            dispatch_compute_pass_indirect_ping_pong_scan_steps,
            dispatch_x86_stage,
            dispatch_x86_stage_indirect,
            dispatch_x86_stages_indirect,
            init_repeated_u32_words,
        },
    },
    timing::stamp_timer,
};

pub(super) struct MetadataCallDispatchInputs<'a, 'timer> {
    pub(super) device: &'a wgpu::Device,
    pub(super) queue: &'a wgpu::Queue,
    pub(super) encoder: &'a mut wgpu::CommandEncoder,
    pub(super) timer: &'a mut Option<&'timer mut crate::gpu::timer::GpuTimer>,
    pub(super) hir_words: usize,
    pub(super) match_record_rows: usize,
    pub(super) has_match: bool,
    pub(super) needs_enclosing_return_records: bool,
    pub(super) node_func_owner_needs_copyback: bool,
    pub(super) enclosing_let_needs_copyback: bool,
    pub(super) match_pattern_owner_needs_copyback: bool,
    pub(super) active_hir_dispatch_args_buf: &'a wgpu::Buffer,
    pub(super) hir_count: &'a wgpu::Buffer,
    pub(super) hir_plus_one: &'a wgpu::Buffer,
    pub(super) hir_scan_block: &'a wgpu::Buffer,
    pub(super) func_owner_scan_params_buf: &'a UniformBindingArray,
    pub(super) node_inst_scan_params_buf: &'a UniformBindingArray,
    pub(super) node_func_owner_b_buf: &'a wgpu::Buffer,
    pub(super) node_func_buf: &'a wgpu::Buffer,
    pub(super) expr_resolved_step_final_buf: &'a wgpu::Buffer,
    pub(super) expr_resolved_final_buf: &'a wgpu::Buffer,
    pub(super) match_result_owner_step_final_buf: &'a wgpu::Buffer,
    pub(super) match_result_value_owner_buf: &'a wgpu::Buffer,
    pub(super) enclosing_let_node_b_buf: &'a wgpu::Buffer,
    pub(super) enclosing_let_node_a_buf: &'a wgpu::Buffer,
    pub(super) match_pattern_owner_step_final_buf: &'a wgpu::Buffer,
    pub(super) match_pattern_node_owner_buf: &'a wgpu::Buffer,
    pub(super) match_pattern_first_use_node_buf: &'a wgpu::Buffer,
    pub(super) func_meta_buf: &'a wgpu::Buffer,
    pub(super) func_meta_uniform_buf: &'a wgpu::Buffer,
    pub(super) const_value_status_buf: &'a wgpu::Buffer,
    pub(super) const_value_status_uniform_buf: &'a wgpu::Buffer,
    pub(super) param_reg_status_buf: &'a wgpu::Buffer,
    pub(super) param_reg_status_uniform_buf: &'a wgpu::Buffer,
    pub(super) local_literal_status_buf: &'a wgpu::Buffer,
    pub(super) local_literal_status_uniform_buf: &'a wgpu::Buffer,
    pub(super) intrinsic_call_record_buf: &'a wgpu::Buffer,
    pub(super) call_abi_status_buf: &'a wgpu::Buffer,
    pub(super) call_abi_status_uniform_buf: &'a wgpu::Buffer,
    pub(super) active_scan_dispatch_args_bind_group: &'a wgpu::BindGroup,
    pub(super) node_tree_info_bind_group: &'a wgpu::BindGroup,
    pub(super) func_bind_group: &'a wgpu::BindGroup,
    pub(super) func_owner_scan_local_bind_group: &'a wgpu::BindGroup,
    pub(super) func_owner_scan_block_bind_groups: &'a [wgpu::BindGroup],
    pub(super) func_assign_nodes_bind_group: &'a wgpu::BindGroup,
    pub(super) func_assign_nodes_step_bind_groups: &'a [wgpu::BindGroup],
    pub(super) func_slot_flags_bind_group: &'a wgpu::BindGroup,
    pub(super) func_slot_scatter_bind_group: &'a wgpu::BindGroup,
    pub(super) expr_resolve_init_bind_group: &'a wgpu::BindGroup,
    pub(super) expr_resolve_step_bind_groups: &'a [wgpu::BindGroup],
    pub(super) enum_records_bind_group: &'a wgpu::BindGroup,
    pub(super) match_records_bind_group: &'a wgpu::BindGroup,
    pub(super) return_match_records_bind_group: &'a wgpu::BindGroup,
    pub(super) match_result_owner_init_bind_group: &'a wgpu::BindGroup,
    pub(super) match_result_owner_step_bind_groups: &'a [wgpu::BindGroup],
    pub(super) enclosing_return_init_bind_group: &'a wgpu::BindGroup,
    pub(super) enclosing_return_step_bind_groups: &'a [wgpu::BindGroup],
    pub(super) enclosing_let_init_bind_group: &'a wgpu::BindGroup,
    pub(super) enclosing_let_step_bind_groups: &'a [wgpu::BindGroup],
    pub(super) match_ownership_bind_group: &'a wgpu::BindGroup,
    pub(super) match_pattern_owner_init_bind_group: &'a wgpu::BindGroup,
    pub(super) match_pattern_owner_step_bind_groups: &'a [wgpu::BindGroup],
    pub(super) match_pattern_records_bind_group: &'a wgpu::BindGroup,
    pub(super) match_pattern_finalize_bind_group: &'a wgpu::BindGroup,
    pub(super) struct_records_bind_group: &'a wgpu::BindGroup,
    pub(super) array_records_bind_group: &'a wgpu::BindGroup,
    pub(super) enclosing_stmt_init_bind_group: &'a wgpu::BindGroup,
    pub(super) enclosing_stmt_step_bind_groups: &'a [wgpu::BindGroup],
    pub(super) decl_widths_bind_group: &'a wgpu::BindGroup,
    pub(super) decl_layout_bind_group: &'a wgpu::BindGroup,
    pub(super) node_inst_scan_local_bind_group: &'a wgpu::BindGroup,
    pub(super) node_inst_scan_block_bind_groups: &'a [wgpu::BindGroup],
    pub(super) node_inst_scan_input_clear_bind_group: &'a wgpu::BindGroup,
    pub(super) call_callee_root_call_clear_bind_group: &'a wgpu::BindGroup,
    pub(super) call_records_bind_group: &'a wgpu::BindGroup,
    pub(super) const_values_bind_group: &'a wgpu::BindGroup,
    pub(super) param_regs_bind_group: &'a wgpu::BindGroup,
    pub(super) local_literals_bind_group: &'a wgpu::BindGroup,
    pub(super) call_arg_values_bind_group: &'a wgpu::BindGroup,
    pub(super) intrinsic_calls_bind_group: &'a wgpu::BindGroup,
    pub(super) call_abi_bind_group: &'a wgpu::BindGroup,
    pub(super) call_callee_owner_init_bind_group: &'a wgpu::BindGroup,
    pub(super) call_callee_owner_step_bind_groups: &'a [wgpu::BindGroup],
}

pub(super) fn record_metadata_and_call_dispatches(
    generator: &GpuX86CodeGenerator,
    inputs: MetadataCallDispatchInputs<'_, '_>,
) -> Result<()> {
    let MetadataCallDispatchInputs {
        device,
        queue,
        encoder,
        timer,
        hir_words,
        match_record_rows,
        has_match,
        needs_enclosing_return_records,
        node_func_owner_needs_copyback,
        enclosing_let_needs_copyback,
        match_pattern_owner_needs_copyback,
        active_hir_dispatch_args_buf,
        hir_count,
        hir_plus_one,
        hir_scan_block,
        func_owner_scan_params_buf,
        node_inst_scan_params_buf,
        node_func_owner_b_buf,
        node_func_buf,
        expr_resolved_step_final_buf,
        expr_resolved_final_buf,
        match_result_owner_step_final_buf,
        match_result_value_owner_buf,
        enclosing_let_node_b_buf,
        enclosing_let_node_a_buf,
        match_pattern_owner_step_final_buf,
        match_pattern_node_owner_buf,
        match_pattern_first_use_node_buf,
        func_meta_buf,
        func_meta_uniform_buf,
        const_value_status_buf,
        const_value_status_uniform_buf,
        param_reg_status_buf,
        param_reg_status_uniform_buf,
        local_literal_status_buf,
        local_literal_status_uniform_buf,
        intrinsic_call_record_buf,
        call_abi_status_buf,
        call_abi_status_uniform_buf,
        active_scan_dispatch_args_bind_group,
        node_tree_info_bind_group,
        func_bind_group,
        func_owner_scan_local_bind_group,
        func_owner_scan_block_bind_groups,
        func_assign_nodes_bind_group,
        func_assign_nodes_step_bind_groups,
        func_slot_flags_bind_group,
        func_slot_scatter_bind_group,
        expr_resolve_init_bind_group,
        expr_resolve_step_bind_groups,
        enum_records_bind_group,
        match_records_bind_group,
        return_match_records_bind_group,
        match_result_owner_init_bind_group,
        match_result_owner_step_bind_groups,
        enclosing_return_init_bind_group,
        enclosing_return_step_bind_groups,
        enclosing_let_init_bind_group,
        enclosing_let_step_bind_groups,
        match_ownership_bind_group,
        match_pattern_owner_init_bind_group,
        match_pattern_owner_step_bind_groups,
        match_pattern_records_bind_group,
        match_pattern_finalize_bind_group,
        struct_records_bind_group,
        array_records_bind_group,
        enclosing_stmt_init_bind_group,
        enclosing_stmt_step_bind_groups,
        decl_widths_bind_group,
        decl_layout_bind_group,
        node_inst_scan_local_bind_group,
        node_inst_scan_block_bind_groups,
        node_inst_scan_input_clear_bind_group,
        call_callee_root_call_clear_bind_group,
        call_records_bind_group,
        const_values_bind_group,
        param_regs_bind_group,
        local_literals_bind_group,
        call_arg_values_bind_group,
        intrinsic_calls_bind_group,
        call_abi_bind_group,
        call_callee_owner_init_bind_group,
        call_callee_owner_step_bind_groups,
    } = inputs;

    dispatch_x86_stage(
        encoder,
        "active_scan_dispatch_args",
        &generator.active_scan_dispatch_args_pass,
        active_scan_dispatch_args_bind_group,
        (1, 1),
    );
    stamp_timer(timer, encoder, "x86.metadata.active_dispatch.done");
    dispatch_x86_stages_indirect(
        encoder,
        &[
            (
                "node_tree_info",
                &generator.node_tree_info_pass,
                node_tree_info_bind_group,
            ),
            (
                "func_discover",
                &generator.func_discover_pass,
                func_bind_group,
            ),
        ],
        active_hir_dispatch_args_buf,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "func_owner_scan_local",
        &generator.func_owner_scan_local_pass,
        func_owner_scan_local_bind_group,
        active_hir_dispatch_args_buf,
    );
    dispatch_compute_pass_indirect_ping_pong_scan_steps(
        encoder,
        "func_owner_scan_blocks",
        "codegen.x86.func_owner_scan_blocks",
        &generator.func_owner_scan_blocks_pass,
        func_owner_scan_block_bind_groups,
        func_owner_scan_params_buf,
        hir_scan_block,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "func_assign_nodes",
        &generator.func_assign_nodes_pass,
        func_assign_nodes_bind_group,
        active_hir_dispatch_args_buf,
    );
    dispatch_compute_pass_indirect_bind_group_steps(
        encoder,
        "func_assign_nodes_step",
        "codegen.x86.func_assign_nodes_step",
        &generator.func_assign_nodes_step_pass,
        func_assign_nodes_step_bind_groups,
        active_hir_dispatch_args_buf,
    );
    if node_func_owner_needs_copyback {
        encoder.copy_buffer_to_buffer(
            node_func_owner_b_buf,
            0,
            node_func_buf,
            0,
            (hir_words * 4) as u64,
        );
    }
    dispatch_x86_stages_indirect(
        encoder,
        &[
            (
                "func_slot_flags",
                &generator.func_slot_flags_pass,
                func_slot_flags_bind_group,
            ),
            (
                "func_slot_scan_local",
                &generator.node_inst_scan_local_pass,
                node_inst_scan_local_bind_group,
            ),
        ],
        hir_plus_one,
    );
    dispatch_compute_pass_indirect_ping_pong_scan_steps(
        encoder,
        "func_slot_scan_blocks",
        "codegen.x86.node_inst_scan_blocks",
        &generator.node_inst_scan_blocks_pass,
        node_inst_scan_block_bind_groups,
        node_inst_scan_params_buf,
        hir_scan_block,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "func_slot_scatter",
        &generator.func_slot_scatter_pass,
        func_slot_scatter_bind_group,
        hir_plus_one,
    );
    stamp_timer(timer, encoder, "x86.metadata.func_owner.done");
    dispatch_x86_stage_indirect(
        encoder,
        "expr_resolve_init",
        &generator.expr_resolve_init_pass,
        expr_resolve_init_bind_group,
        active_hir_dispatch_args_buf,
    );
    dispatch_compute_pass_indirect_bind_group_steps(
        encoder,
        "expr_resolve_step",
        "codegen.x86.expr_resolve_step",
        &generator.expr_resolve_step_pass,
        expr_resolve_step_bind_groups,
        active_hir_dispatch_args_buf,
    );
    encoder.copy_buffer_to_buffer(
        expr_resolved_step_final_buf,
        0,
        expr_resolved_final_buf,
        0,
        (hir_words * 4) as u64,
    );
    stamp_timer(timer, encoder, "x86.metadata.expr_resolve.done");
    dispatch_x86_stages_indirect(
        encoder,
        &[
            (
                "enum_records",
                &generator.enum_records_pass,
                enum_records_bind_group,
            ),
            (
                "match_records",
                &generator.match_records_pass,
                match_records_bind_group,
            ),
            (
                "return_match_records",
                &generator.return_match_records_pass,
                return_match_records_bind_group,
            ),
            (
                "match_result_owner_init",
                &generator.match_result_owner_init_pass,
                match_result_owner_init_bind_group,
            ),
        ],
        active_hir_dispatch_args_buf,
    );
    dispatch_compute_pass_indirect_bind_group_steps(
        encoder,
        "match_result_owner_step",
        "codegen.x86.match_result_owner_step",
        &generator.match_result_owner_step_pass,
        match_result_owner_step_bind_groups,
        active_hir_dispatch_args_buf,
    );
    encoder.copy_buffer_to_buffer(
        match_result_owner_step_final_buf,
        0,
        match_result_value_owner_buf,
        0,
        (match_record_rows * 4) as u64,
    );
    stamp_timer(timer, encoder, "x86.metadata.match_result.done");
    if needs_enclosing_return_records {
        dispatch_x86_stage_indirect(
            encoder,
            "enclosing_return_init",
            &generator.enclosing_return_init_pass,
            enclosing_return_init_bind_group,
            active_hir_dispatch_args_buf,
        );
        dispatch_compute_pass_indirect_bind_group_steps(
            encoder,
            "enclosing_return_step",
            "codegen.x86.enclosing_return_step",
            &generator.enclosing_return_step_pass,
            enclosing_return_step_bind_groups,
            active_hir_dispatch_args_buf,
        );
    }
    dispatch_x86_stage_indirect(
        encoder,
        "enclosing_let_init",
        &generator.enclosing_let_init_pass,
        enclosing_let_init_bind_group,
        active_hir_dispatch_args_buf,
    );
    dispatch_compute_pass_indirect_bind_group_steps(
        encoder,
        "enclosing_let_step",
        "codegen.x86.enclosing_let_step",
        &generator.enclosing_let_step_pass,
        enclosing_let_step_bind_groups,
        active_hir_dispatch_args_buf,
    );
    if enclosing_let_needs_copyback {
        encoder.copy_buffer_to_buffer(
            enclosing_let_node_b_buf,
            0,
            enclosing_let_node_a_buf,
            0,
            (hir_words * 4) as u64,
        );
    }
    stamp_timer(timer, encoder, "x86.metadata.enclosing_flow.done");
    dispatch_x86_stages_indirect(
        encoder,
        &[
            (
                "match_ownership",
                &generator.match_ownership_pass,
                match_ownership_bind_group,
            ),
            (
                "match_pattern_owner_init",
                &generator.match_pattern_owner_init_pass,
                match_pattern_owner_init_bind_group,
            ),
        ],
        active_hir_dispatch_args_buf,
    );
    dispatch_compute_pass_indirect_bind_group_steps(
        encoder,
        "match_pattern_owner_step",
        "codegen.x86.match_pattern_owner_step",
        &generator.match_pattern_owner_step_pass,
        match_pattern_owner_step_bind_groups,
        active_hir_dispatch_args_buf,
    );
    if match_pattern_owner_needs_copyback {
        encoder.copy_buffer_to_buffer(
            match_pattern_owner_step_final_buf,
            0,
            match_pattern_node_owner_buf,
            0,
            (hir_words * 4) as u64,
        );
    }
    init_repeated_u32_words(
        device,
        queue,
        encoder,
        &generator.fill_u32_pass,
        "match_pattern_first_use_node",
        match_pattern_first_use_node_buf,
        &[u32::MAX],
        hir_words,
    )?;
    stamp_timer(timer, encoder, "x86.metadata.match_pattern_owner.done");
    if has_match {
        dispatch_x86_stages_indirect(
            encoder,
            &[
                (
                    "match_pattern_records",
                    &generator.match_pattern_records_pass,
                    match_pattern_records_bind_group,
                ),
                (
                    "match_pattern_finalize",
                    &generator.match_pattern_finalize_pass,
                    match_pattern_finalize_bind_group,
                ),
            ],
            active_hir_dispatch_args_buf,
        );
    }
    dispatch_x86_stages_indirect(
        encoder,
        &[
            (
                "struct_records",
                &generator.struct_records_pass,
                struct_records_bind_group,
            ),
            (
                "array_records",
                &generator.array_records_pass,
                array_records_bind_group,
            ),
        ],
        active_hir_dispatch_args_buf,
    );
    stamp_timer(timer, encoder, "x86.metadata.aggregate_records.done");
    dispatch_x86_stage_indirect(
        encoder,
        "enclosing_stmt_init",
        &generator.enclosing_stmt_init_pass,
        enclosing_stmt_init_bind_group,
        active_hir_dispatch_args_buf,
    );
    dispatch_compute_pass_indirect_bind_group_steps(
        encoder,
        "enclosing_stmt_step",
        "codegen.x86.enclosing_stmt_step",
        &generator.enclosing_stmt_step_pass,
        enclosing_stmt_step_bind_groups,
        active_hir_dispatch_args_buf,
    );
    stamp_timer(timer, encoder, "x86.metadata.enclosing_stmt.done");
    dispatch_x86_stages_indirect(
        encoder,
        &[
            (
                "decl_widths",
                &generator.decl_widths_pass,
                decl_widths_bind_group,
            ),
            (
                "decl_width_scan_local",
                &generator.node_inst_scan_local_pass,
                node_inst_scan_local_bind_group,
            ),
        ],
        active_hir_dispatch_args_buf,
    );
    dispatch_compute_pass_indirect_ping_pong_scan_steps(
        encoder,
        "decl_width_scan_blocks",
        "codegen.x86.node_inst_scan_blocks",
        &generator.node_inst_scan_blocks_pass,
        node_inst_scan_block_bind_groups,
        node_inst_scan_params_buf,
        hir_scan_block,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "decl_layout",
        &generator.decl_layout_pass,
        decl_layout_bind_group,
        active_hir_dispatch_args_buf,
    );
    stamp_timer(timer, encoder, "x86.metadata.decl_layout.done");
    dispatch_compute_pass_indirect(
        encoder,
        "node_inst_scan_input.active_clear",
        "codegen.x86.node_inst_scan_input.active_clear",
        &generator.active_clear_u32_pass,
        node_inst_scan_input_clear_bind_group,
        hir_plus_one,
    );
    dispatch_compute_pass_indirect(
        encoder,
        "call_callee_root_call.active_clear",
        "codegen.x86.call_callee_root_call.active_clear",
        &generator.active_clear_u32_pass,
        call_callee_root_call_clear_bind_group,
        hir_count,
    );
    dispatch_x86_stages_indirect(
        encoder,
        &[
            (
                "call_records",
                &generator.call_records_pass,
                call_records_bind_group,
            ),
            (
                "const_values",
                &generator.const_values_pass,
                const_values_bind_group,
            ),
            (
                "param_regs",
                &generator.param_regs_pass,
                param_regs_bind_group,
            ),
            (
                "local_literals",
                &generator.local_literals_pass,
                local_literals_bind_group,
            ),
        ],
        active_hir_dispatch_args_buf,
    );
    encoder.copy_buffer_to_buffer(func_meta_buf, 0, func_meta_uniform_buf, 0, 32);
    encoder.copy_buffer_to_buffer(
        const_value_status_buf,
        0,
        const_value_status_uniform_buf,
        0,
        16,
    );
    encoder.copy_buffer_to_buffer(param_reg_status_buf, 0, param_reg_status_uniform_buf, 0, 16);
    encoder.copy_buffer_to_buffer(
        local_literal_status_buf,
        0,
        local_literal_status_uniform_buf,
        0,
        16,
    );
    init_repeated_u32_words(
        device,
        queue,
        encoder,
        &generator.fill_u32_pass,
        "intrinsic_call_record",
        intrinsic_call_record_buf,
        &[u32::MAX],
        hir_words,
    )?;
    dispatch_x86_stages_indirect(
        encoder,
        &[
            (
                "call_arg_values",
                &generator.call_arg_values_pass,
                call_arg_values_bind_group,
            ),
            (
                "intrinsic_calls",
                &generator.intrinsic_calls_pass,
                intrinsic_calls_bind_group,
            ),
            ("call_abi", &generator.call_abi_pass, call_abi_bind_group),
            (
                "call_callee_owner_init",
                &generator.call_callee_owner_init_pass,
                call_callee_owner_init_bind_group,
            ),
        ],
        active_hir_dispatch_args_buf,
    );
    dispatch_compute_pass_indirect_bind_group_steps(
        encoder,
        "call_callee_owner_step",
        "codegen.x86.call_callee_owner_step",
        &generator.call_callee_owner_step_pass,
        call_callee_owner_step_bind_groups,
        active_hir_dispatch_args_buf,
    );
    encoder.copy_buffer_to_buffer(call_abi_status_buf, 0, call_abi_status_uniform_buf, 0, 16);
    stamp_timer(timer, encoder, "x86.calls.done");

    Ok(())
}
