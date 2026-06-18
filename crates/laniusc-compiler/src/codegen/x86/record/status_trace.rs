use super::super::support::readback_u32s;

/// Status buffers that can be copied into the x86 status trace readback.
pub(super) struct StatusTraceSources<'a> {
    pub(super) hir_status: &'a wgpu::Buffer,
    pub(super) hir_count: &'a wgpu::Buffer,
    pub(super) hir_plus_one: &'a wgpu::Buffer,
    pub(super) func_meta: &'a wgpu::Buffer,
    pub(super) node_tree_status: &'a wgpu::Buffer,
    pub(super) enum_record_status: &'a wgpu::Buffer,
    pub(super) struct_record_status: &'a wgpu::Buffer,
    pub(super) decl_layout_status: &'a wgpu::Buffer,
    pub(super) node_inst_count_status: &'a wgpu::Buffer,
    pub(super) node_inst_order_status: &'a wgpu::Buffer,
    pub(super) node_inst_range_status: &'a wgpu::Buffer,
    pub(super) node_inst_subtree_bounds_status: &'a wgpu::Buffer,
    pub(super) node_inst_location_status: &'a wgpu::Buffer,
    pub(super) node_inst_gen_input_status: &'a wgpu::Buffer,
    pub(super) virtual_inst_status: &'a wgpu::Buffer,
    pub(super) virtual_func_first_row_status: &'a wgpu::Buffer,
    pub(super) virtual_next_call_status: &'a wgpu::Buffer,
    pub(super) func_param_reg_mask_status: &'a wgpu::Buffer,
    pub(super) virtual_liveness_status: &'a wgpu::Buffer,
    pub(super) virtual_regalloc_status: &'a wgpu::Buffer,
    pub(super) select_status: &'a wgpu::Buffer,
    pub(super) size_status: &'a wgpu::Buffer,
    pub(super) text_status: &'a wgpu::Buffer,
    pub(super) reloc_status: &'a wgpu::Buffer,
    pub(super) encode_status: &'a wgpu::Buffer,
    pub(super) layout_status: &'a wgpu::Buffer,
    pub(super) status: &'a wgpu::Buffer,
}

/// Allocates and records a status trace readback when x86 status tracing is enabled.
pub(super) fn record_status_trace_readback(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    sources: StatusTraceSources<'_>,
) -> Option<wgpu::Buffer> {
    let entries = [
        (sources.hir_status, 6),
        (sources.hir_count, 4),
        (sources.hir_plus_one, 4),
        (sources.func_meta, 8),
        (sources.node_tree_status, 4),
        (sources.enum_record_status, 4),
        (sources.struct_record_status, 4),
        (sources.decl_layout_status, 4),
        (sources.node_inst_count_status, 4),
        (sources.node_inst_order_status, 4),
        (sources.node_inst_range_status, 4),
        (sources.node_inst_subtree_bounds_status, 4),
        (sources.node_inst_location_status, 4),
        (sources.node_inst_gen_input_status, 4),
        (sources.virtual_inst_status, 4),
        (sources.virtual_func_first_row_status, 4),
        (sources.virtual_next_call_status, 4),
        (sources.func_param_reg_mask_status, 4),
        (sources.virtual_liveness_status, 4),
        (sources.virtual_regalloc_status, 4),
        (sources.select_status, 4),
        (sources.size_status, 4),
        (sources.text_status, 4),
        (sources.reloc_status, 4),
        (sources.encode_status, 4),
        (sources.layout_status, 4),
        (sources.status, 4),
    ];
    let readback = status_trace_readback(device, &entries);
    copy_status_trace(encoder, &readback, &entries);
    readback
}

/// Allocates the status trace readback buffer when requested by environment.
pub(super) fn status_trace_readback(
    device: &wgpu::Device,
    entries: &[(&wgpu::Buffer, u64)],
) -> Option<wgpu::Buffer> {
    if std::env::var("LANIUS_X86_STATUS_TRACE").is_ok_and(|value| {
        let value = value.trim();
        matches!(value, "1" | "true" | "TRUE" | "True")
    }) {
        let word_count = entries.iter().map(|(_, words)| *words as usize).sum();
        Some(readback_u32s(
            device,
            "rb.codegen.x86.status_trace",
            word_count,
        ))
    } else {
        None
    }
}

/// Copies status trace entries into a contiguous readback buffer.
pub(super) fn copy_status_trace(
    encoder: &mut wgpu::CommandEncoder,
    readback: &Option<wgpu::Buffer>,
    entries: &[(&wgpu::Buffer, u64)],
) {
    let Some(readback) = readback else {
        return;
    };

    let mut offset = 0u64;
    for (buffer, words) in entries {
        encoder.copy_buffer_to_buffer(buffer, 0, readback, offset * 4, words * 4);
        offset += words;
    }
}
