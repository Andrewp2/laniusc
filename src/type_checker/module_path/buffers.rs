use super::{super::*, inputs::CreateInputs, layout::Layout};

pub(super) struct Buffers {
    pub(super) record_family_bits: wgpu::Buffer,
    pub(super) record_family_flag: wgpu::Buffer,
    pub(super) module_record_flag: wgpu::Buffer,
    pub(super) import_record_flag: wgpu::Buffer,
    pub(super) decl_record_flag: wgpu::Buffer,
    pub(super) path_record_flag: wgpu::Buffer,
    pub(super) module_record_prefix: wgpu::Buffer,
    pub(super) import_record_prefix: wgpu::Buffer,
    pub(super) decl_record_prefix: wgpu::Buffer,
    pub(super) record_scan_local_prefix: wgpu::Buffer,
    pub(super) record_scan_block_sum: wgpu::Buffer,
    pub(super) record_scan_prefix_a: wgpu::Buffer,
    pub(super) record_scan_prefix_b: wgpu::Buffer,
    pub(super) module_count_out: wgpu::Buffer,
    pub(super) module_table_count_out: wgpu::Buffer,
    pub(super) import_count_out: wgpu::Buffer,
    pub(super) decl_count_out: wgpu::Buffer,
    pub(super) module_file_id: wgpu::Buffer,
    pub(super) module_path_id: wgpu::Buffer,
    pub(super) module_owner_hir: wgpu::Buffer,
    pub(super) module_status: wgpu::Buffer,
    pub(super) module_key_segment_count: wgpu::Buffer,
    pub(super) module_key_segment_base: wgpu::Buffer,
    pub(super) module_key_segment_name_id: wgpu::Buffer,
    pub(super) module_key_to_module_id: wgpu::Buffer,
    pub(super) module_key_order_tmp: wgpu::Buffer,
    pub(super) module_key_radix_dispatch_args: wgpu::Buffer,
    pub(super) module_key_radix_block_histogram: wgpu::Buffer,
    pub(super) module_key_radix_block_bucket_prefix: wgpu::Buffer,
    pub(super) module_key_radix_bucket_total: wgpu::Buffer,
    pub(super) module_key_radix_bucket_base: wgpu::Buffer,
    pub(super) module_id_by_file_id: wgpu::Buffer,
    pub(super) import_module_file_id: wgpu::Buffer,
    pub(super) import_path_id: wgpu::Buffer,
    pub(super) import_kind: wgpu::Buffer,
    pub(super) import_owner_hir: wgpu::Buffer,
    pub(super) import_module_id: wgpu::Buffer,
    pub(super) import_target_module_id: wgpu::Buffer,
    pub(super) import_status: wgpu::Buffer,
    pub(super) import_edge_key_order: wgpu::Buffer,
    pub(super) import_edge_key_order_tmp: wgpu::Buffer,
    pub(super) import_edge_key_radix_dispatch_args: wgpu::Buffer,
    pub(super) decl_module_file_id: wgpu::Buffer,
    pub(super) decl_module_id: wgpu::Buffer,
    pub(super) decl_name_token: wgpu::Buffer,
    pub(super) decl_id_by_name_token: wgpu::Buffer,
    pub(super) decl_name_id: wgpu::Buffer,
    pub(super) decl_kind: wgpu::Buffer,
    pub(super) decl_namespace: wgpu::Buffer,
    pub(super) decl_visibility: wgpu::Buffer,
    pub(super) decl_hir_node: wgpu::Buffer,
    pub(super) decl_parent_type_decl: wgpu::Buffer,
    pub(super) decl_token_start: wgpu::Buffer,
    pub(super) decl_token_end: wgpu::Buffer,
    pub(super) decl_key_to_decl_id: wgpu::Buffer,
    pub(super) decl_key_order_tmp: wgpu::Buffer,
    pub(super) decl_key_radix_dispatch_args: wgpu::Buffer,
    pub(super) decl_key_radix_block_histogram: wgpu::Buffer,
    pub(super) decl_key_radix_block_bucket_prefix: wgpu::Buffer,
    pub(super) decl_key_radix_bucket_total: wgpu::Buffer,
    pub(super) decl_key_radix_bucket_base: wgpu::Buffer,
    pub(super) decl_status: wgpu::Buffer,
    pub(super) decl_duplicate_of: wgpu::Buffer,
    pub(super) decl_type_key_flag: wgpu::Buffer,
    pub(super) decl_value_key_flag: wgpu::Buffer,
    pub(super) decl_type_key_prefix: wgpu::Buffer,
    pub(super) decl_value_key_prefix: wgpu::Buffer,
    pub(super) decl_type_key_count_out: wgpu::Buffer,
    pub(super) decl_value_key_count_out: wgpu::Buffer,
    pub(super) decl_type_key_to_decl_id: wgpu::Buffer,
    pub(super) decl_value_key_to_decl_id: wgpu::Buffer,
    pub(super) import_visible_type_count: wgpu::Buffer,
    pub(super) import_visible_value_count: wgpu::Buffer,
    pub(super) import_visible_type_prefix: wgpu::Buffer,
    pub(super) import_visible_value_prefix: wgpu::Buffer,
    pub(super) import_visible_type_count_out: wgpu::Buffer,
    pub(super) import_visible_value_count_out: wgpu::Buffer,
    pub(super) import_visible_type_module_id: wgpu::Buffer,
    pub(super) import_visible_type_name_id: wgpu::Buffer,
    pub(super) import_visible_type_decl_id: wgpu::Buffer,
    pub(super) import_visible_type_key_order: wgpu::Buffer,
    pub(super) import_visible_type_key_order_tmp: wgpu::Buffer,
    pub(super) import_visible_type_key_module_id: wgpu::Buffer,
    pub(super) import_visible_type_key_name_id: wgpu::Buffer,
    pub(super) import_visible_type_key_to_decl_id: wgpu::Buffer,
    pub(super) import_visible_type_status: wgpu::Buffer,
    pub(super) import_visible_type_duplicate_of: wgpu::Buffer,
    pub(super) import_visible_type_key_radix_dispatch_args: wgpu::Buffer,
    pub(super) import_visible_value_module_id: wgpu::Buffer,
    pub(super) import_visible_value_name_id: wgpu::Buffer,
    pub(super) import_visible_value_decl_id: wgpu::Buffer,
    pub(super) import_visible_value_key_order: wgpu::Buffer,
    pub(super) import_visible_value_key_order_tmp: wgpu::Buffer,
    pub(super) import_visible_value_key_module_id: wgpu::Buffer,
    pub(super) import_visible_value_key_name_id: wgpu::Buffer,
    pub(super) import_visible_value_key_to_decl_id: wgpu::Buffer,
    pub(super) import_visible_value_status: wgpu::Buffer,
    pub(super) import_visible_value_duplicate_of: wgpu::Buffer,
    pub(super) import_visible_value_key_radix_dispatch_args: wgpu::Buffer,
    pub(super) import_visible_validate_dispatch_args: wgpu::Buffer,
    pub(super) import_visible_key_radix_block_histogram: wgpu::Buffer,
    pub(super) import_visible_key_radix_block_bucket_prefix: wgpu::Buffer,
    pub(super) import_visible_key_radix_bucket_total: wgpu::Buffer,
    pub(super) import_visible_key_radix_bucket_base: wgpu::Buffer,
    pub(super) resolved_type_decl: wgpu::Buffer,
    pub(super) resolved_value_decl: wgpu::Buffer,
    pub(super) resolved_type_status: wgpu::Buffer,
    pub(super) resolved_value_status: wgpu::Buffer,
    pub(super) path_record_prefix: wgpu::Buffer,
    pub(super) path_scan_local_prefix: wgpu::Buffer,
    pub(super) path_scan_block_sum: wgpu::Buffer,
    pub(super) path_scan_prefix_a: wgpu::Buffer,
    pub(super) path_scan_prefix_b: wgpu::Buffer,
    pub(super) path_start: wgpu::Buffer,
    pub(super) path_len: wgpu::Buffer,
    pub(super) path_segment_count: wgpu::Buffer,
    pub(super) path_segment_base: wgpu::Buffer,
    pub(super) path_segment_name_id: wgpu::Buffer,
    pub(super) path_segment_token: wgpu::Buffer,
    pub(super) path_segment_count_out: wgpu::Buffer,
    pub(super) path_owner_hir: wgpu::Buffer,
    pub(super) path_owner_token: wgpu::Buffer,
    pub(super) path_id_by_owner_hir: wgpu::Buffer,
    pub(super) path_owner_module_id: wgpu::Buffer,
    pub(super) path_kind: wgpu::Buffer,
    pub(super) path_count_out: wgpu::Buffer,
    pub(super) path_dispatch_args: wgpu::Buffer,
    pub(super) path_segment_dispatch_args: wgpu::Buffer,
    pub(super) import_dispatch_args: wgpu::Buffer,
    pub(super) scan_steps: Vec<NameScanStep>,
    pub(super) record_scan_steps: Vec<NameScanStep>,
}

impl Buffers {
    pub(super) fn new(device: &wgpu::Device, layout: Layout, inputs: &CreateInputs<'_>) -> Self {
        let Layout {
            n_blocks,
            record_capacity,
            record_capacity_u32,
            record_n_blocks,
            module_capacity,
            import_record_capacity,
            import_visible_capacity,
            key_radix_histogram_len,
            ..
        } = layout;
        let hir_node_capacity = inputs.hir_node_capacity;
        let token_capacity = inputs.token_capacity;
        let external = inputs.external_scratch;
        let scan_params = NameScanParams {
            n_items: hir_node_capacity,
            n_blocks,
            scan_step: 0,
        };
        let scan_steps = make_name_scan_steps(device, scan_params);
        let record_scan_params = NameScanParams {
            n_items: record_capacity_u32,
            n_blocks: record_n_blocks,
            scan_step: 0,
        };
        let record_scan_steps = make_name_scan_steps(device, record_scan_params);
        // Module/path family bits are dead before type-instance passes reuse this
        // HIR-indexed storage for const-generic declaration counts and, later,
        // function entrypoint tags.
        let record_family_bits = alias_storage_buffer(inputs.record_family_bits_scratch);
        // Record-family flags feed module/path scans and resident visible-decl
        // scans. Struct-init by-node ordinals are recorded later, after those scans.
        let record_family_flag = alias_storage_buffer(inputs.record_family_flag_scratch);
        let module_record_flag = alias_storage_buffer(&record_family_flag);
        let import_record_flag = alias_storage_buffer(&record_family_flag);
        let decl_record_flag = alias_storage_buffer(&record_family_flag);
        let path_record_flag = alias_storage_buffer(&record_family_flag);
        // Parser list-workspace buffers are dead before typecheck starts. Use one
        // as shared HIR-keyed module/import/decl/path prefix scratch instead of
        // allocating a second max-capacity buffer.
        let module_record_prefix = alias_or_storage_u32(
            device,
            "type_check.resident.module_record_prefix",
            hir_node_capacity as usize,
            external.map(|scratch| scratch.module_record_prefix),
        );
        // Module, import, and declaration record prefixes are consumed by their
        // scatter passes before the next record-family scan runs, so one prefix
        // buffer is enough.
        let import_record_prefix = alias_storage_buffer(&module_record_prefix);
        let decl_record_prefix = alias_storage_buffer(&module_record_prefix);
        // The counted-scan local prefix is scratch for module/path and visible
        // declaration scans. Reuse a dead parser list-workspace buffer.
        let record_scan_local_prefix = alias_or_storage_u32(
            device,
            "type_check.resident.record_scan_local_prefix",
            hir_node_capacity as usize,
            external.map(|scratch| scratch.record_scan_local_prefix),
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
        // Module/import/decl key radix histograms are phase-local scratch. Borrow
        // dead parser delimiter workspaces when they are large enough; very small
        // tests still need the 256-bucket minimum allocation.
        let key_radix_block_histogram = reuse_storage_u32(
            device,
            "type_check.resident.module_path_key_radix_block_histogram",
            key_radix_histogram_len,
            external.map(|scratch| scratch.module_path_key_radix_block_histogram),
        );
        let key_radix_block_bucket_prefix = reuse_storage_u32(
            device,
            "type_check.resident.module_path_key_radix_block_bucket_prefix",
            key_radix_histogram_len,
            external.map(|scratch| scratch.module_path_key_radix_block_bucket_prefix),
        );
        let key_radix_bucket_total = storage_u32_rw(
            device,
            "type_check.resident.module_path_key_radix_bucket_total",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let key_radix_bucket_base = storage_u32_rw(
            device,
            "type_check.resident.module_path_key_radix_bucket_base",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_count_out = storage_u32_rw(
            device,
            "type_check.resident.module_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let module_table_count_out = storage_u32_fill_rw(
            device,
            "type_check.resident.module_table_count_out",
            1,
            layout.module_capacity_u32,
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
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_path_id = storage_u32_rw(
            device,
            "type_check.resident.module_path_id",
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_owner_hir = storage_u32_rw(
            device,
            "type_check.resident.module_owner_hir",
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_status = storage_u32_rw(
            device,
            "type_check.resident.module_status",
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_key_segment_count = storage_u32_rw(
            device,
            "type_check.resident.module_key_segment_count",
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_key_segment_base = storage_u32_rw(
            device,
            "type_check.resident.module_key_segment_base",
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_key_segment_capacity = module_capacity
            .max(1)
            .saturating_mul(MODULE_KEY_SEGMENT_ROW_WIDTH);
        let module_key_segment_name_id = storage_u32_rw(
            device,
            "type_check.resident.module_key_segment_name_id",
            module_key_segment_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_key_to_module_id = storage_u32_rw(
            device,
            "type_check.resident.module_key_to_module_id",
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_key_order_tmp = storage_u32_rw(
            device,
            "type_check.resident.module_key_order_tmp",
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_key_radix_dispatch_args = storage_u32_rw(
            device,
            "type_check.resident.module_key_radix_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let module_key_radix_block_histogram = alias_storage_buffer(&key_radix_block_histogram);
        let module_key_radix_block_bucket_prefix =
            alias_storage_buffer(&key_radix_block_bucket_prefix);
        let module_key_radix_bucket_total = alias_storage_buffer(&key_radix_bucket_total);
        let module_key_radix_bucket_base = alias_storage_buffer(&key_radix_bucket_base);
        let module_id_by_file_id = storage_u32_rw(
            device,
            "type_check.resident.module_id_by_file_id",
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_module_file_id = storage_u32_rw(
            device,
            "type_check.resident.import_module_file_id",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_path_id = storage_u32_rw(
            device,
            "type_check.resident.import_path_id",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_kind = storage_u32_rw(
            device,
            "type_check.resident.import_kind",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_owner_hir = storage_u32_rw(
            device,
            "type_check.resident.import_owner_hir",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_module_id = storage_u32_rw(
            device,
            "type_check.resident.import_module_id",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_target_module_id = storage_u32_rw(
            device,
            "type_check.resident.import_target_module_id",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_status = storage_u32_rw(
            device,
            "type_check.resident.import_status",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_edge_key_order = storage_u32_rw(
            device,
            "type_check.resident.import_edge_key_order",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_edge_key_order_tmp = storage_u32_rw(
            device,
            "type_check.resident.import_edge_key_order_tmp",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_edge_key_radix_dispatch_args = storage_u32_rw(
            device,
            "type_check.resident.import_edge_key_radix_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        // Declaration tables are retained through module/path resolution, but they
        // are not part of the x86 handoff. Use parser token/tree workspaces that
        // are dead after HIR construction.
        let decl_module_file_id = reuse_storage_u32(
            device,
            "type_check.resident.decl_module_file_id",
            record_capacity,
            external.map(|scratch| scratch.decl_module_file_id),
        );
        let decl_module_id = storage_u32_rw(
            device,
            "type_check.resident.decl_module_id",
            record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let decl_name_id = reuse_storage_u32(
            device,
            "type_check.resident.decl_name_id",
            record_capacity,
            external.map(|scratch| scratch.decl_name_id),
        );
        // Name-radix scratch is dead before module/path recording runs. These
        // declaration metadata buffers are retained for x86, so keep them in
        // typechecker-owned scratch rather than parser scratch that backend passes
        // may later borrow for their own phase-local work.
        let decl_name_token = reuse_storage_u32(
            device,
            "type_check.resident.decl_name_token",
            record_capacity,
            Some(inputs.decl_name_token_scratch),
        );
        let decl_id_by_name_token = reuse_storage_u32(
            device,
            "type_check.resident.decl_id_by_name_token",
            token_capacity.max(1) as usize,
            Some(inputs.decl_id_by_name_token_scratch),
        );
        let decl_kind = reuse_storage_u32(
            device,
            "type_check.resident.decl_kind",
            record_capacity,
            Some(inputs.decl_kind_scratch),
        );
        let decl_namespace = reuse_storage_u32(
            device,
            "type_check.resident.decl_namespace",
            record_capacity,
            external.map(|scratch| scratch.decl_namespace),
        );
        let decl_visibility = reuse_storage_u32(
            device,
            "type_check.resident.decl_visibility",
            record_capacity,
            external.map(|scratch| scratch.decl_visibility),
        );
        let decl_hir_node = reuse_storage_u32(
            device,
            "type_check.resident.decl_hir_node",
            record_capacity,
            Some(inputs.decl_hir_node_scratch),
        );
        let decl_parent_type_decl = reuse_storage_u32(
            device,
            "type_check.resident.decl_parent_type_decl",
            record_capacity,
            Some(inputs.decl_parent_type_decl_scratch),
        );
        let decl_token_start = reuse_storage_u32(
            device,
            "type_check.resident.decl_token_start",
            record_capacity,
            external.map(|scratch| scratch.decl_token_start),
        );
        let decl_token_end = reuse_storage_u32(
            device,
            "type_check.resident.decl_token_end",
            record_capacity,
            external.map(|scratch| scratch.decl_token_end),
        );
        let decl_key_to_decl_id = reuse_storage_u32(
            device,
            "type_check.resident.decl_key_to_decl_id",
            record_capacity,
            external.map(|scratch| scratch.decl_key_to_decl_id),
        );
        let decl_key_order_tmp = reuse_storage_u32(
            device,
            "type_check.resident.decl_key_order_tmp",
            record_capacity,
            external.map(|scratch| scratch.decl_key_order_tmp),
        );
        let decl_key_radix_dispatch_args = storage_u32_rw(
            device,
            "type_check.resident.decl_key_radix_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let decl_key_radix_block_histogram = alias_storage_buffer(&key_radix_block_histogram);
        let decl_key_radix_block_bucket_prefix =
            alias_storage_buffer(&key_radix_block_bucket_prefix);
        let decl_key_radix_bucket_total = alias_storage_buffer(&key_radix_bucket_total);
        let decl_key_radix_bucket_base = alias_storage_buffer(&key_radix_bucket_base);
        let decl_status = reuse_storage_u32(
            device,
            "type_check.resident.decl_status",
            record_capacity,
            external.map(|scratch| scratch.decl_status),
        );
        // Duplicate rows are consumed before type-instance passes populate the
        // HIR-keyed generic-param count table.
        let decl_duplicate_of = alias_or_storage_u32(
            device,
            "type_check.resident.decl_duplicate_of",
            record_capacity,
            external.map(|scratch| scratch.type_decl_generic_param_count_by_node),
        );
        // Declaration namespace/public flags are consumed during module-path
        // visibility setup, before type-instance argument tag/payload tables are
        // written by later typecheck passes.
        let decl_type_key_flag = alias_or_storage_u32(
            device,
            "type_check.resident.decl_type_key_flag",
            record_capacity,
            external.map(|scratch| scratch.type_instance_arg_ref_tag),
        );
        let decl_value_key_flag = alias_or_storage_u32(
            device,
            "type_check.resident.decl_value_key_flag",
            record_capacity,
            external.map(|scratch| scratch.type_instance_arg_ref_payload),
        );
        // Declaration key prefixes are consumed before import-visible key scans
        // populate their prefixes, so both families can share the same external
        // token-capacity prefix workspaces.
        let decl_type_key_prefix = alias_or_storage_u32(
            device,
            "type_check.resident.decl_type_key_prefix",
            record_capacity,
            external.map(|scratch| scratch.import_visible_type_prefix),
        );
        let decl_value_key_prefix = alias_or_storage_u32(
            device,
            "type_check.resident.decl_value_key_prefix",
            record_capacity,
            external.map(|scratch| scratch.import_visible_value_prefix),
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
        // Type declaration-key lookup is retained by module/path consumers, but
        // lexer DFA summary scratch is dead after tokenization and is not part of
        // the typecheck or x86 input surface.
        let decl_type_key_to_decl_id = alias_or_storage_u32(
            device,
            "type_check.resident.decl_type_key_to_decl_id",
            record_capacity,
            external.map(|scratch| scratch.decl_type_key_to_decl_id),
        );
        // Module-path value-key lookup is consumed inside typecheck and is not
        // retained by the x86 handoff. Reuse dead parser list-workspace rows.
        let decl_value_key_to_decl_id = alias_or_storage_u32(
            device,
            "type_check.resident.decl_value_key_to_decl_id",
            record_capacity,
            external.map(|scratch| scratch.decl_value_key_to_decl_id),
        );
        let import_visible_type_count = alias_or_storage_u32(
            device,
            "type_check.resident.import_visible_type_count",
            record_capacity,
            external.map(|scratch| scratch.import_visible_type_count),
        );
        let import_visible_value_count = alias_or_storage_u32(
            device,
            "type_check.resident.import_visible_value_count",
            record_capacity,
            external.map(|scratch| scratch.import_visible_value_count),
        );
        let import_visible_type_prefix = alias_or_storage_u32(
            device,
            "type_check.resident.import_visible_type_prefix",
            record_capacity,
            external.map(|scratch| scratch.import_visible_type_prefix),
        );
        let import_visible_value_prefix = alias_or_storage_u32(
            device,
            "type_check.resident.import_visible_value_prefix",
            record_capacity,
            external.map(|scratch| scratch.import_visible_value_prefix),
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
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_name_id = storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_name_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_decl_id = storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_decl_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_key_order = storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_key_order",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_key_order_tmp = storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_key_order_tmp",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_key_module_id = storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_key_module_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_key_name_id = storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_key_name_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_key_to_decl_id = storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_key_to_decl_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_status = storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_status",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_duplicate_of = storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_duplicate_of",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_key_radix_dispatch_args = storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_key_radix_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let import_visible_value_module_id = storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_module_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_name_id = storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_name_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_decl_id = storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_decl_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_key_order = storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_key_order",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_key_order_tmp = storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_key_order_tmp",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_key_module_id = storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_key_module_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_key_name_id = storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_key_name_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_key_to_decl_id = storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_key_to_decl_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_status = storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_status",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_duplicate_of = storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_duplicate_of",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_key_radix_dispatch_args = storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_key_radix_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let import_visible_validate_dispatch_args = storage_u32_rw(
            device,
            "type_check.resident.import_visible_validate_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let import_visible_key_radix_block_histogram =
            alias_storage_buffer(&key_radix_block_histogram);
        let import_visible_key_radix_block_bucket_prefix =
            alias_storage_buffer(&key_radix_block_bucket_prefix);
        let import_visible_key_radix_bucket_total = alias_storage_buffer(&key_radix_bucket_total);
        let import_visible_key_radix_bucket_base = alias_storage_buffer(&key_radix_bucket_base);
        let resolved_type_decl = alias_or_storage_u32(
            device,
            "type_check.resident.resolved_type_decl",
            record_capacity,
            external.map(|scratch| scratch.resolved_type_decl),
        );
        let resolved_value_decl = alias_or_storage_u32(
            device,
            "type_check.resident.resolved_value_decl",
            record_capacity,
            external.map(|scratch| scratch.resolved_value_decl),
        );
        let resolved_type_status = alias_or_storage_u32(
            device,
            "type_check.resident.resolved_type_status",
            record_capacity,
            external.map(|scratch| scratch.resolved_type_status),
        );
        let resolved_value_status = alias_or_storage_u32(
            device,
            "type_check.resident.resolved_value_status",
            record_capacity,
            external.map(|scratch| scratch.resolved_value_status),
        );
        // Path prefixes are only needed until path records have been scattered.
        // Later module/import scatters read the retained path_id_by_owner_hir table,
        // so this prefix can share the module/import/decl prefix scratch.
        let path_record_prefix = alias_storage_buffer(&module_record_prefix);
        let path_scan_local_prefix = alias_storage_buffer(&record_scan_local_prefix);
        let path_scan_block_sum = alias_storage_buffer(&record_scan_block_sum);
        let path_scan_prefix_a = alias_storage_buffer(&record_scan_prefix_a);
        let path_scan_prefix_b = alias_storage_buffer(&record_scan_prefix_b);
        let path_start = alias_or_storage_u32(
            device,
            "type_check.resident.path_start",
            record_capacity,
            external.map(|scratch| scratch.path_start),
        );
        let path_len = alias_or_storage_u32(
            device,
            "type_check.resident.path_len",
            record_capacity,
            external.map(|scratch| scratch.path_len),
        );
        let path_segment_count = alias_or_storage_u32(
            device,
            "type_check.resident.path_segment_count",
            record_capacity,
            external.map(|scratch| scratch.path_segment_count),
        );
        let path_segment_base = alias_or_storage_u32(
            device,
            "type_check.resident.path_segment_base",
            record_capacity,
            external.map(|scratch| scratch.path_segment_base),
        );
        let path_segment_capacity = token_capacity.max(1) as usize;
        let path_segment_name_id = alias_or_storage_u32(
            device,
            "type_check.resident.path_segment_name_id",
            path_segment_capacity,
            external.map(|scratch| scratch.path_segment_name_id),
        );
        let path_segment_token = alias_or_storage_u32(
            device,
            "type_check.resident.path_segment_token",
            path_segment_capacity,
            external.map(|scratch| scratch.path_segment_token),
        );
        let path_segment_count_out = storage_u32_rw(
            device,
            "type_check.resident.path_segment_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let path_owner_hir = alias_or_storage_u32(
            device,
            "type_check.resident.path_owner_hir",
            record_capacity,
            external.map(|scratch| scratch.path_owner_hir),
        );
        let path_owner_token = alias_or_storage_u32(
            device,
            "type_check.resident.path_owner_token",
            record_capacity,
            external.map(|scratch| scratch.path_owner_token),
        );
        // Path ids are retained for later typecheck and x86 lowering, but the
        // parser list workspace is no longer read after HIR construction, so it
        // can carry this owner-HIR map.
        let path_id_by_owner_hir = alias_or_storage_u32(
            device,
            "type_check.resident.path_id_by_owner_hir",
            hir_node_capacity.max(1) as usize,
            external.map(|scratch| scratch.path_id_by_owner_hir),
        );
        let path_owner_module_id = alias_or_storage_u32(
            device,
            "type_check.resident.path_owner_module_id",
            record_capacity,
            external.map(|scratch| scratch.path_owner_module_id),
        );
        let path_kind = alias_or_storage_u32(
            device,
            "type_check.resident.path_kind",
            record_capacity,
            external.map(|scratch| scratch.path_kind),
        );
        let path_count_out = storage_u32_rw(
            device,
            "type_check.resident.path_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let path_dispatch_args = storage_u32_rw(
            device,
            "type_check.resident.path_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let path_segment_dispatch_args = storage_u32_rw(
            device,
            "type_check.resident.path_segment_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let import_dispatch_args = storage_u32_rw(
            device,
            "type_check.resident.import_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );

        Self {
            record_family_bits,
            record_family_flag,
            module_record_flag,
            import_record_flag,
            decl_record_flag,
            path_record_flag,
            module_record_prefix,
            import_record_prefix,
            decl_record_prefix,
            record_scan_local_prefix,
            record_scan_block_sum,
            record_scan_prefix_a,
            record_scan_prefix_b,
            module_count_out,
            module_table_count_out,
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
            module_key_radix_dispatch_args,
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
            import_edge_key_order,
            import_edge_key_order_tmp,
            import_edge_key_radix_dispatch_args,
            decl_module_file_id,
            decl_module_id,
            decl_name_token,
            decl_id_by_name_token,
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
            decl_key_radix_dispatch_args,
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
            import_visible_type_key_radix_dispatch_args,
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
            import_visible_value_key_radix_dispatch_args,
            import_visible_validate_dispatch_args,
            import_visible_key_radix_block_histogram,
            import_visible_key_radix_block_bucket_prefix,
            import_visible_key_radix_bucket_total,
            import_visible_key_radix_bucket_base,
            resolved_type_decl,
            resolved_value_decl,
            resolved_type_status,
            resolved_value_status,
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
            path_segment_count_out,
            path_owner_hir,
            path_owner_token,
            path_id_by_owner_hir,
            path_owner_module_id,
            path_kind,
            path_count_out,
            path_dispatch_args,
            path_segment_dispatch_args,
            import_dispatch_args,
            scan_steps,
            record_scan_steps,
        }
    }
}
