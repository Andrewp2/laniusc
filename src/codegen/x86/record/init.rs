use anyhow::Result;

use super::super::{
    X86FeatureSummary,
    support::{init_repeated_u32_words, write_u32_words, zero_u32_words},
};
use crate::gpu::passes_core::PassData;

pub(super) struct InitializerInputs<'a> {
    pub device: &'a wgpu::Device,
    pub queue: &'a wgpu::Queue,
    pub encoder: &'a mut wgpu::CommandEncoder,
    pub fill_u32_pass: &'a PassData,
    pub feature_summary: X86FeatureSummary,
    pub token_words: usize,
    pub hir_words: usize,
    pub enum_value_record_rows: usize,
    pub match_record_rows: usize,
    pub aggregate_record_rows: usize,
    pub decl_layout_words: usize,
    pub function_slot_capacity: usize,
    pub param_reg_record_words: usize,
    pub node_inst_order_rows: usize,
    pub func_meta_buf: &'a wgpu::Buffer,
    pub func_meta_uniform_buf: &'a wgpu::Buffer,
    pub node_tree_status_buf: &'a wgpu::Buffer,
    pub enum_type_record_buf: &'a wgpu::Buffer,
    pub enum_value_record_buf: &'a wgpu::Buffer,
    pub enum_record_status_buf: &'a wgpu::Buffer,
    pub match_arm_owner_buf: &'a wgpu::Buffer,
    pub match_return_node_buf: &'a wgpu::Buffer,
    pub match_pattern_owner_buf: &'a wgpu::Buffer,
    pub match_result_value_owner_buf: &'a wgpu::Buffer,
    pub match_pattern_node_owner_buf: &'a wgpu::Buffer,
    pub match_pattern_node_variant_buf: &'a wgpu::Buffer,
    pub match_pattern_node_payload_decl_buf: &'a wgpu::Buffer,
    pub match_pattern_first_variant_node_buf: &'a wgpu::Buffer,
    pub match_pattern_first_payload_node_buf: &'a wgpu::Buffer,
    pub struct_type_record_buf: &'a wgpu::Buffer,
    pub struct_access_record_buf: &'a wgpu::Buffer,
    pub struct_store_record_buf: &'a wgpu::Buffer,
    pub struct_record_status_buf: &'a wgpu::Buffer,
    pub decl_layout_record_buf: &'a wgpu::Buffer,
    pub decl_layout_status_buf: &'a wgpu::Buffer,
    pub decl_node_by_token_buf: &'a wgpu::Buffer,
    pub func_slot_by_index_buf: &'a wgpu::Buffer,
    pub func_slot_by_node_buf: &'a wgpu::Buffer,
    pub call_record_buf: &'a wgpu::Buffer,
    pub call_type_record_buf: &'a wgpu::Buffer,
    pub call_record_status_buf: &'a wgpu::Buffer,
    pub const_value_record_buf: &'a wgpu::Buffer,
    pub const_value_status_buf: &'a wgpu::Buffer,
    pub param_reg_record_buf: &'a wgpu::Buffer,
    pub param_reg_status_buf: &'a wgpu::Buffer,
    pub local_literal_record_buf: &'a wgpu::Buffer,
    pub local_literal_status_buf: &'a wgpu::Buffer,
    pub local_literal_status_uniform_buf: &'a wgpu::Buffer,
    pub node_inst_order_record_buf: &'a wgpu::Buffer,
    pub call_arg_lookup_record_buf: &'a wgpu::Buffer,
    pub intrinsic_call_status_buf: &'a wgpu::Buffer,
    pub call_abi_record_buf: &'a wgpu::Buffer,
    pub call_abi_status_buf: &'a wgpu::Buffer,
    pub for_iterable_node_buf: &'a wgpu::Buffer,
    pub node_control_padding_buf: &'a wgpu::Buffer,
    pub postfix_operand_owner_buf: &'a wgpu::Buffer,
    pub node_inst_count_status_buf: &'a wgpu::Buffer,
    pub node_inst_order_status_buf: &'a wgpu::Buffer,
    pub node_inst_range_start_buf: &'a wgpu::Buffer,
    pub node_inst_range_info_buf: &'a wgpu::Buffer,
    pub node_inst_range_status_buf: &'a wgpu::Buffer,
    pub node_inst_subtree_bounds_status_buf: &'a wgpu::Buffer,
    pub node_inst_location_record_buf: &'a wgpu::Buffer,
    pub node_inst_location_status_buf: &'a wgpu::Buffer,
    pub node_inst_gen_input_status_buf: &'a wgpu::Buffer,
    pub virtual_inst_status_buf: &'a wgpu::Buffer,
    pub virtual_func_first_row_status_buf: &'a wgpu::Buffer,
    pub virtual_liveness_status_buf: &'a wgpu::Buffer,
    pub virtual_next_call_status_buf: &'a wgpu::Buffer,
    pub func_param_reg_mask_status_buf: &'a wgpu::Buffer,
    pub virtual_regalloc_status_buf: &'a wgpu::Buffer,
    pub select_status_buf: &'a wgpu::Buffer,
    pub size_status_buf: &'a wgpu::Buffer,
    pub text_len_buf: &'a wgpu::Buffer,
    pub text_status_buf: &'a wgpu::Buffer,
    pub encode_status_buf: &'a wgpu::Buffer,
    pub elf_layout_buf: &'a wgpu::Buffer,
    pub layout_status_buf: &'a wgpu::Buffer,
    pub status_buf: &'a wgpu::Buffer,
}

pub(super) fn record_initializers(inputs: InitializerInputs<'_>) -> Result<()> {
    let InitializerInputs {
        device,
        queue,
        encoder,
        fill_u32_pass,
        feature_summary,
        token_words,
        hir_words,
        enum_value_record_rows,
        match_record_rows,
        aggregate_record_rows,
        decl_layout_words,
        function_slot_capacity,
        param_reg_record_words,
        node_inst_order_rows,
        func_meta_buf,
        func_meta_uniform_buf,
        node_tree_status_buf,
        enum_type_record_buf,
        enum_value_record_buf,
        enum_record_status_buf,
        match_arm_owner_buf,
        match_return_node_buf,
        match_pattern_owner_buf,
        match_result_value_owner_buf,
        match_pattern_node_owner_buf,
        match_pattern_node_variant_buf,
        match_pattern_node_payload_decl_buf,
        match_pattern_first_variant_node_buf,
        match_pattern_first_payload_node_buf,
        struct_type_record_buf,
        struct_access_record_buf,
        struct_store_record_buf,
        struct_record_status_buf,
        decl_layout_record_buf,
        decl_layout_status_buf,
        decl_node_by_token_buf,
        func_slot_by_index_buf,
        func_slot_by_node_buf,
        call_record_buf,
        call_type_record_buf,
        call_record_status_buf,
        const_value_record_buf,
        const_value_status_buf,
        param_reg_record_buf,
        param_reg_status_buf,
        local_literal_record_buf,
        local_literal_status_buf,
        local_literal_status_uniform_buf,
        node_inst_order_record_buf,
        call_arg_lookup_record_buf,
        intrinsic_call_status_buf,
        call_abi_record_buf,
        call_abi_status_buf,
        for_iterable_node_buf,
        node_control_padding_buf,
        postfix_operand_owner_buf,
        node_inst_count_status_buf,
        node_inst_order_status_buf,
        node_inst_range_start_buf,
        node_inst_range_info_buf,
        node_inst_range_status_buf,
        node_inst_subtree_bounds_status_buf,
        node_inst_location_record_buf,
        node_inst_location_status_buf,
        node_inst_gen_input_status_buf,
        virtual_inst_status_buf,
        virtual_func_first_row_status_buf,
        virtual_liveness_status_buf,
        virtual_next_call_status_buf,
        func_param_reg_mask_status_buf,
        virtual_regalloc_status_buf,
        select_status_buf,
        size_status_buf,
        text_len_buf,
        text_status_buf,
        encode_status_buf,
        elf_layout_buf,
        layout_status_buf,
        status_buf,
    } = inputs;

    macro_rules! init_repeated {
        ($label:literal, $buffer:expr, $pattern:expr, $repeats:expr $(,)?) => {
            init_repeated_u32_words(
                device,
                queue,
                encoder,
                fill_u32_pass,
                $label,
                $buffer,
                $pattern,
                $repeats,
            )?
        };
    }

    write_u32_words(
        queue,
        func_meta_buf,
        &[0, 0, u32::MAX, 0, u32::MAX, 0, 0, 0],
    );
    write_u32_words(
        queue,
        func_meta_uniform_buf,
        &[0, 0, u32::MAX, 0, u32::MAX, 0, 0, 0],
    );
    // x86_node_tree_info validates every active HIR tree row before later
    // backend passes consume the parser parent/subtree records directly.
    write_u32_words(queue, node_tree_status_buf, &[1, 0, u32::MAX, 0]);
    // Owning-function seed/step passes overwrite active owner/link rows before
    // later backend passes consume x86_node_func.
    zero_u32_words(queue, encoder, enum_type_record_buf, token_words);
    init_repeated!(
        "enum_value_record",
        enum_value_record_buf,
        &[u32::MAX; 2],
        enum_value_record_rows,
    );
    write_u32_words(queue, enum_record_status_buf, &[0, 0, u32::MAX, 0]);
    // x86_match_records writes default rows only when match HIR records exist,
    // then fills match-expression and match-arm rows with metadata.
    init_repeated!(
        "match_arm_owner",
        match_arm_owner_buf,
        &[u32::MAX],
        match_record_rows
    );
    init_repeated!(
        "match_return_node",
        match_return_node_buf,
        &[u32::MAX],
        match_record_rows,
    );
    init_repeated!(
        "match_pattern_owner",
        match_pattern_owner_buf,
        &[u32::MAX],
        hir_words
    );
    init_repeated!(
        "match_result_value_owner",
        match_result_value_owner_buf,
        &[u32::MAX],
        match_record_rows,
    );
    init_repeated!(
        "match_pattern_node_owner",
        match_pattern_node_owner_buf,
        &[u32::MAX],
        hir_words,
    );
    init_repeated!(
        "match_pattern_node_variant",
        match_pattern_node_variant_buf,
        &[u32::MAX],
        hir_words,
    );
    init_repeated!(
        "match_pattern_node_payload_decl",
        match_pattern_node_payload_decl_buf,
        &[u32::MAX],
        match_record_rows,
    );
    // Match-result owner seed/step passes overwrite active rows in their
    // ping-pong owner/link scratch before later consumers read them.
    init_repeated!(
        "match_pattern_first_variant_node",
        match_pattern_first_variant_node_buf,
        &[u32::MAX],
        hir_words,
    );
    init_repeated!(
        "match_pattern_first_payload_node",
        match_pattern_first_payload_node_buf,
        &[u32::MAX],
        hir_words,
    );
    zero_u32_words(queue, encoder, struct_type_record_buf, token_words);
    init_repeated!(
        "struct_access_record",
        struct_access_record_buf,
        &[u32::MAX; 3],
        aggregate_record_rows,
    );
    init_repeated!(
        "struct_store_record",
        struct_store_record_buf,
        &[u32::MAX; 4],
        aggregate_record_rows,
    );
    write_u32_words(queue, struct_record_status_buf, &[0, 0, u32::MAX, 0]);
    init_repeated!(
        "decl_layout_record",
        decl_layout_record_buf,
        &[u32::MAX; 4],
        decl_layout_words,
    );
    write_u32_words(queue, decl_layout_status_buf, &[0, 0, u32::MAX, 0]);
    init_repeated!(
        "decl_node_by_token",
        decl_node_by_token_buf,
        &[u32::MAX],
        token_words
    );
    init_repeated!(
        "func_slot_by_index",
        func_slot_by_index_buf,
        &[u32::MAX],
        function_slot_capacity,
    );
    init_repeated!(
        "func_slot_by_node",
        func_slot_by_node_buf,
        &[u32::MAX],
        hir_words
    );
    init_repeated!("call_record", call_record_buf, &[u32::MAX; 4], hir_words);
    if feature_summary.has_call() {
        init_repeated!(
            "call_type_record",
            call_type_record_buf,
            &[u32::MAX; 3],
            hir_words
        );
    }
    write_u32_words(queue, call_record_status_buf, &[0, 0, u32::MAX, 0]);
    init_repeated!(
        "const_value_record",
        const_value_record_buf,
        &[u32::MAX; 2],
        token_words,
    );
    write_u32_words(queue, const_value_status_buf, &[1, 0, u32::MAX, 0]);
    init_repeated!(
        "param_reg_record",
        param_reg_record_buf,
        &[u32::MAX],
        param_reg_record_words,
    );
    write_u32_words(queue, param_reg_status_buf, &[1, 0, u32::MAX, 0]);
    init_repeated!(
        "local_literal_record",
        local_literal_record_buf,
        &[u32::MAX; 3],
        token_words,
    );
    write_u32_words(queue, local_literal_status_buf, &[1, 0, u32::MAX, 0]);
    write_u32_words(
        queue,
        local_literal_status_uniform_buf,
        &[1, 0, u32::MAX, 0],
    );
    init_repeated!(
        "node_inst_order_record",
        node_inst_order_record_buf,
        &[u32::MAX; 3],
        node_inst_order_rows,
    );
    init_repeated!(
        "call_arg_lookup_record",
        call_arg_lookup_record_buf,
        &[u32::MAX],
        token_words * 4,
    );
    write_u32_words(queue, intrinsic_call_status_buf, &[1, 0, u32::MAX, 0]);
    init_repeated!(
        "call_abi_record",
        call_abi_record_buf,
        &[u32::MAX; 2],
        token_words,
    );
    write_u32_words(queue, call_abi_status_buf, &[1, 0, u32::MAX, 0]);
    init_repeated!(
        "for_iterable_node",
        for_iterable_node_buf,
        &[u32::MAX],
        hir_words,
    );
    init_repeated!(
        "node_control_padding",
        node_control_padding_buf,
        &[0],
        hir_words,
    );
    init_repeated!(
        "postfix_operand_owner",
        postfix_operand_owner_buf,
        &[u32::MAX],
        hir_words,
    );
    // x86_node_inst_counts overwrites every active HIR node row before the count
    // records are consumed. Later passes only read active nodes or compact order
    // rows derived from those active records. Same-end rank seed/step passes
    // overwrite active link/rank scratch; node_inst_order overwrites active
    // bucket counts before consumers read them.
    init_repeated!(
        "node_inst_order_record",
        node_inst_order_record_buf,
        &[u32::MAX, 0, u32::MAX],
        node_inst_order_rows,
    );
    // node_inst_subtree_slot_bounds reuses call_record storage, which has
    // already been initialized to the same INVALID pattern. node_inst_order
    // overwrites every active node row before subtree_bounds reads it.
    write_u32_words(queue, node_inst_count_status_buf, &[1, 0, u32::MAX, 0]);
    write_u32_words(queue, node_inst_order_status_buf, &[0, 0, u32::MAX, 0]);
    // Node scan local/block passes overwrite the active local-prefix, block-sum,
    // and ping-pong prefix rows before consumers read them.
    init_repeated!(
        "node_inst_range_start",
        node_inst_range_start_buf,
        &[u32::MAX],
        hir_words,
    );
    init_repeated!(
        "node_inst_range_info",
        node_inst_range_info_buf,
        &[u32::MAX],
        hir_words,
    );
    write_u32_words(queue, node_inst_range_status_buf, &[0, 0, u32::MAX, 0]);
    // Final subtree bounds reuse node_inst_order_record after the prefix apply
    // pass, so their initial contents are covered by that buffer's
    // initialization.
    write_u32_words(
        queue,
        node_inst_subtree_bounds_status_buf,
        &[0, 0, u32::MAX, 0],
    );
    init_repeated!(
        "node_inst_location_record",
        node_inst_location_record_buf,
        &[u32::MAX; 4],
        hir_words,
    );
    write_u32_words(queue, node_inst_location_status_buf, &[0, 0, u32::MAX, 0]);
    write_u32_words(queue, node_inst_gen_input_status_buf, &[0, 0, u32::MAX, 0]);
    // x86_virtual_inst_clear initializes the compact row range from
    // x86_node_inst_gen_input_status[3] immediately before generation.
    // x86_node_inst_gen then overwrites semantic rows while padding rows remain
    // X86_VINST_NONE without requiring a capacity-wide clear.
    write_u32_words(queue, virtual_inst_status_buf, &[0, 0, u32::MAX, 0]);
    // x86_virtual_func_rows_init initializes only discovered function slots
    // before virtual_func_first_row scatters virtual-row bounds. Later stages
    // read these buffers through function slots only, so token-capacity clears
    // are unnecessary.
    write_u32_words(
        queue,
        virtual_func_first_row_status_buf,
        &[0, 0, u32::MAX, 0],
    );
    // x86_virtual_liveness_init writes every active row before direct operand
    // liveness updates extend live_end.
    write_u32_words(queue, virtual_liveness_status_buf, &[0, 0, u32::MAX, 0]);
    // The next-call suffix scan writes every row it later consumes. Register
    // allocation reads only rows below x86_virtual_next_call_status[3].
    write_u32_words(queue, virtual_next_call_status_buf, &[0, 0, u32::MAX, 0]);
    // func_param_reg_mask_buf reuses node_inst_count_record storage.
    // x86_virtual_func_rows_init clears the function slots that regalloc can
    // read before virtual_param_masks atomically ORs parameter masks.
    write_u32_words(queue, func_param_reg_mask_status_buf, &[0, 0, u32::MAX, 0]);
    // x86_virtual_liveness_init writes INVALID for every active virtual row
    // before register allocation fills value-def rows. Rows outside the active
    // virtual-row count are not consumed.
    write_u32_words(queue, virtual_regalloc_status_buf, &[0, 0, u32::MAX, 0]);
    queue.write_buffer(select_status_buf, 0, &[0u8; 16]);
    write_u32_words(queue, size_status_buf, &[1, 0, u32::MAX, 0]);
    write_u32_words(queue, text_len_buf, &[0]);
    write_u32_words(queue, text_status_buf, &[0, 0, u32::MAX, 0]);
    write_u32_words(queue, encode_status_buf, &[0, 0, u32::MAX, 0]);
    queue.write_buffer(elf_layout_buf, 0, &[0u8; 32]);
    write_u32_words(queue, layout_status_buf, &[0, 0, u32::MAX, 0]);
    queue.write_buffer(status_buf, 0, &[0u8; 16]);

    Ok(())
}
