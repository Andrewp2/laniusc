use anyhow::Result;

use super::{
    super::{
        GpuX86ExternalScratchBuffers,
        X86FeatureSummary,
        X86Params,
        support::{
            PooledReadbackBuffer,
            PooledStorageBuffer,
            external_or_storage_u32_copy,
            pooled_readback_bytes,
            pooled_storage_u32_copy,
            storage_u32_copy,
            uniform_u32_struct,
            uniform_u32_words,
            x86_params_bytes,
        },
        x86_call_type_record_words,
        x86_node_inst_gen_node_record_words,
        x86_node_inst_order_record_words,
    },
    allocation::AllocationScope,
    dispatch_args::ActiveDispatchArgBuffers,
};
use crate::gpu::buffers::LaniusBuffer;

/// Buffers allocated before x86 metadata discovery and feature-specific records.
pub(super) struct InitialRecordBuffers {
    pub(super) params_buf: LaniusBuffer<u32>,
    pub(super) feature_params_buf: LaniusBuffer<u32>,
    pub(super) func_meta_buf: PooledStorageBuffer,
    pub(super) active_dispatch_args: ActiveDispatchArgBuffers,
    pub(super) func_meta_uniform_buf: LaniusBuffer<u32>,
    pub(super) node_tree_status_buf: PooledStorageBuffer,
    pub(super) expr_resolved_final_buf: LaniusBuffer<u32>,
    pub(super) node_func_buf: LaniusBuffer<u32>,
    pub(super) node_inst_scan_input_buf: LaniusBuffer<u32>,
    pub(super) node_inst_scan_block_sum_buf: LaniusBuffer<u32>,
    pub(super) node_inst_scan_prefix_a_buf: LaniusBuffer<u32>,
    pub(super) node_inst_scan_prefix_b_buf: LaniusBuffer<u32>,
    pub(super) enum_value_record_rows: usize,
    pub(super) enum_type_record_buf: LaniusBuffer<u32>,
    pub(super) enum_value_record_buf: LaniusBuffer<u32>,
    pub(super) enum_record_status_buf: PooledStorageBuffer,
    pub(super) match_record_rows: usize,
    pub(super) match_record_buf: LaniusBuffer<u32>,
    pub(super) match_arm_owner_buf: LaniusBuffer<u32>,
    pub(super) match_return_node_buf: LaniusBuffer<u32>,
    pub(super) match_pattern_owner_buf: LaniusBuffer<u32>,
    pub(super) match_result_value_owner_buf: LaniusBuffer<u32>,
    pub(super) match_pattern_node_owner_buf: LaniusBuffer<u32>,
    pub(super) match_pattern_node_variant_buf: LaniusBuffer<u32>,
    pub(super) match_pattern_node_payload_decl_buf: LaniusBuffer<u32>,
    pub(super) node_inst_same_end_link_a_buf: LaniusBuffer<u32>,
    pub(super) node_inst_same_end_link_b_buf: LaniusBuffer<u32>,
}

/// Inputs used to allocate the initial x86 record buffers.
pub(super) struct InitialRecordBufferInputs<'a, 'scratch> {
    pub(super) params: &'a X86Params,
    pub(super) feature_summary: X86FeatureSummary,
    pub(super) hir_words: usize,
    pub(super) node_inst_scan_words: usize,
    pub(super) node_inst_scan_blocks: usize,
    pub(super) token_words: usize,
    pub(super) virtual_next_call_step_count: usize,
    pub(super) virtual_regalloc_chunk_count: usize,
    pub(super) external_scratch: &'a GpuX86ExternalScratchBuffers<'scratch>,
}

/// Buffers allocated for x86 semantic metadata and call/aggregate planning.
pub(super) struct MetadataRecordBuffers {
    pub(super) match_pattern_first_use_node_buf: LaniusBuffer<u32>,
    pub(super) needs_enclosing_return_records: bool,
    pub(super) enclosing_return_node_a_buf: LaniusBuffer<u32>,
    pub(super) enclosing_return_node_b_buf: LaniusBuffer<u32>,
    pub(super) enclosing_let_node_a_buf: LaniusBuffer<u32>,
    pub(super) enclosing_let_node_b_buf: LaniusBuffer<u32>,
    pub(super) match_pattern_first_variant_node_storage_buf: Option<LaniusBuffer<u32>>,
    pub(super) match_pattern_first_payload_node_storage_buf: Option<LaniusBuffer<u32>>,
    pub(super) aggregate_record_rows: usize,
    pub(super) struct_type_record_buf: LaniusBuffer<u32>,
    pub(super) struct_field_width_by_node_buf: LaniusBuffer<u32>,
    pub(super) struct_field_stream_index_by_node_buf: LaniusBuffer<u32>,
    pub(super) struct_access_record_buf: LaniusBuffer<u32>,
    pub(super) struct_store_record_buf: LaniusBuffer<u32>,
    pub(super) aggregate_source_node_buf: LaniusBuffer<u32>,
    pub(super) aggregate_source_offset_buf: LaniusBuffer<u32>,
    pub(super) aggregate_source_node_scratch_buf: LaniusBuffer<u32>,
    pub(super) aggregate_source_offset_scratch_buf: LaniusBuffer<u32>,
    pub(super) struct_record_status_buf: PooledStorageBuffer,
    pub(super) decl_layout_record_buf: LaniusBuffer<u32>,
    pub(super) decl_layout_status_buf: PooledStorageBuffer,
    pub(super) decl_node_by_token_buf: LaniusBuffer<u32>,
    pub(super) func_slot_by_index_buf: LaniusBuffer<u32>,
    pub(super) func_slot_by_node_buf: LaniusBuffer<u32>,
    pub(super) call_record_buf: LaniusBuffer<u32>,
    pub(super) call_type_record_buf: LaniusBuffer<u32>,
    pub(super) node_inst_count_info_buf: LaniusBuffer<u32>,
    pub(super) node_inst_count_payload_buf: LaniusBuffer<u32>,
    pub(super) call_record_status_buf: PooledStorageBuffer,
    pub(super) const_value_record_buf: LaniusBuffer<u32>,
    pub(super) const_value_status_buf: PooledStorageBuffer,
    pub(super) const_value_status_uniform_buf: LaniusBuffer<u32>,
    pub(super) param_reg_record_words: usize,
    pub(super) param_reg_record_buf: LaniusBuffer<u32>,
    pub(super) param_reg_status_buf: PooledStorageBuffer,
    pub(super) param_reg_status_uniform_buf: LaniusBuffer<u32>,
    pub(super) local_literal_record_buf: LaniusBuffer<u32>,
    pub(super) local_literal_status_buf: PooledStorageBuffer,
    pub(super) local_literal_status_uniform_buf: LaniusBuffer<u32>,
    pub(super) empty_param_record_buf: Option<LaniusBuffer<u32>>,
    pub(super) node_inst_order_record_buf: LaniusBuffer<u32>,
    pub(super) intrinsic_call_status_buf: PooledStorageBuffer,
    pub(super) call_abi_record_buf: LaniusBuffer<u32>,
    pub(super) call_abi_status_buf: PooledStorageBuffer,
    pub(super) call_abi_status_uniform_buf: LaniusBuffer<u32>,
    pub(super) for_iterable_node_buf: LaniusBuffer<u32>,
    pub(super) node_control_padding_buf: LaniusBuffer<u32>,
    pub(super) postfix_operand_owner_buf: LaniusBuffer<u32>,
}

/// Inputs used to allocate metadata-stage x86 record buffers.
pub(super) struct MetadataRecordBufferInputs<'a, 'scratch> {
    pub(super) feature_summary: X86FeatureSummary,
    pub(super) hir_words: usize,
    pub(super) token_words: usize,
    pub(super) decl_layout_words: usize,
    pub(super) inst_capacity: usize,
    pub(super) function_slot_capacity: usize,
    pub(super) external_scratch: &'a GpuX86ExternalScratchBuffers<'scratch>,
}

/// Buffers allocated for instruction planning, virtual lowering, and output emission.
pub(super) struct InstructionRecordBuffers {
    pub(super) node_inst_count_status_buf: PooledStorageBuffer,
    pub(super) node_inst_order_status_buf: PooledStorageBuffer,
    pub(super) node_inst_scan_local_prefix_buf: LaniusBuffer<u32>,
    pub(super) node_inst_range_start_buf: LaniusBuffer<u32>,
    pub(super) node_inst_range_info_buf: LaniusBuffer<u32>,
    pub(super) node_inst_range_status_buf: PooledStorageBuffer,
    pub(super) node_inst_subtree_bound_start_buf: LaniusBuffer<u32>,
    pub(super) node_inst_subtree_bound_end_buf: LaniusBuffer<u32>,
    pub(super) node_inst_gen_node_record_buf: LaniusBuffer<u32>,
    pub(super) node_inst_subtree_bounds_status_buf: PooledStorageBuffer,
    pub(super) node_inst_location_status_buf: PooledStorageBuffer,
    pub(super) short_circuit_rhs_node_a_buf: LaniusBuffer<u32>,
    pub(super) short_circuit_rhs_node_b_buf: LaniusBuffer<u32>,
    pub(super) short_circuit_rhs_link_a_buf: LaniusBuffer<u32>,
    pub(super) short_circuit_rhs_link_b_buf: LaniusBuffer<u32>,
    pub(super) node_inst_gen_input_status_buf: PooledStorageBuffer,
    pub(super) virtual_inst_record_buf: LaniusBuffer<u32>,
    pub(super) virtual_inst_args_buf: LaniusBuffer<u32>,
    pub(super) virtual_inst_status_buf: PooledStorageBuffer,
    pub(super) virtual_func_first_row_buf: LaniusBuffer<u32>,
    pub(super) virtual_func_first_row_status_buf: PooledStorageBuffer,
    pub(super) virtual_func_slot_buf: LaniusBuffer<u32>,
    pub(super) virtual_value_def_status_buf: PooledStorageBuffer,
    pub(super) virtual_live_start_buf: LaniusBuffer<u32>,
    pub(super) virtual_live_end_buf: LaniusBuffer<u32>,
    pub(super) virtual_liveness_status_buf: PooledStorageBuffer,
    pub(super) virtual_next_call_a_buf: LaniusBuffer<u32>,
    pub(super) virtual_next_call_b_buf: LaniusBuffer<u32>,
    pub(super) virtual_next_call_status_buf: PooledStorageBuffer,
    pub(super) func_param_reg_mask_status_buf: PooledStorageBuffer,
    pub(super) virtual_regalloc_param_rank_mask_buf: LaniusBuffer<u32>,
    pub(super) virtual_phys_reg_buf: LaniusBuffer<u32>,
    pub(super) virtual_call_live_reg_mask_buf: LaniusBuffer<u32>,
    pub(super) virtual_regalloc_status_buf: PooledStorageBuffer,
    pub(super) select_status_buf: PooledStorageBuffer,
    pub(super) size_status_buf: PooledStorageBuffer,
    pub(super) text_len_buf: LaniusBuffer<u32>,
    pub(super) rodata_len_buf: LaniusBuffer<u32>,
    pub(super) rodata_size_by_node_buf: LaniusBuffer<u32>,
    pub(super) rodata_offset_by_node_buf: LaniusBuffer<u32>,
    pub(super) rodata_status_buf: PooledStorageBuffer,
    pub(super) rodata_scan_blocks: usize,
    pub(super) rodata_scan_local_prefix_buf: LaniusBuffer<u32>,
    pub(super) rodata_scan_block_sum_buf: LaniusBuffer<u32>,
    pub(super) rodata_scan_prefix_a_buf: LaniusBuffer<u32>,
    pub(super) rodata_scan_prefix_b_buf: LaniusBuffer<u32>,
    pub(super) text_status_buf: PooledStorageBuffer,
    pub(super) text_scan_words: usize,
    pub(super) text_scan_blocks: usize,
    pub(super) text_scan_block_sum_buf: LaniusBuffer<u32>,
    pub(super) text_scan_prefix_a_buf: LaniusBuffer<u32>,
    pub(super) text_scan_prefix_b_buf: LaniusBuffer<u32>,
    pub(super) virtual_value_def_flag_buf: LaniusBuffer<u32>,
    pub(super) virtual_value_def_row_buf: LaniusBuffer<u32>,
    pub(super) reloc_count_buf: LaniusBuffer<u32>,
    pub(super) reloc_status_buf: PooledStorageBuffer,
    pub(super) encode_status_buf: PooledStorageBuffer,
    pub(super) elf_layout_buf: LaniusBuffer<u32>,
    pub(super) layout_status_buf: PooledStorageBuffer,
    pub(super) status_buf: PooledStorageBuffer,
    pub(super) out_buf: PooledStorageBuffer,
    pub(super) output_status_offset: u64,
    pub(super) output_readback: PooledReadbackBuffer,
}

/// Inputs used to allocate instruction-stage x86 record buffers.
pub(super) struct InstructionRecordBufferInputs<'a, 'scratch> {
    pub(super) hir_words: usize,
    pub(super) node_inst_scan_words: usize,
    pub(super) inst_capacity: usize,
    pub(super) function_slot_capacity: usize,
    pub(super) output_words: usize,
    pub(super) output_readback_bytes: u64,
    pub(super) external_scratch: &'a GpuX86ExternalScratchBuffers<'scratch>,
}

/// Allocates the first x86 record buffer group and reuses external scratch where valid.
pub(super) fn create_initial_record_buffers(
    device: &wgpu::Device,
    allocation_scope: &mut AllocationScope<'_>,
    inputs: InitialRecordBufferInputs<'_, '_>,
) -> Result<InitialRecordBuffers> {
    let InitialRecordBufferInputs {
        params,
        feature_summary,
        hir_words,
        node_inst_scan_words,
        node_inst_scan_blocks,
        token_words,
        virtual_next_call_step_count,
        virtual_regalloc_chunk_count,
        external_scratch,
    } = inputs;

    let params_bytes = x86_params_bytes(params);
    let params_buf = uniform_u32_struct(device, "codegen.x86.params", &params_bytes);
    let feature_record_words = feature_summary.record_words();
    let feature_params_buf =
        uniform_u32_words(device, "codegen.x86.feature_params", &feature_record_words);
    let func_meta_buf = pooled_storage_u32_copy(device, "codegen.x86.func_meta", 8);
    let active_dispatch_args = ActiveDispatchArgBuffers::create(
        device,
        virtual_next_call_step_count,
        virtual_regalloc_chunk_count,
    );
    let func_meta_uniform_buf = uniform_u32_words(
        device,
        "codegen.x86.func_meta.uniform",
        &[0, 0, u32::MAX, 0, u32::MAX, 0, 0, 0],
    );
    let node_tree_status_buf = pooled_storage_u32_copy(device, "codegen.x86.node_tree_status", 4);
    let expr_resolved_final_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.expr_resolved_node",
        hir_words,
        external_scratch.expr_resolved_final,
    );
    let node_func_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.node_func",
        hir_words,
        external_scratch.node_func,
    );
    let node_inst_scan_input_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.node_inst_scan_input",
        node_inst_scan_words,
        external_scratch.node_inst_scan_input,
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
    allocation_scope.checkpoint("metadata tree/function buffer allocation")?;

    let enum_type_record_buf =
        storage_u32_copy(device, "codegen.x86.enum_type_record", token_words);
    let enum_value_record_rows = if feature_summary.has_enum() {
        hir_words
    } else {
        1
    };
    let enum_value_record_buf = storage_u32_copy(
        device,
        "codegen.x86.enum_value_record",
        enum_value_record_rows * 2,
    );
    let enum_record_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.enum_record_status", 4);
    let match_record_rows = if feature_summary.has_match() {
        hir_words
    } else {
        1
    };
    let match_record_buf =
        storage_u32_copy(device, "codegen.x86.match_record", match_record_rows * 4);
    let match_arm_owner_buf =
        storage_u32_copy(device, "codegen.x86.match_arm_owner", match_record_rows);
    let match_return_node_buf =
        storage_u32_copy(device, "codegen.x86.match_return_node", match_record_rows);
    let match_pattern_owner_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.match_pattern_owner",
        hir_words,
        external_scratch.match_pattern_owner,
    );
    let match_result_value_owner_buf = storage_u32_copy(
        device,
        "codegen.x86.match_result_value_owner",
        match_record_rows,
    );
    let match_pattern_node_owner_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.match_pattern_node_owner",
        hir_words,
        external_scratch.match_pattern_node_owner,
    );
    let match_pattern_node_variant_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.match_pattern_node_variant",
        hir_words,
        external_scratch.match_pattern_node_variant,
    );
    let match_pattern_node_payload_decl_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.match_pattern_node_payload_decl",
        match_record_rows,
        external_scratch.match_pattern_node_payload_decl,
    );
    let node_inst_same_end_link_a_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.node_inst_same_end_link_a",
        hir_words,
        external_scratch.node_inst_same_end_link_a,
    );
    let node_inst_same_end_link_b_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.node_inst_same_end_link_b",
        hir_words,
        external_scratch.node_inst_same_end_link_b,
    );

    Ok(InitialRecordBuffers {
        params_buf,
        feature_params_buf,
        func_meta_buf,
        active_dispatch_args,
        func_meta_uniform_buf,
        node_tree_status_buf,
        expr_resolved_final_buf,
        node_func_buf,
        node_inst_scan_input_buf,
        node_inst_scan_block_sum_buf,
        node_inst_scan_prefix_a_buf,
        node_inst_scan_prefix_b_buf,
        enum_value_record_rows,
        enum_type_record_buf,
        enum_value_record_buf,
        enum_record_status_buf,
        match_record_rows,
        match_record_buf,
        match_arm_owner_buf,
        match_return_node_buf,
        match_pattern_owner_buf,
        match_result_value_owner_buf,
        match_pattern_node_owner_buf,
        match_pattern_node_variant_buf,
        match_pattern_node_payload_decl_buf,
        node_inst_same_end_link_a_buf,
        node_inst_same_end_link_b_buf,
    })
}

/// Allocates x86 metadata, aggregate, call, and declaration-layout buffers.
pub(super) fn create_metadata_record_buffers(
    device: &wgpu::Device,
    allocation_scope: &mut AllocationScope<'_>,
    inputs: MetadataRecordBufferInputs<'_, '_>,
) -> Result<MetadataRecordBuffers> {
    let MetadataRecordBufferInputs {
        feature_summary,
        hir_words,
        token_words,
        decl_layout_words,
        inst_capacity,
        function_slot_capacity,
        external_scratch,
    } = inputs;

    let match_pattern_first_use_node_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.match_pattern_first_use_node",
        hir_words,
        external_scratch.match_pattern_first_use_node,
    );
    let needs_enclosing_return_records = feature_summary.has_enum()
        || feature_summary.has_match()
        || feature_summary.has_aggregate();
    let enclosing_return_record_rows = if needs_enclosing_return_records {
        hir_words
    } else {
        1
    };
    let enclosing_return_node_a_buf = storage_u32_copy(
        device,
        "codegen.x86.enclosing_return_node.a",
        enclosing_return_record_rows,
    );
    let enclosing_return_node_b_buf = storage_u32_copy(
        device,
        "codegen.x86.enclosing_return_node.b",
        enclosing_return_record_rows,
    );
    let enclosing_let_node_a_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.enclosing_let_node.a",
        hir_words,
        external_scratch.enclosing_let_node_a,
    );
    let enclosing_let_node_b_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.enclosing_let_node.b",
        hir_words,
        external_scratch.enclosing_let_node_b,
    );
    let match_pattern_first_variant_node_storage_buf = feature_summary.has_match().then(|| {
        storage_u32_copy(
            device,
            "codegen.x86.match_pattern_first_variant_node",
            hir_words,
        )
    });
    let match_pattern_first_payload_node_storage_buf = feature_summary.has_match().then(|| {
        storage_u32_copy(
            device,
            "codegen.x86.match_pattern_first_payload_node",
            hir_words,
        )
    });
    let struct_type_record_buf =
        storage_u32_copy(device, "codegen.x86.struct_type_record", token_words);
    let struct_field_width_by_node_buf =
        storage_u32_copy(device, "codegen.x86.struct_field_width_by_node", hir_words);
    let struct_field_stream_index_by_node_buf = storage_u32_copy(
        device,
        "codegen.x86.struct_field_stream_index_by_node",
        hir_words,
    );
    let aggregate_record_rows = if feature_summary.has_aggregate() {
        hir_words
    } else {
        1
    };
    let struct_access_record_buf = storage_u32_copy(
        device,
        "codegen.x86.struct_access_record",
        aggregate_record_rows * 3,
    );
    let struct_store_record_buf = storage_u32_copy(
        device,
        "codegen.x86.struct_store_record",
        aggregate_record_rows * 4,
    );
    let aggregate_source_node_buf = storage_u32_copy(
        device,
        "codegen.x86.aggregate_source_node",
        aggregate_record_rows,
    );
    let aggregate_source_offset_buf = storage_u32_copy(
        device,
        "codegen.x86.aggregate_source_offset",
        aggregate_record_rows,
    );
    let aggregate_source_node_scratch_buf = storage_u32_copy(
        device,
        "codegen.x86.aggregate_source_node.scratch",
        aggregate_record_rows,
    );
    let aggregate_source_offset_scratch_buf = storage_u32_copy(
        device,
        "codegen.x86.aggregate_source_offset.scratch",
        aggregate_record_rows,
    );
    let struct_record_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.struct_record_status", 4);
    let decl_layout_record_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.decl_layout_record",
        decl_layout_words * 4,
        external_scratch.decl_layout_record,
    );
    let decl_layout_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.decl_layout_status", 4);
    let decl_node_by_token_buf =
        storage_u32_copy(device, "codegen.x86.decl_node_by_token", token_words);
    let func_slot_by_index_buf = storage_u32_copy(
        device,
        "codegen.x86.func_slot_by_index",
        function_slot_capacity,
    );
    let func_slot_by_node_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.func_slot_by_node",
        hir_words,
        external_scratch.func_slot_by_node,
    );
    let call_record_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.call_record",
        hir_words * 4,
        external_scratch.call_record,
    );
    allocation_scope.checkpoint("call record buffer allocation")?;

    let call_type_record_words = x86_call_type_record_words(hir_words, feature_summary.has_call());
    let call_type_record_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.call_type_record",
        call_type_record_words,
        external_scratch.call_type_record,
    );
    let node_inst_count_info_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.node_inst_count_info",
        hir_words,
        external_scratch.node_inst_count_info,
    );
    let node_inst_count_payload_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.node_inst_count_payload",
        hir_words,
        external_scratch.node_inst_count_payload,
    );
    allocation_scope.checkpoint("node count buffer allocation")?;

    let call_record_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.call_record_status", 4);
    let const_value_record_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.const_value_record",
        token_words * 2,
        external_scratch.const_value_record,
    );
    let const_value_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.const_value_status", 4);
    let const_value_status_uniform_buf = uniform_u32_words(
        device,
        "codegen.x86.const_value_status.uniform",
        &[1, 0, u32::MAX, 0],
    );
    let param_reg_record_words = token_words.saturating_mul(6);
    let param_reg_record_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.param_reg_record",
        param_reg_record_words,
        external_scratch.param_reg_record,
    );
    let param_reg_status_buf = pooled_storage_u32_copy(device, "codegen.x86.param_reg_status", 4);
    let param_reg_status_uniform_buf = uniform_u32_words(
        device,
        "codegen.x86.param_reg_status.uniform",
        &[1, 0, u32::MAX, 0],
    );
    let local_literal_record_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.local_literal_record",
        token_words * 3,
        external_scratch.local_literal_record,
    );
    let local_literal_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.local_literal_status", 4);
    let local_literal_status_uniform_buf = uniform_u32_words(
        device,
        "codegen.x86.local_literal_status.uniform",
        &[1, 0, u32::MAX, 0],
    );
    let empty_param_record_buf = (!feature_summary.has_param())
        .then(|| storage_u32_copy(device, "codegen.x86.empty_param_record", 4));
    allocation_scope.checkpoint("metadata record buffer allocation")?;

    let node_inst_order_record_words =
        x86_node_inst_order_record_words(hir_words, inst_capacity, function_slot_capacity);
    let node_inst_order_record_buf = storage_u32_copy(
        device,
        "codegen.x86.node_inst_order_record",
        node_inst_order_record_words,
    );
    allocation_scope.checkpoint("node instruction order buffer allocation")?;

    let intrinsic_call_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.intrinsic_call_status", 4);
    let call_abi_record_words = if feature_summary.has_call() {
        token_words * 2
    } else {
        function_slot_capacity.max(2)
    };
    let call_abi_record_buf =
        storage_u32_copy(device, "codegen.x86.call_abi_record", call_abi_record_words);
    let call_abi_status_buf = pooled_storage_u32_copy(device, "codegen.x86.call_abi_status", 4);
    let call_abi_status_uniform_buf = uniform_u32_words(
        device,
        "codegen.x86.call_abi_status.uniform",
        &[1, 0, u32::MAX, 0],
    );
    let for_iterable_node_buf =
        storage_u32_copy(device, "codegen.x86.for_iterable_node", hir_words);
    let node_control_padding_buf =
        storage_u32_copy(device, "codegen.x86.node_control_padding", hir_words);
    let postfix_operand_owner_buf =
        storage_u32_copy(device, "codegen.x86.postfix_operand_owner", hir_words);
    allocation_scope.checkpoint("call argument planning buffer allocation")?;

    Ok(MetadataRecordBuffers {
        match_pattern_first_use_node_buf,
        needs_enclosing_return_records,
        enclosing_return_node_a_buf,
        enclosing_return_node_b_buf,
        enclosing_let_node_a_buf,
        enclosing_let_node_b_buf,
        match_pattern_first_variant_node_storage_buf,
        match_pattern_first_payload_node_storage_buf,
        aggregate_record_rows,
        struct_type_record_buf,
        struct_field_width_by_node_buf,
        struct_field_stream_index_by_node_buf,
        struct_access_record_buf,
        struct_store_record_buf,
        aggregate_source_node_buf,
        aggregate_source_offset_buf,
        aggregate_source_node_scratch_buf,
        aggregate_source_offset_scratch_buf,
        struct_record_status_buf,
        decl_layout_record_buf,
        decl_layout_status_buf,
        decl_node_by_token_buf,
        func_slot_by_index_buf,
        func_slot_by_node_buf,
        call_record_buf,
        call_type_record_buf,
        node_inst_count_info_buf,
        node_inst_count_payload_buf,
        call_record_status_buf,
        const_value_record_buf,
        const_value_status_buf,
        const_value_status_uniform_buf,
        param_reg_record_words,
        param_reg_record_buf,
        param_reg_status_buf,
        param_reg_status_uniform_buf,
        local_literal_record_buf,
        local_literal_status_buf,
        local_literal_status_uniform_buf,
        empty_param_record_buf,
        node_inst_order_record_buf,
        intrinsic_call_status_buf,
        call_abi_record_buf,
        call_abi_status_buf,
        call_abi_status_uniform_buf,
        for_iterable_node_buf,
        node_control_padding_buf,
        postfix_operand_owner_buf,
    })
}

/// Allocates x86 instruction, register-allocation, relocation, and output buffers.
pub(super) fn create_instruction_record_buffers(
    device: &wgpu::Device,
    mut allocation_scope: AllocationScope<'_>,
    inputs: InstructionRecordBufferInputs<'_, '_>,
) -> Result<InstructionRecordBuffers> {
    let InstructionRecordBufferInputs {
        hir_words,
        node_inst_scan_words,
        inst_capacity,
        function_slot_capacity,
        output_words,
        output_readback_bytes,
        external_scratch,
    } = inputs;

    let node_inst_count_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.node_inst_count_status", 5);
    let node_inst_order_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.node_inst_order_status", 4);
    let node_inst_scan_local_prefix_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.node_inst_scan_local_prefix",
        node_inst_scan_words,
        external_scratch.node_inst_scan_local_prefix,
    );
    let node_inst_range_start_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.node_inst_range_start",
        hir_words,
        external_scratch.node_inst_range_start,
    );
    let node_inst_range_info_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.node_inst_range_info",
        hir_words,
        external_scratch.node_inst_range_info,
    );
    let node_inst_range_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.node_inst_range_status", 4);
    let node_inst_subtree_bound_start_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.node_inst_subtree_bound_start",
        hir_words,
        external_scratch.node_inst_subtree_bound_start,
    );
    let node_inst_subtree_bound_end_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.node_inst_subtree_bound_end",
        hir_words,
        external_scratch.node_inst_subtree_bound_end,
    );
    let node_inst_gen_node_record_words =
        x86_node_inst_gen_node_record_words(hir_words, inst_capacity);
    let node_inst_gen_node_record_buf = external_or_storage_u32_copy(
        device,
        "codegen.x86.node_inst_gen_node_record",
        node_inst_gen_node_record_words,
        external_scratch.node_inst_gen_node_record,
    );
    let node_inst_subtree_bounds_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.node_inst_subtree_bounds_status", 4);
    allocation_scope.checkpoint("node instruction scan/range buffer allocation")?;

    let node_inst_location_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.node_inst_location_status", 4);
    let short_circuit_rhs_node_a_buf =
        storage_u32_copy(device, "codegen.x86.short_circuit_rhs_node.a", hir_words);
    let short_circuit_rhs_node_b_buf =
        storage_u32_copy(device, "codegen.x86.short_circuit_rhs_node.b", hir_words);
    let short_circuit_rhs_link_a_buf =
        storage_u32_copy(device, "codegen.x86.short_circuit_rhs_link.a", hir_words);
    let short_circuit_rhs_link_b_buf =
        storage_u32_copy(device, "codegen.x86.short_circuit_rhs_link.b", hir_words);
    let node_inst_gen_input_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.node_inst_gen_input_status", 5);
    let virtual_inst_record_buf =
        storage_u32_copy(device, "codegen.x86.virtual_inst_record", inst_capacity * 4);
    let virtual_inst_args_buf =
        storage_u32_copy(device, "codegen.x86.virtual_inst_args", inst_capacity * 4);
    let virtual_inst_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.virtual_inst_status", 4);
    allocation_scope.checkpoint("virtual instruction buffer allocation")?;

    let virtual_func_first_row_buf = storage_u32_copy(
        device,
        "codegen.x86.virtual_func_first_row",
        function_slot_capacity,
    );
    let virtual_func_first_row_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.virtual_func_first_row_status", 4);
    let virtual_func_slot_buf =
        storage_u32_copy(device, "codegen.x86.virtual_func_slot", inst_capacity);
    let virtual_value_def_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.virtual_value_def_status", 4);
    let virtual_live_start_buf =
        storage_u32_copy(device, "codegen.x86.virtual_live_start", inst_capacity);
    let virtual_live_end_buf =
        storage_u32_copy(device, "codegen.x86.virtual_live_end", inst_capacity);
    let virtual_liveness_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.virtual_liveness_status", 4);
    let virtual_next_call_a_buf =
        storage_u32_copy(device, "codegen.x86.virtual_next_call.a", inst_capacity);
    let virtual_next_call_b_buf =
        storage_u32_copy(device, "codegen.x86.virtual_next_call.b", inst_capacity);
    let virtual_next_call_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.virtual_next_call_status", 4);
    let func_param_reg_mask_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.func_param_reg_mask_status", 4);
    let virtual_regalloc_param_rank_mask_buf = storage_u32_copy(
        device,
        "codegen.x86.virtual_regalloc_param_rank_mask",
        function_slot_capacity,
    );
    let virtual_phys_reg_buf =
        storage_u32_copy(device, "codegen.x86.virtual_phys_reg", inst_capacity);
    let virtual_call_live_reg_mask_buf = storage_u32_copy(
        device,
        "codegen.x86.virtual_call_live_reg_mask",
        inst_capacity,
    );
    let virtual_regalloc_status_buf =
        pooled_storage_u32_copy(device, "codegen.x86.virtual_regalloc_status", 4);
    let select_status_buf = pooled_storage_u32_copy(device, "codegen.x86.select_status", 4);
    let size_status_buf = pooled_storage_u32_copy(device, "codegen.x86.size_status", 4);
    let text_len_buf = storage_u32_copy(device, "codegen.x86.text_len", 1);
    let rodata_len_buf = storage_u32_copy(device, "codegen.x86.rodata_len", 1);
    let rodata_size_by_node_buf =
        storage_u32_copy(device, "codegen.x86.rodata_size_by_node", hir_words);
    let rodata_offset_by_node_buf =
        storage_u32_copy(device, "codegen.x86.rodata_offset_by_node", hir_words);
    let rodata_status_buf = pooled_storage_u32_copy(device, "codegen.x86.rodata_status", 4);
    let rodata_scan_blocks = hir_words.div_ceil(256).max(1);
    let rodata_scan_local_prefix_buf =
        storage_u32_copy(device, "codegen.x86.rodata_scan_local_prefix", hir_words);
    let rodata_scan_block_sum_buf = storage_u32_copy(
        device,
        "codegen.x86.rodata_scan_block_sum",
        rodata_scan_blocks,
    );
    let rodata_scan_prefix_a_buf = storage_u32_copy(
        device,
        "codegen.x86.rodata_scan_prefix_a",
        rodata_scan_blocks,
    );
    let rodata_scan_prefix_b_buf = storage_u32_copy(
        device,
        "codegen.x86.rodata_scan_prefix_b",
        rodata_scan_blocks,
    );
    let text_status_buf = pooled_storage_u32_copy(device, "codegen.x86.text_status", 4);
    let text_scan_words = inst_capacity;
    let text_scan_blocks = text_scan_words.div_ceil(256).max(1);
    let text_scan_block_sum_buf =
        storage_u32_copy(device, "codegen.x86.text_scan_block_sum", text_scan_blocks);
    let text_scan_prefix_a_buf =
        storage_u32_copy(device, "codegen.x86.text_scan_prefix_a", text_scan_blocks);
    let text_scan_prefix_b_buf =
        storage_u32_copy(device, "codegen.x86.text_scan_prefix_b", text_scan_blocks);
    let virtual_value_def_flag_buf =
        storage_u32_copy(device, "codegen.x86.virtual_value_def_flag", inst_capacity);
    let virtual_value_def_row_buf =
        storage_u32_copy(device, "codegen.x86.virtual_value_def_row", inst_capacity);
    let reloc_count_buf = storage_u32_copy(device, "codegen.x86.reloc_count", 1);
    let reloc_status_buf = pooled_storage_u32_copy(device, "codegen.x86.reloc_status", 4);
    let encode_status_buf = pooled_storage_u32_copy(device, "codegen.x86.encode_status", 4);
    let elf_layout_buf = storage_u32_copy(device, "codegen.x86.elf_layout", 8);
    let layout_status_buf = pooled_storage_u32_copy(device, "codegen.x86.layout_status", 4);
    let status_buf = pooled_storage_u32_copy(device, "codegen.x86.status", 4);
    let out_buf = pooled_storage_u32_copy(device, "codegen.x86.out_words", output_words);
    let output_status_offset = output_readback_bytes;
    let output_readback = pooled_readback_bytes(
        device,
        "rb.codegen.x86.out_words_and_status",
        output_readback_bytes + 16,
    );
    allocation_scope.finish("virtual/output buffer allocation")?;

    Ok(InstructionRecordBuffers {
        node_inst_count_status_buf,
        node_inst_order_status_buf,
        node_inst_scan_local_prefix_buf,
        node_inst_range_start_buf,
        node_inst_range_info_buf,
        node_inst_range_status_buf,
        node_inst_subtree_bound_start_buf,
        node_inst_subtree_bound_end_buf,
        node_inst_gen_node_record_buf,
        node_inst_subtree_bounds_status_buf,
        node_inst_location_status_buf,
        short_circuit_rhs_node_a_buf,
        short_circuit_rhs_node_b_buf,
        short_circuit_rhs_link_a_buf,
        short_circuit_rhs_link_b_buf,
        node_inst_gen_input_status_buf,
        virtual_inst_record_buf,
        virtual_inst_args_buf,
        virtual_inst_status_buf,
        virtual_func_first_row_buf,
        virtual_func_first_row_status_buf,
        virtual_func_slot_buf,
        virtual_value_def_status_buf,
        virtual_live_start_buf,
        virtual_live_end_buf,
        virtual_liveness_status_buf,
        virtual_next_call_a_buf,
        virtual_next_call_b_buf,
        virtual_next_call_status_buf,
        func_param_reg_mask_status_buf,
        virtual_regalloc_param_rank_mask_buf,
        virtual_phys_reg_buf,
        virtual_call_live_reg_mask_buf,
        virtual_regalloc_status_buf,
        select_status_buf,
        size_status_buf,
        text_len_buf,
        rodata_len_buf,
        rodata_size_by_node_buf,
        rodata_offset_by_node_buf,
        rodata_status_buf,
        rodata_scan_blocks,
        rodata_scan_local_prefix_buf,
        rodata_scan_block_sum_buf,
        rodata_scan_prefix_a_buf,
        rodata_scan_prefix_b_buf,
        text_status_buf,
        text_scan_words,
        text_scan_blocks,
        text_scan_block_sum_buf,
        text_scan_prefix_a_buf,
        text_scan_prefix_b_buf,
        virtual_value_def_flag_buf,
        virtual_value_def_row_buf,
        reloc_count_buf,
        reloc_status_buf,
        encode_status_buf,
        elf_layout_buf,
        layout_status_buf,
        status_buf,
        out_buf,
        output_status_offset,
        output_readback,
    })
}
