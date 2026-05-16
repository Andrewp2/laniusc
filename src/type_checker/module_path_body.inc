{
        let n_blocks = hir_node_capacity.div_ceil(256).max(1);
    let scan_params = NameScanParams {
        n_items: hir_node_capacity,
        n_blocks,
        scan_step: 0,
    };
    let scan_steps = make_name_scan_steps(device, scan_params);
    let record_scan_steps = make_name_scan_steps(device, scan_params);

    let module_record_flag = storage_u32_rw(
        device,
        "type_check.resident.module_record_flag",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_record_flag = storage_u32_rw(
        device,
        "type_check.resident.import_record_flag",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_record_flag = storage_u32_rw(
        device,
        "type_check.resident.decl_record_flag",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_record_prefix = storage_u32_rw(
        device,
        "type_check.resident.module_record_prefix",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_record_prefix = storage_u32_rw(
        device,
        "type_check.resident.import_record_prefix",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_record_prefix = storage_u32_rw(
        device,
        "type_check.resident.decl_record_prefix",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let record_scan_local_prefix = storage_u32_rw(
        device,
        "type_check.resident.record_scan_local_prefix",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let record_scan_block_sum = storage_u32_rw(
        device,
        "type_check.resident.record_scan_block_sum",
        n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let record_scan_prefix_a = storage_u32_rw(
        device,
        "type_check.resident.record_scan_prefix_a",
        n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let record_scan_prefix_b = storage_u32_rw(
        device,
        "type_check.resident.record_scan_prefix_b",
        n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_count_out = storage_u32_rw(
        device,
        "type_check.resident.module_count_out",
        1,
        wgpu::BufferUsages::empty(),
    );
    let import_count_out = storage_u32_rw(
        device,
        "type_check.resident.import_count_out",
        1,
        wgpu::BufferUsages::empty(),
    );
    let decl_count_out = storage_u32_rw(
        device,
        "type_check.resident.decl_count_out",
        1,
        wgpu::BufferUsages::empty(),
    );
    let module_file_id = storage_u32_rw(
        device,
        "type_check.resident.module_file_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_path_id = storage_u32_rw(
        device,
        "type_check.resident.module_path_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_owner_hir = storage_u32_rw(
        device,
        "type_check.resident.module_owner_hir",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_status = storage_u32_rw(
        device,
        "type_check.resident.module_status",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_key_segment_count = storage_u32_rw(
        device,
        "type_check.resident.module_key_segment_count",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_key_segment_base = storage_u32_rw(
        device,
        "type_check.resident.module_key_segment_base",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_key_segment_capacity = (hir_node_capacity as usize)
        .max(1)
        .saturating_mul(MODULE_PATH_MAX_SEGMENTS);
    let module_key_segment_name_id = storage_u32_rw(
        device,
        "type_check.resident.module_key_segment_name_id",
        module_key_segment_capacity,
        wgpu::BufferUsages::empty(),
    );
    let module_key_to_module_id = storage_u32_rw(
        device,
        "type_check.resident.module_key_to_module_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_key_order_tmp = storage_u32_rw(
        device,
        "type_check.resident.module_key_order_tmp",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_key_radix_histogram_len = (n_blocks as usize).max(1) * NAME_RADIX_BUCKETS as usize;
    let module_key_radix_block_histogram = storage_u32_rw(
        device,
        "type_check.resident.module_key_radix_block_histogram",
        module_key_radix_histogram_len,
        wgpu::BufferUsages::empty(),
    );
    let module_key_radix_block_bucket_prefix = storage_u32_rw(
        device,
        "type_check.resident.module_key_radix_block_bucket_prefix",
        module_key_radix_histogram_len,
        wgpu::BufferUsages::empty(),
    );
    let module_key_radix_bucket_total = storage_u32_rw(
        device,
        "type_check.resident.module_key_radix_bucket_total",
        NAME_RADIX_BUCKETS as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_key_radix_bucket_base = storage_u32_rw(
        device,
        "type_check.resident.module_key_radix_bucket_base",
        NAME_RADIX_BUCKETS as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_id_by_file_id = storage_u32_rw(
        device,
        "type_check.resident.module_id_by_file_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_module_file_id = storage_u32_rw(
        device,
        "type_check.resident.import_module_file_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_path_id = storage_u32_rw(
        device,
        "type_check.resident.import_path_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_kind = storage_u32_rw(
        device,
        "type_check.resident.import_kind",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_owner_hir = storage_u32_rw(
        device,
        "type_check.resident.import_owner_hir",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_module_id = storage_u32_rw(
        device,
        "type_check.resident.import_module_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_target_module_id = storage_u32_rw(
        device,
        "type_check.resident.import_target_module_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_status = storage_u32_rw(
        device,
        "type_check.resident.import_status",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_module_file_id = storage_u32_rw(
        device,
        "type_check.resident.decl_module_file_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_module_id = storage_u32_rw(
        device,
        "type_check.resident.decl_module_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_name_id = storage_u32_rw(
        device,
        "type_check.resident.decl_name_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_name_token = storage_u32_rw(
        device,
        "type_check.resident.decl_name_token",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_kind = storage_u32_rw(
        device,
        "type_check.resident.decl_kind",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_namespace = storage_u32_rw(
        device,
        "type_check.resident.decl_namespace",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_visibility = storage_u32_rw(
        device,
        "type_check.resident.decl_visibility",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_hir_node = storage_u32_rw(
        device,
        "type_check.resident.decl_hir_node",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_parent_type_decl = storage_u32_rw(
        device,
        "type_check.resident.decl_parent_type_decl",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_token_start = storage_u32_rw(
        device,
        "type_check.resident.decl_token_start",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_token_end = storage_u32_rw(
        device,
        "type_check.resident.decl_token_end",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_key_to_decl_id = storage_u32_rw(
        device,
        "type_check.resident.decl_key_to_decl_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_key_order_tmp = storage_u32_rw(
        device,
        "type_check.resident.decl_key_order_tmp",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_key_radix_histogram_len = (n_blocks as usize).max(1) * NAME_RADIX_BUCKETS as usize;
    let decl_key_radix_block_histogram = storage_u32_rw(
        device,
        "type_check.resident.decl_key_radix_block_histogram",
        decl_key_radix_histogram_len,
        wgpu::BufferUsages::empty(),
    );
    let decl_key_radix_block_bucket_prefix = storage_u32_rw(
        device,
        "type_check.resident.decl_key_radix_block_bucket_prefix",
        decl_key_radix_histogram_len,
        wgpu::BufferUsages::empty(),
    );
    let decl_key_radix_bucket_total = storage_u32_rw(
        device,
        "type_check.resident.decl_key_radix_bucket_total",
        NAME_RADIX_BUCKETS as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_key_radix_bucket_base = storage_u32_rw(
        device,
        "type_check.resident.decl_key_radix_bucket_base",
        NAME_RADIX_BUCKETS as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_status = storage_u32_rw(
        device,
        "type_check.resident.decl_status",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_duplicate_of = storage_u32_rw(
        device,
        "type_check.resident.decl_duplicate_of",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_type_key_flag = storage_u32_rw(
        device,
        "type_check.resident.decl_type_key_flag",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_value_key_flag = storage_u32_rw(
        device,
        "type_check.resident.decl_value_key_flag",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_type_key_prefix = storage_u32_rw(
        device,
        "type_check.resident.decl_type_key_prefix",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_value_key_prefix = storage_u32_rw(
        device,
        "type_check.resident.decl_value_key_prefix",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_type_key_count_out = storage_u32_rw(
        device,
        "type_check.resident.decl_type_key_count_out",
        1,
        wgpu::BufferUsages::empty(),
    );
    let decl_value_key_count_out = storage_u32_rw(
        device,
        "type_check.resident.decl_value_key_count_out",
        1,
        wgpu::BufferUsages::empty(),
    );
    let decl_type_key_to_decl_id = storage_u32_rw(
        device,
        "type_check.resident.decl_type_key_to_decl_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_value_key_to_decl_id = storage_u32_rw(
        device,
        "type_check.resident.decl_value_key_to_decl_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_type_count = storage_u32_rw(
        device,
        "type_check.resident.import_visible_type_count",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_value_count = storage_u32_rw(
        device,
        "type_check.resident.import_visible_value_count",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_type_prefix = storage_u32_rw(
        device,
        "type_check.resident.import_visible_type_prefix",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_value_prefix = storage_u32_rw(
        device,
        "type_check.resident.import_visible_value_prefix",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_type_count_out = storage_u32_rw(
        device,
        "type_check.resident.import_visible_type_count_out",
        1,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_value_count_out = storage_u32_rw(
        device,
        "type_check.resident.import_visible_value_count_out",
        1,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_type_module_id = storage_u32_rw(
        device,
        "type_check.resident.import_visible_type_module_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_type_name_id = storage_u32_rw(
        device,
        "type_check.resident.import_visible_type_name_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_type_decl_id = storage_u32_rw(
        device,
        "type_check.resident.import_visible_type_decl_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_type_key_order = storage_u32_rw(
        device,
        "type_check.resident.import_visible_type_key_order",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_type_key_order_tmp = storage_u32_rw(
        device,
        "type_check.resident.import_visible_type_key_order_tmp",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_type_key_module_id = storage_u32_rw(
        device,
        "type_check.resident.import_visible_type_key_module_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_type_key_name_id = storage_u32_rw(
        device,
        "type_check.resident.import_visible_type_key_name_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_type_key_to_decl_id = storage_u32_rw(
        device,
        "type_check.resident.import_visible_type_key_to_decl_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_type_status = storage_u32_rw(
        device,
        "type_check.resident.import_visible_type_status",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_type_duplicate_of = storage_u32_rw(
        device,
        "type_check.resident.import_visible_type_duplicate_of",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_value_module_id = storage_u32_rw(
        device,
        "type_check.resident.import_visible_value_module_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_value_name_id = storage_u32_rw(
        device,
        "type_check.resident.import_visible_value_name_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_value_decl_id = storage_u32_rw(
        device,
        "type_check.resident.import_visible_value_decl_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_value_key_order = storage_u32_rw(
        device,
        "type_check.resident.import_visible_value_key_order",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_value_key_order_tmp = storage_u32_rw(
        device,
        "type_check.resident.import_visible_value_key_order_tmp",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_value_key_module_id = storage_u32_rw(
        device,
        "type_check.resident.import_visible_value_key_module_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_value_key_name_id = storage_u32_rw(
        device,
        "type_check.resident.import_visible_value_key_name_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_value_key_to_decl_id = storage_u32_rw(
        device,
        "type_check.resident.import_visible_value_key_to_decl_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_value_status = storage_u32_rw(
        device,
        "type_check.resident.import_visible_value_status",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_value_duplicate_of = storage_u32_rw(
        device,
        "type_check.resident.import_visible_value_duplicate_of",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_key_radix_histogram_len =
        (n_blocks as usize).max(1) * NAME_RADIX_BUCKETS as usize;
    let import_visible_key_radix_block_histogram = storage_u32_rw(
        device,
        "type_check.resident.import_visible_key_radix_block_histogram",
        import_visible_key_radix_histogram_len,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_key_radix_block_bucket_prefix = storage_u32_rw(
        device,
        "type_check.resident.import_visible_key_radix_block_bucket_prefix",
        import_visible_key_radix_histogram_len,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_key_radix_bucket_total = storage_u32_rw(
        device,
        "type_check.resident.import_visible_key_radix_bucket_total",
        NAME_RADIX_BUCKETS as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_key_radix_bucket_base = storage_u32_rw(
        device,
        "type_check.resident.import_visible_key_radix_bucket_base",
        NAME_RADIX_BUCKETS as usize,
        wgpu::BufferUsages::empty(),
    );
    let resolved_type_decl = storage_u32_rw(
        device,
        "type_check.resident.resolved_type_decl",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let resolved_value_decl = storage_u32_rw(
        device,
        "type_check.resident.resolved_value_decl",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let resolved_type_status = storage_u32_rw(
        device,
        "type_check.resident.resolved_type_status",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let resolved_value_status = storage_u32_rw(
        device,
        "type_check.resident.resolved_value_status",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let path_record_flag = storage_u32_rw(
        device,
        "type_check.resident.path_record_flag",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let path_record_kind = storage_u32_rw(
        device,
        "type_check.resident.path_record_kind",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let path_record_prefix = storage_u32_rw(
        device,
        "type_check.resident.path_record_prefix",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let path_scan_local_prefix = storage_u32_rw(
        device,
        "type_check.resident.path_scan_local_prefix",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let path_scan_block_sum = storage_u32_rw(
        device,
        "type_check.resident.path_scan_block_sum",
        n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let path_scan_prefix_a = storage_u32_rw(
        device,
        "type_check.resident.path_scan_prefix_a",
        n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let path_scan_prefix_b = storage_u32_rw(
        device,
        "type_check.resident.path_scan_prefix_b",
        n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let path_start = storage_u32_rw(
        device,
        "type_check.resident.path_start",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let path_len = storage_u32_rw(
        device,
        "type_check.resident.path_len",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let path_segment_count = storage_u32_rw(
        device,
        "type_check.resident.path_segment_count",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let path_segment_base = storage_u32_rw(
        device,
        "type_check.resident.path_segment_base",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let path_segment_capacity = (hir_node_capacity as usize)
        .max(1)
        .saturating_mul(MODULE_PATH_MAX_SEGMENTS);
    let path_segment_name_id = storage_u32_rw(
        device,
        "type_check.resident.path_segment_name_id",
        path_segment_capacity,
        wgpu::BufferUsages::empty(),
    );
    let path_segment_token = storage_u32_rw(
        device,
        "type_check.resident.path_segment_token",
        path_segment_capacity,
        wgpu::BufferUsages::empty(),
    );
    let path_owner_hir = storage_u32_rw(
        device,
        "type_check.resident.path_owner_hir",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let path_owner_token = storage_u32_rw(
        device,
        "type_check.resident.path_owner_token",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let path_owner_module_id = storage_u32_rw(
        device,
        "type_check.resident.path_owner_module_id",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let path_kind = storage_u32_rw(
        device,
        "type_check.resident.path_kind",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let path_count_out = storage_u32_rw(
        device,
        "type_check.resident.path_count_out",
        1,
        wgpu::BufferUsages::empty(),
    );

    let mark_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("hir_status".into(), hir_status_buf.as_entire_binding()),
        ("hir_kind".into(), hir_kind_buf.as_entire_binding()),
        (
            "hir_token_pos".into(),
            hir_token_pos_buf.as_entire_binding(),
        ),
        (
            "hir_token_end".into(),
            hir_token_end_buf.as_entire_binding(),
        ),
        ("hir_item_kind".into(), hir_items.kind.as_entire_binding()),
        (
            "hir_item_name_token".into(),
            hir_items.name_token.as_entire_binding(),
        ),
        (
            "hir_item_namespace".into(),
            hir_items.namespace.as_entire_binding(),
        ),
        (
            "hir_item_path_start".into(),
            hir_items.path_start.as_entire_binding(),
        ),
        (
            "hir_item_path_end".into(),
            hir_items.path_end.as_entire_binding(),
        ),
        (
            "hir_item_import_target_kind".into(),
            hir_items.import_target_kind.as_entire_binding(),
        ),
        (
            "module_record_flag".into(),
            module_record_flag.as_entire_binding(),
        ),
        (
            "import_record_flag".into(),
            import_record_flag.as_entire_binding(),
        ),
        (
            "decl_record_flag".into(),
            decl_record_flag.as_entire_binding(),
        ),
        (
            "path_record_flag".into(),
            path_record_flag.as_entire_binding(),
        ),
        (
            "path_record_kind".into(),
            path_record_kind.as_entire_binding(),
        ),
    ]);
    let mark_records = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_00_mark_records"),
        &passes.modules_mark_records.bind_group_layouts[0],
        &passes.modules_mark_records.reflection,
        0,
        &mark_resources,
    )?;

    let scan_local_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gScan".into(), scan_steps[0].params.as_entire_binding()),
        ("scan_input".into(), path_record_flag.as_entire_binding()),
        (
            "scan_local_prefix".into(),
            path_scan_local_prefix.as_entire_binding(),
        ),
        (
            "scan_block_sum".into(),
            path_scan_block_sum.as_entire_binding(),
        ),
    ]);
    let scan_local = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules.path_scan_00_local"),
        &passes.names_scan_local.bind_group_layouts[0],
        &passes.names_scan_local.reflection,
        0,
        &scan_local_resources,
    )?;

    let mut scan_blocks = Vec::with_capacity(scan_steps.len());
    for step in &scan_steps {
        let prefix_in = if step.read_from_a {
            &path_scan_prefix_a
        } else {
            &path_scan_prefix_b
        };
        let prefix_out = if step.write_to_a {
            &path_scan_prefix_a
        } else {
            &path_scan_prefix_b
        };
        let scan_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gScan".into(), step.params.as_entire_binding()),
            (
                "scan_block_sum".into(),
                path_scan_block_sum.as_entire_binding(),
            ),
            ("scan_block_prefix_in".into(), prefix_in.as_entire_binding()),
            (
                "scan_block_prefix_out".into(),
                prefix_out.as_entire_binding(),
            ),
        ]);
        scan_blocks.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_modules.path_scan_01_blocks"),
            &passes.names_scan_blocks.bind_group_layouts[0],
            &passes.names_scan_blocks.reflection,
            0,
            &scan_resources,
        )?);
    }

    let final_prefix = if scan_steps
        .last()
        .map(|step| step.write_to_a)
        .unwrap_or(true)
    {
        &path_scan_prefix_a
    } else {
        &path_scan_prefix_b
    };
    let scan_apply_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gScan".into(), scan_steps[0].params.as_entire_binding()),
        (
            "scan_local_prefix".into(),
            path_scan_local_prefix.as_entire_binding(),
        ),
        ("scan_block_prefix".into(), final_prefix.as_entire_binding()),
        (
            "scan_output_prefix".into(),
            path_record_prefix.as_entire_binding(),
        ),
        ("scan_total".into(), path_count_out.as_entire_binding()),
    ]);
    let scan_apply = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules.path_scan_02_apply"),
        &passes.names_scan_apply.bind_group_layouts[0],
        &passes.names_scan_apply.reflection,
        0,
        &scan_apply_resources,
    )?;

    let scatter_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("hir_status".into(), hir_status_buf.as_entire_binding()),
        ("hir_kind".into(), hir_kind_buf.as_entire_binding()),
        (
            "hir_token_pos".into(),
            hir_token_pos_buf.as_entire_binding(),
        ),
        (
            "hir_token_end".into(),
            hir_token_end_buf.as_entire_binding(),
        ),
        (
            "hir_item_path_start".into(),
            hir_items.path_start.as_entire_binding(),
        ),
        (
            "hir_item_path_end".into(),
            hir_items.path_end.as_entire_binding(),
        ),
        (
            "path_record_flag".into(),
            path_record_flag.as_entire_binding(),
        ),
        (
            "path_record_kind".into(),
            path_record_kind.as_entire_binding(),
        ),
        (
            "path_record_prefix".into(),
            path_record_prefix.as_entire_binding(),
        ),
        ("path_start".into(), path_start.as_entire_binding()),
        ("path_len".into(), path_len.as_entire_binding()),
        (
            "path_segment_base".into(),
            path_segment_base.as_entire_binding(),
        ),
        ("path_owner_hir".into(), path_owner_hir.as_entire_binding()),
        (
            "path_owner_token".into(),
            path_owner_token.as_entire_binding(),
        ),
        ("path_kind".into(), path_kind.as_entire_binding()),
        ("path_count_out".into(), path_count_out.as_entire_binding()),
    ]);
    let scatter_paths = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_01_scatter_paths"),
        &passes.modules_scatter_paths.bind_group_layouts[0],
        &passes.modules_scatter_paths.reflection,
        0,
        &scatter_resources,
    )?;
    let segment_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("token_words".into(), token_buf.as_entire_binding()),
        ("path_count_out".into(), path_count_out.as_entire_binding()),
        ("path_start".into(), path_start.as_entire_binding()),
        ("path_len".into(), path_len.as_entire_binding()),
        (
            "path_segment_base".into(),
            path_segment_base.as_entire_binding(),
        ),
        (
            "path_owner_token".into(),
            path_owner_token.as_entire_binding(),
        ),
        ("path_kind".into(), path_kind.as_entire_binding()),
        (
            "name_id_by_token".into(),
            name_id_by_token.as_entire_binding(),
        ),
        (
            "path_segment_count".into(),
            path_segment_count.as_entire_binding(),
        ),
        (
            "path_segment_name_id".into(),
            path_segment_name_id.as_entire_binding(),
        ),
        (
            "path_segment_token".into(),
            path_segment_token.as_entire_binding(),
        ),
    ]);
    let scatter_path_segments = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_01b_scatter_path_segments"),
        &passes.modules_scatter_path_segments.bind_group_layouts[0],
        &passes.modules_scatter_path_segments.reflection,
        0,
        &segment_resources,
    )?;
    let module_scan = create_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.module_records",
        &record_scan_steps,
        &module_record_flag,
        &module_record_prefix,
        &module_count_out,
        &record_scan_local_prefix,
        &record_scan_block_sum,
        &record_scan_prefix_a,
        &record_scan_prefix_b,
    )?;
    let import_scan = create_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.import_records",
        &record_scan_steps,
        &import_record_flag,
        &import_record_prefix,
        &import_count_out,
        &record_scan_local_prefix,
        &record_scan_block_sum,
        &record_scan_prefix_a,
        &record_scan_prefix_b,
    )?;
    let decl_scan = create_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.decl_records",
        &record_scan_steps,
        &decl_record_flag,
        &decl_record_prefix,
        &decl_count_out,
        &record_scan_local_prefix,
        &record_scan_block_sum,
        &record_scan_prefix_a,
        &record_scan_prefix_b,
    )?;

    let module_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        (
            "module_record_flag".into(),
            module_record_flag.as_entire_binding(),
        ),
        (
            "module_record_prefix".into(),
            module_record_prefix.as_entire_binding(),
        ),
        (
            "hir_item_file_id".into(),
            hir_items.file_id.as_entire_binding(),
        ),
        (
            "path_record_prefix".into(),
            path_record_prefix.as_entire_binding(),
        ),
        ("module_file_id".into(), module_file_id.as_entire_binding()),
        ("module_path_id".into(), module_path_id.as_entire_binding()),
        (
            "module_owner_hir".into(),
            module_owner_hir.as_entire_binding(),
        ),
    ]);
    let scatter_module_records = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_02_scatter_module_records"),
        &passes.modules_scatter_module_records.bind_group_layouts[0],
        &passes.modules_scatter_module_records.reflection,
        0,
        &module_resources,
    )?;

    let module_key_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        (
            "module_count_out".into(),
            module_count_out.as_entire_binding(),
        ),
        ("module_path_id".into(), module_path_id.as_entire_binding()),
        (
            "path_segment_count".into(),
            path_segment_count.as_entire_binding(),
        ),
        (
            "path_segment_base".into(),
            path_segment_base.as_entire_binding(),
        ),
        (
            "path_segment_name_id".into(),
            path_segment_name_id.as_entire_binding(),
        ),
        (
            "path_owner_token".into(),
            path_owner_token.as_entire_binding(),
        ),
        ("status".into(), status_buf.as_entire_binding()),
        ("module_status".into(), module_status.as_entire_binding()),
        (
            "module_key_segment_count".into(),
            module_key_segment_count.as_entire_binding(),
        ),
        (
            "module_key_segment_base".into(),
            module_key_segment_base.as_entire_binding(),
        ),
        (
            "module_key_segment_name_id".into(),
            module_key_segment_name_id.as_entire_binding(),
        ),
        (
            "module_key_to_module_id".into(),
            module_key_to_module_id.as_entire_binding(),
        ),
    ]);
    let build_module_keys = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_02e_build_module_keys"),
        &passes.modules_build_module_keys.bind_group_layouts[0],
        &passes.modules_build_module_keys.reflection,
        0,
        &module_key_resources,
    )?;

    let mut module_key_radix_steps = Vec::with_capacity(MODULE_KEY_RADIX_STEPS as usize);
    let mut sort_module_key_histogram = Vec::with_capacity(MODULE_KEY_RADIX_STEPS as usize);
    let mut sort_module_key_bucket_prefix = Vec::with_capacity(MODULE_KEY_RADIX_STEPS as usize);
    let mut sort_module_key_bucket_bases = Vec::with_capacity(MODULE_KEY_RADIX_STEPS as usize);
    let mut sort_module_key_scatter = Vec::with_capacity(MODULE_KEY_RADIX_STEPS as usize);
    for key_step in 0..MODULE_KEY_RADIX_STEPS {
        let step_params = uniform_from_val(
            device,
            &format!("type_check.modules.module_key_radix.params.{key_step}"),
            &ModuleKeyRadixParams {
                module_capacity: hir_node_capacity,
                reserved: 0,
                n_blocks,
                key_step,
            },
        );
        let read_order = if key_step % 2 == 0 {
            &module_key_to_module_id
        } else {
            &module_key_order_tmp
        };
        let write_order = if key_step % 2 == 0 {
            &module_key_order_tmp
        } else {
            &module_key_to_module_id
        };

        let histogram_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "module_count_out".into(),
                module_count_out.as_entire_binding(),
            ),
            (
                "module_key_segment_count".into(),
                module_key_segment_count.as_entire_binding(),
            ),
            (
                "module_key_segment_base".into(),
                module_key_segment_base.as_entire_binding(),
            ),
            (
                "module_key_segment_name_id".into(),
                module_key_segment_name_id.as_entire_binding(),
            ),
            ("module_key_order_in".into(), read_order.as_entire_binding()),
            (
                "radix_block_histogram".into(),
                module_key_radix_block_histogram.as_entire_binding(),
            ),
        ]);
        sort_module_key_histogram.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_modules_03_sort_module_keys_histogram"),
            &passes.modules_sort_module_keys_histogram.bind_group_layouts[0],
            &passes.modules_sort_module_keys_histogram.reflection,
            0,
            &histogram_resources,
        )?);

        let bucket_prefix_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "radix_block_histogram".into(),
                module_key_radix_block_histogram.as_entire_binding(),
            ),
            (
                "radix_block_bucket_prefix".into(),
                module_key_radix_block_bucket_prefix.as_entire_binding(),
            ),
            (
                "radix_bucket_total".into(),
                module_key_radix_bucket_total.as_entire_binding(),
            ),
        ]);
        sort_module_key_bucket_prefix.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_modules.module_key_radix_bucket_prefix"),
            &passes.names_radix_bucket_prefix.bind_group_layouts[0],
            &passes.names_radix_bucket_prefix.reflection,
            0,
            &bucket_prefix_resources,
        )?);

        let bucket_bases_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "radix_bucket_total".into(),
                module_key_radix_bucket_total.as_entire_binding(),
            ),
            (
                "radix_bucket_base".into(),
                module_key_radix_bucket_base.as_entire_binding(),
            ),
        ]);
        sort_module_key_bucket_bases.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_modules.module_key_radix_bucket_bases"),
            &passes.names_radix_bucket_bases.bind_group_layouts[0],
            &passes.names_radix_bucket_bases.reflection,
            0,
            &bucket_bases_resources,
        )?);

        let scatter_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "module_count_out".into(),
                module_count_out.as_entire_binding(),
            ),
            (
                "module_key_segment_count".into(),
                module_key_segment_count.as_entire_binding(),
            ),
            (
                "module_key_segment_base".into(),
                module_key_segment_base.as_entire_binding(),
            ),
            (
                "module_key_segment_name_id".into(),
                module_key_segment_name_id.as_entire_binding(),
            ),
            ("module_key_order_in".into(), read_order.as_entire_binding()),
            (
                "radix_bucket_base".into(),
                module_key_radix_bucket_base.as_entire_binding(),
            ),
            (
                "radix_block_bucket_prefix".into(),
                module_key_radix_block_bucket_prefix.as_entire_binding(),
            ),
            (
                "module_key_order_out".into(),
                write_order.as_entire_binding(),
            ),
        ]);
        sort_module_key_scatter.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_modules_03b_sort_module_keys_scatter"),
            &passes.modules_sort_module_keys_scatter.bind_group_layouts[0],
            &passes.modules_sort_module_keys_scatter.reflection,
            0,
            &scatter_resources,
        )?);

        drop(histogram_resources);
        drop(bucket_prefix_resources);
        drop(bucket_bases_resources);
        drop(scatter_resources);
        module_key_radix_steps.push(ModuleKeyRadixStep {
            _params: step_params,
        });
    }

    let validate_module_params = uniform_from_val(
        device,
        "type_check.modules.module_key_radix.params.validate",
        &ModuleKeyRadixParams {
            module_capacity: hir_node_capacity,
            reserved: 0,
            n_blocks,
            key_step: 0,
        },
    );
    let validate_module_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), validate_module_params.as_entire_binding()),
        (
            "module_count_out".into(),
            module_count_out.as_entire_binding(),
        ),
        (
            "sorted_module_key_order".into(),
            module_key_to_module_id.as_entire_binding(),
        ),
        (
            "module_key_segment_count".into(),
            module_key_segment_count.as_entire_binding(),
        ),
        (
            "module_key_segment_base".into(),
            module_key_segment_base.as_entire_binding(),
        ),
        (
            "module_key_segment_name_id".into(),
            module_key_segment_name_id.as_entire_binding(),
        ),
        ("module_path_id".into(), module_path_id.as_entire_binding()),
        (
            "path_owner_token".into(),
            path_owner_token.as_entire_binding(),
        ),
        ("status".into(), status_buf.as_entire_binding()),
        ("module_status".into(), module_status.as_entire_binding()),
    ]);
    let validate_modules = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_04_validate_modules"),
        &passes.modules_validate_modules.bind_group_layouts[0],
        &passes.modules_validate_modules.reflection,
        0,
        &validate_module_resources,
    )?;
    drop(validate_module_resources);
    module_key_radix_steps.push(ModuleKeyRadixStep {
        _params: validate_module_params,
    });

    let import_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        (
            "import_record_flag".into(),
            import_record_flag.as_entire_binding(),
        ),
        (
            "import_record_prefix".into(),
            import_record_prefix.as_entire_binding(),
        ),
        (
            "hir_item_file_id".into(),
            hir_items.file_id.as_entire_binding(),
        ),
        (
            "hir_item_import_target_kind".into(),
            hir_items.import_target_kind.as_entire_binding(),
        ),
        (
            "path_record_prefix".into(),
            path_record_prefix.as_entire_binding(),
        ),
        (
            "import_module_file_id".into(),
            import_module_file_id.as_entire_binding(),
        ),
        ("import_path_id".into(), import_path_id.as_entire_binding()),
        ("import_kind".into(), import_kind.as_entire_binding()),
        (
            "import_owner_hir".into(),
            import_owner_hir.as_entire_binding(),
        ),
    ]);
    let scatter_import_records = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_02b_scatter_import_records"),
        &passes.modules_scatter_import_records.bind_group_layouts[0],
        &passes.modules_scatter_import_records.reflection,
        0,
        &import_resources,
    )?;

        let resolve_import_params = uniform_from_val(
        device,
        "type_check.modules.resolve_imports.params",
        &ModuleKeyRadixParams {
            module_capacity: hir_node_capacity,
            reserved: 0,
            n_blocks,
            key_step: 0,
        },
    );
    let resolve_import_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), resolve_import_params.as_entire_binding()),
        (
            "import_count_out".into(),
            import_count_out.as_entire_binding(),
        ),
        ("import_kind".into(), import_kind.as_entire_binding()),
        ("import_path_id".into(), import_path_id.as_entire_binding()),
        (
            "path_segment_count".into(),
            path_segment_count.as_entire_binding(),
        ),
        (
            "path_segment_base".into(),
            path_segment_base.as_entire_binding(),
        ),
        (
            "path_segment_name_id".into(),
            path_segment_name_id.as_entire_binding(),
        ),
        (
            "path_owner_token".into(),
            path_owner_token.as_entire_binding(),
        ),
        (
            "module_count_out".into(),
            module_count_out.as_entire_binding(),
        ),
        (
            "sorted_module_key_order".into(),
            module_key_to_module_id.as_entire_binding(),
        ),
        (
            "module_key_segment_count".into(),
            module_key_segment_count.as_entire_binding(),
        ),
        (
            "module_key_segment_base".into(),
            module_key_segment_base.as_entire_binding(),
        ),
        (
            "module_key_segment_name_id".into(),
            module_key_segment_name_id.as_entire_binding(),
        ),
        ("status".into(), status_buf.as_entire_binding()),
        (
            "import_target_module_id".into(),
            import_target_module_id.as_entire_binding(),
        ),
        ("import_status".into(), import_status.as_entire_binding()),
    ]);
    let resolve_imports = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_05_resolve_imports"),
        &passes.modules_resolve_imports.bind_group_layouts[0],
        &passes.modules_resolve_imports.reflection,
        0,
        &resolve_import_resources,
    )?;
    drop(resolve_import_resources);
    module_key_radix_steps.push(ModuleKeyRadixStep {
        _params: resolve_import_params,
    });

    let decl_module_params = uniform_from_val(
        device,
        "type_check.modules.decl_module.params",
        &ModuleKeyRadixParams {
            module_capacity: hir_node_capacity,
            reserved: 0,
            n_blocks,
            key_step: 0,
        },
    );
    let clear_file_module_map_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            ("gParams".into(), decl_module_params.as_entire_binding()),
            ("decl_count_out".into(), decl_count_out.as_entire_binding()),
            (
                "import_count_out".into(),
                import_count_out.as_entire_binding(),
            ),
            ("path_count_out".into(), path_count_out.as_entire_binding()),
            (
                "module_id_by_file_id".into(),
                module_id_by_file_id.as_entire_binding(),
            ),
            ("decl_module_id".into(), decl_module_id.as_entire_binding()),
            (
                "import_module_id".into(),
                import_module_id.as_entire_binding(),
            ),
            (
                "path_owner_module_id".into(),
                path_owner_module_id.as_entire_binding(),
            ),
        ]);
    let clear_file_module_map = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_05b_clear_file_module_map"),
        &passes.modules_clear_file_module_map.bind_group_layouts[0],
        &passes.modules_clear_file_module_map.reflection,
        0,
        &clear_file_module_map_resources,
    )?;

    let build_file_module_map_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            ("gParams".into(), decl_module_params.as_entire_binding()),
            (
                "module_count_out".into(),
                module_count_out.as_entire_binding(),
            ),
            ("module_file_id".into(), module_file_id.as_entire_binding()),
            ("module_status".into(), module_status.as_entire_binding()),
            (
                "module_id_by_file_id".into(),
                module_id_by_file_id.as_entire_binding(),
            ),
        ]);
    let build_file_module_map = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_05c_build_file_module_map"),
        &passes.modules_build_file_module_map.bind_group_layouts[0],
        &passes.modules_build_file_module_map.reflection,
        0,
        &build_file_module_map_resources,
    )?;

    let attach_record_modules_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            ("gParams".into(), decl_module_params.as_entire_binding()),
            ("decl_count_out".into(), decl_count_out.as_entire_binding()),
            (
                "decl_module_file_id".into(),
                decl_module_file_id.as_entire_binding(),
            ),
            (
                "import_count_out".into(),
                import_count_out.as_entire_binding(),
            ),
            (
                "import_module_file_id".into(),
                import_module_file_id.as_entire_binding(),
            ),
            ("path_count_out".into(), path_count_out.as_entire_binding()),
            ("path_owner_hir".into(), path_owner_hir.as_entire_binding()),
            (
                "hir_item_file_id".into(),
                hir_items.file_id.as_entire_binding(),
            ),
            (
                "module_id_by_file_id".into(),
                module_id_by_file_id.as_entire_binding(),
            ),
            ("decl_module_id".into(), decl_module_id.as_entire_binding()),
            (
                "import_module_id".into(),
                import_module_id.as_entire_binding(),
            ),
            (
                "path_owner_module_id".into(),
                path_owner_module_id.as_entire_binding(),
            ),
        ]);
    let attach_record_modules = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_05d_attach_record_modules"),
        &passes.modules_attach_record_modules.bind_group_layouts[0],
        &passes.modules_attach_record_modules.reflection,
        0,
        &attach_record_modules_resources,
    )?;

    let seed_decl_key_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), decl_module_params.as_entire_binding()),
        ("decl_count_out".into(), decl_count_out.as_entire_binding()),
        (
            "decl_key_to_decl_id".into(),
            decl_key_to_decl_id.as_entire_binding(),
        ),
        ("decl_status".into(), decl_status.as_entire_binding()),
        (
            "decl_duplicate_of".into(),
            decl_duplicate_of.as_entire_binding(),
        ),
    ]);
    let seed_decl_key_order = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_06a_seed_decl_key_order"),
        &passes.modules_seed_decl_key_order.bind_group_layouts[0],
        &passes.modules_seed_decl_key_order.reflection,
        0,
        &seed_decl_key_resources,
    )?;

    let mut sort_decl_key_histogram = Vec::with_capacity(DECL_KEY_RADIX_STEPS as usize);
    let mut sort_decl_key_bucket_prefix = Vec::with_capacity(DECL_KEY_RADIX_STEPS as usize);
    let mut sort_decl_key_bucket_bases = Vec::with_capacity(DECL_KEY_RADIX_STEPS as usize);
    let mut sort_decl_key_scatter = Vec::with_capacity(DECL_KEY_RADIX_STEPS as usize);
    for key_step in 0..DECL_KEY_RADIX_STEPS {
        let step_params = uniform_from_val(
            device,
            &format!("type_check.modules.decl_key_radix.params.{key_step}"),
            &ModuleKeyRadixParams {
                module_capacity: hir_node_capacity,
                reserved: 0,
                n_blocks,
                key_step,
            },
        );
        let read_order = if key_step % 2 == 0 {
            &decl_key_to_decl_id
        } else {
            &decl_key_order_tmp
        };
        let write_order = if key_step % 2 == 0 {
            &decl_key_order_tmp
        } else {
            &decl_key_to_decl_id
        };

        let histogram_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            ("decl_count_out".into(), decl_count_out.as_entire_binding()),
            ("decl_module_id".into(), decl_module_id.as_entire_binding()),
            ("decl_namespace".into(), decl_namespace.as_entire_binding()),
            ("decl_name_id".into(), decl_name_id.as_entire_binding()),
            ("decl_key_order_in".into(), read_order.as_entire_binding()),
            (
                "radix_block_histogram".into(),
                decl_key_radix_block_histogram.as_entire_binding(),
            ),
        ]);
        sort_decl_key_histogram.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_modules_06_sort_decl_keys"),
            &passes.modules_sort_decl_keys.bind_group_layouts[0],
            &passes.modules_sort_decl_keys.reflection,
            0,
            &histogram_resources,
        )?);

        let bucket_prefix_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "radix_block_histogram".into(),
                decl_key_radix_block_histogram.as_entire_binding(),
            ),
            (
                "radix_block_bucket_prefix".into(),
                decl_key_radix_block_bucket_prefix.as_entire_binding(),
            ),
            (
                "radix_bucket_total".into(),
                decl_key_radix_bucket_total.as_entire_binding(),
            ),
        ]);
        sort_decl_key_bucket_prefix.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_modules.decl_key_radix_bucket_prefix"),
            &passes.names_radix_bucket_prefix.bind_group_layouts[0],
            &passes.names_radix_bucket_prefix.reflection,
            0,
            &bucket_prefix_resources,
        )?);

        let bucket_bases_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "radix_bucket_total".into(),
                decl_key_radix_bucket_total.as_entire_binding(),
            ),
            (
                "radix_bucket_base".into(),
                decl_key_radix_bucket_base.as_entire_binding(),
            ),
        ]);
        sort_decl_key_bucket_bases.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_modules.decl_key_radix_bucket_bases"),
            &passes.names_radix_bucket_bases.bind_group_layouts[0],
            &passes.names_radix_bucket_bases.reflection,
            0,
            &bucket_bases_resources,
        )?);

        let scatter_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            ("decl_count_out".into(), decl_count_out.as_entire_binding()),
            ("decl_module_id".into(), decl_module_id.as_entire_binding()),
            ("decl_namespace".into(), decl_namespace.as_entire_binding()),
            ("decl_name_id".into(), decl_name_id.as_entire_binding()),
            ("decl_key_order_in".into(), read_order.as_entire_binding()),
            (
                "radix_bucket_base".into(),
                decl_key_radix_bucket_base.as_entire_binding(),
            ),
            (
                "radix_block_bucket_prefix".into(),
                decl_key_radix_block_bucket_prefix.as_entire_binding(),
            ),
            ("decl_key_order_out".into(), write_order.as_entire_binding()),
        ]);
        sort_decl_key_scatter.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_modules_06b_sort_decl_keys_scatter"),
            &passes.modules_sort_decl_keys_scatter.bind_group_layouts[0],
            &passes.modules_sort_decl_keys_scatter.reflection,
            0,
            &scatter_resources,
        )?);

        drop(histogram_resources);
        drop(bucket_prefix_resources);
        drop(bucket_bases_resources);
        drop(scatter_resources);
        module_key_radix_steps.push(ModuleKeyRadixStep {
            _params: step_params,
        });
    }

    let validate_decl_params = uniform_from_val(
        device,
        "type_check.modules.decl_key_radix.params.validate",
        &ModuleKeyRadixParams {
            module_capacity: hir_node_capacity,
            reserved: 0,
            n_blocks,
            key_step: 0,
        },
    );
    let validate_decl_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), validate_decl_params.as_entire_binding()),
        ("decl_count_out".into(), decl_count_out.as_entire_binding()),
        (
            "module_count_out".into(),
            module_count_out.as_entire_binding(),
        ),
        (
            "sorted_decl_key_order".into(),
            decl_key_to_decl_id.as_entire_binding(),
        ),
        ("decl_module_id".into(), decl_module_id.as_entire_binding()),
        ("decl_namespace".into(), decl_namespace.as_entire_binding()),
        ("decl_name_id".into(), decl_name_id.as_entire_binding()),
        ("decl_token_start".into(), decl_token_start.as_entire_binding()),
        ("decl_status".into(), decl_status.as_entire_binding()),
        (
            "decl_duplicate_of".into(),
            decl_duplicate_of.as_entire_binding(),
        ),
        ("status".into(), status_buf.as_entire_binding()),
    ]);
    let validate_decls = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_07_validate_decls"),
        &passes.modules_validate_decls.bind_group_layouts[0],
        &passes.modules_validate_decls.reflection,
        0,
        &validate_decl_resources,
    )?;

    let mark_decl_namespace_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            ("gParams".into(), validate_decl_params.as_entire_binding()),
            ("decl_count_out".into(), decl_count_out.as_entire_binding()),
            (
                "sorted_decl_key_order".into(),
                decl_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_namespace".into(), decl_namespace.as_entire_binding()),
            ("decl_status".into(), decl_status.as_entire_binding()),
            (
                "decl_type_key_flag".into(),
                decl_type_key_flag.as_entire_binding(),
            ),
            (
                "decl_value_key_flag".into(),
                decl_value_key_flag.as_entire_binding(),
            ),
        ]);
    let mark_decl_namespace_keys = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_08_mark_decl_namespace_keys"),
        &passes.modules_mark_decl_namespace_keys.bind_group_layouts[0],
        &passes.modules_mark_decl_namespace_keys.reflection,
        0,
        &mark_decl_namespace_resources,
    )?;

    let decl_type_key_scan = create_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.decl_type_keys",
        &record_scan_steps,
        &decl_type_key_flag,
        &decl_type_key_prefix,
        &decl_type_key_count_out,
        &record_scan_local_prefix,
        &record_scan_block_sum,
        &record_scan_prefix_a,
        &record_scan_prefix_b,
    )?;
    let decl_value_key_scan = create_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.decl_value_keys",
        &record_scan_steps,
        &decl_value_key_flag,
        &decl_value_key_prefix,
        &decl_value_key_count_out,
        &record_scan_local_prefix,
        &record_scan_block_sum,
        &record_scan_prefix_a,
        &record_scan_prefix_b,
    )?;

    let scatter_decl_namespace_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            ("gParams".into(), validate_decl_params.as_entire_binding()),
            ("decl_count_out".into(), decl_count_out.as_entire_binding()),
            (
                "sorted_decl_key_order".into(),
                decl_key_to_decl_id.as_entire_binding(),
            ),
            (
                "decl_type_key_flag".into(),
                decl_type_key_flag.as_entire_binding(),
            ),
            (
                "decl_type_key_prefix".into(),
                decl_type_key_prefix.as_entire_binding(),
            ),
            (
                "decl_value_key_flag".into(),
                decl_value_key_flag.as_entire_binding(),
            ),
            (
                "decl_value_key_prefix".into(),
                decl_value_key_prefix.as_entire_binding(),
            ),
            (
                "decl_type_key_to_decl_id".into(),
                decl_type_key_to_decl_id.as_entire_binding(),
            ),
            (
                "decl_value_key_to_decl_id".into(),
                decl_value_key_to_decl_id.as_entire_binding(),
            ),
        ]);
    let scatter_decl_namespace_keys = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_08b_scatter_decl_namespace_keys"),
        &passes
            .modules_scatter_decl_namespace_keys
            .bind_group_layouts[0],
        &passes.modules_scatter_decl_namespace_keys.reflection,
        0,
        &scatter_decl_namespace_resources,
    )?;

    let import_visibility_params = uniform_from_val(
        device,
        "type_check.modules.import_visibility.params",
        &ModuleKeyRadixParams {
            module_capacity: hir_node_capacity,
            reserved: 0,
            n_blocks,
            key_step: 0,
        },
    );
    let count_import_visibility_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            (
                "gParams".into(),
                import_visibility_params.as_entire_binding(),
            ),
            (
                "import_count_out".into(),
                import_count_out.as_entire_binding(),
            ),
            ("import_status".into(), import_status.as_entire_binding()),
            (
                "import_module_id".into(),
                import_module_id.as_entire_binding(),
            ),
            (
                "import_target_module_id".into(),
                import_target_module_id.as_entire_binding(),
            ),
            (
                "decl_type_key_count_out".into(),
                decl_type_key_count_out.as_entire_binding(),
            ),
            (
                "decl_value_key_count_out".into(),
                decl_value_key_count_out.as_entire_binding(),
            ),
            (
                "decl_type_key_to_decl_id".into(),
                decl_type_key_to_decl_id.as_entire_binding(),
            ),
            (
                "decl_value_key_to_decl_id".into(),
                decl_value_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_module_id".into(), decl_module_id.as_entire_binding()),
            (
                "decl_visibility".into(),
                decl_visibility.as_entire_binding(),
            ),
            (
                "import_visible_type_count".into(),
                import_visible_type_count.as_entire_binding(),
            ),
            (
                "import_visible_value_count".into(),
                import_visible_value_count.as_entire_binding(),
            ),
        ]);
    let count_import_visibility = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_09_count_import_visibility"),
        &passes.modules_count_import_visibility.bind_group_layouts[0],
        &passes.modules_count_import_visibility.reflection,
        0,
        &count_import_visibility_resources,
    )?;

    let import_visible_type_scan = create_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.import_visible_type",
        &record_scan_steps,
        &import_visible_type_count,
        &import_visible_type_prefix,
        &import_visible_type_count_out,
        &record_scan_local_prefix,
        &record_scan_block_sum,
        &record_scan_prefix_a,
        &record_scan_prefix_b,
    )?;
    let import_visible_value_scan = create_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.import_visible_value",
        &record_scan_steps,
        &import_visible_value_count,
        &import_visible_value_prefix,
        &import_visible_value_count_out,
        &record_scan_local_prefix,
        &record_scan_block_sum,
        &record_scan_prefix_a,
        &record_scan_prefix_b,
    )?;

    let scatter_import_visible_type_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            (
                "gParams".into(),
                import_visibility_params.as_entire_binding(),
            ),
            (
                "import_count_out".into(),
                import_count_out.as_entire_binding(),
            ),
            ("import_status".into(), import_status.as_entire_binding()),
            (
                "import_module_id".into(),
                import_module_id.as_entire_binding(),
            ),
            (
                "import_target_module_id".into(),
                import_target_module_id.as_entire_binding(),
            ),
            (
                "import_visible_prefix".into(),
                import_visible_type_prefix.as_entire_binding(),
            ),
            (
                "decl_key_count_out".into(),
                decl_type_key_count_out.as_entire_binding(),
            ),
            (
                "decl_key_to_decl_id".into(),
                decl_type_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_module_id".into(), decl_module_id.as_entire_binding()),
            ("decl_name_id".into(), decl_name_id.as_entire_binding()),
            (
                "decl_visibility".into(),
                decl_visibility.as_entire_binding(),
            ),
            ("status".into(), status_buf.as_entire_binding()),
            (
                "import_visible_module_id".into(),
                import_visible_type_module_id.as_entire_binding(),
            ),
            (
                "import_visible_name_id".into(),
                import_visible_type_name_id.as_entire_binding(),
            ),
            (
                "import_visible_decl_id".into(),
                import_visible_type_decl_id.as_entire_binding(),
            ),
            (
                "import_visible_key_order".into(),
                import_visible_type_key_order.as_entire_binding(),
            ),
        ]);
    let scatter_import_visible_type = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_09b_scatter_import_visibility.type"),
        &passes.modules_scatter_import_visibility.bind_group_layouts[0],
        &passes.modules_scatter_import_visibility.reflection,
        0,
        &scatter_import_visible_type_resources,
    )?;

    let scatter_import_visible_value_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            (
                "gParams".into(),
                import_visibility_params.as_entire_binding(),
            ),
            (
                "import_count_out".into(),
                import_count_out.as_entire_binding(),
            ),
            ("import_status".into(), import_status.as_entire_binding()),
            (
                "import_module_id".into(),
                import_module_id.as_entire_binding(),
            ),
            (
                "import_target_module_id".into(),
                import_target_module_id.as_entire_binding(),
            ),
            (
                "import_visible_prefix".into(),
                import_visible_value_prefix.as_entire_binding(),
            ),
            (
                "decl_key_count_out".into(),
                decl_value_key_count_out.as_entire_binding(),
            ),
            (
                "decl_key_to_decl_id".into(),
                decl_value_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_module_id".into(), decl_module_id.as_entire_binding()),
            ("decl_name_id".into(), decl_name_id.as_entire_binding()),
            (
                "decl_visibility".into(),
                decl_visibility.as_entire_binding(),
            ),
            ("status".into(), status_buf.as_entire_binding()),
            (
                "import_visible_module_id".into(),
                import_visible_value_module_id.as_entire_binding(),
            ),
            (
                "import_visible_name_id".into(),
                import_visible_value_name_id.as_entire_binding(),
            ),
            (
                "import_visible_decl_id".into(),
                import_visible_value_decl_id.as_entire_binding(),
            ),
            (
                "import_visible_key_order".into(),
                import_visible_value_key_order.as_entire_binding(),
            ),
        ]);
    let scatter_import_visible_value = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_09b_scatter_import_visibility.value"),
        &passes.modules_scatter_import_visibility.bind_group_layouts[0],
        &passes.modules_scatter_import_visibility.reflection,
        0,
        &scatter_import_visible_value_resources,
    )?;

    let mut sort_import_visible_type_key_histogram =
        Vec::with_capacity(IMPORT_VISIBLE_KEY_RADIX_STEPS as usize);
    let mut sort_import_visible_type_key_bucket_prefix =
        Vec::with_capacity(IMPORT_VISIBLE_KEY_RADIX_STEPS as usize);
    let mut sort_import_visible_type_key_bucket_bases =
        Vec::with_capacity(IMPORT_VISIBLE_KEY_RADIX_STEPS as usize);
    let mut sort_import_visible_type_key_scatter =
        Vec::with_capacity(IMPORT_VISIBLE_KEY_RADIX_STEPS as usize);
    for key_step in 0..IMPORT_VISIBLE_KEY_RADIX_STEPS {
        let step_params = uniform_from_val(
            device,
            &format!("type_check.modules.import_visible_type_radix.params.{key_step}"),
            &ModuleKeyRadixParams {
                module_capacity: hir_node_capacity,
                reserved: 0,
                n_blocks,
                key_step,
            },
        );
        let read_order = if key_step % 2 == 0 {
            &import_visible_type_key_order
        } else {
            &import_visible_type_key_order_tmp
        };
        let write_order = if key_step % 2 == 0 {
            &import_visible_type_key_order_tmp
        } else {
            &import_visible_type_key_order
        };
        let histogram_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "import_visible_count_out".into(),
                import_visible_type_count_out.as_entire_binding(),
            ),
            (
                "import_visible_module_id".into(),
                import_visible_type_module_id.as_entire_binding(),
            ),
            (
                "import_visible_name_id".into(),
                import_visible_type_name_id.as_entire_binding(),
            ),
            (
                "import_visible_key_order_in".into(),
                read_order.as_entire_binding(),
            ),
            (
                "radix_block_histogram".into(),
                import_visible_key_radix_block_histogram.as_entire_binding(),
            ),
        ]);
        sort_import_visible_type_key_histogram.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_modules_09c_sort_import_visible_keys"),
            &passes.modules_sort_import_visible_keys.bind_group_layouts[0],
            &passes.modules_sort_import_visible_keys.reflection,
            0,
            &histogram_resources,
        )?);
        let bucket_prefix_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "radix_block_histogram".into(),
                import_visible_key_radix_block_histogram.as_entire_binding(),
            ),
            (
                "radix_block_bucket_prefix".into(),
                import_visible_key_radix_block_bucket_prefix.as_entire_binding(),
            ),
            (
                "radix_bucket_total".into(),
                import_visible_key_radix_bucket_total.as_entire_binding(),
            ),
        ]);
        sort_import_visible_type_key_bucket_prefix.push(
            bind_group::create_bind_group_from_reflection(
                device,
                Some("type_check_modules.import_visible_type_bucket_prefix"),
                &passes.names_radix_bucket_prefix.bind_group_layouts[0],
                &passes.names_radix_bucket_prefix.reflection,
                0,
                &bucket_prefix_resources,
            )?,
        );
        let bucket_bases_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "radix_bucket_total".into(),
                import_visible_key_radix_bucket_total.as_entire_binding(),
            ),
            (
                "radix_bucket_base".into(),
                import_visible_key_radix_bucket_base.as_entire_binding(),
            ),
        ]);
        sort_import_visible_type_key_bucket_bases.push(
            bind_group::create_bind_group_from_reflection(
                device,
                Some("type_check_modules.import_visible_type_bucket_bases"),
                &passes.names_radix_bucket_bases.bind_group_layouts[0],
                &passes.names_radix_bucket_bases.reflection,
                0,
                &bucket_bases_resources,
            )?,
        );
        let scatter_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "import_visible_count_out".into(),
                import_visible_type_count_out.as_entire_binding(),
            ),
            (
                "import_visible_module_id".into(),
                import_visible_type_module_id.as_entire_binding(),
            ),
            (
                "import_visible_name_id".into(),
                import_visible_type_name_id.as_entire_binding(),
            ),
            (
                "import_visible_key_order_in".into(),
                read_order.as_entire_binding(),
            ),
            (
                "radix_bucket_base".into(),
                import_visible_key_radix_bucket_base.as_entire_binding(),
            ),
            (
                "radix_block_bucket_prefix".into(),
                import_visible_key_radix_block_bucket_prefix.as_entire_binding(),
            ),
            (
                "import_visible_key_order_out".into(),
                write_order.as_entire_binding(),
            ),
        ]);
        sort_import_visible_type_key_scatter.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_modules_09d_sort_import_visible_keys_scatter"),
            &passes
                .modules_sort_import_visible_keys_scatter
                .bind_group_layouts[0],
            &passes.modules_sort_import_visible_keys_scatter.reflection,
            0,
            &scatter_resources,
        )?);
        drop(histogram_resources);
        drop(bucket_prefix_resources);
        drop(bucket_bases_resources);
        drop(scatter_resources);
        module_key_radix_steps.push(ModuleKeyRadixStep {
            _params: step_params,
        });
    }

    let mut sort_import_visible_value_key_histogram =
        Vec::with_capacity(IMPORT_VISIBLE_KEY_RADIX_STEPS as usize);
    let mut sort_import_visible_value_key_bucket_prefix =
        Vec::with_capacity(IMPORT_VISIBLE_KEY_RADIX_STEPS as usize);
    let mut sort_import_visible_value_key_bucket_bases =
        Vec::with_capacity(IMPORT_VISIBLE_KEY_RADIX_STEPS as usize);
    let mut sort_import_visible_value_key_scatter =
        Vec::with_capacity(IMPORT_VISIBLE_KEY_RADIX_STEPS as usize);
    for key_step in 0..IMPORT_VISIBLE_KEY_RADIX_STEPS {
        let step_params = uniform_from_val(
            device,
            &format!("type_check.modules.import_visible_value_radix.params.{key_step}"),
            &ModuleKeyRadixParams {
                module_capacity: hir_node_capacity,
                reserved: 0,
                n_blocks,
                key_step,
            },
        );
        let read_order = if key_step % 2 == 0 {
            &import_visible_value_key_order
        } else {
            &import_visible_value_key_order_tmp
        };
        let write_order = if key_step % 2 == 0 {
            &import_visible_value_key_order_tmp
        } else {
            &import_visible_value_key_order
        };
        let histogram_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "import_visible_count_out".into(),
                import_visible_value_count_out.as_entire_binding(),
            ),
            (
                "import_visible_module_id".into(),
                import_visible_value_module_id.as_entire_binding(),
            ),
            (
                "import_visible_name_id".into(),
                import_visible_value_name_id.as_entire_binding(),
            ),
            (
                "import_visible_key_order_in".into(),
                read_order.as_entire_binding(),
            ),
            (
                "radix_block_histogram".into(),
                import_visible_key_radix_block_histogram.as_entire_binding(),
            ),
        ]);
        sort_import_visible_value_key_histogram.push(
            bind_group::create_bind_group_from_reflection(
                device,
                Some("type_check_modules_09c_sort_import_visible_keys"),
                &passes.modules_sort_import_visible_keys.bind_group_layouts[0],
                &passes.modules_sort_import_visible_keys.reflection,
                0,
                &histogram_resources,
            )?,
        );
        let bucket_prefix_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "radix_block_histogram".into(),
                import_visible_key_radix_block_histogram.as_entire_binding(),
            ),
            (
                "radix_block_bucket_prefix".into(),
                import_visible_key_radix_block_bucket_prefix.as_entire_binding(),
            ),
            (
                "radix_bucket_total".into(),
                import_visible_key_radix_bucket_total.as_entire_binding(),
            ),
        ]);
        sort_import_visible_value_key_bucket_prefix.push(
            bind_group::create_bind_group_from_reflection(
                device,
                Some("type_check_modules.import_visible_value_bucket_prefix"),
                &passes.names_radix_bucket_prefix.bind_group_layouts[0],
                &passes.names_radix_bucket_prefix.reflection,
                0,
                &bucket_prefix_resources,
            )?,
        );
        let bucket_bases_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "radix_bucket_total".into(),
                import_visible_key_radix_bucket_total.as_entire_binding(),
            ),
            (
                "radix_bucket_base".into(),
                import_visible_key_radix_bucket_base.as_entire_binding(),
            ),
        ]);
        sort_import_visible_value_key_bucket_bases.push(
            bind_group::create_bind_group_from_reflection(
                device,
                Some("type_check_modules.import_visible_value_bucket_bases"),
                &passes.names_radix_bucket_bases.bind_group_layouts[0],
                &passes.names_radix_bucket_bases.reflection,
                0,
                &bucket_bases_resources,
            )?,
        );
        let scatter_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "import_visible_count_out".into(),
                import_visible_value_count_out.as_entire_binding(),
            ),
            (
                "import_visible_module_id".into(),
                import_visible_value_module_id.as_entire_binding(),
            ),
            (
                "import_visible_name_id".into(),
                import_visible_value_name_id.as_entire_binding(),
            ),
            (
                "import_visible_key_order_in".into(),
                read_order.as_entire_binding(),
            ),
            (
                "radix_bucket_base".into(),
                import_visible_key_radix_bucket_base.as_entire_binding(),
            ),
            (
                "radix_block_bucket_prefix".into(),
                import_visible_key_radix_block_bucket_prefix.as_entire_binding(),
            ),
            (
                "import_visible_key_order_out".into(),
                write_order.as_entire_binding(),
            ),
        ]);
        sort_import_visible_value_key_scatter.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_modules_09d_sort_import_visible_keys_scatter"),
            &passes
                .modules_sort_import_visible_keys_scatter
                .bind_group_layouts[0],
            &passes.modules_sort_import_visible_keys_scatter.reflection,
            0,
            &scatter_resources,
        )?);
        drop(histogram_resources);
        drop(bucket_prefix_resources);
        drop(bucket_bases_resources);
        drop(scatter_resources);
        module_key_radix_steps.push(ModuleKeyRadixStep {
            _params: step_params,
        });
    }

    let build_import_visible_type_key_table_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            (
                "gParams".into(),
                import_visibility_params.as_entire_binding(),
            ),
            (
                "import_visible_count_out".into(),
                import_visible_type_count_out.as_entire_binding(),
            ),
            (
                "import_visible_key_order".into(),
                import_visible_type_key_order.as_entire_binding(),
            ),
            (
                "import_visible_module_id".into(),
                import_visible_type_module_id.as_entire_binding(),
            ),
            (
                "import_visible_name_id".into(),
                import_visible_type_name_id.as_entire_binding(),
            ),
            (
                "import_visible_decl_id".into(),
                import_visible_type_decl_id.as_entire_binding(),
            ),
            (
                "import_visible_key_module_id".into(),
                import_visible_type_key_module_id.as_entire_binding(),
            ),
            (
                "import_visible_key_name_id".into(),
                import_visible_type_key_name_id.as_entire_binding(),
            ),
            (
                "import_visible_key_to_decl_id".into(),
                import_visible_type_key_to_decl_id.as_entire_binding(),
            ),
        ]);
    let build_import_visible_type_key_table = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_09e_build_import_visible_key_tables.type"),
        &passes
            .modules_build_import_visible_key_tables
            .bind_group_layouts[0],
        &passes.modules_build_import_visible_key_tables.reflection,
        0,
        &build_import_visible_type_key_table_resources,
    )?;

    let build_import_visible_value_key_table_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            (
                "gParams".into(),
                import_visibility_params.as_entire_binding(),
            ),
            (
                "import_visible_count_out".into(),
                import_visible_value_count_out.as_entire_binding(),
            ),
            (
                "import_visible_key_order".into(),
                import_visible_value_key_order.as_entire_binding(),
            ),
            (
                "import_visible_module_id".into(),
                import_visible_value_module_id.as_entire_binding(),
            ),
            (
                "import_visible_name_id".into(),
                import_visible_value_name_id.as_entire_binding(),
            ),
            (
                "import_visible_decl_id".into(),
                import_visible_value_decl_id.as_entire_binding(),
            ),
            (
                "import_visible_key_module_id".into(),
                import_visible_value_key_module_id.as_entire_binding(),
            ),
            (
                "import_visible_key_name_id".into(),
                import_visible_value_key_name_id.as_entire_binding(),
            ),
            (
                "import_visible_key_to_decl_id".into(),
                import_visible_value_key_to_decl_id.as_entire_binding(),
            ),
        ]);
    let build_import_visible_value_key_table = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_09e_build_import_visible_key_tables.value"),
        &passes
            .modules_build_import_visible_key_tables
            .bind_group_layouts[0],
        &passes.modules_build_import_visible_key_tables.reflection,
        0,
        &build_import_visible_value_key_table_resources,
    )?;

    let validate_import_visible_keys_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            (
                "gParams".into(),
                import_visibility_params.as_entire_binding(),
            ),
            (
                "import_visible_type_count_out".into(),
                import_visible_type_count_out.as_entire_binding(),
            ),
            (
                "import_visible_type_key_module_id".into(),
                import_visible_type_key_module_id.as_entire_binding(),
            ),
            (
                "import_visible_type_key_name_id".into(),
                import_visible_type_key_name_id.as_entire_binding(),
            ),
            (
                "import_visible_type_key_to_decl_id".into(),
                import_visible_type_key_to_decl_id.as_entire_binding(),
            ),
            (
                "import_visible_value_count_out".into(),
                import_visible_value_count_out.as_entire_binding(),
            ),
            (
                "import_visible_value_key_module_id".into(),
                import_visible_value_key_module_id.as_entire_binding(),
            ),
            (
                "import_visible_value_key_name_id".into(),
                import_visible_value_key_name_id.as_entire_binding(),
            ),
            (
                "import_visible_value_key_to_decl_id".into(),
                import_visible_value_key_to_decl_id.as_entire_binding(),
            ),
            (
                "import_visible_type_status".into(),
                import_visible_type_status.as_entire_binding(),
            ),
            (
                "import_visible_type_duplicate_of".into(),
                import_visible_type_duplicate_of.as_entire_binding(),
            ),
            (
                "import_visible_value_status".into(),
                import_visible_value_status.as_entire_binding(),
            ),
            (
                "import_visible_value_duplicate_of".into(),
                import_visible_value_duplicate_of.as_entire_binding(),
            ),
        ]);
    let validate_import_visible_keys = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_09f_validate_import_visible_keys"),
        &passes
            .modules_validate_import_visible_keys
            .bind_group_layouts[0],
        &passes.modules_validate_import_visible_keys.reflection,
        0,
        &validate_import_visible_keys_resources,
    )?;

    let resolve_local_type_paths_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            (
                "gParams".into(),
                import_visibility_params.as_entire_binding(),
            ),
            ("path_count_out".into(), path_count_out.as_entire_binding()),
            ("path_kind".into(), path_kind.as_entire_binding()),
            (
                "path_segment_count".into(),
                path_segment_count.as_entire_binding(),
            ),
            (
                "path_segment_base".into(),
                path_segment_base.as_entire_binding(),
            ),
            (
                "path_segment_name_id".into(),
                path_segment_name_id.as_entire_binding(),
            ),
            (
                "path_owner_module_id".into(),
                path_owner_module_id.as_entire_binding(),
            ),
            (
                "decl_key_count_out".into(),
                decl_type_key_count_out.as_entire_binding(),
            ),
            (
                "decl_key_to_decl_id".into(),
                decl_type_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_module_id".into(), decl_module_id.as_entire_binding()),
            ("decl_name_id".into(), decl_name_id.as_entire_binding()),
            (
                "resolved_decl".into(),
                resolved_type_decl.as_entire_binding(),
            ),
            (
                "resolved_status".into(),
                resolved_type_status.as_entire_binding(),
            ),
        ]);
    let resolve_local_type_paths = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10_resolve_local_paths.type"),
        &passes.modules_resolve_local_paths.bind_group_layouts[0],
        &passes.modules_resolve_local_paths.reflection,
        0,
        &resolve_local_type_paths_resources,
    )?;

    let resolve_local_value_paths_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            (
                "gParams".into(),
                import_visibility_params.as_entire_binding(),
            ),
            ("path_count_out".into(), path_count_out.as_entire_binding()),
            ("path_kind".into(), path_kind.as_entire_binding()),
            (
                "path_segment_count".into(),
                path_segment_count.as_entire_binding(),
            ),
            (
                "path_segment_base".into(),
                path_segment_base.as_entire_binding(),
            ),
            (
                "path_segment_name_id".into(),
                path_segment_name_id.as_entire_binding(),
            ),
            (
                "path_owner_module_id".into(),
                path_owner_module_id.as_entire_binding(),
            ),
            (
                "decl_key_count_out".into(),
                decl_value_key_count_out.as_entire_binding(),
            ),
            (
                "decl_key_to_decl_id".into(),
                decl_value_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_module_id".into(), decl_module_id.as_entire_binding()),
            ("decl_name_id".into(), decl_name_id.as_entire_binding()),
            (
                "resolved_decl".into(),
                resolved_value_decl.as_entire_binding(),
            ),
            (
                "resolved_status".into(),
                resolved_value_status.as_entire_binding(),
            ),
        ]);
    let resolve_local_value_paths = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10_resolve_local_paths.value"),
        &passes.modules_resolve_local_paths.bind_group_layouts[0],
        &passes.modules_resolve_local_paths.reflection,
        0,
        &resolve_local_value_paths_resources,
    )?;

    let resolve_imported_type_paths_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            (
                "gParams".into(),
                import_visibility_params.as_entire_binding(),
            ),
            ("path_count_out".into(), path_count_out.as_entire_binding()),
            ("path_kind".into(), path_kind.as_entire_binding()),
            (
                "path_segment_count".into(),
                path_segment_count.as_entire_binding(),
            ),
            (
                "path_segment_base".into(),
                path_segment_base.as_entire_binding(),
            ),
            (
                "path_segment_name_id".into(),
                path_segment_name_id.as_entire_binding(),
            ),
            (
                "path_owner_module_id".into(),
                path_owner_module_id.as_entire_binding(),
            ),
            (
                "import_visible_count_out".into(),
                import_visible_type_count_out.as_entire_binding(),
            ),
            (
                "import_visible_key_module_id".into(),
                import_visible_type_key_module_id.as_entire_binding(),
            ),
            (
                "import_visible_key_name_id".into(),
                import_visible_type_key_name_id.as_entire_binding(),
            ),
            (
                "import_visible_key_to_decl_id".into(),
                import_visible_type_key_to_decl_id.as_entire_binding(),
            ),
            (
                "import_visible_status".into(),
                import_visible_type_status.as_entire_binding(),
            ),
            (
                "resolved_decl".into(),
                resolved_type_decl.as_entire_binding(),
            ),
            (
                "resolved_status".into(),
                resolved_type_status.as_entire_binding(),
            ),
        ]);
    let resolve_imported_type_paths = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10b_resolve_imported_paths.type"),
        &passes.modules_resolve_imported_paths.bind_group_layouts[0],
        &passes.modules_resolve_imported_paths.reflection,
        0,
        &resolve_imported_type_paths_resources,
    )?;

        let resolve_imported_value_paths_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            (
                "gParams".into(),
                import_visibility_params.as_entire_binding(),
            ),
            ("path_count_out".into(), path_count_out.as_entire_binding()),
            ("path_kind".into(), path_kind.as_entire_binding()),
            (
                "path_segment_count".into(),
                path_segment_count.as_entire_binding(),
            ),
            (
                "path_segment_base".into(),
                path_segment_base.as_entire_binding(),
            ),
            (
                "path_segment_name_id".into(),
                path_segment_name_id.as_entire_binding(),
            ),
            (
                "path_owner_module_id".into(),
                path_owner_module_id.as_entire_binding(),
            ),
            (
                "import_visible_count_out".into(),
                import_visible_value_count_out.as_entire_binding(),
            ),
            (
                "import_visible_key_module_id".into(),
                import_visible_value_key_module_id.as_entire_binding(),
            ),
            (
                "import_visible_key_name_id".into(),
                import_visible_value_key_name_id.as_entire_binding(),
            ),
            (
                "import_visible_key_to_decl_id".into(),
                import_visible_value_key_to_decl_id.as_entire_binding(),
            ),
            (
                "import_visible_status".into(),
                import_visible_value_status.as_entire_binding(),
            ),
            (
                "resolved_decl".into(),
                resolved_value_decl.as_entire_binding(),
            ),
            (
                "resolved_status".into(),
                resolved_value_status.as_entire_binding(),
            ),
        ]);
    let resolve_imported_value_paths = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10b_resolve_imported_paths.value"),
        &passes.modules_resolve_imported_paths.bind_group_layouts[0],
        &passes.modules_resolve_imported_paths.reflection,
        0,
        &resolve_imported_value_paths_resources,
    )?;

    let resolve_qualified_type_paths_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            (
                "gParams".into(),
                import_visibility_params.as_entire_binding(),
            ),
            ("path_count_out".into(), path_count_out.as_entire_binding()),
            ("path_kind".into(), path_kind.as_entire_binding()),
            (
                "path_segment_count".into(),
                path_segment_count.as_entire_binding(),
            ),
            (
                "path_segment_base".into(),
                path_segment_base.as_entire_binding(),
            ),
            (
                "path_segment_name_id".into(),
                path_segment_name_id.as_entire_binding(),
            ),
            (
                "module_count_out".into(),
                module_count_out.as_entire_binding(),
            ),
            (
                "sorted_module_key_order".into(),
                module_key_to_module_id.as_entire_binding(),
            ),
            (
                "module_key_segment_count".into(),
                module_key_segment_count.as_entire_binding(),
            ),
            (
                "module_key_segment_base".into(),
                module_key_segment_base.as_entire_binding(),
            ),
            (
                "module_key_segment_name_id".into(),
                module_key_segment_name_id.as_entire_binding(),
            ),
            (
                "decl_key_count_out".into(),
                decl_type_key_count_out.as_entire_binding(),
            ),
            (
                "decl_key_to_decl_id".into(),
                decl_type_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_module_id".into(), decl_module_id.as_entire_binding()),
            ("decl_name_id".into(), decl_name_id.as_entire_binding()),
            (
                "resolved_decl".into(),
                resolved_type_decl.as_entire_binding(),
            ),
            (
                "resolved_status".into(),
                resolved_type_status.as_entire_binding(),
            ),
        ]);
    let resolve_qualified_type_paths = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10c_resolve_qualified_paths.type"),
        &passes.modules_resolve_qualified_paths.bind_group_layouts[0],
        &passes.modules_resolve_qualified_paths.reflection,
        0,
        &resolve_qualified_type_paths_resources,
    )?;

    let resolve_qualified_value_paths_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            (
                "gParams".into(),
                import_visibility_params.as_entire_binding(),
            ),
            ("path_count_out".into(), path_count_out.as_entire_binding()),
            ("path_kind".into(), path_kind.as_entire_binding()),
            (
                "path_segment_count".into(),
                path_segment_count.as_entire_binding(),
            ),
            (
                "path_segment_base".into(),
                path_segment_base.as_entire_binding(),
            ),
            (
                "path_segment_name_id".into(),
                path_segment_name_id.as_entire_binding(),
            ),
            (
                "module_count_out".into(),
                module_count_out.as_entire_binding(),
            ),
            (
                "sorted_module_key_order".into(),
                module_key_to_module_id.as_entire_binding(),
            ),
            (
                "module_key_segment_count".into(),
                module_key_segment_count.as_entire_binding(),
            ),
            (
                "module_key_segment_base".into(),
                module_key_segment_base.as_entire_binding(),
            ),
            (
                "module_key_segment_name_id".into(),
                module_key_segment_name_id.as_entire_binding(),
            ),
            (
                "decl_key_count_out".into(),
                decl_value_key_count_out.as_entire_binding(),
            ),
            (
                "decl_key_to_decl_id".into(),
                decl_value_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_module_id".into(), decl_module_id.as_entire_binding()),
            ("decl_name_id".into(), decl_name_id.as_entire_binding()),
            (
                "resolved_decl".into(),
                resolved_value_decl.as_entire_binding(),
            ),
            (
                "resolved_status".into(),
                resolved_value_status.as_entire_binding(),
            ),
        ]);
    let resolve_qualified_value_paths = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10c_resolve_qualified_paths.value"),
        &passes.modules_resolve_qualified_paths.bind_group_layouts[0],
        &passes.modules_resolve_qualified_paths.reflection,
        0,
        &resolve_qualified_value_paths_resources,
    )?;

    let decl_core_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        (
            "decl_record_flag".into(),
            decl_record_flag.as_entire_binding(),
        ),
        (
            "decl_record_prefix".into(),
            decl_record_prefix.as_entire_binding(),
        ),
        ("parent".into(), hir_items.parent.as_entire_binding()),
        (
            "hir_item_file_id".into(),
            hir_items.file_id.as_entire_binding(),
        ),
        (
            "hir_item_name_token".into(),
            hir_items.name_token.as_entire_binding(),
        ),
        ("hir_item_kind".into(), hir_items.kind.as_entire_binding()),
        (
            "hir_item_namespace".into(),
            hir_items.namespace.as_entire_binding(),
        ),
        (
            "hir_item_visibility".into(),
            hir_items.visibility.as_entire_binding(),
        ),
        (
            "name_id_by_token".into(),
            name_id_by_token.as_entire_binding(),
        ),
        (
            "decl_module_file_id".into(),
            decl_module_file_id.as_entire_binding(),
        ),
        ("decl_name_id".into(), decl_name_id.as_entire_binding()),
        ("decl_kind".into(), decl_kind.as_entire_binding()),
        ("decl_namespace".into(), decl_namespace.as_entire_binding()),
        (
            "decl_visibility".into(),
            decl_visibility.as_entire_binding(),
        ),
        ("decl_hir_node".into(), decl_hir_node.as_entire_binding()),
        (
            "decl_parent_type_decl".into(),
            decl_parent_type_decl.as_entire_binding(),
        ),
    ]);
    let scatter_decl_core_records = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_02c_scatter_decl_core_records"),
        &passes.modules_scatter_decl_core_records.bind_group_layouts[0],
        &passes.modules_scatter_decl_core_records.reflection,
        0,
        &decl_core_resources,
    )?;

    let decl_span_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        (
            "decl_record_flag".into(),
            decl_record_flag.as_entire_binding(),
        ),
        (
            "decl_record_prefix".into(),
            decl_record_prefix.as_entire_binding(),
        ),
        (
            "hir_item_name_token".into(),
            hir_items.name_token.as_entire_binding(),
        ),
        (
            "hir_token_pos".into(),
            hir_token_pos_buf.as_entire_binding(),
        ),
        (
            "hir_token_end".into(),
            hir_token_end_buf.as_entire_binding(),
        ),
        (
            "decl_name_token".into(),
            decl_name_token.as_entire_binding(),
        ),
        (
            "decl_token_start".into(),
            decl_token_start.as_entire_binding(),
        ),
        ("decl_token_end".into(), decl_token_end.as_entire_binding()),
    ]);
    let scatter_decl_span_records = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_02d_scatter_decl_span_records"),
        &passes.modules_scatter_decl_span_records.bind_group_layouts[0],
        &passes.modules_scatter_decl_span_records.reflection,
        0,
        &decl_span_resources,
    )?;
    let clear_type_path_types_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            ("gParams".into(), params.as_entire_binding()),
            (
                "module_type_path_type".into(),
                module_type_path_type.as_entire_binding(),
            ),
            (
                "module_type_path_status".into(),
                module_type_path_status.as_entire_binding(),
            ),
            (
                "module_value_path_expr_head".into(),
                module_value_path_expr_head.as_entire_binding(),
            ),
            (
                "module_value_path_call_head".into(),
                module_value_path_call_head.as_entire_binding(),
            ),
            (
                "module_value_path_call_open".into(),
                module_value_path_call_open.as_entire_binding(),
            ),
            (
                "module_value_path_const_head".into(),
                module_value_path_const_head.as_entire_binding(),
            ),
            (
                "module_value_path_const_end".into(),
                module_value_path_const_end.as_entire_binding(),
            ),
            (
                "module_value_path_status".into(),
                module_value_path_status.as_entire_binding(),
            ),
        ]);
    let clear_type_path_types = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10d_clear_type_path_types"),
        &passes.modules_clear_type_path_types.bind_group_layouts[0],
        &passes.modules_clear_type_path_types.reflection,
        0,
        &clear_type_path_types_resources,
    )?;
    let project_type_paths_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("path_count_out".into(), path_count_out.as_entire_binding()),
        ("path_kind".into(), path_kind.as_entire_binding()),
        (
            "path_segment_count".into(),
            path_segment_count.as_entire_binding(),
        ),
        (
            "path_owner_token".into(),
            path_owner_token.as_entire_binding(),
        ),
        (
            "resolved_type_decl".into(),
            resolved_type_decl.as_entire_binding(),
        ),
        (
            "resolved_type_status".into(),
            resolved_type_status.as_entire_binding(),
        ),
        ("decl_kind".into(), decl_kind.as_entire_binding()),
        ("decl_namespace".into(), decl_namespace.as_entire_binding()),
        (
            "decl_name_token".into(),
            decl_name_token.as_entire_binding(),
        ),
        (
            "module_type_path_type".into(),
            module_type_path_type.as_entire_binding(),
        ),
        (
            "module_type_path_status".into(),
            module_type_path_status.as_entire_binding(),
        ),
    ]);
    let project_type_paths = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10e_project_type_paths"),
        &passes.modules_project_type_paths.bind_group_layouts[0],
        &passes.modules_project_type_paths.reflection,
        0,
        &project_type_paths_resources,
    )?;
    let project_type_aliases_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            ("gParams".into(), params.as_entire_binding()),
            ("hir_status".into(), hir_status_buf.as_entire_binding()),
            ("hir_kind".into(), hir_kind_buf.as_entire_binding()),
            ("first_child".into(), hir_items.first_child.as_entire_binding()),
            (
                "next_sibling".into(),
                hir_items.next_sibling.as_entire_binding(),
            ),
            ("hir_token_pos".into(), hir_token_pos_buf.as_entire_binding()),
            ("hir_type_form".into(), hir_items.type_form.as_entire_binding()),
            ("decl_count_out".into(), decl_count_out.as_entire_binding()),
            ("decl_kind".into(), decl_kind.as_entire_binding()),
            ("decl_namespace".into(), decl_namespace.as_entire_binding()),
            (
                "decl_name_token".into(),
                decl_name_token.as_entire_binding(),
            ),
            ("decl_hir_node".into(), decl_hir_node.as_entire_binding()),
            (
                "type_expr_ref_tag".into(),
                type_expr_ref_tag.as_entire_binding(),
            ),
            (
                "type_expr_ref_payload".into(),
                type_expr_ref_payload.as_entire_binding(),
            ),
            (
                "module_type_path_type".into(),
                module_type_path_type.as_entire_binding(),
            ),
            (
                "module_type_path_status".into(),
                module_type_path_status.as_entire_binding(),
            ),
        ]);
    let project_type_aliases = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10e2_project_type_aliases"),
        &passes.modules_project_type_aliases.bind_group_layouts[0],
        &passes.modules_project_type_aliases.reflection,
        0,
        &project_type_aliases_resources,
    )?;
    let project_type_instances_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            ("gParams".into(), params.as_entire_binding()),
            (
                "path_segment_count".into(),
                path_segment_count.as_entire_binding(),
            ),
            (
                "path_segment_base".into(),
                path_segment_base.as_entire_binding(),
            ),
            (
                "path_segment_token".into(),
                path_segment_token.as_entire_binding(),
            ),
            (
                "path_owner_token".into(),
                path_owner_token.as_entire_binding(),
            ),
            (
                "resolved_type_decl".into(),
                resolved_type_decl.as_entire_binding(),
            ),
            (
                "decl_name_token".into(),
                decl_name_token.as_entire_binding(),
            ),
            (
                "type_instance_kind".into(),
                type_instance_kind.as_entire_binding(),
            ),
            (
                "type_instance_arg_count".into(),
                type_instance_arg_count.as_entire_binding(),
            ),
            (
                "type_decl_generic_param_count".into(),
                type_decl_generic_param_count.as_entire_binding(),
            ),
            (
                "type_expr_ref_tag".into(),
                type_expr_ref_tag.as_entire_binding(),
            ),
            (
                "type_expr_ref_payload".into(),
                type_expr_ref_payload.as_entire_binding(),
            ),
            (
                "type_instance_decl_token".into(),
                type_instance_decl_token.as_entire_binding(),
            ),
            (
                "type_instance_state".into(),
                type_instance_state.as_entire_binding(),
            ),
        ]);
    let project_type_instances = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10k_project_type_instances"),
        &passes.modules_project_type_instances.bind_group_layouts[0],
        &passes.modules_project_type_instances.reflection,
        0,
        &project_type_instances_resources,
    )?;
    let mark_value_call_paths_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            ("gParams".into(), params.as_entire_binding()),
            ("hir_status".into(), hir_status_buf.as_entire_binding()),
            ("parent".into(), hir_items.parent.as_entire_binding()),
            (
                "next_sibling".into(),
                hir_items.next_sibling.as_entire_binding(),
            ),
            ("hir_kind".into(), hir_kind_buf.as_entire_binding()),
            (
                "hir_token_pos".into(),
                hir_token_pos_buf.as_entire_binding(),
            ),
            (
                "hir_token_end".into(),
                hir_token_end_buf.as_entire_binding(),
            ),
            (
                "module_value_path_call_head".into(),
                module_value_path_call_head.as_entire_binding(),
            ),
            (
                "module_value_path_call_open".into(),
                module_value_path_call_open.as_entire_binding(),
            ),
            (
                "module_value_path_expr_head".into(),
                module_value_path_expr_head.as_entire_binding(),
            ),
        ]);
    let mark_value_call_paths = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10f_mark_value_call_paths"),
        &passes.modules_mark_value_call_paths.bind_group_layouts[0],
        &passes.modules_mark_value_call_paths.reflection,
        0,
        &mark_value_call_paths_resources,
    )?;
    let project_value_paths_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            ("gParams".into(), params.as_entire_binding()),
            ("path_count_out".into(), path_count_out.as_entire_binding()),
            ("path_kind".into(), path_kind.as_entire_binding()),
            (
                "path_segment_count".into(),
                path_segment_count.as_entire_binding(),
            ),
            (
                "path_segment_base".into(),
                path_segment_base.as_entire_binding(),
            ),
            (
                "path_segment_token".into(),
                path_segment_token.as_entire_binding(),
            ),
            (
                "path_owner_token".into(),
                path_owner_token.as_entire_binding(),
            ),
            (
                "resolved_type_decl".into(),
                resolved_type_decl.as_entire_binding(),
            ),
            (
                "resolved_value_status".into(),
                resolved_value_status.as_entire_binding(),
            ),
            (
                "module_type_path_status".into(),
                module_type_path_status.as_entire_binding(),
            ),
            (
                "module_value_path_call_head".into(),
                module_value_path_call_head.as_entire_binding(),
            ),
            (
                "module_value_path_expr_head".into(),
                module_value_path_expr_head.as_entire_binding(),
            ),
            (
                "module_value_path_status".into(),
                module_value_path_status.as_entire_binding(),
            ),
        ]);
    let project_value_paths = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10g_project_value_paths"),
        &passes.modules_project_value_paths.bind_group_layouts[0],
        &passes.modules_project_value_paths.reflection,
        0,
        &project_value_paths_resources,
    )?;
    let consume_value_calls_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            ("gParams".into(), params.as_entire_binding()),
            ("path_count_out".into(), path_count_out.as_entire_binding()),
            (
                "path_owner_token".into(),
                path_owner_token.as_entire_binding(),
            ),
            (
                "resolved_value_decl".into(),
                resolved_value_decl.as_entire_binding(),
            ),
            (
                "resolved_value_status".into(),
                resolved_value_status.as_entire_binding(),
            ),
            (
                "decl_token_start".into(),
                decl_token_start.as_entire_binding(),
            ),
            (
                "call_arg_record".into(),
                call_arg_record.as_entire_binding(),
            ),
            (
                "module_value_path_call_open".into(),
                module_value_path_call_open.as_entire_binding(),
            ),
            ("hir_token_pos".into(), hir_token_pos_buf.as_entire_binding()),
            (
                "hir_call_callee_node".into(),
                hir_items.call_callee_node.as_entire_binding(),
            ),
            (
                "hir_call_arg_parent_call".into(),
                hir_items.call_arg_parent_call.as_entire_binding(),
            ),
            (
                "hir_call_arg_ordinal".into(),
                hir_items.call_arg_ordinal.as_entire_binding(),
            ),
            (
                "hir_expr_form".into(),
                hir_items.expr_form.as_entire_binding(),
            ),
            (
                "hir_expr_left_node".into(),
                hir_items.expr_left_node.as_entire_binding(),
            ),
            (
                "call_param_count".into(),
                call_param_count.as_entire_binding(),
            ),
            (
                "call_param_type".into(),
                call_param_type.as_entire_binding(),
            ),
            (
                "module_value_path_status".into(),
                module_value_path_status.as_entire_binding(),
            ),
            ("call_fn_index".into(), call_fn_index.as_entire_binding()),
            (
                "call_return_type".into(),
                call_return_type.as_entire_binding(),
            ),
            (
                "call_return_type_token".into(),
                call_return_type_token.as_entire_binding(),
            ),
            ("status".into(), status_buf.as_entire_binding()),
        ]);
    let consume_value_calls = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10h_consume_value_calls"),
        &passes.modules_consume_value_calls.bind_group_layouts[0],
        &passes.modules_consume_value_calls.reflection,
        0,
        &consume_value_calls_resources,
    )?;
    let consume_value_consts_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            ("gParams".into(), params.as_entire_binding()),
            ("path_count_out".into(), path_count_out.as_entire_binding()),
            ("path_kind".into(), path_kind.as_entire_binding()),
            (
                "path_segment_count".into(),
                path_segment_count.as_entire_binding(),
            ),
            (
                "path_segment_base".into(),
                path_segment_base.as_entire_binding(),
            ),
            (
                "path_segment_token".into(),
                path_segment_token.as_entire_binding(),
            ),
            (
                "path_owner_token".into(),
                path_owner_token.as_entire_binding(),
            ),
            (
                "resolved_value_decl".into(),
                resolved_value_decl.as_entire_binding(),
            ),
            (
                "resolved_value_status".into(),
                resolved_value_status.as_entire_binding(),
            ),
            ("decl_kind".into(), decl_kind.as_entire_binding()),
            (
                "decl_name_token".into(),
                decl_name_token.as_entire_binding(),
            ),
            (
                "module_value_path_call_head".into(),
                module_value_path_call_head.as_entire_binding(),
            ),
            (
                "module_value_path_status".into(),
                module_value_path_status.as_entire_binding(),
            ),
            (
                "module_value_path_const_head".into(),
                module_value_path_const_head.as_entire_binding(),
            ),
            (
                "module_value_path_const_end".into(),
                module_value_path_const_end.as_entire_binding(),
            ),
            ("visible_decl".into(), visible_decl.as_entire_binding()),
            ("visible_type".into(), visible_type.as_entire_binding()),
        ]);
    let consume_value_consts = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10i_consume_value_consts"),
        &passes.modules_consume_value_consts.bind_group_layouts[0],
        &passes.modules_consume_value_consts.reflection,
        0,
        &consume_value_consts_resources,
    )?;
    let consume_value_enum_units_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            ("gParams".into(), params.as_entire_binding()),
            ("path_count_out".into(), path_count_out.as_entire_binding()),
            ("path_kind".into(), path_kind.as_entire_binding()),
            (
                "path_segment_count".into(),
                path_segment_count.as_entire_binding(),
            ),
            (
                "path_owner_token".into(),
                path_owner_token.as_entire_binding(),
            ),
            (
                "resolved_value_decl".into(),
                resolved_value_decl.as_entire_binding(),
            ),
            (
                "resolved_value_status".into(),
                resolved_value_status.as_entire_binding(),
            ),
            ("decl_kind".into(), decl_kind.as_entire_binding()),
            ("decl_namespace".into(), decl_namespace.as_entire_binding()),
            (
                "decl_name_token".into(),
                decl_name_token.as_entire_binding(),
            ),
            ("decl_hir_node".into(), decl_hir_node.as_entire_binding()),
            (
                "decl_parent_type_decl".into(),
                decl_parent_type_decl.as_entire_binding(),
            ),
            (
                "hir_variant_payload_count".into(),
                hir_items.variant_payload_count.as_entire_binding(),
            ),
            (
                "module_value_path_call_head".into(),
                module_value_path_call_head.as_entire_binding(),
            ),
            (
                "module_value_path_status".into(),
                module_value_path_status.as_entire_binding(),
            ),
            ("visible_decl".into(), visible_decl.as_entire_binding()),
            ("visible_type".into(), visible_type.as_entire_binding()),
        ]);
    let consume_value_enum_units = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10j_consume_value_enum_units"),
        &passes.modules_consume_value_enum_units.bind_group_layouts[0],
        &passes.modules_consume_value_enum_units.reflection,
        0,
        &consume_value_enum_units_resources,
    )?;
    let consume_value_enum_calls_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            ("gParams".into(), params.as_entire_binding()),
            ("path_count_out".into(), path_count_out.as_entire_binding()),
            ("path_kind".into(), path_kind.as_entire_binding()),
            (
                "path_segment_count".into(),
                path_segment_count.as_entire_binding(),
            ),
            (
                "path_segment_base".into(),
                path_segment_base.as_entire_binding(),
            ),
            (
                "path_segment_token".into(),
                path_segment_token.as_entire_binding(),
            ),
            (
                "path_owner_token".into(),
                path_owner_token.as_entire_binding(),
            ),
            (
                "resolved_value_decl".into(),
                resolved_value_decl.as_entire_binding(),
            ),
            (
                "resolved_value_status".into(),
                resolved_value_status.as_entire_binding(),
            ),
            ("decl_kind".into(), decl_kind.as_entire_binding()),
            ("decl_namespace".into(), decl_namespace.as_entire_binding()),
            (
                "decl_name_token".into(),
                decl_name_token.as_entire_binding(),
            ),
            (
                "decl_parent_type_decl".into(),
                decl_parent_type_decl.as_entire_binding(),
            ),
            (
                "module_value_path_call_head".into(),
                module_value_path_call_head.as_entire_binding(),
            ),
            (
                "type_decl_generic_param_count".into(),
                type_decl_generic_param_count.as_entire_binding(),
            ),
            (
                "module_value_path_status".into(),
                module_value_path_status.as_entire_binding(),
            ),
            (
                "call_return_type".into(),
                call_return_type.as_entire_binding(),
            ),
        ]);
    let consume_value_enum_calls = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10l_consume_value_enum_calls"),
        &passes.modules_consume_value_enum_calls.bind_group_layouts[0],
        &passes.modules_consume_value_enum_calls.reflection,
        0,
        &consume_value_enum_calls_resources,
    )?;
            let bind_match_patterns_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            ("gParams".into(), params.as_entire_binding()),
            ("token_words".into(), token_buf.as_entire_binding()),
            ("language_name_id".into(), language_name_id.as_entire_binding()),
            ("path_count_out".into(), path_count_out.as_entire_binding()),
            ("path_kind".into(), path_kind.as_entire_binding()),
            (
                "path_owner_token".into(),
                path_owner_token.as_entire_binding(),
            ),
            (
                "resolved_value_decl".into(),
                resolved_value_decl.as_entire_binding(),
            ),
            (
                "resolved_value_status".into(),
                resolved_value_status.as_entire_binding(),
            ),
            ("decl_kind".into(), decl_kind.as_entire_binding()),
            (
                "decl_name_token".into(),
                decl_name_token.as_entire_binding(),
            ),
            (
                "decl_parent_type_decl".into(),
                decl_parent_type_decl.as_entire_binding(),
            ),
            (
                "name_id_by_token".into(),
                name_id_by_token.as_entire_binding(),
            ),
            ("visible_decl".into(), visible_decl.as_entire_binding()),
            ("visible_type".into(), visible_type.as_entire_binding()),
            (
                "module_value_path_status".into(),
                module_value_path_status.as_entire_binding(),
            ),
        ]);
    let bind_match_patterns = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10m_bind_match_patterns"),
        &passes.modules_bind_match_patterns.bind_group_layouts[0],
        &passes.modules_bind_match_patterns.reflection,
        0,
        &bind_match_patterns_resources,
    )?;
    let type_match_payloads_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            ("gParams".into(), params.as_entire_binding()),
            ("token_words".into(), token_buf.as_entire_binding()),
            ("hir_status".into(), hir_status_buf.as_entire_binding()),
            ("hir_kind".into(), hir_kind_buf.as_entire_binding()),
            (
                "hir_token_pos".into(),
                hir_token_pos_buf.as_entire_binding(),
            ),
            (
                "hir_token_end".into(),
                hir_token_end_buf.as_entire_binding(),
            ),
            ("visible_decl".into(), visible_decl.as_entire_binding()),
            ("visible_type".into(), visible_type.as_entire_binding()),
            (
                "type_expr_ref_tag".into(),
                type_expr_ref_tag.as_entire_binding(),
            ),
            (
                "type_expr_ref_payload".into(),
                type_expr_ref_payload.as_entire_binding(),
            ),
            (
                "type_instance_decl_token".into(),
                type_instance_decl_token.as_entire_binding(),
            ),
            (
                "type_instance_arg_start".into(),
                type_instance_arg_start.as_entire_binding(),
            ),
            (
                "type_instance_arg_count".into(),
                type_instance_arg_count.as_entire_binding(),
            ),
            (
                "type_instance_arg_ref_tag".into(),
                type_instance_arg_ref_tag.as_entire_binding(),
            ),
            (
                "type_instance_arg_ref_payload".into(),
                type_instance_arg_ref_payload.as_entire_binding(),
            ),
            (
                "name_id_by_token".into(),
                name_id_by_token.as_entire_binding(),
            ),
        ]);
    let type_match_payloads = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10m2_type_match_payloads"),
        &passes.modules_type_match_payloads.bind_group_layouts[0],
        &passes.modules_type_match_payloads.reflection,
        0,
        &type_match_payloads_resources,
    )?;
    let type_match_exprs_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("token_words".into(), token_buf.as_entire_binding()),
        ("token_count".into(), token_count_buf.as_entire_binding()),
        ("hir_status".into(), hir_status_buf.as_entire_binding()),
        ("hir_kind".into(), hir_kind_buf.as_entire_binding()),
        (
            "hir_token_pos".into(),
            hir_token_pos_buf.as_entire_binding(),
        ),
        (
            "hir_token_end".into(),
            hir_token_end_buf.as_entire_binding(),
        ),
        ("visible_decl".into(), visible_decl.as_entire_binding()),
        ("visible_type".into(), visible_type.as_entire_binding()),
        (
            "type_expr_ref_tag".into(),
            type_expr_ref_tag.as_entire_binding(),
        ),
        (
            "type_expr_ref_payload".into(),
            type_expr_ref_payload.as_entire_binding(),
        ),
        (
            "name_id_by_token".into(),
            name_id_by_token.as_entire_binding(),
        ),
        (
            "call_return_type".into(),
            call_return_type.as_entire_binding(),
        ),
        ("status".into(), status_buf.as_entire_binding()),
    ]);
    let type_match_exprs = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_10n_type_match_exprs"),
        &passes.modules_type_match_exprs.bind_group_layouts[0],
        &passes.modules_type_match_exprs.reflection,
        0,
        &type_match_exprs_resources,
    )?;
    drop(mark_resources);
    drop(scan_local_resources);
    drop(scan_apply_resources);
    drop(scatter_resources);
    drop(segment_resources);
    drop(module_resources);
    drop(module_key_resources);
    drop(import_resources);
    drop(clear_file_module_map_resources);
    drop(build_file_module_map_resources);
    drop(attach_record_modules_resources);
    drop(seed_decl_key_resources);
    drop(validate_decl_resources);
    drop(mark_decl_namespace_resources);
    drop(scatter_decl_namespace_resources);
    drop(count_import_visibility_resources);
    drop(scatter_import_visible_type_resources);
    drop(scatter_import_visible_value_resources);
    drop(build_import_visible_type_key_table_resources);
    drop(build_import_visible_value_key_table_resources);
    drop(validate_import_visible_keys_resources);
    drop(resolve_local_type_paths_resources);
    drop(resolve_local_value_paths_resources);
    drop(resolve_imported_type_paths_resources);
    drop(resolve_imported_value_paths_resources);
    drop(resolve_qualified_type_paths_resources);
    drop(resolve_qualified_value_paths_resources);
    drop(decl_core_resources);
    drop(decl_span_resources);
    drop(clear_type_path_types_resources);
    drop(project_type_paths_resources);
    drop(project_type_aliases_resources);
    drop(project_type_instances_resources);
    drop(mark_value_call_paths_resources);
    drop(project_value_paths_resources);
    drop(consume_value_calls_resources);
    drop(consume_value_consts_resources);
    drop(consume_value_enum_units_resources);
    drop(consume_value_enum_calls_resources);
    drop(bind_match_patterns_resources);
    drop(type_match_payloads_resources);
    drop(type_match_exprs_resources);
    module_key_radix_steps.push(ModuleKeyRadixStep {
        _params: decl_module_params,
    });
    module_key_radix_steps.push(ModuleKeyRadixStep {
        _params: validate_decl_params,
    });
    module_key_radix_steps.push(ModuleKeyRadixStep {
        _params: import_visibility_params,
    });

    Ok(ModulePathState {
        n_blocks,
        token_capacity,
        module_record_flag,
        import_record_flag,
        decl_record_flag,
        module_record_prefix,
        import_record_prefix,
        decl_record_prefix,
        record_scan_local_prefix,
        record_scan_block_sum,
        record_scan_prefix_a,
        record_scan_prefix_b,
        module_count_out,
        import_count_out,
        decl_count_out,
        module_file_id,
        module_path_id,
        module_owner_hir,
        module_status,
        module_key_segment_count,
        module_key_segment_base,
        module_key_segment_name_id,
        module_key_to_module_id,
        module_key_order_tmp,
        module_key_radix_block_histogram,
        module_key_radix_block_bucket_prefix,
        module_key_radix_bucket_total,
        module_key_radix_bucket_base,
        module_id_by_file_id,
        import_module_file_id,
        import_path_id,
        import_kind,
        import_owner_hir,
        import_module_id,
        import_target_module_id,
        import_status,
        decl_module_file_id,
        decl_module_id,
        decl_name_token,
        decl_name_id,
        decl_kind,
        decl_namespace,
        decl_visibility,
        decl_hir_node,
        decl_parent_type_decl,
        decl_token_start,
        decl_token_end,
        decl_key_to_decl_id,
        decl_key_order_tmp,
        decl_key_radix_block_histogram,
        decl_key_radix_block_bucket_prefix,
        decl_key_radix_bucket_total,
        decl_key_radix_bucket_base,
        decl_status,
        decl_duplicate_of,
        decl_type_key_flag,
        decl_value_key_flag,
        decl_type_key_prefix,
        decl_value_key_prefix,
        decl_type_key_count_out,
        decl_value_key_count_out,
        decl_type_key_to_decl_id,
        decl_value_key_to_decl_id,
        import_visible_type_count,
        import_visible_value_count,
        import_visible_type_prefix,
        import_visible_value_prefix,
        import_visible_type_count_out,
        import_visible_value_count_out,
        import_visible_type_module_id,
        import_visible_type_name_id,
        import_visible_type_decl_id,
        import_visible_type_key_order,
        import_visible_type_key_order_tmp,
        import_visible_type_key_module_id,
        import_visible_type_key_name_id,
        import_visible_type_key_to_decl_id,
        import_visible_type_status,
        import_visible_type_duplicate_of,
        import_visible_value_module_id,
        import_visible_value_name_id,
        import_visible_value_decl_id,
        import_visible_value_key_order,
        import_visible_value_key_order_tmp,
        import_visible_value_key_module_id,
        import_visible_value_key_name_id,
        import_visible_value_key_to_decl_id,
        import_visible_value_status,
        import_visible_value_duplicate_of,
        import_visible_key_radix_block_histogram,
        import_visible_key_radix_block_bucket_prefix,
        import_visible_key_radix_bucket_total,
        import_visible_key_radix_bucket_base,
        resolved_type_decl,
        resolved_value_decl,
        resolved_type_status,
        resolved_value_status,
        path_record_flag,
        path_record_kind,
        path_record_prefix,
        path_scan_local_prefix,
        path_scan_block_sum,
        path_scan_prefix_a,
        path_scan_prefix_b,
        path_start,
        path_len,
        path_segment_count,
        path_segment_base,
        path_segment_name_id,
        path_segment_token,
        path_owner_hir,
        path_owner_token,
        path_owner_module_id,
        path_kind,
        path_count_out,
        scan_steps,
        record_scan_steps,
        module_key_radix_steps,
        bind_groups: ModulePathBindGroups {
            mark_records,
            scan_local,
            scan_blocks,
            scan_apply,
            scatter_paths,
            scatter_path_segments,
            module_scan,
            import_scan,
            decl_scan,
            scatter_module_records,
            scatter_import_records,
            scatter_decl_core_records,
            scatter_decl_span_records,
            build_module_keys,
            sort_module_key_histogram,
            sort_module_key_bucket_prefix,
            sort_module_key_bucket_bases,
            sort_module_key_scatter,
            validate_modules,
            resolve_imports,
            clear_file_module_map,
            build_file_module_map,
            attach_record_modules,
            seed_decl_key_order,
            sort_decl_key_histogram,
            sort_decl_key_bucket_prefix,
            sort_decl_key_bucket_bases,
            sort_decl_key_scatter,
            validate_decls,
            mark_decl_namespace_keys,
            decl_type_key_scan,
            decl_value_key_scan,
            scatter_decl_namespace_keys,
            count_import_visibility,
            import_visible_type_scan,
            import_visible_value_scan,
            scatter_import_visible_type,
            scatter_import_visible_value,
            sort_import_visible_type_key_histogram,
            sort_import_visible_type_key_bucket_prefix,
            sort_import_visible_type_key_bucket_bases,
            sort_import_visible_type_key_scatter,
            sort_import_visible_value_key_histogram,
            sort_import_visible_value_key_bucket_prefix,
            sort_import_visible_value_key_bucket_bases,
            sort_import_visible_value_key_scatter,
            build_import_visible_type_key_table,
            build_import_visible_value_key_table,
            validate_import_visible_keys,
            resolve_local_type_paths,
            resolve_local_value_paths,
            resolve_imported_type_paths,
            resolve_imported_value_paths,
            resolve_qualified_type_paths,
            resolve_qualified_value_paths,
            clear_type_path_types,
            project_type_paths,
            project_type_aliases,
            project_type_instances,
            mark_value_call_paths,
            project_value_paths,
            consume_value_calls,
            consume_value_consts,
            consume_value_enum_units,
            consume_value_enum_calls,
            bind_match_patterns,
            type_match_payloads,
            type_match_exprs,
        },
    })

}
