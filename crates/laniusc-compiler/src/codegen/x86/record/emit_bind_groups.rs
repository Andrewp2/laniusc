use anyhow::Result;

use super::{
    super::{
        GpuX86CodeGenerator,
        GpuX86ExprMetadataBuffers,
        support::{UniformBindingArray, reflected_bind_group},
    },
    bind_helpers::scan_block_groups,
    scan::final_ping_pong_scan_prefix,
};

/// Bind groups used by final x86 instruction selection, encoding, and ELF emission.
pub(super) struct EmitBindGroups {
    pub(super) select: wgpu::BindGroup,
    pub(super) inst_size: wgpu::BindGroup,
    pub(super) text_scan_local: wgpu::BindGroup,
    pub(super) text_scan_block: Vec<wgpu::BindGroup>,
    pub(super) text_offsets: wgpu::BindGroup,
    pub(super) reloc_scan_local: wgpu::BindGroup,
    pub(super) reloc_scan_block: Vec<wgpu::BindGroup>,
    pub(super) reloc_records: wgpu::BindGroup,
    pub(super) rodata_sizes: wgpu::BindGroup,
    pub(super) rodata_scan_local: wgpu::BindGroup,
    pub(super) rodata_scan_block: Vec<wgpu::BindGroup>,
    pub(super) rodata_offsets: wgpu::BindGroup,
    pub(super) rodata_dispatch_args: wgpu::BindGroup,
    pub(super) rodata_write: wgpu::BindGroup,
    pub(super) encode: wgpu::BindGroup,
    pub(super) reloc_patch: wgpu::BindGroup,
    pub(super) elf_layout: wgpu::BindGroup,
    pub(super) elf: wgpu::BindGroup,
}

/// Buffer inputs needed by final x86 emit passes.
pub(super) struct EmitBindGroupInputs<'a> {
    pub(super) params: &'a wgpu::Buffer,
    pub(super) elf_params: &'a wgpu::Buffer,
    pub(super) reloc_finalize_params: &'a wgpu::Buffer,
    pub(super) text_scan_params: &'a UniformBindingArray,
    pub(super) rodata_scan_params: &'a UniformBindingArray,
    pub(super) hir_status: &'a wgpu::Buffer,
    pub(super) expr_metadata: &'a GpuX86ExprMetadataBuffers<'a>,
    pub(super) func_meta: &'a wgpu::Buffer,
    pub(super) decl_layout_status: &'a wgpu::Buffer,
    pub(super) virtual_inst_record: &'a wgpu::Buffer,
    pub(super) virtual_inst_args: &'a wgpu::Buffer,
    pub(super) virtual_inst_status: &'a wgpu::Buffer,
    pub(super) virtual_phys_reg: &'a wgpu::Buffer,
    pub(super) virtual_call_live_reg_mask: &'a wgpu::Buffer,
    pub(super) virtual_regalloc_status: &'a wgpu::Buffer,
    pub(super) virtual_func_first_row: &'a wgpu::Buffer,
    pub(super) virtual_func_first_row_status: &'a wgpu::Buffer,
    pub(super) func_param_reg_mask: &'a wgpu::Buffer,
    pub(super) virtual_func_slot: &'a wgpu::Buffer,
    pub(super) virtual_value_def_flag: &'a wgpu::Buffer,
    pub(super) inst_kind: &'a wgpu::Buffer,
    pub(super) inst_arg0: &'a wgpu::Buffer,
    pub(super) inst_arg1: &'a wgpu::Buffer,
    pub(super) inst_arg2: &'a wgpu::Buffer,
    pub(super) inst_size: &'a wgpu::Buffer,
    pub(super) inst_byte_offset: &'a wgpu::Buffer,
    pub(super) select_status: &'a wgpu::Buffer,
    pub(super) size_status: &'a wgpu::Buffer,
    pub(super) text_scan_local_prefix: &'a wgpu::Buffer,
    pub(super) text_scan_block_sum: &'a wgpu::Buffer,
    pub(super) text_scan_prefix_a: &'a wgpu::Buffer,
    pub(super) text_scan_prefix_b: &'a wgpu::Buffer,
    pub(super) text_len: &'a wgpu::Buffer,
    pub(super) rodata_len: &'a wgpu::Buffer,
    pub(super) rodata_size_by_node: &'a wgpu::Buffer,
    pub(super) rodata_offset_by_node: &'a wgpu::Buffer,
    pub(super) rodata_status: &'a wgpu::Buffer,
    pub(super) rodata_dispatch_args: &'a wgpu::Buffer,
    pub(super) rodata_scan_local_prefix: &'a wgpu::Buffer,
    pub(super) rodata_scan_block_sum: &'a wgpu::Buffer,
    pub(super) rodata_scan_prefix_a: &'a wgpu::Buffer,
    pub(super) rodata_scan_prefix_b: &'a wgpu::Buffer,
    pub(super) text_status: &'a wgpu::Buffer,
    pub(super) reloc_count: &'a wgpu::Buffer,
    pub(super) reloc_kind: &'a wgpu::Buffer,
    pub(super) reloc_site_inst: &'a wgpu::Buffer,
    pub(super) reloc_target_inst: &'a wgpu::Buffer,
    pub(super) reloc_status: &'a wgpu::Buffer,
    pub(super) object_reloc_site_offset: &'a wgpu::Buffer,
    pub(super) object_reloc_target_offset: &'a wgpu::Buffer,
    pub(super) out: &'a wgpu::Buffer,
    pub(super) encode_status: &'a wgpu::Buffer,
    pub(super) elf_layout: &'a wgpu::Buffer,
    pub(super) layout_status: &'a wgpu::Buffer,
    pub(super) status: &'a wgpu::Buffer,
}

/// Creates bind groups for x86 final text, relocation, and ELF output passes.
pub(super) fn create_emit_bind_groups(
    generator: &GpuX86CodeGenerator,
    device: &wgpu::Device,
    inputs: EmitBindGroupInputs<'_>,
) -> Result<EmitBindGroups> {
    let EmitBindGroupInputs {
        params,
        elf_params,
        reloc_finalize_params,
        text_scan_params,
        rodata_scan_params,
        hir_status,
        expr_metadata,
        func_meta,
        decl_layout_status,
        virtual_inst_record,
        virtual_inst_args,
        virtual_inst_status,
        virtual_phys_reg,
        virtual_call_live_reg_mask,
        virtual_regalloc_status,
        virtual_func_first_row,
        virtual_func_first_row_status,
        func_param_reg_mask,
        virtual_func_slot,
        virtual_value_def_flag,
        inst_kind,
        inst_arg0,
        inst_arg1,
        inst_arg2,
        inst_size,
        inst_byte_offset,
        select_status,
        size_status,
        text_scan_local_prefix,
        text_scan_block_sum,
        text_scan_prefix_a,
        text_scan_prefix_b,
        text_len,
        rodata_len,
        rodata_size_by_node,
        rodata_offset_by_node,
        rodata_status,
        rodata_dispatch_args,
        rodata_scan_local_prefix,
        rodata_scan_block_sum,
        rodata_scan_prefix_a,
        rodata_scan_prefix_b,
        text_status,
        reloc_count,
        reloc_kind,
        reloc_site_inst,
        reloc_target_inst,
        reloc_status,
        object_reloc_site_offset,
        object_reloc_target_offset,
        out,
        encode_status,
        elf_layout,
        layout_status,
        status,
    } = inputs;

    let select = reflected_bind_group(
        device,
        Some("codegen.x86.select.bind_group"),
        &generator.select_pass,
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
            ("x86_virtual_phys_reg", virtual_phys_reg.as_entire_binding()),
            (
                "x86_virtual_call_live_reg_mask",
                virtual_call_live_reg_mask.as_entire_binding(),
            ),
            (
                "x86_virtual_regalloc_status",
                virtual_regalloc_status.as_entire_binding(),
            ),
            (
                "x86_func_first_virtual_row",
                virtual_func_first_row.as_entire_binding(),
            ),
            (
                "x86_func_first_virtual_row_status",
                virtual_func_first_row_status.as_entire_binding(),
            ),
            (
                "x86_func_param_reg_mask",
                func_param_reg_mask.as_entire_binding(),
            ),
            (
                "x86_decl_layout_status",
                decl_layout_status.as_entire_binding(),
            ),
            ("x86_func_meta", func_meta.as_entire_binding()),
            (
                "x86_virtual_func_slot",
                virtual_func_slot.as_entire_binding(),
            ),
            (
                "x86_virtual_value_def_flag",
                virtual_value_def_flag.as_entire_binding(),
            ),
            ("x86_inst_kind", inst_kind.as_entire_binding()),
            ("x86_inst_arg0", inst_arg0.as_entire_binding()),
            ("x86_inst_arg1", inst_arg1.as_entire_binding()),
            ("x86_inst_arg2", inst_arg2.as_entire_binding()),
            ("select_status", select_status.as_entire_binding()),
        ],
    )?;
    let inst_size_bind_group = reflected_bind_group(
        device,
        Some("codegen.x86.inst_size.bind_group"),
        &generator.inst_size_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("x86_inst_kind", inst_kind.as_entire_binding()),
            ("x86_inst_arg0", inst_arg0.as_entire_binding()),
            ("x86_inst_arg1", inst_arg1.as_entire_binding()),
            ("x86_inst_arg2", inst_arg2.as_entire_binding()),
            (
                "x86_decl_layout_status",
                decl_layout_status.as_entire_binding(),
            ),
            ("select_status", select_status.as_entire_binding()),
            ("x86_inst_size", inst_size.as_entire_binding()),
            ("size_status", size_status.as_entire_binding()),
        ],
    )?;
    let text_scan_local = reflected_bind_group(
        device,
        Some("codegen.x86.text_scan_local.bind_group"),
        &generator.text_scan_local_pass,
        0,
        &[
            ("gScan", text_scan_params.binding(0)),
            ("select_status", select_status.as_entire_binding()),
            ("x86_inst_size", inst_size.as_entire_binding()),
            (
                "x86_text_scan_local_prefix",
                text_scan_local_prefix.as_entire_binding(),
            ),
            (
                "x86_text_scan_block_sum",
                text_scan_block_sum.as_entire_binding(),
            ),
        ],
    )?;
    let text_scan_block = scan_block_groups(
        device,
        [
            "codegen.x86.text_scan_blocks.even.bind_group",
            "codegen.x86.text_scan_blocks.odd.bind_group",
        ],
        &generator.node_inst_scan_blocks_pass,
        text_scan_params,
        "gNodeInstBlockScan",
        "x86_node_inst_scan_block_sum",
        "x86_node_inst_scan_block_prefix_in",
        "x86_node_inst_scan_block_prefix_out",
        text_scan_block_sum,
        text_scan_prefix_a,
        text_scan_prefix_b,
    )?;
    let final_text_scan_prefix =
        final_ping_pong_scan_prefix(text_scan_params, text_scan_prefix_a, text_scan_prefix_b);
    let text_offsets = reflected_bind_group(
        device,
        Some("codegen.x86.text_offsets.bind_group"),
        &generator.text_offsets_pass,
        0,
        &[
            ("gScan", text_scan_params.binding(0)),
            ("x86_inst_size", inst_size.as_entire_binding()),
            ("size_status", size_status.as_entire_binding()),
            (
                "x86_text_scan_local_prefix",
                text_scan_local_prefix.as_entire_binding(),
            ),
            (
                "x86_text_scan_block_prefix",
                final_text_scan_prefix.as_entire_binding(),
            ),
            ("x86_inst_byte_offset", inst_byte_offset.as_entire_binding()),
            ("x86_text_len", text_len.as_entire_binding()),
            ("text_status", text_status.as_entire_binding()),
        ],
    )?;
    let reloc_scan_local = reflected_bind_group(
        device,
        Some("codegen.x86.reloc_scan_local.bind_group"),
        &generator.reloc_scan_local_pass,
        0,
        &[
            ("gScan", text_scan_params.binding(0)),
            ("select_status", select_status.as_entire_binding()),
            ("size_status", size_status.as_entire_binding()),
            ("text_status", text_status.as_entire_binding()),
            ("x86_inst_kind", inst_kind.as_entire_binding()),
            ("x86_inst_arg0", inst_arg0.as_entire_binding()),
            ("x86_inst_arg1", inst_arg1.as_entire_binding()),
            ("x86_inst_arg2", inst_arg2.as_entire_binding()),
            (
                "x86_reloc_scan_local_prefix",
                text_scan_local_prefix.as_entire_binding(),
            ),
            (
                "x86_reloc_scan_block_sum",
                text_scan_block_sum.as_entire_binding(),
            ),
        ],
    )?;
    let reloc_scan_block = scan_block_groups(
        device,
        [
            "codegen.x86.reloc_scan_blocks.even.bind_group",
            "codegen.x86.reloc_scan_blocks.odd.bind_group",
        ],
        &generator.node_inst_scan_blocks_pass,
        text_scan_params,
        "gNodeInstBlockScan",
        "x86_node_inst_scan_block_sum",
        "x86_node_inst_scan_block_prefix_in",
        "x86_node_inst_scan_block_prefix_out",
        text_scan_block_sum,
        text_scan_prefix_a,
        text_scan_prefix_b,
    )?;
    let final_reloc_scan_prefix =
        final_ping_pong_scan_prefix(text_scan_params, text_scan_prefix_a, text_scan_prefix_b);
    let reloc_records = reflected_bind_group(
        device,
        Some("codegen.x86.reloc_records.bind_group"),
        &generator.reloc_records_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("gScan", text_scan_params.binding(0)),
            ("select_status", select_status.as_entire_binding()),
            ("size_status", size_status.as_entire_binding()),
            ("text_status", text_status.as_entire_binding()),
            ("x86_inst_kind", inst_kind.as_entire_binding()),
            ("x86_inst_arg0", inst_arg0.as_entire_binding()),
            ("x86_inst_arg1", inst_arg1.as_entire_binding()),
            ("x86_inst_arg2", inst_arg2.as_entire_binding()),
            (
                "x86_reloc_scan_local_prefix",
                text_scan_local_prefix.as_entire_binding(),
            ),
            (
                "x86_reloc_scan_block_prefix",
                final_reloc_scan_prefix.as_entire_binding(),
            ),
            ("x86_reloc_count", reloc_count.as_entire_binding()),
            ("x86_reloc_kind", reloc_kind.as_entire_binding()),
            ("x86_reloc_site_inst", reloc_site_inst.as_entire_binding()),
            (
                "x86_reloc_target_inst",
                reloc_target_inst.as_entire_binding(),
            ),
            ("reloc_status", reloc_status.as_entire_binding()),
        ],
    )?;
    let rodata_sizes = reflected_bind_group(
        device,
        Some("codegen.x86.rodata_sizes.bind_group"),
        &generator.rodata_sizes_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_status", hir_status.as_entire_binding()),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "hir_string_decoded_len",
                expr_metadata.string_decoded_len.as_entire_binding(),
            ),
            (
                "x86_rodata_size_by_node",
                rodata_size_by_node.as_entire_binding(),
            ),
            ("x86_rodata_status", rodata_status.as_entire_binding()),
        ],
    )?;
    let rodata_scan_local = reflected_bind_group(
        device,
        Some("codegen.x86.rodata_scan_local.bind_group"),
        &generator.rodata_scan_local_pass,
        0,
        &[
            ("gScan", rodata_scan_params.binding(0)),
            (
                "x86_rodata_size_by_node",
                rodata_size_by_node.as_entire_binding(),
            ),
            ("x86_rodata_status", rodata_status.as_entire_binding()),
            (
                "x86_rodata_scan_local_prefix",
                rodata_scan_local_prefix.as_entire_binding(),
            ),
            (
                "x86_rodata_scan_block_sum",
                rodata_scan_block_sum.as_entire_binding(),
            ),
        ],
    )?;
    let rodata_scan_block = scan_block_groups(
        device,
        [
            "codegen.x86.rodata_scan_blocks.even.bind_group",
            "codegen.x86.rodata_scan_blocks.odd.bind_group",
        ],
        &generator.node_inst_scan_blocks_pass,
        rodata_scan_params,
        "gNodeInstBlockScan",
        "x86_node_inst_scan_block_sum",
        "x86_node_inst_scan_block_prefix_in",
        "x86_node_inst_scan_block_prefix_out",
        rodata_scan_block_sum,
        rodata_scan_prefix_a,
        rodata_scan_prefix_b,
    )?;
    let final_rodata_scan_prefix = final_ping_pong_scan_prefix(
        rodata_scan_params,
        rodata_scan_prefix_a,
        rodata_scan_prefix_b,
    );
    let rodata_offsets = reflected_bind_group(
        device,
        Some("codegen.x86.rodata_offsets.bind_group"),
        &generator.rodata_offsets_pass,
        0,
        &[
            ("gScan", rodata_scan_params.binding(0)),
            (
                "x86_rodata_size_by_node",
                rodata_size_by_node.as_entire_binding(),
            ),
            (
                "x86_rodata_scan_local_prefix",
                rodata_scan_local_prefix.as_entire_binding(),
            ),
            (
                "x86_rodata_scan_block_prefix",
                final_rodata_scan_prefix.as_entire_binding(),
            ),
            (
                "x86_rodata_offset_by_node",
                rodata_offset_by_node.as_entire_binding(),
            ),
            ("x86_rodata_len", rodata_len.as_entire_binding()),
            ("x86_rodata_status", rodata_status.as_entire_binding()),
        ],
    )?;
    let rodata_dispatch_args = reflected_bind_group(
        device,
        Some("codegen.x86.rodata_dispatch_args.bind_group"),
        &generator.rodata_dispatch_args_pass,
        0,
        &[
            (
                "hir_string_count",
                expr_metadata.string_count.as_entire_binding(),
            ),
            (
                "string_dispatch_args",
                rodata_dispatch_args.as_entire_binding(),
            ),
        ],
    )?;
    let encode = reflected_bind_group(
        device,
        Some("codegen.x86.encode.bind_group"),
        &generator.encode_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("x86_inst_kind", inst_kind.as_entire_binding()),
            ("x86_inst_arg0", inst_arg0.as_entire_binding()),
            ("x86_inst_arg1", inst_arg1.as_entire_binding()),
            ("x86_inst_arg2", inst_arg2.as_entire_binding()),
            ("x86_inst_size", inst_size.as_entire_binding()),
            ("x86_inst_byte_offset", inst_byte_offset.as_entire_binding()),
            (
                "x86_decl_layout_status",
                decl_layout_status.as_entire_binding(),
            ),
            ("x86_text_len", text_len.as_entire_binding()),
            (
                "x86_rodata_size_by_node",
                rodata_size_by_node.as_entire_binding(),
            ),
            (
                "x86_rodata_offset_by_node",
                rodata_offset_by_node.as_entire_binding(),
            ),
            ("text_status", text_status.as_entire_binding()),
            ("reloc_status", reloc_status.as_entire_binding()),
            ("out_words", out.as_entire_binding()),
            ("encode_status", encode_status.as_entire_binding()),
        ],
    )?;
    let reloc_patch = reflected_bind_group(
        device,
        Some("codegen.x86.reloc_patch.bind_group"),
        &generator.reloc_patch_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("gRelocFinalize", reloc_finalize_params.as_entire_binding()),
            ("x86_inst_kind", inst_kind.as_entire_binding()),
            ("x86_inst_arg0", inst_arg0.as_entire_binding()),
            ("x86_inst_arg1", inst_arg1.as_entire_binding()),
            ("x86_inst_arg2", inst_arg2.as_entire_binding()),
            ("x86_inst_size", inst_size.as_entire_binding()),
            ("x86_inst_byte_offset", inst_byte_offset.as_entire_binding()),
            (
                "x86_decl_layout_status",
                decl_layout_status.as_entire_binding(),
            ),
            ("x86_text_len", text_len.as_entire_binding()),
            ("x86_rodata_len", rodata_len.as_entire_binding()),
            (
                "x86_rodata_size_by_node",
                rodata_size_by_node.as_entire_binding(),
            ),
            (
                "x86_rodata_offset_by_node",
                rodata_offset_by_node.as_entire_binding(),
            ),
            ("text_status", text_status.as_entire_binding()),
            ("x86_rodata_status", rodata_status.as_entire_binding()),
            ("encode_status", encode_status.as_entire_binding()),
            ("x86_reloc_count", reloc_count.as_entire_binding()),
            ("x86_reloc_kind", reloc_kind.as_entire_binding()),
            ("x86_reloc_site_inst", reloc_site_inst.as_entire_binding()),
            (
                "x86_reloc_target_inst",
                reloc_target_inst.as_entire_binding(),
            ),
            ("out_words", out.as_entire_binding()),
            ("reloc_status", reloc_status.as_entire_binding()),
            (
                "x86_object_reloc_site_offset",
                object_reloc_site_offset.as_entire_binding(),
            ),
            (
                "x86_object_reloc_target_offset",
                object_reloc_target_offset.as_entire_binding(),
            ),
        ],
    )?;
    let elf_layout_bind_group = reflected_bind_group(
        device,
        Some("codegen.x86.elf_layout.bind_group"),
        &generator.elf_layout_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("x86_text_len", text_len.as_entire_binding()),
            ("x86_rodata_len", rodata_len.as_entire_binding()),
            ("encode_status", encode_status.as_entire_binding()),
            ("x86_elf_layout", elf_layout.as_entire_binding()),
            ("layout_status", layout_status.as_entire_binding()),
        ],
    )?;
    let elf = reflected_bind_group(
        device,
        Some("codegen.x86.elf_write.bind_group"),
        &generator.elf_write_pass,
        0,
        &[
            ("gParams", elf_params.as_entire_binding()),
            ("x86_elf_layout", elf_layout.as_entire_binding()),
            ("layout_status", layout_status.as_entire_binding()),
            ("out_words", out.as_entire_binding()),
            ("status", status.as_entire_binding()),
        ],
    )?;
    let rodata_write = reflected_bind_group(
        device,
        Some("codegen.x86.rodata_write.bind_group"),
        &generator.rodata_write_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_status", hir_status.as_entire_binding()),
            (
                "hir_string_data_offset",
                expr_metadata.string_data_offset.as_entire_binding(),
            ),
            (
                "hir_string_decoded_len",
                expr_metadata.string_decoded_len.as_entire_binding(),
            ),
            (
                "hir_string_data_words",
                expr_metadata.string_data_words.as_entire_binding(),
            ),
            (
                "hir_string_node",
                expr_metadata.string_node.as_entire_binding(),
            ),
            (
                "hir_string_count",
                expr_metadata.string_count.as_entire_binding(),
            ),
            (
                "x86_rodata_size_by_node",
                rodata_size_by_node.as_entire_binding(),
            ),
            (
                "x86_rodata_offset_by_node",
                rodata_offset_by_node.as_entire_binding(),
            ),
            ("x86_rodata_len", rodata_len.as_entire_binding()),
            ("x86_rodata_status", rodata_status.as_entire_binding()),
            ("x86_elf_layout", elf_layout.as_entire_binding()),
            ("layout_status", layout_status.as_entire_binding()),
            ("out_words", out.as_entire_binding()),
            ("status", status.as_entire_binding()),
        ],
    )?;

    Ok(EmitBindGroups {
        select,
        inst_size: inst_size_bind_group,
        text_scan_local,
        text_scan_block,
        text_offsets,
        reloc_scan_local,
        reloc_scan_block,
        reloc_records,
        rodata_sizes,
        rodata_scan_local,
        rodata_scan_block,
        rodata_offsets,
        rodata_dispatch_args,
        rodata_write,
        encode,
        reloc_patch,
        elf_layout: elf_layout_bind_group,
        elf,
    })
}
