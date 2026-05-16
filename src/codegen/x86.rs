use anyhow::Result;
use encase::ShaderType;

use crate::gpu::{
    device,
    passes_core::{PassData, make_traced_main_pass},
};

mod finish;
mod record;
mod support;

use support::trace_x86_codegen;

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct X86Params {
    n_tokens: u32,
    source_len: u32,
    out_capacity: u32,
    n_hir_nodes: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct X86ScanParams {
    n_items: u32,
    n_blocks: u32,
    scan_step: u32,
}

pub struct GpuX86ExprMetadataBuffers<'a> {
    pub record: &'a wgpu::Buffer,
    pub int_value: &'a wgpu::Buffer,
    pub stmt_record: &'a wgpu::Buffer,
}

pub struct GpuX86FunctionMetadataBuffers<'a> {
    pub item_kind: &'a wgpu::Buffer,
    pub item_decl_token: &'a wgpu::Buffer,
    pub param_record: &'a wgpu::Buffer,
}

pub struct GpuX86CallMetadataBuffers<'a> {
    pub callee_node: &'a wgpu::Buffer,
    pub arg_start: &'a wgpu::Buffer,
    pub arg_end: &'a wgpu::Buffer,
    pub arg_count: &'a wgpu::Buffer,
    pub arg_parent_call: &'a wgpu::Buffer,
    pub arg_ordinal: &'a wgpu::Buffer,
    pub call_fn_index: &'a wgpu::Buffer,
    pub call_intrinsic_tag: &'a wgpu::Buffer,
    pub call_return_type: &'a wgpu::Buffer,
    pub call_return_type_token: &'a wgpu::Buffer,
    pub call_param_type: &'a wgpu::Buffer,
}

const MAX_X86_VREGS: usize = 8;
const MAX_X86_USE_EDGES: usize = MAX_X86_VREGS * 4 + 1;
const MAX_X86_INSTS: usize = 256;
const MAX_X86_NODE_LOCAL_INSTS: usize = 4;
const MAX_X86_VIRTUAL_USE_EDGES: usize = MAX_X86_INSTS * 4 + 1;
const MAX_X86_RELOCS: usize = 8;

pub struct RecordedX86Codegen {
    output_capacity: usize,
    _retained_buffers: Vec<wgpu::Buffer>,
    out_buf: wgpu::Buffer,
    status_readback: wgpu::Buffer,
    status_trace_readback: Option<wgpu::Buffer>,
    out_readback: wgpu::Buffer,
}

pub struct GpuX86CodeGenerator {
    node_tree_info_pass: PassData,
    func_discover_pass: PassData,
    call_records_pass: PassData,
    const_values_pass: PassData,
    param_regs_pass: PassData,
    local_literals_pass: PassData,
    func_return_stmts_pass: PassData,
    block_return_stmts_pass: PassData,
    terminal_ifs_pass: PassData,
    return_calls_pass: PassData,
    call_arg_values_pass: PassData,
    call_arg_lookup_pass: PassData,
    intrinsic_calls_pass: PassData,
    call_abi_pass: PassData,
    call_arg_widths_pass: PassData,
    call_arg_prefix_seed_pass: PassData,
    call_arg_prefix_scan_pass: PassData,
    call_arg_vregs_pass: PassData,
    node_inst_counts_pass: PassData,
    node_inst_order_pass: PassData,
    node_inst_scan_local_pass: PassData,
    node_inst_scan_blocks_pass: PassData,
    node_inst_prefix_scan_pass: PassData,
    node_inst_locations_pass: PassData,
    node_inst_gen_pass: PassData,
    virtual_use_edges_pass: PassData,
    virtual_liveness_pass: PassData,
    virtual_regalloc_pass: PassData,
    func_body_plan_pass: PassData,
    lower_values_pass: PassData,
    use_edges_pass: PassData,
    liveness_pass: PassData,
    regalloc_pass: PassData,
    func_inst_counts_pass: PassData,
    func_inst_order_pass: PassData,
    func_inst_scan_local_pass: PassData,
    func_inst_scan_blocks_pass: PassData,
    func_inst_prefix_scan_pass: PassData,
    func_layout_pass: PassData,
    func_return_inst_plan_pass: PassData,
    entry_inst_plan_pass: PassData,
    inst_plan_pass: PassData,
    reloc_plan_pass: PassData,
    select_pass: PassData,
    inst_size_pass: PassData,
    text_offsets_pass: PassData,
    encode_pass: PassData,
    reloc_patch_pass: PassData,
    elf_layout_pass: PassData,
    elf_write_pass: PassData,
}

impl GpuX86CodeGenerator {
    pub fn new_with_device(gpu: &device::GpuDevice) -> Result<Self> {
        macro_rules! load_x86_pass {
            ($name:literal, $spv:literal, $reflection:literal) => {{
                make_traced_main_pass!(
                    &gpu.device,
                    trace_x86_codegen,
                    $name,
                    concat!("codegen_x86_", $name),
                    artifacts: ($spv, $reflection)
                )
            }};
        }

        let node_tree_info_pass = load_x86_pass!(
            "node_tree_info",
            "x86_node_tree_info.spv",
            "x86_node_tree_info.reflect.json"
        );
        let func_discover_pass = load_x86_pass!(
            "func_discover",
            "x86_func_discover.spv",
            "x86_func_discover.reflect.json"
        );
        let call_records_pass = load_x86_pass!(
            "call_records",
            "x86_call_records.spv",
            "x86_call_records.reflect.json"
        );
        let const_values_pass = load_x86_pass!(
            "const_values",
            "x86_const_values.spv",
            "x86_const_values.reflect.json"
        );
        let param_regs_pass = load_x86_pass!(
            "param_regs",
            "x86_param_regs.spv",
            "x86_param_regs.reflect.json"
        );
        let local_literals_pass = load_x86_pass!(
            "local_literals",
            "x86_local_literals.spv",
            "x86_local_literals.reflect.json"
        );
        let func_return_stmts_pass = load_x86_pass!(
            "func_return_stmts",
            "x86_func_return_stmts.spv",
            "x86_func_return_stmts.reflect.json"
        );
        let block_return_stmts_pass = load_x86_pass!(
            "block_return_stmts",
            "x86_block_return_stmts.spv",
            "x86_block_return_stmts.reflect.json"
        );
        let terminal_ifs_pass = load_x86_pass!(
            "terminal_ifs",
            "x86_terminal_ifs.spv",
            "x86_terminal_ifs.reflect.json"
        );
        let return_calls_pass = load_x86_pass!(
            "return_calls",
            "x86_return_calls.spv",
            "x86_return_calls.reflect.json"
        );
        let call_arg_values_pass = load_x86_pass!(
            "call_arg_values",
            "x86_call_arg_values.spv",
            "x86_call_arg_values.reflect.json"
        );
        let call_arg_lookup_pass = load_x86_pass!(
            "call_arg_lookup",
            "x86_call_arg_lookup.spv",
            "x86_call_arg_lookup.reflect.json"
        );
        let intrinsic_calls_pass = load_x86_pass!(
            "intrinsic_calls",
            "x86_intrinsic_calls.spv",
            "x86_intrinsic_calls.reflect.json"
        );
        let call_abi_pass =
            load_x86_pass!("call_abi", "x86_call_abi.spv", "x86_call_abi.reflect.json");
        let call_arg_widths_pass = load_x86_pass!(
            "call_arg_widths",
            "x86_call_arg_widths.spv",
            "x86_call_arg_widths.reflect.json"
        );
        let call_arg_prefix_seed_pass = load_x86_pass!(
            "call_arg_prefix_seed",
            "x86_call_arg_prefix_seed.spv",
            "x86_call_arg_prefix_seed.reflect.json"
        );
        let call_arg_prefix_scan_pass = load_x86_pass!(
            "call_arg_prefix_scan",
            "x86_call_arg_prefix_scan.spv",
            "x86_call_arg_prefix_scan.reflect.json"
        );
        let call_arg_vregs_pass = load_x86_pass!(
            "call_arg_vregs",
            "x86_call_arg_vregs.spv",
            "x86_call_arg_vregs.reflect.json"
        );
        let node_inst_counts_pass = load_x86_pass!(
            "node_inst_counts",
            "x86_node_inst_counts.spv",
            "x86_node_inst_counts.reflect.json"
        );
        let node_inst_order_pass = load_x86_pass!(
            "node_inst_order",
            "x86_node_inst_order.spv",
            "x86_node_inst_order.reflect.json"
        );
        let node_inst_scan_local_pass = load_x86_pass!(
            "node_inst_scan_local",
            "x86_node_inst_scan_local.spv",
            "x86_node_inst_scan_local.reflect.json"
        );
        let node_inst_scan_blocks_pass = load_x86_pass!(
            "node_inst_scan_blocks",
            "x86_node_inst_scan_blocks.spv",
            "x86_node_inst_scan_blocks.reflect.json"
        );
        let node_inst_prefix_scan_pass = load_x86_pass!(
            "node_inst_prefix_scan",
            "x86_node_inst_prefix_scan.spv",
            "x86_node_inst_prefix_scan.reflect.json"
        );
        let node_inst_locations_pass = load_x86_pass!(
            "node_inst_locations",
            "x86_node_inst_locations.spv",
            "x86_node_inst_locations.reflect.json"
        );
        let node_inst_gen_pass = load_x86_pass!(
            "node_inst_gen",
            "x86_node_inst_gen.spv",
            "x86_node_inst_gen.reflect.json"
        );
        let virtual_use_edges_pass = load_x86_pass!(
            "virtual_use_edges",
            "x86_virtual_use_edges.spv",
            "x86_virtual_use_edges.reflect.json"
        );
        let virtual_liveness_pass = load_x86_pass!(
            "virtual_liveness",
            "x86_virtual_liveness.spv",
            "x86_virtual_liveness.reflect.json"
        );
        let virtual_regalloc_pass = load_x86_pass!(
            "virtual_regalloc",
            "x86_virtual_regalloc.spv",
            "x86_virtual_regalloc.reflect.json"
        );
        let func_body_plan_pass = load_x86_pass!(
            "func_body_plan",
            "x86_func_body_plan.spv",
            "x86_func_body_plan.reflect.json"
        );
        let lower_values_pass = load_x86_pass!(
            "lower_values",
            "x86_lower_values.spv",
            "x86_lower_values.reflect.json"
        );
        let use_edges_pass = load_x86_pass!(
            "use_edges",
            "x86_use_edges.spv",
            "x86_use_edges.reflect.json"
        );
        let liveness_pass =
            load_x86_pass!("liveness", "x86_liveness.spv", "x86_liveness.reflect.json");
        let regalloc_pass =
            load_x86_pass!("regalloc", "x86_regalloc.spv", "x86_regalloc.reflect.json");
        let func_inst_counts_pass = load_x86_pass!(
            "func_inst_counts",
            "x86_func_inst_counts.spv",
            "x86_func_inst_counts.reflect.json"
        );
        let func_inst_order_pass = load_x86_pass!(
            "func_inst_order",
            "x86_func_inst_order.spv",
            "x86_func_inst_order.reflect.json"
        );
        let func_inst_scan_local_pass = load_x86_pass!(
            "func_inst_scan_local",
            "x86_func_inst_scan_local.spv",
            "x86_func_inst_scan_local.reflect.json"
        );
        let func_inst_scan_blocks_pass = load_x86_pass!(
            "func_inst_scan_blocks",
            "x86_func_inst_scan_blocks.spv",
            "x86_func_inst_scan_blocks.reflect.json"
        );
        let func_inst_prefix_scan_pass = load_x86_pass!(
            "func_inst_prefix_scan",
            "x86_func_inst_prefix_scan.spv",
            "x86_func_inst_prefix_scan.reflect.json"
        );
        let func_layout_pass = load_x86_pass!(
            "func_layout",
            "x86_func_layout.spv",
            "x86_func_layout.reflect.json"
        );
        let func_return_inst_plan_pass = load_x86_pass!(
            "func_return_inst_plan",
            "x86_func_return_inst_plan.spv",
            "x86_func_return_inst_plan.reflect.json"
        );
        let entry_inst_plan_pass = load_x86_pass!(
            "entry_inst_plan",
            "x86_entry_inst_plan.spv",
            "x86_entry_inst_plan.reflect.json"
        );
        let inst_plan_pass = load_x86_pass!(
            "inst_plan",
            "x86_inst_plan.spv",
            "x86_inst_plan.reflect.json"
        );
        let reloc_plan_pass = load_x86_pass!(
            "reloc_plan",
            "x86_reloc_plan.spv",
            "x86_reloc_plan.reflect.json"
        );
        let select_pass = load_x86_pass!("select", "x86_select.spv", "x86_select.reflect.json");
        let inst_size_pass = load_x86_pass!(
            "inst_size",
            "x86_inst_size.spv",
            "x86_inst_size.reflect.json"
        );
        let text_offsets_pass = load_x86_pass!(
            "text_offsets",
            "x86_text_offsets.spv",
            "x86_text_offsets.reflect.json"
        );
        let encode_pass = load_x86_pass!("encode", "x86_encode.spv", "x86_encode.reflect.json");
        let reloc_patch_pass = load_x86_pass!(
            "reloc_patch",
            "x86_reloc_patch.spv",
            "x86_reloc_patch.reflect.json"
        );
        let elf_layout_pass = load_x86_pass!(
            "elf_layout",
            "x86_elf_layout.spv",
            "x86_elf_layout.reflect.json"
        );
        let elf_write_pass = load_x86_pass!(
            "elf_write",
            "x86_elf_write.spv",
            "x86_elf_write.reflect.json"
        );
        Ok(Self {
            node_tree_info_pass,
            func_discover_pass,
            call_records_pass,
            const_values_pass,
            param_regs_pass,
            local_literals_pass,
            func_return_stmts_pass,
            block_return_stmts_pass,
            terminal_ifs_pass,
            return_calls_pass,
            call_arg_values_pass,
            call_arg_lookup_pass,
            intrinsic_calls_pass,
            call_abi_pass,
            call_arg_widths_pass,
            call_arg_prefix_seed_pass,
            call_arg_prefix_scan_pass,
            call_arg_vregs_pass,
            node_inst_counts_pass,
            node_inst_order_pass,
            node_inst_scan_local_pass,
            node_inst_scan_blocks_pass,
            node_inst_prefix_scan_pass,
            node_inst_locations_pass,
            node_inst_gen_pass,
            virtual_use_edges_pass,
            virtual_liveness_pass,
            virtual_regalloc_pass,
            func_body_plan_pass,
            lower_values_pass,
            use_edges_pass,
            liveness_pass,
            regalloc_pass,
            func_inst_counts_pass,
            func_inst_order_pass,
            func_inst_scan_local_pass,
            func_inst_scan_blocks_pass,
            func_inst_prefix_scan_pass,
            func_layout_pass,
            func_return_inst_plan_pass,
            entry_inst_plan_pass,
            inst_plan_pass,
            reloc_plan_pass,
            select_pass,
            inst_size_pass,
            text_offsets_pass,
            encode_pass,
            reloc_patch_pass,
            elf_layout_pass,
            elf_write_pass,
        })
    }
}
