use super::{
    super::{
        GpuX86CodeGenerator,
        support::{
            UniformBindingArray,
            dispatch_compute_pass_indirect,
            dispatch_compute_pass_indirect_bind_group_steps,
            dispatch_compute_pass_indirect_offsets_with_dynamic_uniform_offsets,
            dispatch_compute_pass_indirect_ping_pong_scan_steps,
            dispatch_indirect_dynamic_sequence,
            dispatch_x86_stage,
            dispatch_x86_stage_indirect,
            dispatch_x86_stages,
            dispatch_x86_stages_indirect,
            workgroup_grid_1d,
        },
    },
    indirect::IndirectUniformOffsets,
    timing::stamp_timer,
};

pub(super) struct InstructionDispatchInputs<'a, 'timer> {
    pub(super) encoder: &'a mut wgpu::CommandEncoder,
    pub(super) timer: &'a mut Option<&'timer mut crate::gpu::timer::GpuTimer>,
    pub(super) has_aggregate: bool,
    pub(super) active_hir_dispatch_args: &'a wgpu::Buffer,
    pub(super) hir_plus_one: &'a wgpu::Buffer,
    pub(super) hir_scan_block: &'a wgpu::Buffer,
    pub(super) node_order_scan: &'a wgpu::Buffer,
    pub(super) node_order_scan_block: &'a wgpu::Buffer,
    pub(super) virtual_inst: &'a wgpu::Buffer,
    pub(super) node_inst_scan_params: &'a UniformBindingArray,
    pub(super) for_iterable_nodes: &'a wgpu::BindGroup,
    pub(super) control_padding: &'a wgpu::BindGroup,
    pub(super) postfix_operand_owner: &'a wgpu::BindGroup,
    pub(super) node_inst_counts: &'a wgpu::BindGroup,
    pub(super) node_inst_same_end_rank_init: &'a wgpu::BindGroup,
    pub(super) node_inst_same_end_rank_step: &'a [wgpu::BindGroup],
    pub(super) node_inst_end_counts: &'a wgpu::BindGroup,
    pub(super) node_inst_scan_local: &'a wgpu::BindGroup,
    pub(super) node_inst_scan_block: &'a [wgpu::BindGroup],
    pub(super) node_inst_order: &'a wgpu::BindGroup,
    pub(super) node_order_dispatch_args: &'a wgpu::BindGroup,
    pub(super) node_inst_prefix_scan: &'a wgpu::BindGroup,
    pub(super) node_inst_subtree_bounds: &'a wgpu::BindGroup,
    pub(super) expr_semantic_type_init: &'a wgpu::BindGroup,
    pub(super) expr_semantic_type_step: &'a [wgpu::BindGroup],
    pub(super) node_inst_locations: &'a wgpu::BindGroup,
    pub(super) node_inst_gen_worklist_scatter: &'a wgpu::BindGroup,
    pub(super) node_inst_gen_worklist_dispatch_args: &'a wgpu::BindGroup,
    pub(super) enclosing_loop_init: &'a wgpu::BindGroup,
    pub(super) enclosing_loop_step: &'a [wgpu::BindGroup],
    pub(super) short_circuit_rhs_init: &'a wgpu::BindGroup,
    pub(super) short_circuit_rhs_step: &'a [wgpu::BindGroup],
    pub(super) index_source_owner_init: &'a wgpu::BindGroup,
    pub(super) index_source_owner_step: &'a [wgpu::BindGroup],
    pub(super) node_inst_gen_inputs: &'a wgpu::BindGroup,
    pub(super) virtual_inst_clear_dispatch_args: &'a wgpu::BindGroup,
    pub(super) virtual_inst_clear: &'a wgpu::BindGroup,
    pub(super) node_inst_gen: &'a wgpu::BindGroup,
    pub(super) node_inst_gen_aggregate_copy: &'a wgpu::BindGroup,
    pub(super) aggregate_literal_return_copy_flags: &'a wgpu::BindGroup,
    pub(super) aggregate_literal_return_copy: &'a wgpu::BindGroup,
}

pub(super) fn record_instruction_dispatches(
    generator: &GpuX86CodeGenerator,
    inputs: InstructionDispatchInputs<'_, '_>,
) {
    let InstructionDispatchInputs {
        encoder,
        timer,
        has_aggregate,
        active_hir_dispatch_args,
        hir_plus_one,
        hir_scan_block,
        node_order_scan,
        node_order_scan_block,
        virtual_inst,
        node_inst_scan_params,
        for_iterable_nodes,
        control_padding,
        postfix_operand_owner,
        node_inst_counts,
        node_inst_same_end_rank_init,
        node_inst_same_end_rank_step,
        node_inst_end_counts,
        node_inst_scan_local,
        node_inst_scan_block,
        node_inst_order,
        node_order_dispatch_args,
        node_inst_prefix_scan,
        node_inst_subtree_bounds,
        expr_semantic_type_init,
        expr_semantic_type_step,
        node_inst_locations,
        node_inst_gen_worklist_scatter,
        node_inst_gen_worklist_dispatch_args,
        enclosing_loop_init,
        enclosing_loop_step,
        short_circuit_rhs_init,
        short_circuit_rhs_step,
        index_source_owner_init,
        index_source_owner_step,
        node_inst_gen_inputs,
        virtual_inst_clear_dispatch_args,
        virtual_inst_clear,
        node_inst_gen,
        node_inst_gen_aggregate_copy,
        aggregate_literal_return_copy_flags,
        aggregate_literal_return_copy,
    } = inputs;

    dispatch_x86_stages_indirect(
        encoder,
        &[
            (
                "for_iterable_nodes",
                &generator.for_iterable_nodes_pass,
                for_iterable_nodes,
            ),
            (
                "node_control_padding",
                &generator.node_control_padding_pass,
                control_padding,
            ),
            (
                "postfix_operand_owner",
                &generator.postfix_operand_owner_pass,
                postfix_operand_owner,
            ),
            (
                "node_inst_counts",
                &generator.node_inst_counts_pass,
                node_inst_counts,
            ),
            (
                "node_inst_same_end_rank_init",
                &generator.node_inst_same_end_rank_init_pass,
                node_inst_same_end_rank_init,
            ),
        ],
        active_hir_dispatch_args,
    );
    dispatch_compute_pass_indirect_bind_group_steps(
        encoder,
        "node_inst_same_end_rank_step",
        "codegen.x86.node_inst_same_end_rank_step",
        &generator.node_inst_same_end_rank_step_pass,
        node_inst_same_end_rank_step,
        active_hir_dispatch_args,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "node_inst_end_counts",
        &generator.node_inst_end_counts_pass,
        node_inst_end_counts,
        active_hir_dispatch_args,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "node_inst_scan_local",
        &generator.node_inst_scan_local_pass,
        node_inst_scan_local,
        hir_plus_one,
    );
    dispatch_compute_pass_indirect_ping_pong_scan_steps(
        encoder,
        "node_inst_scan_blocks",
        "codegen.x86.node_inst_scan_blocks",
        &generator.node_inst_scan_blocks_pass,
        node_inst_scan_block,
        node_inst_scan_params,
        hir_scan_block,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "node_inst_order",
        &generator.node_inst_order_pass,
        node_inst_order,
        active_hir_dispatch_args,
    );
    dispatch_x86_stage(
        encoder,
        "node_order_dispatch_args",
        &generator.node_order_dispatch_args_pass,
        node_order_dispatch_args,
        (1, 1),
    );
    dispatch_x86_stage_indirect(
        encoder,
        "node_inst_scan_local",
        &generator.node_inst_scan_local_pass,
        node_inst_scan_local,
        node_order_scan,
    );
    dispatch_compute_pass_indirect_ping_pong_scan_steps(
        encoder,
        "node_inst_scan_blocks.order",
        "codegen.x86.node_inst_scan_blocks",
        &generator.node_inst_scan_blocks_pass,
        node_inst_scan_block,
        node_inst_scan_params,
        node_order_scan_block,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "node_inst_prefix_scan",
        &generator.node_inst_prefix_scan_pass,
        node_inst_prefix_scan,
        active_hir_dispatch_args,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "node_inst_subtree_bounds",
        &generator.node_inst_subtree_bounds_pass,
        node_inst_subtree_bounds,
        hir_plus_one,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "expr_semantic_type_init",
        &generator.expr_semantic_type_init_pass,
        expr_semantic_type_init,
        active_hir_dispatch_args,
    );
    dispatch_compute_pass_indirect_bind_group_steps(
        encoder,
        "expr_semantic_type_step",
        "codegen.x86.expr_semantic_type_step",
        &generator.expr_semantic_type_step_pass,
        expr_semantic_type_step,
        active_hir_dispatch_args,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "node_inst_locations",
        &generator.node_inst_locations_pass,
        node_inst_locations,
        active_hir_dispatch_args,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "node_inst_gen_flag_scan_local",
        &generator.node_inst_scan_local_pass,
        node_inst_scan_local,
        hir_plus_one,
    );
    dispatch_compute_pass_indirect_ping_pong_scan_steps(
        encoder,
        "node_inst_gen_flag_scan_blocks",
        "codegen.x86.node_inst_scan_blocks",
        &generator.node_inst_scan_blocks_pass,
        node_inst_scan_block,
        node_inst_scan_params,
        hir_scan_block,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "node_inst_gen_worklist_scatter",
        &generator.node_inst_gen_worklist_scatter_pass,
        node_inst_gen_worklist_scatter,
        hir_plus_one,
    );
    dispatch_x86_stage(
        encoder,
        "node_inst_gen_worklist_dispatch_args",
        &generator.node_inst_gen_worklist_dispatch_args_pass,
        node_inst_gen_worklist_dispatch_args,
        (1, 1),
    );
    stamp_timer(timer, encoder, "x86.inst_locations.done");
    dispatch_x86_stage_indirect(
        encoder,
        "enclosing_loop_init",
        &generator.enclosing_loop_init_pass,
        enclosing_loop_init,
        active_hir_dispatch_args,
    );
    dispatch_compute_pass_indirect_bind_group_steps(
        encoder,
        "enclosing_loop_step",
        "codegen.x86.enclosing_loop_step",
        &generator.enclosing_loop_step_pass,
        enclosing_loop_step,
        active_hir_dispatch_args,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "short_circuit_rhs_init",
        &generator.short_circuit_rhs_init_pass,
        short_circuit_rhs_init,
        active_hir_dispatch_args,
    );
    dispatch_compute_pass_indirect_bind_group_steps(
        encoder,
        "short_circuit_rhs_step",
        "codegen.x86.short_circuit_rhs_step",
        &generator.short_circuit_rhs_step_pass,
        short_circuit_rhs_step,
        active_hir_dispatch_args,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "index_source_owner_init",
        &generator.index_source_owner_init_pass,
        index_source_owner_init,
        active_hir_dispatch_args,
    );
    dispatch_compute_pass_indirect_bind_group_steps(
        encoder,
        "index_source_owner_step",
        "codegen.x86.index_source_owner_step",
        &generator.index_source_owner_step_pass,
        index_source_owner_step,
        active_hir_dispatch_args,
    );
    dispatch_x86_stages(
        encoder,
        &[
            (
                "node_inst_gen_inputs",
                &generator.node_inst_gen_inputs_pass,
                node_inst_gen_inputs,
            ),
            (
                "virtual_inst_clear_dispatch_args",
                &generator.virtual_inst_clear_dispatch_args_pass,
                virtual_inst_clear_dispatch_args,
            ),
        ],
        (1, 1),
    );
    dispatch_x86_stage_indirect(
        encoder,
        "virtual_inst_clear",
        &generator.virtual_inst_clear_pass,
        virtual_inst_clear,
        virtual_inst,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "node_inst_gen",
        &generator.node_inst_gen_pass,
        node_inst_gen,
        node_order_scan,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "node_inst_gen_aggregate_copy",
        &generator.node_inst_gen_aggregate_copy_pass,
        node_inst_gen_aggregate_copy,
        node_order_scan_block,
    );
    if has_aggregate {
        dispatch_x86_stage_indirect(
            encoder,
            "aggregate_literal_return_copy_flags",
            &generator.aggregate_literal_return_copy_flags_pass,
            aggregate_literal_return_copy_flags,
            active_hir_dispatch_args,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "aggregate_literal_return_copy_scan_local",
            &generator.node_inst_scan_local_pass,
            node_inst_scan_local,
            hir_plus_one,
        );
        dispatch_compute_pass_indirect_ping_pong_scan_steps(
            encoder,
            "aggregate_literal_return_copy_scan_blocks",
            "codegen.x86.node_inst_scan_blocks",
            &generator.node_inst_scan_blocks_pass,
            node_inst_scan_block,
            node_inst_scan_params,
            hir_scan_block,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "aggregate_literal_return_copy_worklist_scatter",
            &generator.node_inst_gen_worklist_scatter_pass,
            node_inst_gen_worklist_scatter,
            hir_plus_one,
        );
        dispatch_x86_stage(
            encoder,
            "aggregate_literal_return_copy_dispatch_args",
            &generator.node_inst_gen_worklist_dispatch_args_pass,
            node_inst_gen_worklist_dispatch_args,
            (1, 1),
        );
        dispatch_x86_stage_indirect(
            encoder,
            "aggregate_literal_return_copy",
            &generator.aggregate_literal_return_copy_pass,
            aggregate_literal_return_copy,
            node_order_scan,
        );
    }
    stamp_timer(timer, encoder, "x86.inst_gen.done");
}

pub(super) struct VirtualEmitDispatchInputs<'a, 'timer> {
    pub(super) encoder: &'a mut wgpu::CommandEncoder,
    pub(super) timer: &'a mut Option<&'timer mut crate::gpu::timer::GpuTimer>,
    pub(super) virtual_dispatch_arg_groups: (u32, u32),
    pub(super) virtual_next_call_params: &'a UniformBindingArray,
    pub(super) virtual_regalloc_params: &'a UniformBindingArray,
    pub(super) text_scan_params: &'a UniformBindingArray,
    pub(super) function_dispatch: &'a wgpu::Buffer,
    pub(super) virtual_inst: &'a wgpu::Buffer,
    pub(super) virtual_next_call_dispatch: &'a wgpu::Buffer,
    pub(super) virtual_regalloc: &'a wgpu::Buffer,
    pub(super) selected_inst: &'a wgpu::Buffer,
    pub(super) selected_scan_block: &'a wgpu::Buffer,
    pub(super) elf_header_word: &'a wgpu::Buffer,
    pub(super) virtual_dispatch_args: &'a wgpu::BindGroup,
    pub(super) virtual_func_rows_init: &'a wgpu::BindGroup,
    pub(super) virtual_func_first_row: &'a wgpu::BindGroup,
    pub(super) virtual_func_span_max: &'a wgpu::BindGroup,
    pub(super) virtual_regalloc_dispatch_args: &'a wgpu::BindGroup,
    pub(super) virtual_next_call_bind_groups: &'a [wgpu::BindGroup],
    pub(super) virtual_param_masks: &'a wgpu::BindGroup,
    pub(super) virtual_liveness_init: &'a wgpu::BindGroup,
    pub(super) virtual_liveness: &'a wgpu::BindGroup,
    pub(super) virtual_spans_fixed_barrier: &'a wgpu::BindGroup,
    pub(super) virtual_value_def_flags: &'a wgpu::BindGroup,
    pub(super) virtual_value_def_scan_local: &'a wgpu::BindGroup,
    pub(super) virtual_value_def_scan_block: &'a [wgpu::BindGroup],
    pub(super) virtual_value_def_compact: &'a wgpu::BindGroup,
    pub(super) virtual_regalloc_bind_group: &'a wgpu::BindGroup,
    pub(super) select: &'a wgpu::BindGroup,
    pub(super) inst_size: &'a wgpu::BindGroup,
    pub(super) text_scan_local: &'a wgpu::BindGroup,
    pub(super) text_scan_block: &'a [wgpu::BindGroup],
    pub(super) text_offsets: &'a wgpu::BindGroup,
    pub(super) reloc_scan_local: &'a wgpu::BindGroup,
    pub(super) reloc_scan_block: &'a [wgpu::BindGroup],
    pub(super) reloc_records: &'a wgpu::BindGroup,
    pub(super) output_dispatch_args: &'a wgpu::BindGroup,
    pub(super) encode: &'a wgpu::BindGroup,
    pub(super) reloc_patch: &'a wgpu::BindGroup,
    pub(super) elf_layout: &'a wgpu::BindGroup,
    pub(super) elf: &'a wgpu::BindGroup,
}

pub(super) fn record_virtual_emit_dispatches(
    generator: &GpuX86CodeGenerator,
    inputs: VirtualEmitDispatchInputs<'_, '_>,
) {
    let VirtualEmitDispatchInputs {
        encoder,
        timer,
        virtual_dispatch_arg_groups,
        virtual_next_call_params,
        virtual_regalloc_params,
        text_scan_params,
        function_dispatch,
        virtual_inst,
        virtual_next_call_dispatch,
        virtual_regalloc,
        selected_inst,
        selected_scan_block,
        elf_header_word,
        virtual_dispatch_args,
        virtual_func_rows_init,
        virtual_func_first_row,
        virtual_func_span_max,
        virtual_regalloc_dispatch_args,
        virtual_next_call_bind_groups,
        virtual_param_masks,
        virtual_liveness_init,
        virtual_liveness,
        virtual_spans_fixed_barrier,
        virtual_value_def_flags,
        virtual_value_def_scan_local,
        virtual_value_def_scan_block,
        virtual_value_def_compact,
        virtual_regalloc_bind_group,
        select,
        inst_size,
        text_scan_local,
        text_scan_block,
        text_offsets,
        reloc_scan_local,
        reloc_scan_block,
        reloc_records,
        output_dispatch_args,
        encode,
        reloc_patch,
        elf_layout,
        elf,
    } = inputs;

    dispatch_x86_stage(
        encoder,
        "virtual_dispatch_args",
        &generator.virtual_dispatch_args_pass,
        virtual_dispatch_args,
        virtual_dispatch_arg_groups,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "virtual_func_rows_init",
        &generator.virtual_func_rows_init_pass,
        virtual_func_rows_init,
        function_dispatch,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "virtual_func_first_row",
        &generator.virtual_func_first_row_pass,
        virtual_func_first_row,
        virtual_inst,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "virtual_func_span_max",
        &generator.virtual_func_span_max_pass,
        virtual_func_span_max,
        function_dispatch,
    );
    stamp_timer(timer, encoder, "x86.virtual_rows.done");

    let virtual_next_call_offsets = IndirectUniformOffsets::for_params(virtual_next_call_params);
    let virtual_next_call_bind_group_sequence = (0..virtual_next_call_params.len())
        .map(|step_i| &virtual_next_call_bind_groups[step_i & 1])
        .collect::<Vec<_>>();
    dispatch_indirect_dynamic_sequence(
        encoder,
        "virtual_next_calls",
        "codegen.x86.virtual_next_calls",
        &generator.virtual_next_calls_pass,
        &virtual_next_call_bind_group_sequence,
        virtual_next_call_dispatch,
        &virtual_next_call_offsets.indirect,
        &virtual_next_call_offsets.dynamic,
    );
    stamp_timer(timer, encoder, "x86.virtual_next_calls.done");
    dispatch_x86_stage_indirect(
        encoder,
        "virtual_param_masks",
        &generator.virtual_param_masks_pass,
        virtual_param_masks,
        virtual_inst,
    );
    stamp_timer(timer, encoder, "x86.virtual_param_masks.done");
    dispatch_x86_stages_indirect(
        encoder,
        &[
            (
                "virtual_liveness_init",
                &generator.virtual_liveness_init_pass,
                virtual_liveness_init,
            ),
            (
                "virtual_liveness",
                &generator.virtual_liveness_pass,
                virtual_liveness,
            ),
        ],
        virtual_inst,
    );
    stamp_timer(timer, encoder, "x86.virtual_liveness.done");
    dispatch_x86_stage_indirect(
        encoder,
        "virtual_spans_fixed_barrier",
        &generator.virtual_spans_fixed_barrier_pass,
        virtual_spans_fixed_barrier,
        virtual_inst,
    );
    stamp_timer(timer, encoder, "x86.virtual_spans_fixed_barrier.done");
    dispatch_x86_stage_indirect(
        encoder,
        "virtual_value_def_flags",
        &generator.virtual_value_def_flags_pass,
        virtual_value_def_flags,
        selected_inst,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "virtual_value_def_scan_local",
        &generator.node_inst_scan_local_pass,
        virtual_value_def_scan_local,
        selected_inst,
    );
    dispatch_compute_pass_indirect_ping_pong_scan_steps(
        encoder,
        "virtual_value_def_scan_blocks",
        "codegen.x86.virtual_value_def_scan_blocks",
        &generator.node_inst_scan_blocks_pass,
        virtual_value_def_scan_block,
        text_scan_params,
        selected_scan_block,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "virtual_value_def_compact",
        &generator.virtual_value_def_compact_pass,
        virtual_value_def_compact,
        virtual_inst,
    );
    stamp_timer(timer, encoder, "x86.virtual_value_defs.done");
    dispatch_x86_stage(
        encoder,
        "virtual_regalloc_dispatch_args",
        &generator.virtual_regalloc_dispatch_args_pass,
        virtual_regalloc_dispatch_args,
        virtual_dispatch_arg_groups,
    );

    let virtual_regalloc_offsets = IndirectUniformOffsets::for_params(virtual_regalloc_params);
    dispatch_compute_pass_indirect_offsets_with_dynamic_uniform_offsets(
        encoder,
        "virtual_regalloc",
        "codegen.x86.virtual_regalloc",
        &generator.virtual_regalloc_pass,
        virtual_regalloc_bind_group,
        virtual_regalloc,
        &virtual_regalloc_offsets.indirect,
        &virtual_regalloc_offsets.dynamic,
    );
    stamp_timer(timer, encoder, "x86.regalloc.done");

    dispatch_compute_pass_indirect(
        encoder,
        "select",
        "codegen.x86.select",
        &generator.select_pass,
        select,
        virtual_inst,
    );
    dispatch_x86_stages_indirect(
        encoder,
        &[
            ("inst_size", &generator.inst_size_pass, inst_size),
            (
                "text_scan_local",
                &generator.text_scan_local_pass,
                text_scan_local,
            ),
        ],
        selected_inst,
    );
    dispatch_compute_pass_indirect_ping_pong_scan_steps(
        encoder,
        "text_scan_blocks",
        "codegen.x86.text_scan_blocks",
        &generator.node_inst_scan_blocks_pass,
        text_scan_block,
        text_scan_params,
        selected_scan_block,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "text_offsets",
        &generator.text_offsets_pass,
        text_offsets,
        selected_inst,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "reloc_scan_local",
        &generator.reloc_scan_local_pass,
        reloc_scan_local,
        selected_inst,
    );
    dispatch_compute_pass_indirect_ping_pong_scan_steps(
        encoder,
        "reloc_scan_blocks",
        "codegen.x86.reloc_scan_blocks",
        &generator.node_inst_scan_blocks_pass,
        reloc_scan_block,
        text_scan_params,
        selected_scan_block,
    );
    dispatch_x86_stage_indirect(
        encoder,
        "reloc_records",
        &generator.reloc_records_pass,
        reloc_records,
        selected_inst,
    );
    stamp_timer(timer, encoder, "x86.reloc_records.done");
    dispatch_x86_stage(
        encoder,
        "output_dispatch_args",
        &generator.output_dispatch_args_pass,
        output_dispatch_args,
        (1, 1),
    );
    dispatch_compute_pass_indirect(
        encoder,
        "encode",
        "codegen.x86.encode",
        &generator.encode_pass,
        encode,
        selected_inst,
    );
    dispatch_compute_pass_indirect(
        encoder,
        "reloc_patch",
        "codegen.x86.reloc_patch",
        &generator.reloc_patch_pass,
        reloc_patch,
        selected_inst,
    );
    stamp_timer(timer, encoder, "x86.reloc_patch.done");

    let (layout_groups_x, layout_groups_y) = workgroup_grid_1d(1);
    dispatch_x86_stages(
        encoder,
        &[("elf_layout", &generator.elf_layout_pass, elf_layout)],
        (layout_groups_x, layout_groups_y),
    );

    dispatch_compute_pass_indirect(
        encoder,
        "elf_write",
        "codegen.x86.elf_write",
        &generator.elf_write_pass,
        elf,
        elf_header_word,
    );
    stamp_timer(timer, encoder, "x86.emit.done");
}
