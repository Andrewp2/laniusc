use anyhow::Result;

use super::{
    super::{
        GpuX86CodeGenerator,
        GpuX86ExprMetadataBuffers,
        GpuX86FunctionMetadataBuffers,
        support::{UniformBindingArray, reflected_bind_group},
    },
    bind_helpers::{StepNames, StepPairs, scan_block_groups, step_pair_groups},
};

pub(super) struct DispatchSetupBindGroups {
    pub(super) active_scan_dispatch_args: wgpu::BindGroup,
    pub(super) node_inst_scan_input_clear: wgpu::BindGroup,
    pub(super) call_callee_root_call_clear: wgpu::BindGroup,
    pub(super) node_order_dispatch_args: wgpu::BindGroup,
    pub(super) virtual_dispatch_args: wgpu::BindGroup,
    pub(super) output_dispatch_args: wgpu::BindGroup,
}

pub(super) struct DispatchSetupInputs<'a> {
    pub(super) params: &'a wgpu::Buffer,
    pub(super) hir_status: &'a wgpu::Buffer,
    pub(super) hir_count: &'a wgpu::Buffer,
    pub(super) hir_plus_one: &'a wgpu::Buffer,
    pub(super) hir_scan_block: &'a wgpu::Buffer,
    pub(super) node_inst_scan_input: &'a wgpu::Buffer,
    pub(super) call_callee_root_call: &'a wgpu::Buffer,
    pub(super) node_inst_order_status: &'a wgpu::Buffer,
    pub(super) node_order_scan: &'a wgpu::Buffer,
    pub(super) node_order_scan_block: &'a wgpu::Buffer,
    pub(super) virtual_inst_status: &'a wgpu::Buffer,
    pub(super) func_meta: &'a wgpu::Buffer,
    pub(super) function_dispatch: &'a wgpu::Buffer,
    pub(super) virtual_inst: &'a wgpu::Buffer,
    pub(super) virtual_next_call: &'a wgpu::Buffer,
    pub(super) selected_inst: &'a wgpu::Buffer,
    pub(super) selected_scan_block: &'a wgpu::Buffer,
    pub(super) text_len: &'a wgpu::Buffer,
    pub(super) text_status: &'a wgpu::Buffer,
    pub(super) text_word: &'a wgpu::Buffer,
    pub(super) elf_header_word: &'a wgpu::Buffer,
}

pub(super) fn create_dispatch_setup_bind_groups(
    generator: &GpuX86CodeGenerator,
    device: &wgpu::Device,
    inputs: DispatchSetupInputs<'_>,
) -> Result<DispatchSetupBindGroups> {
    let active_scan_dispatch_args = reflected_bind_group(
        device,
        Some("codegen.x86.active_scan_dispatch_args.bind_group"),
        &generator.active_scan_dispatch_args_pass,
        0,
        &[
            ("gParams", inputs.params.as_entire_binding()),
            ("hir_status", inputs.hir_status.as_entire_binding()),
            (
                "active_hir_count_dispatch_args",
                inputs.hir_count.as_entire_binding(),
            ),
            (
                "active_hir_plus_one_dispatch_args",
                inputs.hir_plus_one.as_entire_binding(),
            ),
            (
                "active_hir_scan_block_dispatch_args",
                inputs.hir_scan_block.as_entire_binding(),
            ),
        ],
    )?;
    let node_inst_scan_input_clear = reflected_bind_group(
        device,
        Some("codegen.x86.node_inst_scan_input.active_clear.bind_group"),
        &generator.active_clear_u32_pass,
        0,
        &[
            (
                "active_dispatch_args",
                inputs.hir_plus_one.as_entire_binding(),
            ),
            ("target", inputs.node_inst_scan_input.as_entire_binding()),
        ],
    )?;
    let call_callee_root_call_clear = reflected_bind_group(
        device,
        Some("codegen.x86.call_callee_root_call.active_clear.bind_group"),
        &generator.active_clear_u32_pass,
        0,
        &[
            ("active_dispatch_args", inputs.hir_count.as_entire_binding()),
            ("target", inputs.call_callee_root_call.as_entire_binding()),
        ],
    )?;
    let node_order_dispatch_args = reflected_bind_group(
        device,
        Some("codegen.x86.node_order_dispatch_args.bind_group"),
        &generator.node_order_dispatch_args_pass,
        0,
        &[
            ("gParams", inputs.params.as_entire_binding()),
            (
                "x86_node_inst_order_status",
                inputs.node_inst_order_status.as_entire_binding(),
            ),
            (
                "active_node_order_scan_dispatch_args",
                inputs.node_order_scan.as_entire_binding(),
            ),
            (
                "active_node_order_scan_block_dispatch_args",
                inputs.node_order_scan_block.as_entire_binding(),
            ),
        ],
    )?;
    let virtual_dispatch_args = reflected_bind_group(
        device,
        Some("codegen.x86.virtual_dispatch_args.bind_group"),
        &generator.virtual_dispatch_args_pass,
        0,
        &[
            ("gParams", inputs.params.as_entire_binding()),
            (
                "x86_virtual_inst_status",
                inputs.virtual_inst_status.as_entire_binding(),
            ),
            ("x86_func_meta", inputs.func_meta.as_entire_binding()),
            (
                "active_function_dispatch_args",
                inputs.function_dispatch.as_entire_binding(),
            ),
            (
                "active_virtual_inst_dispatch_args",
                inputs.virtual_inst.as_entire_binding(),
            ),
            (
                "active_virtual_next_call_dispatch_args",
                inputs.virtual_next_call.as_entire_binding(),
            ),
            (
                "active_selected_inst_dispatch_args",
                inputs.selected_inst.as_entire_binding(),
            ),
            (
                "active_selected_scan_block_dispatch_args",
                inputs.selected_scan_block.as_entire_binding(),
            ),
        ],
    )?;
    let output_dispatch_args = reflected_bind_group(
        device,
        Some("codegen.x86.output_dispatch_args.bind_group"),
        &generator.output_dispatch_args_pass,
        0,
        &[
            ("gParams", inputs.params.as_entire_binding()),
            ("x86_text_len", inputs.text_len.as_entire_binding()),
            ("text_status", inputs.text_status.as_entire_binding()),
            (
                "active_text_word_dispatch_args",
                inputs.text_word.as_entire_binding(),
            ),
            (
                "active_elf_header_word_dispatch_args",
                inputs.elf_header_word.as_entire_binding(),
            ),
        ],
    )?;

    Ok(DispatchSetupBindGroups {
        active_scan_dispatch_args,
        node_inst_scan_input_clear,
        call_callee_root_call_clear,
        node_order_dispatch_args,
        virtual_dispatch_args,
        output_dispatch_args,
    })
}

pub(super) struct FunctionDiscoveryBindGroups {
    pub(super) node_tree_info: wgpu::BindGroup,
    pub(super) func: wgpu::BindGroup,
    pub(super) func_owner_scan_local: wgpu::BindGroup,
    pub(super) func_owner_scan_block: Vec<wgpu::BindGroup>,
    pub(super) func_assign_nodes: wgpu::BindGroup,
    pub(super) func_assign_nodes_step: Vec<wgpu::BindGroup>,
    pub(super) func_slot_flags: wgpu::BindGroup,
    pub(super) func_slot_scatter: wgpu::BindGroup,
    pub(super) expr_resolve_init: wgpu::BindGroup,
    pub(super) expr_resolve_step: Vec<wgpu::BindGroup>,
}

pub(super) struct FunctionDiscoveryInputs<'a> {
    pub(super) params: &'a wgpu::Buffer,
    pub(super) hir_status: &'a wgpu::Buffer,
    pub(super) hir_kind: &'a wgpu::Buffer,
    pub(super) hir_item_kind: &'a wgpu::Buffer,
    pub(super) parent: &'a wgpu::Buffer,
    pub(super) subtree_end: &'a wgpu::Buffer,
    pub(super) function_metadata: &'a GpuX86FunctionMetadataBuffers<'a>,
    pub(super) expr_metadata: &'a GpuX86ExprMetadataBuffers<'a>,
    pub(super) fn_entrypoint_tag: &'a wgpu::Buffer,
    pub(super) node_tree_status: &'a wgpu::Buffer,
    pub(super) func_meta: &'a wgpu::Buffer,
    pub(super) node_func: &'a wgpu::Buffer,
    pub(super) decl_node_by_token: &'a wgpu::Buffer,
    pub(super) func_slot_by_node: &'a wgpu::Buffer,
    pub(super) func_owner_scan_params: &'a UniformBindingArray,
    pub(super) func_owner_scan_local_prefix: &'a wgpu::Buffer,
    pub(super) func_owner_scan_block_sum: &'a wgpu::Buffer,
    pub(super) func_owner_scan_prefix_a: &'a wgpu::Buffer,
    pub(super) func_owner_scan_prefix_b: &'a wgpu::Buffer,
    pub(super) final_func_owner_scan_prefix: &'a wgpu::Buffer,
    pub(super) node_func_owner_steps: &'a [u32],
    pub(super) node_func_owner_link_a: &'a wgpu::Buffer,
    pub(super) node_func_owner_link_b: &'a wgpu::Buffer,
    pub(super) node_func_owner_b: &'a wgpu::Buffer,
    pub(super) node_inst_scan_input: &'a wgpu::Buffer,
    pub(super) node_inst_scan_local_prefix: &'a wgpu::Buffer,
    pub(super) final_node_inst_scan_prefix: &'a wgpu::Buffer,
    pub(super) func_slot_by_index: &'a wgpu::Buffer,
    pub(super) expr_resolve_steps: &'a [u32],
    pub(super) expr_resolved_a: &'a wgpu::Buffer,
    pub(super) expr_resolved_b: &'a wgpu::Buffer,
    pub(super) expr_resolve_link_a: &'a wgpu::Buffer,
    pub(super) expr_resolve_link_b: &'a wgpu::Buffer,
}

pub(super) fn create_function_discovery_bind_groups(
    generator: &GpuX86CodeGenerator,
    device: &wgpu::Device,
    inputs: FunctionDiscoveryInputs<'_>,
) -> Result<FunctionDiscoveryBindGroups> {
    let node_tree_info = reflected_bind_group(
        device,
        Some("codegen.x86.node_tree_info.bind_group"),
        &generator.node_tree_info_pass,
        0,
        &[
            ("gParams", inputs.params.as_entire_binding()),
            ("hir_status", inputs.hir_status.as_entire_binding()),
            ("parent", inputs.parent.as_entire_binding()),
            ("subtree_end", inputs.subtree_end.as_entire_binding()),
            (
                "x86_node_tree_status",
                inputs.node_tree_status.as_entire_binding(),
            ),
        ],
    )?;
    let func = reflected_bind_group(
        device,
        Some("codegen.x86.func_discover.bind_group"),
        &generator.func_discover_pass,
        0,
        &[
            ("gParams", inputs.params.as_entire_binding()),
            ("hir_status", inputs.hir_status.as_entire_binding()),
            ("hir_kind", inputs.hir_kind.as_entire_binding()),
            ("hir_item_kind", inputs.hir_item_kind.as_entire_binding()),
            (
                "x86_node_tree_status",
                inputs.node_tree_status.as_entire_binding(),
            ),
            (
                "hir_node_decl_token",
                inputs.function_metadata.node_decl_token.as_entire_binding(),
            ),
            (
                "fn_entrypoint_tag",
                inputs.fn_entrypoint_tag.as_entire_binding(),
            ),
            ("x86_func_meta", inputs.func_meta.as_entire_binding()),
            ("x86_node_func", inputs.node_func.as_entire_binding()),
            (
                "x86_decl_node_by_token",
                inputs.decl_node_by_token.as_entire_binding(),
            ),
        ],
    )?;
    let func_owner_scan_local = reflected_bind_group(
        device,
        Some("codegen.x86.func_owner_scan_local.bind_group"),
        &generator.func_owner_scan_local_pass,
        0,
        &[
            ("gScan", inputs.func_owner_scan_params.binding(0)),
            ("hir_status", inputs.hir_status.as_entire_binding()),
            ("hir_kind", inputs.hir_kind.as_entire_binding()),
            ("hir_item_kind", inputs.hir_item_kind.as_entire_binding()),
            (
                "x86_func_owner_scan_local_prefix",
                inputs.func_owner_scan_local_prefix.as_entire_binding(),
            ),
            (
                "x86_func_owner_scan_block_sum",
                inputs.func_owner_scan_block_sum.as_entire_binding(),
            ),
        ],
    )?;
    let func_owner_scan_block = scan_block_groups(
        device,
        [
            "codegen.x86.func_owner_scan_blocks.even.bind_group",
            "codegen.x86.func_owner_scan_blocks.odd.bind_group",
        ],
        &generator.func_owner_scan_blocks_pass,
        inputs.func_owner_scan_params,
        "gFuncOwnerBlockScan",
        "x86_func_owner_scan_block_sum",
        "x86_func_owner_scan_block_prefix_in",
        "x86_func_owner_scan_block_prefix_out",
        inputs.func_owner_scan_block_sum,
        inputs.func_owner_scan_prefix_a,
        inputs.func_owner_scan_prefix_b,
    )?;
    let func_assign_nodes = reflected_bind_group(
        device,
        Some("codegen.x86.func_assign_nodes.bind_group"),
        &generator.func_assign_nodes_pass,
        0,
        &[
            ("gParams", inputs.params.as_entire_binding()),
            ("hir_status", inputs.hir_status.as_entire_binding()),
            ("hir_kind", inputs.hir_kind.as_entire_binding()),
            ("hir_item_kind", inputs.hir_item_kind.as_entire_binding()),
            ("x86_tree_parent", inputs.parent.as_entire_binding()),
            (
                "x86_tree_subtree_end",
                inputs.subtree_end.as_entire_binding(),
            ),
            (
                "x86_node_tree_status",
                inputs.node_tree_status.as_entire_binding(),
            ),
            (
                "x86_func_owner_scan_local_prefix",
                inputs.func_owner_scan_local_prefix.as_entire_binding(),
            ),
            (
                "x86_func_owner_scan_block_prefix",
                inputs.final_func_owner_scan_prefix.as_entire_binding(),
            ),
            ("x86_node_func", inputs.node_func.as_entire_binding()),
            (
                "x86_func_owner_link",
                inputs.node_func_owner_link_a.as_entire_binding(),
            ),
        ],
    )?;
    let func_assign_nodes_step = step_pair_groups(
        device,
        "codegen.x86.func_assign_nodes_step.bind_group",
        &generator.func_assign_nodes_step_pass,
        inputs.node_func_owner_steps,
        inputs.params,
        inputs.hir_status,
        &[("x86_node_tree_status", inputs.node_tree_status)],
        StepNames {
            first_in: "x86_func_owner_link_in",
            second_in: "x86_node_func_in",
            first_out: "x86_func_owner_link_out",
            second_out: "x86_node_func_out",
        },
        StepPairs {
            first_a: inputs.node_func_owner_link_a,
            first_b: inputs.node_func_owner_link_b,
            second_a: inputs.node_func,
            second_b: inputs.node_func_owner_b,
        },
    )?;
    let func_slot_flags = reflected_bind_group(
        device,
        Some("codegen.x86.func_slot_flags.bind_group"),
        &generator.func_slot_flags_pass,
        0,
        &[
            ("gParams", inputs.params.as_entire_binding()),
            ("hir_status", inputs.hir_status.as_entire_binding()),
            ("hir_kind", inputs.hir_kind.as_entire_binding()),
            ("hir_item_kind", inputs.hir_item_kind.as_entire_binding()),
            (
                "x86_func_slot_flags",
                inputs.node_inst_scan_input.as_entire_binding(),
            ),
        ],
    )?;
    let func_slot_scatter = reflected_bind_group(
        device,
        Some("codegen.x86.func_slot_scatter.bind_group"),
        &generator.func_slot_scatter_pass,
        0,
        &[
            ("gParams", inputs.params.as_entire_binding()),
            ("hir_status", inputs.hir_status.as_entire_binding()),
            (
                "x86_func_slot_flags",
                inputs.node_inst_scan_input.as_entire_binding(),
            ),
            (
                "x86_func_slot_by_node",
                inputs.func_slot_by_node.as_entire_binding(),
            ),
            (
                "x86_func_slot_scan_local_prefix",
                inputs.node_inst_scan_local_prefix.as_entire_binding(),
            ),
            (
                "x86_func_slot_scan_block_prefix",
                inputs.final_node_inst_scan_prefix.as_entire_binding(),
            ),
            ("x86_func_meta", inputs.func_meta.as_entire_binding()),
            (
                "x86_func_slot_by_index",
                inputs.func_slot_by_index.as_entire_binding(),
            ),
        ],
    )?;
    let expr_resolve_init = reflected_bind_group(
        device,
        Some("codegen.x86.expr_resolve_init.bind_group"),
        &generator.expr_resolve_init_pass,
        0,
        &[
            ("gParams", inputs.params.as_entire_binding()),
            ("hir_status", inputs.hir_status.as_entire_binding()),
            (
                "hir_expr_record",
                inputs.expr_metadata.record.as_entire_binding(),
            ),
            (
                "x86_expr_resolved_node",
                inputs.expr_resolved_a.as_entire_binding(),
            ),
            (
                "x86_expr_resolve_link",
                inputs.expr_resolve_link_a.as_entire_binding(),
            ),
        ],
    )?;
    let expr_resolve_step = step_pair_groups(
        device,
        "codegen.x86.expr_resolve_step.bind_group",
        &generator.expr_resolve_step_pass,
        inputs.expr_resolve_steps,
        inputs.params,
        inputs.hir_status,
        &[],
        StepNames {
            first_in: "x86_expr_resolved_node_in",
            second_in: "x86_expr_resolve_link_in",
            first_out: "x86_expr_resolved_node_out",
            second_out: "x86_expr_resolve_link_out",
        },
        StepPairs {
            first_a: inputs.expr_resolved_a,
            first_b: inputs.expr_resolved_b,
            second_a: inputs.expr_resolve_link_a,
            second_b: inputs.expr_resolve_link_b,
        },
    )?;

    Ok(FunctionDiscoveryBindGroups {
        node_tree_info,
        func,
        func_owner_scan_local,
        func_owner_scan_block,
        func_assign_nodes,
        func_assign_nodes_step,
        func_slot_flags,
        func_slot_scatter,
        expr_resolve_init,
        expr_resolve_step,
    })
}
