use super::{
    super::*,
    bind_helpers::{create_count_dispatch, create_record_flag_extract},
    buffers::Buffers,
    inputs::CreateInputs,
    layout::Layout,
};

pub(in crate::type_checker) struct RecordDiscovery {
    pub(in crate::type_checker) mark_records: wgpu::BindGroup,
    pub(in crate::type_checker) extract_path_record_flag_params:
        LaniusBuffer<RecordFamilyFlagParams>,
    pub(in crate::type_checker) extract_path_record_flag: wgpu::BindGroup,
    pub(in crate::type_checker) extract_module_record_flag_params:
        LaniusBuffer<RecordFamilyFlagParams>,
    pub(in crate::type_checker) extract_module_record_flag: wgpu::BindGroup,
    pub(in crate::type_checker) extract_import_record_flag_params:
        LaniusBuffer<RecordFamilyFlagParams>,
    pub(in crate::type_checker) extract_import_record_flag: wgpu::BindGroup,
    pub(in crate::type_checker) extract_decl_record_flag_params:
        LaniusBuffer<RecordFamilyFlagParams>,
    pub(in crate::type_checker) extract_decl_record_flag: wgpu::BindGroup,
    pub(in crate::type_checker) path_scan: U32ScanBindGroups,
    pub(in crate::type_checker) scatter_paths: wgpu::BindGroup,
    pub(in crate::type_checker) path_dispatch_params: LaniusBuffer<CountDispatchParams>,
    pub(in crate::type_checker) path_dispatch_args: wgpu::BindGroup,
    pub(in crate::type_checker) path_segment_dispatch_params: LaniusBuffer<CountDispatchParams>,
    pub(in crate::type_checker) path_segment_dispatch_args: wgpu::BindGroup,
    pub(in crate::type_checker) import_dispatch_params: LaniusBuffer<CountDispatchParams>,
    pub(in crate::type_checker) import_dispatch_args: wgpu::BindGroup,
    pub(in crate::type_checker) count_path_segments: wgpu::BindGroup,
    pub(in crate::type_checker) path_segment_scan: U32ScanBindGroups,
    pub(in crate::type_checker) scatter_path_segments: wgpu::BindGroup,
    pub(in crate::type_checker) module_scan: U32ScanBindGroups,
    pub(in crate::type_checker) import_scan: U32ScanBindGroups,
    pub(in crate::type_checker) decl_scan: U32ScanBindGroups,
}

pub(in crate::type_checker) fn create_record_discovery(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    layout: Layout,
    inputs: &CreateInputs<'_>,
    buffers: &Buffers,
) -> Result<RecordDiscovery> {
    let mark_records = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_00_mark_records"),
        &passes.modules_mark_records,
        0,
        &[
            ("gParams", inputs.params.as_entire_binding()),
            ("hir_status", inputs.hir_status_buf.as_entire_binding()),
            ("hir_kind", inputs.hir_kind_buf.as_entire_binding()),
            (
                "hir_token_pos",
                inputs.hir_token_pos_buf.as_entire_binding(),
            ),
            (
                "hir_token_end",
                inputs.hir_token_end_buf.as_entire_binding(),
            ),
            ("hir_item_kind", inputs.hir_items.kind.as_entire_binding()),
            (
                "hir_item_name_token",
                inputs.hir_items.name_token.as_entire_binding(),
            ),
            (
                "hir_item_namespace",
                inputs.hir_items.namespace.as_entire_binding(),
            ),
            (
                "hir_item_path_start",
                inputs.hir_items.path_start.as_entire_binding(),
            ),
            (
                "hir_item_path_end",
                inputs.hir_items.path_end.as_entire_binding(),
            ),
            (
                "hir_item_import_target_kind",
                inputs.hir_items.import_target_kind.as_entire_binding(),
            ),
            (
                "record_family_bits",
                buffers.record_family_bits.as_entire_binding(),
            ),
        ],
    )?;

    let (extract_path_record_flag_params, extract_path_record_flag) = create_record_flag_extract(
        device,
        &passes.modules_extract_record_flag,
        "type_check.modules.extract_path_record_flag.params",
        "type_check_modules_00b_extract_record_flag.path",
        inputs.hir_node_capacity,
        1u32 << 3,
        &buffers.record_family_bits,
        &buffers.record_family_flag,
    )?;
    let (extract_module_record_flag_params, extract_module_record_flag) =
        create_record_flag_extract(
            device,
            &passes.modules_extract_record_flag,
            "type_check.modules.extract_module_record_flag.params",
            "type_check_modules_00b_extract_record_flag.module",
            inputs.hir_node_capacity,
            1u32,
            &buffers.record_family_bits,
            &buffers.record_family_flag,
        )?;
    let (extract_import_record_flag_params, extract_import_record_flag) =
        create_record_flag_extract(
            device,
            &passes.modules_extract_record_flag,
            "type_check.modules.extract_import_record_flag.params",
            "type_check_modules_00b_extract_record_flag.import",
            inputs.hir_node_capacity,
            1u32 << 1,
            &buffers.record_family_bits,
            &buffers.record_family_flag,
        )?;
    let (extract_decl_record_flag_params, extract_decl_record_flag) = create_record_flag_extract(
        device,
        &passes.modules_extract_record_flag,
        "type_check.modules.extract_decl_record_flag.params",
        "type_check_modules_00b_extract_record_flag.decl",
        inputs.hir_node_capacity,
        1u32 << 2,
        &buffers.record_family_bits,
        &buffers.record_family_flag,
    )?;

    let path_scan = create_counted_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.path_records",
        &buffers.scan_steps,
        inputs.hir_active_count_buf,
        &buffers.path_record_flag,
        &buffers.path_record_prefix,
        &buffers.path_count_out,
        &buffers.path_scan_local_prefix,
        &buffers.path_scan_block_sum,
        &buffers.path_scan_prefix_a,
        &buffers.path_scan_prefix_b,
    )?;

    let scatter_paths = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_01_scatter_paths"),
        &passes.modules_scatter_paths,
        0,
        &[
            ("gParams", inputs.params.as_entire_binding()),
            ("hir_status", inputs.hir_status_buf.as_entire_binding()),
            ("hir_kind", inputs.hir_kind_buf.as_entire_binding()),
            (
                "hir_token_pos",
                inputs.hir_token_pos_buf.as_entire_binding(),
            ),
            (
                "hir_token_end",
                inputs.hir_token_end_buf.as_entire_binding(),
            ),
            (
                "hir_item_path_start",
                inputs.hir_items.path_start.as_entire_binding(),
            ),
            (
                "hir_item_path_end",
                inputs.hir_items.path_end.as_entire_binding(),
            ),
            (
                "path_record_flag",
                buffers.path_record_flag.as_entire_binding(),
            ),
            (
                "record_family_bits",
                buffers.record_family_bits.as_entire_binding(),
            ),
            (
                "path_record_prefix",
                buffers.path_record_prefix.as_entire_binding(),
            ),
            ("path_start", buffers.path_start.as_entire_binding()),
            ("path_len", buffers.path_len.as_entire_binding()),
            ("path_owner_hir", buffers.path_owner_hir.as_entire_binding()),
            (
                "path_owner_token",
                buffers.path_owner_token.as_entire_binding(),
            ),
            (
                "path_id_by_owner_hir",
                buffers.path_id_by_owner_hir.as_entire_binding(),
            ),
            ("path_kind", buffers.path_kind.as_entire_binding()),
            ("path_count_out", buffers.path_count_out.as_entire_binding()),
        ],
    )?;
    let (path_dispatch_params, path_dispatch_args) = create_count_dispatch(
        device,
        &passes.count_dispatch_args,
        "type_check.modules.path_dispatch.params",
        "type_check_modules_path_dispatch_args",
        layout.record_capacity_u32,
        1,
        &buffers.path_count_out,
        &buffers.path_dispatch_args,
    )?;
    let (path_segment_dispatch_params, path_segment_dispatch_args) = create_count_dispatch(
        device,
        &passes.count_dispatch_args,
        "type_check.modules.path_segment_dispatch.params",
        "type_check_modules_path_segment_dispatch_args",
        layout.record_capacity_u32,
        PATH_SEGMENT_ROW_WIDTH as u32,
        &buffers.path_count_out,
        &buffers.path_segment_dispatch_args,
    )?;
    let (import_dispatch_params, import_dispatch_args) = create_count_dispatch(
        device,
        &passes.count_dispatch_args,
        "type_check.modules.import_dispatch.params",
        "type_check_modules_import_dispatch_args",
        layout.record_capacity_u32,
        1,
        &buffers.import_count_out,
        &buffers.import_dispatch_args,
    )?;
    let count_path_segments = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_01b_count_path_segments"),
        &passes.modules_count_path_segments,
        0,
        &[
            ("gParams", inputs.params.as_entire_binding()),
            ("token_words", inputs.token_buf.as_entire_binding()),
            ("path_count_out", buffers.path_count_out.as_entire_binding()),
            ("path_start", buffers.path_start.as_entire_binding()),
            ("path_len", buffers.path_len.as_entire_binding()),
            ("path_kind", buffers.path_kind.as_entire_binding()),
            (
                "name_id_by_token",
                inputs.name_id_by_token.as_entire_binding(),
            ),
            (
                "path_segment_count",
                buffers.path_segment_count.as_entire_binding(),
            ),
        ],
    )?;
    let path_segment_scan = create_counted_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.path_segments",
        &buffers.scan_steps,
        &buffers.path_count_out,
        &buffers.path_segment_count,
        &buffers.path_segment_base,
        &buffers.path_segment_count_out,
        &buffers.path_scan_local_prefix,
        &buffers.path_scan_block_sum,
        &buffers.path_scan_prefix_a,
        &buffers.path_scan_prefix_b,
    )?;

    let scatter_path_segments = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_01b_scatter_path_segments"),
        &passes.modules_scatter_path_segments,
        0,
        &[
            ("gParams", inputs.params.as_entire_binding()),
            ("token_words", inputs.token_buf.as_entire_binding()),
            ("path_count_out", buffers.path_count_out.as_entire_binding()),
            ("path_start", buffers.path_start.as_entire_binding()),
            ("path_len", buffers.path_len.as_entire_binding()),
            (
                "path_segment_base",
                buffers.path_segment_base.as_entire_binding(),
            ),
            (
                "path_segment_count",
                buffers.path_segment_count.as_entire_binding(),
            ),
            ("path_kind", buffers.path_kind.as_entire_binding()),
            (
                "name_id_by_token",
                inputs.name_id_by_token.as_entire_binding(),
            ),
            (
                "path_segment_name_id",
                buffers.path_segment_name_id.as_entire_binding(),
            ),
            (
                "path_segment_token",
                buffers.path_segment_token.as_entire_binding(),
            ),
        ],
    )?;
    let module_scan = create_counted_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.module_records",
        &buffers.scan_steps,
        inputs.hir_active_count_buf,
        &buffers.module_record_flag,
        &buffers.module_record_prefix,
        &buffers.module_count_out,
        &buffers.record_scan_local_prefix,
        &buffers.record_scan_block_sum,
        &buffers.record_scan_prefix_a,
        &buffers.record_scan_prefix_b,
    )?;
    let import_scan = create_counted_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.import_records",
        &buffers.scan_steps,
        inputs.hir_active_count_buf,
        &buffers.import_record_flag,
        &buffers.import_record_prefix,
        &buffers.import_count_out,
        &buffers.record_scan_local_prefix,
        &buffers.record_scan_block_sum,
        &buffers.record_scan_prefix_a,
        &buffers.record_scan_prefix_b,
    )?;
    let decl_scan = create_counted_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.decl_records",
        &buffers.scan_steps,
        inputs.hir_active_count_buf,
        &buffers.decl_record_flag,
        &buffers.decl_record_prefix,
        &buffers.decl_count_out,
        &buffers.record_scan_local_prefix,
        &buffers.record_scan_block_sum,
        &buffers.record_scan_prefix_a,
        &buffers.record_scan_prefix_b,
    )?;

    Ok(RecordDiscovery {
        mark_records,
        extract_path_record_flag_params,
        extract_path_record_flag,
        extract_module_record_flag_params,
        extract_module_record_flag,
        extract_import_record_flag_params,
        extract_import_record_flag,
        extract_decl_record_flag_params,
        extract_decl_record_flag,
        path_scan,
        scatter_paths,
        path_dispatch_params,
        path_dispatch_args,
        path_segment_dispatch_params,
        path_segment_dispatch_args,
        import_dispatch_params,
        import_dispatch_args,
        count_path_segments,
        path_segment_scan,
        scatter_path_segments,
        module_scan,
        import_scan,
        decl_scan,
    })
}
