use anyhow::Result;

use super::{
    GpuX86CallMetadataBuffers,
    GpuX86CodeGenerator,
    GpuX86ExprMetadataBuffers,
    GpuX86FunctionMetadataBuffers,
    MAX_X86_INSTS,
    MAX_X86_NODE_LOCAL_INSTS,
    MAX_X86_RELOCS,
    MAX_X86_USE_EDGES,
    MAX_X86_VIRTUAL_USE_EDGES,
    MAX_X86_VREGS,
    RecordedX86Codegen,
    X86Params,
    X86ScanParams,
    support::{
        dispatch_compute_pass,
        dispatch_x86_stage,
        dispatch_x86_stages,
        readback_u32s,
        reflected_bind_group,
        scan_steps_for_blocks,
        storage_u32_copy,
        uniform_u32_struct,
        uniform_u32_words,
        workgroup_grid_1d,
        write_repeated_u32_words,
        write_u32_words,
        x86_params_bytes,
        x86_scan_params_bytes,
    },
};

impl GpuX86CodeGenerator {
    #[allow(clippy::too_many_arguments)]
    pub fn record_x86_elf_from_gpu_hir(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        source_len: u32,
        token_capacity: u32,
        n_hir_nodes: u32,
        hir_status_buf: &wgpu::Buffer,
        hir_kind_buf: &wgpu::Buffer,
        parent_buf: &wgpu::Buffer,
        first_child_buf: &wgpu::Buffer,
        next_sibling_buf: &wgpu::Buffer,
        subtree_end_buf: &wgpu::Buffer,
        function_metadata: GpuX86FunctionMetadataBuffers<'_>,
        expr_metadata: GpuX86ExprMetadataBuffers<'_>,
        call_metadata: GpuX86CallMetadataBuffers<'_>,
        visible_decl_buf: &wgpu::Buffer,
        fn_entrypoint_tag_buf: &wgpu::Buffer,
    ) -> Result<RecordedX86Codegen> {
        let output_capacity = 4096usize;
        let output_words = output_capacity.div_ceil(4);
        let params = X86Params {
            n_tokens: token_capacity,
            source_len,
            out_capacity: output_capacity as u32,
            n_hir_nodes,
        };

        let params_bytes = x86_params_bytes(&params);
        let params_buf = uniform_u32_struct(device, "codegen.x86.params", &params_bytes);
        let hir_words = n_hir_nodes.max(1) as usize;
        let token_words = (token_capacity as usize).max(1);
        let node_inst_scan_words = hir_words;
        let node_inst_scan_blocks = node_inst_scan_words.div_ceil(256).max(1);
        let func_inst_scan_words = hir_words + 1;
        let func_inst_scan_blocks = func_inst_scan_words.div_ceil(256).max(1);
        let func_lookup_words = ((token_capacity as usize) * 2).max(1);
        let func_meta_buf = storage_u32_copy(device, "codegen.x86.func_meta", 8);
        let func_meta_uniform_buf = uniform_u32_words(
            device,
            "codegen.x86.func_meta.uniform",
            &[0, 0, u32::MAX, 0, u32::MAX, 0, 0, 0],
        );
        let node_tree_record_buf =
            storage_u32_copy(device, "codegen.x86.node_tree_record", hir_words * 4);
        let node_tree_status_buf = storage_u32_copy(device, "codegen.x86.node_tree_status", 4);
        let func_record_buf = storage_u32_copy(device, "codegen.x86.func_record", hir_words * 4);
        let node_func_buf = storage_u32_copy(device, "codegen.x86.node_func", hir_words);
        let func_lookup_key_buf =
            storage_u32_copy(device, "codegen.x86.func_lookup_key", func_lookup_words);
        let func_lookup_node_buf =
            storage_u32_copy(device, "codegen.x86.func_lookup_node", func_lookup_words);
        let call_record_buf = storage_u32_copy(device, "codegen.x86.call_record", hir_words * 4);
        let call_type_record_buf =
            storage_u32_copy(device, "codegen.x86.call_type_record", hir_words * 4);
        let call_record_status_buf = storage_u32_copy(device, "codegen.x86.call_record_status", 4);
        let const_value_record_buf = storage_u32_copy(
            device,
            "codegen.x86.const_value_record",
            func_lookup_words * 4,
        );
        let const_value_status_buf = storage_u32_copy(device, "codegen.x86.const_value_status", 4);
        let const_value_status_uniform_buf = uniform_u32_words(
            device,
            "codegen.x86.const_value_status.uniform",
            &[1, 0, u32::MAX, 0],
        );
        let param_reg_record_buf =
            storage_u32_copy(device, "codegen.x86.param_reg_record", token_words * 4);
        let param_reg_status_buf = storage_u32_copy(device, "codegen.x86.param_reg_status", 4);
        let param_reg_status_uniform_buf = uniform_u32_words(
            device,
            "codegen.x86.param_reg_status.uniform",
            &[1, 0, u32::MAX, 0],
        );
        let local_literal_record_buf =
            storage_u32_copy(device, "codegen.x86.local_literal_record", token_words * 4);
        let local_literal_status_buf =
            storage_u32_copy(device, "codegen.x86.local_literal_status", 4);
        let local_literal_status_uniform_buf = uniform_u32_words(
            device,
            "codegen.x86.local_literal_status.uniform",
            &[1, 0, u32::MAX, 0],
        );
        let func_return_stmt_record_buf =
            storage_u32_copy(device, "codegen.x86.func_return_stmt_record", hir_words * 4);
        let func_return_stmt_count_buf =
            storage_u32_copy(device, "codegen.x86.func_return_stmt_count", hir_words);
        let func_return_stmt_status_buf =
            storage_u32_copy(device, "codegen.x86.func_return_stmt_status", 4);
        let func_return_stmt_status_uniform_buf = uniform_u32_words(
            device,
            "codegen.x86.func_return_stmt_status.uniform",
            &[1, 0, u32::MAX, 0],
        );
        let block_return_stmt_record_buf = storage_u32_copy(
            device,
            "codegen.x86.block_return_stmt_record",
            hir_words * 4,
        );
        let block_return_stmt_count_buf =
            storage_u32_copy(device, "codegen.x86.block_return_stmt_count", hir_words);
        let block_return_stmt_status_buf =
            storage_u32_copy(device, "codegen.x86.block_return_stmt_status", 4);
        let terminal_if_record_buf =
            storage_u32_copy(device, "codegen.x86.terminal_if_record", hir_words * 4);
        let terminal_if_count_buf =
            storage_u32_copy(device, "codegen.x86.terminal_if_count", hir_words);
        let terminal_if_status_buf = storage_u32_copy(device, "codegen.x86.terminal_if_status", 4);
        let terminal_if_status_uniform_buf = uniform_u32_words(
            device,
            "codegen.x86.terminal_if_status.uniform",
            &[1, 0, u32::MAX, 0],
        );
        let return_call_record_buf =
            storage_u32_copy(device, "codegen.x86.return_call_record", hir_words * 4);
        let return_call_count_buf =
            storage_u32_copy(device, "codegen.x86.return_call_count", hir_words);
        let return_call_status_buf = storage_u32_copy(device, "codegen.x86.return_call_status", 4);
        let return_call_status_uniform_buf = uniform_u32_words(
            device,
            "codegen.x86.return_call_status.uniform",
            &[1, 0, u32::MAX, 0],
        );
        let call_arg_value_record_buf =
            storage_u32_copy(device, "codegen.x86.call_arg_value_record", hir_words * 4);
        let call_arg_eval_record_buf =
            storage_u32_copy(device, "codegen.x86.call_arg_eval_record", hir_words * 4);
        let call_arg_value_status_buf =
            storage_u32_copy(device, "codegen.x86.call_arg_value_status", 4);
        let call_arg_lookup_record_buf = storage_u32_copy(
            device,
            "codegen.x86.call_arg_lookup_record",
            hir_words * 6 * 4,
        );
        let call_arg_lookup_status_buf =
            storage_u32_copy(device, "codegen.x86.call_arg_lookup_status", 4);
        let intrinsic_call_record_buf =
            storage_u32_copy(device, "codegen.x86.intrinsic_call_record", hir_words * 4);
        let intrinsic_call_status_buf =
            storage_u32_copy(device, "codegen.x86.intrinsic_call_status", 4);
        let call_abi_record_buf =
            storage_u32_copy(device, "codegen.x86.call_abi_record", hir_words * 8);
        let call_arg_abi_record_buf =
            storage_u32_copy(device, "codegen.x86.call_arg_abi_record", hir_words * 4);
        let call_abi_flags_buf = storage_u32_copy(device, "codegen.x86.call_abi_flags", hir_words);
        let call_abi_status_buf = storage_u32_copy(device, "codegen.x86.call_abi_status", 4);
        let call_abi_status_uniform_buf = uniform_u32_words(
            device,
            "codegen.x86.call_abi_status.uniform",
            &[1, 0, u32::MAX, 0],
        );
        let call_arg_width_record_buf =
            storage_u32_copy(device, "codegen.x86.call_arg_width_record", hir_words * 4);
        let call_arg_width_status_buf =
            storage_u32_copy(device, "codegen.x86.call_arg_width_status", 4);
        let call_arg_width_slot_record_buf = storage_u32_copy(
            device,
            "codegen.x86.call_arg_width_slot_record",
            hir_words * 6 * 4,
        );
        let call_arg_prefix_seed_status_buf =
            storage_u32_copy(device, "codegen.x86.call_arg_prefix_seed_status", 4);
        let call_arg_prefix_record_buf =
            storage_u32_copy(device, "codegen.x86.call_arg_prefix_record", hir_words * 4);
        let call_arg_total_width_record_buf = storage_u32_copy(
            device,
            "codegen.x86.call_arg_total_width_record",
            hir_words * 4,
        );
        let call_arg_prefix_status_buf =
            storage_u32_copy(device, "codegen.x86.call_arg_prefix_status", 4);
        let call_arg_range_record_buf =
            storage_u32_copy(device, "codegen.x86.call_arg_range_record", hir_words * 4);
        let call_vreg_summary_record_buf = storage_u32_copy(
            device,
            "codegen.x86.call_vreg_summary_record",
            hir_words * 4,
        );
        let call_vreg_count_record_buf =
            storage_u32_copy(device, "codegen.x86.call_vreg_count_record", hir_words * 4);
        let call_arg_vreg_status_buf =
            storage_u32_copy(device, "codegen.x86.call_arg_vreg_status", 4);
        let node_inst_count_record_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_count_record", hir_words * 4);
        let node_inst_order_record_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_order_record", hir_words * 4);
        let node_inst_order_node_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_order_node", hir_words);
        let node_inst_order_slot_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_order_slot", hir_words);
        let node_inst_scan_input_buf = storage_u32_copy(
            device,
            "codegen.x86.node_inst_scan_input",
            node_inst_scan_words,
        );
        let node_inst_count_status_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_count_status", 4);
        let node_inst_order_status_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_order_status", 4);
        let node_inst_scan_local_prefix_buf = storage_u32_copy(
            device,
            "codegen.x86.node_inst_scan_local_prefix",
            node_inst_scan_words,
        );
        let node_inst_scan_block_sum_buf = storage_u32_copy(
            device,
            "codegen.x86.node_inst_scan_block_sum",
            node_inst_scan_blocks,
        );
        let node_inst_scan_prefix_a_buf = storage_u32_copy(
            device,
            "codegen.x86.node_inst_scan_prefix_a",
            node_inst_scan_blocks,
        );
        let node_inst_scan_prefix_b_buf = storage_u32_copy(
            device,
            "codegen.x86.node_inst_scan_prefix_b",
            node_inst_scan_blocks,
        );
        let node_inst_range_record_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_range_record", hir_words * 4);
        let node_inst_range_status_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_range_status", 4);
        let node_inst_location_record_buf = storage_u32_copy(
            device,
            "codegen.x86.node_inst_location_record",
            hir_words * MAX_X86_NODE_LOCAL_INSTS,
        );
        let node_inst_location_status_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_location_status", 4);
        let node_value_record_buf =
            storage_u32_copy(device, "codegen.x86.node_value_record", hir_words * 4);
        let virtual_inst_record_buf =
            storage_u32_copy(device, "codegen.x86.virtual_inst_record", MAX_X86_INSTS * 4);
        let virtual_inst_args_buf =
            storage_u32_copy(device, "codegen.x86.virtual_inst_args", MAX_X86_INSTS * 4);
        let virtual_inst_status_buf =
            storage_u32_copy(device, "codegen.x86.virtual_inst_status", 4);
        let virtual_use_key_buf = storage_u32_copy(
            device,
            "codegen.x86.virtual_use_key",
            MAX_X86_VIRTUAL_USE_EDGES,
        );
        let virtual_use_value_buf = storage_u32_copy(
            device,
            "codegen.x86.virtual_use_value",
            MAX_X86_VIRTUAL_USE_EDGES,
        );
        let virtual_vreg_use_count_buf =
            storage_u32_copy(device, "codegen.x86.virtual_vreg_use_count", MAX_X86_INSTS);
        let virtual_use_status_buf = storage_u32_copy(device, "codegen.x86.virtual_use_status", 4);
        let virtual_live_start_buf =
            storage_u32_copy(device, "codegen.x86.virtual_live_start", MAX_X86_INSTS);
        let virtual_live_end_buf =
            storage_u32_copy(device, "codegen.x86.virtual_live_end", MAX_X86_INSTS);
        let virtual_liveness_status_buf =
            storage_u32_copy(device, "codegen.x86.virtual_liveness_status", 4);
        let virtual_phys_reg_buf =
            storage_u32_copy(device, "codegen.x86.virtual_phys_reg", MAX_X86_INSTS);
        let virtual_regalloc_status_buf =
            storage_u32_copy(device, "codegen.x86.virtual_regalloc_status", 4);
        let func_body_status_buf = storage_u32_copy(device, "codegen.x86.func_body_status", 4);
        let vreg_kind_buf = storage_u32_copy(device, "codegen.x86.vreg_kind", MAX_X86_VREGS);
        let vreg_value_buf = storage_u32_copy(device, "codegen.x86.vreg_value", MAX_X86_VREGS);
        let vreg_args_buf = storage_u32_copy(device, "codegen.x86.vreg_args", MAX_X86_VREGS * 4);
        let vreg_op_buf = storage_u32_copy(device, "codegen.x86.vreg_op", MAX_X86_VREGS);
        let expr_vreg_buf = storage_u32_copy(device, "codegen.x86.expr_vreg", hir_words);
        let return_vreg_buf = storage_u32_copy(device, "codegen.x86.return_vreg", 1);
        let lower_status_buf = storage_u32_copy(device, "codegen.x86.lower_status", 4);
        let use_key_buf = storage_u32_copy(device, "codegen.x86.use_key", MAX_X86_USE_EDGES);
        let use_value_buf = storage_u32_copy(device, "codegen.x86.use_value", MAX_X86_USE_EDGES);
        let vreg_use_count_buf =
            storage_u32_copy(device, "codegen.x86.vreg_use_count", MAX_X86_VREGS);
        let use_status_buf = storage_u32_copy(device, "codegen.x86.use_status", 4);
        let live_start_buf = storage_u32_copy(device, "codegen.x86.live_start", MAX_X86_VREGS);
        let live_end_buf = storage_u32_copy(device, "codegen.x86.live_end", MAX_X86_VREGS);
        let liveness_status_buf = storage_u32_copy(device, "codegen.x86.liveness_status", 4);
        let phys_reg_buf = storage_u32_copy(device, "codegen.x86.phys_reg", MAX_X86_VREGS);
        let regalloc_status_buf = storage_u32_copy(device, "codegen.x86.regalloc_status", 4);
        let regalloc_status_uniform_buf = uniform_u32_words(
            device,
            "codegen.x86.regalloc_status.uniform",
            &[0, 0, u32::MAX, 0],
        );
        let func_inst_count_record_buf =
            storage_u32_copy(device, "codegen.x86.func_inst_count_record", hir_words * 4);
        let func_inst_count_status_buf =
            storage_u32_copy(device, "codegen.x86.func_inst_count_status", 9);
        let func_inst_order_record_buf = storage_u32_copy(
            device,
            "codegen.x86.func_inst_order_record",
            func_inst_scan_words * 4,
        );
        let func_inst_order_slot_buf =
            storage_u32_copy(device, "codegen.x86.func_inst_order_slot", hir_words);
        let func_inst_scan_input_buf = storage_u32_copy(
            device,
            "codegen.x86.func_inst_scan_input",
            func_inst_scan_words,
        );
        let func_inst_order_status_buf =
            storage_u32_copy(device, "codegen.x86.func_inst_order_status", 9);
        let func_inst_scan_local_prefix_buf = storage_u32_copy(
            device,
            "codegen.x86.func_inst_scan_local_prefix",
            func_inst_scan_words,
        );
        let func_inst_scan_block_sum_buf = storage_u32_copy(
            device,
            "codegen.x86.func_inst_scan_block_sum",
            func_inst_scan_blocks,
        );
        let func_inst_scan_prefix_a_buf = storage_u32_copy(
            device,
            "codegen.x86.func_inst_scan_prefix_a",
            func_inst_scan_blocks,
        );
        let func_inst_scan_prefix_b_buf = storage_u32_copy(
            device,
            "codegen.x86.func_inst_scan_prefix_b",
            func_inst_scan_blocks,
        );
        let func_inst_range_record_buf =
            storage_u32_copy(device, "codegen.x86.func_inst_range_record", hir_words * 4);
        let func_inst_range_status_buf =
            storage_u32_copy(device, "codegen.x86.func_inst_range_status", 9);
        let func_layout_record_buf =
            storage_u32_copy(device, "codegen.x86.func_layout_record", hir_words * 4);
        let func_layout_status_buf = storage_u32_copy(device, "codegen.x86.func_layout_status", 9);
        let func_return_inst_status_buf =
            storage_u32_copy(device, "codegen.x86.func_return_inst_status", 4);
        let entry_inst_status_buf = storage_u32_copy(device, "codegen.x86.entry_inst_status", 6);
        let select_plan_buf = storage_u32_copy(device, "codegen.x86.select_plan", 5);
        let planned_inst_kind_buf =
            storage_u32_copy(device, "codegen.x86.planned_inst_kind", MAX_X86_INSTS);
        let planned_inst_arg0_buf =
            storage_u32_copy(device, "codegen.x86.planned_inst_arg0", MAX_X86_INSTS);
        let planned_reloc_kind_buf =
            storage_u32_copy(device, "codegen.x86.planned_reloc_kind", MAX_X86_RELOCS);
        let planned_reloc_site_inst_buf = storage_u32_copy(
            device,
            "codegen.x86.planned_reloc_site_inst",
            MAX_X86_RELOCS,
        );
        let planned_reloc_target_inst_buf = storage_u32_copy(
            device,
            "codegen.x86.planned_reloc_target_inst",
            MAX_X86_RELOCS,
        );
        let plan_status_buf = storage_u32_copy(device, "codegen.x86.plan_status", 4);
        let inst_kind_buf = storage_u32_copy(device, "codegen.x86.inst_kind", MAX_X86_INSTS);
        let inst_arg0_buf = storage_u32_copy(device, "codegen.x86.inst_arg0", MAX_X86_INSTS);
        let inst_arg1_buf = storage_u32_copy(device, "codegen.x86.inst_arg1", MAX_X86_INSTS);
        let inst_arg2_buf = storage_u32_copy(device, "codegen.x86.inst_arg2", MAX_X86_INSTS);
        let reloc_count_buf = storage_u32_copy(device, "codegen.x86.reloc_count", 1);
        let reloc_kind_buf = storage_u32_copy(device, "codegen.x86.reloc_kind", MAX_X86_RELOCS);
        let reloc_site_inst_buf =
            storage_u32_copy(device, "codegen.x86.reloc_site_inst", MAX_X86_RELOCS);
        let reloc_target_inst_buf =
            storage_u32_copy(device, "codegen.x86.reloc_target_inst", MAX_X86_RELOCS);
        let select_status_buf = storage_u32_copy(device, "codegen.x86.select_status", 4);
        let inst_size_buf = storage_u32_copy(device, "codegen.x86.inst_size", MAX_X86_INSTS);
        let size_status_buf = storage_u32_copy(device, "codegen.x86.size_status", 4);
        let inst_byte_offset_buf =
            storage_u32_copy(device, "codegen.x86.inst_byte_offset", MAX_X86_INSTS);
        let text_len_buf = storage_u32_copy(device, "codegen.x86.text_len", 1);
        let text_status_buf = storage_u32_copy(device, "codegen.x86.text_status", 4);
        let text_words_buf = storage_u32_copy(device, "codegen.x86.text_words", output_words);
        let encode_status_buf = storage_u32_copy(device, "codegen.x86.encode_status", 4);
        let reloc_status_buf = storage_u32_copy(device, "codegen.x86.reloc_status", 4);
        let elf_layout_buf = storage_u32_copy(device, "codegen.x86.elf_layout", 8);
        let layout_status_buf = storage_u32_copy(device, "codegen.x86.layout_status", 4);
        let status_buf = storage_u32_copy(device, "codegen.x86.status", 4);
        let out_buf = storage_u32_copy(device, "codegen.x86.out_words", output_words);
        let status_readback = readback_u32s(device, "rb.codegen.x86.status", 4);
        let trace_status_words = 126usize;
        let status_trace_readback = if std::env::var("LANIUS_X86_STATUS_TRACE").is_ok_and(|value| {
            let value = value.trim();
            matches!(value, "1" | "true" | "TRUE" | "True")
        }) {
            Some(readback_u32s(
                device,
                "rb.codegen.x86.status_trace",
                trace_status_words,
            ))
        } else {
            None
        };
        let out_readback = readback_u32s(device, "rb.codegen.x86.out_words", output_words);

        let node_inst_scan_steps = scan_steps_for_blocks(node_inst_scan_blocks);
        let node_inst_scan_params_bufs = node_inst_scan_steps
            .iter()
            .map(|step| {
                let params = X86ScanParams {
                    n_items: node_inst_scan_words as u32,
                    n_blocks: node_inst_scan_blocks as u32,
                    scan_step: *step,
                };
                let bytes = x86_scan_params_bytes(&params);
                uniform_u32_struct(
                    device,
                    &format!("codegen.x86.node_inst_scan.params.{step}"),
                    &bytes,
                )
            })
            .collect::<Vec<_>>();
        let func_inst_scan_steps = scan_steps_for_blocks(func_inst_scan_blocks);
        let func_inst_scan_params_bufs = func_inst_scan_steps
            .iter()
            .map(|step| {
                let params = X86ScanParams {
                    n_items: func_inst_scan_words as u32,
                    n_blocks: func_inst_scan_blocks as u32,
                    scan_step: *step,
                };
                let bytes = x86_scan_params_bytes(&params);
                uniform_u32_struct(
                    device,
                    &format!("codegen.x86.func_inst_scan.params.{step}"),
                    &bytes,
                )
            })
            .collect::<Vec<_>>();

        queue.write_buffer(&params_buf, 0, &params_bytes);
        for (step, buf) in node_inst_scan_steps
            .iter()
            .zip(node_inst_scan_params_bufs.iter())
        {
            let params = X86ScanParams {
                n_items: node_inst_scan_words as u32,
                n_blocks: node_inst_scan_blocks as u32,
                scan_step: *step,
            };
            queue.write_buffer(buf, 0, &x86_scan_params_bytes(&params));
        }
        for (step, buf) in func_inst_scan_steps
            .iter()
            .zip(func_inst_scan_params_bufs.iter())
        {
            let params = X86ScanParams {
                n_items: func_inst_scan_words as u32,
                n_blocks: func_inst_scan_blocks as u32,
                scan_step: *step,
            };
            queue.write_buffer(buf, 0, &x86_scan_params_bytes(&params));
        }
        include!("record_init.rs");

        let node_tree_info_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.node_tree_info.bind_group"),
            &self.node_tree_info_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("parent", parent_buf.as_entire_binding()),
                ("first_child", first_child_buf.as_entire_binding()),
                ("next_sibling", next_sibling_buf.as_entire_binding()),
                ("subtree_end", subtree_end_buf.as_entire_binding()),
                (
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_tree_status",
                    node_tree_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let func_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.func_discover.bind_group"),
            &self.func_discover_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                (
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_tree_status",
                    node_tree_status_buf.as_entire_binding(),
                ),
                (
                    "hir_item_kind",
                    function_metadata.item_kind.as_entire_binding(),
                ),
                (
                    "hir_item_decl_token",
                    function_metadata.item_decl_token.as_entire_binding(),
                ),
                (
                    "fn_entrypoint_tag",
                    fn_entrypoint_tag_buf.as_entire_binding(),
                ),
                ("x86_func_meta", func_meta_buf.as_entire_binding()),
                ("x86_func_record", func_record_buf.as_entire_binding()),
                ("x86_node_func", node_func_buf.as_entire_binding()),
                (
                    "x86_func_lookup_key",
                    func_lookup_key_buf.as_entire_binding(),
                ),
                (
                    "x86_func_lookup_node",
                    func_lookup_node_buf.as_entire_binding(),
                ),
            ],
        )?;
        let call_records_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.call_records.bind_group"),
            &self.call_records_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                ("x86_node_func", node_func_buf.as_entire_binding()),
                (
                    "hir_call_callee_node",
                    call_metadata.callee_node.as_entire_binding(),
                ),
                (
                    "hir_call_arg_start",
                    call_metadata.arg_start.as_entire_binding(),
                ),
                (
                    "hir_call_arg_end",
                    call_metadata.arg_end.as_entire_binding(),
                ),
                (
                    "hir_call_arg_count",
                    call_metadata.arg_count.as_entire_binding(),
                ),
                (
                    "call_fn_index",
                    call_metadata.call_fn_index.as_entire_binding(),
                ),
                (
                    "call_return_type",
                    call_metadata.call_return_type.as_entire_binding(),
                ),
                (
                    "call_return_type_token",
                    call_metadata.call_return_type_token.as_entire_binding(),
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
            ],
        )?;
        let const_values_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.const_values.bind_group"),
            &self.const_values_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                (
                    "hir_expr_int_value",
                    expr_metadata.int_value.as_entire_binding(),
                ),
                (
                    "hir_stmt_record",
                    expr_metadata.stmt_record.as_entire_binding(),
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
        let param_regs_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.param_regs.bind_group"),
            &self.param_regs_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                (
                    "hir_param_record",
                    function_metadata.param_record.as_entire_binding(),
                ),
                (
                    "hir_item_decl_token",
                    function_metadata.item_decl_token.as_entire_binding(),
                ),
                (
                    "call_param_type",
                    call_metadata.call_param_type.as_entire_binding(),
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
        let local_literals_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.local_literals.bind_group"),
            &self.local_literals_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("parent", parent_buf.as_entire_binding()),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                (
                    "hir_expr_int_value",
                    expr_metadata.int_value.as_entire_binding(),
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
        let func_return_stmts_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.func_return_stmts.bind_group"),
            &self.func_return_stmts_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("parent", parent_buf.as_entire_binding()),
                (
                    "hir_stmt_record",
                    expr_metadata.stmt_record.as_entire_binding(),
                ),
                (
                    "x86_func_return_stmt_record",
                    func_return_stmt_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_return_stmt_count",
                    func_return_stmt_count_buf.as_entire_binding(),
                ),
                (
                    "x86_func_return_stmt_status",
                    func_return_stmt_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let block_return_stmts_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.block_return_stmts.bind_group"),
            &self.block_return_stmts_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("parent", parent_buf.as_entire_binding()),
                (
                    "hir_stmt_record",
                    expr_metadata.stmt_record.as_entire_binding(),
                ),
                (
                    "x86_block_return_stmt_record",
                    block_return_stmt_record_buf.as_entire_binding(),
                ),
                (
                    "x86_block_return_stmt_count",
                    block_return_stmt_count_buf.as_entire_binding(),
                ),
                (
                    "x86_block_return_stmt_status",
                    block_return_stmt_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let terminal_ifs_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.terminal_ifs.bind_group"),
            &self.terminal_ifs_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("parent", parent_buf.as_entire_binding()),
                (
                    "hir_stmt_record",
                    expr_metadata.stmt_record.as_entire_binding(),
                ),
                ("x86_node_func", node_func_buf.as_entire_binding()),
                (
                    "x86_block_return_stmt_record",
                    block_return_stmt_record_buf.as_entire_binding(),
                ),
                (
                    "x86_block_return_stmt_count",
                    block_return_stmt_count_buf.as_entire_binding(),
                ),
                (
                    "x86_block_return_stmt_status",
                    block_return_stmt_status_buf.as_entire_binding(),
                ),
                (
                    "x86_return_call_record",
                    return_call_record_buf.as_entire_binding(),
                ),
                (
                    "x86_return_call_status",
                    return_call_status_buf.as_entire_binding(),
                ),
                (
                    "x86_terminal_if_record",
                    terminal_if_record_buf.as_entire_binding(),
                ),
                (
                    "x86_terminal_if_count",
                    terminal_if_count_buf.as_entire_binding(),
                ),
                (
                    "x86_terminal_if_status",
                    terminal_if_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let return_calls_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.return_calls.bind_group"),
            &self.return_calls_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("parent", parent_buf.as_entire_binding()),
                ("subtree_end", subtree_end_buf.as_entire_binding()),
                ("x86_node_func", node_func_buf.as_entire_binding()),
                (
                    "x86_func_return_stmt_record",
                    func_return_stmt_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_return_stmt_count",
                    func_return_stmt_count_buf.as_entire_binding(),
                ),
                (
                    "x86_return_call_record",
                    return_call_record_buf.as_entire_binding(),
                ),
                (
                    "x86_return_call_count",
                    return_call_count_buf.as_entire_binding(),
                ),
                (
                    "x86_return_call_status",
                    return_call_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let call_arg_values_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.call_arg_values.bind_group"),
            &self.call_arg_values_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                (
                    "hir_expr_int_value",
                    expr_metadata.int_value.as_entire_binding(),
                ),
                ("visible_decl", visible_decl_buf.as_entire_binding()),
                ("x86_call_record", call_record_buf.as_entire_binding()),
                (
                    "x86_const_value_record",
                    const_value_record_buf.as_entire_binding(),
                ),
                (
                    "x86_const_value_status",
                    const_value_status_buf.as_entire_binding(),
                ),
                (
                    "x86_param_reg_record",
                    param_reg_record_buf.as_entire_binding(),
                ),
                (
                    "x86_param_reg_status",
                    param_reg_status_uniform_buf.as_entire_binding(),
                ),
                (
                    "x86_local_literal_record",
                    local_literal_record_buf.as_entire_binding(),
                ),
                (
                    "x86_local_literal_status",
                    local_literal_status_buf.as_entire_binding(),
                ),
                (
                    "hir_call_arg_parent_call",
                    call_metadata.arg_parent_call.as_entire_binding(),
                ),
                (
                    "hir_call_arg_ordinal",
                    call_metadata.arg_ordinal.as_entire_binding(),
                ),
                (
                    "call_record_status",
                    call_record_status_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_value_record",
                    call_arg_value_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_eval_record",
                    call_arg_eval_record_buf.as_entire_binding(),
                ),
                (
                    "call_arg_value_status",
                    call_arg_value_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let call_arg_lookup_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.call_arg_lookup.bind_group"),
            &self.call_arg_lookup_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("x86_call_record", call_record_buf.as_entire_binding()),
                (
                    "call_record_status",
                    call_record_status_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_value_record",
                    call_arg_value_record_buf.as_entire_binding(),
                ),
                (
                    "call_arg_value_status",
                    call_arg_value_status_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_lookup_record",
                    call_arg_lookup_record_buf.as_entire_binding(),
                ),
                (
                    "call_arg_lookup_status",
                    call_arg_lookup_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let intrinsic_calls_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.intrinsic_calls.bind_group"),
            &self.intrinsic_calls_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("parent", parent_buf.as_entire_binding()),
                (
                    "hir_call_arg_parent_call",
                    call_metadata.arg_parent_call.as_entire_binding(),
                ),
                (
                    "hir_call_arg_ordinal",
                    call_metadata.arg_ordinal.as_entire_binding(),
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
                    "x86_call_arg_lookup_record",
                    call_arg_lookup_record_buf.as_entire_binding(),
                ),
                (
                    "call_arg_lookup_status",
                    call_arg_lookup_status_buf.as_entire_binding(),
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
        let call_abi_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.call_abi.bind_group"),
            &self.call_abi_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                (
                    "x86_func_lookup_key",
                    func_lookup_key_buf.as_entire_binding(),
                ),
                (
                    "x86_func_lookup_node",
                    func_lookup_node_buf.as_entire_binding(),
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
                    "x86_call_arg_value_record",
                    call_arg_value_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_lookup_record",
                    call_arg_lookup_record_buf.as_entire_binding(),
                ),
                (
                    "call_arg_lookup_status",
                    call_arg_lookup_status_buf.as_entire_binding(),
                ),
                (
                    "call_intrinsic_tag",
                    call_metadata.call_intrinsic_tag.as_entire_binding(),
                ),
                (
                    "x86_call_abi_record",
                    call_abi_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_abi_record",
                    call_arg_abi_record_buf.as_entire_binding(),
                ),
                ("x86_call_abi_flags", call_abi_flags_buf.as_entire_binding()),
                ("call_abi_status", call_abi_status_buf.as_entire_binding()),
            ],
        )?;
        let call_arg_widths_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.call_arg_widths.bind_group"),
            &self.call_arg_widths_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("x86_call_record", call_record_buf.as_entire_binding()),
                (
                    "call_record_status",
                    call_record_status_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_value_record",
                    call_arg_value_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_eval_record",
                    call_arg_eval_record_buf.as_entire_binding(),
                ),
                (
                    "call_arg_value_status",
                    call_arg_value_status_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_abi_record",
                    call_arg_abi_record_buf.as_entire_binding(),
                ),
                ("call_abi_status", call_abi_status_buf.as_entire_binding()),
                (
                    "x86_call_arg_width_record",
                    call_arg_width_record_buf.as_entire_binding(),
                ),
                (
                    "call_arg_width_status",
                    call_arg_width_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let call_arg_prefix_seed_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.call_arg_prefix_seed.bind_group"),
            &self.call_arg_prefix_seed_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                (
                    "x86_call_arg_width_record",
                    call_arg_width_record_buf.as_entire_binding(),
                ),
                (
                    "call_arg_width_status",
                    call_arg_width_status_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_width_slot_record",
                    call_arg_width_slot_record_buf.as_entire_binding(),
                ),
                (
                    "call_arg_prefix_seed_status",
                    call_arg_prefix_seed_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let call_arg_prefix_scan_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.call_arg_prefix_scan.bind_group"),
            &self.call_arg_prefix_scan_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("x86_call_record", call_record_buf.as_entire_binding()),
                (
                    "call_record_status",
                    call_record_status_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_width_slot_record",
                    call_arg_width_slot_record_buf.as_entire_binding(),
                ),
                (
                    "call_arg_prefix_seed_status",
                    call_arg_prefix_seed_status_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_prefix_record",
                    call_arg_prefix_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_total_width_record",
                    call_arg_total_width_record_buf.as_entire_binding(),
                ),
                (
                    "call_arg_prefix_status",
                    call_arg_prefix_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let call_arg_vregs_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.call_arg_vregs.bind_group"),
            &self.call_arg_vregs_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("x86_call_record", call_record_buf.as_entire_binding()),
                (
                    "call_record_status",
                    call_record_status_buf.as_entire_binding(),
                ),
                (
                    "x86_call_abi_record",
                    call_abi_record_buf.as_entire_binding(),
                ),
                ("call_abi_status", call_abi_status_buf.as_entire_binding()),
                (
                    "x86_call_arg_prefix_record",
                    call_arg_prefix_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_total_width_record",
                    call_arg_total_width_record_buf.as_entire_binding(),
                ),
                (
                    "call_arg_prefix_status",
                    call_arg_prefix_status_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_range_record",
                    call_arg_range_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_vreg_summary_record",
                    call_vreg_summary_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_vreg_count_record",
                    call_vreg_count_record_buf.as_entire_binding(),
                ),
                (
                    "call_arg_vreg_status",
                    call_arg_vreg_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let node_inst_counts_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.node_inst_counts.bind_group"),
            &self.node_inst_counts_pass,
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
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_tree_status",
                    node_tree_status_buf.as_entire_binding(),
                ),
                ("x86_call_record", call_record_buf.as_entire_binding()),
                (
                    "call_record_status",
                    call_record_status_buf.as_entire_binding(),
                ),
                (
                    "x86_intrinsic_call_record",
                    intrinsic_call_record_buf.as_entire_binding(),
                ),
                (
                    "x86_intrinsic_call_status",
                    intrinsic_call_status_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_count_record",
                    node_inst_count_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_scan_input",
                    node_inst_scan_input_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_count_status",
                    node_inst_count_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let node_inst_order_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.node_inst_order.bind_group"),
            &self.node_inst_order_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                (
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_tree_status",
                    node_tree_status_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_count_record",
                    node_inst_count_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_count_status",
                    node_inst_count_status_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_order_record",
                    node_inst_order_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_order_node",
                    node_inst_order_node_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_order_slot",
                    node_inst_order_slot_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_scan_input",
                    node_inst_scan_input_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_order_status",
                    node_inst_order_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let node_inst_scan_local_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.node_inst_scan_local.bind_group"),
            &self.node_inst_scan_local_pass,
            0,
            &[
                ("gScan", node_inst_scan_params_bufs[0].as_entire_binding()),
                (
                    "x86_node_inst_scan_input",
                    node_inst_scan_input_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_scan_local_prefix",
                    node_inst_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_scan_block_sum",
                    node_inst_scan_block_sum_buf.as_entire_binding(),
                ),
            ],
        )?;
        let node_inst_scan_block_bind_groups = node_inst_scan_params_bufs
            .iter()
            .enumerate()
            .map(|(step_i, params_buf)| {
                let input_buf = if step_i % 2 == 0 {
                    &node_inst_scan_prefix_b_buf
                } else {
                    &node_inst_scan_prefix_a_buf
                };
                let output_buf = if step_i % 2 == 0 {
                    &node_inst_scan_prefix_a_buf
                } else {
                    &node_inst_scan_prefix_b_buf
                };
                reflected_bind_group(
                    device,
                    Some("codegen.x86.node_inst_scan_blocks.bind_group"),
                    &self.node_inst_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", params_buf.as_entire_binding()),
                        (
                            "x86_node_inst_scan_block_sum",
                            node_inst_scan_block_sum_buf.as_entire_binding(),
                        ),
                        (
                            "x86_node_inst_scan_block_prefix_in",
                            input_buf.as_entire_binding(),
                        ),
                        (
                            "x86_node_inst_scan_block_prefix_out",
                            output_buf.as_entire_binding(),
                        ),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let final_node_inst_scan_prefix_buf = if (node_inst_scan_params_bufs.len() - 1) % 2 == 0 {
            &node_inst_scan_prefix_a_buf
        } else {
            &node_inst_scan_prefix_b_buf
        };
        let node_inst_prefix_scan_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.node_inst_prefix_scan.bind_group"),
            &self.node_inst_prefix_scan_pass,
            0,
            &[
                ("gScan", node_inst_scan_params_bufs[0].as_entire_binding()),
                (
                    "x86_node_inst_order_record",
                    node_inst_order_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_order_status",
                    node_inst_order_status_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_scan_local_prefix",
                    node_inst_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_scan_block_prefix",
                    final_node_inst_scan_prefix_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_range_record",
                    node_inst_range_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_range_status",
                    node_inst_range_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let node_inst_locations_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.node_inst_locations.bind_group"),
            &self.node_inst_locations_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                (
                    "hir_stmt_record",
                    expr_metadata.stmt_record.as_entire_binding(),
                ),
                (
                    "x86_node_inst_count_record",
                    node_inst_count_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_range_record",
                    node_inst_range_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_range_status",
                    node_inst_range_status_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_location_record",
                    node_inst_location_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_location_status",
                    node_inst_location_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let node_inst_gen_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.node_inst_gen.bind_group"),
            &self.node_inst_gen_pass,
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
                    "hir_expr_int_value",
                    expr_metadata.int_value.as_entire_binding(),
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
                (
                    "x86_param_reg_record",
                    param_reg_record_buf.as_entire_binding(),
                ),
                (
                    "x86_param_reg_status",
                    param_reg_status_buf.as_entire_binding(),
                ),
                ("x86_call_record", call_record_buf.as_entire_binding()),
                (
                    "call_record_status",
                    call_record_status_buf.as_entire_binding(),
                ),
                (
                    "x86_call_abi_record",
                    call_abi_record_buf.as_entire_binding(),
                ),
                ("call_abi_status", call_abi_status_buf.as_entire_binding()),
                (
                    "x86_intrinsic_call_record",
                    intrinsic_call_record_buf.as_entire_binding(),
                ),
                (
                    "x86_intrinsic_call_status",
                    intrinsic_call_status_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_range_record",
                    node_inst_range_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_range_status",
                    node_inst_range_status_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_location_record",
                    node_inst_location_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_location_status",
                    node_inst_location_status_buf.as_entire_binding(),
                ),
                (
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_value_record",
                    node_value_record_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_record",
                    virtual_inst_record_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_args",
                    virtual_inst_args_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_status",
                    virtual_inst_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let virtual_use_edges_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.virtual_use_edges.bind_group"),
            &self.virtual_use_edges_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "x86_virtual_inst_record",
                    virtual_inst_record_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_args",
                    virtual_inst_args_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_status",
                    virtual_inst_status_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_use_key",
                    virtual_use_key_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_use_value",
                    virtual_use_value_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_vreg_use_count",
                    virtual_vreg_use_count_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_use_status",
                    virtual_use_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let virtual_liveness_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.virtual_liveness.bind_group"),
            &self.virtual_liveness_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "x86_virtual_inst_record",
                    virtual_inst_record_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_use_key",
                    virtual_use_key_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_use_value",
                    virtual_use_value_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_vreg_use_count",
                    virtual_vreg_use_count_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_use_status",
                    virtual_use_status_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_live_start",
                    virtual_live_start_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_live_end",
                    virtual_live_end_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_liveness_status",
                    virtual_liveness_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let virtual_regalloc_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.virtual_regalloc.bind_group"),
            &self.virtual_regalloc_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "x86_virtual_inst_record",
                    virtual_inst_record_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_live_start",
                    virtual_live_start_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_live_end",
                    virtual_live_end_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_liveness_status",
                    virtual_liveness_status_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_phys_reg",
                    virtual_phys_reg_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_regalloc_status",
                    virtual_regalloc_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let func_body_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.func_body_plan.bind_group"),
            &self.func_body_plan_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                (
                    "hir_expr_int_value",
                    expr_metadata.int_value.as_entire_binding(),
                ),
                ("visible_decl", visible_decl_buf.as_entire_binding()),
                (
                    "x86_const_value_record",
                    const_value_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_abi_record",
                    call_abi_record_buf.as_entire_binding(),
                ),
                (
                    "call_abi_status",
                    call_abi_status_uniform_buf.as_entire_binding(),
                ),
                (
                    "x86_param_reg_record",
                    param_reg_record_buf.as_entire_binding(),
                ),
                (
                    "x86_param_reg_status",
                    param_reg_status_uniform_buf.as_entire_binding(),
                ),
                (
                    "x86_local_literal_record",
                    local_literal_record_buf.as_entire_binding(),
                ),
                (
                    "x86_local_literal_status",
                    local_literal_status_uniform_buf.as_entire_binding(),
                ),
                (
                    "x86_func_return_stmt_record",
                    func_return_stmt_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_return_stmt_count",
                    func_return_stmt_count_buf.as_entire_binding(),
                ),
                (
                    "x86_func_return_stmt_status",
                    func_return_stmt_status_uniform_buf.as_entire_binding(),
                ),
                (
                    "x86_terminal_if_record",
                    terminal_if_record_buf.as_entire_binding(),
                ),
                (
                    "x86_terminal_if_count",
                    terminal_if_count_buf.as_entire_binding(),
                ),
                (
                    "x86_terminal_if_status",
                    terminal_if_status_uniform_buf.as_entire_binding(),
                ),
                (
                    "x86_func_body_status",
                    func_body_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let lower_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.lower_values.bind_group"),
            &self.lower_values_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                (
                    "hir_expr_int_value",
                    expr_metadata.int_value.as_entire_binding(),
                ),
                ("visible_decl", visible_decl_buf.as_entire_binding()),
                (
                    "x86_const_value_record",
                    const_value_record_buf.as_entire_binding(),
                ),
                (
                    "x86_const_value_status",
                    const_value_status_uniform_buf.as_entire_binding(),
                ),
                (
                    "x86_local_literal_record",
                    local_literal_record_buf.as_entire_binding(),
                ),
                (
                    "x86_local_literal_status",
                    local_literal_status_uniform_buf.as_entire_binding(),
                ),
                (
                    "x86_func_return_stmt_record",
                    func_return_stmt_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_return_stmt_status",
                    func_return_stmt_status_uniform_buf.as_entire_binding(),
                ),
                (
                    "x86_terminal_if_record",
                    terminal_if_record_buf.as_entire_binding(),
                ),
                (
                    "x86_terminal_if_status",
                    terminal_if_status_uniform_buf.as_entire_binding(),
                ),
                (
                    "x86_return_call_record",
                    return_call_record_buf.as_entire_binding(),
                ),
                (
                    "x86_return_call_status",
                    return_call_status_uniform_buf.as_entire_binding(),
                ),
                ("x86_func_meta", func_meta_uniform_buf.as_entire_binding()),
                ("x86_vreg_kind", vreg_kind_buf.as_entire_binding()),
                ("x86_vreg_value", vreg_value_buf.as_entire_binding()),
                ("x86_vreg_args", vreg_args_buf.as_entire_binding()),
                ("x86_vreg_op", vreg_op_buf.as_entire_binding()),
                ("x86_expr_vreg", expr_vreg_buf.as_entire_binding()),
                ("x86_return_vreg", return_vreg_buf.as_entire_binding()),
                ("lower_status", lower_status_buf.as_entire_binding()),
            ],
        )?;
        let use_edges_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.use_edges.bind_group"),
            &self.use_edges_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("x86_vreg_kind", vreg_kind_buf.as_entire_binding()),
                ("x86_vreg_args", vreg_args_buf.as_entire_binding()),
                ("lower_status", lower_status_buf.as_entire_binding()),
                ("x86_return_vreg", return_vreg_buf.as_entire_binding()),
                ("x86_use_key", use_key_buf.as_entire_binding()),
                ("x86_use_value", use_value_buf.as_entire_binding()),
                ("x86_vreg_use_count", vreg_use_count_buf.as_entire_binding()),
                ("use_status", use_status_buf.as_entire_binding()),
            ],
        )?;
        let liveness_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.liveness.bind_group"),
            &self.liveness_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("x86_vreg_kind", vreg_kind_buf.as_entire_binding()),
                ("lower_status", lower_status_buf.as_entire_binding()),
                ("x86_use_key", use_key_buf.as_entire_binding()),
                ("x86_use_value", use_value_buf.as_entire_binding()),
                ("x86_vreg_use_count", vreg_use_count_buf.as_entire_binding()),
                ("use_status", use_status_buf.as_entire_binding()),
                ("x86_live_start", live_start_buf.as_entire_binding()),
                ("x86_live_end", live_end_buf.as_entire_binding()),
                ("liveness_status", liveness_status_buf.as_entire_binding()),
            ],
        )?;
        let regalloc_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.regalloc.bind_group"),
            &self.regalloc_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("x86_vreg_kind", vreg_kind_buf.as_entire_binding()),
                ("x86_live_start", live_start_buf.as_entire_binding()),
                ("x86_live_end", live_end_buf.as_entire_binding()),
                ("liveness_status", liveness_status_buf.as_entire_binding()),
                ("x86_return_vreg", return_vreg_buf.as_entire_binding()),
                ("x86_phys_reg", phys_reg_buf.as_entire_binding()),
                ("regalloc_status", regalloc_status_buf.as_entire_binding()),
            ],
        )?;
        let func_inst_counts_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.func_inst_counts.bind_group"),
            &self.func_inst_counts_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("x86_func_meta", func_meta_uniform_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("parent", parent_buf.as_entire_binding()),
                (
                    "hir_stmt_record",
                    expr_metadata.stmt_record.as_entire_binding(),
                ),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                ("visible_decl", visible_decl_buf.as_entire_binding()),
                (
                    "x86_const_value_record",
                    const_value_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_abi_record",
                    call_abi_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_lookup_record",
                    call_arg_lookup_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_eval_record",
                    call_arg_eval_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_return_stmt_record",
                    func_return_stmt_record_buf.as_entire_binding(),
                ),
                (
                    "x86_terminal_if_record",
                    terminal_if_record_buf.as_entire_binding(),
                ),
                (
                    "x86_param_reg_record",
                    param_reg_record_buf.as_entire_binding(),
                ),
                (
                    "x86_intrinsic_call_record",
                    intrinsic_call_record_buf.as_entire_binding(),
                ),
                (
                    "x86_intrinsic_call_status",
                    intrinsic_call_status_buf.as_entire_binding(),
                ),
                ("x86_vreg_kind", vreg_kind_buf.as_entire_binding()),
                ("x86_vreg_value", vreg_value_buf.as_entire_binding()),
                ("x86_vreg_op", vreg_op_buf.as_entire_binding()),
                ("x86_vreg_args", vreg_args_buf.as_entire_binding()),
                (
                    "regalloc_status",
                    regalloc_status_uniform_buf.as_entire_binding(),
                ),
                ("x86_return_vreg", return_vreg_buf.as_entire_binding()),
                (
                    "x86_func_inst_count_record",
                    func_inst_count_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_inst_count_status",
                    func_inst_count_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let func_inst_order_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.func_inst_order.bind_group"),
            &self.func_inst_order_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                (
                    "x86_func_inst_count_record",
                    func_inst_count_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_inst_count_status",
                    func_inst_count_status_buf.as_entire_binding(),
                ),
                (
                    "x86_func_inst_order_record",
                    func_inst_order_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_inst_order_slot",
                    func_inst_order_slot_buf.as_entire_binding(),
                ),
                (
                    "x86_func_inst_scan_input",
                    func_inst_scan_input_buf.as_entire_binding(),
                ),
                (
                    "x86_func_inst_order_status",
                    func_inst_order_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let func_inst_scan_local_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.func_inst_scan_local.bind_group"),
            &self.func_inst_scan_local_pass,
            0,
            &[
                ("gScan", func_inst_scan_params_bufs[0].as_entire_binding()),
                (
                    "x86_func_inst_scan_input",
                    func_inst_scan_input_buf.as_entire_binding(),
                ),
                (
                    "x86_func_inst_scan_local_prefix",
                    func_inst_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "x86_func_inst_scan_block_sum",
                    func_inst_scan_block_sum_buf.as_entire_binding(),
                ),
            ],
        )?;
        let func_inst_scan_block_bind_groups = func_inst_scan_params_bufs
            .iter()
            .enumerate()
            .map(|(step_i, params_buf)| {
                let input_buf = if step_i % 2 == 0 {
                    &func_inst_scan_prefix_b_buf
                } else {
                    &func_inst_scan_prefix_a_buf
                };
                let output_buf = if step_i % 2 == 0 {
                    &func_inst_scan_prefix_a_buf
                } else {
                    &func_inst_scan_prefix_b_buf
                };
                reflected_bind_group(
                    device,
                    Some("codegen.x86.func_inst_scan_blocks.bind_group"),
                    &self.func_inst_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", params_buf.as_entire_binding()),
                        (
                            "x86_func_inst_scan_block_sum",
                            func_inst_scan_block_sum_buf.as_entire_binding(),
                        ),
                        (
                            "x86_func_inst_scan_block_prefix_in",
                            input_buf.as_entire_binding(),
                        ),
                        (
                            "x86_func_inst_scan_block_prefix_out",
                            output_buf.as_entire_binding(),
                        ),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let final_func_inst_scan_prefix_buf = if (func_inst_scan_params_bufs.len() - 1) % 2 == 0 {
            &func_inst_scan_prefix_a_buf
        } else {
            &func_inst_scan_prefix_b_buf
        };
        let func_inst_prefix_scan_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.func_inst_prefix_scan.bind_group"),
            &self.func_inst_prefix_scan_pass,
            0,
            &[
                ("gScan", func_inst_scan_params_bufs[0].as_entire_binding()),
                (
                    "x86_func_inst_order_record",
                    func_inst_order_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_inst_order_slot",
                    func_inst_order_slot_buf.as_entire_binding(),
                ),
                (
                    "x86_func_inst_order_status",
                    func_inst_order_status_buf.as_entire_binding(),
                ),
                (
                    "x86_func_inst_scan_local_prefix",
                    func_inst_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "x86_func_inst_scan_block_prefix",
                    final_func_inst_scan_prefix_buf.as_entire_binding(),
                ),
                (
                    "x86_func_inst_range_record",
                    func_inst_range_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_inst_range_status",
                    func_inst_range_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let func_layout_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.func_layout.bind_group"),
            &self.func_layout_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                (
                    "x86_func_inst_count_record",
                    func_inst_count_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_inst_count_status",
                    func_inst_count_status_buf.as_entire_binding(),
                ),
                (
                    "x86_func_inst_range_record",
                    func_inst_range_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_inst_range_status",
                    func_inst_range_status_buf.as_entire_binding(),
                ),
                (
                    "x86_func_layout_record",
                    func_layout_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_layout_status",
                    func_layout_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let inst_plan_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.inst_plan.bind_group"),
            &self.inst_plan_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("x86_return_vreg", return_vreg_buf.as_entire_binding()),
                ("x86_vreg_value", vreg_value_buf.as_entire_binding()),
                (
                    "x86_call_abi_record",
                    call_abi_record_buf.as_entire_binding(),
                ),
                (
                    "x86_terminal_if_record",
                    terminal_if_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_layout_record",
                    func_layout_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_layout_status",
                    func_layout_status_buf.as_entire_binding(),
                ),
                (
                    "x86_func_return_inst_status",
                    func_return_inst_status_buf.as_entire_binding(),
                ),
                (
                    "x86_entry_inst_status",
                    entry_inst_status_buf.as_entire_binding(),
                ),
                ("x86_select_plan", select_plan_buf.as_entire_binding()),
                ("plan_status", plan_status_buf.as_entire_binding()),
            ],
        )?;
        let reloc_plan_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.reloc_plan.bind_group"),
            &self.reloc_plan_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("x86_return_vreg", return_vreg_buf.as_entire_binding()),
                ("x86_vreg_value", vreg_value_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("parent", parent_buf.as_entire_binding()),
                (
                    "hir_stmt_record",
                    expr_metadata.stmt_record.as_entire_binding(),
                ),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                ("visible_decl", visible_decl_buf.as_entire_binding()),
                (
                    "x86_call_abi_record",
                    call_abi_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_lookup_record",
                    call_arg_lookup_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_eval_record",
                    call_arg_eval_record_buf.as_entire_binding(),
                ),
                (
                    "x86_terminal_if_record",
                    terminal_if_record_buf.as_entire_binding(),
                ),
                (
                    "x86_param_reg_record",
                    param_reg_record_buf.as_entire_binding(),
                ),
                (
                    "x86_intrinsic_call_record",
                    intrinsic_call_record_buf.as_entire_binding(),
                ),
                (
                    "x86_intrinsic_call_status",
                    intrinsic_call_status_buf.as_entire_binding(),
                ),
                ("x86_select_plan", select_plan_buf.as_entire_binding()),
                (
                    "x86_func_layout_record",
                    func_layout_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_layout_status",
                    func_layout_status_buf.as_entire_binding(),
                ),
                (
                    "x86_entry_inst_status",
                    entry_inst_status_buf.as_entire_binding(),
                ),
                ("plan_status", plan_status_buf.as_entire_binding()),
                (
                    "x86_planned_reloc_kind",
                    planned_reloc_kind_buf.as_entire_binding(),
                ),
                (
                    "x86_planned_reloc_site_inst",
                    planned_reloc_site_inst_buf.as_entire_binding(),
                ),
                (
                    "x86_planned_reloc_target_inst",
                    planned_reloc_target_inst_buf.as_entire_binding(),
                ),
            ],
        )?;
        let func_return_inst_plan_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.func_return_inst_plan.bind_group"),
            &self.func_return_inst_plan_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                (
                    "hir_expr_int_value",
                    expr_metadata.int_value.as_entire_binding(),
                ),
                ("visible_decl", visible_decl_buf.as_entire_binding()),
                (
                    "x86_const_value_record",
                    const_value_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_abi_record",
                    call_abi_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_lookup_record",
                    call_arg_lookup_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_eval_record",
                    call_arg_eval_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_return_stmt_record",
                    func_return_stmt_record_buf.as_entire_binding(),
                ),
                (
                    "x86_terminal_if_record",
                    terminal_if_record_buf.as_entire_binding(),
                ),
                (
                    "x86_param_reg_record",
                    param_reg_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_layout_record",
                    func_layout_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_layout_status",
                    func_layout_status_buf.as_entire_binding(),
                ),
                (
                    "x86_planned_inst_kind",
                    planned_inst_kind_buf.as_entire_binding(),
                ),
                (
                    "x86_planned_inst_arg0",
                    planned_inst_arg0_buf.as_entire_binding(),
                ),
                (
                    "x86_func_return_inst_status",
                    func_return_inst_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let entry_inst_plan_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.entry_inst_plan.bind_group"),
            &self.entry_inst_plan_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("parent", parent_buf.as_entire_binding()),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                (
                    "hir_expr_int_value",
                    expr_metadata.int_value.as_entire_binding(),
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
                (
                    "x86_intrinsic_call_record",
                    intrinsic_call_record_buf.as_entire_binding(),
                ),
                (
                    "x86_intrinsic_call_status",
                    intrinsic_call_status_buf.as_entire_binding(),
                ),
                ("x86_vreg_kind", vreg_kind_buf.as_entire_binding()),
                ("x86_vreg_value", vreg_value_buf.as_entire_binding()),
                ("x86_vreg_args", vreg_args_buf.as_entire_binding()),
                ("x86_vreg_op", vreg_op_buf.as_entire_binding()),
                ("x86_use_key", use_key_buf.as_entire_binding()),
                ("x86_use_value", use_value_buf.as_entire_binding()),
                ("x86_return_vreg", return_vreg_buf.as_entire_binding()),
                (
                    "x86_call_abi_record",
                    call_abi_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_lookup_record",
                    call_arg_lookup_record_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_eval_record",
                    call_arg_eval_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_layout_record",
                    func_layout_record_buf.as_entire_binding(),
                ),
                (
                    "x86_func_layout_status",
                    func_layout_status_buf.as_entire_binding(),
                ),
                (
                    "x86_func_return_inst_status",
                    func_return_inst_status_buf.as_entire_binding(),
                ),
                (
                    "x86_planned_inst_kind",
                    planned_inst_kind_buf.as_entire_binding(),
                ),
                (
                    "x86_planned_inst_arg0",
                    planned_inst_arg0_buf.as_entire_binding(),
                ),
                (
                    "x86_entry_inst_status",
                    entry_inst_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let select_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.select.bind_group"),
            &self.select_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("x86_select_plan", select_plan_buf.as_entire_binding()),
                (
                    "x86_virtual_inst_record",
                    virtual_inst_record_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_args",
                    virtual_inst_args_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_status",
                    virtual_inst_status_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_phys_reg",
                    virtual_phys_reg_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_regalloc_status",
                    virtual_regalloc_status_buf.as_entire_binding(),
                ),
                ("x86_func_meta", func_meta_buf.as_entire_binding()),
                ("x86_node_func", node_func_buf.as_entire_binding()),
                (
                    "x86_planned_inst_kind",
                    planned_inst_kind_buf.as_entire_binding(),
                ),
                (
                    "x86_planned_inst_arg0",
                    planned_inst_arg0_buf.as_entire_binding(),
                ),
                (
                    "x86_planned_reloc_kind",
                    planned_reloc_kind_buf.as_entire_binding(),
                ),
                (
                    "x86_planned_reloc_site_inst",
                    planned_reloc_site_inst_buf.as_entire_binding(),
                ),
                (
                    "x86_planned_reloc_target_inst",
                    planned_reloc_target_inst_buf.as_entire_binding(),
                ),
                ("plan_status", plan_status_buf.as_entire_binding()),
                ("x86_inst_kind", inst_kind_buf.as_entire_binding()),
                ("x86_inst_arg0", inst_arg0_buf.as_entire_binding()),
                ("x86_inst_arg1", inst_arg1_buf.as_entire_binding()),
                ("x86_inst_arg2", inst_arg2_buf.as_entire_binding()),
                ("x86_reloc_count", reloc_count_buf.as_entire_binding()),
                ("x86_reloc_kind", reloc_kind_buf.as_entire_binding()),
                (
                    "x86_reloc_site_inst",
                    reloc_site_inst_buf.as_entire_binding(),
                ),
                (
                    "x86_reloc_target_inst",
                    reloc_target_inst_buf.as_entire_binding(),
                ),
                ("select_status", select_status_buf.as_entire_binding()),
            ],
        )?;
        let inst_size_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.inst_size.bind_group"),
            &self.inst_size_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("x86_inst_kind", inst_kind_buf.as_entire_binding()),
                ("x86_inst_arg0", inst_arg0_buf.as_entire_binding()),
                ("x86_inst_arg1", inst_arg1_buf.as_entire_binding()),
                ("x86_inst_arg2", inst_arg2_buf.as_entire_binding()),
                ("select_status", select_status_buf.as_entire_binding()),
                ("x86_inst_size", inst_size_buf.as_entire_binding()),
                ("size_status", size_status_buf.as_entire_binding()),
            ],
        )?;
        let text_offsets_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.text_offsets.bind_group"),
            &self.text_offsets_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("x86_inst_size", inst_size_buf.as_entire_binding()),
                ("size_status", size_status_buf.as_entire_binding()),
                (
                    "x86_inst_byte_offset",
                    inst_byte_offset_buf.as_entire_binding(),
                ),
                ("x86_text_len", text_len_buf.as_entire_binding()),
                ("text_status", text_status_buf.as_entire_binding()),
            ],
        )?;
        let encode_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.encode.bind_group"),
            &self.encode_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("x86_inst_kind", inst_kind_buf.as_entire_binding()),
                ("x86_inst_arg0", inst_arg0_buf.as_entire_binding()),
                ("x86_inst_arg1", inst_arg1_buf.as_entire_binding()),
                ("x86_inst_arg2", inst_arg2_buf.as_entire_binding()),
                ("x86_inst_size", inst_size_buf.as_entire_binding()),
                (
                    "x86_inst_byte_offset",
                    inst_byte_offset_buf.as_entire_binding(),
                ),
                ("x86_text_len", text_len_buf.as_entire_binding()),
                ("text_status", text_status_buf.as_entire_binding()),
                ("x86_text_words", text_words_buf.as_entire_binding()),
                ("encode_status", encode_status_buf.as_entire_binding()),
            ],
        )?;
        let reloc_patch_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.reloc_patch.bind_group"),
            &self.reloc_patch_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("x86_inst_kind", inst_kind_buf.as_entire_binding()),
                ("x86_inst_size", inst_size_buf.as_entire_binding()),
                (
                    "x86_inst_byte_offset",
                    inst_byte_offset_buf.as_entire_binding(),
                ),
                ("x86_text_len", text_len_buf.as_entire_binding()),
                ("text_status", text_status_buf.as_entire_binding()),
                ("encode_status", encode_status_buf.as_entire_binding()),
                ("x86_reloc_count", reloc_count_buf.as_entire_binding()),
                ("x86_reloc_kind", reloc_kind_buf.as_entire_binding()),
                (
                    "x86_reloc_site_inst",
                    reloc_site_inst_buf.as_entire_binding(),
                ),
                (
                    "x86_reloc_target_inst",
                    reloc_target_inst_buf.as_entire_binding(),
                ),
                ("x86_text_words", text_words_buf.as_entire_binding()),
                ("reloc_status", reloc_status_buf.as_entire_binding()),
            ],
        )?;
        let elf_layout_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.elf_layout.bind_group"),
            &self.elf_layout_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("x86_text_len", text_len_buf.as_entire_binding()),
                ("encode_status", reloc_status_buf.as_entire_binding()),
                ("x86_elf_layout", elf_layout_buf.as_entire_binding()),
                ("layout_status", layout_status_buf.as_entire_binding()),
            ],
        )?;
        let elf_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.elf_write.bind_group"),
            &self.elf_write_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("x86_text_words", text_words_buf.as_entire_binding()),
                ("x86_elf_layout", elf_layout_buf.as_entire_binding()),
                ("layout_status", layout_status_buf.as_entire_binding()),
                ("out_words", out_buf.as_entire_binding()),
                ("status", status_buf.as_entire_binding()),
            ],
        )?;

        let hir_groups = n_hir_nodes.div_ceil(256).max(1);
        let (hir_groups_x, hir_groups_y) = workgroup_grid_1d(hir_groups);
        let hir_grid = (hir_groups_x, hir_groups_y);
        dispatch_x86_stages(
            encoder,
            &[
                (
                    "node_tree_info",
                    &self.node_tree_info_pass,
                    &node_tree_info_bind_group,
                ),
                ("func_discover", &self.func_discover_pass, &func_bind_group),
                (
                    "call_records",
                    &self.call_records_pass,
                    &call_records_bind_group,
                ),
                (
                    "const_values",
                    &self.const_values_pass,
                    &const_values_bind_group,
                ),
                ("param_regs", &self.param_regs_pass, &param_regs_bind_group),
                (
                    "local_literals",
                    &self.local_literals_pass,
                    &local_literals_bind_group,
                ),
                (
                    "func_return_stmts",
                    &self.func_return_stmts_pass,
                    &func_return_stmts_bind_group,
                ),
                (
                    "block_return_stmts",
                    &self.block_return_stmts_pass,
                    &block_return_stmts_bind_group,
                ),
                (
                    "return_calls",
                    &self.return_calls_pass,
                    &return_calls_bind_group,
                ),
                (
                    "terminal_ifs",
                    &self.terminal_ifs_pass,
                    &terminal_ifs_bind_group,
                ),
            ],
            hir_grid,
        );
        encoder.copy_buffer_to_buffer(&func_meta_buf, 0, &func_meta_uniform_buf, 0, 32);
        encoder.copy_buffer_to_buffer(
            &const_value_status_buf,
            0,
            &const_value_status_uniform_buf,
            0,
            16,
        );
        encoder.copy_buffer_to_buffer(
            &param_reg_status_buf,
            0,
            &param_reg_status_uniform_buf,
            0,
            16,
        );
        encoder.copy_buffer_to_buffer(
            &local_literal_status_buf,
            0,
            &local_literal_status_uniform_buf,
            0,
            16,
        );
        encoder.copy_buffer_to_buffer(
            &func_return_stmt_status_buf,
            0,
            &func_return_stmt_status_uniform_buf,
            0,
            16,
        );
        encoder.copy_buffer_to_buffer(
            &terminal_if_status_buf,
            0,
            &terminal_if_status_uniform_buf,
            0,
            16,
        );
        encoder.copy_buffer_to_buffer(
            &return_call_status_buf,
            0,
            &return_call_status_uniform_buf,
            0,
            16,
        );
        dispatch_x86_stages(
            encoder,
            &[
                (
                    "call_arg_values",
                    &self.call_arg_values_pass,
                    &call_arg_values_bind_group,
                ),
                (
                    "call_arg_lookup",
                    &self.call_arg_lookup_pass,
                    &call_arg_lookup_bind_group,
                ),
                (
                    "intrinsic_calls",
                    &self.intrinsic_calls_pass,
                    &intrinsic_calls_bind_group,
                ),
                ("call_abi", &self.call_abi_pass, &call_abi_bind_group),
            ],
            hir_grid,
        );
        encoder.copy_buffer_to_buffer(&call_abi_status_buf, 0, &call_abi_status_uniform_buf, 0, 16);
        dispatch_x86_stages(
            encoder,
            &[
                (
                    "call_arg_widths",
                    &self.call_arg_widths_pass,
                    &call_arg_widths_bind_group,
                ),
                (
                    "call_arg_prefix_seed",
                    &self.call_arg_prefix_seed_pass,
                    &call_arg_prefix_seed_bind_group,
                ),
                (
                    "call_arg_prefix_scan",
                    &self.call_arg_prefix_scan_pass,
                    &call_arg_prefix_scan_bind_group,
                ),
                (
                    "func_body_plan",
                    &self.func_body_plan_pass,
                    &func_body_bind_group,
                ),
                (
                    "call_arg_vregs",
                    &self.call_arg_vregs_pass,
                    &call_arg_vregs_bind_group,
                ),
                (
                    "node_inst_counts",
                    &self.node_inst_counts_pass,
                    &node_inst_counts_bind_group,
                ),
                (
                    "node_inst_order",
                    &self.node_inst_order_pass,
                    &node_inst_order_bind_group,
                ),
            ],
            hir_grid,
        );
        let node_inst_scan_local_grid = workgroup_grid_1d(node_inst_scan_blocks as u32);
        dispatch_x86_stage(
            encoder,
            "node_inst_scan_local",
            &self.node_inst_scan_local_pass,
            &node_inst_scan_local_bind_group,
            node_inst_scan_local_grid,
        );
        let node_inst_scan_block_groups =
            workgroup_grid_1d((node_inst_scan_blocks as u32).div_ceil(256).max(1));
        for (step_i, bind_group) in node_inst_scan_block_bind_groups.iter().enumerate() {
            dispatch_compute_pass(
                encoder,
                &format!("node_inst_scan_blocks.{step_i}"),
                "codegen.x86.node_inst_scan_blocks",
                &self.node_inst_scan_blocks_pass,
                bind_group,
                node_inst_scan_block_groups,
            );
        }
        let node_inst_scan_apply_groups =
            workgroup_grid_1d((node_inst_scan_words as u32).div_ceil(256).max(1));
        dispatch_x86_stage(
            encoder,
            "node_inst_prefix_scan",
            &self.node_inst_prefix_scan_pass,
            &node_inst_prefix_scan_bind_group,
            node_inst_scan_apply_groups,
        );
        dispatch_x86_stage(
            encoder,
            "node_inst_locations",
            &self.node_inst_locations_pass,
            &node_inst_locations_bind_group,
            hir_grid,
        );
        dispatch_x86_stage(
            encoder,
            "node_inst_gen",
            &self.node_inst_gen_pass,
            &node_inst_gen_bind_group,
            hir_grid,
        );
        let virtual_inst_groups = (MAX_X86_INSTS as u32).div_ceil(256).max(1);
        let virtual_inst_grid = workgroup_grid_1d(virtual_inst_groups);
        dispatch_x86_stages(
            encoder,
            &[
                (
                    "virtual_use_edges",
                    &self.virtual_use_edges_pass,
                    &virtual_use_edges_bind_group,
                ),
                (
                    "virtual_liveness",
                    &self.virtual_liveness_pass,
                    &virtual_liveness_bind_group,
                ),
                (
                    "virtual_regalloc",
                    &self.virtual_regalloc_pass,
                    &virtual_regalloc_bind_group,
                ),
            ],
            virtual_inst_grid,
        );

        let lower_groups = hir_groups;
        let (lower_groups_x, lower_groups_y) = workgroup_grid_1d(lower_groups);
        dispatch_x86_stage(
            encoder,
            "lower_values",
            &self.lower_values_pass,
            &lower_bind_group,
            (lower_groups_x, lower_groups_y),
        );

        let use_edge_groups = (MAX_X86_USE_EDGES as u32).div_ceil(256).max(1);
        let (use_edge_groups_x, use_edge_groups_y) = workgroup_grid_1d(use_edge_groups);
        dispatch_x86_stage(
            encoder,
            "use_edges",
            &self.use_edges_pass,
            &use_edges_bind_group,
            (use_edge_groups_x, use_edge_groups_y),
        );

        let vreg_groups = (MAX_X86_VREGS as u32).div_ceil(256).max(1);
        let (vreg_groups_x, vreg_groups_y) = workgroup_grid_1d(vreg_groups);
        let vreg_grid = (vreg_groups_x, vreg_groups_y);
        dispatch_x86_stages(
            encoder,
            &[
                ("liveness", &self.liveness_pass, &liveness_bind_group),
                ("regalloc", &self.regalloc_pass, &regalloc_bind_group),
            ],
            vreg_grid,
        );
        encoder.copy_buffer_to_buffer(&regalloc_status_buf, 0, &regalloc_status_uniform_buf, 0, 16);

        let single_grid = workgroup_grid_1d(1);
        dispatch_x86_stage(
            encoder,
            "func_inst_counts",
            &self.func_inst_counts_pass,
            &func_inst_counts_bind_group,
            single_grid,
        );
        dispatch_x86_stage(
            encoder,
            "func_inst_order",
            &self.func_inst_order_pass,
            &func_inst_order_bind_group,
            hir_grid,
        );
        let func_inst_scan_local_grid = workgroup_grid_1d(func_inst_scan_blocks as u32);
        dispatch_x86_stage(
            encoder,
            "func_inst_scan_local",
            &self.func_inst_scan_local_pass,
            &func_inst_scan_local_bind_group,
            func_inst_scan_local_grid,
        );
        let func_inst_scan_block_groups =
            workgroup_grid_1d((func_inst_scan_blocks as u32).div_ceil(256).max(1));
        for (step_i, bind_group) in func_inst_scan_block_bind_groups.iter().enumerate() {
            dispatch_compute_pass(
                encoder,
                &format!("func_inst_scan_blocks.{step_i}"),
                "codegen.x86.func_inst_scan_blocks",
                &self.func_inst_scan_blocks_pass,
                bind_group,
                func_inst_scan_block_groups,
            );
        }
        let func_inst_scan_apply_groups =
            workgroup_grid_1d((func_inst_scan_words as u32).div_ceil(256).max(1));
        dispatch_x86_stage(
            encoder,
            "func_inst_prefix_scan",
            &self.func_inst_prefix_scan_pass,
            &func_inst_prefix_scan_bind_group,
            func_inst_scan_apply_groups,
        );
        dispatch_x86_stages(
            encoder,
            &[
                (
                    "func_layout",
                    &self.func_layout_pass,
                    &func_layout_bind_group,
                ),
                (
                    "func_return_inst_plan",
                    &self.func_return_inst_plan_pass,
                    &func_return_inst_plan_bind_group,
                ),
            ],
            hir_grid,
        );

        let (plan_groups_x, plan_groups_y) = workgroup_grid_1d(1);
        let plan_grid = (plan_groups_x, plan_groups_y);
        dispatch_x86_stages(
            encoder,
            &[
                (
                    "entry_inst_plan",
                    &self.entry_inst_plan_pass,
                    &entry_inst_plan_bind_group,
                ),
                ("inst_plan", &self.inst_plan_pass, &inst_plan_bind_group),
                ("reloc_plan", &self.reloc_plan_pass, &reloc_plan_bind_group),
            ],
            plan_grid,
        );

        let select_groups = (MAX_X86_INSTS as u32).div_ceil(256).max(1);
        let (select_groups_x, select_groups_y) = workgroup_grid_1d(select_groups);
        dispatch_compute_pass(
            encoder,
            "select",
            "codegen.x86.select",
            &self.select_pass,
            &select_bind_group,
            (select_groups_x, select_groups_y),
        );

        let inst_groups = (MAX_X86_INSTS as u32).div_ceil(256).max(1);
        let (inst_groups_x, inst_groups_y) = workgroup_grid_1d(inst_groups);
        let inst_grid = (inst_groups_x, inst_groups_y);
        dispatch_x86_stages(
            encoder,
            &[
                ("inst_size", &self.inst_size_pass, &inst_size_bind_group),
                (
                    "text_offsets",
                    &self.text_offsets_pass,
                    &text_offsets_bind_group,
                ),
            ],
            inst_grid,
        );

        let text_word_groups = (output_words as u32).div_ceil(256).max(1);
        let (text_word_groups_x, text_word_groups_y) = workgroup_grid_1d(text_word_groups);
        dispatch_x86_stages(
            encoder,
            &[("encode", &self.encode_pass, &encode_bind_group)],
            (text_word_groups_x, text_word_groups_y),
        );

        let reloc_groups = (MAX_X86_RELOCS as u32).div_ceil(256).max(1);
        let (reloc_groups_x, reloc_groups_y) = workgroup_grid_1d(reloc_groups);
        dispatch_x86_stages(
            encoder,
            &[(
                "reloc_patch",
                &self.reloc_patch_pass,
                &reloc_patch_bind_group,
            )],
            (reloc_groups_x, reloc_groups_y),
        );

        let (layout_groups_x, layout_groups_y) = workgroup_grid_1d(1);
        dispatch_x86_stages(
            encoder,
            &[("elf_layout", &self.elf_layout_pass, &elf_layout_bind_group)],
            (layout_groups_x, layout_groups_y),
        );

        let output_groups = (output_words as u32).div_ceil(256).max(1);
        let (output_groups_x, output_groups_y) = workgroup_grid_1d(output_groups);
        dispatch_x86_stages(
            encoder,
            &[("elf_write", &self.elf_write_pass, &elf_bind_group)],
            (output_groups_x, output_groups_y),
        );
        encoder.copy_buffer_to_buffer(&status_buf, 0, &status_readback, 0, 16);
        if let Some(status_trace_readback) = &status_trace_readback {
            let mut offset = 0u64;
            for (buffer, words) in [
                (&lower_status_buf, 4u64),
                (&use_status_buf, 4),
                (&liveness_status_buf, 4),
                (&regalloc_status_buf, 4),
                (&node_inst_count_status_buf, 4),
                (&node_inst_order_status_buf, 4),
                (&node_inst_range_status_buf, 4),
                (&node_inst_location_status_buf, 4),
                (&virtual_inst_status_buf, 4),
                (&virtual_use_status_buf, 4),
                (&virtual_liveness_status_buf, 4),
                (&virtual_regalloc_status_buf, 4),
                (&func_inst_count_status_buf, 9),
                (&func_inst_order_status_buf, 9),
                (&func_inst_range_status_buf, 9),
                (&func_layout_status_buf, 9),
                (&func_return_inst_status_buf, 4),
                (&entry_inst_status_buf, 6),
                (&plan_status_buf, 4),
                (&select_status_buf, 4),
                (&size_status_buf, 4),
                (&text_status_buf, 4),
                (&encode_status_buf, 4),
                (&reloc_status_buf, 4),
                (&layout_status_buf, 4),
                (&status_buf, 4),
            ] {
                encoder.copy_buffer_to_buffer(
                    buffer,
                    0,
                    status_trace_readback,
                    offset * 4,
                    words * 4,
                );
                offset += words;
            }
        }

        Ok(include!("record_retained_expr.rs"))
    }
}
