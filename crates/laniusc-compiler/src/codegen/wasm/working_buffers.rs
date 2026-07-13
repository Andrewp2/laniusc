use super::*;

pub(super) struct WasmWorkingBuffers {
    pub params_buf: LaniusBuffer<WasmParams>,
    pub body_scan_param_bufs: Vec<LaniusBuffer<WasmScanParams>>,
    pub body_scan_blocks: u32,
    pub arg_scan_param_bufs: Vec<LaniusBuffer<WasmScanParams>>,
    pub arg_scan_blocks: u32,
    pub func_scan_param_bufs: Vec<LaniusBuffer<WasmScanParams>>,
    pub func_scan_blocks: u32,
    pub body_dispatch_buf: LaniusBuffer<u32>,
    pub module_type_dispatch_buf: LaniusBuffer<u32>,
    pub body_buf: LaniusBuffer<u32>,
    pub body_plan_buf: LaniusBuffer<u32>,
    pub wasm_func_flag_buf: LaniusBuffer<u32>,
    pub wasm_func_decl_flag_buf: LaniusBuffer<u32>,
    pub wasm_func_slot_by_token_buf: LaniusBuffer<u32>,
    pub wasm_func_token_by_slot_buf: LaniusBuffer<u32>,
    pub wasm_func_param_ordinal_by_decl_token_buf: LaniusBuffer<u32>,
    pub wasm_func_body_len_by_token_buf: LaniusBuffer<u32>,
    pub wasm_func_local_max_by_token_buf: LaniusBuffer<u32>,
    pub wasm_func_return_count_by_token_buf: LaniusBuffer<u32>,
    pub wasm_func_invalid_count_by_token_buf: LaniusBuffer<u32>,
    pub wasm_func_return_token_by_token_buf: LaniusBuffer<u32>,
    pub wasm_func_detail_by_token_buf: LaniusBuffer<u32>,
    pub wasm_func_scan_local_prefix_buf: LaniusBuffer<u32>,
    pub wasm_func_scan_block_sum_buf: LaniusBuffer<u32>,
    pub wasm_func_scan_prefix_a_buf: LaniusBuffer<u32>,
    pub wasm_func_scan_prefix_b_buf: LaniusBuffer<u32>,
    pub body_let_init_expr_by_decl_token_buf: LaniusBuffer<u32>,
    pub body_fragment_len_buf: LaniusBuffer<u32>,
    pub body_fragment_meta_buf: LaniusBuffer<u32>,
    pub body_fragment_aux_buf: LaniusBuffer<u32>,
    pub body_scan_local_prefix_buf: LaniusBuffer<u32>,
    pub body_scan_block_sum_buf: LaniusBuffer<u32>,
    pub body_scan_prefix_a_buf: LaniusBuffer<u32>,
    pub body_scan_prefix_b_buf: LaniusBuffer<u32>,
    pub wasm_agg_call_arg_count_by_fragment_buf: LaniusBuffer<u32>,
    pub wasm_agg_call_arg_count_local_prefix_buf: LaniusBuffer<u32>,
    pub wasm_agg_call_arg_count_block_sum_buf: LaniusBuffer<u32>,
    pub wasm_agg_call_arg_count_prefix_a_buf: LaniusBuffer<u32>,
    pub wasm_agg_call_arg_count_prefix_b_buf: LaniusBuffer<u32>,
    pub wasm_agg_call_arg_len_buf: LaniusBuffer<u32>,
    pub wasm_agg_call_arg_meta_buf: LaniusBuffer<u32>,
    pub wasm_agg_call_arg_aux_buf: LaniusBuffer<u32>,
    pub wasm_agg_call_arg_byte_local_prefix_buf: LaniusBuffer<u32>,
    pub wasm_agg_call_arg_byte_block_sum_buf: LaniusBuffer<u32>,
    pub wasm_agg_call_arg_byte_prefix_a_buf: LaniusBuffer<u32>,
    pub wasm_agg_call_arg_byte_prefix_b_buf: LaniusBuffer<u32>,
    pub body_status_buf: LaniusBuffer<u32>,
    pub struct_field_count_by_decl_token_buf: LaniusBuffer<u32>,
    pub struct_field_index_by_token_buf: LaniusBuffer<u32>,
    pub struct_field_decl_by_token_buf: LaniusBuffer<u32>,
    pub struct_field_name_id_buf: LaniusBuffer<u32>,
    pub struct_field_ref_tag_buf: LaniusBuffer<u32>,
    pub struct_field_ref_payload_buf: LaniusBuffer<u32>,
    pub struct_field_scalar_offset_buf: LaniusBuffer<u32>,
    pub struct_field_scalar_width_buf: LaniusBuffer<u32>,
    pub struct_init_field_index_buf: LaniusBuffer<u32>,
    pub member_result_field_index_buf: LaniusBuffer<u32>,
    pub wasm_agg_local_width_by_token_buf: LaniusBuffer<u32>,
    pub wasm_agg_local_base_by_token_buf: LaniusBuffer<u32>,
    pub wasm_agg_scan_block_sum_buf: LaniusBuffer<u32>,
    pub wasm_agg_scan_prefix_a_buf: LaniusBuffer<u32>,
    pub wasm_agg_scan_prefix_b_buf: LaniusBuffer<u32>,
    pub hir_enum_match_record_buf: LaniusBuffer<u32>,
    pub wasm_const_value_record_buf: LaniusBuffer<u32>,
    pub out_buf: LaniusBuffer<u32>,
    pub packed_out_buf: LaniusBuffer<u32>,
    pub status_buf: LaniusBuffer<u32>,
    pub out_readback: wgpu::Buffer,
    pub status_readback: wgpu::Buffer,
    pub body_plan_readback: wgpu::Buffer,
    pub body_fragment_len_readback: wgpu::Buffer,
    pub body_fragment_meta_readback: wgpu::Buffer,
    pub body_fragment_aux_readback: wgpu::Buffer,
    pub wasm_func_invalid_count_readback: wgpu::Buffer,
    pub wasm_func_detail_readback: wgpu::Buffer,
}

pub(super) fn create_wasm_working_buffers(
    device: &wgpu::Device,
    output_capacity: usize,
    token_capacity: u32,
    hir_node_capacity: u32,
) -> WasmWorkingBuffers {
    let params_buf = LaniusBuffer::new(
        (
            device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("codegen.wasm.params"),
                size: 16,
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            }),
            16,
        ),
        1,
    );
    let WasmBufferCapacities {
        body_item_capacity,
        body_scan_blocks,
        body_scan_steps,
        arg_record_capacity,
        arg_scan_blocks,
        arg_scan_steps,
        func_scan_blocks,
        func_scan_steps,
    } = WasmBufferCapacities::for_input(token_capacity, hir_node_capacity);
    let body_scan_param_bufs = create_wasm_scan_param_buffers(
        device,
        "codegen.wasm.body_scan.params",
        body_scan_steps.len(),
    );
    let arg_scan_param_bufs = create_wasm_scan_param_buffers(
        device,
        "codegen.wasm.arg_scan.params",
        arg_scan_steps.len(),
    );
    let func_scan_param_bufs = create_wasm_scan_param_buffers(
        device,
        "codegen.wasm.func_scan.params",
        func_scan_steps.len(),
    );
    let out_buf = storage_u32_rw(
        device,
        "codegen.wasm.out_words",
        output_capacity,
        wgpu::BufferUsages::COPY_SRC,
    );
    let body_dispatch_buf = storage_u32_rw(
        device,
        "codegen.wasm.body_dispatch",
        3,
        wgpu::BufferUsages::INDIRECT,
    );
    let module_type_dispatch_buf = storage_u32_rw(
        device,
        "codegen.wasm.module_type_dispatch",
        3,
        wgpu::BufferUsages::INDIRECT,
    );
    let packed_out_buf = storage_u32_rw(
        device,
        "codegen.wasm.packed_out_words",
        output_capacity.div_ceil(4),
        wgpu::BufferUsages::COPY_SRC,
    );
    let body_buf = storage_u32_rw(
        device,
        "codegen.wasm.body_words",
        output_capacity,
        wgpu::BufferUsages::empty(),
    );
    let body_plan_buf = storage_u32_rw(
        device,
        "codegen.wasm.body_plan",
        WASM_BODY_PLAN_WORDS,
        wgpu::BufferUsages::COPY_SRC,
    );
    let wasm_func_flag_buf = storage_u32_rw(
        device,
        "codegen.wasm.func_flag",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_func_decl_flag_buf = storage_u32_rw(
        device,
        "codegen.wasm.func_decl_flag",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_func_slot_by_token_buf = storage_u32_rw(
        device,
        "codegen.wasm.func_slot_by_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_func_token_by_slot_buf = storage_u32_rw(
        device,
        "codegen.wasm.func_token_by_slot",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_func_param_ordinal_by_decl_token_buf = storage_u32_rw(
        device,
        "codegen.wasm.func_param_ordinal_by_decl_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_func_body_len_by_token_buf = storage_u32_rw(
        device,
        "codegen.wasm.func_body_len_by_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_func_local_max_by_token_buf = storage_u32_rw(
        device,
        "codegen.wasm.func_local_max_by_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_func_return_count_by_token_buf = storage_u32_rw(
        device,
        "codegen.wasm.func_return_count_by_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_func_invalid_count_by_token_buf = storage_u32_rw(
        device,
        "codegen.wasm.func_invalid_count_by_token",
        token_capacity as usize,
        wgpu::BufferUsages::COPY_SRC,
    );
    let wasm_func_return_token_by_token_buf = storage_u32_rw(
        device,
        "codegen.wasm.func_return_token_by_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_func_detail_by_token_buf = storage_u32_rw(
        device,
        "codegen.wasm.func_detail_by_token",
        token_capacity as usize,
        wgpu::BufferUsages::COPY_SRC,
    );
    let wasm_func_scan_local_prefix_buf = storage_u32_rw(
        device,
        "codegen.wasm.func_scan_local_prefix",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_func_scan_block_sum_buf = storage_u32_rw(
        device,
        "codegen.wasm.func_scan_block_sum",
        func_scan_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_func_scan_prefix_a_buf = storage_u32_rw(
        device,
        "codegen.wasm.func_scan_prefix_a",
        func_scan_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_func_scan_prefix_b_buf = storage_u32_rw(
        device,
        "codegen.wasm.func_scan_prefix_b",
        func_scan_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let body_let_init_expr_by_decl_token_buf = storage_u32_rw(
        device,
        "codegen.wasm.body_let_init_expr_by_decl_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let body_fragment_len_buf = storage_u32_rw(
        device,
        "codegen.wasm.body_fragment_len",
        body_item_capacity as usize,
        wgpu::BufferUsages::COPY_SRC,
    );
    let body_fragment_meta_buf = storage_u32_rw(
        device,
        "codegen.wasm.body_fragment_meta",
        body_item_capacity as usize * 4,
        wgpu::BufferUsages::COPY_SRC,
    );
    let body_fragment_aux_buf = storage_u32_rw(
        device,
        "codegen.wasm.body_fragment_aux",
        body_item_capacity as usize * 4,
        wgpu::BufferUsages::COPY_SRC,
    );
    let body_scan_local_prefix_buf = storage_u32_rw(
        device,
        "codegen.wasm.body_scan_local_prefix",
        body_item_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let body_scan_block_sum_buf = storage_u32_rw(
        device,
        "codegen.wasm.body_scan_block_sum",
        body_scan_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let body_scan_prefix_a_buf = storage_u32_rw(
        device,
        "codegen.wasm.body_scan_prefix_a",
        body_scan_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let body_scan_prefix_b_buf = storage_u32_rw(
        device,
        "codegen.wasm.body_scan_prefix_b",
        body_scan_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_agg_call_arg_count_by_fragment_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg_call_arg.count_by_fragment",
        body_item_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_agg_call_arg_count_local_prefix_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg_call_arg.count_local_prefix",
        body_item_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_agg_call_arg_count_block_sum_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg_call_arg.count_block_sum",
        body_scan_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_agg_call_arg_count_prefix_a_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg_call_arg.count_prefix_a",
        body_scan_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_agg_call_arg_count_prefix_b_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg_call_arg.count_prefix_b",
        body_scan_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_agg_call_arg_len_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg_call_arg.len",
        arg_record_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_agg_call_arg_meta_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg_call_arg.meta",
        arg_record_capacity as usize * 4,
        wgpu::BufferUsages::empty(),
    );
    let wasm_agg_call_arg_aux_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg_call_arg.aux",
        arg_record_capacity as usize * 4,
        wgpu::BufferUsages::empty(),
    );
    let wasm_agg_call_arg_byte_local_prefix_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg_call_arg.byte_local_prefix",
        arg_record_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_agg_call_arg_byte_block_sum_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg_call_arg.byte_block_sum",
        arg_scan_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_agg_call_arg_byte_prefix_a_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg_call_arg.byte_prefix_a",
        arg_scan_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_agg_call_arg_byte_prefix_b_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg_call_arg.byte_prefix_b",
        arg_scan_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let body_status_buf = storage_u32_rw(
        device,
        "codegen.wasm.body_status",
        4,
        wgpu::BufferUsages::empty(),
    );
    let struct_field_count_by_decl_token_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg.struct_field_count_by_decl_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_field_index_by_token_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg.struct_field_index_by_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_field_decl_by_token_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg.struct_field_decl_by_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_field_name_id_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg.struct_field_name_id",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_field_ref_tag_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg.struct_field_ref_tag",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_field_ref_payload_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg.struct_field_ref_payload",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_field_scalar_offset_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg.struct_field_scalar_offset",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_field_scalar_width_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg.struct_field_scalar_width",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_init_field_index_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg.struct_init_field_index",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let member_result_field_index_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg.member_result_field_index",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_agg_local_width_by_token_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg.local_width_by_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_agg_local_base_by_token_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg.local_base_by_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_agg_scan_block_sum_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg.scan_block_sum",
        func_scan_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_agg_scan_prefix_a_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg.scan_prefix_a",
        func_scan_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let wasm_agg_scan_prefix_b_buf = storage_u32_rw(
        device,
        "codegen.wasm.agg.scan_prefix_b",
        func_scan_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_enum_match_record_buf = storage_u32_rw(
        device,
        "codegen.wasm.hir_enum_match_record",
        hir_node_capacity as usize * 4,
        wgpu::BufferUsages::empty(),
    );
    let wasm_const_value_record_buf = storage_u32_rw(
        device,
        "codegen.wasm.const_value_record",
        token_capacity as usize * 2,
        wgpu::BufferUsages::empty(),
    );
    let status_buf = storage_u32_rw(
        device,
        "codegen.wasm.status",
        4,
        wgpu::BufferUsages::COPY_SRC,
    );
    let WasmReadbackBuffers {
        out: out_readback,
        status: status_readback,
        body_plan: body_plan_readback,
        body_fragment_len: body_fragment_len_readback,
        body_fragment_aux: body_fragment_aux_readback,
        body_fragment_meta: body_fragment_meta_readback,
        func_invalid_count: wasm_func_invalid_count_readback,
        func_detail: wasm_func_detail_readback,
    } = create_wasm_readback_buffers(
        device,
        output_capacity.div_ceil(4),
        body_item_capacity,
        token_capacity,
    );
    WasmWorkingBuffers {
        params_buf,
        body_scan_param_bufs,
        body_scan_blocks,
        arg_scan_param_bufs,
        arg_scan_blocks,
        func_scan_param_bufs,
        func_scan_blocks,
        body_dispatch_buf,
        module_type_dispatch_buf,
        body_buf,
        body_plan_buf,
        wasm_func_flag_buf,
        wasm_func_decl_flag_buf,
        wasm_func_slot_by_token_buf,
        wasm_func_token_by_slot_buf,
        wasm_func_param_ordinal_by_decl_token_buf,
        wasm_func_body_len_by_token_buf,
        wasm_func_local_max_by_token_buf,
        wasm_func_return_count_by_token_buf,
        wasm_func_invalid_count_by_token_buf,
        wasm_func_return_token_by_token_buf,
        wasm_func_detail_by_token_buf,
        wasm_func_scan_local_prefix_buf,
        wasm_func_scan_block_sum_buf,
        wasm_func_scan_prefix_a_buf,
        wasm_func_scan_prefix_b_buf,
        body_let_init_expr_by_decl_token_buf,
        body_fragment_len_buf,
        body_fragment_meta_buf,
        body_fragment_aux_buf,
        body_scan_local_prefix_buf,
        body_scan_block_sum_buf,
        body_scan_prefix_a_buf,
        body_scan_prefix_b_buf,
        wasm_agg_call_arg_count_by_fragment_buf,
        wasm_agg_call_arg_count_local_prefix_buf,
        wasm_agg_call_arg_count_block_sum_buf,
        wasm_agg_call_arg_count_prefix_a_buf,
        wasm_agg_call_arg_count_prefix_b_buf,
        wasm_agg_call_arg_len_buf,
        wasm_agg_call_arg_meta_buf,
        wasm_agg_call_arg_aux_buf,
        wasm_agg_call_arg_byte_local_prefix_buf,
        wasm_agg_call_arg_byte_block_sum_buf,
        wasm_agg_call_arg_byte_prefix_a_buf,
        wasm_agg_call_arg_byte_prefix_b_buf,
        body_status_buf,
        struct_field_count_by_decl_token_buf,
        struct_field_index_by_token_buf,
        struct_field_decl_by_token_buf,
        struct_field_name_id_buf,
        struct_field_ref_tag_buf,
        struct_field_ref_payload_buf,
        struct_field_scalar_offset_buf,
        struct_field_scalar_width_buf,
        struct_init_field_index_buf,
        member_result_field_index_buf,
        wasm_agg_local_width_by_token_buf,
        wasm_agg_local_base_by_token_buf,
        wasm_agg_scan_block_sum_buf,
        wasm_agg_scan_prefix_a_buf,
        wasm_agg_scan_prefix_b_buf,
        hir_enum_match_record_buf,
        wasm_const_value_record_buf,
        out_buf,
        packed_out_buf,
        status_buf,
        out_readback,
        status_readback,
        body_plan_readback,
        body_fragment_len_readback,
        body_fragment_meta_readback,
        body_fragment_aux_readback,
        wasm_func_invalid_count_readback,
        wasm_func_detail_readback,
    }
}
