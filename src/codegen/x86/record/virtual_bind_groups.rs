use anyhow::Result;

use super::{
    super::{
        GpuX86CodeGenerator,
        support::{UniformBindingArray, reflected_bind_group},
    },
    bind_helpers::scan_block_groups,
    scan::final_ping_pong_scan_prefix,
};

pub(super) struct VirtualBindGroups {
    pub(super) liveness_init: wgpu::BindGroup,
    pub(super) liveness: wgpu::BindGroup,
    pub(super) next_call: Vec<wgpu::BindGroup>,
    pub(super) param_masks: wgpu::BindGroup,
    pub(super) spans_fixed_barrier: wgpu::BindGroup,
    pub(super) value_def_flags: wgpu::BindGroup,
    pub(super) value_def_scan_local: wgpu::BindGroup,
    pub(super) value_def_scan_block: Vec<wgpu::BindGroup>,
    pub(super) value_def_compact: wgpu::BindGroup,
    pub(super) regalloc: wgpu::BindGroup,
    pub(super) func_rows_init: wgpu::BindGroup,
    pub(super) func_first_row: wgpu::BindGroup,
    pub(super) func_span_max: wgpu::BindGroup,
    pub(super) regalloc_dispatch_args: wgpu::BindGroup,
}

pub(super) struct VirtualBindGroupInputs<'a> {
    pub(super) params: &'a wgpu::Buffer,
    pub(super) text_scan_params: &'a UniformBindingArray,
    pub(super) next_call_params: &'a UniformBindingArray,
    pub(super) regalloc_params: &'a UniformBindingArray,
    pub(super) func_meta: &'a wgpu::Buffer,
    pub(super) func_slot_by_index: &'a wgpu::Buffer,
    pub(super) func_slot_by_node: &'a wgpu::Buffer,
    pub(super) final_node_func: &'a wgpu::Buffer,
    pub(super) func_param_reg_mask: &'a wgpu::Buffer,
    pub(super) func_param_reg_mask_status: &'a wgpu::Buffer,
    pub(super) virtual_inst_record: &'a wgpu::Buffer,
    pub(super) virtual_inst_args: &'a wgpu::Buffer,
    pub(super) virtual_inst_status: &'a wgpu::Buffer,
    pub(super) virtual_func_slot: &'a wgpu::Buffer,
    pub(super) virtual_next_call_a: &'a wgpu::Buffer,
    pub(super) virtual_next_call_b: &'a wgpu::Buffer,
    pub(super) virtual_next_call_status: &'a wgpu::Buffer,
    pub(super) virtual_live_start: &'a wgpu::Buffer,
    pub(super) virtual_live_end: &'a wgpu::Buffer,
    pub(super) virtual_liveness_status: &'a wgpu::Buffer,
    pub(super) virtual_phys_reg: &'a wgpu::Buffer,
    pub(super) virtual_call_live_reg_mask: &'a wgpu::Buffer,
    pub(super) virtual_func_first_row: &'a wgpu::Buffer,
    pub(super) virtual_func_last_row: &'a wgpu::Buffer,
    pub(super) virtual_func_first_row_status: &'a wgpu::Buffer,
    pub(super) virtual_value_def_flag: &'a wgpu::Buffer,
    pub(super) virtual_value_def_scan_local_prefix: &'a wgpu::Buffer,
    pub(super) virtual_value_def_scan_block_sum: &'a wgpu::Buffer,
    pub(super) virtual_value_def_scan_prefix_a: &'a wgpu::Buffer,
    pub(super) virtual_value_def_scan_prefix_b: &'a wgpu::Buffer,
    pub(super) virtual_value_def_row: &'a wgpu::Buffer,
    pub(super) virtual_value_def_status: &'a wgpu::Buffer,
    pub(super) virtual_regalloc_active_end: &'a wgpu::Buffer,
    pub(super) virtual_regalloc_param_rank_mask: &'a wgpu::Buffer,
    pub(super) virtual_regalloc_status: &'a wgpu::Buffer,
    pub(super) virtual_regalloc_dispatch_args: &'a wgpu::Buffer,
}

pub(super) fn create_virtual_bind_groups(
    generator: &GpuX86CodeGenerator,
    device: &wgpu::Device,
    inputs: VirtualBindGroupInputs<'_>,
) -> Result<VirtualBindGroups> {
    let VirtualBindGroupInputs {
        params,
        text_scan_params,
        next_call_params,
        regalloc_params,
        func_meta,
        func_slot_by_index,
        func_slot_by_node,
        final_node_func,
        func_param_reg_mask,
        func_param_reg_mask_status,
        virtual_inst_record,
        virtual_inst_args,
        virtual_inst_status,
        virtual_func_slot,
        virtual_next_call_a,
        virtual_next_call_b,
        virtual_next_call_status,
        virtual_live_start,
        virtual_live_end,
        virtual_liveness_status,
        virtual_phys_reg,
        virtual_call_live_reg_mask,
        virtual_func_first_row,
        virtual_func_last_row,
        virtual_func_first_row_status,
        virtual_value_def_flag,
        virtual_value_def_scan_local_prefix,
        virtual_value_def_scan_block_sum,
        virtual_value_def_scan_prefix_a,
        virtual_value_def_scan_prefix_b,
        virtual_value_def_row,
        virtual_value_def_status,
        virtual_regalloc_active_end,
        virtual_regalloc_param_rank_mask,
        virtual_regalloc_status,
        virtual_regalloc_dispatch_args,
    } = inputs;

    let liveness_init = reflected_bind_group(
        device,
        Some("codegen.x86.virtual_liveness_init.bind_group"),
        &generator.virtual_liveness_init_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
            (
                "x86_virtual_live_start",
                virtual_live_start.as_entire_binding(),
            ),
            ("x86_virtual_live_end", virtual_live_end.as_entire_binding()),
            ("x86_virtual_phys_reg", virtual_phys_reg.as_entire_binding()),
        ],
    )?;
    let liveness = reflected_bind_group(
        device,
        Some("codegen.x86.virtual_liveness.bind_group"),
        &generator.virtual_liveness_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_args",
                virtual_inst_args.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
            ("x86_virtual_live_end", virtual_live_end.as_entire_binding()),
            (
                "x86_virtual_liveness_status",
                virtual_liveness_status.as_entire_binding(),
            ),
        ],
    )?;
    let next_call_even = reflected_bind_group(
        device,
        Some("codegen.x86.virtual_next_calls.even.bind_group"),
        &generator.virtual_next_calls_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("gNextCallScan", next_call_params.binding(0)),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_args",
                virtual_inst_args.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
            (
                "x86_virtual_func_slot",
                virtual_func_slot.as_entire_binding(),
            ),
            (
                "x86_virtual_next_call_in",
                virtual_next_call_b.as_entire_binding(),
            ),
            (
                "x86_virtual_next_call_out",
                virtual_next_call_a.as_entire_binding(),
            ),
            (
                "x86_virtual_next_call_status",
                virtual_next_call_status.as_entire_binding(),
            ),
        ],
    )?;
    let next_call_odd = reflected_bind_group(
        device,
        Some("codegen.x86.virtual_next_calls.odd.bind_group"),
        &generator.virtual_next_calls_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("gNextCallScan", next_call_params.binding(0)),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_args",
                virtual_inst_args.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
            (
                "x86_virtual_func_slot",
                virtual_func_slot.as_entire_binding(),
            ),
            (
                "x86_virtual_next_call_in",
                virtual_next_call_a.as_entire_binding(),
            ),
            (
                "x86_virtual_next_call_out",
                virtual_next_call_b.as_entire_binding(),
            ),
            (
                "x86_virtual_next_call_status",
                virtual_next_call_status.as_entire_binding(),
            ),
        ],
    )?;
    let next_call = vec![next_call_even, next_call_odd];
    let param_masks = reflected_bind_group(
        device,
        Some("codegen.x86.virtual_param_masks.bind_group"),
        &generator.virtual_param_masks_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_args",
                virtual_inst_args.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
            (
                "x86_virtual_func_slot",
                virtual_func_slot.as_entire_binding(),
            ),
            (
                "x86_func_param_reg_mask",
                func_param_reg_mask.as_entire_binding(),
            ),
            (
                "x86_func_param_reg_mask_status",
                func_param_reg_mask_status.as_entire_binding(),
            ),
        ],
    )?;
    let spans_fixed_barrier = reflected_bind_group(
        device,
        Some("codegen.x86.virtual_spans_fixed_barrier.bind_group"),
        &generator.virtual_spans_fixed_barrier_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
            (
                "x86_virtual_live_start",
                virtual_live_start.as_entire_binding(),
            ),
            ("x86_virtual_live_end", virtual_live_end.as_entire_binding()),
            (
                "x86_virtual_liveness_status",
                virtual_liveness_status.as_entire_binding(),
            ),
            (
                "x86_virtual_next_call_a",
                virtual_next_call_a.as_entire_binding(),
            ),
            (
                "x86_virtual_next_call_b",
                virtual_next_call_b.as_entire_binding(),
            ),
            (
                "x86_virtual_next_call_status",
                virtual_next_call_status.as_entire_binding(),
            ),
            (
                "x86_virtual_spans_fixed_barrier",
                virtual_call_live_reg_mask.as_entire_binding(),
            ),
        ],
    )?;
    let value_def_flags = reflected_bind_group(
        device,
        Some("codegen.x86.virtual_value_def_flags.bind_group"),
        &generator.virtual_value_def_flags_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
            ("x86_virtual_live_end", virtual_live_end.as_entire_binding()),
            (
                "x86_virtual_liveness_status",
                virtual_liveness_status.as_entire_binding(),
            ),
            (
                "x86_virtual_value_def_flag",
                virtual_value_def_flag.as_entire_binding(),
            ),
        ],
    )?;
    let value_def_scan_local = reflected_bind_group(
        device,
        Some("codegen.x86.virtual_value_def_scan_local.bind_group"),
        &generator.node_inst_scan_local_pass,
        0,
        &[
            ("gScan", text_scan_params.binding(0)),
            (
                "x86_node_inst_scan_input",
                virtual_value_def_flag.as_entire_binding(),
            ),
            (
                "x86_node_inst_scan_local_prefix",
                virtual_value_def_scan_local_prefix.as_entire_binding(),
            ),
            (
                "x86_node_inst_scan_block_sum",
                virtual_value_def_scan_block_sum.as_entire_binding(),
            ),
        ],
    )?;
    let value_def_scan_block = scan_block_groups(
        device,
        [
            "codegen.x86.virtual_value_def_scan_blocks.bind_group",
            "codegen.x86.virtual_value_def_scan_blocks.bind_group",
        ],
        &generator.node_inst_scan_blocks_pass,
        text_scan_params,
        "gNodeInstBlockScan",
        "x86_node_inst_scan_block_sum",
        "x86_node_inst_scan_block_prefix_in",
        "x86_node_inst_scan_block_prefix_out",
        virtual_value_def_scan_block_sum,
        virtual_value_def_scan_prefix_a,
        virtual_value_def_scan_prefix_b,
    )?;
    let final_value_def_scan_prefix = final_ping_pong_scan_prefix(
        text_scan_params,
        virtual_value_def_scan_prefix_a,
        virtual_value_def_scan_prefix_b,
    );
    let value_def_compact = reflected_bind_group(
        device,
        Some("codegen.x86.virtual_value_def_compact.bind_group"),
        &generator.virtual_value_def_compact_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
            (
                "x86_virtual_value_def_flag",
                virtual_value_def_flag.as_entire_binding(),
            ),
            (
                "x86_virtual_value_def_scan_local_prefix",
                virtual_value_def_scan_local_prefix.as_entire_binding(),
            ),
            (
                "x86_virtual_value_def_scan_block_prefix",
                final_value_def_scan_prefix.as_entire_binding(),
            ),
            (
                "x86_virtual_value_def_row",
                virtual_value_def_row.as_entire_binding(),
            ),
            (
                "x86_virtual_value_def_status",
                virtual_value_def_status.as_entire_binding(),
            ),
        ],
    )?;
    let regalloc = reflected_bind_group(
        device,
        Some("codegen.x86.virtual_regalloc.bind_group"),
        &generator.virtual_regalloc_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("gRegalloc", regalloc_params.binding(0)),
            ("x86_func_meta", func_meta.as_entire_binding()),
            (
                "x86_func_slot_by_index",
                func_slot_by_index.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_args",
                virtual_inst_args.as_entire_binding(),
            ),
            (
                "x86_virtual_live_start",
                virtual_live_start.as_entire_binding(),
            ),
            ("x86_virtual_live_end", virtual_live_end.as_entire_binding()),
            (
                "x86_virtual_liveness_status",
                virtual_liveness_status.as_entire_binding(),
            ),
            (
                "x86_virtual_next_call_status",
                virtual_next_call_status.as_entire_binding(),
            ),
            (
                "x86_func_param_reg_mask",
                func_param_reg_mask.as_entire_binding(),
            ),
            (
                "x86_func_param_reg_mask_status",
                func_param_reg_mask_status.as_entire_binding(),
            ),
            (
                "x86_func_first_virtual_row",
                virtual_func_first_row.as_entire_binding(),
            ),
            (
                "x86_func_last_virtual_row",
                virtual_func_last_row.as_entire_binding(),
            ),
            (
                "x86_func_first_virtual_row_status",
                virtual_func_first_row_status.as_entire_binding(),
            ),
            (
                "x86_virtual_value_def_row",
                virtual_value_def_row.as_entire_binding(),
            ),
            (
                "x86_virtual_value_def_status",
                virtual_value_def_status.as_entire_binding(),
            ),
            (
                "x86_virtual_func_slot",
                virtual_func_slot.as_entire_binding(),
            ),
            (
                "x86_virtual_regalloc_active_end",
                virtual_regalloc_active_end.as_entire_binding(),
            ),
            (
                "x86_virtual_regalloc_param_rank_mask",
                virtual_regalloc_param_rank_mask.as_entire_binding(),
            ),
            ("x86_virtual_phys_reg", virtual_phys_reg.as_entire_binding()),
            (
                "x86_virtual_call_live_reg_mask",
                virtual_call_live_reg_mask.as_entire_binding(),
            ),
            (
                "x86_virtual_regalloc_status",
                virtual_regalloc_status.as_entire_binding(),
            ),
        ],
    )?;
    let func_rows_init = reflected_bind_group(
        device,
        Some("codegen.x86.virtual_func_rows_init.bind_group"),
        &generator.virtual_func_rows_init_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("x86_func_meta", func_meta.as_entire_binding()),
            (
                "x86_func_slot_by_index",
                func_slot_by_index.as_entire_binding(),
            ),
            (
                "x86_func_first_virtual_row",
                virtual_func_first_row.as_entire_binding(),
            ),
            (
                "x86_func_last_virtual_row",
                virtual_func_last_row.as_entire_binding(),
            ),
            (
                "x86_func_param_reg_mask",
                func_param_reg_mask.as_entire_binding(),
            ),
        ],
    )?;
    let func_first_row = reflected_bind_group(
        device,
        Some("codegen.x86.virtual_func_first_row.bind_group"),
        &generator.virtual_func_first_row_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "x86_virtual_inst_record",
                virtual_inst_record.as_entire_binding(),
            ),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
            ("x86_node_func", final_node_func.as_entire_binding()),
            (
                "x86_func_slot_by_node",
                func_slot_by_node.as_entire_binding(),
            ),
            (
                "x86_func_first_virtual_row",
                virtual_func_first_row.as_entire_binding(),
            ),
            (
                "x86_func_last_virtual_row",
                virtual_func_last_row.as_entire_binding(),
            ),
            (
                "x86_func_first_virtual_row_status",
                virtual_func_first_row_status.as_entire_binding(),
            ),
            (
                "x86_virtual_func_slot",
                virtual_func_slot.as_entire_binding(),
            ),
        ],
    )?;
    let func_span_max = reflected_bind_group(
        device,
        Some("codegen.x86.virtual_func_span_max.bind_group"),
        &generator.virtual_func_span_max_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "x86_func_slot_by_index",
                func_slot_by_index.as_entire_binding(),
            ),
            (
                "x86_func_first_virtual_row",
                virtual_func_first_row.as_entire_binding(),
            ),
            (
                "x86_func_last_virtual_row",
                virtual_func_last_row.as_entire_binding(),
            ),
            (
                "x86_func_first_virtual_row_status",
                virtual_func_first_row_status.as_entire_binding(),
            ),
            ("x86_func_meta", func_meta.as_entire_binding()),
        ],
    )?;
    let regalloc_dispatch_args = reflected_bind_group(
        device,
        Some("codegen.x86.virtual_regalloc_dispatch_args.bind_group"),
        &generator.virtual_regalloc_dispatch_args_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "x86_virtual_inst_status",
                virtual_inst_status.as_entire_binding(),
            ),
            (
                "x86_virtual_value_def_status",
                virtual_value_def_status.as_entire_binding(),
            ),
            ("x86_func_meta", func_meta.as_entire_binding()),
            (
                "active_virtual_regalloc_dispatch_args",
                virtual_regalloc_dispatch_args.as_entire_binding(),
            ),
        ],
    )?;

    Ok(VirtualBindGroups {
        liveness_init,
        liveness,
        next_call,
        param_masks,
        spans_fixed_barrier,
        value_def_flags,
        value_def_scan_local,
        value_def_scan_block,
        value_def_compact,
        regalloc,
        func_rows_init,
        func_first_row,
        func_span_max,
        regalloc_dispatch_args,
    })
}
