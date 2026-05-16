{
        write_u32_words(
            queue,
            &func_meta_buf,
            &[0, 0, u32::MAX, 0, u32::MAX, 0, 0, 0],
        );
        write_u32_words(
            queue,
            &func_meta_uniform_buf,
            &[0, 0, u32::MAX, 0, u32::MAX, 0, 0, 0],
        );
        write_repeated_u32_words(queue, &node_tree_record_buf, &[u32::MAX; 4], hir_words);
        write_u32_words(queue, &node_tree_status_buf, &[1, 0, u32::MAX, 0]);
        write_repeated_u32_words(queue, &func_record_buf, &[u32::MAX; 4], hir_words);
        write_repeated_u32_words(queue, &node_func_buf, &[u32::MAX], hir_words);
        write_repeated_u32_words(queue, &func_lookup_key_buf, &[u32::MAX], func_lookup_words);
        write_repeated_u32_words(queue, &func_lookup_node_buf, &[u32::MAX], func_lookup_words);
        write_repeated_u32_words(queue, &call_record_buf, &[u32::MAX; 4], hir_words);
        write_repeated_u32_words(queue, &call_type_record_buf, &[u32::MAX; 4], hir_words);
        write_u32_words(queue, &call_record_status_buf, &[0, 0, u32::MAX, 0]);
        write_repeated_u32_words(
            queue,
            &const_value_record_buf,
            &[u32::MAX; 4],
            func_lookup_words,
        );
        write_u32_words(queue, &const_value_status_buf, &[1, 0, u32::MAX, 0]);
        write_repeated_u32_words(queue, &param_reg_record_buf, &[u32::MAX; 4], token_words);
        write_u32_words(queue, &param_reg_status_buf, &[1, 0, u32::MAX, 0]);
        write_repeated_u32_words(
            queue,
            &local_literal_record_buf,
            &[u32::MAX; 4],
            token_words,
        );
        write_u32_words(queue, &local_literal_status_buf, &[1, 0, u32::MAX, 0]);
        write_u32_words(
            queue,
            &local_literal_status_uniform_buf,
            &[1, 0, u32::MAX, 0],
        );
        write_repeated_u32_words(
            queue,
            &func_return_stmt_record_buf,
            &[u32::MAX; 4],
            hir_words,
        );
        write_repeated_u32_words(queue, &func_return_stmt_count_buf, &[0], hir_words);
        write_u32_words(queue, &func_return_stmt_status_buf, &[1, 0, u32::MAX, 0]);
        write_u32_words(
            queue,
            &func_return_stmt_status_uniform_buf,
            &[1, 0, u32::MAX, 0],
        );
        write_repeated_u32_words(
            queue,
            &block_return_stmt_record_buf,
            &[u32::MAX; 4],
            hir_words,
        );
        write_repeated_u32_words(queue, &block_return_stmt_count_buf, &[0], hir_words);
        write_u32_words(queue, &block_return_stmt_status_buf, &[1, 0, u32::MAX, 0]);
        write_repeated_u32_words(
            queue,
            &terminal_if_record_buf,
            &[u32::MAX; 4],
            hir_words,
        );
        write_repeated_u32_words(queue, &terminal_if_count_buf, &[0], hir_words);
        write_u32_words(queue, &terminal_if_status_buf, &[1, 0, u32::MAX, 0]);
        write_u32_words(
            queue,
            &terminal_if_status_uniform_buf,
            &[1, 0, u32::MAX, 0],
        );
        write_repeated_u32_words(
            queue,
            &return_call_record_buf,
            &[u32::MAX; 4],
            hir_words,
        );
        write_repeated_u32_words(queue, &return_call_count_buf, &[0], hir_words);
        write_u32_words(queue, &return_call_status_buf, &[1, 0, u32::MAX, 0]);
        write_u32_words(
            queue,
            &return_call_status_uniform_buf,
            &[1, 0, u32::MAX, 0],
        );
        write_repeated_u32_words(queue, &call_arg_value_record_buf, &[u32::MAX; 4], hir_words);
        write_repeated_u32_words(queue, &call_arg_eval_record_buf, &[u32::MAX; 4], hir_words);
        write_u32_words(queue, &call_arg_value_status_buf, &[1, 0, u32::MAX, 0]);
        write_repeated_u32_words(
            queue,
            &call_arg_lookup_record_buf,
            &[u32::MAX; 4],
            hir_words * 6,
        );
        write_u32_words(queue, &call_arg_lookup_status_buf, &[1, 0, u32::MAX, 0]);
        write_repeated_u32_words(
            queue,
            &intrinsic_call_record_buf,
            &[u32::MAX; 4],
            hir_words,
        );
        write_u32_words(queue, &intrinsic_call_status_buf, &[1, 0, u32::MAX, 0]);
        write_repeated_u32_words(queue, &call_abi_record_buf, &[u32::MAX; 4], hir_words * 2);
        write_repeated_u32_words(queue, &call_arg_abi_record_buf, &[u32::MAX; 4], hir_words);
        write_repeated_u32_words(queue, &call_abi_flags_buf, &[0], hir_words);
        write_u32_words(queue, &call_abi_status_buf, &[1, 0, u32::MAX, 0]);
        write_repeated_u32_words(queue, &call_arg_width_record_buf, &[u32::MAX; 4], hir_words);
        write_u32_words(queue, &call_arg_width_status_buf, &[1, 0, u32::MAX, 0]);
        write_repeated_u32_words(
            queue,
            &call_arg_width_slot_record_buf,
            &[u32::MAX; 4],
            hir_words * 6,
        );
        write_u32_words(
            queue,
            &call_arg_prefix_seed_status_buf,
            &[1, 0, u32::MAX, 0],
        );
        write_repeated_u32_words(
            queue,
            &call_arg_prefix_record_buf,
            &[u32::MAX; 4],
            hir_words,
        );
        write_repeated_u32_words(
            queue,
            &call_arg_total_width_record_buf,
            &[u32::MAX; 4],
            hir_words,
        );
        write_u32_words(queue, &call_arg_prefix_status_buf, &[1, 0, u32::MAX, 0]);
        write_repeated_u32_words(queue, &call_arg_range_record_buf, &[u32::MAX; 4], hir_words);
        write_repeated_u32_words(
            queue,
            &call_vreg_summary_record_buf,
            &[u32::MAX; 4],
            hir_words,
        );
        write_repeated_u32_words(
            queue,
            &call_vreg_count_record_buf,
            &[u32::MAX; 4],
            hir_words,
        );
        write_u32_words(queue, &call_arg_vreg_status_buf, &[1, 0, u32::MAX, 0]);
        write_repeated_u32_words(
            queue,
            &node_inst_count_record_buf,
            &[u32::MAX; 4],
            hir_words,
        );
        write_repeated_u32_words(
            queue,
            &node_inst_order_record_buf,
            &[u32::MAX, 0, 0, u32::MAX],
            hir_words,
        );
        write_repeated_u32_words(queue, &node_inst_order_node_buf, &[u32::MAX], hir_words);
        write_repeated_u32_words(queue, &node_inst_order_slot_buf, &[u32::MAX], hir_words);
        write_repeated_u32_words(
            queue,
            &node_inst_scan_input_buf,
            &[0],
            node_inst_scan_words,
        );
        write_u32_words(queue, &node_inst_count_status_buf, &[1, 0, u32::MAX, 0]);
        write_u32_words(queue, &node_inst_order_status_buf, &[0, 0, u32::MAX, 0]);
        write_repeated_u32_words(
            queue,
            &node_inst_scan_local_prefix_buf,
            &[0],
            node_inst_scan_words,
        );
        write_repeated_u32_words(
            queue,
            &node_inst_scan_block_sum_buf,
            &[0],
            node_inst_scan_blocks,
        );
        write_repeated_u32_words(
            queue,
            &node_inst_scan_prefix_a_buf,
            &[0],
            node_inst_scan_blocks,
        );
        write_repeated_u32_words(
            queue,
            &node_inst_scan_prefix_b_buf,
            &[0],
            node_inst_scan_blocks,
        );
        write_repeated_u32_words(
            queue,
            &node_inst_range_record_buf,
            &[u32::MAX; 4],
            hir_words,
        );
        write_u32_words(queue, &node_inst_range_status_buf, &[0, 0, u32::MAX, 0]);
        write_repeated_u32_words(
            queue,
            &node_inst_location_record_buf,
            &[u32::MAX; 4],
            hir_words,
        );
        write_u32_words(
            queue,
            &node_inst_location_status_buf,
            &[0, 0, u32::MAX, 0],
        );
        write_repeated_u32_words(queue, &node_value_record_buf, &[u32::MAX; 4], hir_words);
        write_repeated_u32_words(
            queue,
            &virtual_inst_record_buf,
            &[u32::MAX; 4],
            MAX_X86_INSTS,
        );
        write_repeated_u32_words(
            queue,
            &virtual_inst_args_buf,
            &[u32::MAX; 4],
            MAX_X86_INSTS,
        );
        write_u32_words(queue, &virtual_inst_status_buf, &[0, 0, u32::MAX, 0]);
        write_u32_words(
            queue,
            &virtual_use_key_buf,
            &[u32::MAX; MAX_X86_VIRTUAL_USE_EDGES],
        );
        write_u32_words(
            queue,
            &virtual_use_value_buf,
            &[u32::MAX; MAX_X86_VIRTUAL_USE_EDGES],
        );
        write_u32_words(queue, &virtual_vreg_use_count_buf, &[0; MAX_X86_INSTS]);
        write_u32_words(queue, &virtual_use_status_buf, &[0, 0, u32::MAX, 0]);
        write_u32_words(queue, &virtual_live_start_buf, &[u32::MAX; MAX_X86_INSTS]);
        write_u32_words(queue, &virtual_live_end_buf, &[u32::MAX; MAX_X86_INSTS]);
        write_u32_words(queue, &virtual_liveness_status_buf, &[0, 0, u32::MAX, 0]);
        write_u32_words(queue, &virtual_phys_reg_buf, &[u32::MAX; MAX_X86_INSTS]);
        write_u32_words(queue, &virtual_regalloc_status_buf, &[0, 0, u32::MAX, 0]);
        write_u32_words(queue, &func_body_status_buf, &[1, 0, u32::MAX, 0]);
        write_u32_words(queue, &vreg_kind_buf, &[0; MAX_X86_VREGS]);
        write_u32_words(queue, &vreg_value_buf, &[0; MAX_X86_VREGS]);
        write_u32_words(queue, &vreg_args_buf, &[u32::MAX; MAX_X86_VREGS * 4]);
        write_u32_words(queue, &vreg_op_buf, &[0; MAX_X86_VREGS]);
        write_repeated_u32_words(queue, &expr_vreg_buf, &[u32::MAX], hir_words);
        write_u32_words(queue, &return_vreg_buf, &[u32::MAX]);
        write_u32_words(queue, &lower_status_buf, &[0, 0, u32::MAX, 0]);
        write_u32_words(queue, &use_key_buf, &[u32::MAX; MAX_X86_USE_EDGES]);
        write_u32_words(queue, &use_value_buf, &[u32::MAX; MAX_X86_USE_EDGES]);
        write_u32_words(queue, &vreg_use_count_buf, &[0; MAX_X86_VREGS]);
        write_u32_words(queue, &use_status_buf, &[0, 0, u32::MAX, 0]);
        write_u32_words(queue, &live_start_buf, &[u32::MAX; MAX_X86_VREGS]);
        write_u32_words(queue, &live_end_buf, &[u32::MAX; MAX_X86_VREGS]);
        write_u32_words(queue, &liveness_status_buf, &[0, 0, u32::MAX, 0]);
        write_u32_words(queue, &phys_reg_buf, &[u32::MAX; MAX_X86_VREGS]);
        write_u32_words(queue, &regalloc_status_buf, &[0, 0, u32::MAX, 0]);
        write_u32_words(
            queue,
            &regalloc_status_uniform_buf,
            &[0, 0, u32::MAX, 0],
        );
        write_repeated_u32_words(
            queue,
            &func_inst_count_record_buf,
            &[u32::MAX; 4],
            hir_words,
        );
        write_u32_words(
            queue,
            &func_inst_count_status_buf,
            &[0, 0, u32::MAX, 0, u32::MAX, u32::MAX, 0, u32::MAX, 0],
        );
        write_repeated_u32_words(
            queue,
            &func_inst_order_record_buf,
            &[u32::MAX, 0, 0, u32::MAX],
            func_inst_scan_words,
        );
        write_repeated_u32_words(queue, &func_inst_order_slot_buf, &[u32::MAX], hir_words);
        write_repeated_u32_words(queue, &func_inst_scan_input_buf, &[0], func_inst_scan_words);
        write_u32_words(
            queue,
            &func_inst_order_status_buf,
            &[0, 0, u32::MAX, 0, u32::MAX, u32::MAX, 0, u32::MAX, 0],
        );
        write_repeated_u32_words(
            queue,
            &func_inst_scan_local_prefix_buf,
            &[0],
            func_inst_scan_words,
        );
        write_repeated_u32_words(
            queue,
            &func_inst_scan_block_sum_buf,
            &[0],
            func_inst_scan_blocks,
        );
        write_repeated_u32_words(
            queue,
            &func_inst_scan_prefix_a_buf,
            &[0],
            func_inst_scan_blocks,
        );
        write_repeated_u32_words(
            queue,
            &func_inst_scan_prefix_b_buf,
            &[0],
            func_inst_scan_blocks,
        );
        write_repeated_u32_words(
            queue,
            &func_inst_range_record_buf,
            &[u32::MAX; 4],
            hir_words,
        );
        write_u32_words(
            queue,
            &func_inst_range_status_buf,
            &[0, 0, u32::MAX, 0, u32::MAX, u32::MAX, 0, u32::MAX, 0],
        );
        write_repeated_u32_words(queue, &func_layout_record_buf, &[u32::MAX; 4], hir_words);
        write_u32_words(
            queue,
            &func_layout_status_buf,
            &[0, 0, u32::MAX, 0, u32::MAX, u32::MAX, 0, u32::MAX, 0],
        );
        write_u32_words(queue, &func_return_inst_status_buf, &[0, 0, u32::MAX, 0]);
        write_u32_words(
            queue,
            &entry_inst_status_buf,
            &[0, 0, u32::MAX, 0, u32::MAX, 0],
        );
        write_u32_words(queue, &select_plan_buf, &[0, 0, 0, u32::MAX]);
        write_u32_words(queue, &planned_inst_kind_buf, &[0; MAX_X86_INSTS]);
        write_u32_words(queue, &planned_inst_arg0_buf, &[0; MAX_X86_INSTS]);
        write_u32_words(queue, &planned_reloc_kind_buf, &[0; MAX_X86_RELOCS]);
        write_u32_words(
            queue,
            &planned_reloc_site_inst_buf,
            &[u32::MAX; MAX_X86_RELOCS],
        );
        write_u32_words(
            queue,
            &planned_reloc_target_inst_buf,
            &[u32::MAX; MAX_X86_RELOCS],
        );
        write_u32_words(queue, &plan_status_buf, &[0, 0, u32::MAX, 0]);
        write_u32_words(queue, &inst_kind_buf, &[0; MAX_X86_INSTS]);
        write_u32_words(queue, &inst_arg0_buf, &[0; MAX_X86_INSTS]);
        write_u32_words(queue, &inst_arg1_buf, &[0; MAX_X86_INSTS]);
        write_u32_words(queue, &inst_arg2_buf, &[0; MAX_X86_INSTS]);
        write_u32_words(queue, &reloc_count_buf, &[0]);
        write_u32_words(queue, &reloc_kind_buf, &[0; MAX_X86_RELOCS]);
        write_u32_words(queue, &reloc_site_inst_buf, &[u32::MAX; MAX_X86_RELOCS]);
        write_u32_words(queue, &reloc_target_inst_buf, &[u32::MAX; MAX_X86_RELOCS]);
        queue.write_buffer(&select_status_buf, 0, &[0u8; 16]);
        write_u32_words(queue, &inst_size_buf, &[0; MAX_X86_INSTS]);
        write_u32_words(queue, &size_status_buf, &[1, 0, u32::MAX, 0]);
        write_u32_words(queue, &inst_byte_offset_buf, &[0; MAX_X86_INSTS]);
        write_u32_words(queue, &text_len_buf, &[0]);
        write_u32_words(queue, &text_status_buf, &[0, 0, u32::MAX, 0]);
        write_u32_words(queue, &encode_status_buf, &[0, 0, u32::MAX, 0]);
        write_u32_words(queue, &reloc_status_buf, &[0, 0, u32::MAX, 0]);
        queue.write_buffer(&elf_layout_buf, 0, &[0u8; 32]);
        write_u32_words(queue, &layout_status_buf, &[0, 0, u32::MAX, 0]);
        queue.write_buffer(&status_buf, 0, &[0u8; 16]);
}
