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

    // pair→header
    pub params_llp: LaniusBuffer<super::passes::llp_pairs::LLPParams>,
    pub token_kinds: LaniusBuffer<u32>,
    pub action_table: LaniusBuffer<u8>,
    pub out_headers: LaniusBuffer<ActionHeader>,

    // pack varlen
    pub params_pack: LaniusBuffer<super::passes::pack_varlen::PackParams>,
    pub sc_offsets: LaniusBuffer<u32>,
    pub emit_offsets: LaniusBuffer<u32>,
    pub tables_blob: LaniusBuffer<u32>,
    pub out_sc: LaniusBuffer<u32>,
    pub out_emit: LaniusBuffer<u32>,

    // -------- Brackets (parallel) --------
    pub b01_params: LaniusBuffer<super::passes::brackets_01::Params>,
    pub b02_params: LaniusBuffer<super::passes::brackets_02::Params>,
    pub b03_params: LaniusBuffer<super::passes::brackets_03::Params>,
    pub b04_params: LaniusBuffer<super::passes::brackets_04::Params>,
    pub b05_params: LaniusBuffer<super::passes::brackets_05::Params>,
    pub b06_params: LaniusBuffer<super::passes::brackets_06::Params>,
    pub b07_params: LaniusBuffer<super::passes::brackets_pse_04::Params>, // PSE-style pair-by-layer

    pub b_exscan_inblock: LaniusBuffer<i32>,
    pub b_block_sum: LaniusBuffer<i32>,
    pub b_block_minpref: LaniusBuffer<i32>,
    pub b_block_maxdepth: LaniusBuffer<i32>,
    pub b_block_prefix: LaniusBuffer<i32>,

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
    pub match_for_index: LaniusBuffer<u32>,

    // counts used at dispatch
    pub b_n_blocks: u32,
    pub b_n_layers: u32,

    // -------- Tree (tiled stack) --------
    pub tb01_params: LaniusBuffer<super::passes::tree_blocked_01::Params>,
    pub tb02_params: LaniusBuffer<super::passes::tree_blocked_02::Params>,
    pub tb03_params: LaniusBuffer<super::passes::tree_blocked_03::Params>,

    // Shared small tables/outputs
    pub prod_arity: LaniusBuffer<u32>,
    pub node_kind: LaniusBuffer<u32>,
    pub parent: LaniusBuffer<u32>,

    // Tiled tree builder buffers
    pub tb_end_off: LaniusBuffer<u32>,
    pub tb_end_nodes: LaniusBuffer<u32>,
    pub tb_end_rem: LaniusBuffer<u32>,
    pub tb_start_off: LaniusBuffer<u32>,
    pub tb_start_nodes: LaniusBuffer<u32>,
    pub tb_start_rem: LaniusBuffer<u32>,
}

impl ParserBuffers {
    pub fn new(
        device: &wgpu::Device,
        token_kinds_u32: &[u32],
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
    ) -> Self {
        let n_tokens = token_kinds_u32.len() as u32;
        let n_pairs = n_tokens.saturating_sub(1) as usize;

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
        let mut sc_offsets_host = Vec::with_capacity(n_pairs);
        let mut emit_offsets_host = Vec::with_capacity(n_pairs);
        let (mut acc_sc, mut acc_emit) = (0u32, 0u32);

        for i in 0..n_pairs {
            let prev = token_kinds_u32[i];
            let thisk = token_kinds_u32[i + 1];
            let idx2d = (prev as usize) * (n_kinds as usize) + (thisk as usize);
            sc_offsets_host.push(acc_sc);
            acc_sc += tables.sc_len[idx2d];
            emit_offsets_host.push(acc_emit);
            acc_emit += tables.pp_len[idx2d];
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

        let sc_offsets = storage_ro_from_u32s(device, "pack.sc_offsets", &sc_offsets_host);
        let emit_offsets = storage_ro_from_u32s(device, "pack.emit_offsets", &emit_offsets_host);
        let tables_blob = storage_ro_from_u32s(device, "pack.tables_blob", &blob);

        let out_sc = storage_rw_for_array::<u32>(device, "pack.out_sc", total_sc.max(1) as usize);
        let out_emit =
            storage_rw_for_array::<u32>(device, "pack.out_emit", total_emit.max(1) as usize);

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
            &super::passes::brackets_02::Params { n_blocks },
        );
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
            &super::passes::brackets_05::Params { n_layers },
        );
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
                n_layers,
                typed_check: 0,
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
        let match_for_index = storage_rw_for_array::<u32>(
            device,
            "brackets.match_for_index",
            total_sc.max(1) as usize,
        );

        // ---------- Tree (tiled stack) ----------
        // Shared tables/outputs
        let prod_arity = storage_ro_from_u32s(device, "parser.prod_arity", &tables.prod_arity);
        // Note: the tree’s node count equals total_emit
        let node_kind =
            storage_rw_for_array::<u32>(device, "parser.node_kind", total_emit.max(1) as usize);
        let parent =
            storage_rw_for_array::<u32>(device, "parser.parent", total_emit.max(1) as usize);

        // Params
        let tb_block_size: u32 = 1024;
        let n_blocks_tb = ((total_emit + tb_block_size - 1) / tb_block_size).max(1);
        let max_stack_depth = tb_block_size; // conservative bound

        let tb01_params = uniform_from_val(
            device,
            "parser.tb01.params",
            &super::passes::tree_blocked_01::Params {
                n: total_emit,
                block_size: tb_block_size,
            },
        );

        let tb02_params = uniform_from_val(
            device,
            "parser.tb02.params",
            &super::passes::tree_blocked_02::Params {
                n: total_emit,
                block_size: tb_block_size,
                num_blocks: n_blocks_tb,
            },
        );

        let tb03_params = uniform_from_val(
            device,
            "parser.tb03.params",
            &super::passes::tree_blocked_03::Params {
                n: total_emit,
                block_size: tb_block_size,
            },
        );

        // Tiled tree buffers (CSR-style snapshots)
        let tb_end_off =
            storage_rw_for_array::<u32>(device, "parser.tb_end_off", (n_blocks_tb + 1) as usize);
        let tb_end_nodes = storage_rw_for_array::<u32>(
            device,
            "parser.tb_end_nodes",
            (n_blocks_tb * max_stack_depth) as usize,
        );
        let tb_end_rem = storage_rw_for_array::<u32>(
            device,
            "parser.tb_end_rem",
            (n_blocks_tb * max_stack_depth) as usize,
        );
        let tb_start_off =
            storage_rw_for_array::<u32>(device, "parser.tb_start_off", (n_blocks_tb + 1) as usize);
        let tb_start_nodes = storage_rw_for_array::<u32>(
            device,
            "parser.tb_start_nodes",
            (n_blocks_tb * max_stack_depth) as usize,
        );
        let tb_start_rem = storage_rw_for_array::<u32>(
            device,
            "parser.tb_start_rem",
            (n_blocks_tb * max_stack_depth) as usize,
        );

        Self {
            n_tokens,
            n_kinds,
            total_sc,
            total_emit,

            params_llp,
            token_kinds,
            action_table,
            out_headers,

            params_pack,
            sc_offsets,
            emit_offsets,
            tables_blob,
            out_sc,
            out_emit,

            b01_params,
            b02_params,
            b03_params,
            b04_params,
            b05_params,
            b06_params,
            b07_params,

            b_exscan_inblock,
            b_block_sum,
            b_block_minpref,
            b_block_maxdepth,
            b_block_prefix,

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
            match_for_index,

            b_n_blocks: n_blocks,
            b_n_layers: n_layers,

            // Tree (tiled)
            tb01_params,
            tb02_params,
            tb03_params,

            prod_arity,
            node_kind,
            parent,

            tb_end_off,
            tb_end_nodes,
            tb_end_rem,
            tb_start_off,
            tb_start_nodes,
            tb_start_rem,
        }
    }
}
