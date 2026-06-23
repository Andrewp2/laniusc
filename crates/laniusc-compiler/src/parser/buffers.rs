//! GPU buffer allocation for parser token facts, pair streams, tree rows, and HIR rows.

mod constructors;
mod model;
mod scan_steps;
mod scans;
mod sizing;
mod storage;
pub use model::{ActionHeader, ParserBuffers, TokenBraceMatchParams, TokenDelimiterParams};
pub use scan_steps::*;
use scans::*;
use sizing::resident_partial_parse_tree_capacity;
pub(crate) use sizing::resident_partial_parse_tree_capacity_for_tables;
use storage::{alias_storage_buffer, dispatch_args_buffer};

use crate::gpu::buffers::{
    LaniusBuffer,
    storage_ro_from_bytes,
    storage_ro_from_u32s,
    storage_rw_for_array,
    uniform_from_val,
};

impl ParserBuffers {
    fn new_with_sizing(
        device: &wgpu::Device,
        n_tokens: u32,
        token_kinds_u32: Option<&[u32]>,
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
        resident_partial_parse_capacity: bool,
        retain_debug_hir_buffers: bool,
        tree_capacity_override: Option<u32>,
    ) -> Self {
        let n_pairs = n_tokens.saturating_sub(1) as usize;
        let token_input_capacity = n_tokens.saturating_sub(2).max(1);
        let token_delimiter_n_blocks = token_input_capacity.div_ceil(256).max(1);
        let pair_capacity = n_pairs.max(1);
        let ll1_stack_capacity = 1;
        let empty = [0u32];
        let ll1_predict_src = if tables.ll1_predict.is_empty() {
            &empty[..]
        } else {
            &tables.ll1_predict
        };
        let ll1_rhs_off_src = if tables.prod_rhs_off.is_empty() {
            &empty[..]
        } else {
            &tables.prod_rhs_off
        };
        let ll1_rhs_len_src = if tables.prod_rhs_len.is_empty() {
            &empty[..]
        } else {
            &tables.prod_rhs_len
        };
        let ll1_rhs_src = if tables.prod_rhs.is_empty() {
            &empty[..]
        } else {
            &tables.prod_rhs
        };
        let ll1_predict = storage_ro_from_u32s(device, "parser.ll1_predict", ll1_predict_src);
        let ll1_prod_rhs_off =
            storage_ro_from_u32s(device, "parser.ll1_prod_rhs_off", ll1_rhs_off_src);
        let ll1_prod_rhs_len =
            storage_ro_from_u32s(device, "parser.ll1_prod_rhs_len", ll1_rhs_len_src);
        let ll1_prod_rhs = storage_ro_from_u32s(device, "parser.ll1_prod_rhs", ll1_rhs_src);
        let ll1_emit =
            storage_rw_for_array::<u32>(device, "parser.ll1_emit", ll1_stack_capacity as usize);
        let ll1_emit_pos =
            storage_rw_for_array::<u32>(device, "parser.ll1_emit_pos", ll1_stack_capacity as usize);
        let ll1_status = storage_rw_for_array::<u32>(device, "parser.ll1_status", 6);

        let stream_has_soi = token_kinds_u32
            .map(|kinds| kinds.first().copied() == Some(0))
            .unwrap_or(true);
        let first_input = if n_tokens > 1 && stream_has_soi { 1 } else { 0 };
        // Match the canonical LL(1) stream: the last token is the EOF sentinel and is not
        // consumed as ordinary input.
        let input_end = n_tokens.saturating_sub(1);
        let n_input_tokens = input_end.saturating_sub(first_input);
        let token_count = storage_ro_from_u32s(device, "parser.token_count", &[n_input_tokens]);
        let active_pair_thread_dispatch_args =
            dispatch_args_buffer(device, "parser.active_pair_thread_dispatch_args");
        let active_pair_group_dispatch_args =
            dispatch_args_buffer(device, "parser.active_pair_group_dispatch_args");
        // ---------- Pair-to-header ----------
        let semantic_token_kinds = if let Some(kinds) = token_kinds_u32 {
            // Test/debug one-shot parsing receives already-classified parser
            // token kinds. Resident compilation fills this buffer on the GPU
            // with `tokens_to_kinds` instead.
            storage_ro_from_u32s(device, "parser.semantic_token_kinds.input", kinds)
        } else {
            storage_rw_for_array::<u32>(device, "parser.semantic_token_kinds", n_tokens as usize)
        };
        let token_delimiter_params = uniform_from_val(
            device,
            "parser.token_delimiters.params",
            &TokenDelimiterParams {
                n_tokens: token_input_capacity,
                n_blocks: token_delimiter_n_blocks,
                scan_step: 0,
            },
        );
        let token_delimiter_scan_steps =
            make_token_delimiter_scan_steps(device, token_input_capacity, token_delimiter_n_blocks);
        let token_depth_paren_inblock = storage_rw_for_array::<i32>(
            device,
            "parser.token_depth_paren_inblock",
            token_input_capacity as usize,
        );
        let token_depth_brace_inblock = storage_rw_for_array::<i32>(
            device,
            "parser.token_depth_brace_inblock",
            token_input_capacity as usize,
        );
        let token_depth_bracket_inblock = storage_rw_for_array::<i32>(
            device,
            "parser.token_depth_bracket_inblock",
            n_tokens.max(1) as usize,
        );
        let token_depth_angle_inblock = storage_rw_for_array::<i32>(
            device,
            "parser.token_depth_angle_inblock",
            token_input_capacity as usize,
        );
        let token_block_sum_paren = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_sum_paren",
            token_delimiter_n_blocks as usize,
        );
        let token_block_sum_brace = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_sum_brace",
            token_delimiter_n_blocks as usize,
        );
        let token_block_sum_bracket = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_sum_bracket",
            token_delimiter_n_blocks as usize,
        );
        let token_block_sum_angle = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_sum_angle",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_paren_a = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_paren_a",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_paren_b = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_paren_b",
            token_delimiter_n_blocks as usize,
        );
        let token_block_prefix_paren = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_prefix_paren",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_brace_a = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_brace_a",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_brace_b = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_brace_b",
            token_delimiter_n_blocks as usize,
        );
        let token_block_prefix_brace = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_prefix_brace",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_bracket_a = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_bracket_a",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_bracket_b = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_bracket_b",
            token_delimiter_n_blocks as usize,
        );
        let token_block_prefix_bracket = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_prefix_bracket",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_angle_a = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_angle_a",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_angle_b = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_angle_b",
            token_delimiter_n_blocks as usize,
        );
        let token_block_prefix_angle = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_prefix_angle",
            token_delimiter_n_blocks as usize,
        );
        let token_top_brace_owner_block = storage_rw_for_array::<u32>(
            device,
            "parser.token_top_brace_owner_block",
            token_delimiter_n_blocks as usize,
        );
        let token_top_brace_owner_prefix_a = storage_rw_for_array::<u32>(
            device,
            "parser.token_top_brace_owner_prefix_a",
            token_delimiter_n_blocks as usize,
        );
        let token_top_brace_owner_prefix_b = storage_rw_for_array::<u32>(
            device,
            "parser.token_top_brace_owner_prefix_b",
            token_delimiter_n_blocks as usize,
        );
        let token_top_brace_owner_block_prefix = storage_rw_for_array::<u32>(
            device,
            "parser.token_top_brace_owner_block_prefix",
            token_delimiter_n_blocks as usize,
        );
        let token_statement_event_block = storage_rw_for_array::<u32>(
            device,
            "parser.token_statement_event_block",
            token_delimiter_n_blocks as usize,
        );
        let token_statement_event_prefix_a = storage_rw_for_array::<u32>(
            device,
            "parser.token_statement_event_prefix_a",
            token_delimiter_n_blocks as usize,
        );
        let token_statement_event_prefix_b = storage_rw_for_array::<u32>(
            device,
            "parser.token_statement_event_prefix_b",
            token_delimiter_n_blocks as usize,
        );
        let token_statement_event_block_prefix = storage_rw_for_array::<u32>(
            device,
            "parser.token_statement_event_block_prefix",
            token_delimiter_n_blocks as usize,
        );
        let token_brace_semantic_kind = storage_rw_for_array::<u32>(
            device,
            "parser.token_brace_semantic_kind",
            n_tokens.max(1) as usize,
        );
        let token_bracket_semantic_kind = storage_rw_for_array::<u32>(
            device,
            "parser.token_bracket_semantic_kind",
            token_input_capacity as usize,
        );
        let token_statement_context_kind = storage_rw_for_array::<u32>(
            device,
            "parser.token_statement_context_kind",
            token_input_capacity as usize,
        );
        let token_impl_header_kind = storage_rw_for_array::<u32>(
            device,
            "parser.token_impl_header_kind",
            token_input_capacity as usize,
        );
        let token_impl_context_event = storage_rw_for_array::<u32>(
            device,
            "parser.token_impl_context_event",
            token_input_capacity as usize,
        );
        let token_type_path_context_kind = storage_rw_for_array::<u32>(
            device,
            "parser.token_type_path_context_kind",
            token_input_capacity as usize,
        );
        let token_where_context_event = storage_rw_for_array::<u32>(
            device,
            "parser.token_where_context_event",
            token_input_capacity as usize,
        );
        let token_match_pattern_context_event = storage_rw_for_array::<u32>(
            device,
            "parser.token_match_pattern_context_event",
            token_input_capacity as usize,
        );
        let token_brace_match_params = uniform_from_val(
            device,
            "parser.token_brace_match.params",
            &TokenBraceMatchParams {
                n_tokens: token_input_capacity,
            },
        );
        let token_brace_match_depth = storage_rw_for_array::<i32>(
            device,
            "parser.token_brace_match_depth",
            token_input_capacity as usize,
        );
        let token_brace_match_block_min = storage_rw_for_array::<i32>(
            device,
            "parser.token_brace_match_block_min",
            token_delimiter_n_blocks as usize,
        );
        let token_brace_match_min_tree_base =
            next_power_of_two_u32(token_delimiter_n_blocks).max(1);
        let token_brace_match_min_tree = storage_rw_for_array::<i32>(
            device,
            "parser.token_brace_match_min_tree",
            token_brace_match_min_tree_base.saturating_mul(2) as usize,
        );
        let token_brace_match_min_tree_steps = make_tree_prefix_max_build_steps(
            device,
            token_delimiter_n_blocks,
            token_brace_match_min_tree_base,
        );
        let token_bracket_match_depth = storage_rw_for_array::<i32>(
            device,
            "parser.token_bracket_match_depth",
            token_input_capacity as usize,
        );
        let token_bracket_match_block_min = storage_rw_for_array::<i32>(
            device,
            "parser.token_bracket_match_block_min",
            token_delimiter_n_blocks as usize,
        );
        let token_bracket_match_min_tree = storage_rw_for_array::<i32>(
            device,
            "parser.token_bracket_match_min_tree",
            token_brace_match_min_tree_base.saturating_mul(2) as usize,
        );
        let token_paren_match_depth = storage_rw_for_array::<i32>(
            device,
            "parser.token_paren_match_depth",
            token_input_capacity as usize,
        );
        let token_paren_match_block_min = storage_rw_for_array::<i32>(
            device,
            "parser.token_paren_match_block_min",
            token_delimiter_n_blocks as usize,
        );
        let token_paren_match_min_tree = storage_rw_for_array::<i32>(
            device,
            "parser.token_paren_match_min_tree",
            token_brace_match_min_tree_base.saturating_mul(2) as usize,
        );
        let token_angle_match_depth = storage_rw_for_array::<i32>(
            device,
            "parser.token_angle_match_depth",
            token_input_capacity as usize,
        );
        let token_angle_match_block_min = storage_rw_for_array::<i32>(
            device,
            "parser.token_angle_match_block_min",
            token_delimiter_n_blocks as usize,
        );
        let token_angle_match_min_tree = storage_rw_for_array::<i32>(
            device,
            "parser.token_angle_match_min_tree",
            token_brace_match_min_tree_base.saturating_mul(2) as usize,
        );
        let token_feature_flags = if token_kinds_u32.is_some() {
            storage_ro_from_u32s(
                device,
                "parser.token_feature_flags.conservative",
                &[u32::MAX],
            )
        } else {
            storage_ro_from_u32s(device, "parser.token_feature_flags", &[0])
        };

        let params_llp = uniform_from_val(
            device,
            "parser.params_llp",
            &super::passes::llp_pairs::LLPParams { n_tokens, n_kinds },
        );

        let action_table = if action_table_bytes.is_empty() {
            let one = vec![0u8; core::mem::size_of::<ActionHeader>()];
            storage_ro_from_bytes::<u8>(device, "parser.action_table", &one, one.len())
        } else {
            storage_ro_from_bytes::<u8>(
                device,
                "parser.action_table",
                action_table_bytes,
                action_table_bytes.len(),
            )
        };

        let out_headers: LaniusBuffer<ActionHeader> = storage_rw_for_array::<ActionHeader>(
            device,
            "parser.out_headers",
            pair_capacity.saturating_add(1),
        );

        // ---------- Pack varlen ----------
        let (mut acc_sc, mut acc_emit) = (0u32, 0u32);

        if resident_partial_parse_capacity {
            let max_sc_len = tables.sc_len.iter().copied().max().unwrap_or(0);
            let max_emit_len = tables.pp_len.iter().copied().max().unwrap_or(0);
            acc_sc = (n_pairs as u32).saturating_mul(max_sc_len);
            acc_emit = (n_pairs as u32).saturating_mul(max_emit_len);
        } else {
            let token_kinds_u32 =
                token_kinds_u32.expect("non-resident parser sizing requires explicit token kinds");
            for i in 0..n_pairs {
                let prev = token_kinds_u32[i];
                let thisk = token_kinds_u32[i + 1];
                let idx2d = (prev as usize) * (n_kinds as usize) + (thisk as usize);
                acc_sc += tables.sc_len[idx2d];
                acc_emit += tables.pp_len[idx2d];
            }
        }
        let total_sc = acc_sc;
        let total_emit = acc_emit;
        let tree_count_uses_status = true;
        let tree_capacity = tree_capacity_override
            .unwrap_or_else(|| {
                if tree_count_uses_status {
                    resident_partial_parse_tree_capacity(total_emit)
                } else {
                    total_emit
                }
            })
            .max(1);
        let emit_capacity = if resident_partial_parse_capacity {
            tree_capacity
        } else {
            total_emit.max(1)
        };

        let mut blob: Vec<u32> = Vec::with_capacity(
            tables.sc_superseq.len()
                + tables.sc_off.len()
                + tables.sc_len.len()
                + tables.pp_superseq.len()
                + tables.pp_off.len()
                + tables.pp_len.len(),
        );

        let sc_superseq_off = blob.len() as u32;
        blob.extend_from_slice(&tables.sc_superseq);

        let sc_off_off = blob.len() as u32;
        blob.extend_from_slice(&tables.sc_off);

        let sc_len_off = blob.len() as u32;
        blob.extend_from_slice(&tables.sc_len);

        let pp_superseq_off = blob.len() as u32;
        blob.extend_from_slice(&tables.pp_superseq);

        let pp_off_off = blob.len() as u32;
        blob.extend_from_slice(&tables.pp_off);

        let pp_len_off = blob.len() as u32;
        blob.extend_from_slice(&tables.pp_len);

        let params_pack = uniform_from_val(
            device,
            "pack.params",
            &super::passes::pack::varlen::PackParams {
                n_tokens,
                n_kinds,
                total_sc,
                total_emit,
                sc_capacity: total_sc.max(1),
                emit_capacity,
                sc_superseq_off,
                sc_off_off,
                sc_len_off,
                pp_superseq_off,
                pp_off_off,
                pp_len_off,
            },
        );

        let n_pack_pairs = pair_capacity;
        let sc_offsets = storage_rw_for_array::<u32>(device, "pack.sc_offsets", n_pack_pairs);
        let emit_offsets = storage_rw_for_array::<u32>(device, "pack.emit_offsets", n_pack_pairs);
        let pack_sc_prefix_a =
            storage_rw_for_array::<u32>(device, "pack.sc_prefix_a", n_pack_pairs);
        let pack_sc_prefix_b =
            storage_rw_for_array::<u32>(device, "pack.sc_prefix_b", n_pack_pairs);
        let pack_emit_prefix_a =
            storage_rw_for_array::<u32>(device, "pack.emit_prefix_a", n_pack_pairs);
        let pack_emit_prefix_b =
            storage_rw_for_array::<u32>(device, "pack.emit_prefix_b", n_pack_pairs);
        let pack_offset_scan_steps =
            make_pack_offset_scan_steps(device, n_tokens.saturating_sub(1));
        let pack_total_reduce_steps =
            make_pack_total_reduce_steps(device, n_tokens.saturating_sub(1));
        let partial_parse_status =
            storage_rw_for_array::<u32>(device, "pack.partial_parse_status", 6);
        let tables_blob = storage_ro_from_u32s(device, "pack.tables_blob", &blob);

        let out_sc = storage_rw_for_array::<u32>(device, "pack.out_sc", total_sc.max(1) as usize);
        let out_emit = storage_rw_for_array::<u32>(device, "pack.out_emit", emit_capacity as usize);
        let out_emit_pos =
            storage_rw_for_array::<u32>(device, "pack.out_emit_pos", emit_capacity as usize);

        // ---------- Brackets (parallel) ----------
        //
        // Resident parsing validates stack effects before publishing acceptance,
        // so bracket scratch is sized to the conservative stack capacity.
        const WG: u32 = 256;
        let bracket_capacity = total_sc.max(1);
        let n_blocks = total_sc.div_ceil(WG).max(1);

        let b01_params = uniform_from_val(
            device,
            "brackets.b01.params",
            &super::passes::brackets::scan_inblock::Params {
                n_sc: total_sc,
                wg_size: WG,
            },
        );
        let b02_params = uniform_from_val(
            device,
            "brackets.b02.params",
            &super::passes::brackets::scan_block_prefix::Params {
                n_blocks,
                scan_step: 0,
            },
        );
        let b02_scan_steps = make_brackets_block_prefix_scan_steps(device, n_blocks);
        let b03_params = uniform_from_val(
            device,
            "brackets.b03.params",
            &super::passes::brackets::apply_prefix::Params {
                n_sc: total_sc,
                wg_size: WG,
            },
        );

        // layers upper bound = #pushes <= total_sc; +2 for safety.
        let n_layers = total_sc.saturating_add(2).max(1);

        let b04_params = uniform_from_val(
            device,
            "brackets.b04.params",
            &super::passes::brackets::histogram_layers::Params {
                n_sc: total_sc,
                n_layers,
            },
        );
        let b05_params = uniform_from_val(
            device,
            "brackets.b05.params",
            &super::passes::brackets::scan_histograms::Params {
                n_layers,
                scan_step: 0,
            },
        );
        let b05_scan_steps = make_brackets_histogram_scan_steps(device, n_layers);
        let b06_params = uniform_from_val(
            device,
            "brackets.b06.params",
            &super::passes::brackets::scatter_by_layer::Params {
                n_sc: total_sc,
                n_layers,
            },
        );
        let b07_params = uniform_from_val(
            device,
            "brackets.b07.params",
            &super::passes::brackets::pse_pair::Params {
                n_sc: total_sc,
                n_layers,
                typed_check: 1,
            },
        );

        let b_exscan_inblock = storage_rw_for_array::<i32>(
            device,
            "brackets.exscan_inblock",
            bracket_capacity as usize,
        );
        let b_block_sum =
            storage_rw_for_array::<i32>(device, "brackets.block_sum", n_blocks as usize);
        let b_block_minpref =
            storage_rw_for_array::<i32>(device, "brackets.block_minpref", n_blocks as usize);
        let b_block_maxdepth =
            storage_rw_for_array::<i32>(device, "brackets.block_maxdepth", n_blocks as usize);
        let b_block_prefix =
            storage_rw_for_array::<i32>(device, "brackets.block_prefix", n_blocks as usize);
        let b_block_prefix_sum_a =
            storage_rw_for_array::<i32>(device, "brackets.block_prefix_sum_a", n_blocks as usize);
        let b_block_prefix_sum_b =
            storage_rw_for_array::<i32>(device, "brackets.block_prefix_sum_b", n_blocks as usize);
        let b_block_prefix_min_a =
            storage_rw_for_array::<i32>(device, "brackets.block_prefix_min_a", n_blocks as usize);
        let b_block_prefix_min_b =
            storage_rw_for_array::<i32>(device, "brackets.block_prefix_min_b", n_blocks as usize);

        let depths_out = storage_rw_for_array::<i32>(device, "brackets.depths_out", 2);
        let valid_out = storage_rw_for_array::<u32>(device, "brackets.valid_out", 1);

        let b_depth_exscan =
            storage_rw_for_array::<i32>(device, "brackets.depth_exscan", bracket_capacity as usize);
        let b_layer =
            storage_rw_for_array::<u32>(device, "brackets.layer", bracket_capacity as usize);

        let b_hist_push =
            storage_rw_for_array::<u32>(device, "brackets.hist_push", n_layers as usize);
        let b_hist_pop =
            storage_rw_for_array::<u32>(device, "brackets.hist_pop", n_layers as usize);
        let b_off_push =
            storage_rw_for_array::<u32>(device, "brackets.off_push", n_layers as usize);
        let b_off_pop = storage_rw_for_array::<u32>(device, "brackets.off_pop", n_layers as usize);
        let b_cur_push =
            storage_rw_for_array::<u32>(device, "brackets.cur_push", n_layers as usize);
        let b_cur_pop = storage_rw_for_array::<u32>(device, "brackets.cur_pop", n_layers as usize);
        let b_pushes_by_layer = storage_rw_for_array::<u32>(
            device,
            "brackets.pushes_by_layer",
            bracket_capacity as usize,
        );
        let b_pops_by_layer = storage_rw_for_array::<u32>(
            device,
            "brackets.pops_by_layer",
            bracket_capacity as usize,
        );
        let b_slot_for_index = storage_rw_for_array::<u32>(
            device,
            "brackets.slot_for_index",
            bracket_capacity as usize,
        );
        let match_for_index = storage_rw_for_array::<u32>(
            device,
            "brackets.match_for_index",
            bracket_capacity as usize,
        );

        // ---------- Tree parent recovery ----------
        let tree_n_node_blocks = tree_capacity.div_ceil(WG).max(1);
        let tree_n_prefix_blocks = tree_capacity.saturating_add(1).div_ceil(WG).max(1);
        let tree_prefix_params_base = super::passes::tree::prefix::local::Params {
            n: tree_capacity,
            uses_status_count: u32::from(tree_count_uses_status),
            n_node_blocks: tree_n_node_blocks,
            n_prefix_blocks: tree_n_prefix_blocks,
            scan_step: 0,
        };
        let tree_prefix_params = uniform_from_val(
            device,
            "parser.tree_prefix.params",
            &tree_prefix_params_base,
        );
        let tree_active_dispatch_args =
            dispatch_args_buffer(device, "parser.tree_active_dispatch_args");
        let tree_enum_dispatch_args =
            dispatch_args_buffer(device, "parser.tree_enum_dispatch_args");
        let tree_match_dispatch_args =
            dispatch_args_buffer(device, "parser.tree_match_dispatch_args");
        let tree_struct_dispatch_args =
            dispatch_args_buffer(device, "parser.tree_struct_dispatch_args");
        let hir_semantic_dispatch_args =
            dispatch_args_buffer(device, "parser.hir_semantic_dispatch_args");
        let tree_prefix_scan_steps =
            make_tree_prefix_scan_steps(device, tree_prefix_params_base, tree_n_node_blocks);
        let tree_prefix_inblock = storage_rw_for_array::<i32>(
            device,
            "parser.tree_prefix_inblock",
            tree_capacity as usize,
        );
        let tree_block_sum = storage_rw_for_array::<i32>(
            device,
            "parser.tree_block_sum",
            tree_n_node_blocks as usize,
        );
        let tree_block_prefix_a = storage_rw_for_array::<i32>(
            device,
            "parser.tree_block_prefix_a",
            tree_n_node_blocks as usize,
        );
        let tree_block_prefix_b = storage_rw_for_array::<i32>(
            device,
            "parser.tree_block_prefix_b",
            tree_n_node_blocks as usize,
        );
        let tree_block_prefix = storage_rw_for_array::<i32>(
            device,
            "parser.tree_block_prefix",
            tree_n_node_blocks as usize,
        );
        let tree_prefix =
            storage_rw_for_array::<i32>(device, "parser.tree_prefix", tree_capacity as usize + 1);
        let tree_prefix_block_max = storage_rw_for_array::<i32>(
            device,
            "parser.tree_prefix_block_max",
            tree_n_prefix_blocks as usize,
        );
        let tree_prefix_block_max_tree_base = next_power_of_two_u32(tree_n_prefix_blocks).max(1);
        let tree_prefix_block_max_tree = storage_rw_for_array::<i32>(
            device,
            "parser.tree_prefix_block_max_tree",
            tree_prefix_block_max_tree_base.saturating_mul(2) as usize,
        );
        let tree_prefix_max_build_steps = make_tree_prefix_max_build_steps(
            device,
            tree_n_prefix_blocks,
            tree_prefix_block_max_tree_base,
        );

        // Shared tables/outputs
        let prod_arity = storage_ro_from_u32s(device, "parser.prod_arity", &tables.prod_arity);
        let node_kind =
            storage_rw_for_array::<u32>(device, "parser.node_kind", tree_capacity as usize);
        let parent = storage_rw_for_array::<u32>(device, "parser.parent", tree_capacity as usize);
        let tree_params = uniform_from_val(
            device,
            "parser.tree_parent.params",
            &super::passes::tree::parent::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                n_prefix_blocks: tree_n_prefix_blocks,
                max_tree_leaf_base: tree_prefix_block_max_tree_base,
            },
        );
        let tree_span_params = uniform_from_val(
            device,
            "parser.tree_spans.params",
            &super::passes::tree::spans::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                n_prefix_blocks: tree_n_prefix_blocks,
                max_tree_leaf_base: tree_prefix_block_max_tree_base,
            },
        );
        let tree_prev_sibling_params = uniform_from_val(
            device,
            "parser.tree_prev_sibling.params",
            &super::passes::tree::prev::sibling::clear::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let first_child =
            storage_rw_for_array::<u32>(device, "parser.first_child", tree_capacity as usize);
        let next_sibling =
            storage_rw_for_array::<u32>(device, "parser.next_sibling", tree_capacity as usize);
        let prev_sibling =
            storage_rw_for_array::<u32>(device, "parser.prev_sibling", tree_capacity as usize);
        let subtree_end =
            storage_rw_for_array::<u32>(device, "parser.subtree_end", tree_capacity as usize);
        let hir_params = uniform_from_val(
            device,
            "parser.hir_nodes.params",
            &super::passes::hir::nodes::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_span_params = uniform_from_val(
            device,
            "parser.hir_spans.params",
            &super::passes::hir::spans::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                token_capacity: token_input_capacity,
            },
        );
        let hir_type_fields_params = uniform_from_val(
            device,
            "parser.hir_type_fields.params",
            &super::passes::hir::types::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_item_fields_params = uniform_from_val(
            device,
            "parser.hir_item_fields.params",
            &super::passes::hir::item::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_param_fields_params = uniform_from_val(
            device,
            "parser.hir_param_fields.params",
            &super::passes::hir::param::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_method_fields_params = uniform_from_val(
            device,
            "parser.hir_method_fields.params",
            &super::passes::hir::method::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_expr_fields_params = uniform_from_val(
            device,
            "parser.hir_expr_fields.params",
            &super::passes::hir::expr::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_member_fields_params = uniform_from_val(
            device,
            "parser.hir_member_fields.params",
            &super::passes::hir::member::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_stmt_fields_params = uniform_from_val(
            device,
            "parser.hir_stmt_fields.params",
            &super::passes::hir::stmt_fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_call_fields_params = uniform_from_val(
            device,
            "parser.hir_call_fields.params",
            &super::passes::hir::call::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_array_fields_params = uniform_from_val(
            device,
            "parser.hir_array_fields.params",
            &super::passes::hir::array::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_enum_match_fields_params = uniform_from_val(
            device,
            "parser.hir_enum_match_fields.params",
            &super::passes::hir::enums::match_fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_struct_fields_params = uniform_from_val(
            device,
            "parser.hir_struct_fields.params",
            &super::passes::hir::structs::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_kind =
            storage_rw_for_array::<u32>(device, "parser.hir_kind", tree_capacity as usize);
        let hir_semantic_block_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_block_count",
            tree_n_node_blocks as usize,
        );
        let hir_semantic_prefix_scan_steps =
            make_hir_semantic_prefix_scan_steps(device, tree_n_node_blocks);
        let hir_semantic_flag =
            alias_storage_buffer::<i32, u32>(&tree_prefix, tree_capacity as usize);
        let hir_semantic_local_prefix =
            alias_storage_buffer::<i32, u32>(&tree_prefix_inblock, tree_capacity as usize);
        let hir_semantic_block_prefix_a =
            alias_storage_buffer::<i32, u32>(&tree_block_prefix_a, tree_n_node_blocks as usize);
        let hir_semantic_block_prefix_b =
            alias_storage_buffer::<i32, u32>(&tree_block_prefix_b, tree_n_node_blocks as usize);
        let hir_node_dense_id =
            storage_rw_for_array::<u32>(device, "parser.hir_node_dense_id", tree_capacity as usize);
        let hir_semantic_prefix_before_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_prefix_before_node",
            tree_capacity as usize,
        );
        let hir_semantic_dense_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_dense_node",
            tree_capacity as usize,
        );
        let reuse_semantic_debug_buffers =
            resident_partial_parse_capacity && !retain_debug_hir_buffers;
        let hir_semantic_subtree_end = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_subtree_end",
            tree_capacity as usize,
        );
        let hir_semantic_count =
            storage_rw_for_array::<u32>(device, "parser.hir_semantic_count", 1);
        let hir_semantic_parent = if reuse_semantic_debug_buffers {
            // `hir_semantic_prefix_before_node` is only live until
            // `hir_semantic_subtree_end` projects dense ranges. Production
            // resident compilation does not read it back, so the durable dense
            // parent records can reuse that tree-sized allocation.
            alias_storage_buffer::<u32, u32>(
                &hir_semantic_prefix_before_node,
                tree_capacity as usize,
            )
        } else {
            storage_rw_for_array::<u32>(
                device,
                "parser.hir_semantic_parent",
                tree_capacity as usize,
            )
        };
        let hir_semantic_first_child = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_first_child",
            tree_capacity as usize,
        );
        let hir_semantic_next_sibling = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_next_sibling",
            tree_capacity as usize,
        );
        let hir_semantic_depth = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_depth",
            tree_capacity as usize,
        );
        let hir_semantic_child_index = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_child_index",
            tree_capacity as usize,
        );
        // Shared scratch for Pareas-style linked-list pointer jumping. The
        // durable HIR outputs remain in their own buffers; these workspaces are
        // overwritten by each list-family link/rank/scatter sequence.
        let hir_list0_owner_a =
            storage_rw_for_array::<u32>(device, "parser.hir_list0_owner_a", tree_capacity as usize);
        let hir_list0_owner_b =
            storage_rw_for_array::<u32>(device, "parser.hir_list0_owner_b", tree_capacity as usize);
        let hir_list0_link_a =
            storage_rw_for_array::<u32>(device, "parser.hir_list0_link_a", tree_capacity as usize);
        let hir_list0_link_b =
            storage_rw_for_array::<u32>(device, "parser.hir_list0_link_b", tree_capacity as usize);
        let hir_list0_rank_a =
            storage_rw_for_array::<u32>(device, "parser.hir_list0_rank_a", tree_capacity as usize);
        let hir_list0_rank_b =
            storage_rw_for_array::<u32>(device, "parser.hir_list0_rank_b", tree_capacity as usize);
        let hir_list1_owner_a =
            storage_rw_for_array::<u32>(device, "parser.hir_list1_owner_a", tree_capacity as usize);
        let hir_list1_owner_b =
            storage_rw_for_array::<u32>(device, "parser.hir_list1_owner_b", tree_capacity as usize);
        let hir_list1_link_a =
            storage_rw_for_array::<u32>(device, "parser.hir_list1_link_a", tree_capacity as usize);
        let hir_list1_link_b =
            storage_rw_for_array::<u32>(device, "parser.hir_list1_link_b", tree_capacity as usize);
        let hir_list1_rank_a =
            storage_rw_for_array::<u32>(device, "parser.hir_list1_rank_a", tree_capacity as usize);
        let hir_list1_rank_b =
            storage_rw_for_array::<u32>(device, "parser.hir_list1_rank_b", tree_capacity as usize);
        let hir_semantic_parent_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_semantic_parent_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_semantic_parent_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_semantic_parent_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_semantic_depth_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_semantic_depth_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_semantic_depth_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_semantic_depth_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_semantic_child_index_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_semantic_child_index_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_semantic_child_index_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_semantic_child_index_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_token_pos =
            storage_rw_for_array::<u32>(device, "parser.hir_token_pos", tree_capacity as usize);
        let hir_token_end =
            storage_rw_for_array::<u32>(device, "parser.hir_token_end", tree_capacity as usize);
        let hir_token_file_id =
            storage_rw_for_array::<u32>(device, "parser.hir_token_file_id", tree_capacity as usize);
        let (hir_type_form, hir_type_value_node, hir_type_len_token, hir_type_len_value) =
            if resident_partial_parse_capacity {
                // Resident compilation does not expose packed productions as
                // parser debug artifacts. After `hir_nodes`, the production
                // streams and tree-prefix scratch are dead, so reuse them for
                // tree-sized type metadata.
                (
                    alias_storage_buffer::<u32, u32>(&out_emit, tree_capacity as usize),
                    alias_storage_buffer::<u32, u32>(&out_emit_pos, tree_capacity as usize),
                    alias_storage_buffer::<i32, u32>(&tree_prefix_inblock, tree_capacity as usize),
                    alias_storage_buffer::<i32, u32>(&tree_prefix, tree_capacity as usize),
                )
            } else {
                (
                    storage_rw_for_array::<u32>(
                        device,
                        "parser.hir_type_form",
                        tree_capacity as usize,
                    ),
                    storage_rw_for_array::<u32>(
                        device,
                        "parser.hir_type_value_node",
                        tree_capacity as usize,
                    ),
                    storage_rw_for_array::<u32>(
                        device,
                        "parser.hir_type_len_token",
                        tree_capacity as usize,
                    ),
                    storage_rw_for_array::<u32>(
                        device,
                        "parser.hir_type_len_value",
                        tree_capacity as usize,
                    ),
                )
            };
        let hir_type_file_id =
            alias_storage_buffer::<u32, u32>(&hir_token_file_id, tree_capacity as usize);
        // Right-recursive list families use a previous-node record only from
        // their link pass through the immediately following scatter pass.
        // Reuse one scratch buffer across those phases; durable next/start/count
        // records remain separately allocated below.
        let hir_previous_scratch = storage_rw_for_array::<u32>(
            device,
            "parser.hir_previous_scratch",
            tree_capacity as usize,
        );

        let hir_type_path_leaf_node = if reuse_semantic_debug_buffers {
            // `hir_semantic_subtree_end` is read only by `hir_semantic_nav`.
            // HIR type metadata starts later, so production can reuse this
            // debug navigation buffer for the durable type leaf record.
            alias_storage_buffer::<u32, u32>(&hir_semantic_subtree_end, tree_capacity as usize)
        } else {
            storage_rw_for_array::<u32>(
                device,
                "parser.hir_type_path_leaf_node",
                tree_capacity as usize,
            )
        };
        let hir_bound_path_owner_by_leaf = storage_rw_for_array::<u32>(
            device,
            "parser.hir_bound_path_owner_by_leaf",
            tree_capacity as usize,
        );
        let hir_type_path_leaf_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_type_path_leaf_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_type_path_leaf_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_type_path_leaf_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_type_arg_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_type_arg_start",
            tree_capacity as usize,
        );
        let hir_type_arg_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_type_arg_count",
            tree_capacity as usize,
        );
        let hir_type_arg_next =
            storage_rw_for_array::<u32>(device, "parser.hir_type_arg_next", tree_capacity as usize);
        let hir_type_alias_target_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_type_alias_target_node",
            tree_capacity as usize,
        );
        let hir_fn_return_type_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_fn_return_type_node",
            tree_capacity as usize,
        );
        // Function-signature ownership is a transient pointer-jump family. It
        // starts after type-alias ownership has been consumed. The function
        // owner row remains live through parameter-link seeding, so keep it on
        // the second scratch family while parameter ranks reuse list0.
        let hir_fn_signature_owner_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_fn_signature_owner_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_fn_signature_return_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_fn_signature_return_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_fn_signature_function_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_a, tree_capacity as usize);
        let hir_fn_signature_function_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_b, tree_capacity as usize);
        let hir_type_arg_owner_a = storage_rw_for_array::<u32>(
            device,
            "parser.hir_type_arg_owner_a",
            tree_capacity as usize,
        );
        let hir_type_arg_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_type_arg_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_type_arg_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_type_arg_rank_a = storage_rw_for_array::<u32>(
            device,
            "parser.hir_type_arg_rank_a",
            tree_capacity as usize,
        );
        let hir_type_arg_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_type_arg_previous =
            alias_storage_buffer::<u32, u32>(&hir_previous_scratch, tree_capacity as usize);
        let hir_type_alias_owner_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_type_alias_owner_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_type_alias_owner_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_type_alias_owner_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_item_kind =
            storage_rw_for_array::<u32>(device, "parser.hir_item_kind", tree_capacity as usize);
        let hir_item_name_token = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_name_token",
            tree_capacity as usize,
        );
        // `hir_item_decl_token` is a late projection from `hir_item_kind` and
        // `hir_token_pos`. The scheduler writes it after all pointer-jump list
        // families are done, so it can reuse list scratch instead of retaining
        // one more tree-sized allocation.
        let hir_item_decl_token =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_item_namespace = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_namespace",
            tree_capacity as usize,
        );
        let hir_item_visibility = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_visibility",
            tree_capacity as usize,
        );
        let hir_item_path_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_path_start",
            tree_capacity as usize,
        );
        let hir_item_path_end =
            storage_rw_for_array::<u32>(device, "parser.hir_item_path_end", tree_capacity as usize);
        let hir_item_path_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_path_node",
            tree_capacity as usize,
        );
        let hir_item_file_id =
            alias_storage_buffer::<u32, u32>(&hir_token_file_id, tree_capacity as usize);
        let hir_item_import_target_kind = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_import_target_kind",
            tree_capacity as usize,
        );
        let hir_param_record = storage_rw_for_array::<u32>(
            device,
            "parser.hir_param_record",
            tree_capacity.saturating_mul(4) as usize,
        );
        let hir_param_type_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_param_type_node",
            tree_capacity as usize,
        );
        let hir_method_owner_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_method_owner_node",
            tree_capacity as usize,
        );
        let hir_method_impl_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_method_impl_node",
            tree_capacity as usize,
        );
        let hir_method_name_token = storage_rw_for_array::<u32>(
            device,
            "parser.hir_method_name_token",
            tree_capacity as usize,
        );
        let hir_method_first_param_token = storage_rw_for_array::<u32>(
            device,
            "parser.hir_method_first_param_token",
            tree_capacity as usize,
        );
        let hir_method_receiver_mode = storage_rw_for_array::<u32>(
            device,
            "parser.hir_method_receiver_mode",
            tree_capacity as usize,
        );
        let hir_method_visibility = storage_rw_for_array::<u32>(
            device,
            "parser.hir_method_visibility",
            tree_capacity as usize,
        );
        let hir_method_signature_flags = storage_rw_for_array::<u32>(
            device,
            "parser.hir_method_signature_flags",
            tree_capacity as usize,
        );
        let hir_method_impl_receiver_type_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_method_impl_receiver_type_node",
            tree_capacity as usize,
        );
        let hir_param_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_param_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_param_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_param_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_param_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_param_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_param_previous =
            alias_storage_buffer::<u32, u32>(&hir_previous_scratch, tree_capacity as usize);
        let hir_variant_parent_enum = storage_rw_for_array::<u32>(
            device,
            "parser.hir_variant_parent_enum",
            tree_capacity as usize,
        );
        let hir_variant_ordinal = storage_rw_for_array::<u32>(
            device,
            "parser.hir_variant_ordinal",
            tree_capacity as usize,
        );
        let hir_variant_payload_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_variant_payload_start",
            tree_capacity as usize,
        );
        let hir_variant_payload_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_variant_payload_count",
            tree_capacity as usize,
        );
        let hir_variant_payload_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_variant_payload_node",
            tree_capacity.saturating_mul(4) as usize,
        );
        let hir_variant_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_variant_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_variant_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_variant_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_variant_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_variant_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_variant_payload_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_a, tree_capacity as usize);
        let hir_variant_payload_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_b, tree_capacity as usize);
        let hir_variant_payload_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_a, tree_capacity as usize);
        let hir_variant_payload_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_b, tree_capacity as usize);
        let hir_variant_payload_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_a, tree_capacity as usize);
        let hir_variant_payload_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_b, tree_capacity as usize);
        let hir_rank_flag =
            storage_rw_for_array::<u32>(device, "parser.hir_rank_flag", tree_capacity as usize);
        let hir_rank_local_prefix = storage_rw_for_array::<u32>(
            device,
            "parser.hir_rank_local_prefix",
            tree_capacity as usize,
        );
        let hir_rank_block_sum = storage_rw_for_array::<u32>(
            device,
            "parser.hir_rank_block_sum",
            tree_n_node_blocks as usize,
        );
        let hir_rank_block_prefix_a = storage_rw_for_array::<u32>(
            device,
            "parser.hir_rank_block_prefix_a",
            tree_n_node_blocks as usize,
        );
        let hir_rank_block_prefix_b = storage_rw_for_array::<u32>(
            device,
            "parser.hir_rank_block_prefix_b",
            tree_n_node_blocks as usize,
        );
        let hir_rank_node =
            storage_rw_for_array::<u32>(device, "parser.hir_rank_node", tree_capacity as usize);
        let hir_rank_count = storage_rw_for_array::<u32>(device, "parser.hir_rank_count", 1);
        let hir_rank_dispatch_args = dispatch_args_buffer(device, "parser.hir_rank_dispatch_args");
        let hir_list_rank_flag =
            alias_storage_buffer::<u32, u32>(&hir_rank_flag, tree_capacity as usize);
        let hir_list_rank_local_prefix =
            alias_storage_buffer::<u32, u32>(&hir_rank_local_prefix, tree_capacity as usize);
        let hir_list_rank_block_sum =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_sum, tree_n_node_blocks as usize);
        let hir_list_rank_block_prefix_a =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_a, tree_n_node_blocks as usize);
        let hir_list_rank_block_prefix_b =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_b, tree_n_node_blocks as usize);
        let hir_list_rank_node =
            alias_storage_buffer::<u32, u32>(&hir_rank_node, tree_capacity as usize);
        let hir_list_rank_count = alias_storage_buffer::<u32, u32>(&hir_rank_count, 1);
        let hir_list_rank_dispatch_args =
            alias_storage_buffer::<u32, u32>(&hir_rank_dispatch_args, 3);
        let hir_enum_rank_flag =
            alias_storage_buffer::<u32, u32>(&hir_rank_flag, tree_capacity as usize);
        let hir_enum_rank_local_prefix =
            alias_storage_buffer::<u32, u32>(&hir_rank_local_prefix, tree_capacity as usize);
        let hir_enum_rank_block_sum =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_sum, tree_n_node_blocks as usize);
        let hir_enum_rank_block_prefix_a =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_a, tree_n_node_blocks as usize);
        let hir_enum_rank_block_prefix_b =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_b, tree_n_node_blocks as usize);
        let hir_enum_rank_node =
            alias_storage_buffer::<u32, u32>(&hir_rank_node, tree_capacity as usize);
        let hir_enum_rank_count = alias_storage_buffer::<u32, u32>(&hir_rank_count, 1);
        let hir_enum_rank_dispatch_args =
            alias_storage_buffer::<u32, u32>(&hir_rank_dispatch_args, 3);
        let hir_match_scrutinee_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_scrutinee_node",
            tree_capacity as usize,
        );
        let hir_match_arm_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_start",
            tree_capacity as usize,
        );
        let hir_match_arm_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_count",
            tree_capacity as usize,
        );
        let hir_match_arm_next = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_next",
            tree_capacity as usize,
        );
        let hir_match_arm_pattern_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_pattern_node",
            tree_capacity as usize,
        );
        let hir_match_arm_payload_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_payload_start",
            tree_capacity as usize,
        );
        let hir_match_arm_payload_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_payload_count",
            tree_capacity as usize,
        );
        let hir_match_arm_result_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_result_node",
            tree_capacity as usize,
        );
        let hir_match_payload_owner_arm = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_payload_owner_arm",
            tree_capacity as usize,
        );
        let hir_match_payload_match_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_payload_match_node",
            tree_capacity as usize,
        );
        let hir_match_payload_ordinal = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_payload_ordinal",
            tree_capacity as usize,
        );
        let hir_match_arm_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_match_arm_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_match_arm_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_match_arm_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_match_arm_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_match_arm_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_match_arm_previous =
            alias_storage_buffer::<u32, u32>(&hir_previous_scratch, tree_capacity as usize);
        let hir_match_payload_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_a, tree_capacity as usize);
        let hir_match_payload_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_b, tree_capacity as usize);
        let hir_match_payload_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_a, tree_capacity as usize);
        let hir_match_payload_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_b, tree_capacity as usize);
        let hir_match_payload_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_a, tree_capacity as usize);
        let hir_match_payload_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_b, tree_capacity as usize);
        let hir_match_rank_flag =
            alias_storage_buffer::<u32, u32>(&hir_rank_flag, tree_capacity as usize);
        let hir_match_rank_local_prefix =
            alias_storage_buffer::<u32, u32>(&hir_rank_local_prefix, tree_capacity as usize);
        let hir_match_rank_block_sum =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_sum, tree_n_node_blocks as usize);
        let hir_match_rank_block_prefix_a =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_a, tree_n_node_blocks as usize);
        let hir_match_rank_block_prefix_b =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_b, tree_n_node_blocks as usize);
        let hir_match_rank_node =
            alias_storage_buffer::<u32, u32>(&hir_rank_node, tree_capacity as usize);
        let hir_match_rank_count = alias_storage_buffer::<u32, u32>(&hir_rank_count, 1);
        let hir_match_rank_dispatch_args =
            alias_storage_buffer::<u32, u32>(&hir_rank_dispatch_args, 3);
        let hir_call_callee_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_call_callee_node",
            tree_capacity as usize,
        );
        let hir_call_context_stmt_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_call_context_stmt_node",
            tree_capacity as usize,
        );
        let hir_call_arg_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_call_arg_start",
            tree_capacity as usize,
        );
        let hir_call_arg_end =
            storage_rw_for_array::<u32>(device, "parser.hir_call_arg_end", tree_capacity as usize);
        let hir_call_arg_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_call_arg_count",
            tree_capacity as usize,
        );
        let hir_call_arg_parent_call = storage_rw_for_array::<u32>(
            device,
            "parser.hir_call_arg_parent_call",
            tree_capacity as usize,
        );
        let hir_call_arg_ordinal = storage_rw_for_array::<u32>(
            device,
            "parser.hir_call_arg_ordinal",
            tree_capacity as usize,
        );
        let hir_call_arg_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_call_arg_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_call_arg_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_call_arg_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_call_arg_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_call_arg_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_array_lit_first_element = storage_rw_for_array::<u32>(
            device,
            "parser.hir_array_lit_first_element",
            tree_capacity as usize,
        );
        let hir_array_lit_element_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_array_lit_element_count",
            tree_capacity as usize,
        );
        let hir_array_lit_context_stmt_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_array_lit_context_stmt_node",
            tree_capacity as usize,
        );
        let hir_array_element_parent_lit = storage_rw_for_array::<u32>(
            device,
            "parser.hir_array_element_parent_lit",
            tree_capacity as usize,
        );
        let hir_array_element_ordinal = storage_rw_for_array::<u32>(
            device,
            "parser.hir_array_element_ordinal",
            tree_capacity as usize,
        );
        let hir_array_element_next = storage_rw_for_array::<u32>(
            device,
            "parser.hir_array_element_next",
            tree_capacity as usize,
        );
        let hir_array_element_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_array_element_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_array_element_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_array_element_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_array_element_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_array_element_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_array_element_previous =
            alias_storage_buffer::<u32, u32>(&hir_previous_scratch, tree_capacity as usize);
        let hir_expr_form = storage_rw_for_array::<u32>(device, "parser.hir_expr_form", 1);
        let hir_expr_left_node =
            storage_rw_for_array::<u32>(device, "parser.hir_expr_left_node", 1);
        let hir_expr_right_node =
            storage_rw_for_array::<u32>(device, "parser.hir_expr_right_node", 1);
        let hir_expr_value_token =
            storage_rw_for_array::<u32>(device, "parser.hir_expr_value_token", 1);
        let hir_expr_record = storage_rw_for_array::<u32>(
            device,
            "parser.hir_expr_record",
            tree_capacity.saturating_mul(4) as usize,
        );
        let hir_expr_result_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_expr_result_node",
            tree_capacity as usize,
        );
        let hir_expr_result_root_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_expr_result_root_node",
            tree_capacity as usize,
        );
        let hir_expr_result_root_scratch_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_expr_result_root_scratch_node",
            tree_capacity as usize,
        );
        let hir_binary_span_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_binary_span_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_binary_span_start_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_binary_span_start_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_expr_int_value = storage_rw_for_array::<u32>(
            device,
            "parser.hir_expr_int_value",
            tree_capacity as usize,
        );
        let hir_member_receiver_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_member_receiver_node",
            tree_capacity as usize,
        );
        let hir_member_receiver_token = storage_rw_for_array::<u32>(
            device,
            "parser.hir_member_receiver_token",
            tree_capacity as usize,
        );
        let hir_member_name_token = storage_rw_for_array::<u32>(
            device,
            "parser.hir_member_name_token",
            tree_capacity as usize,
        );
        let hir_stmt_record = storage_rw_for_array::<u32>(
            device,
            "parser.hir_stmt_record",
            tree_capacity.saturating_mul(4) as usize,
        );
        let hir_stmt_scope_end = storage_rw_for_array::<u32>(
            device,
            "parser.hir_stmt_scope_end",
            tree_capacity as usize,
        );
        let hir_nearest_stmt_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_nearest_stmt_node",
            tree_capacity as usize,
        );
        let hir_nearest_block_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_nearest_block_node",
            tree_capacity as usize,
        );
        let hir_nearest_enclosing_control_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_nearest_enclosing_control_node",
            tree_capacity as usize,
        );
        let hir_nearest_loop_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_nearest_loop_node",
            tree_capacity as usize,
        );
        let hir_nearest_fn_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_nearest_fn_node",
            tree_capacity as usize,
        );
        let hir_struct_field_parent_struct = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_field_parent_struct",
            tree_capacity as usize,
        );
        let hir_struct_field_ordinal = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_field_ordinal",
            tree_capacity as usize,
        );
        let hir_struct_field_type_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_field_type_node",
            tree_capacity as usize,
        );
        let hir_struct_decl_field_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_decl_field_start",
            tree_capacity as usize,
        );
        let hir_struct_decl_field_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_decl_field_count",
            tree_capacity as usize,
        );
        let hir_struct_lit_head_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_lit_head_node",
            tree_capacity as usize,
        );
        let hir_struct_lit_context_stmt_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_lit_context_stmt_node",
            tree_capacity as usize,
        );
        let hir_struct_lit_field_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_lit_field_start",
            tree_capacity as usize,
        );
        let hir_struct_lit_field_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_lit_field_count",
            tree_capacity as usize,
        );
        let hir_struct_lit_field_parent_lit = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_lit_field_parent_lit",
            tree_capacity as usize,
        );
        let hir_struct_lit_field_value_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_lit_field_value_node",
            tree_capacity as usize,
        );
        // `prev_sibling` is consumed for the last time by
        // `hir_struct_field_links`. The following rank/scatter passes do not
        // read it, so the final struct-literal next-link output can reuse that
        // tree-sized buffer instead of retaining one more parser allocation.
        let hir_struct_lit_field_next =
            alias_storage_buffer::<u32, u32>(&prev_sibling, tree_capacity as usize);
        let hir_struct_field_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_struct_field_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_struct_field_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_struct_field_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_struct_field_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_struct_field_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_struct_lit_field_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_a, tree_capacity as usize);
        let hir_struct_lit_field_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_b, tree_capacity as usize);
        let hir_struct_lit_field_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_a, tree_capacity as usize);
        let hir_struct_lit_field_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_b, tree_capacity as usize);
        let hir_struct_lit_field_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_a, tree_capacity as usize);
        let hir_struct_lit_field_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_b, tree_capacity as usize);
        let hir_struct_lit_field_previous =
            alias_storage_buffer::<u32, u32>(&hir_previous_scratch, tree_capacity as usize);
        let hir_stmt_context_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_stmt_context_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_contextual_stmt_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_contextual_stmt_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_nearest_stmt_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_a, tree_capacity as usize);
        let hir_nearest_stmt_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_b, tree_capacity as usize);
        let hir_nearest_block_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_a, tree_capacity as usize);
        let hir_nearest_block_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_b, tree_capacity as usize);
        let hir_nearest_enclosing_control_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_nearest_enclosing_control_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_nearest_loop_value_a =
            alias_storage_buffer::<u32, u32>(&hir_rank_flag, tree_capacity as usize);
        let hir_nearest_loop_value_b =
            alias_storage_buffer::<u32, u32>(&hir_rank_node, tree_capacity as usize);
        let hir_nearest_fn_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_a, tree_capacity as usize);
        let hir_nearest_fn_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_b, tree_capacity as usize);
        let hir_struct_rank_flag =
            alias_storage_buffer::<u32, u32>(&hir_rank_flag, tree_capacity as usize);
        let hir_struct_rank_local_prefix =
            alias_storage_buffer::<u32, u32>(&hir_rank_local_prefix, tree_capacity as usize);
        let hir_struct_rank_block_sum =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_sum, tree_n_node_blocks as usize);
        let hir_struct_rank_block_prefix_a =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_a, tree_n_node_blocks as usize);
        let hir_struct_rank_block_prefix_b =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_b, tree_n_node_blocks as usize);
        let hir_struct_rank_node =
            alias_storage_buffer::<u32, u32>(&hir_rank_node, tree_capacity as usize);
        let hir_struct_rank_count = alias_storage_buffer::<u32, u32>(&hir_rank_count, 1);
        let hir_struct_rank_dispatch_args =
            alias_storage_buffer::<u32, u32>(&hir_rank_dispatch_args, 3);
        let default_token_file_id = storage_rw_for_array::<u32>(
            device,
            "parser.default_token_file_id",
            n_tokens.max(1) as usize,
        );
        let source_file_token_end_params = uniform_from_val(
            device,
            "parser.source_file_token_end.params",
            &super::passes::source_file_token_end::Params {
                token_capacity: token_input_capacity,
            },
        );
        let source_file_token_end = storage_rw_for_array::<u32>(
            device,
            "parser.source_file_token_end",
            token_input_capacity as usize,
        );

        Self {
            n_tokens,
            n_kinds,
            total_sc,
            total_emit,
            tree_count_uses_status,
            tree_capacity,

            ll1_predict,
            ll1_prod_rhs_off,
            ll1_prod_rhs_len,
            ll1_prod_rhs,
            ll1_emit,
            ll1_emit_pos,
            ll1_status,
            params_llp,
            semantic_token_kinds,
            token_delimiter_params,
            token_delimiter_scan_steps,
            token_input_capacity,
            token_delimiter_n_blocks,
            token_depth_paren_inblock,
            token_depth_brace_inblock,
            token_depth_bracket_inblock,
            token_depth_angle_inblock,
            token_block_sum_paren,
            token_block_sum_brace,
            token_block_sum_bracket,
            token_block_sum_angle,
            token_prefix_paren_a,
            token_prefix_paren_b,
            token_block_prefix_paren,
            token_prefix_brace_a,
            token_prefix_brace_b,
            token_block_prefix_brace,
            token_prefix_bracket_a,
            token_prefix_bracket_b,
            token_block_prefix_bracket,
            token_prefix_angle_a,
            token_prefix_angle_b,
            token_block_prefix_angle,
            token_top_brace_owner_block,
            token_top_brace_owner_prefix_a,
            token_top_brace_owner_prefix_b,
            token_top_brace_owner_block_prefix,
            token_statement_event_block,
            token_statement_event_prefix_a,
            token_statement_event_prefix_b,
            token_statement_event_block_prefix,
            token_brace_semantic_kind,
            token_bracket_semantic_kind,
            token_statement_context_kind,
            token_impl_header_kind,
            token_impl_context_event,
            token_type_path_context_kind,
            token_where_context_event,
            token_match_pattern_context_event,
            token_brace_match_params,
            token_brace_match_depth,
            token_brace_match_block_min,
            token_brace_match_min_tree_base,
            token_brace_match_min_tree,
            token_brace_match_min_tree_steps,
            token_bracket_match_depth,
            token_bracket_match_block_min,
            token_bracket_match_min_tree,
            token_paren_match_depth,
            token_paren_match_block_min,
            token_paren_match_min_tree,
            token_angle_match_depth,
            token_angle_match_block_min,
            token_angle_match_min_tree,
            token_feature_flags,
            token_count,
            default_token_file_id,
            source_file_token_end_params,
            source_file_token_end,
            active_pair_thread_dispatch_args,
            active_pair_group_dispatch_args,
            action_table,
            out_headers,

            params_pack,
            sc_offsets,
            emit_offsets,
            pack_sc_prefix_a,
            pack_sc_prefix_b,
            pack_emit_prefix_a,
            pack_emit_prefix_b,
            pack_offset_scan_steps,
            pack_total_reduce_steps,
            partial_parse_status,
            tables_blob,
            out_sc,
            out_emit,
            out_emit_pos,

            b01_params,
            b02_params,
            b02_scan_steps,
            b03_params,
            b04_params,
            b05_params,
            b06_params,
            b07_params,
            b05_scan_steps,

            b_exscan_inblock,
            b_block_sum,
            b_block_minpref,
            b_block_maxdepth,
            b_block_prefix,
            b_block_prefix_sum_a,
            b_block_prefix_sum_b,
            b_block_prefix_min_a,
            b_block_prefix_min_b,

            depths_out,
            valid_out,

            b_depth_exscan,
            b_layer,

            b_hist_push,
            b_hist_pop,
            b_off_push,
            b_off_pop,
            b_cur_push,
            b_cur_pop,
            b_pushes_by_layer,
            b_pops_by_layer,
            b_slot_for_index,
            match_for_index,

            b_n_blocks: n_blocks,
            b_n_layers: n_layers,

            // Tree parent recovery
            tree_prefix_params,
            tree_prefix_scan_steps,
            tree_n_node_blocks,
            tree_n_prefix_blocks,
            tree_active_dispatch_args,
            tree_enum_dispatch_args,
            tree_match_dispatch_args,
            tree_struct_dispatch_args,
            hir_semantic_dispatch_args,
            tree_prefix_inblock,
            tree_block_sum,
            tree_block_prefix_a,
            tree_block_prefix_b,
            tree_block_prefix,
            tree_prefix,
            tree_prefix_block_max,
            tree_prefix_block_max_tree_base,
            tree_prefix_block_max_tree,
            tree_prefix_max_build_steps,
            tree_params,
            tree_span_params,
            tree_prev_sibling_params,
            prod_arity,
            node_kind,
            parent,
            first_child,
            next_sibling,
            prev_sibling,
            subtree_end,

            // HIR-facing classification
            hir_params,
            hir_span_params,
            hir_type_fields_params,
            hir_item_fields_params,
            hir_param_fields_params,
            hir_method_fields_params,
            hir_expr_fields_params,
            hir_member_fields_params,
            hir_stmt_fields_params,
            hir_call_fields_params,
            hir_array_fields_params,
            hir_enum_match_fields_params,
            hir_struct_fields_params,
            hir_kind,
            hir_semantic_block_count,
            hir_semantic_prefix_scan_steps,
            hir_semantic_flag,
            hir_semantic_local_prefix,
            hir_semantic_block_prefix_a,
            hir_semantic_block_prefix_b,
            hir_node_dense_id,
            hir_semantic_prefix_before_node,
            hir_semantic_dense_node,
            hir_semantic_subtree_end,
            hir_semantic_parent,
            hir_semantic_first_child,
            hir_semantic_next_sibling,
            hir_semantic_depth,
            hir_semantic_child_index,
            hir_semantic_parent_link_a,
            hir_semantic_parent_link_b,
            hir_semantic_parent_value_a,
            hir_semantic_parent_value_b,
            hir_semantic_depth_link_a,
            hir_semantic_depth_link_b,
            hir_semantic_depth_value_a,
            hir_semantic_depth_value_b,
            hir_semantic_child_index_link_a,
            hir_semantic_child_index_link_b,
            hir_semantic_child_index_rank_a,
            hir_semantic_child_index_rank_b,
            hir_semantic_count,
            hir_token_pos,
            hir_token_end,
            hir_token_file_id,
            hir_type_form,
            hir_type_value_node,
            hir_type_len_token,
            hir_type_len_value,
            hir_type_file_id,
            hir_type_path_leaf_node,
            hir_bound_path_owner_by_leaf,
            hir_type_path_leaf_link_a,
            hir_type_path_leaf_link_b,
            hir_type_path_leaf_value_a,
            hir_type_path_leaf_value_b,
            hir_type_arg_start,
            hir_type_arg_count,
            hir_type_arg_next,
            hir_type_alias_target_node,
            hir_fn_return_type_node,
            hir_fn_signature_owner_link_a,
            hir_fn_signature_owner_link_b,
            hir_fn_signature_return_owner_a,
            hir_fn_signature_return_owner_b,
            hir_fn_signature_function_owner_a,
            hir_fn_signature_function_owner_b,
            hir_type_arg_owner_a,
            hir_type_arg_owner_b,
            hir_type_arg_link_a,
            hir_type_arg_link_b,
            hir_type_arg_rank_a,
            hir_type_arg_rank_b,
            hir_type_arg_previous,
            hir_type_alias_owner_link_a,
            hir_type_alias_owner_link_b,
            hir_type_alias_owner_value_a,
            hir_type_alias_owner_value_b,
            hir_item_kind,
            hir_item_name_token,
            hir_item_decl_token,
            hir_item_namespace,
            hir_item_visibility,
            hir_item_path_start,
            hir_item_path_end,
            hir_item_path_node,
            hir_item_file_id,
            hir_item_import_target_kind,
            hir_param_record,
            hir_param_type_node,
            hir_method_owner_node,
            hir_method_impl_node,
            hir_method_name_token,
            hir_method_first_param_token,
            hir_method_receiver_mode,
            hir_method_visibility,
            hir_method_signature_flags,
            hir_method_impl_receiver_type_node,
            hir_param_owner_a,
            hir_param_owner_b,
            hir_param_link_a,
            hir_param_link_b,
            hir_param_rank_a,
            hir_param_rank_b,
            hir_param_previous,
            hir_variant_parent_enum,
            hir_variant_ordinal,
            hir_variant_payload_start,
            hir_variant_payload_count,
            hir_variant_payload_node,
            hir_variant_owner_a,
            hir_variant_owner_b,
            hir_variant_link_a,
            hir_variant_link_b,
            hir_variant_rank_a,
            hir_variant_rank_b,
            hir_variant_payload_owner_a,
            hir_variant_payload_owner_b,
            hir_variant_payload_link_a,
            hir_variant_payload_link_b,
            hir_variant_payload_rank_a,
            hir_variant_payload_rank_b,
            hir_list_rank_flag,
            hir_list_rank_local_prefix,
            hir_list_rank_block_sum,
            hir_list_rank_block_prefix_a,
            hir_list_rank_block_prefix_b,
            hir_list_rank_node,
            hir_list_rank_count,
            hir_list_rank_dispatch_args,
            hir_enum_rank_flag,
            hir_enum_rank_local_prefix,
            hir_enum_rank_block_sum,
            hir_enum_rank_block_prefix_a,
            hir_enum_rank_block_prefix_b,
            hir_enum_rank_node,
            hir_enum_rank_count,
            hir_enum_rank_dispatch_args,
            hir_match_scrutinee_node,
            hir_match_arm_start,
            hir_match_arm_count,
            hir_match_arm_next,
            hir_match_arm_pattern_node,
            hir_match_arm_payload_start,
            hir_match_arm_payload_count,
            hir_match_arm_result_node,
            hir_match_payload_owner_arm,
            hir_match_payload_match_node,
            hir_match_payload_ordinal,
            hir_match_arm_owner_a,
            hir_match_arm_owner_b,
            hir_match_arm_link_a,
            hir_match_arm_link_b,
            hir_match_arm_rank_a,
            hir_match_arm_rank_b,
            hir_match_arm_previous,
            hir_match_payload_owner_a,
            hir_match_payload_owner_b,
            hir_match_payload_link_a,
            hir_match_payload_link_b,
            hir_match_payload_rank_a,
            hir_match_payload_rank_b,
            hir_match_rank_flag,
            hir_match_rank_local_prefix,
            hir_match_rank_block_sum,
            hir_match_rank_block_prefix_a,
            hir_match_rank_block_prefix_b,
            hir_match_rank_node,
            hir_match_rank_count,
            hir_match_rank_dispatch_args,
            hir_call_callee_node,
            hir_call_context_stmt_node,
            hir_call_arg_start,
            hir_call_arg_end,
            hir_call_arg_count,
            hir_call_arg_parent_call,
            hir_call_arg_ordinal,
            hir_call_arg_owner_a,
            hir_call_arg_owner_b,
            hir_call_arg_link_a,
            hir_call_arg_link_b,
            hir_call_arg_rank_a,
            hir_call_arg_rank_b,
            hir_array_lit_first_element,
            hir_array_lit_element_count,
            hir_array_lit_context_stmt_node,
            hir_array_element_parent_lit,
            hir_array_element_ordinal,
            hir_array_element_next,
            hir_array_element_owner_a,
            hir_array_element_owner_b,
            hir_array_element_link_a,
            hir_array_element_link_b,
            hir_array_element_rank_a,
            hir_array_element_rank_b,
            hir_array_element_previous,
            hir_expr_form,
            hir_expr_left_node,
            hir_expr_right_node,
            hir_expr_value_token,
            hir_expr_record,
            hir_expr_result_node,
            hir_expr_result_root_node,
            hir_expr_result_root_scratch_node,
            hir_binary_span_link_a,
            hir_binary_span_link_b,
            hir_binary_span_start_a,
            hir_binary_span_start_b,
            hir_expr_int_value,
            hir_member_receiver_node,
            hir_member_receiver_token,
            hir_member_name_token,
            hir_stmt_record,
            hir_stmt_scope_end,
            hir_nearest_stmt_node,
            hir_nearest_block_node,
            hir_nearest_enclosing_control_node,
            hir_nearest_loop_node,
            hir_nearest_fn_node,
            hir_struct_field_parent_struct,
            hir_struct_field_ordinal,
            hir_struct_field_type_node,
            hir_struct_decl_field_start,
            hir_struct_decl_field_count,
            hir_struct_lit_head_node,
            hir_struct_lit_context_stmt_node,
            hir_struct_lit_field_start,
            hir_struct_lit_field_count,
            hir_struct_lit_field_parent_lit,
            hir_struct_lit_field_value_node,
            hir_struct_lit_field_next,
            hir_struct_field_owner_a,
            hir_struct_field_owner_b,
            hir_struct_field_link_a,
            hir_struct_field_link_b,
            hir_struct_field_rank_a,
            hir_struct_field_rank_b,
            hir_struct_lit_field_owner_a,
            hir_struct_lit_field_owner_b,
            hir_struct_lit_field_link_a,
            hir_struct_lit_field_link_b,
            hir_struct_lit_field_rank_a,
            hir_struct_lit_field_rank_b,
            hir_struct_lit_field_previous,
            hir_stmt_context_link_a,
            hir_stmt_context_link_b,
            hir_contextual_stmt_value_a,
            hir_contextual_stmt_value_b,
            hir_nearest_stmt_value_a,
            hir_nearest_stmt_value_b,
            hir_nearest_block_value_a,
            hir_nearest_block_value_b,
            hir_nearest_enclosing_control_value_a,
            hir_nearest_enclosing_control_value_b,
            hir_nearest_loop_value_a,
            hir_nearest_loop_value_b,
            hir_nearest_fn_value_a,
            hir_nearest_fn_value_b,
            hir_struct_rank_flag,
            hir_struct_rank_local_prefix,
            hir_struct_rank_block_sum,
            hir_struct_rank_block_prefix_a,
            hir_struct_rank_block_prefix_b,
            hir_struct_rank_node,
            hir_struct_rank_count,
            hir_struct_rank_dispatch_args,
        }
    }
}
