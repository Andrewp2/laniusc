use anyhow::Result;
use log::warn;

use super::{
    support::{
        dispatch_compute_pass_indirect,
        dispatch_compute_pass_indirect_offset,
        dispatch_x86_stage,
        dispatch_x86_stage_indirect,
        dispatch_x86_stages,
        dispatch_x86_stages_indirect,
        init_repeated_u32_words,
        pointer_jump_steps_for_items,
        readback_u32s,
        reflected_bind_group,
        scan_steps_for_blocks,
        storage_u32_copy,
        storage_u32_rw,
        uniform_u32_struct,
        uniform_u32_words,
        workgroup_grid_1d,
        write_u32_words,
        x86_params_bytes,
        x86_regalloc_params_bytes,
        x86_scan_params_bytes,
        zero_u32_words,
    },
    x86_capacity_estimate_for_hir_and_tokens,
    x86_node_inst_order_record_words,
    x86_node_inst_order_rows,
    GpuX86ArrayMetadataBuffers,
    GpuX86CallMetadataBuffers,
    GpuX86CodeGenerator,
    GpuX86EnumMetadataBuffers,
    GpuX86ExprMetadataBuffers,
    GpuX86FunctionMetadataBuffers,
    GpuX86StructMetadataBuffers,
    GpuX86TypeMetadataBuffers,
    RecordedX86Codegen,
    X86Params,
    X86RegallocParams,
    X86ScanParams,
    X86_REGALLOC_ROWS_PER_CHUNK,
};

struct X86RecordHostTimer {
    enabled: bool,
    start: std::time::Instant,
    last: std::time::Instant,
}

impl X86RecordHostTimer {
    fn new() -> Self {
        let now = std::time::Instant::now();
        Self {
            enabled: crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false),
            start: now,
            last: now,
        }
    }

    fn stamp(&mut self, stage: &str) {
        if !self.enabled {
            return;
        }
        let now = std::time::Instant::now();
        let dt_ms = now.duration_since(self.last).as_secs_f64() * 1000.0;
        let total_ms = now.duration_since(self.start).as_secs_f64() * 1000.0;
        println!(
            "[gpu_compile_host_timer] codegen.x86.record.{stage}: {dt_ms:.3}ms (total {total_ms:.3}ms)"
        );
        self.last = now;
    }
}

fn stamp_x86_timer(
    timer: &mut Option<&mut crate::gpu::timer::GpuTimer>,
    encoder: &mut wgpu::CommandEncoder,
    label: &'static str,
) {
    if let Some(timer) = timer.as_deref_mut() {
        timer.stamp(encoder, label);
    }
}

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
        active_hir_dispatch_args_buf: &wgpu::Buffer,
        hir_kind_buf: &wgpu::Buffer,
        parent_buf: &wgpu::Buffer,
        first_child_buf: &wgpu::Buffer,
        next_sibling_buf: &wgpu::Buffer,
        subtree_end_buf: &wgpu::Buffer,
        function_metadata: GpuX86FunctionMetadataBuffers<'_>,
        expr_metadata: GpuX86ExprMetadataBuffers<'_>,
        call_metadata: GpuX86CallMetadataBuffers<'_>,
        array_metadata: GpuX86ArrayMetadataBuffers<'_>,
        enum_metadata: GpuX86EnumMetadataBuffers<'_>,
        struct_metadata: GpuX86StructMetadataBuffers<'_>,
        type_metadata: GpuX86TypeMetadataBuffers<'_>,
        visible_decl_buf: &wgpu::Buffer,
        fn_entrypoint_tag_buf: &wgpu::Buffer,
        mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
    ) -> Result<RecordedX86Codegen> {
        let mut host_timer = X86RecordHostTimer::new();
        let capacity =
            x86_capacity_estimate_for_hir_and_tokens(n_hir_nodes as usize, token_capacity as usize);
        let hir_words = capacity.hir_words;
        let inst_capacity = capacity.inst_capacity;
        let output_capacity = capacity.output_capacity;
        if capacity.inst_capacity_capped {
            warn!(
                "x86 instruction capacity estimate hit cap: requested={} cap={} hir_words={} token_capacity={}; exact GPU instruction-count projection is required for larger programs",
                capacity.requested_inst_capacity,
                capacity.inst_capacity,
                capacity.hir_words,
                token_capacity
            );
        }
        let output_words = output_capacity.div_ceil(4);
        let virtual_next_call_steps = scan_steps_for_blocks(inst_capacity);
        let virtual_regalloc_chunk_count =
            inst_capacity.div_ceil(X86_REGALLOC_ROWS_PER_CHUNK).max(1);
        let virtual_dispatch_arg_task_count = virtual_next_call_steps
            .len()
            .max(virtual_regalloc_chunk_count)
            .max(1);
        let virtual_dispatch_arg_groups = workgroup_grid_1d(
            (virtual_dispatch_arg_task_count as u32)
                .div_ceil(256)
                .max(1),
        );
        let params = X86Params {
            n_tokens: token_capacity,
            source_len,
            out_capacity: output_capacity as u32,
            n_hir_nodes,
            inst_capacity: inst_capacity as u32,
            virtual_next_call_step_count: virtual_next_call_steps.len().min(u32::MAX as usize)
                as u32,
            regalloc_rows_per_chunk: X86_REGALLOC_ROWS_PER_CHUNK as u32,
            regalloc_chunk_count: virtual_regalloc_chunk_count.min(u32::MAX as usize) as u32,
        };
        host_timer.stamp("capacity");

        let params_bytes = x86_params_bytes(&params);
        let params_buf = uniform_u32_struct(device, "codegen.x86.params", &params_bytes);
        let token_words = (token_capacity as usize).max(1);
        let decl_layout_words = token_words;
        let node_inst_scan_words = hir_words + 1;
        let node_inst_scan_blocks = node_inst_scan_words.div_ceil(256).max(1);
        let node_inst_order_rows = x86_node_inst_order_rows(hir_words, inst_capacity);
        let node_func_owner_steps = pointer_jump_steps_for_items(hir_words);
        let expr_resolve_steps = pointer_jump_steps_for_items(hir_words);
        let expr_semantic_type_steps = pointer_jump_steps_for_items(hir_words);
        let enclosing_return_steps = pointer_jump_steps_for_items(hir_words);
        let enclosing_let_steps = pointer_jump_steps_for_items(hir_words);
        let enclosing_stmt_steps = pointer_jump_steps_for_items(hir_words);
        let call_callee_owner_steps = pointer_jump_steps_for_items(hir_words);
        let match_result_owner_steps = pointer_jump_steps_for_items(hir_words);
        let match_pattern_owner_steps = pointer_jump_steps_for_items(hir_words);
        let node_inst_same_end_rank_steps = pointer_jump_steps_for_items(hir_words);
        let enclosing_loop_steps = pointer_jump_steps_for_items(hir_words);
        let func_owner_scan_blocks = hir_words.div_ceil(256).max(1);
        let func_meta_buf = storage_u32_copy(device, "codegen.x86.func_meta", 8);
        let active_hir_count_dispatch_args_buf = storage_u32_rw(
            device,
            "codegen.x86.active_hir_count_dispatch_args",
            4,
            wgpu::BufferUsages::INDIRECT,
        );
        let active_hir_plus_one_dispatch_args_buf = storage_u32_rw(
            device,
            "codegen.x86.active_hir_plus_one_dispatch_args",
            4,
            wgpu::BufferUsages::INDIRECT,
        );
        let active_hir_scan_block_dispatch_args_buf = storage_u32_rw(
            device,
            "codegen.x86.active_hir_scan_block_dispatch_args",
            4,
            wgpu::BufferUsages::INDIRECT,
        );
        let active_node_order_scan_dispatch_args_buf = storage_u32_rw(
            device,
            "codegen.x86.active_node_order_scan_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let active_node_order_scan_block_dispatch_args_buf = storage_u32_rw(
            device,
            "codegen.x86.active_node_order_scan_block_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let active_function_dispatch_args_buf = storage_u32_rw(
            device,
            "codegen.x86.active_function_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let active_virtual_inst_dispatch_args_buf = storage_u32_rw(
            device,
            "codegen.x86.active_virtual_inst_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let active_virtual_next_call_dispatch_args_buf = storage_u32_rw(
            device,
            "codegen.x86.active_virtual_next_call_dispatch_args",
            virtual_next_call_steps.len().max(1) * 3,
            wgpu::BufferUsages::INDIRECT,
        );
        let active_virtual_regalloc_dispatch_args_buf = storage_u32_rw(
            device,
            "codegen.x86.active_virtual_regalloc_dispatch_args",
            virtual_regalloc_chunk_count * 3,
            wgpu::BufferUsages::INDIRECT,
        );
        let active_selected_inst_dispatch_args_buf = storage_u32_rw(
            device,
            "codegen.x86.active_selected_inst_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let active_selected_scan_block_dispatch_args_buf = storage_u32_rw(
            device,
            "codegen.x86.active_selected_scan_block_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let active_text_word_dispatch_args_buf = storage_u32_rw(
            device,
            "codegen.x86.active_text_word_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let active_elf_header_word_dispatch_args_buf = storage_u32_rw(
            device,
            "codegen.x86.active_elf_header_word_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let func_meta_uniform_buf = uniform_u32_words(
            device,
            "codegen.x86.func_meta.uniform",
            &[0, 0, u32::MAX, 0, u32::MAX, 0, 0, 0],
        );
        let node_tree_record_buf =
            storage_u32_copy(device, "codegen.x86.node_tree_record", hir_words * 4);
        let node_tree_status_buf = storage_u32_copy(device, "codegen.x86.node_tree_status", 4);
        let expr_resolved_final_buf =
            storage_u32_copy(device, "codegen.x86.expr_resolved_node", hir_words);
        let node_func_buf = storage_u32_copy(device, "codegen.x86.node_func", hir_words);
        let func_owner_scan_local_prefix_buf = storage_u32_copy(
            device,
            "codegen.x86.func_owner_scan_local_prefix",
            node_inst_scan_words,
        );
        let func_owner_scan_block_sum_buf = storage_u32_copy(
            device,
            "codegen.x86.func_owner_scan_block_sum",
            node_inst_scan_blocks,
        );
        let func_owner_scan_prefix_a_buf = storage_u32_copy(
            device,
            "codegen.x86.func_owner_scan_prefix_a",
            node_inst_scan_blocks,
        );
        let func_owner_scan_prefix_b_buf = storage_u32_copy(
            device,
            "codegen.x86.func_owner_scan_prefix_b",
            node_inst_scan_blocks,
        );
        let enum_type_record_buf =
            storage_u32_copy(device, "codegen.x86.enum_type_record", token_words);
        let enum_value_record_buf =
            storage_u32_copy(device, "codegen.x86.enum_value_record", hir_words * 2);
        let enum_record_status_buf = storage_u32_copy(device, "codegen.x86.enum_record_status", 4);
        let match_record_buf = storage_u32_copy(device, "codegen.x86.match_record", hir_words * 4);
        let match_arm_owner_buf =
            storage_u32_copy(device, "codegen.x86.match_arm_owner", hir_words);
        let return_match_node_buf =
            storage_u32_copy(device, "codegen.x86.return_match_node", hir_words);
        let match_return_node_buf =
            storage_u32_copy(device, "codegen.x86.match_return_node", hir_words);
        let match_pattern_owner_buf =
            storage_u32_copy(device, "codegen.x86.match_pattern_owner", hir_words);
        let match_result_value_owner_buf =
            storage_u32_copy(device, "codegen.x86.match_result_value_owner", hir_words);
        let match_pattern_node_owner_buf =
            storage_u32_copy(device, "codegen.x86.match_pattern_node_owner", hir_words);
        let match_pattern_node_variant_buf =
            storage_u32_copy(device, "codegen.x86.match_pattern_node_variant", hir_words);
        let match_pattern_node_payload_decl_buf = storage_u32_copy(
            device,
            "codegen.x86.match_pattern_node_payload_decl",
            hir_words,
        );
        let node_inst_same_end_link_a_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_same_end_link_a", hir_words);
        let node_inst_same_end_link_b_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_same_end_link_b", hir_words);
        // Expression resolution copies its final output before match-result
        // owner propagation starts. Match-pattern owner propagation starts
        // after match-result owners have been copied to the stable value-owner
        // table. Reuse those same HIR-sized scratch rows for this pointer jump.
        let match_result_owner_a_buf = &match_pattern_node_owner_buf;
        let match_result_owner_b_buf = &match_pattern_node_variant_buf;
        let match_result_owner_link_a_buf = &node_inst_same_end_link_a_buf;
        let match_result_owner_link_b_buf = &node_inst_same_end_link_b_buf;
        let match_pattern_first_use_node_buf = storage_u32_copy(
            device,
            "codegen.x86.match_pattern_first_use_node",
            hir_words,
        );
        // Function-owner pointer jumping completes before match-pattern
        // candidate projection. Copy an odd-step result back to node_func and
        // reuse this HIR-sized storage for the later first-use candidate rows.
        let node_func_owner_b_buf = &match_pattern_first_use_node_buf;
        let match_pattern_first_variant_node_buf = storage_u32_copy(
            device,
            "codegen.x86.match_pattern_first_variant_node",
            hir_words,
        );
        let match_pattern_first_payload_node_buf = storage_u32_copy(
            device,
            "codegen.x86.match_pattern_first_payload_node",
            hir_words,
        );
        let enclosing_return_node_a_buf =
            storage_u32_copy(device, "codegen.x86.enclosing_return_node.a", hir_words);
        let enclosing_return_node_b_buf =
            storage_u32_copy(device, "codegen.x86.enclosing_return_node.b", hir_words);
        let enclosing_let_node_a_buf =
            storage_u32_copy(device, "codegen.x86.enclosing_let_node.a", hir_words);
        let enclosing_let_node_b_buf =
            storage_u32_copy(device, "codegen.x86.enclosing_let_node.b", hir_words);
        let struct_type_record_buf =
            storage_u32_copy(device, "codegen.x86.struct_type_record", token_words);
        let struct_access_record_buf =
            storage_u32_copy(device, "codegen.x86.struct_access_record", hir_words * 3);
        let struct_store_record_buf =
            storage_u32_copy(device, "codegen.x86.struct_store_record", hir_words * 4);
        let struct_record_status_buf =
            storage_u32_copy(device, "codegen.x86.struct_record_status", 4);
        let decl_layout_record_buf = storage_u32_copy(
            device,
            "codegen.x86.decl_layout_record",
            decl_layout_words * 4,
        );
        let decl_layout_status_buf = storage_u32_copy(device, "codegen.x86.decl_layout_status", 4);
        let decl_node_by_token_buf =
            storage_u32_copy(device, "codegen.x86.decl_node_by_token", token_words);
        let func_slot_by_index_buf =
            storage_u32_copy(device, "codegen.x86.func_slot_by_index", token_words);
        let call_record_buf = storage_u32_copy(device, "codegen.x86.call_record", hir_words * 4);
        let call_type_record_buf =
            storage_u32_copy(device, "codegen.x86.call_type_record", hir_words * 3);
        // Enclosing-let propagation is copied back to the stable A buffer
        // before call-record projection. Reuse the alternate ping-pong storage
        // for call-callee-root markers produced by call_records.
        let call_callee_root_call_buf = &enclosing_let_node_b_buf;
        let call_record_status_buf = storage_u32_copy(device, "codegen.x86.call_record_status", 4);
        let const_value_record_buf =
            storage_u32_copy(device, "codegen.x86.const_value_record", token_words * 2);
        let const_value_status_buf = storage_u32_copy(device, "codegen.x86.const_value_status", 4);
        let const_value_status_uniform_buf = uniform_u32_words(
            device,
            "codegen.x86.const_value_status.uniform",
            &[1, 0, u32::MAX, 0],
        );
        let param_reg_record_words = token_words
            .saturating_mul(5)
            .saturating_add(hir_words);
        let param_reg_record_buf = storage_u32_copy(
            device,
            "codegen.x86.param_reg_record",
            param_reg_record_words,
        );
        let param_reg_status_buf = storage_u32_copy(device, "codegen.x86.param_reg_status", 4);
        let param_reg_status_uniform_buf = uniform_u32_words(
            device,
            "codegen.x86.param_reg_status.uniform",
            &[1, 0, u32::MAX, 0],
        );
        let local_literal_record_buf =
            storage_u32_copy(device, "codegen.x86.local_literal_record", token_words * 3);
        let local_literal_status_buf =
            storage_u32_copy(device, "codegen.x86.local_literal_status", 4);
        let local_literal_status_uniform_buf = uniform_u32_words(
            device,
            "codegen.x86.local_literal_status.uniform",
            &[1, 0, u32::MAX, 0],
        );
        let node_inst_order_record_words =
            x86_node_inst_order_record_words(hir_words, inst_capacity, token_words);
        let node_inst_order_record_buf = storage_u32_copy(
            device,
            "codegen.x86.node_inst_order_record",
            node_inst_order_record_words,
        );
        let call_arg_lookup_record_buf = storage_u32_copy(
            device,
            "codegen.x86.call_arg_lookup_record",
            token_words * 4,
        );
        // Match-pattern owner records are consumed before call projection.
        // Reuse that HIR-sized table for per-call intrinsic metadata.
        let intrinsic_call_record_buf = &match_pattern_owner_buf;
        let intrinsic_call_status_buf =
            storage_u32_copy(device, "codegen.x86.intrinsic_call_status", 4);
        let call_abi_record_buf =
            storage_u32_copy(device, "codegen.x86.call_abi_record", token_words * 2);
        let call_abi_status_buf = storage_u32_copy(device, "codegen.x86.call_abi_status", 4);
        let call_abi_status_uniform_buf = uniform_u32_words(
            device,
            "codegen.x86.call_abi_status.uniform",
            &[1, 0, u32::MAX, 0],
        );
        // Call type records are consumed by call ABI classification before
        // instruction planning begins. Reuse that HIR-sized table for node
        // instruction counts, then for virtual parameter masks after location
        // planning consumes the counts.
        let node_inst_count_record_buf = &call_type_record_buf;
        // Node instruction counts are consumed before virtual parameter mask
        // materialization. Reuse this HIR-sized table once instruction
        // location planning has finished.
        let func_param_reg_mask_buf = &node_inst_count_record_buf;
        // Function-owner propagation completes before same-end rank init, so
        // reuse that stage's link ping-pong buffers instead of allocating a
        // separate pair of HIR-sized temporaries.
        let node_func_owner_link_a_buf = &node_inst_same_end_link_a_buf;
        let node_func_owner_link_b_buf = &node_inst_same_end_link_b_buf;
        let node_func_owner_needs_copyback = node_func_owner_steps.len() % 2 != 0;
        let final_node_func_buf = &node_func_buf;
        // Match-pattern candidate records are finalized before node instruction
        // ordering begins. Reuse those HIR-sized scratch buffers for the later
        // same-end rank and ordering scratch arrays.
        let expr_resolved_a_buf = &match_pattern_node_owner_buf;
        let expr_resolved_b_buf = &match_pattern_node_variant_buf;
        let expr_resolve_link_a_buf = &node_inst_same_end_link_a_buf;
        let expr_resolve_link_b_buf = &node_inst_same_end_link_b_buf;
        let expr_resolved_step_final_buf = if expr_resolve_steps.len() % 2 == 0 {
            expr_resolved_a_buf
        } else {
            expr_resolved_b_buf
        };
        // After node_inst_counts consumes enclosing-return records, reuse those
        // HIR-sized rows to materialize Pareas-style expression numeric types
        // for instruction generation.
        let expr_semantic_type_a_buf = &enclosing_return_node_a_buf;
        let expr_semantic_type_b_buf = &enclosing_return_node_b_buf;
        let expr_semantic_type_link_a_buf = &node_inst_same_end_link_a_buf;
        let expr_semantic_type_link_b_buf = &node_inst_same_end_link_b_buf;
        let expr_semantic_type_final_buf = if expr_semantic_type_steps.len() % 2 == 0 {
            expr_semantic_type_a_buf
        } else {
            expr_semantic_type_b_buf
        };
        let enclosing_return_link_a_buf = &node_inst_same_end_link_a_buf;
        let enclosing_return_link_b_buf = &node_inst_same_end_link_b_buf;
        let enclosing_return_step_final_buf = if enclosing_return_steps.len() % 2 == 0 {
            &enclosing_return_node_a_buf
        } else {
            &enclosing_return_node_b_buf
        };
        let enclosing_let_link_a_buf = &node_inst_same_end_link_a_buf;
        let enclosing_let_link_b_buf = &node_inst_same_end_link_b_buf;
        let enclosing_let_needs_copyback = enclosing_let_steps.len() % 2 != 0;
        let enclosing_let_step_final_buf = &enclosing_let_node_a_buf;
        let match_result_owner_step_final_buf = if match_result_owner_steps.len() % 2 == 0 {
            match_result_owner_a_buf
        } else {
            match_result_owner_b_buf
        };
        let enclosing_stmt_node_a_buf = &match_pattern_first_variant_node_buf;
        let enclosing_stmt_node_b_buf = &match_pattern_first_payload_node_buf;
        let enclosing_stmt_link_a_buf = &node_inst_same_end_link_a_buf;
        let enclosing_stmt_link_b_buf = &node_inst_same_end_link_b_buf;
        let enclosing_stmt_step_final_buf = if enclosing_stmt_steps.len() % 2 == 0 {
            enclosing_stmt_node_a_buf
        } else {
            enclosing_stmt_node_b_buf
        };
        let call_callee_owner_call_a_buf = &match_pattern_first_variant_node_buf;
        let call_callee_owner_call_b_buf = &match_pattern_first_payload_node_buf;
        let call_callee_owner_link_a_buf = &node_inst_same_end_link_a_buf;
        let call_callee_owner_link_b_buf = &node_inst_same_end_link_b_buf;
        let call_callee_owner_step_final_buf = if call_callee_owner_steps.len() % 2 == 0 {
            call_callee_owner_call_a_buf
        } else {
            call_callee_owner_call_b_buf
        };
        let match_pattern_owner_a_buf = &match_pattern_node_owner_buf;
        let match_pattern_owner_b_buf = &match_pattern_node_variant_buf;
        let match_pattern_owner_link_a_buf = &node_inst_same_end_link_a_buf;
        let match_pattern_owner_link_b_buf = &node_inst_same_end_link_b_buf;
        let match_pattern_owner_step_final_buf = if match_pattern_owner_steps.len() % 2 == 0 {
            match_pattern_owner_a_buf
        } else {
            match_pattern_owner_b_buf
        };
        let node_inst_same_end_rank_a_buf = &match_pattern_node_owner_buf;
        let node_inst_same_end_rank_b_buf = &match_pattern_node_variant_buf;
        let node_inst_same_end_rank_final_buf = if node_inst_same_end_rank_steps.len() % 2 == 0 {
            node_inst_same_end_rank_a_buf
        } else {
            node_inst_same_end_rank_b_buf
        };
        let enclosing_loop_node_a_buf = &match_pattern_node_owner_buf;
        let enclosing_loop_node_b_buf = &match_pattern_node_variant_buf;
        let enclosing_loop_link_a_buf = &node_inst_same_end_link_a_buf;
        let enclosing_loop_link_b_buf = &node_inst_same_end_link_b_buf;
        let enclosing_loop_step_final_buf = if enclosing_loop_steps.len() % 2 == 0 {
            enclosing_loop_node_a_buf
        } else {
            enclosing_loop_node_b_buf
        };
        let node_inst_same_end_bucket_count_buf = &match_pattern_first_use_node_buf;
        // Call records are no longer read after node instruction counts. The
        // slot-bounds pass and the later location pass run sequentially, so
        // they can reuse the same HIR-sized storage.
        let node_inst_subtree_slot_bounds_buf = &call_record_buf;
        let node_inst_scan_input_buf = &func_owner_scan_local_prefix_buf;
        let node_inst_count_status_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_count_status", 4);
        let node_inst_order_status_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_order_status", 4);
        let node_inst_scan_local_prefix_buf = storage_u32_copy(
            device,
            "codegen.x86.node_inst_scan_local_prefix",
            node_inst_scan_words,
        );
        let node_inst_scan_block_sum_buf = &func_owner_scan_block_sum_buf;
        let node_inst_scan_prefix_a_buf = &func_owner_scan_prefix_a_buf;
        let node_inst_scan_prefix_b_buf = &func_owner_scan_prefix_b_buf;
        let node_inst_range_record_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_range_record", hir_words * 2);
        let node_inst_range_status_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_range_status", 4);
        // The ordered instruction-count table is no longer read after
        // node_inst_prefix_scan. Reuse it for finalized subtree bounds, which
        // are produced by the next pass and consumed by instruction generation.
        let node_inst_subtree_bounds_buf = &node_inst_order_record_buf;
        let node_inst_subtree_bounds_status_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_subtree_bounds_status", 4);
        let node_inst_location_record_buf = &call_record_buf;
        let node_inst_location_status_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_location_status", 4);
        let node_inst_gen_input_status_buf =
            storage_u32_copy(device, "codegen.x86.node_inst_gen_input_status", 4);
        let virtual_inst_record_buf =
            storage_u32_copy(device, "codegen.x86.virtual_inst_record", inst_capacity * 4);
        let virtual_inst_args_buf =
            storage_u32_copy(device, "codegen.x86.virtual_inst_args", inst_capacity * 4);
        let virtual_inst_status_buf =
            storage_u32_copy(device, "codegen.x86.virtual_inst_status", 4);
        // Call argument lookup and ABI records are dead after instruction
        // generation. Reuse their token-indexed storage for virtual row bounds,
        // initialized immediately before the row-bound scatter pass.
        let virtual_func_first_row_buf = &call_arg_lookup_record_buf;
        let virtual_func_last_row_buf = &call_abi_record_buf;
        let virtual_func_first_row_status_buf =
            storage_u32_copy(device, "codegen.x86.virtual_func_first_row_status", 4);
        let virtual_live_start_buf =
            storage_u32_copy(device, "codegen.x86.virtual_live_start", inst_capacity);
        let virtual_live_end_buf =
            storage_u32_copy(device, "codegen.x86.virtual_live_end", inst_capacity);
        let virtual_liveness_status_buf =
            storage_u32_copy(device, "codegen.x86.virtual_liveness_status", 4);
        let virtual_next_call_a_buf =
            storage_u32_copy(device, "codegen.x86.virtual_next_call.a", inst_capacity);
        let virtual_next_call_b_buf =
            storage_u32_copy(device, "codegen.x86.virtual_next_call.b", inst_capacity);
        let virtual_next_call_status_buf =
            storage_u32_copy(device, "codegen.x86.virtual_next_call_status", 4);
        let func_param_reg_mask_status_buf =
            storage_u32_copy(device, "codegen.x86.func_param_reg_mask_status", 4);
        // The node-order/subtree-bounds scratch is dead after instruction
        // generation. Register allocation reuses it for per-function active
        // register ends.
        let virtual_regalloc_active_end_buf = &node_inst_order_record_buf;
        let virtual_phys_reg_buf =
            storage_u32_copy(device, "codegen.x86.virtual_phys_reg", inst_capacity);
        let virtual_regalloc_status_buf =
            storage_u32_copy(device, "codegen.x86.virtual_regalloc_status", 4);
        // Register allocation is the last consumer of liveness and next-call
        // scratch records. Selection overwrites every selected instruction row,
        // so reuse those inst-sized buffers for final instruction fields.
        let inst_kind_buf = &virtual_live_start_buf;
        let inst_arg0_buf = &virtual_live_end_buf;
        let inst_arg1_buf = &virtual_next_call_a_buf;
        let inst_arg2_buf = &virtual_next_call_b_buf;
        let select_status_buf = storage_u32_copy(device, "codegen.x86.select_status", 4);
        let inst_size_buf = &virtual_phys_reg_buf;
        let size_status_buf = storage_u32_copy(device, "codegen.x86.size_status", 4);
        // Selection is the final consumer of virtual instruction records and
        // args. Text emission reuses those inst-sized tables for byte offsets
        // and scan-local prefixes.
        let inst_byte_offset_buf = &virtual_inst_record_buf;
        let text_len_buf = storage_u32_copy(device, "codegen.x86.text_len", 1);
        let text_status_buf = storage_u32_copy(device, "codegen.x86.text_status", 4);
        let text_scan_words = inst_capacity;
        let text_scan_blocks = text_scan_words.div_ceil(256).max(1);
        let text_scan_local_prefix_buf = &virtual_inst_args_buf;
        let text_scan_block_sum_buf =
            storage_u32_copy(device, "codegen.x86.text_scan_block_sum", text_scan_blocks);
        let text_scan_prefix_a_buf =
            storage_u32_copy(device, "codegen.x86.text_scan_prefix_a", text_scan_blocks);
        let text_scan_prefix_b_buf =
            storage_u32_copy(device, "codegen.x86.text_scan_prefix_b", text_scan_blocks);
        let encode_status_buf = storage_u32_copy(device, "codegen.x86.encode_status", 4);
        let elf_layout_buf = storage_u32_copy(device, "codegen.x86.elf_layout", 8);
        let layout_status_buf = storage_u32_copy(device, "codegen.x86.layout_status", 4);
        let status_buf = storage_u32_copy(device, "codegen.x86.status", 4);
        let out_buf = storage_u32_copy(device, "codegen.x86.out_words", output_words);
        let output_readback_bytes = (output_words.max(1) * 4) as u64;
        let output_status_offset = output_readback_bytes;
        let output_readback = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.codegen.x86.out_words_and_status"),
            size: output_readback_bytes + 16,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let trace_status_words = 84usize;
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
        host_timer.stamp("scratch_buffers");
        let func_owner_scan_steps = scan_steps_for_blocks(func_owner_scan_blocks);
        let func_owner_scan_params_bufs = func_owner_scan_steps
            .iter()
            .map(|step| {
                let params = X86ScanParams {
                    n_items: hir_words as u32,
                    n_blocks: func_owner_scan_blocks as u32,
                    scan_step: *step,
                    inst_capacity: inst_capacity as u32,
                };
                let bytes = x86_scan_params_bytes(&params);
                uniform_u32_struct(
                    device,
                    &format!("codegen.x86.func_owner_scan.params.{step}"),
                    &bytes,
                )
            })
            .collect::<Vec<_>>();
        let final_func_owner_scan_prefix_buf = if (func_owner_scan_params_bufs.len() - 1) % 2 == 0 {
            &func_owner_scan_prefix_a_buf
        } else {
            &func_owner_scan_prefix_b_buf
        };
        let node_inst_scan_steps = scan_steps_for_blocks(node_inst_scan_blocks);
        let node_inst_scan_params_bufs = node_inst_scan_steps
            .iter()
            .map(|step| {
                let params = X86ScanParams {
                    n_items: node_inst_scan_words as u32,
                    n_blocks: node_inst_scan_blocks as u32,
                    scan_step: *step,
                    inst_capacity: inst_capacity as u32,
                };
                let bytes = x86_scan_params_bytes(&params);
                uniform_u32_struct(
                    device,
                    &format!("codegen.x86.node_inst_scan.params.{step}"),
                    &bytes,
                )
            })
            .collect::<Vec<_>>();
        let final_node_inst_scan_prefix_buf = if (node_inst_scan_params_bufs.len() - 1) % 2 == 0 {
            &node_inst_scan_prefix_a_buf
        } else {
            &node_inst_scan_prefix_b_buf
        };
        let text_scan_steps = scan_steps_for_blocks(text_scan_blocks);
        let text_scan_params_bufs = text_scan_steps
            .iter()
            .map(|step| {
                let params = X86ScanParams {
                    n_items: text_scan_words as u32,
                    n_blocks: text_scan_blocks as u32,
                    scan_step: *step,
                    inst_capacity: inst_capacity as u32,
                };
                let bytes = x86_scan_params_bytes(&params);
                uniform_u32_struct(
                    device,
                    &format!("codegen.x86.text_scan.params.{step}"),
                    &bytes,
                )
            })
            .collect::<Vec<_>>();
        let virtual_next_call_params_bufs = virtual_next_call_steps
            .iter()
            .map(|step| {
                let params = X86ScanParams {
                    n_items: inst_capacity as u32,
                    n_blocks: 0,
                    scan_step: *step,
                    inst_capacity: inst_capacity as u32,
                };
                let bytes = x86_scan_params_bytes(&params);
                uniform_u32_struct(
                    device,
                    &format!("codegen.x86.virtual_next_call.params.{step}"),
                    &bytes,
                )
            })
            .collect::<Vec<_>>();
        let virtual_regalloc_params_bufs = (0..virtual_regalloc_chunk_count)
            .map(|chunk_i| {
                let params = X86RegallocParams {
                    chunk_start: chunk_i
                        .saturating_mul(X86_REGALLOC_ROWS_PER_CHUNK)
                        .min(u32::MAX as usize) as u32,
                    chunk_len: X86_REGALLOC_ROWS_PER_CHUNK as u32,
                    init_status: u32::from(chunk_i == 0),
                    reserved: 0,
                };
                let bytes = x86_regalloc_params_bytes(&params);
                uniform_u32_struct(
                    device,
                    &format!("codegen.x86.virtual_regalloc.params.{chunk_i}"),
                    &bytes,
                )
            })
            .collect::<Vec<_>>();
        host_timer.stamp("scan_params");

        host_timer.stamp("uniform_buffers_initialized");
        macro_rules! init_repeated {
            ($label:literal, $buffer:expr, $pattern:expr, $repeats:expr $(,)?) => {
                init_repeated_u32_words(
                    device,
                    queue,
                    encoder,
                    &self.fill_u32_pass,
                    $label,
                    $buffer,
                    $pattern,
                    $repeats,
                )?
            };
        }
        include!("record_init.rs");
        host_timer.stamp("initializers_recorded");

        let active_scan_dispatch_args_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.active_scan_dispatch_args.bind_group"),
            &self.active_scan_dispatch_args_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                (
                    "active_hir_count_dispatch_args",
                    active_hir_count_dispatch_args_buf.as_entire_binding(),
                ),
                (
                    "active_hir_plus_one_dispatch_args",
                    active_hir_plus_one_dispatch_args_buf.as_entire_binding(),
                ),
                (
                    "active_hir_scan_block_dispatch_args",
                    active_hir_scan_block_dispatch_args_buf.as_entire_binding(),
                ),
            ],
        )?;
        let node_inst_scan_input_clear_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.node_inst_scan_input.active_clear.bind_group"),
            &self.active_clear_u32_pass,
            0,
            &[
                (
                    "active_dispatch_args",
                    active_hir_plus_one_dispatch_args_buf.as_entire_binding(),
                ),
                ("target", node_inst_scan_input_buf.as_entire_binding()),
            ],
        )?;
        let call_callee_root_call_clear_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.call_callee_root_call.active_clear.bind_group"),
            &self.active_clear_u32_pass,
            0,
            &[
                (
                    "active_dispatch_args",
                    active_hir_count_dispatch_args_buf.as_entire_binding(),
                ),
                ("target", call_callee_root_call_buf.as_entire_binding()),
            ],
        )?;
        let node_order_dispatch_args_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.node_order_dispatch_args.bind_group"),
            &self.node_order_dispatch_args_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "x86_node_inst_order_status",
                    node_inst_order_status_buf.as_entire_binding(),
                ),
                (
                    "active_node_order_scan_dispatch_args",
                    active_node_order_scan_dispatch_args_buf.as_entire_binding(),
                ),
                (
                    "active_node_order_scan_block_dispatch_args",
                    active_node_order_scan_block_dispatch_args_buf.as_entire_binding(),
                ),
            ],
        )?;
        let virtual_dispatch_args_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.virtual_dispatch_args.bind_group"),
            &self.virtual_dispatch_args_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "x86_virtual_inst_status",
                    virtual_inst_status_buf.as_entire_binding(),
                ),
                ("x86_func_meta", func_meta_buf.as_entire_binding()),
                (
                    "active_function_dispatch_args",
                    active_function_dispatch_args_buf.as_entire_binding(),
                ),
                (
                    "active_virtual_inst_dispatch_args",
                    active_virtual_inst_dispatch_args_buf.as_entire_binding(),
                ),
                (
                    "active_virtual_next_call_dispatch_args",
                    active_virtual_next_call_dispatch_args_buf.as_entire_binding(),
                ),
                (
                    "active_virtual_regalloc_dispatch_args",
                    active_virtual_regalloc_dispatch_args_buf.as_entire_binding(),
                ),
                (
                    "active_selected_inst_dispatch_args",
                    active_selected_inst_dispatch_args_buf.as_entire_binding(),
                ),
                (
                    "active_selected_scan_block_dispatch_args",
                    active_selected_scan_block_dispatch_args_buf.as_entire_binding(),
                ),
            ],
        )?;
        let output_dispatch_args_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.output_dispatch_args.bind_group"),
            &self.output_dispatch_args_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("x86_text_len", text_len_buf.as_entire_binding()),
                ("text_status", text_status_buf.as_entire_binding()),
                (
                    "active_text_word_dispatch_args",
                    active_text_word_dispatch_args_buf.as_entire_binding(),
                ),
                (
                    "active_elf_header_word_dispatch_args",
                    active_elf_header_word_dispatch_args_buf.as_entire_binding(),
                ),
            ],
        )?;

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
                    "hir_node_decl_token",
                    function_metadata.node_decl_token.as_entire_binding(),
                ),
                (
                    "hir_node_name_token",
                    function_metadata.node_name_token.as_entire_binding(),
                ),
                (
                    "hir_token_pos",
                    function_metadata.hir_token_pos.as_entire_binding(),
                ),
                (
                    "fn_entrypoint_tag",
                    fn_entrypoint_tag_buf.as_entire_binding(),
                ),
                ("x86_func_meta", func_meta_buf.as_entire_binding()),
                ("x86_node_func", node_func_buf.as_entire_binding()),
                (
                    "x86_decl_node_by_token",
                    decl_node_by_token_buf.as_entire_binding(),
                ),
                (
                    "x86_func_slot_by_index",
                    func_slot_by_index_buf.as_entire_binding(),
                ),
            ],
        )?;
        let func_owner_scan_local_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.func_owner_scan_local.bind_group"),
            &self.func_owner_scan_local_pass,
            0,
            &[
                ("gScan", func_owner_scan_params_bufs[0].as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                (
                    "x86_func_owner_scan_local_prefix",
                    func_owner_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "x86_func_owner_scan_block_sum",
                    func_owner_scan_block_sum_buf.as_entire_binding(),
                ),
            ],
        )?;
        let func_owner_scan_block_bind_groups = func_owner_scan_params_bufs
            .iter()
            .enumerate()
            .map(|(step_i, params_buf)| {
                let input_buf = if step_i % 2 == 0 {
                    &func_owner_scan_prefix_b_buf
                } else {
                    &func_owner_scan_prefix_a_buf
                };
                let output_buf = if step_i % 2 == 0 {
                    &func_owner_scan_prefix_a_buf
                } else {
                    &func_owner_scan_prefix_b_buf
                };
                reflected_bind_group(
                    device,
                    Some("codegen.x86.func_owner_scan_blocks.bind_group"),
                    &self.func_owner_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", params_buf.as_entire_binding()),
                        (
                            "x86_func_owner_scan_block_sum",
                            func_owner_scan_block_sum_buf.as_entire_binding(),
                        ),
                        (
                            "x86_func_owner_scan_block_prefix_in",
                            input_buf.as_entire_binding(),
                        ),
                        (
                            "x86_func_owner_scan_block_prefix_out",
                            output_buf.as_entire_binding(),
                        ),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let func_assign_nodes_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.func_assign_nodes.bind_group"),
            &self.func_assign_nodes_pass,
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
                    "x86_func_owner_scan_local_prefix",
                    func_owner_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "x86_func_owner_scan_block_prefix",
                    final_func_owner_scan_prefix_buf.as_entire_binding(),
                ),
                ("x86_node_func", node_func_buf.as_entire_binding()),
                (
                    "x86_func_owner_link",
                    node_func_owner_link_a_buf.as_entire_binding(),
                ),
            ],
        )?;
        let func_assign_nodes_step_bind_groups = node_func_owner_steps
            .iter()
            .enumerate()
            .map(|(step_i, _step)| {
                let (link_in, owner_in, link_out, owner_out) = if step_i % 2 == 0 {
                    (
                        node_func_owner_link_a_buf,
                        &node_func_buf,
                        node_func_owner_link_b_buf,
                        node_func_owner_b_buf,
                    )
                } else {
                    (
                        node_func_owner_link_b_buf,
                        node_func_owner_b_buf,
                        node_func_owner_link_a_buf,
                        &node_func_buf,
                    )
                };
                reflected_bind_group(
                    device,
                    Some("codegen.x86.func_assign_nodes_step.bind_group"),
                    &self.func_assign_nodes_step_pass,
                    0,
                    &[
                        ("gParams", params_buf.as_entire_binding()),
                        ("hir_status", hir_status_buf.as_entire_binding()),
                        (
                            "x86_node_tree_status",
                            node_tree_status_buf.as_entire_binding(),
                        ),
                        ("x86_func_owner_link_in", link_in.as_entire_binding()),
                        ("x86_node_func_in", owner_in.as_entire_binding()),
                        ("x86_func_owner_link_out", link_out.as_entire_binding()),
                        ("x86_node_func_out", owner_out.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let expr_resolve_init_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.expr_resolve_init.bind_group"),
            &self.expr_resolve_init_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                (
                    "x86_expr_resolved_node",
                    expr_resolved_a_buf.as_entire_binding(),
                ),
                (
                    "x86_expr_resolve_link",
                    expr_resolve_link_a_buf.as_entire_binding(),
                ),
            ],
        )?;
        let expr_resolve_step_bind_groups = expr_resolve_steps
            .iter()
            .enumerate()
            .map(|(step_i, _step)| {
                let (resolved_in, link_in, resolved_out, link_out) = if step_i % 2 == 0 {
                    (
                        expr_resolved_a_buf,
                        expr_resolve_link_a_buf,
                        expr_resolved_b_buf,
                        expr_resolve_link_b_buf,
                    )
                } else {
                    (
                        expr_resolved_b_buf,
                        expr_resolve_link_b_buf,
                        expr_resolved_a_buf,
                        expr_resolve_link_a_buf,
                    )
                };
                reflected_bind_group(
                    device,
                    Some("codegen.x86.expr_resolve_step.bind_group"),
                    &self.expr_resolve_step_pass,
                    0,
                    &[
                        ("gParams", params_buf.as_entire_binding()),
                        ("hir_status", hir_status_buf.as_entire_binding()),
                        ("x86_expr_resolved_node_in", resolved_in.as_entire_binding()),
                        ("x86_expr_resolve_link_in", link_in.as_entire_binding()),
                        (
                            "x86_expr_resolved_node_out",
                            resolved_out.as_entire_binding(),
                        ),
                        ("x86_expr_resolve_link_out", link_out.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let enum_records_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.enum_records.bind_group"),
            &self.enum_records_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                (
                    "x86_expr_resolved_node",
                    expr_resolved_final_buf.as_entire_binding(),
                ),
                (
                    "hir_item_decl_token",
                    enum_metadata.item_decl_token.as_entire_binding(),
                ),
                (
                    "hir_variant_parent_enum",
                    enum_metadata.variant_parent_enum.as_entire_binding(),
                ),
                (
                    "hir_variant_ordinal",
                    enum_metadata.variant_ordinal.as_entire_binding(),
                ),
                (
                    "hir_variant_payload_count",
                    enum_metadata.variant_payload_count.as_entire_binding(),
                ),
                (
                    "hir_call_callee_node",
                    call_metadata.callee_node.as_entire_binding(),
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
                    "decl_count_out",
                    enum_metadata.decl_count_out.as_entire_binding(),
                ),
                ("visible_decl", visible_decl_buf.as_entire_binding()),
                ("decl_kind", enum_metadata.decl_kind.as_entire_binding()),
                (
                    "decl_name_token",
                    enum_metadata.decl_name_token.as_entire_binding(),
                ),
                (
                    "decl_id_by_name_token",
                    enum_metadata.decl_id_by_name_token.as_entire_binding(),
                ),
                (
                    "decl_hir_node",
                    enum_metadata.decl_hir_node.as_entire_binding(),
                ),
                (
                    "decl_parent_type_decl",
                    enum_metadata.decl_parent_type_decl.as_entire_binding(),
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
            ],
        )?;
        let match_records_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.match_records.bind_group"),
            &self.match_records_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "hir_match_scrutinee_node",
                    enum_metadata.match_scrutinee_node.as_entire_binding(),
                ),
                (
                    "hir_match_arm_start",
                    enum_metadata.match_arm_start.as_entire_binding(),
                ),
                (
                    "hir_match_arm_count",
                    enum_metadata.match_arm_count.as_entire_binding(),
                ),
                (
                    "hir_match_arm_next",
                    enum_metadata.match_arm_next.as_entire_binding(),
                ),
                (
                    "hir_match_arm_pattern_node",
                    enum_metadata.match_arm_pattern_node.as_entire_binding(),
                ),
                (
                    "hir_match_arm_payload_start",
                    enum_metadata.match_arm_payload_start.as_entire_binding(),
                ),
                (
                    "hir_match_arm_payload_count",
                    enum_metadata.match_arm_payload_count.as_entire_binding(),
                ),
                (
                    "hir_match_arm_result_node",
                    enum_metadata.match_arm_result_node.as_entire_binding(),
                ),
                (
                    "hir_token_pos",
                    enum_metadata.hir_token_pos.as_entire_binding(),
                ),
                ("x86_match_record", match_record_buf.as_entire_binding()),
                (
                    "x86_match_result_value_owner",
                    match_result_value_owner_buf.as_entire_binding(),
                ),
                (
                    "x86_match_arm_owner",
                    match_arm_owner_buf.as_entire_binding(),
                ),
            ],
        )?;
        let match_pattern_records_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.match_pattern_records.bind_group"),
            &self.match_pattern_records_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                (
                    "x86_expr_resolved_node",
                    expr_resolved_final_buf.as_entire_binding(),
                ),
                (
                    "hir_call_callee_node",
                    call_metadata.callee_node.as_entire_binding(),
                ),
                ("visible_decl", visible_decl_buf.as_entire_binding()),
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
                    "decl_count_out",
                    enum_metadata.decl_count_out.as_entire_binding(),
                ),
                ("decl_kind", enum_metadata.decl_kind.as_entire_binding()),
                (
                    "decl_name_token",
                    enum_metadata.decl_name_token.as_entire_binding(),
                ),
                (
                    "decl_id_by_name_token",
                    enum_metadata.decl_id_by_name_token.as_entire_binding(),
                ),
                (
                    "decl_hir_node",
                    enum_metadata.decl_hir_node.as_entire_binding(),
                ),
                (
                    "decl_parent_type_decl",
                    enum_metadata.decl_parent_type_decl.as_entire_binding(),
                ),
                (
                    "hir_variant_ordinal",
                    enum_metadata.variant_ordinal.as_entire_binding(),
                ),
                ("x86_match_record", match_record_buf.as_entire_binding()),
                (
                    "x86_match_pattern_node_owner",
                    match_pattern_node_owner_buf.as_entire_binding(),
                ),
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
            ],
        )?;
        let enclosing_return_init_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.enclosing_return_init.bind_group"),
            &self.enclosing_return_init_pass,
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
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
                ),
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
        let enclosing_return_step_bind_groups = enclosing_return_steps
            .iter()
            .enumerate()
            .map(|(step_i, _step)| {
                let (node_in, link_in, node_out, link_out) = if step_i % 2 == 0 {
                    (
                        &enclosing_return_node_a_buf,
                        enclosing_return_link_a_buf,
                        &enclosing_return_node_b_buf,
                        enclosing_return_link_b_buf,
                    )
                } else {
                    (
                        &enclosing_return_node_b_buf,
                        enclosing_return_link_b_buf,
                        &enclosing_return_node_a_buf,
                        enclosing_return_link_a_buf,
                    )
                };
                reflected_bind_group(
                    device,
                    Some("codegen.x86.enclosing_return_step.bind_group"),
                    &self.enclosing_return_step_pass,
                    0,
                    &[
                        ("gParams", params_buf.as_entire_binding()),
                        ("hir_status", hir_status_buf.as_entire_binding()),
                        ("x86_enclosing_return_node_in", node_in.as_entire_binding()),
                        ("x86_enclosing_return_link_in", link_in.as_entire_binding()),
                        (
                            "x86_enclosing_return_node_out",
                            node_out.as_entire_binding(),
                        ),
                        (
                            "x86_enclosing_return_link_out",
                            link_out.as_entire_binding(),
                        ),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let enclosing_let_init_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.enclosing_let_init.bind_group"),
            &self.enclosing_let_init_pass,
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
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
                ),
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
        let enclosing_let_step_bind_groups = enclosing_let_steps
            .iter()
            .enumerate()
            .map(|(step_i, _step)| {
                let (node_in, link_in, node_out, link_out) = if step_i % 2 == 0 {
                    (
                        &enclosing_let_node_a_buf,
                        enclosing_let_link_a_buf,
                        &enclosing_let_node_b_buf,
                        enclosing_let_link_b_buf,
                    )
                } else {
                    (
                        &enclosing_let_node_b_buf,
                        enclosing_let_link_b_buf,
                        &enclosing_let_node_a_buf,
                        enclosing_let_link_a_buf,
                    )
                };
                reflected_bind_group(
                    device,
                    Some("codegen.x86.enclosing_let_step.bind_group"),
                    &self.enclosing_let_step_pass,
                    0,
                    &[
                        ("gParams", params_buf.as_entire_binding()),
                        ("hir_status", hir_status_buf.as_entire_binding()),
                        ("x86_enclosing_let_node_in", node_in.as_entire_binding()),
                        ("x86_enclosing_let_link_in", link_in.as_entire_binding()),
                        ("x86_enclosing_let_node_out", node_out.as_entire_binding()),
                        ("x86_enclosing_let_link_out", link_out.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let enclosing_stmt_init_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.enclosing_stmt_init.bind_group"),
            &self.enclosing_stmt_init_pass,
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
                    "x86_enclosing_stmt_node",
                    enclosing_stmt_node_a_buf.as_entire_binding(),
                ),
                (
                    "x86_enclosing_stmt_link",
                    enclosing_stmt_link_a_buf.as_entire_binding(),
                ),
            ],
        )?;
        let enclosing_stmt_step_bind_groups = enclosing_stmt_steps
            .iter()
            .enumerate()
            .map(|(step_i, _step)| {
                let (node_in, link_in, node_out, link_out) = if step_i % 2 == 0 {
                    (
                        enclosing_stmt_node_a_buf,
                        enclosing_stmt_link_a_buf,
                        enclosing_stmt_node_b_buf,
                        enclosing_stmt_link_b_buf,
                    )
                } else {
                    (
                        enclosing_stmt_node_b_buf,
                        enclosing_stmt_link_b_buf,
                        enclosing_stmt_node_a_buf,
                        enclosing_stmt_link_a_buf,
                    )
                };
                reflected_bind_group(
                    device,
                    Some("codegen.x86.enclosing_stmt_step.bind_group"),
                    &self.enclosing_stmt_step_pass,
                    0,
                    &[
                        ("gParams", params_buf.as_entire_binding()),
                        ("hir_status", hir_status_buf.as_entire_binding()),
                        ("x86_enclosing_stmt_node_in", node_in.as_entire_binding()),
                        ("x86_enclosing_stmt_link_in", link_in.as_entire_binding()),
                        ("x86_enclosing_stmt_node_out", node_out.as_entire_binding()),
                        ("x86_enclosing_stmt_link_out", link_out.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let return_match_records_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.return_match_records.bind_group"),
            &self.return_match_records_pass,
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
                    "x86_expr_resolved_node",
                    expr_resolved_final_buf.as_entire_binding(),
                ),
                (
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
                ),
                (
                    "x86_return_match_node",
                    return_match_node_buf.as_entire_binding(),
                ),
                (
                    "x86_match_return_node",
                    match_return_node_buf.as_entire_binding(),
                ),
            ],
        )?;
        let match_result_owner_init_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.match_result_owner_init.bind_group"),
            &self.match_result_owner_init_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                (
                    "x86_match_result_root_owner",
                    match_result_value_owner_buf.as_entire_binding(),
                ),
                (
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
                ),
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
        let match_result_owner_step_bind_groups = match_result_owner_steps
            .iter()
            .enumerate()
            .map(|(step_i, _step)| {
                let (owner_in, link_in, owner_out, link_out) = if step_i % 2 == 0 {
                    (
                        match_result_owner_a_buf,
                        match_result_owner_link_a_buf,
                        match_result_owner_b_buf,
                        match_result_owner_link_b_buf,
                    )
                } else {
                    (
                        match_result_owner_b_buf,
                        match_result_owner_link_b_buf,
                        match_result_owner_a_buf,
                        match_result_owner_link_a_buf,
                    )
                };
                reflected_bind_group(
                    device,
                    Some("codegen.x86.match_result_owner_step.bind_group"),
                    &self.match_result_owner_step_pass,
                    0,
                    &[
                        ("gParams", params_buf.as_entire_binding()),
                        ("hir_status", hir_status_buf.as_entire_binding()),
                        ("x86_match_result_owner_in", owner_in.as_entire_binding()),
                        (
                            "x86_match_result_owner_link_in",
                            link_in.as_entire_binding(),
                        ),
                        ("x86_match_result_owner_out", owner_out.as_entire_binding()),
                        (
                            "x86_match_result_owner_link_out",
                            link_out.as_entire_binding(),
                        ),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let match_ownership_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.match_ownership.bind_group"),
            &self.match_ownership_pass,
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
                    "x86_expr_resolved_node",
                    expr_resolved_final_buf.as_entire_binding(),
                ),
                (
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
                ),
                (
                    "x86_match_return_node",
                    match_return_node_buf.as_entire_binding(),
                ),
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
        let match_pattern_owner_init_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.match_pattern_owner_init.bind_group"),
            &self.match_pattern_owner_init_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                (
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
                ),
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
        let match_pattern_owner_step_bind_groups = match_pattern_owner_steps
            .iter()
            .enumerate()
            .map(|(step_i, _step)| {
                let (owner_in, link_in, owner_out, link_out) = if step_i % 2 == 0 {
                    (
                        match_pattern_owner_a_buf,
                        match_pattern_owner_link_a_buf,
                        match_pattern_owner_b_buf,
                        match_pattern_owner_link_b_buf,
                    )
                } else {
                    (
                        match_pattern_owner_b_buf,
                        match_pattern_owner_link_b_buf,
                        match_pattern_owner_a_buf,
                        match_pattern_owner_link_a_buf,
                    )
                };
                reflected_bind_group(
                    device,
                    Some("codegen.x86.match_pattern_owner_step.bind_group"),
                    &self.match_pattern_owner_step_pass,
                    0,
                    &[
                        ("gParams", params_buf.as_entire_binding()),
                        ("hir_status", hir_status_buf.as_entire_binding()),
                        (
                            "x86_match_pattern_node_owner_in",
                            owner_in.as_entire_binding(),
                        ),
                        (
                            "x86_match_pattern_owner_link_in",
                            link_in.as_entire_binding(),
                        ),
                        (
                            "x86_match_pattern_node_owner_out",
                            owner_out.as_entire_binding(),
                        ),
                        (
                            "x86_match_pattern_owner_link_out",
                            link_out.as_entire_binding(),
                        ),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let match_pattern_finalize_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.match_pattern_finalize.bind_group"),
            &self.match_pattern_finalize_pass,
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
                ("x86_match_record", match_record_buf.as_entire_binding()),
            ],
        )?;
        let struct_records_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.struct_records.bind_group"),
            &self.struct_records_pass,
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
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
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
        let array_records_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.array_records.bind_group"),
            &self.array_records_pass,
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
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
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
        let decl_widths_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.decl_widths.bind_group"),
            &self.decl_widths_pass,
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
                    "hir_param_record",
                    function_metadata.param_record.as_entire_binding(),
                ),
                (
                    "x86_expr_resolved_node",
                    expr_resolved_final_buf.as_entire_binding(),
                ),
                (
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
                ),
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
            ],
        )?;
        let decl_layout_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.decl_layout.bind_group"),
            &self.decl_layout_pass,
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
                    "hir_param_record",
                    function_metadata.param_record.as_entire_binding(),
                ),
                (
                    "x86_expr_resolved_node",
                    expr_resolved_final_buf.as_entire_binding(),
                ),
                ("x86_node_func", final_node_func_buf.as_entire_binding()),
                (
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
                ),
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
                    "x86_decl_layout_record",
                    decl_layout_record_buf.as_entire_binding(),
                ),
                (
                    "x86_decl_layout_status",
                    decl_layout_status_buf.as_entire_binding(),
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
                (
                    "x86_expr_resolved_node",
                    expr_resolved_final_buf.as_entire_binding(),
                ),
                ("x86_node_func", final_node_func_buf.as_entire_binding()),
                (
                    "hir_call_callee_node",
                    call_metadata.callee_node.as_entire_binding(),
                ),
                (
                    "hir_token_pos",
                    function_metadata.hir_token_pos.as_entire_binding(),
                ),
                (
                    "hir_call_arg_count",
                    call_metadata.arg_count.as_entire_binding(),
                ),
                (
                    "hir_member_name_token",
                    call_metadata.member_name_token.as_entire_binding(),
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
                    "x86_call_callee_root_call",
                    call_callee_root_call_buf.as_entire_binding(),
                ),
                (
                    "call_record_status",
                    call_record_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let call_callee_owner_init_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.call_callee_owner_init.bind_group"),
            &self.call_callee_owner_init_pass,
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
        let call_callee_owner_step_bind_groups = call_callee_owner_steps
            .iter()
            .enumerate()
            .map(|(step_i, _step)| {
                let (owner_in, link_in, owner_out, link_out) = if step_i % 2 == 0 {
                    (
                        call_callee_owner_call_a_buf,
                        call_callee_owner_link_a_buf,
                        call_callee_owner_call_b_buf,
                        call_callee_owner_link_b_buf,
                    )
                } else {
                    (
                        call_callee_owner_call_b_buf,
                        call_callee_owner_link_b_buf,
                        call_callee_owner_call_a_buf,
                        call_callee_owner_link_a_buf,
                    )
                };
                reflected_bind_group(
                    device,
                    Some("codegen.x86.call_callee_owner_step.bind_group"),
                    &self.call_callee_owner_step_pass,
                    0,
                    &[
                        ("gParams", params_buf.as_entire_binding()),
                        ("hir_status", hir_status_buf.as_entire_binding()),
                        (
                            "x86_call_callee_owner_call_in",
                            owner_in.as_entire_binding(),
                        ),
                        ("x86_call_callee_owner_link_in", link_in.as_entire_binding()),
                        (
                            "x86_call_callee_owner_call_out",
                            owner_out.as_entire_binding(),
                        ),
                        (
                            "x86_call_callee_owner_link_out",
                            link_out.as_entire_binding(),
                        ),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let const_values_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.const_values.bind_group"),
            &self.const_values_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
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
                    "hir_node_decl_token",
                    function_metadata.node_decl_token.as_entire_binding(),
                ),
                (
                    "hir_token_pos",
                    function_metadata.hir_token_pos.as_entire_binding(),
                ),
                (
                    "method_decl_param_offset",
                    function_metadata
                        .method_decl_param_offset
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
        let call_arg_values_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.call_arg_values.bind_group"),
            &self.call_arg_values_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                (
                    "x86_expr_resolved_node",
                    expr_resolved_final_buf.as_entire_binding(),
                ),
                ("x86_call_record", call_record_buf.as_entire_binding()),
                (
                    "hir_call_arg_parent_call",
                    call_metadata.arg_parent_call.as_entire_binding(),
                ),
                (
                    "hir_call_arg_ordinal",
                    call_metadata.arg_ordinal.as_entire_binding(),
                ),
                (
                    "hir_call_callee_node",
                    call_metadata.callee_node.as_entire_binding(),
                ),
                (
                    "hir_member_receiver_node",
                    call_metadata.member_receiver_node.as_entire_binding(),
                ),
                (
                    "call_record_status",
                    call_record_status_buf.as_entire_binding(),
                ),
                (
                    "x86_call_arg_lookup_record",
                    call_arg_lookup_record_buf.as_entire_binding(),
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
        let call_abi_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.call_abi.bind_group"),
            &self.call_abi_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                (
                    "x86_decl_node_by_token",
                    decl_node_by_token_buf.as_entire_binding(),
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
                    "type_instance_kind",
                    type_metadata.type_instance_kind.as_entire_binding(),
                ),
                (
                    "type_instance_decl_token",
                    type_metadata.type_instance_decl_token.as_entire_binding(),
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
                    "x86_call_abi_record",
                    call_abi_record_buf.as_entire_binding(),
                ),
                ("call_abi_status", call_abi_status_buf.as_entire_binding()),
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
                    "x86_expr_resolved_node",
                    expr_resolved_final_buf.as_entire_binding(),
                ),
                ("x86_node_func", final_node_func_buf.as_entire_binding()),
                ("visible_decl", visible_decl_buf.as_entire_binding()),
                (
                    "x86_decl_layout_record",
                    decl_layout_record_buf.as_entire_binding(),
                ),
                (
                    "x86_decl_layout_status",
                    decl_layout_status_buf.as_entire_binding(),
                ),
                (
                    "x86_param_reg_record",
                    param_reg_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_tree_status",
                    node_tree_status_buf.as_entire_binding(),
                ),
                (
                    "x86_enclosing_return_node",
                    enclosing_return_step_final_buf.as_entire_binding(),
                ),
                (
                    "x86_return_match_node",
                    return_match_node_buf.as_entire_binding(),
                ),
                (
                    "x86_match_return_node",
                    match_return_node_buf.as_entire_binding(),
                ),
                ("x86_call_record", call_record_buf.as_entire_binding()),
                (
                    "x86_call_callee_owner_call",
                    call_callee_owner_step_final_buf.as_entire_binding(),
                ),
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
                    "x86_enum_value_record",
                    enum_value_record_buf.as_entire_binding(),
                ),
                (
                    "x86_enum_record_status",
                    enum_record_status_buf.as_entire_binding(),
                ),
                ("x86_match_record", match_record_buf.as_entire_binding()),
                (
                    "x86_match_pattern_node_owner",
                    match_pattern_node_owner_buf.as_entire_binding(),
                ),
                (
                    "x86_match_result_value_owner",
                    match_result_value_owner_buf.as_entire_binding(),
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
        let node_inst_same_end_rank_init_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.node_inst_same_end_rank_init.bind_group"),
            &self.node_inst_same_end_rank_init_pass,
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
                    "x86_node_inst_same_end_link",
                    node_inst_same_end_link_a_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_same_end_rank",
                    node_inst_same_end_rank_a_buf.as_entire_binding(),
                ),
            ],
        )?;
        let node_inst_same_end_rank_step_bind_groups = node_inst_same_end_rank_steps
            .iter()
            .enumerate()
            .map(|(step_i, _step)| {
                let (link_in, rank_in, link_out, rank_out) = if step_i % 2 == 0 {
                    (
                        &node_inst_same_end_link_a_buf,
                        &node_inst_same_end_rank_a_buf,
                        &node_inst_same_end_link_b_buf,
                        &node_inst_same_end_rank_b_buf,
                    )
                } else {
                    (
                        &node_inst_same_end_link_b_buf,
                        &node_inst_same_end_rank_b_buf,
                        &node_inst_same_end_link_a_buf,
                        &node_inst_same_end_rank_a_buf,
                    )
                };
                reflected_bind_group(
                    device,
                    Some("codegen.x86.node_inst_same_end_rank_step.bind_group"),
                    &self.node_inst_same_end_rank_step_pass,
                    0,
                    &[
                        ("gParams", params_buf.as_entire_binding()),
                        ("hir_status", hir_status_buf.as_entire_binding()),
                        (
                            "x86_node_inst_same_end_link_in",
                            link_in.as_entire_binding(),
                        ),
                        (
                            "x86_node_inst_same_end_rank_in",
                            rank_in.as_entire_binding(),
                        ),
                        (
                            "x86_node_inst_same_end_link_out",
                            link_out.as_entire_binding(),
                        ),
                        (
                            "x86_node_inst_same_end_rank_out",
                            rank_out.as_entire_binding(),
                        ),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let node_inst_end_counts_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.node_inst_end_counts.bind_group"),
            &self.node_inst_end_counts_pass,
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
                    "x86_node_inst_scan_input",
                    node_inst_scan_input_buf.as_entire_binding(),
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
                    "x86_node_inst_same_end_rank",
                    node_inst_same_end_rank_final_buf.as_entire_binding(),
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
                    "x86_node_inst_order_record",
                    node_inst_order_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_same_end_bucket_count",
                    node_inst_same_end_bucket_count_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_subtree_slot_bounds",
                    node_inst_subtree_slot_bounds_buf.as_entire_binding(),
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
                    "x86_node_inst_count_record",
                    node_inst_count_record_buf.as_entire_binding(),
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
                    "x86_node_inst_same_end_rank",
                    node_inst_same_end_rank_final_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_same_end_bucket_count",
                    node_inst_same_end_bucket_count_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_range_status",
                    node_inst_range_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let node_inst_subtree_bounds_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.node_inst_subtree_bounds.bind_group"),
            &self.node_inst_subtree_bounds_pass,
            0,
            &[
                ("gScan", node_inst_scan_params_bufs[0].as_entire_binding()),
                (
                    "x86_node_inst_subtree_slot_bounds",
                    node_inst_subtree_slot_bounds_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_range_status",
                    node_inst_range_status_buf.as_entire_binding(),
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
                    "x86_node_inst_subtree_bounds_record",
                    node_inst_subtree_bounds_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_subtree_bounds_status",
                    node_inst_subtree_bounds_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let expr_semantic_type_init_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.expr_semantic_type_init.bind_group"),
            &self.expr_semantic_type_init_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                (
                    "hir_token_pos",
                    function_metadata.hir_token_pos.as_entire_binding(),
                ),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                (
                    "x86_expr_resolved_node",
                    expr_resolved_final_buf.as_entire_binding(),
                ),
                ("visible_decl", visible_decl_buf.as_entire_binding()),
                (
                    "visible_type",
                    type_metadata.visible_type.as_entire_binding(),
                ),
                (
                    "call_return_type",
                    call_metadata.call_return_type.as_entire_binding(),
                ),
                (
                    "x86_decl_layout_record",
                    decl_layout_record_buf.as_entire_binding(),
                ),
                (
                    "x86_param_reg_record",
                    param_reg_record_buf.as_entire_binding(),
                ),
                (
                    "x86_expr_semantic_type",
                    expr_semantic_type_a_buf.as_entire_binding(),
                ),
                (
                    "x86_expr_semantic_type_link",
                    expr_semantic_type_link_a_buf.as_entire_binding(),
                ),
            ],
        )?;
        let expr_semantic_type_step_bind_groups = expr_semantic_type_steps
            .iter()
            .enumerate()
            .map(|(step_i, _step)| {
                let (type_in, link_in, type_out, link_out) = if step_i % 2 == 0 {
                    (
                        expr_semantic_type_a_buf,
                        expr_semantic_type_link_a_buf,
                        expr_semantic_type_b_buf,
                        expr_semantic_type_link_b_buf,
                    )
                } else {
                    (
                        expr_semantic_type_b_buf,
                        expr_semantic_type_link_b_buf,
                        expr_semantic_type_a_buf,
                        expr_semantic_type_link_a_buf,
                    )
                };
                reflected_bind_group(
                    device,
                    Some("codegen.x86.expr_semantic_type_step.bind_group"),
                    &self.expr_semantic_type_step_pass,
                    0,
                    &[
                        ("gParams", params_buf.as_entire_binding()),
                        ("hir_status", hir_status_buf.as_entire_binding()),
                        ("x86_expr_semantic_type_in", type_in.as_entire_binding()),
                        (
                            "x86_expr_semantic_type_link_in",
                            link_in.as_entire_binding(),
                        ),
                        ("x86_expr_semantic_type_out", type_out.as_entire_binding()),
                        (
                            "x86_expr_semantic_type_link_out",
                            link_out.as_entire_binding(),
                        ),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
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
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                (
                    "x86_expr_resolved_node",
                    expr_resolved_final_buf.as_entire_binding(),
                ),
                (
                    "x86_expr_semantic_type",
                    expr_semantic_type_final_buf.as_entire_binding(),
                ),
                ("x86_match_record", match_record_buf.as_entire_binding()),
                (
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
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
                    "x86_node_inst_same_end_rank",
                    node_inst_same_end_rank_final_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_same_end_bucket_count",
                    node_inst_same_end_bucket_count_buf.as_entire_binding(),
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
        let enclosing_loop_init_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.enclosing_loop_init.bind_group"),
            &self.enclosing_loop_init_pass,
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
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
                ),
                (
                    "x86_enclosing_loop_node",
                    enclosing_loop_node_a_buf.as_entire_binding(),
                ),
                (
                    "x86_enclosing_loop_link",
                    enclosing_loop_link_a_buf.as_entire_binding(),
                ),
            ],
        )?;
        let enclosing_loop_step_bind_groups = enclosing_loop_steps
            .iter()
            .enumerate()
            .map(|(step_i, _step)| {
                let (node_in, link_in, node_out, link_out) = if step_i % 2 == 0 {
                    (
                        enclosing_loop_node_a_buf,
                        enclosing_loop_link_a_buf,
                        enclosing_loop_node_b_buf,
                        enclosing_loop_link_b_buf,
                    )
                } else {
                    (
                        enclosing_loop_node_b_buf,
                        enclosing_loop_link_b_buf,
                        enclosing_loop_node_a_buf,
                        enclosing_loop_link_a_buf,
                    )
                };
                reflected_bind_group(
                    device,
                    Some("codegen.x86.enclosing_loop_step.bind_group"),
                    &self.enclosing_loop_step_pass,
                    0,
                    &[
                        ("gParams", params_buf.as_entire_binding()),
                        ("hir_status", hir_status_buf.as_entire_binding()),
                        ("x86_enclosing_loop_node_in", node_in.as_entire_binding()),
                        ("x86_enclosing_loop_link_in", link_in.as_entire_binding()),
                        ("x86_enclosing_loop_node_out", node_out.as_entire_binding()),
                        ("x86_enclosing_loop_link_out", link_out.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let node_inst_gen_inputs_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.node_inst_gen_inputs.bind_group"),
            &self.node_inst_gen_inputs_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "x86_node_inst_location_status",
                    node_inst_location_status_buf.as_entire_binding(),
                ),
                (
                    "x86_const_value_status",
                    const_value_status_buf.as_entire_binding(),
                ),
                (
                    "x86_decl_layout_status",
                    decl_layout_status_buf.as_entire_binding(),
                ),
                (
                    "x86_local_literal_status",
                    local_literal_status_buf.as_entire_binding(),
                ),
                (
                    "x86_param_reg_status",
                    param_reg_status_buf.as_entire_binding(),
                ),
                ("call_abi_status", call_abi_status_buf.as_entire_binding()),
                (
                    "x86_struct_record_status",
                    struct_record_status_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_gen_input_status",
                    node_inst_gen_input_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let virtual_inst_clear_dispatch_args_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.virtual_inst_clear_dispatch_args.bind_group"),
            &self.virtual_inst_clear_dispatch_args_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "x86_node_inst_gen_input_status",
                    node_inst_gen_input_status_buf.as_entire_binding(),
                ),
                (
                    "active_virtual_inst_dispatch_args",
                    active_virtual_inst_dispatch_args_buf.as_entire_binding(),
                ),
            ],
        )?;
        let virtual_inst_clear_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.virtual_inst_clear.bind_group"),
            &self.virtual_inst_clear_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "x86_node_inst_gen_input_status",
                    node_inst_gen_input_status_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_record",
                    virtual_inst_record_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_args",
                    virtual_inst_args_buf.as_entire_binding(),
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
                    "hir_expr_int_value",
                    expr_metadata.int_value.as_entire_binding(),
                ),
                ("visible_decl", visible_decl_buf.as_entire_binding()),
                (
                    "x86_decl_layout_record",
                    decl_layout_record_buf.as_entire_binding(),
                ),
                (
                    "x86_const_value_record",
                    const_value_record_buf.as_entire_binding(),
                ),
                (
                    "x86_local_literal_record",
                    local_literal_record_buf.as_entire_binding(),
                ),
                (
                    "x86_param_reg_record",
                    param_reg_record_buf.as_entire_binding(),
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
                    "x86_intrinsic_call_record",
                    intrinsic_call_record_buf.as_entire_binding(),
                ),
                (
                    "x86_enum_value_record",
                    enum_value_record_buf.as_entire_binding(),
                ),
                ("x86_match_record", match_record_buf.as_entire_binding()),
                (
                    "x86_match_arm_owner",
                    match_arm_owner_buf.as_entire_binding(),
                ),
                (
                    "x86_match_result_value_owner",
                    match_result_value_owner_buf.as_entire_binding(),
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
                    "x86_node_inst_range_record",
                    node_inst_range_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_location_record",
                    node_inst_location_record_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_gen_input_status",
                    node_inst_gen_input_status_buf.as_entire_binding(),
                ),
                (
                    "x86_node_inst_subtree_bounds_record",
                    node_inst_subtree_bounds_buf.as_entire_binding(),
                ),
                (
                    "x86_node_tree_record",
                    node_tree_record_buf.as_entire_binding(),
                ),
                (
                    "x86_enclosing_loop_node",
                    enclosing_loop_step_final_buf.as_entire_binding(),
                ),
                (
                    "x86_return_match_node",
                    return_match_node_buf.as_entire_binding(),
                ),
                (
                    "x86_match_return_node",
                    match_return_node_buf.as_entire_binding(),
                ),
                (
                    "x86_enclosing_let_node",
                    enclosing_let_step_final_buf.as_entire_binding(),
                ),
                ("x86_node_func", final_node_func_buf.as_entire_binding()),
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
        let virtual_liveness_init_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.virtual_liveness_init.bind_group"),
            &self.virtual_liveness_init_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "x86_virtual_inst_record",
                    virtual_inst_record_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_status",
                    virtual_inst_status_buf.as_entire_binding(),
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
                    "x86_virtual_phys_reg",
                    virtual_phys_reg_buf.as_entire_binding(),
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
                    "x86_virtual_inst_args",
                    virtual_inst_args_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_status",
                    virtual_inst_status_buf.as_entire_binding(),
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
        let virtual_next_call_bind_groups = virtual_next_call_params_bufs
            .iter()
            .enumerate()
            .map(|(i, scan_params_buf)| {
                let (input, output) = if i == 0 {
                    (&virtual_next_call_b_buf, &virtual_next_call_a_buf)
                } else if i % 2 == 1 {
                    (&virtual_next_call_a_buf, &virtual_next_call_b_buf)
                } else {
                    (&virtual_next_call_b_buf, &virtual_next_call_a_buf)
                };
                reflected_bind_group(
                    device,
                    Some("codegen.x86.virtual_next_calls.bind_group"),
                    &self.virtual_next_calls_pass,
                    0,
                    &[
                        ("gParams", params_buf.as_entire_binding()),
                        ("gScan", scan_params_buf.as_entire_binding()),
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
                        ("x86_node_func", final_node_func_buf.as_entire_binding()),
                        ("x86_virtual_next_call_in", input.as_entire_binding()),
                        ("x86_virtual_next_call_out", output.as_entire_binding()),
                        (
                            "x86_virtual_next_call_status",
                            virtual_next_call_status_buf.as_entire_binding(),
                        ),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let virtual_param_masks_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.virtual_param_masks.bind_group"),
            &self.virtual_param_masks_pass,
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
                ("x86_node_func", final_node_func_buf.as_entire_binding()),
                (
                    "hir_node_decl_token",
                    function_metadata.node_decl_token.as_entire_binding(),
                ),
                (
                    "hir_token_pos",
                    function_metadata.hir_token_pos.as_entire_binding(),
                ),
                (
                    "x86_func_param_reg_mask",
                    func_param_reg_mask_buf.as_entire_binding(),
                ),
                (
                    "x86_func_param_reg_mask_status",
                    func_param_reg_mask_status_buf.as_entire_binding(),
                ),
            ],
        )?;
        let virtual_regalloc_bind_groups = virtual_regalloc_params_bufs
            .iter()
            .map(|regalloc_params_buf| {
                reflected_bind_group(
                    device,
                    Some("codegen.x86.virtual_regalloc.bind_group"),
                    &self.virtual_regalloc_pass,
                    0,
                    &[
                        ("gParams", params_buf.as_entire_binding()),
                        ("gRegalloc", regalloc_params_buf.as_entire_binding()),
                        ("hir_kind", hir_kind_buf.as_entire_binding()),
                        (
                            "x86_decl_node_by_token",
                            decl_node_by_token_buf.as_entire_binding(),
                        ),
                        ("x86_func_meta", func_meta_buf.as_entire_binding()),
                        (
                            "x86_func_slot_by_index",
                            func_slot_by_index_buf.as_entire_binding(),
                        ),
                        (
                            "x86_virtual_inst_record",
                            virtual_inst_record_buf.as_entire_binding(),
                        ),
                        (
                            "x86_virtual_inst_args",
                            virtual_inst_args_buf.as_entire_binding(),
                        ),
                        ("x86_node_func", final_node_func_buf.as_entire_binding()),
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
                            "x86_virtual_next_call_a",
                            virtual_next_call_a_buf.as_entire_binding(),
                        ),
                        (
                            "x86_virtual_next_call_b",
                            virtual_next_call_b_buf.as_entire_binding(),
                        ),
                        (
                            "x86_virtual_next_call_status",
                            virtual_next_call_status_buf.as_entire_binding(),
                        ),
                        (
                            "x86_func_param_reg_mask",
                            func_param_reg_mask_buf.as_entire_binding(),
                        ),
                        (
                            "x86_func_param_reg_mask_status",
                            func_param_reg_mask_status_buf.as_entire_binding(),
                        ),
                        (
                            "x86_func_first_virtual_row",
                            virtual_func_first_row_buf.as_entire_binding(),
                        ),
                        (
                            "x86_func_last_virtual_row",
                            virtual_func_last_row_buf.as_entire_binding(),
                        ),
                        (
                            "x86_func_first_virtual_row_status",
                            virtual_func_first_row_status_buf.as_entire_binding(),
                        ),
                        (
                            "x86_virtual_regalloc_active_end",
                            virtual_regalloc_active_end_buf.as_entire_binding(),
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
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let virtual_func_rows_init_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.virtual_func_rows_init.bind_group"),
            &self.virtual_func_rows_init_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                (
                    "hir_node_decl_token",
                    function_metadata.node_decl_token.as_entire_binding(),
                ),
                (
                    "hir_token_pos",
                    function_metadata.hir_token_pos.as_entire_binding(),
                ),
                (
                    "x86_func_first_virtual_row",
                    virtual_func_first_row_buf.as_entire_binding(),
                ),
                (
                    "x86_func_last_virtual_row",
                    virtual_func_last_row_buf.as_entire_binding(),
                ),
                (
                    "x86_func_param_reg_mask",
                    func_param_reg_mask_buf.as_entire_binding(),
                ),
            ],
        )?;
        let virtual_func_first_row_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.virtual_func_first_row.bind_group"),
            &self.virtual_func_first_row_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "x86_virtual_inst_record",
                    virtual_inst_record_buf.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_status",
                    virtual_inst_status_buf.as_entire_binding(),
                ),
                ("x86_node_func", final_node_func_buf.as_entire_binding()),
                (
                    "hir_node_decl_token",
                    function_metadata.node_decl_token.as_entire_binding(),
                ),
                (
                    "hir_token_pos",
                    function_metadata.hir_token_pos.as_entire_binding(),
                ),
                (
                    "x86_func_first_virtual_row",
                    virtual_func_first_row_buf.as_entire_binding(),
                ),
                (
                    "x86_func_last_virtual_row",
                    virtual_func_last_row_buf.as_entire_binding(),
                ),
                (
                    "x86_func_first_virtual_row_status",
                    virtual_func_first_row_status_buf.as_entire_binding(),
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
                (
                    "x86_func_first_virtual_row",
                    virtual_func_first_row_buf.as_entire_binding(),
                ),
                (
                    "x86_func_first_virtual_row_status",
                    virtual_func_first_row_status_buf.as_entire_binding(),
                ),
                (
                    "x86_decl_layout_status",
                    decl_layout_status_buf.as_entire_binding(),
                ),
                ("x86_func_meta", func_meta_buf.as_entire_binding()),
                ("x86_node_func", final_node_func_buf.as_entire_binding()),
                (
                    "hir_node_decl_token",
                    function_metadata.node_decl_token.as_entire_binding(),
                ),
                ("x86_inst_kind", inst_kind_buf.as_entire_binding()),
                ("x86_inst_arg0", inst_arg0_buf.as_entire_binding()),
                ("x86_inst_arg1", inst_arg1_buf.as_entire_binding()),
                ("x86_inst_arg2", inst_arg2_buf.as_entire_binding()),
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
                (
                    "x86_decl_layout_status",
                    decl_layout_status_buf.as_entire_binding(),
                ),
                ("select_status", select_status_buf.as_entire_binding()),
                ("x86_inst_size", inst_size_buf.as_entire_binding()),
                ("size_status", size_status_buf.as_entire_binding()),
            ],
        )?;
        let text_scan_local_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.text_scan_local.bind_group"),
            &self.text_scan_local_pass,
            0,
            &[
                ("gScan", text_scan_params_bufs[0].as_entire_binding()),
                ("select_status", select_status_buf.as_entire_binding()),
                ("x86_inst_size", inst_size_buf.as_entire_binding()),
                (
                    "x86_text_scan_local_prefix",
                    text_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "x86_text_scan_block_sum",
                    text_scan_block_sum_buf.as_entire_binding(),
                ),
            ],
        )?;
        let text_scan_block_bind_groups = text_scan_params_bufs
            .iter()
            .enumerate()
            .map(|(step_i, params_buf)| {
                let input_buf = if step_i % 2 == 0 {
                    &text_scan_prefix_b_buf
                } else {
                    &text_scan_prefix_a_buf
                };
                let output_buf = if step_i % 2 == 0 {
                    &text_scan_prefix_a_buf
                } else {
                    &text_scan_prefix_b_buf
                };
                reflected_bind_group(
                    device,
                    Some("codegen.x86.text_scan_blocks.bind_group"),
                    &self.node_inst_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", params_buf.as_entire_binding()),
                        (
                            "x86_node_inst_scan_block_sum",
                            text_scan_block_sum_buf.as_entire_binding(),
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
        let final_text_scan_prefix_buf = if (text_scan_params_bufs.len() - 1) % 2 == 0 {
            &text_scan_prefix_a_buf
        } else {
            &text_scan_prefix_b_buf
        };
        let text_offsets_bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.text_offsets.bind_group"),
            &self.text_offsets_pass,
            0,
            &[
                ("gScan", text_scan_params_bufs[0].as_entire_binding()),
                ("x86_inst_size", inst_size_buf.as_entire_binding()),
                ("size_status", size_status_buf.as_entire_binding()),
                (
                    "x86_text_scan_local_prefix",
                    text_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "x86_text_scan_block_prefix",
                    final_text_scan_prefix_buf.as_entire_binding(),
                ),
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
                (
                    "x86_decl_layout_status",
                    decl_layout_status_buf.as_entire_binding(),
                ),
                ("x86_text_len", text_len_buf.as_entire_binding()),
                ("text_status", text_status_buf.as_entire_binding()),
                ("out_words", out_buf.as_entire_binding()),
                ("encode_status", encode_status_buf.as_entire_binding()),
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
                ("encode_status", encode_status_buf.as_entire_binding()),
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
                ("x86_elf_layout", elf_layout_buf.as_entire_binding()),
                ("layout_status", layout_status_buf.as_entire_binding()),
                ("out_words", out_buf.as_entire_binding()),
                ("status", status_buf.as_entire_binding()),
            ],
        )?;
        host_timer.stamp("bind_groups");

        dispatch_x86_stage(
            encoder,
            "active_scan_dispatch_args",
            &self.active_scan_dispatch_args_pass,
            &active_scan_dispatch_args_bind_group,
            (1, 1),
        );
        dispatch_x86_stages_indirect(
            encoder,
            &[
                (
                    "node_tree_info",
                    &self.node_tree_info_pass,
                    &node_tree_info_bind_group,
                ),
                ("func_discover", &self.func_discover_pass, &func_bind_group),
            ],
            active_hir_dispatch_args_buf,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "func_owner_scan_local",
            &self.func_owner_scan_local_pass,
            &func_owner_scan_local_bind_group,
            active_hir_dispatch_args_buf,
        );
        for (step_i, bind_group) in func_owner_scan_block_bind_groups.iter().enumerate() {
            dispatch_compute_pass_indirect(
                encoder,
                &format!("func_owner_scan_blocks.{step_i}"),
                "codegen.x86.func_owner_scan_blocks",
                &self.func_owner_scan_blocks_pass,
                bind_group,
                &active_hir_scan_block_dispatch_args_buf,
            );
        }
        dispatch_x86_stage_indirect(
            encoder,
            "func_assign_nodes",
            &self.func_assign_nodes_pass,
            &func_assign_nodes_bind_group,
            active_hir_dispatch_args_buf,
        );
        for (step_i, bind_group) in func_assign_nodes_step_bind_groups.iter().enumerate() {
            dispatch_compute_pass_indirect(
                encoder,
                &format!("func_assign_nodes_step.{step_i}"),
                "codegen.x86.func_assign_nodes_step",
                &self.func_assign_nodes_step_pass,
                bind_group,
                active_hir_dispatch_args_buf,
            );
        }
        if node_func_owner_needs_copyback {
            encoder.copy_buffer_to_buffer(
                node_func_owner_b_buf,
                0,
                &node_func_buf,
                0,
                (hir_words * 4) as u64,
            );
        }
        dispatch_x86_stage_indirect(
            encoder,
            "expr_resolve_init",
            &self.expr_resolve_init_pass,
            &expr_resolve_init_bind_group,
            active_hir_dispatch_args_buf,
        );
        for (step_i, bind_group) in expr_resolve_step_bind_groups.iter().enumerate() {
            dispatch_compute_pass_indirect(
                encoder,
                &format!("expr_resolve_step.{step_i}"),
                "codegen.x86.expr_resolve_step",
                &self.expr_resolve_step_pass,
                bind_group,
                active_hir_dispatch_args_buf,
            );
        }
        encoder.copy_buffer_to_buffer(
            expr_resolved_step_final_buf,
            0,
            &expr_resolved_final_buf,
            0,
            (hir_words * 4) as u64,
        );
        dispatch_x86_stages_indirect(
            encoder,
            &[
                (
                    "enum_records",
                    &self.enum_records_pass,
                    &enum_records_bind_group,
                ),
                (
                    "match_records",
                    &self.match_records_pass,
                    &match_records_bind_group,
                ),
            ],
            active_hir_dispatch_args_buf,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "return_match_records",
            &self.return_match_records_pass,
            &return_match_records_bind_group,
            active_hir_dispatch_args_buf,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "match_result_owner_init",
            &self.match_result_owner_init_pass,
            &match_result_owner_init_bind_group,
            active_hir_dispatch_args_buf,
        );
        for (step_i, bind_group) in match_result_owner_step_bind_groups.iter().enumerate() {
            dispatch_compute_pass_indirect(
                encoder,
                &format!("match_result_owner_step.{step_i}"),
                "codegen.x86.match_result_owner_step",
                &self.match_result_owner_step_pass,
                bind_group,
                active_hir_dispatch_args_buf,
            );
        }
        encoder.copy_buffer_to_buffer(
            match_result_owner_step_final_buf,
            0,
            &match_result_value_owner_buf,
            0,
            (hir_words * 4) as u64,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "enclosing_return_init",
            &self.enclosing_return_init_pass,
            &enclosing_return_init_bind_group,
            active_hir_dispatch_args_buf,
        );
        for (step_i, bind_group) in enclosing_return_step_bind_groups.iter().enumerate() {
            dispatch_compute_pass_indirect(
                encoder,
                &format!("enclosing_return_step.{step_i}"),
                "codegen.x86.enclosing_return_step",
                &self.enclosing_return_step_pass,
                bind_group,
                active_hir_dispatch_args_buf,
            );
        }
        dispatch_x86_stage_indirect(
            encoder,
            "enclosing_let_init",
            &self.enclosing_let_init_pass,
            &enclosing_let_init_bind_group,
            active_hir_dispatch_args_buf,
        );
        for (step_i, bind_group) in enclosing_let_step_bind_groups.iter().enumerate() {
            dispatch_compute_pass_indirect(
                encoder,
                &format!("enclosing_let_step.{step_i}"),
                "codegen.x86.enclosing_let_step",
                &self.enclosing_let_step_pass,
                bind_group,
                active_hir_dispatch_args_buf,
            );
        }
        if enclosing_let_needs_copyback {
            encoder.copy_buffer_to_buffer(
                &enclosing_let_node_b_buf,
                0,
                &enclosing_let_node_a_buf,
                0,
                (hir_words * 4) as u64,
            );
        }
        dispatch_x86_stage_indirect(
            encoder,
            "match_ownership",
            &self.match_ownership_pass,
            &match_ownership_bind_group,
            active_hir_dispatch_args_buf,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "match_pattern_owner_init",
            &self.match_pattern_owner_init_pass,
            &match_pattern_owner_init_bind_group,
            active_hir_dispatch_args_buf,
        );
        for (step_i, bind_group) in match_pattern_owner_step_bind_groups.iter().enumerate() {
            dispatch_compute_pass_indirect(
                encoder,
                &format!("match_pattern_owner_step.{step_i}"),
                "codegen.x86.match_pattern_owner_step",
                &self.match_pattern_owner_step_pass,
                bind_group,
                active_hir_dispatch_args_buf,
            );
        }
        if match_pattern_owner_steps.len() % 2 != 0 {
            encoder.copy_buffer_to_buffer(
                match_pattern_owner_step_final_buf,
                0,
                &match_pattern_node_owner_buf,
                0,
                (hir_words * 4) as u64,
            );
        }
        init_repeated_u32_words(
            device,
            queue,
            encoder,
            &self.fill_u32_pass,
            "match_pattern_first_use_node",
            &match_pattern_first_use_node_buf,
            &[u32::MAX],
            hir_words,
        )?;
        dispatch_x86_stages_indirect(
            encoder,
            &[
                (
                    "match_pattern_records",
                    &self.match_pattern_records_pass,
                    &match_pattern_records_bind_group,
                ),
                (
                    "match_pattern_finalize",
                    &self.match_pattern_finalize_pass,
                    &match_pattern_finalize_bind_group,
                ),
                (
                    "struct_records",
                    &self.struct_records_pass,
                    &struct_records_bind_group,
                ),
            ],
            active_hir_dispatch_args_buf,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "array_records",
            &self.array_records_pass,
            &array_records_bind_group,
            active_hir_dispatch_args_buf,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "enclosing_stmt_init",
            &self.enclosing_stmt_init_pass,
            &enclosing_stmt_init_bind_group,
            active_hir_dispatch_args_buf,
        );
        for (step_i, bind_group) in enclosing_stmt_step_bind_groups.iter().enumerate() {
            dispatch_compute_pass_indirect(
                encoder,
                &format!("enclosing_stmt_step.{step_i}"),
                "codegen.x86.enclosing_stmt_step",
                &self.enclosing_stmt_step_pass,
                bind_group,
                active_hir_dispatch_args_buf,
            );
        }
        dispatch_x86_stage_indirect(
            encoder,
            "decl_widths",
            &self.decl_widths_pass,
            &decl_widths_bind_group,
            active_hir_dispatch_args_buf,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "decl_width_scan_local",
            &self.node_inst_scan_local_pass,
            &node_inst_scan_local_bind_group,
            active_hir_dispatch_args_buf,
        );
        for (step_i, bind_group) in node_inst_scan_block_bind_groups.iter().enumerate() {
            dispatch_compute_pass_indirect(
                encoder,
                &format!("decl_width_scan_blocks.{step_i}"),
                "codegen.x86.node_inst_scan_blocks",
                &self.node_inst_scan_blocks_pass,
                bind_group,
                &active_hir_scan_block_dispatch_args_buf,
            );
        }
        dispatch_x86_stage_indirect(
            encoder,
            "decl_layout",
            &self.decl_layout_pass,
            &decl_layout_bind_group,
            active_hir_dispatch_args_buf,
        );
        stamp_x86_timer(&mut timer, encoder, "x86.metadata.done");
        dispatch_compute_pass_indirect(
            encoder,
            "node_inst_scan_input.active_clear",
            "codegen.x86.node_inst_scan_input.active_clear",
            &self.active_clear_u32_pass,
            &node_inst_scan_input_clear_bind_group,
            &active_hir_plus_one_dispatch_args_buf,
        );
        dispatch_compute_pass_indirect(
            encoder,
            "call_callee_root_call.active_clear",
            "codegen.x86.call_callee_root_call.active_clear",
            &self.active_clear_u32_pass,
            &call_callee_root_call_clear_bind_group,
            &active_hir_count_dispatch_args_buf,
        );
        dispatch_x86_stages_indirect(
            encoder,
            &[
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
            ],
            active_hir_dispatch_args_buf,
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
        init_repeated_u32_words(
            device,
            queue,
            encoder,
            &self.fill_u32_pass,
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
                    &self.call_arg_values_pass,
                    &call_arg_values_bind_group,
                ),
                (
                    "intrinsic_calls",
                    &self.intrinsic_calls_pass,
                    &intrinsic_calls_bind_group,
                ),
                ("call_abi", &self.call_abi_pass, &call_abi_bind_group),
            ],
            active_hir_dispatch_args_buf,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "call_callee_owner_init",
            &self.call_callee_owner_init_pass,
            &call_callee_owner_init_bind_group,
            active_hir_dispatch_args_buf,
        );
        for (step_i, bind_group) in call_callee_owner_step_bind_groups.iter().enumerate() {
            dispatch_compute_pass_indirect(
                encoder,
                &format!("call_callee_owner_step.{step_i}"),
                "codegen.x86.call_callee_owner_step",
                &self.call_callee_owner_step_pass,
                bind_group,
                active_hir_dispatch_args_buf,
            );
        }
        encoder.copy_buffer_to_buffer(&call_abi_status_buf, 0, &call_abi_status_uniform_buf, 0, 16);
        stamp_x86_timer(&mut timer, encoder, "x86.calls.done");
        dispatch_x86_stages_indirect(
            encoder,
            &[(
                "node_inst_counts",
                &self.node_inst_counts_pass,
                &node_inst_counts_bind_group,
            )],
            active_hir_dispatch_args_buf,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "node_inst_same_end_rank_init",
            &self.node_inst_same_end_rank_init_pass,
            &node_inst_same_end_rank_init_bind_group,
            active_hir_dispatch_args_buf,
        );
        for (step_i, bind_group) in node_inst_same_end_rank_step_bind_groups.iter().enumerate() {
            dispatch_compute_pass_indirect(
                encoder,
                &format!("node_inst_same_end_rank_step.{step_i}"),
                "codegen.x86.node_inst_same_end_rank_step",
                &self.node_inst_same_end_rank_step_pass,
                bind_group,
                active_hir_dispatch_args_buf,
            );
        }
        dispatch_x86_stage_indirect(
            encoder,
            "node_inst_end_counts",
            &self.node_inst_end_counts_pass,
            &node_inst_end_counts_bind_group,
            active_hir_dispatch_args_buf,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "node_inst_scan_local",
            &self.node_inst_scan_local_pass,
            &node_inst_scan_local_bind_group,
            &active_hir_plus_one_dispatch_args_buf,
        );
        for (step_i, bind_group) in node_inst_scan_block_bind_groups.iter().enumerate() {
            dispatch_compute_pass_indirect(
                encoder,
                &format!("node_inst_scan_blocks.{step_i}"),
                "codegen.x86.node_inst_scan_blocks",
                &self.node_inst_scan_blocks_pass,
                bind_group,
                &active_hir_scan_block_dispatch_args_buf,
            );
        }
        dispatch_x86_stage_indirect(
            encoder,
            "node_inst_order",
            &self.node_inst_order_pass,
            &node_inst_order_bind_group,
            active_hir_dispatch_args_buf,
        );
        dispatch_x86_stage(
            encoder,
            "node_order_dispatch_args",
            &self.node_order_dispatch_args_pass,
            &node_order_dispatch_args_bind_group,
            (1, 1),
        );
        dispatch_x86_stage_indirect(
            encoder,
            "node_inst_scan_local",
            &self.node_inst_scan_local_pass,
            &node_inst_scan_local_bind_group,
            &active_node_order_scan_dispatch_args_buf,
        );
        for (step_i, bind_group) in node_inst_scan_block_bind_groups.iter().enumerate() {
            dispatch_compute_pass_indirect(
                encoder,
                &format!("node_inst_scan_blocks.order.{step_i}"),
                "codegen.x86.node_inst_scan_blocks",
                &self.node_inst_scan_blocks_pass,
                bind_group,
                &active_node_order_scan_block_dispatch_args_buf,
            );
        }
        dispatch_x86_stage_indirect(
            encoder,
            "node_inst_prefix_scan",
            &self.node_inst_prefix_scan_pass,
            &node_inst_prefix_scan_bind_group,
            &active_node_order_scan_dispatch_args_buf,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "node_inst_subtree_bounds",
            &self.node_inst_subtree_bounds_pass,
            &node_inst_subtree_bounds_bind_group,
            &active_hir_plus_one_dispatch_args_buf,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "expr_semantic_type_init",
            &self.expr_semantic_type_init_pass,
            &expr_semantic_type_init_bind_group,
            active_hir_dispatch_args_buf,
        );
        for (step_i, bind_group) in expr_semantic_type_step_bind_groups.iter().enumerate() {
            dispatch_compute_pass_indirect(
                encoder,
                &format!("expr_semantic_type_step.{step_i}"),
                "codegen.x86.expr_semantic_type_step",
                &self.expr_semantic_type_step_pass,
                bind_group,
                active_hir_dispatch_args_buf,
            );
        }
        dispatch_x86_stage_indirect(
            encoder,
            "node_inst_locations",
            &self.node_inst_locations_pass,
            &node_inst_locations_bind_group,
            active_hir_dispatch_args_buf,
        );
        stamp_x86_timer(&mut timer, encoder, "x86.inst_locations.done");
        dispatch_x86_stage_indirect(
            encoder,
            "enclosing_loop_init",
            &self.enclosing_loop_init_pass,
            &enclosing_loop_init_bind_group,
            active_hir_dispatch_args_buf,
        );
        for (step_i, bind_group) in enclosing_loop_step_bind_groups.iter().enumerate() {
            dispatch_compute_pass_indirect(
                encoder,
                &format!("enclosing_loop_step.{step_i}"),
                "codegen.x86.enclosing_loop_step",
                &self.enclosing_loop_step_pass,
                bind_group,
                active_hir_dispatch_args_buf,
            );
        }
        dispatch_x86_stage(
            encoder,
            "node_inst_gen_inputs",
            &self.node_inst_gen_inputs_pass,
            &node_inst_gen_inputs_bind_group,
            (1, 1),
        );
        dispatch_x86_stage(
            encoder,
            "virtual_inst_clear_dispatch_args",
            &self.virtual_inst_clear_dispatch_args_pass,
            &virtual_inst_clear_dispatch_args_bind_group,
            (1, 1),
        );
        dispatch_x86_stage_indirect(
            encoder,
            "virtual_inst_clear",
            &self.virtual_inst_clear_pass,
            &virtual_inst_clear_bind_group,
            &active_virtual_inst_dispatch_args_buf,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "node_inst_gen",
            &self.node_inst_gen_pass,
            &node_inst_gen_bind_group,
            active_hir_dispatch_args_buf,
        );
        stamp_x86_timer(&mut timer, encoder, "x86.inst_gen.done");
        dispatch_x86_stage(
            encoder,
            "virtual_dispatch_args",
            &self.virtual_dispatch_args_pass,
            &virtual_dispatch_args_bind_group,
            virtual_dispatch_arg_groups,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "virtual_func_rows_init",
            &self.virtual_func_rows_init_pass,
            &virtual_func_rows_init_bind_group,
            active_hir_dispatch_args_buf,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "virtual_func_first_row",
            &self.virtual_func_first_row_pass,
            &virtual_func_first_row_bind_group,
            &active_virtual_inst_dispatch_args_buf,
        );
        stamp_x86_timer(&mut timer, encoder, "x86.virtual_rows.done");
        for (step_i, bind_group) in virtual_next_call_bind_groups.iter().enumerate() {
            let indirect_offset = (step_i * 3 * std::mem::size_of::<u32>()) as u64;
            dispatch_compute_pass_indirect_offset(
                encoder,
                &format!("virtual_next_calls.{step_i}"),
                "codegen.x86.virtual_next_calls",
                &self.virtual_next_calls_pass,
                bind_group,
                &active_virtual_next_call_dispatch_args_buf,
                indirect_offset,
            );
        }
        stamp_x86_timer(&mut timer, encoder, "x86.virtual_next_calls.done");
        dispatch_x86_stage_indirect(
            encoder,
            "virtual_param_masks",
            &self.virtual_param_masks_pass,
            &virtual_param_masks_bind_group,
            &active_virtual_inst_dispatch_args_buf,
        );
        stamp_x86_timer(&mut timer, encoder, "x86.virtual_param_masks.done");
        dispatch_x86_stage_indirect(
            encoder,
            "virtual_liveness_init",
            &self.virtual_liveness_init_pass,
            &virtual_liveness_init_bind_group,
            &active_virtual_inst_dispatch_args_buf,
        );
        dispatch_x86_stage_indirect(
            encoder,
            "virtual_liveness",
            &self.virtual_liveness_pass,
            &virtual_liveness_bind_group,
            &active_virtual_inst_dispatch_args_buf,
        );
        stamp_x86_timer(&mut timer, encoder, "x86.virtual_liveness.done");
        for (chunk_i, bind_group) in virtual_regalloc_bind_groups.iter().enumerate() {
            let stage = format!("virtual_regalloc.{chunk_i}");
            let label = format!("codegen.x86.{stage}");
            let indirect_offset = (chunk_i * 3 * std::mem::size_of::<u32>()) as u64;
            dispatch_compute_pass_indirect_offset(
                encoder,
                &stage,
                &label,
                &self.virtual_regalloc_pass,
                bind_group,
                &active_virtual_regalloc_dispatch_args_buf,
                indirect_offset,
            );
        }
        stamp_x86_timer(&mut timer, encoder, "x86.regalloc.done");

        dispatch_compute_pass_indirect(
            encoder,
            "select",
            "codegen.x86.select",
            &self.select_pass,
            &select_bind_group,
            &active_virtual_inst_dispatch_args_buf,
        );

        dispatch_x86_stage_indirect(
            encoder,
            "inst_size",
            &self.inst_size_pass,
            &inst_size_bind_group,
            &active_selected_inst_dispatch_args_buf,
        );
        dispatch_compute_pass_indirect(
            encoder,
            "text_scan_local",
            "codegen.x86.text_scan_local",
            &self.text_scan_local_pass,
            &text_scan_local_bind_group,
            &active_selected_inst_dispatch_args_buf,
        );
        for (step_i, bind_group) in text_scan_block_bind_groups.iter().enumerate() {
            dispatch_compute_pass_indirect(
                encoder,
                &format!("text_scan_blocks.{step_i}"),
                "codegen.x86.text_scan_blocks",
                &self.node_inst_scan_blocks_pass,
                bind_group,
                &active_selected_scan_block_dispatch_args_buf,
            );
        }
        dispatch_x86_stage_indirect(
            encoder,
            "text_offsets",
            &self.text_offsets_pass,
            &text_offsets_bind_group,
            &active_selected_inst_dispatch_args_buf,
        );
        dispatch_x86_stage(
            encoder,
            "output_dispatch_args",
            &self.output_dispatch_args_pass,
            &output_dispatch_args_bind_group,
            (1, 1),
        );

        dispatch_compute_pass_indirect(
            encoder,
            "encode",
            "codegen.x86.encode",
            &self.encode_pass,
            &encode_bind_group,
            &active_text_word_dispatch_args_buf,
        );

        let (layout_groups_x, layout_groups_y) = workgroup_grid_1d(1);
        dispatch_x86_stages(
            encoder,
            &[("elf_layout", &self.elf_layout_pass, &elf_layout_bind_group)],
            (layout_groups_x, layout_groups_y),
        );

        dispatch_compute_pass_indirect(
            encoder,
            "elf_write",
            "codegen.x86.elf_write",
            &self.elf_write_pass,
            &elf_bind_group,
            &active_elf_header_word_dispatch_args_buf,
        );
        stamp_x86_timer(&mut timer, encoder, "x86.emit.done");
        encoder.copy_buffer_to_buffer(&out_buf, 0, &output_readback, 0, output_readback_bytes);
        encoder.copy_buffer_to_buffer(&status_buf, 0, &output_readback, output_status_offset, 16);
        if let Some(status_trace_readback) = &status_trace_readback {
            let mut offset = 0u64;
            for (buffer, words) in [
                (&enum_record_status_buf, 4),
                (&struct_record_status_buf, 4),
                (&decl_layout_status_buf, 4),
                (&node_inst_count_status_buf, 4),
                (&node_inst_order_status_buf, 4),
                (&node_inst_range_status_buf, 4),
                (&node_inst_subtree_bounds_status_buf, 4),
                (&node_inst_location_status_buf, 4),
                (&node_inst_gen_input_status_buf, 4),
                (&virtual_inst_status_buf, 4),
                (&virtual_func_first_row_status_buf, 4),
                (&virtual_next_call_status_buf, 4),
                (&func_param_reg_mask_status_buf, 4),
                (&virtual_liveness_status_buf, 4),
                (&virtual_regalloc_status_buf, 4),
                (&select_status_buf, 4),
                (&size_status_buf, 4),
                (&text_status_buf, 4),
                (&encode_status_buf, 4),
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
        host_timer.stamp("dispatch_and_readbacks_recorded");

        Ok(include!("record_retained_expr.rs"))
    }
}
