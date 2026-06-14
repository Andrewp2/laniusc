use anyhow::Result;

use super::{
    GpuX86CodeGenerator,
    RecordedX86Codegen,
    support::{RetainedX86Buffer, zero_u32_words},
};

mod allocation;
mod bind_helpers;
mod buffers;
mod calls;
mod capacity;
mod dispatch_args;
mod dispatch_recording;
mod emit_bind_groups;
mod enum_match_bind_groups;
mod features;
mod indirect;
mod init;
mod inputs;
mod inst_gen_bind_groups;
mod inst_plan_bind_groups;
mod metadata_bind_groups;
mod metadata_dispatch;
mod retained;
mod scan;
mod semantic_bind_groups;
mod status_trace;
mod timing;
mod virtual_bind_groups;

use allocation::AllocationScope;
use buffers::{
    InitialRecordBufferInputs,
    InitialRecordBuffers,
    InstructionRecordBufferInputs,
    InstructionRecordBuffers,
    MetadataRecordBufferInputs,
    MetadataRecordBuffers,
    create_initial_record_buffers,
    create_instruction_record_buffers,
    create_metadata_record_buffers,
};
use calls::{CallRecordBindGroups, CallRecordInputs, create_call_record_bind_groups};
use capacity::RecordCapacity;
use dispatch_args::ActiveDispatchArgBuffers;
use dispatch_recording::{
    InstructionDispatchInputs,
    VirtualEmitDispatchInputs,
    record_instruction_dispatches,
    record_virtual_emit_dispatches,
};
use emit_bind_groups::{EmitBindGroupInputs, EmitBindGroups, create_emit_bind_groups};
use enum_match_bind_groups::{
    EnumMatchBindGroupInputs,
    EnumMatchBindGroups,
    create_enum_match_bind_groups,
};
use init::{InitializerInputs, record_initializers};
pub use inputs::RecordElfInputs;
use inst_gen_bind_groups::{
    InstGenBindGroupInputs,
    InstGenBindGroups,
    create_inst_gen_bind_groups,
};
use inst_plan_bind_groups::{
    InstPlanBindGroupInputs,
    InstPlanBindGroups,
    create_inst_plan_bind_groups,
};
use metadata_bind_groups::{
    DispatchSetupBindGroups,
    DispatchSetupInputs,
    FunctionDiscoveryBindGroups,
    FunctionDiscoveryInputs,
    create_dispatch_setup_bind_groups,
    create_function_discovery_bind_groups,
};
use metadata_dispatch::{MetadataCallDispatchInputs, record_metadata_and_call_dispatches};
use retained::RetainedRecording;
use scan::{final_ping_pong_scan_prefix, regalloc_params, scan_params, scan_params_for_steps};
use semantic_bind_groups::{
    SemanticRecordBindGroups,
    SemanticRecordInputs,
    create_semantic_record_bind_groups,
};
use status_trace::{StatusTraceSources, record_status_trace_readback};
use timing::HostTimer;
use virtual_bind_groups::{VirtualBindGroupInputs, VirtualBindGroups, create_virtual_bind_groups};

impl GpuX86CodeGenerator {
    pub fn record_elf_from_hir(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        inputs: RecordElfInputs<'_, '_>,
    ) -> Result<RecordedX86Codegen> {
        let RecordElfInputs {
            source_len,
            token_capacity,
            n_hir_nodes,
            inst_hir_node_count,
            hir_status_buf,
            active_hir_dispatch_args_buf,
            hir_kind_buf,
            hir_item_kind_buf,
            parent_buf,
            subtree_end_buf,
            function_metadata,
            expr_metadata,
            call_metadata,
            array_metadata,
            enum_metadata,
            struct_metadata,
            type_metadata,
            visible_decl_buf,
            fn_entrypoint_tag_buf,
            feature_summary,
            external_scratch,
            mut timer,
        } = inputs;
        let mut host_timer = HostTimer::new();
        let RecordCapacity {
            hir_words,
            inst_capacity,
            output_capacity,
            output_words,
            output_readback_bytes,
            node_inst_scan_words,
            node_inst_scan_blocks,
            node_func_owner_steps,
            expr_resolve_steps,
            expr_semantic_type_steps,
            enclosing_return_steps,
            enclosing_let_steps,
            enclosing_stmt_steps,
            call_callee_owner_steps,
            match_result_owner_steps,
            match_pattern_owner_steps,
            node_inst_same_end_rank_steps,
            enclosing_loop_steps,
            short_circuit_rhs_steps,
            index_source_owner_steps,
            func_owner_scan_blocks,
            node_inst_order_rows,
            virtual_next_call_steps,
            virtual_regalloc_chunk_count,
            token_words,
            function_slot_capacity,
            virtual_dispatch_arg_groups,
            params,
        } = RecordCapacity::for_hir(
            source_len,
            token_capacity,
            n_hir_nodes,
            inst_hir_node_count as usize,
            feature_summary,
        );
        host_timer.stamp("capacity");

        let mut allocation_scope = AllocationScope::new(device);
        let decl_layout_words = token_words;
        let InitialRecordBuffers {
            params_buf,
            feature_params_buf,
            func_meta_buf,
            active_dispatch_args,
            func_meta_uniform_buf,
            node_tree_status_buf,
            expr_resolved_final_buf,
            node_func_buf,
            func_owner_scan_local_prefix_buf,
            func_owner_scan_block_sum_buf,
            func_owner_scan_prefix_a_buf,
            func_owner_scan_prefix_b_buf,
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
        } = create_initial_record_buffers(
            device,
            &mut allocation_scope,
            InitialRecordBufferInputs {
                params: &params,
                feature_summary,
                hir_words,
                node_inst_scan_words,
                node_inst_scan_blocks,
                token_words,
                virtual_next_call_step_count: virtual_next_call_steps.len(),
                virtual_regalloc_chunk_count,
                external_scratch: &external_scratch,
            },
        )?;
        let ActiveDispatchArgBuffers {
            hir_count,
            hir_plus_one,
            hir_scan_block,
            node_order_scan,
            node_order_scan_block,
            function_dispatch,
            virtual_inst,
            virtual_next_call,
            virtual_regalloc,
            selected_inst,
            selected_scan_block,
            text_word,
            elf_header_word,
        } = active_dispatch_args;
        // Expression resolution copies its final output before match-result
        // owner propagation starts. Match-pattern owner propagation starts
        // after match-result owners have been copied to the stable value-owner
        // table. Reuse those same HIR-sized scratch rows for this pointer jump.
        let match_result_owner_a_buf = &match_pattern_node_owner_buf;
        let match_result_owner_b_buf = &match_pattern_node_variant_buf;
        let match_result_owner_link_a_buf = &node_inst_same_end_link_a_buf;
        let match_result_owner_link_b_buf = &node_inst_same_end_link_b_buf;
        let MetadataRecordBuffers {
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
            call_arg_lookup_record_buf,
            intrinsic_call_status_buf,
            call_abi_record_buf,
            call_abi_status_buf,
            call_abi_status_uniform_buf,
            for_iterable_node_buf,
            node_control_padding_buf,
            postfix_operand_owner_buf,
        } = create_metadata_record_buffers(
            device,
            &mut allocation_scope,
            MetadataRecordBufferInputs {
                feature_summary,
                hir_words,
                token_words,
                decl_layout_words,
                inst_capacity,
                function_slot_capacity,
                external_scratch: &external_scratch,
            },
        )?;
        // Function-owner pointer jumping completes before match-pattern
        // candidate projection. Copy an odd-step result back to node_func and
        // reuse this HIR-sized storage for the later first-use candidate rows.
        let node_func_owner_b_buf = &match_pattern_first_use_node_buf;
        // No-match programs skip the pattern-record/finalize reads. Reuse
        // already allocated HIR scratch for later enclosing-stmt/callee-owner
        // pointer jumping instead of retaining two extra match-only tables.
        let match_pattern_first_variant_node_buf: &wgpu::Buffer =
            match_pattern_first_variant_node_storage_buf
                .as_ref()
                .unwrap_or(&match_pattern_node_owner_buf);
        let match_pattern_first_payload_node_buf: &wgpu::Buffer =
            match_pattern_first_payload_node_storage_buf
                .as_ref()
                .unwrap_or(&match_pattern_node_variant_buf);
        // Enclosing-let propagation is copied back to the stable A buffer
        // before call-record projection. Reuse the alternate ping-pong storage
        // for call-callee-root markers produced by call_records.
        let call_callee_root_call_buf = &enclosing_let_node_b_buf;
        let hir_param_record_buf: &wgpu::Buffer = empty_param_record_buf
            .as_ref()
            .map_or(function_metadata.param_record, |buffer| buffer);
        // Match-pattern owner records are consumed before call projection.
        // Reuse that HIR-sized table for per-call intrinsic metadata.
        let intrinsic_call_record_buf = &match_pattern_owner_buf;
        // Node instruction counts are consumed before virtual parameter mask
        // materialization. Reuse the info table once instruction
        // location planning has finished.
        let func_param_reg_mask_buf = &node_inst_count_info_buf;
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
        // Expression semantic compare mode and pointer-jump links are packed
        // into the same ping-pong scratch rows. node_inst_locations consumes
        // the final record before enclosing-loop propagation reuses the links.
        let expr_semantic_type_a_buf = &node_inst_same_end_link_a_buf;
        let expr_semantic_type_b_buf = &node_inst_same_end_link_b_buf;
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
        let enclosing_stmt_node_a_buf = match_pattern_first_variant_node_buf;
        let enclosing_stmt_node_b_buf = match_pattern_first_payload_node_buf;
        let enclosing_stmt_link_a_buf = &node_inst_same_end_link_a_buf;
        let enclosing_stmt_link_b_buf = &node_inst_same_end_link_b_buf;
        let enclosing_stmt_step_final_buf = if enclosing_stmt_steps.len() % 2 == 0 {
            enclosing_stmt_node_a_buf
        } else {
            enclosing_stmt_node_b_buf
        };
        let call_callee_owner_call_a_buf = match_pattern_first_variant_node_buf;
        let call_callee_owner_call_b_buf = match_pattern_first_payload_node_buf;
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
        let InstructionRecordBuffers {
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
        } = create_instruction_record_buffers(
            device,
            allocation_scope,
            InstructionRecordBufferInputs {
                hir_words,
                node_inst_scan_words,
                inst_capacity,
                function_slot_capacity,
                output_words,
                output_readback_bytes,
                external_scratch: &external_scratch,
            },
        )?;
        let node_inst_scan_block_sum_buf = &func_owner_scan_block_sum_buf;
        let node_inst_scan_prefix_a_buf = &func_owner_scan_prefix_a_buf;
        let node_inst_scan_prefix_b_buf = &func_owner_scan_prefix_b_buf;
        let node_inst_location_record_buf = &call_record_buf;
        let short_circuit_rhs_step_final_buf = if short_circuit_rhs_steps.len() % 2 == 0 {
            &short_circuit_rhs_node_a_buf
        } else {
            &short_circuit_rhs_node_b_buf
        };
        // Short-circuit RHS propagation no longer needs its link buffers after
        // the step sequence. Reuse those HIR-sized rows for index-base owner
        // records consumed by virtual instruction generation.
        let index_source_owner_a_buf = &short_circuit_rhs_link_a_buf;
        let index_source_owner_b_buf = &short_circuit_rhs_link_b_buf;
        let index_source_link_a_buf = &node_inst_same_end_link_a_buf;
        let index_source_link_b_buf = &node_inst_same_end_link_b_buf;
        let index_source_owner_step_final_buf = if index_source_owner_steps.len() % 2 == 0 {
            index_source_owner_a_buf
        } else {
            index_source_owner_b_buf
        };
        // Call argument lookup and ABI records are dead after instruction
        // generation. Reuse their token-indexed storage for virtual row bounds,
        // initialized immediately before the row-bound scatter pass.
        let virtual_func_first_row_buf = &call_arg_lookup_record_buf;
        let virtual_func_last_row_buf = &call_abi_record_buf;
        // The node-order/subtree-bounds scratch is dead after instruction
        // generation. Register allocation reuses it for per-function active
        // register ends.
        let virtual_regalloc_active_end_buf = &node_inst_order_record_buf;
        // Register allocation is the last consumer of liveness and next-call
        // scratch records. Selection overwrites every selected instruction row,
        // so reuse those inst-sized buffers for final instruction fields.
        let inst_kind_buf = &virtual_live_start_buf;
        let inst_arg0_buf = &virtual_live_end_buf;
        let inst_arg1_buf = &virtual_next_call_a_buf;
        let inst_arg2_buf = &virtual_next_call_b_buf;
        let inst_size_buf = &virtual_phys_reg_buf;
        // Selection is the final consumer of virtual instruction records and
        // args. Text emission reuses those inst-sized tables for byte offsets
        // and scan-local prefixes.
        let inst_byte_offset_buf = &virtual_inst_record_buf;
        let text_scan_local_prefix_buf = &virtual_inst_args_buf;
        let virtual_value_def_scan_local_prefix_buf = &virtual_next_call_a_buf;
        let virtual_value_def_scan_block_sum_buf = &text_scan_block_sum_buf;
        let virtual_value_def_scan_prefix_a_buf = &text_scan_prefix_a_buf;
        let virtual_value_def_scan_prefix_b_buf = &text_scan_prefix_b_buf;
        // Relocation record scatter runs after selection and text offsets, so
        // it reuses virtual scratch rows that are dead after regalloc/select.
        let reloc_kind_buf = &virtual_func_slot_buf;
        let reloc_site_inst_buf = &virtual_value_def_row_buf;
        let reloc_target_inst_buf = &virtual_call_live_reg_mask_buf;
        host_timer.stamp("scratch_buffers");
        let func_owner_scan_params_buf = scan_params(
            device,
            "codegen.x86.func_owner_scan.params",
            hir_words,
            func_owner_scan_blocks,
            inst_capacity,
        );
        let final_func_owner_scan_prefix_buf = final_ping_pong_scan_prefix(
            &func_owner_scan_params_buf,
            &func_owner_scan_prefix_a_buf,
            &func_owner_scan_prefix_b_buf,
        );
        let node_inst_scan_params_buf = scan_params(
            device,
            "codegen.x86.node_inst_scan.params",
            node_inst_scan_words,
            node_inst_scan_blocks,
            inst_capacity,
        );
        let final_node_inst_scan_prefix_buf = final_ping_pong_scan_prefix(
            &node_inst_scan_params_buf,
            &node_inst_scan_prefix_a_buf,
            &node_inst_scan_prefix_b_buf,
        );
        let text_scan_params_buf = scan_params(
            device,
            "codegen.x86.text_scan.params",
            text_scan_words,
            text_scan_blocks,
            inst_capacity,
        );
        let virtual_next_call_params_buf = scan_params_for_steps(
            device,
            "codegen.x86.virtual_next_call.params",
            &virtual_next_call_steps,
            inst_capacity,
            0,
            inst_capacity,
        );
        let virtual_regalloc_params_buf = regalloc_params(
            device,
            "codegen.x86.virtual_regalloc.params",
            virtual_regalloc_chunk_count,
        );
        host_timer.stamp("scan_params");

        host_timer.stamp("uniform_buffers_initialized");
        record_initializers(InitializerInputs {
            device,
            queue,
            encoder,
            fill_u32_pass: &self.fill_u32_pass,
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
            func_meta_buf: &func_meta_buf,
            func_meta_uniform_buf: &func_meta_uniform_buf,
            node_tree_status_buf: &node_tree_status_buf,
            enum_type_record_buf: &enum_type_record_buf,
            enum_value_record_buf: &enum_value_record_buf,
            enum_record_status_buf: &enum_record_status_buf,
            match_arm_owner_buf: &match_arm_owner_buf,
            match_return_node_buf: &match_return_node_buf,
            match_pattern_owner_buf: &match_pattern_owner_buf,
            match_result_value_owner_buf: &match_result_value_owner_buf,
            match_pattern_node_owner_buf: &match_pattern_node_owner_buf,
            match_pattern_node_variant_buf: &match_pattern_node_variant_buf,
            match_pattern_node_payload_decl_buf: &match_pattern_node_payload_decl_buf,
            match_pattern_first_variant_node_buf,
            match_pattern_first_payload_node_buf,
            struct_type_record_buf: &struct_type_record_buf,
            struct_access_record_buf: &struct_access_record_buf,
            struct_store_record_buf: &struct_store_record_buf,
            struct_record_status_buf: &struct_record_status_buf,
            decl_layout_record_buf: &decl_layout_record_buf,
            decl_layout_status_buf: &decl_layout_status_buf,
            decl_node_by_token_buf: &decl_node_by_token_buf,
            func_slot_by_index_buf: &func_slot_by_index_buf,
            func_slot_by_node_buf: &func_slot_by_node_buf,
            call_record_buf: &call_record_buf,
            call_type_record_buf: &call_type_record_buf,
            call_record_status_buf: &call_record_status_buf,
            const_value_record_buf: &const_value_record_buf,
            const_value_status_buf: &const_value_status_buf,
            param_reg_record_buf: &param_reg_record_buf,
            param_reg_status_buf: &param_reg_status_buf,
            local_literal_record_buf: &local_literal_record_buf,
            local_literal_status_buf: &local_literal_status_buf,
            local_literal_status_uniform_buf: &local_literal_status_uniform_buf,
            node_inst_order_record_buf: &node_inst_order_record_buf,
            call_arg_lookup_record_buf: &call_arg_lookup_record_buf,
            intrinsic_call_status_buf: &intrinsic_call_status_buf,
            call_abi_record_buf: &call_abi_record_buf,
            call_abi_status_buf: &call_abi_status_buf,
            for_iterable_node_buf: &for_iterable_node_buf,
            node_control_padding_buf: &node_control_padding_buf,
            postfix_operand_owner_buf: &postfix_operand_owner_buf,
            node_inst_count_status_buf: &node_inst_count_status_buf,
            node_inst_order_status_buf: &node_inst_order_status_buf,
            node_inst_range_start_buf: &node_inst_range_start_buf,
            node_inst_range_info_buf: &node_inst_range_info_buf,
            node_inst_range_status_buf: &node_inst_range_status_buf,
            node_inst_subtree_bounds_status_buf: &node_inst_subtree_bounds_status_buf,
            node_inst_location_record_buf: &node_inst_location_record_buf,
            node_inst_location_status_buf: &node_inst_location_status_buf,
            node_inst_gen_input_status_buf: &node_inst_gen_input_status_buf,
            virtual_inst_status_buf: &virtual_inst_status_buf,
            virtual_func_first_row_status_buf: &virtual_func_first_row_status_buf,
            virtual_liveness_status_buf: &virtual_liveness_status_buf,
            virtual_next_call_status_buf: &virtual_next_call_status_buf,
            func_param_reg_mask_status_buf: &func_param_reg_mask_status_buf,
            virtual_regalloc_status_buf: &virtual_regalloc_status_buf,
            select_status_buf: &select_status_buf,
            size_status_buf: &size_status_buf,
            text_len_buf: &text_len_buf,
            text_status_buf: &text_status_buf,
            encode_status_buf: &encode_status_buf,
            elf_layout_buf: &elf_layout_buf,
            layout_status_buf: &layout_status_buf,
            status_buf: &status_buf,
        })?;
        zero_u32_words(
            queue,
            encoder,
            &virtual_call_live_reg_mask_buf,
            inst_capacity,
        );
        zero_u32_words(queue, encoder, &out_buf, output_words);
        host_timer.stamp("initializers_recorded");

        let DispatchSetupBindGroups {
            active_scan_dispatch_args: active_scan_dispatch_args_bind_group,
            node_inst_scan_input_clear: node_inst_scan_input_clear_bind_group,
            call_callee_root_call_clear: call_callee_root_call_clear_bind_group,
            node_order_dispatch_args: node_order_dispatch_args_bind_group,
            virtual_dispatch_args: virtual_dispatch_args_bind_group,
            output_dispatch_args: output_dispatch_args_bind_group,
        } = create_dispatch_setup_bind_groups(
            self,
            device,
            DispatchSetupInputs {
                params: &params_buf,
                hir_status: hir_status_buf,
                hir_count: &hir_count,
                hir_plus_one: &hir_plus_one,
                hir_scan_block: &hir_scan_block,
                node_inst_scan_input: node_inst_scan_input_buf,
                call_callee_root_call: call_callee_root_call_buf,
                node_inst_order_status: &node_inst_order_status_buf,
                node_order_scan: &node_order_scan,
                node_order_scan_block: &node_order_scan_block,
                virtual_inst_status: &virtual_inst_status_buf,
                func_meta: &func_meta_buf,
                function_dispatch: &function_dispatch,
                virtual_inst: &virtual_inst,
                virtual_next_call: &virtual_next_call,
                selected_inst: &selected_inst,
                selected_scan_block: &selected_scan_block,
                text_len: &text_len_buf,
                text_status: &text_status_buf,
                text_word: &text_word,
                elf_header_word: &elf_header_word,
            },
        )?;

        let FunctionDiscoveryBindGroups {
            node_tree_info: node_tree_info_bind_group,
            func: func_bind_group,
            func_owner_scan_local: func_owner_scan_local_bind_group,
            func_owner_scan_block: func_owner_scan_block_bind_groups,
            func_assign_nodes: func_assign_nodes_bind_group,
            func_assign_nodes_step: func_assign_nodes_step_bind_groups,
            func_slot_flags: func_slot_flags_bind_group,
            func_slot_scatter: func_slot_scatter_bind_group,
            expr_resolve_init: expr_resolve_init_bind_group,
            expr_resolve_step: expr_resolve_step_bind_groups,
        } = create_function_discovery_bind_groups(
            self,
            device,
            FunctionDiscoveryInputs {
                params: &params_buf,
                hir_status: hir_status_buf,
                hir_kind: hir_kind_buf,
                hir_item_kind: hir_item_kind_buf,
                parent: parent_buf,
                subtree_end: subtree_end_buf,
                function_metadata: &function_metadata,
                expr_metadata: &expr_metadata,
                fn_entrypoint_tag: fn_entrypoint_tag_buf,
                node_tree_status: &node_tree_status_buf,
                func_meta: &func_meta_buf,
                node_func: &node_func_buf,
                decl_node_by_token: &decl_node_by_token_buf,
                func_slot_by_node: &func_slot_by_node_buf,
                func_owner_scan_params: &func_owner_scan_params_buf,
                func_owner_scan_local_prefix: &func_owner_scan_local_prefix_buf,
                func_owner_scan_block_sum: &func_owner_scan_block_sum_buf,
                func_owner_scan_prefix_a: &func_owner_scan_prefix_a_buf,
                func_owner_scan_prefix_b: &func_owner_scan_prefix_b_buf,
                final_func_owner_scan_prefix: final_func_owner_scan_prefix_buf,
                node_func_owner_steps: &node_func_owner_steps,
                node_func_owner_link_a: node_func_owner_link_a_buf,
                node_func_owner_link_b: node_func_owner_link_b_buf,
                node_func_owner_b: node_func_owner_b_buf,
                node_inst_scan_input: node_inst_scan_input_buf,
                node_inst_scan_local_prefix: &node_inst_scan_local_prefix_buf,
                final_node_inst_scan_prefix: final_node_inst_scan_prefix_buf,
                func_slot_by_index: &func_slot_by_index_buf,
                expr_resolve_steps: &expr_resolve_steps,
                expr_resolved_a: expr_resolved_a_buf,
                expr_resolved_b: expr_resolved_b_buf,
                expr_resolve_link_a: expr_resolve_link_a_buf,
                expr_resolve_link_b: expr_resolve_link_b_buf,
            },
        )?;
        let EnumMatchBindGroups {
            enum_records: enum_records_bind_group,
            match_records: match_records_bind_group,
            match_patterns: match_pattern_records_bind_group,
        } = create_enum_match_bind_groups(
            self,
            device,
            EnumMatchBindGroupInputs {
                params: &params_buf,
                feature_params: &feature_params_buf,
                hir_status: hir_status_buf,
                hir_kind: hir_kind_buf,
                expr_metadata: &expr_metadata,
                enum_metadata: &enum_metadata,
                call_metadata: &call_metadata,
                expr_resolved_final: &expr_resolved_final_buf,
                visible_decl: visible_decl_buf,
                enum_type_record: &enum_type_record_buf,
                enum_value_record: &enum_value_record_buf,
                enum_record_status: &enum_record_status_buf,
                match_record: &match_record_buf,
                match_result_value_owner: &match_result_value_owner_buf,
                match_arm_owner: &match_arm_owner_buf,
                match_pattern_node_owner: &match_pattern_node_owner_buf,
                match_pattern_node_variant: &match_pattern_node_variant_buf,
                match_pattern_node_payload_decl: &match_pattern_node_payload_decl_buf,
                match_pattern_first_use_node: &match_pattern_first_use_node_buf,
                match_pattern_first_variant_node: match_pattern_first_variant_node_buf,
                match_pattern_first_payload_node: match_pattern_first_payload_node_buf,
            },
        )?;
        let SemanticRecordBindGroups {
            enclosing_return_init: enclosing_return_init_bind_group,
            enclosing_return_step: enclosing_return_step_bind_groups,
            enclosing_let_init: enclosing_let_init_bind_group,
            enclosing_let_step: enclosing_let_step_bind_groups,
            enclosing_stmt_init: enclosing_stmt_init_bind_group,
            enclosing_stmt_step: enclosing_stmt_step_bind_groups,
            return_match_records: return_match_records_bind_group,
            match_result_owner_init: match_result_owner_init_bind_group,
            match_result_owner_step: match_result_owner_step_bind_groups,
            match_ownership: match_ownership_bind_group,
            match_pattern_owner_init: match_pattern_owner_init_bind_group,
            match_pattern_owner_step: match_pattern_owner_step_bind_groups,
            match_pattern_finalize: match_pattern_finalize_bind_group,
            struct_records: struct_records_bind_group,
            array_records: array_records_bind_group,
            decl_widths: decl_widths_bind_group,
            decl_layout: decl_layout_bind_group,
        } = create_semantic_record_bind_groups(
            self,
            device,
            SemanticRecordInputs {
                params_buf: &params_buf,
                feature_params_buf: &feature_params_buf,
                hir_status_buf,
                hir_kind_buf,
                parent_buf,
                subtree_end_buf,
                function_metadata: &function_metadata,
                expr_metadata: &expr_metadata,
                call_metadata: &call_metadata,
                array_metadata: &array_metadata,
                struct_metadata: &struct_metadata,
                type_metadata: &type_metadata,
                expr_resolved_final_buf: &expr_resolved_final_buf,
                node_tree_status_buf: &node_tree_status_buf,
                match_record_buf: &match_record_buf,
                match_return_node_buf: &match_return_node_buf,
                match_pattern_owner_buf: &match_pattern_owner_buf,
                match_result_value_owner_buf: &match_result_value_owner_buf,
                match_pattern_node_variant_buf: &match_pattern_node_variant_buf,
                match_pattern_node_payload_decl_buf: &match_pattern_node_payload_decl_buf,
                match_pattern_first_use_node_buf: &match_pattern_first_use_node_buf,
                match_pattern_first_variant_node_buf,
                match_pattern_first_payload_node_buf,
                enclosing_return_node_a_buf: &enclosing_return_node_a_buf,
                enclosing_return_node_b_buf: &enclosing_return_node_b_buf,
                enclosing_return_link_a_buf,
                enclosing_return_link_b_buf,
                enclosing_return_steps: &enclosing_return_steps,
                enclosing_let_node_a_buf: &enclosing_let_node_a_buf,
                enclosing_let_node_b_buf: &enclosing_let_node_b_buf,
                enclosing_let_link_a_buf,
                enclosing_let_link_b_buf,
                enclosing_let_steps: &enclosing_let_steps,
                enclosing_let_step_final_buf,
                enclosing_stmt_node_a_buf,
                enclosing_stmt_node_b_buf,
                enclosing_stmt_link_a_buf,
                enclosing_stmt_link_b_buf,
                enclosing_stmt_steps: &enclosing_stmt_steps,
                match_result_owner_a_buf,
                match_result_owner_b_buf,
                match_result_owner_link_a_buf,
                match_result_owner_link_b_buf,
                match_result_owner_steps: &match_result_owner_steps,
                match_pattern_owner_a_buf,
                match_pattern_owner_b_buf,
                match_pattern_owner_link_a_buf,
                match_pattern_owner_link_b_buf,
                match_pattern_owner_steps: &match_pattern_owner_steps,
                struct_type_record_buf: &struct_type_record_buf,
                struct_access_record_buf: &struct_access_record_buf,
                struct_store_record_buf: &struct_store_record_buf,
                struct_record_status_buf: &struct_record_status_buf,
                enum_type_record_buf: &enum_type_record_buf,
                enum_record_status_buf: &enum_record_status_buf,
                hir_param_record_buf,
                final_node_func_buf,
                node_inst_scan_input_buf,
                decl_node_by_token_buf: &decl_node_by_token_buf,
                node_inst_scan_local_prefix_buf: &node_inst_scan_local_prefix_buf,
                final_node_inst_scan_prefix_buf,
                decl_layout_record_buf: &decl_layout_record_buf,
                decl_layout_status_buf: &decl_layout_status_buf,
            },
        )?;
        let CallRecordBindGroups {
            call_records: call_records_bind_group,
            call_callee_owner_init: call_callee_owner_init_bind_group,
            call_callee_owner_step: call_callee_owner_step_bind_groups,
            const_values: const_values_bind_group,
            param_regs: param_regs_bind_group,
            local_literals: local_literals_bind_group,
            call_arg_values: call_arg_values_bind_group,
            intrinsic_calls: intrinsic_calls_bind_group,
            call_abi: call_abi_bind_group,
        } = create_call_record_bind_groups(
            self,
            device,
            CallRecordInputs {
                params_buf: &params_buf,
                feature_params_buf: &feature_params_buf,
                hir_status_buf,
                hir_kind_buf,
                parent_buf,
                function_metadata: &function_metadata,
                expr_metadata: &expr_metadata,
                call_metadata: &call_metadata,
                type_metadata: &type_metadata,
                visible_decl_buf,
                expr_resolved_final_buf: &expr_resolved_final_buf,
                final_node_func_buf,
                call_record_buf: &call_record_buf,
                call_type_record_buf: &call_type_record_buf,
                call_callee_root_call_buf,
                call_record_status_buf: &call_record_status_buf,
                call_callee_owner_call_a_buf,
                call_callee_owner_call_b_buf,
                call_callee_owner_link_a_buf,
                call_callee_owner_link_b_buf,
                call_callee_owner_steps: &call_callee_owner_steps,
                const_value_record_buf: &const_value_record_buf,
                const_value_status_buf: &const_value_status_buf,
                hir_param_record_buf,
                fn_entrypoint_tag_buf,
                decl_node_by_token_buf: &decl_node_by_token_buf,
                struct_type_record_buf: &struct_type_record_buf,
                struct_record_status_buf: &struct_record_status_buf,
                enum_type_record_buf: &enum_type_record_buf,
                enum_value_record_buf: &enum_value_record_buf,
                enum_record_status_buf: &enum_record_status_buf,
                param_reg_record_buf: &param_reg_record_buf,
                param_reg_status_buf: &param_reg_status_buf,
                local_literal_record_buf: &local_literal_record_buf,
                local_literal_status_buf: &local_literal_status_buf,
                enclosing_stmt_step_final_buf,
                call_arg_lookup_record_buf: &call_arg_lookup_record_buf,
                intrinsic_call_record_buf,
                intrinsic_call_status_buf: &intrinsic_call_status_buf,
                call_abi_record_buf: &call_abi_record_buf,
                call_abi_status_buf: &call_abi_status_buf,
            },
        )?;
        let InstPlanBindGroups {
            for_iterable_nodes: for_iterable_nodes_bind_group,
            control_padding: control_padding_bind_group,
            postfix_operand_owner: postfix_operand_owner_bind_group,
            counts: node_inst_counts_bind_group,
            same_end_rank_init: node_inst_same_end_rank_init_bind_group,
            same_end_rank_step: node_inst_same_end_rank_step_bind_groups,
            end_counts: node_inst_end_counts_bind_group,
            order: node_inst_order_bind_group,
            scan_local: node_inst_scan_local_bind_group,
            scan_block: node_inst_scan_block_bind_groups,
            prefix_scan: node_inst_prefix_scan_bind_group,
            subtree_bounds: node_inst_subtree_bounds_bind_group,
            semantic_type_init: expr_semantic_type_init_bind_group,
            semantic_type_step: expr_semantic_type_step_bind_groups,
            locations: node_inst_locations_bind_group,
            worklist_scatter: node_inst_gen_worklist_scatter_bind_group,
            worklist_dispatch_args: node_inst_gen_worklist_dispatch_args_bind_group,
            enclosing_loop_init: enclosing_loop_init_bind_group,
            enclosing_loop_step: enclosing_loop_step_bind_groups,
            short_circuit_rhs_init: short_circuit_rhs_init_bind_group,
            short_circuit_rhs_step: short_circuit_rhs_step_bind_groups,
            index_source_owner_init: index_source_owner_init_bind_group,
            index_source_owner_step: index_source_owner_step_bind_groups,
        } = create_inst_plan_bind_groups(
            self,
            device,
            InstPlanBindGroupInputs {
                params: &params_buf,
                feature_params: &feature_params_buf,
                node_inst_scan_params: &node_inst_scan_params_buf,
                hir_status: hir_status_buf,
                hir_kind: hir_kind_buf,
                parent: parent_buf,
                subtree_end: subtree_end_buf,
                function_metadata: &function_metadata,
                expr_metadata: &expr_metadata,
                call_metadata: &call_metadata,
                enum_metadata: &enum_metadata,
                type_metadata: &type_metadata,
                hir_param_record: hir_param_record_buf,
                expr_resolved_final: &expr_resolved_final_buf,
                final_node_func: final_node_func_buf,
                visible_decl: visible_decl_buf,
                const_value_record: &const_value_record_buf,
                struct_type_record: &struct_type_record_buf,
                decl_layout_record: &decl_layout_record_buf,
                decl_layout_status: &decl_layout_status_buf,
                param_reg_record: &param_reg_record_buf,
                node_tree_status: &node_tree_status_buf,
                enclosing_return_step_final: enclosing_return_step_final_buf,
                match_return_node: &match_return_node_buf,
                call_record: &call_record_buf,
                call_type_record: &call_type_record_buf,
                call_callee_root_call: call_callee_root_call_buf,
                call_callee_owner_step_final: call_callee_owner_step_final_buf,
                call_record_status: &call_record_status_buf,
                intrinsic_call_record: intrinsic_call_record_buf,
                intrinsic_call_status: &intrinsic_call_status_buf,
                enum_value_record: &enum_value_record_buf,
                enum_record_status: &enum_record_status_buf,
                match_record: &match_record_buf,
                match_pattern_node_owner: &match_pattern_node_owner_buf,
                match_result_value_owner: &match_result_value_owner_buf,
                struct_access_record: &struct_access_record_buf,
                struct_store_record: &struct_store_record_buf,
                struct_record_status: &struct_record_status_buf,
                for_iterable_node: &for_iterable_node_buf,
                node_control_padding: &node_control_padding_buf,
                postfix_operand_owner: &postfix_operand_owner_buf,
                node_inst_count_info: &node_inst_count_info_buf,
                node_inst_count_payload: &node_inst_count_payload_buf,
                node_inst_count_status: &node_inst_count_status_buf,
                node_inst_same_end_link_a: &node_inst_same_end_link_a_buf,
                node_inst_same_end_link_b: &node_inst_same_end_link_b_buf,
                node_inst_same_end_rank_a: node_inst_same_end_rank_a_buf,
                node_inst_same_end_rank_b: node_inst_same_end_rank_b_buf,
                node_inst_same_end_rank_final: node_inst_same_end_rank_final_buf,
                node_inst_same_end_rank_steps: &node_inst_same_end_rank_steps,
                node_inst_scan_input: node_inst_scan_input_buf,
                node_inst_order_record: &node_inst_order_record_buf,
                node_inst_same_end_bucket_count: node_inst_same_end_bucket_count_buf,
                node_inst_subtree_slot_bounds: node_inst_subtree_slot_bounds_buf,
                node_inst_range_start: &node_inst_range_start_buf,
                node_inst_range_info: &node_inst_range_info_buf,
                node_inst_range_status: &node_inst_range_status_buf,
                node_inst_order_status: &node_inst_order_status_buf,
                node_inst_scan_local_prefix: &node_inst_scan_local_prefix_buf,
                node_inst_scan_block_sum: node_inst_scan_block_sum_buf,
                node_inst_scan_prefix_a: node_inst_scan_prefix_a_buf,
                node_inst_scan_prefix_b: node_inst_scan_prefix_b_buf,
                final_node_inst_scan_prefix: final_node_inst_scan_prefix_buf,
                node_inst_subtree_bound_start: &node_inst_subtree_bound_start_buf,
                node_inst_subtree_bound_end: &node_inst_subtree_bound_end_buf,
                node_inst_subtree_bounds_status: &node_inst_subtree_bounds_status_buf,
                expr_semantic_type_a: expr_semantic_type_a_buf,
                expr_semantic_type_b: expr_semantic_type_b_buf,
                expr_semantic_type_final: expr_semantic_type_final_buf,
                expr_semantic_type_steps: &expr_semantic_type_steps,
                node_inst_location_record: node_inst_location_record_buf,
                node_inst_location_status: &node_inst_location_status_buf,
                node_inst_gen_node_record: &node_inst_gen_node_record_buf,
                node_inst_gen_input_status: &node_inst_gen_input_status_buf,
                active_node_inst_gen_dispatch_args: &node_order_scan,
                active_node_inst_gen_aggregate_copy_dispatch_args: &node_order_scan_block,
                enclosing_loop_node_a: enclosing_loop_node_a_buf,
                enclosing_loop_node_b: enclosing_loop_node_b_buf,
                enclosing_loop_link_a: enclosing_loop_link_a_buf,
                enclosing_loop_link_b: enclosing_loop_link_b_buf,
                enclosing_loop_steps: &enclosing_loop_steps,
                short_circuit_rhs_node_a: &short_circuit_rhs_node_a_buf,
                short_circuit_rhs_node_b: &short_circuit_rhs_node_b_buf,
                short_circuit_rhs_link_a: &short_circuit_rhs_link_a_buf,
                short_circuit_rhs_link_b: &short_circuit_rhs_link_b_buf,
                short_circuit_rhs_steps: &short_circuit_rhs_steps,
                index_source_owner_a: index_source_owner_a_buf,
                index_source_owner_b: index_source_owner_b_buf,
                index_source_link_a: index_source_link_a_buf,
                index_source_link_b: index_source_link_b_buf,
                index_source_owner_steps: &index_source_owner_steps,
            },
        )?;
        let InstGenBindGroups {
            input_status: node_inst_gen_inputs_bind_group,
            clear_dispatch_args: virtual_inst_clear_dispatch_args_bind_group,
            clear_virtual_insts: virtual_inst_clear_bind_group,
            generate: node_inst_gen_bind_group,
            aggregate_return_flags: aggregate_literal_return_copy_flags_bind_group,
            aggregate_return_copy: aggregate_literal_return_copy_bind_group,
            aggregate_copy: node_inst_gen_aggregate_copy_bind_group,
        } = create_inst_gen_bind_groups(
            self,
            device,
            InstGenBindGroupInputs {
                params: &params_buf,
                feature_params: &feature_params_buf,
                hir_kind: hir_kind_buf,
                hir_token_pos: function_metadata.hir_token_pos,
                parent: parent_buf,
                expr_metadata: &expr_metadata,
                array_metadata: &array_metadata,
                enum_metadata: &enum_metadata,
                struct_metadata: &struct_metadata,
                expr_resolved_final: &expr_resolved_final_buf,
                visible_decl: visible_decl_buf,
                visible_type: type_metadata.visible_type,
                struct_type_record: &struct_type_record_buf,
                decl_layout_record: &decl_layout_record_buf,
                decl_layout_status: &decl_layout_status_buf,
                const_value_record: &const_value_record_buf,
                const_value_status: &const_value_status_buf,
                local_literal_record: &local_literal_record_buf,
                local_literal_status: &local_literal_status_buf,
                param_reg_record: &param_reg_record_buf,
                param_reg_status: &param_reg_status_buf,
                call_abi_record: &call_abi_record_buf,
                call_abi_status: &call_abi_status_buf,
                call_arg_lookup_record: &call_arg_lookup_record_buf,
                intrinsic_call_record: intrinsic_call_record_buf,
                enum_value_record: &enum_value_record_buf,
                match_record: &match_record_buf,
                match_arm_owner: &match_arm_owner_buf,
                match_return_node: &match_return_node_buf,
                match_result_value_owner: &match_result_value_owner_buf,
                struct_access_record: &struct_access_record_buf,
                struct_store_record: &struct_store_record_buf,
                struct_record_status: &struct_record_status_buf,
                node_inst_range_info: &node_inst_range_info_buf,
                node_inst_location_record: node_inst_location_record_buf,
                node_inst_location_status: &node_inst_location_status_buf,
                node_inst_subtree_bound_start: &node_inst_subtree_bound_start_buf,
                node_inst_subtree_bound_end: &node_inst_subtree_bound_end_buf,
                expr_semantic_type_final: expr_semantic_type_final_buf,
                node_inst_scan_input: node_inst_scan_input_buf,
                node_inst_gen_input_status: &node_inst_gen_input_status_buf,
                node_inst_gen_node_record: &node_inst_gen_node_record_buf,
                active_virtual_inst_dispatch_args: &virtual_inst,
                enclosing_return_step_final: enclosing_return_step_final_buf,
                enclosing_let_step_final: enclosing_let_step_final_buf,
                enclosing_loop_step_final: enclosing_loop_step_final_buf,
                for_iterable_node: &for_iterable_node_buf,
                short_circuit_rhs_step_final: short_circuit_rhs_step_final_buf,
                index_source_owner_step_final: index_source_owner_step_final_buf,
                final_node_func: final_node_func_buf,
                func_slot_by_node: &func_slot_by_node_buf,
                virtual_inst_record: &virtual_inst_record_buf,
                virtual_inst_args: &virtual_inst_args_buf,
                virtual_inst_status: &virtual_inst_status_buf,
            },
        )?;
        let VirtualBindGroups {
            liveness_init: virtual_liveness_init_bind_group,
            liveness: virtual_liveness_bind_group,
            next_call: virtual_next_call_bind_groups,
            param_masks: virtual_param_masks_bind_group,
            spans_fixed_barrier: virtual_spans_fixed_barrier_bind_group,
            value_def_flags: virtual_value_def_flags_bind_group,
            value_def_scan_local: virtual_value_def_scan_local_bind_group,
            value_def_scan_block: virtual_value_def_scan_block_bind_groups,
            value_def_compact: virtual_value_def_compact_bind_group,
            regalloc: virtual_regalloc_bind_group,
            func_rows_init: virtual_func_rows_init_bind_group,
            func_first_row: virtual_func_first_row_bind_group,
            func_span_max: virtual_func_span_max_bind_group,
            regalloc_dispatch_args: virtual_regalloc_dispatch_args_bind_group,
        } = create_virtual_bind_groups(
            self,
            device,
            VirtualBindGroupInputs {
                params: &params_buf,
                text_scan_params: &text_scan_params_buf,
                next_call_params: &virtual_next_call_params_buf,
                regalloc_params: &virtual_regalloc_params_buf,
                func_meta: &func_meta_buf,
                func_slot_by_index: &func_slot_by_index_buf,
                func_slot_by_node: &func_slot_by_node_buf,
                final_node_func: final_node_func_buf,
                func_param_reg_mask: func_param_reg_mask_buf,
                func_param_reg_mask_status: &func_param_reg_mask_status_buf,
                virtual_inst_record: &virtual_inst_record_buf,
                virtual_inst_args: &virtual_inst_args_buf,
                virtual_inst_status: &virtual_inst_status_buf,
                virtual_func_slot: &virtual_func_slot_buf,
                virtual_next_call_a: &virtual_next_call_a_buf,
                virtual_next_call_b: &virtual_next_call_b_buf,
                virtual_next_call_status: &virtual_next_call_status_buf,
                virtual_live_start: &virtual_live_start_buf,
                virtual_live_end: &virtual_live_end_buf,
                virtual_liveness_status: &virtual_liveness_status_buf,
                virtual_phys_reg: &virtual_phys_reg_buf,
                virtual_call_live_reg_mask: &virtual_call_live_reg_mask_buf,
                virtual_func_first_row: virtual_func_first_row_buf,
                virtual_func_last_row: virtual_func_last_row_buf,
                virtual_func_first_row_status: &virtual_func_first_row_status_buf,
                virtual_value_def_flag: &virtual_value_def_flag_buf,
                virtual_value_def_scan_local_prefix: virtual_value_def_scan_local_prefix_buf,
                virtual_value_def_scan_block_sum: virtual_value_def_scan_block_sum_buf,
                virtual_value_def_scan_prefix_a: virtual_value_def_scan_prefix_a_buf,
                virtual_value_def_scan_prefix_b: virtual_value_def_scan_prefix_b_buf,
                virtual_value_def_row: &virtual_value_def_row_buf,
                virtual_value_def_status: &virtual_value_def_status_buf,
                virtual_regalloc_active_end: virtual_regalloc_active_end_buf,
                virtual_regalloc_param_rank_mask: &virtual_regalloc_param_rank_mask_buf,
                virtual_regalloc_status: &virtual_regalloc_status_buf,
                virtual_regalloc_dispatch_args: &virtual_regalloc,
            },
        )?;
        let EmitBindGroups {
            select: select_bind_group,
            inst_size: inst_size_bind_group,
            text_scan_local: text_scan_local_bind_group,
            text_scan_block: text_scan_block_bind_groups,
            text_offsets: text_offsets_bind_group,
            reloc_scan_local: reloc_scan_local_bind_group,
            reloc_scan_block: reloc_scan_block_bind_groups,
            reloc_records: reloc_records_bind_group,
            encode: encode_bind_group,
            reloc_patch: reloc_patch_bind_group,
            elf_layout: elf_layout_bind_group,
            elf: elf_bind_group,
        } = create_emit_bind_groups(
            self,
            device,
            EmitBindGroupInputs {
                params: &params_buf,
                text_scan_params: &text_scan_params_buf,
                func_meta: &func_meta_buf,
                decl_layout_status: &decl_layout_status_buf,
                virtual_inst_record: &virtual_inst_record_buf,
                virtual_inst_args: &virtual_inst_args_buf,
                virtual_inst_status: &virtual_inst_status_buf,
                virtual_phys_reg: &virtual_phys_reg_buf,
                virtual_call_live_reg_mask: &virtual_call_live_reg_mask_buf,
                virtual_regalloc_status: &virtual_regalloc_status_buf,
                virtual_func_first_row: virtual_func_first_row_buf,
                virtual_func_first_row_status: &virtual_func_first_row_status_buf,
                virtual_func_slot: &virtual_func_slot_buf,
                virtual_value_def_flag: &virtual_value_def_flag_buf,
                inst_kind: inst_kind_buf,
                inst_arg0: inst_arg0_buf,
                inst_arg1: inst_arg1_buf,
                inst_arg2: inst_arg2_buf,
                inst_size: inst_size_buf,
                inst_byte_offset: inst_byte_offset_buf,
                select_status: &select_status_buf,
                size_status: &size_status_buf,
                text_scan_local_prefix: text_scan_local_prefix_buf,
                text_scan_block_sum: &text_scan_block_sum_buf,
                text_scan_prefix_a: &text_scan_prefix_a_buf,
                text_scan_prefix_b: &text_scan_prefix_b_buf,
                text_len: &text_len_buf,
                text_status: &text_status_buf,
                reloc_count: &reloc_count_buf,
                reloc_kind: reloc_kind_buf,
                reloc_site_inst: reloc_site_inst_buf,
                reloc_target_inst: reloc_target_inst_buf,
                reloc_status: &reloc_status_buf,
                out: &out_buf,
                encode_status: &encode_status_buf,
                elf_layout: &elf_layout_buf,
                layout_status: &layout_status_buf,
                status: &status_buf,
            },
        )?;
        host_timer.stamp("bind_groups");

        record_metadata_and_call_dispatches(
            self,
            MetadataCallDispatchInputs {
                device,
                queue,
                encoder,
                timer: &mut timer,
                hir_words,
                match_record_rows,
                has_match: feature_summary.has_match(),
                needs_enclosing_return_records,
                node_func_owner_needs_copyback,
                enclosing_let_needs_copyback,
                match_pattern_owner_needs_copyback: match_pattern_owner_steps.len() % 2 != 0,
                active_hir_dispatch_args_buf,
                hir_count: &hir_count,
                hir_plus_one: &hir_plus_one,
                hir_scan_block: &hir_scan_block,
                func_owner_scan_params_buf: &func_owner_scan_params_buf,
                node_inst_scan_params_buf: &node_inst_scan_params_buf,
                node_func_owner_b_buf,
                node_func_buf: &node_func_buf,
                expr_resolved_step_final_buf,
                expr_resolved_final_buf: &expr_resolved_final_buf,
                match_result_owner_step_final_buf,
                match_result_value_owner_buf: &match_result_value_owner_buf,
                enclosing_let_node_b_buf: &enclosing_let_node_b_buf,
                enclosing_let_node_a_buf: &enclosing_let_node_a_buf,
                match_pattern_owner_step_final_buf,
                match_pattern_node_owner_buf: &match_pattern_node_owner_buf,
                match_pattern_first_use_node_buf: &match_pattern_first_use_node_buf,
                func_meta_buf: &func_meta_buf,
                func_meta_uniform_buf: &func_meta_uniform_buf,
                const_value_status_buf: &const_value_status_buf,
                const_value_status_uniform_buf: &const_value_status_uniform_buf,
                param_reg_status_buf: &param_reg_status_buf,
                param_reg_status_uniform_buf: &param_reg_status_uniform_buf,
                local_literal_status_buf: &local_literal_status_buf,
                local_literal_status_uniform_buf: &local_literal_status_uniform_buf,
                intrinsic_call_record_buf,
                call_abi_status_buf: &call_abi_status_buf,
                call_abi_status_uniform_buf: &call_abi_status_uniform_buf,
                active_scan_dispatch_args_bind_group: &active_scan_dispatch_args_bind_group,
                node_tree_info_bind_group: &node_tree_info_bind_group,
                func_bind_group: &func_bind_group,
                func_owner_scan_local_bind_group: &func_owner_scan_local_bind_group,
                func_owner_scan_block_bind_groups: &func_owner_scan_block_bind_groups,
                func_assign_nodes_bind_group: &func_assign_nodes_bind_group,
                func_assign_nodes_step_bind_groups: &func_assign_nodes_step_bind_groups,
                func_slot_flags_bind_group: &func_slot_flags_bind_group,
                func_slot_scatter_bind_group: &func_slot_scatter_bind_group,
                expr_resolve_init_bind_group: &expr_resolve_init_bind_group,
                expr_resolve_step_bind_groups: &expr_resolve_step_bind_groups,
                enum_records_bind_group: &enum_records_bind_group,
                match_records_bind_group: &match_records_bind_group,
                return_match_records_bind_group: &return_match_records_bind_group,
                match_result_owner_init_bind_group: &match_result_owner_init_bind_group,
                match_result_owner_step_bind_groups: &match_result_owner_step_bind_groups,
                enclosing_return_init_bind_group: &enclosing_return_init_bind_group,
                enclosing_return_step_bind_groups: &enclosing_return_step_bind_groups,
                enclosing_let_init_bind_group: &enclosing_let_init_bind_group,
                enclosing_let_step_bind_groups: &enclosing_let_step_bind_groups,
                match_ownership_bind_group: &match_ownership_bind_group,
                match_pattern_owner_init_bind_group: &match_pattern_owner_init_bind_group,
                match_pattern_owner_step_bind_groups: &match_pattern_owner_step_bind_groups,
                match_pattern_records_bind_group: &match_pattern_records_bind_group,
                match_pattern_finalize_bind_group: &match_pattern_finalize_bind_group,
                struct_records_bind_group: &struct_records_bind_group,
                array_records_bind_group: &array_records_bind_group,
                enclosing_stmt_init_bind_group: &enclosing_stmt_init_bind_group,
                enclosing_stmt_step_bind_groups: &enclosing_stmt_step_bind_groups,
                decl_widths_bind_group: &decl_widths_bind_group,
                decl_layout_bind_group: &decl_layout_bind_group,
                node_inst_scan_local_bind_group: &node_inst_scan_local_bind_group,
                node_inst_scan_block_bind_groups: &node_inst_scan_block_bind_groups,
                node_inst_scan_input_clear_bind_group: &node_inst_scan_input_clear_bind_group,
                call_callee_root_call_clear_bind_group: &call_callee_root_call_clear_bind_group,
                call_records_bind_group: &call_records_bind_group,
                const_values_bind_group: &const_values_bind_group,
                param_regs_bind_group: &param_regs_bind_group,
                local_literals_bind_group: &local_literals_bind_group,
                call_arg_values_bind_group: &call_arg_values_bind_group,
                intrinsic_calls_bind_group: &intrinsic_calls_bind_group,
                call_abi_bind_group: &call_abi_bind_group,
                call_callee_owner_init_bind_group: &call_callee_owner_init_bind_group,
                call_callee_owner_step_bind_groups: &call_callee_owner_step_bind_groups,
            },
        )?;
        record_instruction_dispatches(
            self,
            InstructionDispatchInputs {
                encoder,
                timer: &mut timer,
                has_aggregate: feature_summary.has_aggregate(),
                active_hir_dispatch_args: active_hir_dispatch_args_buf,
                hir_plus_one: &hir_plus_one,
                hir_scan_block: &hir_scan_block,
                node_order_scan: &node_order_scan,
                node_order_scan_block: &node_order_scan_block,
                virtual_inst: &virtual_inst,
                node_inst_scan_params: &node_inst_scan_params_buf,
                for_iterable_nodes: &for_iterable_nodes_bind_group,
                control_padding: &control_padding_bind_group,
                postfix_operand_owner: &postfix_operand_owner_bind_group,
                node_inst_counts: &node_inst_counts_bind_group,
                node_inst_same_end_rank_init: &node_inst_same_end_rank_init_bind_group,
                node_inst_same_end_rank_step: &node_inst_same_end_rank_step_bind_groups,
                node_inst_end_counts: &node_inst_end_counts_bind_group,
                node_inst_scan_local: &node_inst_scan_local_bind_group,
                node_inst_scan_block: &node_inst_scan_block_bind_groups,
                node_inst_order: &node_inst_order_bind_group,
                node_order_dispatch_args: &node_order_dispatch_args_bind_group,
                node_inst_prefix_scan: &node_inst_prefix_scan_bind_group,
                node_inst_subtree_bounds: &node_inst_subtree_bounds_bind_group,
                expr_semantic_type_init: &expr_semantic_type_init_bind_group,
                expr_semantic_type_step: &expr_semantic_type_step_bind_groups,
                node_inst_locations: &node_inst_locations_bind_group,
                node_inst_gen_worklist_scatter: &node_inst_gen_worklist_scatter_bind_group,
                node_inst_gen_worklist_dispatch_args:
                    &node_inst_gen_worklist_dispatch_args_bind_group,
                enclosing_loop_init: &enclosing_loop_init_bind_group,
                enclosing_loop_step: &enclosing_loop_step_bind_groups,
                short_circuit_rhs_init: &short_circuit_rhs_init_bind_group,
                short_circuit_rhs_step: &short_circuit_rhs_step_bind_groups,
                index_source_owner_init: &index_source_owner_init_bind_group,
                index_source_owner_step: &index_source_owner_step_bind_groups,
                node_inst_gen_inputs: &node_inst_gen_inputs_bind_group,
                virtual_inst_clear_dispatch_args: &virtual_inst_clear_dispatch_args_bind_group,
                virtual_inst_clear: &virtual_inst_clear_bind_group,
                node_inst_gen: &node_inst_gen_bind_group,
                node_inst_gen_aggregate_copy: &node_inst_gen_aggregate_copy_bind_group,
                aggregate_literal_return_copy_flags:
                    &aggregate_literal_return_copy_flags_bind_group,
                aggregate_literal_return_copy: &aggregate_literal_return_copy_bind_group,
            },
        );
        record_virtual_emit_dispatches(
            self,
            VirtualEmitDispatchInputs {
                encoder,
                timer: &mut timer,
                virtual_dispatch_arg_groups,
                virtual_next_call_params: &virtual_next_call_params_buf,
                virtual_regalloc_params: &virtual_regalloc_params_buf,
                text_scan_params: &text_scan_params_buf,
                function_dispatch: &function_dispatch,
                virtual_inst: &virtual_inst,
                virtual_next_call_dispatch: &virtual_next_call,
                virtual_regalloc: &virtual_regalloc,
                selected_inst: &selected_inst,
                selected_scan_block: &selected_scan_block,
                elf_header_word: &elf_header_word,
                virtual_dispatch_args: &virtual_dispatch_args_bind_group,
                virtual_func_rows_init: &virtual_func_rows_init_bind_group,
                virtual_func_first_row: &virtual_func_first_row_bind_group,
                virtual_func_span_max: &virtual_func_span_max_bind_group,
                virtual_regalloc_dispatch_args: &virtual_regalloc_dispatch_args_bind_group,
                virtual_next_call_bind_groups: &virtual_next_call_bind_groups,
                virtual_param_masks: &virtual_param_masks_bind_group,
                virtual_liveness_init: &virtual_liveness_init_bind_group,
                virtual_liveness: &virtual_liveness_bind_group,
                virtual_spans_fixed_barrier: &virtual_spans_fixed_barrier_bind_group,
                virtual_value_def_flags: &virtual_value_def_flags_bind_group,
                virtual_value_def_scan_local: &virtual_value_def_scan_local_bind_group,
                virtual_value_def_scan_block: &virtual_value_def_scan_block_bind_groups,
                virtual_value_def_compact: &virtual_value_def_compact_bind_group,
                virtual_regalloc_bind_group: &virtual_regalloc_bind_group,
                select: &select_bind_group,
                inst_size: &inst_size_bind_group,
                text_scan_local: &text_scan_local_bind_group,
                text_scan_block: &text_scan_block_bind_groups,
                text_offsets: &text_offsets_bind_group,
                reloc_scan_local: &reloc_scan_local_bind_group,
                reloc_scan_block: &reloc_scan_block_bind_groups,
                reloc_records: &reloc_records_bind_group,
                output_dispatch_args: &output_dispatch_args_bind_group,
                encode: &encode_bind_group,
                reloc_patch: &reloc_patch_bind_group,
                elf_layout: &elf_layout_bind_group,
                elf: &elf_bind_group,
            },
        );
        encoder.copy_buffer_to_buffer(&out_buf, 0, &output_readback, 0, output_readback_bytes);
        encoder.copy_buffer_to_buffer(&status_buf, 0, &output_readback, output_status_offset, 16);
        let status_trace_readback = record_status_trace_readback(
            device,
            encoder,
            StatusTraceSources {
                hir_status: hir_status_buf,
                hir_count: &hir_count,
                hir_plus_one: &hir_plus_one,
                func_meta: &func_meta_buf,
                node_tree_status: &node_tree_status_buf,
                enum_record_status: &enum_record_status_buf,
                struct_record_status: &struct_record_status_buf,
                decl_layout_status: &decl_layout_status_buf,
                node_inst_count_status: &node_inst_count_status_buf,
                node_inst_order_status: &node_inst_order_status_buf,
                node_inst_range_status: &node_inst_range_status_buf,
                node_inst_subtree_bounds_status: &node_inst_subtree_bounds_status_buf,
                node_inst_location_status: &node_inst_location_status_buf,
                node_inst_gen_input_status: &node_inst_gen_input_status_buf,
                virtual_inst_status: &virtual_inst_status_buf,
                virtual_func_first_row_status: &virtual_func_first_row_status_buf,
                virtual_next_call_status: &virtual_next_call_status_buf,
                func_param_reg_mask_status: &func_param_reg_mask_status_buf,
                virtual_liveness_status: &virtual_liveness_status_buf,
                virtual_regalloc_status: &virtual_regalloc_status_buf,
                select_status: &select_status_buf,
                size_status: &size_status_buf,
                text_status: &text_status_buf,
                reloc_status: &reloc_status_buf,
                encode_status: &encode_status_buf,
                layout_status: &layout_status_buf,
                status: &status_buf,
            },
        );
        host_timer.stamp("dispatch_and_readbacks_recorded");

        macro_rules! retain_x86_buffers {
            ($($buffer:expr),+ $(,)?) => {{
                let mut buffers = Vec::<RetainedX86Buffer>::new();
                $(buffers.push(RetainedX86Buffer::from($buffer));)+
                buffers
            }};
        }

        let mut retained_buffers = retain_x86_buffers![
            params_buf,
            hir_count,
            hir_plus_one,
            hir_scan_block,
            node_order_scan,
            node_order_scan_block,
            function_dispatch,
            virtual_inst,
            virtual_next_call,
            virtual_regalloc,
            selected_inst,
            selected_scan_block,
            text_word,
            elf_header_word,
            func_meta_buf,
            func_meta_uniform_buf,
            node_tree_status_buf,
            expr_resolved_final_buf,
            node_func_buf,
            func_owner_scan_local_prefix_buf,
            func_owner_scan_block_sum_buf,
            func_owner_scan_prefix_a_buf,
            func_owner_scan_prefix_b_buf,
            enum_type_record_buf,
            enum_value_record_buf,
            enum_record_status_buf,
            match_record_buf,
            match_arm_owner_buf,
            match_return_node_buf,
            match_pattern_owner_buf,
            match_result_value_owner_buf,
            match_pattern_node_owner_buf,
            match_pattern_node_variant_buf,
            match_pattern_node_payload_decl_buf,
            match_pattern_first_use_node_buf,
            enclosing_return_node_a_buf,
            enclosing_return_node_b_buf,
            enclosing_let_node_a_buf,
            enclosing_let_node_b_buf,
            struct_type_record_buf,
            struct_access_record_buf,
            struct_store_record_buf,
            struct_record_status_buf,
            decl_layout_record_buf,
            decl_layout_status_buf,
            decl_node_by_token_buf,
            func_slot_by_index_buf,
            call_record_buf,
            call_type_record_buf,
            call_record_status_buf,
            const_value_record_buf,
            const_value_status_buf,
            const_value_status_uniform_buf,
            param_reg_record_buf,
            param_reg_status_buf,
            param_reg_status_uniform_buf,
            local_literal_record_buf,
            local_literal_status_buf,
            local_literal_status_uniform_buf,
            node_inst_order_record_buf,
            call_arg_lookup_record_buf,
            intrinsic_call_status_buf,
            call_abi_record_buf,
            call_abi_status_buf,
            call_abi_status_uniform_buf,
            for_iterable_node_buf,
            node_control_padding_buf,
            postfix_operand_owner_buf,
            node_inst_same_end_link_a_buf,
            node_inst_same_end_link_b_buf,
            node_inst_count_status_buf,
            node_inst_order_status_buf,
            node_inst_scan_local_prefix_buf,
            node_inst_range_start_buf,
            node_inst_range_info_buf,
            node_inst_range_status_buf,
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
            virtual_func_first_row_status_buf,
            virtual_func_slot_buf,
            virtual_live_start_buf,
            virtual_live_end_buf,
            virtual_liveness_status_buf,
            virtual_next_call_a_buf,
            virtual_next_call_b_buf,
            virtual_next_call_status_buf,
            func_param_reg_mask_status_buf,
            virtual_value_def_flag_buf,
            virtual_value_def_row_buf,
            virtual_regalloc_param_rank_mask_buf,
            virtual_phys_reg_buf,
            virtual_call_live_reg_mask_buf,
            virtual_regalloc_status_buf,
            select_status_buf,
            size_status_buf,
            text_len_buf,
            text_status_buf,
            text_scan_block_sum_buf,
            text_scan_prefix_a_buf,
            text_scan_prefix_b_buf,
            reloc_count_buf,
            reloc_status_buf,
            encode_status_buf,
            elf_layout_buf,
            layout_status_buf,
            status_buf,
        ];
        if let Some(buffer) = match_pattern_first_variant_node_storage_buf {
            retained_buffers.push(RetainedX86Buffer::from(buffer));
        }
        if let Some(buffer) = match_pattern_first_payload_node_storage_buf {
            retained_buffers.push(RetainedX86Buffer::from(buffer));
        }
        if let Some(buffer) = empty_param_record_buf {
            retained_buffers.push(RetainedX86Buffer::from(buffer));
        }
        retained_buffers.push(RetainedX86Buffer::from(
            func_owner_scan_params_buf.into_buffer(),
        ));
        retained_buffers.push(RetainedX86Buffer::from(
            node_inst_scan_params_buf.into_buffer(),
        ));
        retained_buffers.push(RetainedX86Buffer::from(text_scan_params_buf.into_buffer()));
        retained_buffers.push(RetainedX86Buffer::from(
            virtual_next_call_params_buf.into_buffer(),
        ));
        retained_buffers.push(RetainedX86Buffer::from(
            virtual_regalloc_params_buf.into_buffer(),
        ));
        host_timer.stamp("retained_buffers_collected");

        let mut retained_bind_groups = vec![
            active_scan_dispatch_args_bind_group,
            node_inst_scan_input_clear_bind_group,
            node_order_dispatch_args_bind_group,
            virtual_dispatch_args_bind_group,
            output_dispatch_args_bind_group,
            node_tree_info_bind_group,
            func_bind_group,
            func_owner_scan_local_bind_group,
            func_assign_nodes_bind_group,
            expr_resolve_init_bind_group,
            enum_records_bind_group,
            match_records_bind_group,
            match_pattern_records_bind_group,
            enclosing_return_init_bind_group,
            enclosing_let_init_bind_group,
            enclosing_stmt_init_bind_group,
            return_match_records_bind_group,
            match_result_owner_init_bind_group,
            match_ownership_bind_group,
            match_pattern_owner_init_bind_group,
            match_pattern_finalize_bind_group,
            struct_records_bind_group,
            array_records_bind_group,
            expr_semantic_type_init_bind_group,
            decl_layout_bind_group,
            decl_widths_bind_group,
            const_values_bind_group,
            param_regs_bind_group,
            local_literals_bind_group,
            call_records_bind_group,
            call_callee_owner_init_bind_group,
            call_arg_values_bind_group,
            intrinsic_calls_bind_group,
            call_abi_bind_group,
            for_iterable_nodes_bind_group,
            control_padding_bind_group,
            node_inst_same_end_rank_init_bind_group,
            node_inst_end_counts_bind_group,
            node_inst_counts_bind_group,
            enclosing_loop_init_bind_group,
            short_circuit_rhs_init_bind_group,
            index_source_owner_init_bind_group,
            node_inst_scan_local_bind_group,
            node_inst_prefix_scan_bind_group,
            node_inst_order_bind_group,
            node_inst_subtree_bounds_bind_group,
            node_inst_locations_bind_group,
            node_inst_gen_inputs_bind_group,
            virtual_inst_clear_dispatch_args_bind_group,
            virtual_inst_clear_bind_group,
            node_inst_gen_bind_group,
            aggregate_literal_return_copy_bind_group,
            node_inst_gen_aggregate_copy_bind_group,
            virtual_func_rows_init_bind_group,
            virtual_func_first_row_bind_group,
            virtual_func_span_max_bind_group,
            virtual_regalloc_dispatch_args_bind_group,
            virtual_regalloc_bind_group,
            virtual_spans_fixed_barrier_bind_group,
            virtual_param_masks_bind_group,
            virtual_liveness_init_bind_group,
            virtual_liveness_bind_group,
            select_bind_group,
            inst_size_bind_group,
            text_scan_local_bind_group,
            text_offsets_bind_group,
            reloc_scan_local_bind_group,
            reloc_records_bind_group,
            encode_bind_group,
            reloc_patch_bind_group,
            elf_layout_bind_group,
            elf_bind_group,
        ];
        retained_bind_groups.extend(func_owner_scan_block_bind_groups);
        retained_bind_groups.extend(func_assign_nodes_step_bind_groups);
        retained_bind_groups.extend(expr_resolve_step_bind_groups);
        retained_bind_groups.extend(enclosing_return_step_bind_groups);
        retained_bind_groups.extend(enclosing_let_step_bind_groups);
        retained_bind_groups.extend(match_result_owner_step_bind_groups);
        retained_bind_groups.extend(enclosing_stmt_step_bind_groups);
        retained_bind_groups.extend(call_callee_owner_step_bind_groups);
        retained_bind_groups.extend(match_pattern_owner_step_bind_groups);
        retained_bind_groups.extend(node_inst_same_end_rank_step_bind_groups);
        retained_bind_groups.extend(expr_semantic_type_step_bind_groups);
        retained_bind_groups.extend(enclosing_loop_step_bind_groups);
        retained_bind_groups.extend(short_circuit_rhs_step_bind_groups);
        retained_bind_groups.extend(index_source_owner_step_bind_groups);
        retained_bind_groups.extend(node_inst_scan_block_bind_groups);
        retained_bind_groups.extend(virtual_next_call_bind_groups);
        retained_bind_groups.extend(text_scan_block_bind_groups);
        retained_bind_groups.extend(reloc_scan_block_bind_groups);
        host_timer.stamp("retained_bind_groups_collected");

        Ok(RetainedRecording::new(
            output_capacity,
            output_status_offset,
            retained_buffers,
            retained_bind_groups,
            out_buf,
            output_readback,
            status_trace_readback,
        )
        .into_recorded(&mut host_timer))
    }
}
