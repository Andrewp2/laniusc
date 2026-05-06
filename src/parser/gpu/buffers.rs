// src/parser/gpu/buffers.rs
use encase::ShaderType;

use crate::gpu::buffers::{
    LaniusBuffer,
    storage_ro_from_bytes,
    storage_ro_from_u32s,
    storage_rw_for_array,
    uniform_from_val,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType, Default)]
pub struct ActionHeader {
    pub push_len: u32,
    pub emit_len: u32,
    pub pop_tag: u32,
    pub pop_count: u32,
}

/// All GPU-side buffers for the parser pipeline (no readbacks/staging here).
pub struct ParserBuffers {
    // sizes
    pub n_tokens: u32,
    pub n_kinds: u32,
    pub total_sc: u32,
    pub total_emit: u32,
    pub tree_stream_uses_ll1: bool,
    pub tree_count_uses_status: bool,
    pub tree_capacity: u32,

    // canonical LL(1) outputs flattened from seeded block parsing
    pub ll1_predict: LaniusBuffer<u32>,
    pub ll1_prod_rhs_off: LaniusBuffer<u32>,
    pub ll1_prod_rhs_len: LaniusBuffer<u32>,
    pub ll1_prod_rhs: LaniusBuffer<u32>,
    pub ll1_emit: LaniusBuffer<u32>,
    pub ll1_emit_pos: LaniusBuffer<u32>,
    pub ll1_status: LaniusBuffer<u32>,

    // block-local LL(1) production summaries
    pub ll1_block_size: u32,
    pub ll1_n_blocks: u32,
    pub ll1_block_emit_stride: u32,
    pub ll1_params_base: super::passes::ll1_blocks_01::LL1BlocksParams,
    pub params_ll1_blocks: LaniusBuffer<super::passes::ll1_blocks_01::LL1BlocksParams>,
    pub ll1_block_seed_len: LaniusBuffer<u32>,
    pub ll1_block_seed_stack: LaniusBuffer<u32>,
    pub ll1_seed_plan_status: LaniusBuffer<u32>,
    pub ll1_seeded_status: LaniusBuffer<u32>,
    pub ll1_seeded_emit: LaniusBuffer<u32>,
    pub ll1_seeded_emit_pos: LaniusBuffer<u32>,
    pub ll1_emit_prefix_a: LaniusBuffer<u32>,
    pub ll1_emit_prefix_b: LaniusBuffer<u32>,
    pub ll1_status_summary_a: LaniusBuffer<u32>,
    pub ll1_status_summary_b: LaniusBuffer<u32>,
    pub ll1_emit_prefix_scan_steps: Vec<LL1EmitPrefixScanStep>,

    // pair→header
    pub params_llp: LaniusBuffer<super::passes::llp_pairs::LLPParams>,
    pub token_kinds: LaniusBuffer<u32>,
    pub token_count: LaniusBuffer<u32>,
    pub action_table: LaniusBuffer<u8>,
    pub out_headers: LaniusBuffer<ActionHeader>,

    // pack varlen
    pub params_pack: LaniusBuffer<super::passes::pack_varlen::PackParams>,
    pub sc_offsets: LaniusBuffer<u32>,
    pub emit_offsets: LaniusBuffer<u32>,
    pub pack_sc_prefix_a: LaniusBuffer<u32>,
    pub pack_sc_prefix_b: LaniusBuffer<u32>,
    pub pack_emit_prefix_a: LaniusBuffer<u32>,
    pub pack_emit_prefix_b: LaniusBuffer<u32>,
    pub pack_offset_scan_steps: Vec<PackOffsetScanStep>,
    pub projected_status: LaniusBuffer<u32>,
    pub tables_blob: LaniusBuffer<u32>,
    pub out_sc: LaniusBuffer<u32>,
    pub out_emit: LaniusBuffer<u32>,
    pub out_emit_pos: LaniusBuffer<u32>,

    // -------- Brackets (parallel) --------
    pub b01_params: LaniusBuffer<super::passes::brackets_01::Params>,
    pub b02_params: LaniusBuffer<super::passes::brackets_02::Params>,
    pub b02_scan_steps: Vec<BracketsBlockPrefixScanStep>,
    pub b03_params: LaniusBuffer<super::passes::brackets_03::Params>,
    pub b04_params: LaniusBuffer<super::passes::brackets_04::Params>,
    pub b05_params: LaniusBuffer<super::passes::brackets_05::Params>,
    pub b06_params: LaniusBuffer<super::passes::brackets_06::Params>,
    pub b07_params: LaniusBuffer<super::passes::brackets_pse_04::Params>, // PSE-style pair-by-layer
    pub b05_scan_steps: Vec<BracketsHistogramScanStep>,

    pub b_exscan_inblock: LaniusBuffer<i32>,
    pub b_block_sum: LaniusBuffer<i32>,
    pub b_block_minpref: LaniusBuffer<i32>,
    pub b_block_maxdepth: LaniusBuffer<i32>,
    pub b_block_prefix: LaniusBuffer<i32>,
    pub b_block_prefix_sum_a: LaniusBuffer<i32>,
    pub b_block_prefix_sum_b: LaniusBuffer<i32>,
    pub b_block_prefix_min_a: LaniusBuffer<i32>,
    pub b_block_prefix_min_b: LaniusBuffer<i32>,

    pub depths_out: LaniusBuffer<i32>, // [final, min]
    pub valid_out: LaniusBuffer<u32>,

    pub b_depth_exscan: LaniusBuffer<i32>,
    pub b_layer: LaniusBuffer<u32>,

    pub b_hist_push: LaniusBuffer<u32>,
    pub b_hist_pop: LaniusBuffer<u32>,
    pub b_off_push: LaniusBuffer<u32>,
    pub b_off_pop: LaniusBuffer<u32>,
    pub b_cur_push: LaniusBuffer<u32>,
    pub b_cur_pop: LaniusBuffer<u32>,
    pub b_pushes_by_layer: LaniusBuffer<u32>,
    pub b_pops_by_layer: LaniusBuffer<u32>,
    pub b_slot_for_index: LaniusBuffer<u32>,
    pub match_for_index: LaniusBuffer<u32>,

    // counts used at dispatch
    pub b_n_blocks: u32,
    pub b_n_layers: u32,

    // -------- Tree parent recovery --------
    pub tree_prefix_params: LaniusBuffer<super::passes::tree_prefix_01::Params>,
    pub tree_prefix_scan_steps: Vec<TreePrefixScanStep>,
    pub tree_n_node_blocks: u32,
    pub tree_n_prefix_blocks: u32,
    pub tree_prefix_inblock: LaniusBuffer<i32>,
    pub tree_block_sum: LaniusBuffer<i32>,
    pub tree_block_prefix_a: LaniusBuffer<i32>,
    pub tree_block_prefix_b: LaniusBuffer<i32>,
    pub tree_block_prefix: LaniusBuffer<i32>,
    pub tree_prefix: LaniusBuffer<i32>,
    pub tree_prefix_block_max: LaniusBuffer<i32>,
    pub tree_prefix_block_max_tree_base: u32,
    pub tree_prefix_block_max_tree: LaniusBuffer<i32>,
    pub tree_prefix_max_build_steps: Vec<TreePrefixMaxBuildStep>,
    pub tree_params: LaniusBuffer<super::passes::tree_parent::Params>,
    pub tree_span_params: LaniusBuffer<super::passes::tree_spans::Params>,
    pub prod_arity: LaniusBuffer<u32>,
    pub node_kind: LaniusBuffer<u32>,
    pub parent: LaniusBuffer<u32>,
    pub first_child: LaniusBuffer<u32>,
    pub next_sibling: LaniusBuffer<u32>,
    pub subtree_end: LaniusBuffer<u32>,

    // -------- HIR-facing classification --------
    pub hir_params: LaniusBuffer<super::passes::hir_nodes::Params>,
    pub hir_span_params: LaniusBuffer<super::passes::hir_spans::Params>,
    pub hir_kind: LaniusBuffer<u32>,
    pub hir_token_pos: LaniusBuffer<u32>,
    pub hir_token_end: LaniusBuffer<u32>,
}

pub struct LL1EmitPrefixScanStep {
    pub params: LaniusBuffer<super::passes::ll1_blocks_01::LL1BlocksParams>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct PackOffsetScanStep {
    pub params: LaniusBuffer<super::passes::pack_offsets::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

impl ParserBuffers {
    pub fn new(
        device: &wgpu::Device,
        token_kinds_u32: &[u32],
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
    ) -> Self {
        Self::new_with_sizing(
            device,
            token_kinds_u32,
            n_kinds,
            action_table_bytes,
            tables,
            false,
        )
    }

    pub fn new_resident_capacity(
        device: &wgpu::Device,
        token_kinds_u32: &[u32],
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
    ) -> Self {
        Self::new_with_sizing(
            device,
            token_kinds_u32,
            n_kinds,
            action_table_bytes,
            tables,
            true,
        )
    }

    fn new_with_sizing(
        device: &wgpu::Device,
        token_kinds_u32: &[u32],
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
        resident_projected_capacity: bool,
    ) -> Self {
        let n_tokens = token_kinds_u32.len() as u32;
        let n_pairs = n_tokens.saturating_sub(1) as usize;

        let ll1_stack_capacity = n_tokens.saturating_mul(8).saturating_add(1024).max(1);
        let ll1_max_steps = n_tokens
            .saturating_mul(64)
            .saturating_add(tables.n_productions)
            .saturating_add(1024)
            .max(1);
        let ll1_fill_production = tables
            .prod_arity
            .iter()
            .position(|arity| *arity == 0)
            .unwrap_or(0) as u32;
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

        // ---------- Block-local LL(1) summaries ----------
        const LL1_BLOCK_SIZE: u32 = 256;
        const LL1_BLOCK_STACK_CAPACITY: u32 = 2048;

        let first_input = if n_tokens > 1 && token_kinds_u32.first().copied() == Some(0) {
            1
        } else {
            0
        };
        // Match the canonical LL(1) stream: the last token is the EOF sentinel and is not
        // consumed as ordinary input.
        let input_end = n_tokens.saturating_sub(1);
        let n_input_tokens = input_end.saturating_sub(first_input);
        let token_count = storage_ro_from_u32s(device, "parser.token_count", &[n_input_tokens]);
        let ll1_n_blocks = n_input_tokens.div_ceil(LL1_BLOCK_SIZE).max(1);
        let ll1_block_emit_stride = LL1_BLOCK_STACK_CAPACITY;
        let ll1_params_base = super::passes::ll1_blocks_01::LL1BlocksParams {
            n_tokens,
            n_kinds,
            n_nonterminals: tables.n_nonterminals,
            n_productions: tables.n_productions,
            start_nonterminal: tables.start_nonterminal,
            first_input,
            input_end,
            n_blocks: ll1_n_blocks,
            block_size: LL1_BLOCK_SIZE,
            stack_capacity: LL1_BLOCK_STACK_CAPACITY,
            emit_stride: ll1_block_emit_stride,
            max_steps: ll1_max_steps,
            fill_production: ll1_fill_production,
            emit_scan_step: 0,
        };
        let params_ll1_blocks =
            uniform_from_val(device, "parser.params_ll1_blocks", &ll1_params_base);
        let ll1_block_seed_len =
            storage_rw_for_array::<u32>(device, "parser.ll1_block_seed_len", ll1_n_blocks as usize);
        let ll1_block_seed_stack = storage_rw_for_array::<u32>(
            device,
            "parser.ll1_block_seed_stack",
            (ll1_n_blocks as usize + 1) * LL1_BLOCK_STACK_CAPACITY as usize,
        );
        let ll1_seed_plan_status = storage_rw_for_array::<u32>(
            device,
            "parser.ll1_seed_plan_status",
            super::passes::ll1_blocks_02::LL1_SEED_PLAN_STATUS_WORDS,
        );
        let ll1_seeded_status = storage_rw_for_array::<u32>(
            device,
            "parser.ll1_seeded_status",
            ll1_n_blocks as usize * super::passes::ll1_blocks_01::LL1_BLOCK_STATUS_WORDS,
        );
        let ll1_seeded_emit = storage_rw_for_array::<u32>(
            device,
            "parser.ll1_seeded_emit",
            ll1_n_blocks as usize * ll1_block_emit_stride as usize,
        );
        let ll1_seeded_emit_pos = storage_rw_for_array::<u32>(
            device,
            "parser.ll1_seeded_emit_pos",
            ll1_n_blocks as usize * ll1_block_emit_stride as usize,
        );
        let ll1_emit_prefix_a =
            storage_rw_for_array::<u32>(device, "parser.ll1_emit_prefix_a", ll1_n_blocks as usize);
        let ll1_emit_prefix_b =
            storage_rw_for_array::<u32>(device, "parser.ll1_emit_prefix_b", ll1_n_blocks as usize);
        let ll1_status_summary_a = storage_rw_for_array::<u32>(
            device,
            "parser.ll1_status_summary_a",
            ll1_n_blocks as usize * 4,
        );
        let ll1_status_summary_b = storage_rw_for_array::<u32>(
            device,
            "parser.ll1_status_summary_b",
            ll1_n_blocks as usize * 4,
        );
        let ll1_emit_prefix_scan_steps =
            make_ll1_emit_prefix_scan_steps(device, ll1_params_base, ll1_n_blocks);

        // ---------- Pair→Header ----------
        let token_kinds = storage_ro_from_u32s(device, "parser.token_kinds", token_kinds_u32);

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

        let out_headers: LaniusBuffer<ActionHeader> =
            storage_rw_for_array::<ActionHeader>(device, "parser.out_headers", n_pairs.max(1));

        // ---------- Pack varlen ----------
        let (mut acc_sc, mut acc_emit) = (0u32, 0u32);

        if resident_projected_capacity {
            let max_sc_len = tables.sc_len.iter().copied().max().unwrap_or(0);
            let max_emit_len = tables.pp_len.iter().copied().max().unwrap_or(0);
            acc_sc = (n_pairs as u32).saturating_mul(max_sc_len);
            acc_emit = (n_pairs as u32).saturating_mul(max_emit_len);
        } else {
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
            &super::passes::pack_varlen::PackParams {
                n_tokens,
                n_kinds,
                total_sc,
                total_emit,
                sc_superseq_off,
                sc_off_off,
                sc_len_off,
                pp_superseq_off,
                pp_off_off,
                pp_len_off,
            },
        );

        let n_pack_pairs = n_pairs.max(1);
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
        let projected_status = storage_rw_for_array::<u32>(device, "pack.projected_status", 6);
        let tables_blob = storage_ro_from_u32s(device, "pack.tables_blob", &blob);

        let out_sc = storage_rw_for_array::<u32>(device, "pack.out_sc", total_sc.max(1) as usize);
        let out_emit =
            storage_rw_for_array::<u32>(device, "pack.out_emit", total_emit.max(1) as usize);
        let out_emit_pos =
            storage_rw_for_array::<u32>(device, "pack.out_emit_pos", total_emit.max(1) as usize);

        // ---------- Brackets (parallel) ----------
        const WG: u32 = 256;
        let n_blocks = ((total_sc + WG - 1) / WG).max(1);

        let b01_params = uniform_from_val(
            device,
            "brackets.b01.params",
            &super::passes::brackets_01::Params {
                n_sc: total_sc,
                wg_size: WG,
            },
        );
        let b02_params = uniform_from_val(
            device,
            "brackets.b02.params",
            &super::passes::brackets_02::Params {
                n_blocks,
                scan_step: 0,
            },
        );
        let b02_scan_steps = make_brackets_block_prefix_scan_steps(device, n_blocks);
        let b03_params = uniform_from_val(
            device,
            "brackets.b03.params",
            &super::passes::brackets_03::Params {
                n_sc: total_sc,
                wg_size: WG,
            },
        );

        // layers upper bound = #pushes ≤ total_sc; +2 for safety
        let n_layers = total_sc.saturating_add(2).max(1);

        let b04_params = uniform_from_val(
            device,
            "brackets.b04.params",
            &super::passes::brackets_04::Params {
                n_sc: total_sc,
                n_layers,
            },
        );
        let b05_params = uniform_from_val(
            device,
            "brackets.b05.params",
            &super::passes::brackets_05::Params {
                n_layers,
                scan_step: 0,
            },
        );
        let b05_scan_steps = make_brackets_histogram_scan_steps(device, n_layers);
        let b06_params = uniform_from_val(
            device,
            "brackets.b06.params",
            &super::passes::brackets_06::Params {
                n_sc: total_sc,
                n_layers,
            },
        );
        let b07_params = uniform_from_val(
            device,
            "brackets.b07.params",
            &super::passes::brackets_pse_04::Params {
                n_sc: total_sc,
                n_layers,
                typed_check: 1,
            },
        );

        let b_exscan_inblock = storage_rw_for_array::<i32>(
            device,
            "brackets.exscan_inblock",
            total_sc.max(1) as usize,
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
            storage_rw_for_array::<i32>(device, "brackets.depth_exscan", total_sc.max(1) as usize);
        let b_layer =
            storage_rw_for_array::<u32>(device, "brackets.layer", total_sc.max(1) as usize);

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
            total_sc.max(1) as usize,
        );
        let b_pops_by_layer =
            storage_rw_for_array::<u32>(device, "brackets.pops_by_layer", total_sc.max(1) as usize);
        let b_slot_for_index = storage_rw_for_array::<u32>(
            device,
            "brackets.slot_for_index",
            total_sc.max(1) as usize,
        );
        let match_for_index = storage_rw_for_array::<u32>(
            device,
            "brackets.match_for_index",
            total_sc.max(1) as usize,
        );

        // ---------- Tree parent recovery ----------
        let tree_stream_uses_ll1 = !resident_projected_capacity
            && tables.n_nonterminals > 0
            && !tables.ll1_predict.is_empty()
            && total_emit == 0;
        let tree_count_uses_status = tree_stream_uses_ll1 || resident_projected_capacity;
        let tree_capacity = if tree_count_uses_status {
            ll1_stack_capacity
        } else {
            total_emit
        }
        .max(1);
        let tree_n_node_blocks = tree_capacity.div_ceil(WG).max(1);
        let tree_n_prefix_blocks = tree_capacity.saturating_add(1).div_ceil(WG).max(1);
        let tree_prefix_params_base = super::passes::tree_prefix_01::Params {
            n: tree_capacity,
            uses_ll1: u32::from(tree_count_uses_status),
            n_node_blocks: tree_n_node_blocks,
            n_prefix_blocks: tree_n_prefix_blocks,
            scan_step: 0,
        };
        let tree_prefix_params = uniform_from_val(
            device,
            "parser.tree_prefix.params",
            &tree_prefix_params_base,
        );
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
            &super::passes::tree_parent::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
                n_prefix_blocks: tree_n_prefix_blocks,
                max_tree_leaf_base: tree_prefix_block_max_tree_base,
            },
        );
        let tree_span_params = uniform_from_val(
            device,
            "parser.tree_spans.params",
            &super::passes::tree_spans::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
                n_prefix_blocks: tree_n_prefix_blocks,
                max_tree_leaf_base: tree_prefix_block_max_tree_base,
            },
        );
        let first_child =
            storage_rw_for_array::<u32>(device, "parser.first_child", tree_capacity as usize);
        let next_sibling =
            storage_rw_for_array::<u32>(device, "parser.next_sibling", tree_capacity as usize);
        let subtree_end =
            storage_rw_for_array::<u32>(device, "parser.subtree_end", tree_capacity as usize);
        let hir_params = uniform_from_val(
            device,
            "parser.hir_nodes.params",
            &super::passes::hir_nodes::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
            },
        );
        let hir_span_params = uniform_from_val(
            device,
            "parser.hir_spans.params",
            &super::passes::hir_spans::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
            },
        );
        let hir_kind =
            storage_rw_for_array::<u32>(device, "parser.hir_kind", tree_capacity as usize);
        let hir_token_pos =
            storage_rw_for_array::<u32>(device, "parser.hir_token_pos", tree_capacity as usize);
        let hir_token_end =
            storage_rw_for_array::<u32>(device, "parser.hir_token_end", tree_capacity as usize);

        Self {
            n_tokens,
            n_kinds,
            total_sc,
            total_emit,
            tree_stream_uses_ll1,
            tree_count_uses_status,
            tree_capacity,

            ll1_predict,
            ll1_prod_rhs_off,
            ll1_prod_rhs_len,
            ll1_prod_rhs,
            ll1_emit,
            ll1_emit_pos,
            ll1_status,
            ll1_block_size: LL1_BLOCK_SIZE,
            ll1_n_blocks,
            ll1_block_emit_stride,
            ll1_params_base,
            params_ll1_blocks,
            ll1_block_seed_len,
            ll1_block_seed_stack,
            ll1_seed_plan_status,
            ll1_seeded_status,
            ll1_seeded_emit,
            ll1_seeded_emit_pos,
            ll1_emit_prefix_a,
            ll1_emit_prefix_b,
            ll1_status_summary_a,
            ll1_status_summary_b,
            ll1_emit_prefix_scan_steps,

            params_llp,
            token_kinds,
            token_count,
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
            projected_status,
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
            prod_arity,
            node_kind,
            parent,
            first_child,
            next_sibling,
            subtree_end,

            // HIR-facing classification
            hir_params,
            hir_span_params,
            hir_kind,
            hir_token_pos,
            hir_token_end,
        }
    }
}

pub struct BracketsHistogramScanStep {
    pub params: LaniusBuffer<super::passes::brackets_05::Params>,
    pub read_from_offsets: bool,
    pub write_to_offsets: bool,
}

pub struct BracketsBlockPrefixScanStep {
    pub params: LaniusBuffer<super::passes::brackets_02::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct TreePrefixScanStep {
    pub params: LaniusBuffer<super::passes::tree_prefix_01::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct TreePrefixMaxBuildStep {
    pub params: LaniusBuffer<super::passes::tree_prefix_04::Params>,
    pub work_items: u32,
}

fn make_ll1_emit_prefix_scan_steps(
    device: &wgpu::Device,
    base: super::passes::ll1_blocks_01::LL1BlocksParams,
    n_blocks: u32,
) -> Vec<LL1EmitPrefixScanStep> {
    let mut steps = Vec::new();
    steps.push(LL1EmitPrefixScanStep {
        params: uniform_from_val(
            device,
            "parser.ll1_emit_prefix_scan.params.init",
            &super::passes::ll1_blocks_01::LL1BlocksParams {
                emit_scan_step: 0,
                ..base
            },
        ),
        read_from_a: false,
        write_to_a: true,
    });

    let mut step = 1u32;
    let mut step_count = 0u32;
    while step < n_blocks {
        let read_from_a = step_count % 2 == 0;
        steps.push(LL1EmitPrefixScanStep {
            params: uniform_from_val(
                device,
                "parser.ll1_emit_prefix_scan.params.step",
                &super::passes::ll1_blocks_01::LL1BlocksParams {
                    emit_scan_step: step,
                    ..base
                },
            ),
            read_from_a,
            write_to_a: !read_from_a,
        });
        step <<= 1;
        step_count += 1;
    }

    if step_count % 2 == 1 {
        steps.push(LL1EmitPrefixScanStep {
            params: uniform_from_val(
                device,
                "parser.ll1_emit_prefix_scan.params.copy",
                &super::passes::ll1_blocks_01::LL1BlocksParams {
                    emit_scan_step: n_blocks,
                    ..base
                },
            ),
            read_from_a: false,
            write_to_a: true,
        });
    }

    steps
}

fn make_pack_offset_scan_steps(device: &wgpu::Device, n_pairs: u32) -> Vec<PackOffsetScanStep> {
    let mut steps = Vec::new();
    steps.push(PackOffsetScanStep {
        params: uniform_from_val(
            device,
            "pack.offset_scan.params.init",
            &super::passes::pack_offsets::Params {
                n_pairs,
                scan_step: 0,
            },
        ),
        read_from_a: false,
        write_to_a: true,
    });

    let mut step = 1u32;
    let mut step_count = 0u32;
    while step < n_pairs {
        let read_from_a = step_count % 2 == 0;
        steps.push(PackOffsetScanStep {
            params: uniform_from_val(
                device,
                "pack.offset_scan.params.step",
                &super::passes::pack_offsets::Params {
                    n_pairs,
                    scan_step: step,
                },
            ),
            read_from_a,
            write_to_a: !read_from_a,
        });
        step <<= 1;
        step_count += 1;
    }

    let read_from_a = step_count % 2 == 0;
    steps.push(PackOffsetScanStep {
        params: uniform_from_val(
            device,
            "pack.offset_scan.params.finalize",
            &super::passes::pack_offsets::Params {
                n_pairs,
                scan_step: n_pairs,
            },
        ),
        read_from_a,
        write_to_a: !read_from_a,
    });

    steps
}

fn make_brackets_block_prefix_scan_steps(
    device: &wgpu::Device,
    n_blocks: u32,
) -> Vec<BracketsBlockPrefixScanStep> {
    let mut steps = Vec::new();
    steps.push(BracketsBlockPrefixScanStep {
        params: uniform_from_val(
            device,
            "brackets.b02.scan.params.init",
            &super::passes::brackets_02::Params {
                n_blocks,
                scan_step: 0,
            },
        ),
        read_from_a: false,
        write_to_a: true,
    });

    let mut step = 1u32;
    let mut step_count = 0u32;
    while step < n_blocks {
        let read_from_a = step_count % 2 == 0;
        steps.push(BracketsBlockPrefixScanStep {
            params: uniform_from_val(
                device,
                "brackets.b02.scan.params.step",
                &super::passes::brackets_02::Params {
                    n_blocks,
                    scan_step: step,
                },
            ),
            read_from_a,
            write_to_a: !read_from_a,
        });
        step <<= 1;
        step_count += 1;
    }

    let read_from_a = step_count % 2 == 0;
    steps.push(BracketsBlockPrefixScanStep {
        params: uniform_from_val(
            device,
            "brackets.b02.scan.params.finalize",
            &super::passes::brackets_02::Params {
                n_blocks,
                scan_step: n_blocks,
            },
        ),
        read_from_a,
        write_to_a: !read_from_a,
    });

    steps
}

fn make_brackets_histogram_scan_steps(
    device: &wgpu::Device,
    n_layers: u32,
) -> Vec<BracketsHistogramScanStep> {
    let mut steps = Vec::new();
    steps.push(BracketsHistogramScanStep {
        params: uniform_from_val(
            device,
            "brackets.b05.scan.params.init",
            &super::passes::brackets_05::Params {
                n_layers,
                scan_step: 0,
            },
        ),
        read_from_offsets: false,
        write_to_offsets: true,
    });

    let mut step = 1u32;
    let mut step_count = 0u32;
    while step < n_layers {
        let read_from_offsets = step_count % 2 == 0;
        steps.push(BracketsHistogramScanStep {
            params: uniform_from_val(
                device,
                "brackets.b05.scan.params.step",
                &super::passes::brackets_05::Params {
                    n_layers,
                    scan_step: step,
                },
            ),
            read_from_offsets,
            write_to_offsets: !read_from_offsets,
        });
        step <<= 1;
        step_count += 1;
    }

    if step_count % 2 == 1 {
        steps.push(BracketsHistogramScanStep {
            params: uniform_from_val(
                device,
                "brackets.b05.scan.params.copy",
                &super::passes::brackets_05::Params {
                    n_layers,
                    scan_step: n_layers,
                },
            ),
            read_from_offsets: false,
            write_to_offsets: true,
        });
    }

    steps
}

fn make_tree_prefix_scan_steps(
    device: &wgpu::Device,
    base: super::passes::tree_prefix_01::Params,
    n_blocks: u32,
) -> Vec<TreePrefixScanStep> {
    let mut steps = Vec::new();
    steps.push(TreePrefixScanStep {
        params: uniform_from_val(
            device,
            "parser.tree_prefix_scan.params.init",
            &super::passes::tree_prefix_01::Params {
                scan_step: 0,
                ..base
            },
        ),
        read_from_a: false,
        write_to_a: true,
    });

    let mut step = 1u32;
    let mut step_count = 0u32;
    while step < n_blocks {
        let read_from_a = step_count % 2 == 0;
        steps.push(TreePrefixScanStep {
            params: uniform_from_val(
                device,
                "parser.tree_prefix_scan.params.step",
                &super::passes::tree_prefix_01::Params {
                    scan_step: step,
                    ..base
                },
            ),
            read_from_a,
            write_to_a: !read_from_a,
        });
        step <<= 1;
        step_count += 1;
    }

    let read_from_a = step_count % 2 == 0;
    steps.push(TreePrefixScanStep {
        params: uniform_from_val(
            device,
            "parser.tree_prefix_scan.params.finalize",
            &super::passes::tree_prefix_01::Params {
                scan_step: n_blocks,
                ..base
            },
        ),
        read_from_a,
        write_to_a: !read_from_a,
    });

    steps
}

fn make_tree_prefix_max_build_steps(
    device: &wgpu::Device,
    n_blocks: u32,
    leaf_base: u32,
) -> Vec<TreePrefixMaxBuildStep> {
    let mut steps = Vec::new();
    steps.push(TreePrefixMaxBuildStep {
        params: uniform_from_val(
            device,
            "parser.tree_prefix_max.params.leaves",
            &super::passes::tree_prefix_04::Params {
                n_blocks,
                leaf_base,
                start_node: 0,
                node_count: leaf_base,
                mode: 0,
                _pad0: 0,
                _pad1: 0,
                _pad2: 0,
            },
        ),
        work_items: leaf_base,
    });

    let mut start_node = leaf_base / 2;
    while start_node > 0 {
        steps.push(TreePrefixMaxBuildStep {
            params: uniform_from_val(
                device,
                "parser.tree_prefix_max.params.combine",
                &super::passes::tree_prefix_04::Params {
                    n_blocks,
                    leaf_base,
                    start_node,
                    node_count: start_node,
                    mode: 1,
                    _pad0: 0,
                    _pad1: 0,
                    _pad2: 0,
                },
            ),
            work_items: start_node,
        });

        if start_node == 1 {
            break;
        }
        start_node /= 2;
    }

    steps
}

fn next_power_of_two_u32(value: u32) -> u32 {
    value.checked_next_power_of_two().unwrap_or(1 << 31)
}
