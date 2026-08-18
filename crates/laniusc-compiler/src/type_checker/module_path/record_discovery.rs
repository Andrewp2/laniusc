use super::{
    super::*,
    bind_helpers::{create_count_dispatch, create_record_flag_extract},
    buffers::Buffers,
    inputs::CreateInputs,
    layout::Layout,
};

/// Bind groups for discovering path/module/import/declaration records in HIR.
///
/// These passes mark record-family bits, extract one family at a time, scan the
/// flags, and scatter compacted row ids consumed by later module passes.
pub(in crate::type_checker) struct RecordDiscovery {
    pub(in crate::type_checker) mark_records: ComputeOperation,
    pub(in crate::type_checker) extract_module_record_flag_params:
        LaniusBuffer<RecordFamilyFlagParams>,
    pub(in crate::type_checker) extract_module_record_flag: ComputeOperation,
    pub(in crate::type_checker) extract_import_record_flag_params:
        LaniusBuffer<RecordFamilyFlagParams>,
    pub(in crate::type_checker) extract_import_record_flag: ComputeOperation,
    pub(in crate::type_checker) extract_decl_record_flag_params:
        LaniusBuffer<RecordFamilyFlagParams>,
    pub(in crate::type_checker) extract_decl_record_flag: ComputeOperation,
    pub(in crate::type_checker) scatter_paths: ComputeOperation,
    pub(in crate::type_checker) path_dispatch_params: LaniusBuffer<CountDispatchParams>,
    pub(in crate::type_checker) path_dispatch_args: ComputeOperation,
    pub(in crate::type_checker) import_dispatch_params: LaniusBuffer<CountDispatchParams>,
    pub(in crate::type_checker) import_dispatch_args: ComputeOperation,
    pub(in crate::type_checker) count_path_segments: ComputeOperation,
    pub(in crate::type_checker) scatter_path_segments: ComputeOperation,
    pub(in crate::type_checker) module_scan: PrefixScanOperation,
    pub(in crate::type_checker) import_scan: PrefixScanOperation,
    pub(in crate::type_checker) decl_scan: PrefixScanOperation,
}

/// Creates bind groups for the record-discovery portion of module/path state.
pub(in crate::type_checker) fn create_record_discovery(
    passes: &TypeCheckPasses,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    device: &wgpu::Device,
    layout: Layout,
    inputs: &CreateInputs<'_>,
    buffers: &Buffers,
    resources: &ResourceMap<'_>,
) -> Result<RecordDiscovery> {
    let mark_records = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        MODULE_RECORDS_MARK,
        inputs.hir_active_dispatch_args,
    )?;

    let (extract_module_record_flag_params, extract_module_record_flag) =
        create_record_flag_extract(
            device,
            graph,
            passes,
            MODULE_RECORD_FLAG,
            "type_check.modules.extract_module_record_flag.params",
            inputs.hir_node_capacity,
            1u32,
            &buffers.record_family_bits,
            &buffers.record_family_flag,
            inputs.hir_active_dispatch_args,
        )?;
    let (extract_import_record_flag_params, extract_import_record_flag) =
        create_record_flag_extract(
            device,
            graph,
            passes,
            IMPORT_RECORD_FLAG,
            "type_check.modules.extract_import_record_flag.params",
            inputs.hir_node_capacity,
            1u32 << 1,
            &buffers.record_family_bits,
            &buffers.record_family_flag,
            inputs.hir_active_dispatch_args,
        )?;
    let (extract_decl_record_flag_params, extract_decl_record_flag) = create_record_flag_extract(
        device,
        graph,
        passes,
        DECL_RECORD_FLAG,
        "type_check.modules.extract_decl_record_flag.params",
        inputs.hir_node_capacity,
        1u32 << 2,
        &buffers.record_family_bits,
        &buffers.record_family_flag,
        inputs.hir_active_dispatch_args,
    )?;

    let hir_work = layout.n_blocks.saturating_mul(256).max(1);
    let scatter_paths =
        ComputeOperation::direct_spec(device, graph, resources, passes, PATHS_SCATTER, hir_work)?;
    let (path_dispatch_params, path_dispatch_args) = create_count_dispatch(
        device,
        graph,
        passes,
        resources,
        PATH_DISPATCH,
        "type_check.modules.path_dispatch.params",
        layout.record_capacity_u32,
        1,
    )?;
    let (import_dispatch_params, import_dispatch_args) = create_count_dispatch(
        device,
        graph,
        passes,
        resources,
        IMPORT_DISPATCH,
        "type_check.modules.import_dispatch.params",
        layout.record_capacity_u32,
        1,
    )?;
    let count_path_segments = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        PATH_SEGMENTS_COUNT,
        &buffers.path_dispatch_args,
    )?;
    let scatter_path_segments = ComputeOperation::direct_spec(
        device,
        graph,
        resources,
        passes,
        PATH_SEGMENTS_SCATTER,
        hir_work,
    )?;
    let mut scan_resources = resources.clone();
    scan_resources.buffers([
        ("hir_active_count", inputs.hir_active_count_buf),
        ("hir_active_dispatch_args", inputs.hir_active_dispatch_args),
    ]);
    scan_resources.buffers([
        ("module_record_family_flag", &buffers.record_family_flag),
        ("module_record_prefix", &buffers.module_record_prefix),
        ("module_record_count_out", &buffers.module_count_out),
        ("import_record_count_out", &buffers.import_count_out),
        ("decl_count_out", &buffers.decl_count_out),
        (
            "module_record_scan_local_prefix",
            &buffers.record_scan_local_prefix,
        ),
        (
            "module_record_scan_block_sum",
            &buffers.record_scan_block_sum,
        ),
        ("module_record_scan_prefix_a", &buffers.record_scan_prefix_a),
        ("module_record_scan_prefix_b", &buffers.record_scan_prefix_b),
    ]);
    let module_scan = PrefixScanOperation::from_spec(
        device,
        passes,
        &scan_resources,
        compiler_graph::MODULE_RECORD_SCAN,
    )?;
    let import_scan = PrefixScanOperation::from_spec(
        device,
        passes,
        &scan_resources,
        compiler_graph::IMPORT_RECORD_SCAN,
    )?;
    let decl_scan = PrefixScanOperation::from_spec(
        device,
        passes,
        &scan_resources,
        compiler_graph::DECL_RECORD_SCAN,
    )?;

    Ok(RecordDiscovery {
        mark_records,
        extract_module_record_flag_params,
        extract_module_record_flag,
        extract_import_record_flag_params,
        extract_import_record_flag,
        extract_decl_record_flag_params,
        extract_decl_record_flag,
        scatter_paths,
        path_dispatch_params,
        path_dispatch_args,
        import_dispatch_params,
        import_dispatch_args,
        count_path_segments,
        scatter_path_segments,
        module_scan,
        import_scan,
        decl_scan,
    })
}
