use super::{super::*, inputs::CreateInputs, layout::Layout};

/// Owned resident buffers for module/path relations before bind-group assembly.
///
/// `State` keeps these buffers alive after construction; this intermediate
/// owner lets creation code wire discovery, indexing, declaration, and
/// projection bind groups without exposing raw allocation details.
pub(super) struct Buffers {
    pub(super) record_family_bits: LaniusBuffer<u32>,
    pub(super) record_family_flag: LaniusBuffer<u32>,
    pub(super) module_record_flag: LaniusBuffer<u32>,
    pub(super) import_record_flag: LaniusBuffer<u32>,
    pub(super) decl_record_flag: LaniusBuffer<u32>,
    pub(super) path_record_flag: LaniusBuffer<u32>,
    pub(super) module_record_prefix: LaniusBuffer<u32>,
    pub(super) import_record_prefix: LaniusBuffer<u32>,
    pub(super) decl_record_prefix: LaniusBuffer<u32>,
    pub(super) record_scan_local_prefix: LaniusBuffer<u32>,
    pub(super) record_scan_block_sum: LaniusBuffer<u32>,
    pub(super) record_scan_prefix_a: LaniusBuffer<u32>,
    pub(super) record_scan_prefix_b: LaniusBuffer<u32>,
    pub(super) module_count_out: LaniusBuffer<u32>,
    pub(super) module_table_count_out: LaniusBuffer<u32>,
    pub(super) import_count_out: LaniusBuffer<u32>,
    pub(super) decl_count_out: LaniusBuffer<u32>,
    pub(super) module_file_id: LaniusBuffer<u32>,
    pub(super) module_path_id: LaniusBuffer<u32>,
    pub(super) module_owner_hir: LaniusBuffer<u32>,
    pub(super) module_status: LaniusBuffer<u32>,
    pub(super) module_key_segment_count: LaniusBuffer<u32>,
    pub(super) module_key_segment_base: LaniusBuffer<u32>,
    pub(super) module_key_segment_name_id: LaniusBuffer<u32>,
    pub(super) module_key_to_module_id: LaniusBuffer<u32>,
    pub(super) module_key_order_tmp: LaniusBuffer<u32>,
    pub(super) module_key_radix_dispatch_args: LaniusBuffer<u32>,
    pub(super) module_key_radix_block_histogram: LaniusBuffer<u32>,
    pub(super) module_key_radix_block_bucket_prefix: LaniusBuffer<u32>,
    pub(super) module_key_radix_bucket_total: LaniusBuffer<u32>,
    pub(super) module_key_radix_bucket_base: LaniusBuffer<u32>,
    pub(super) module_id_by_file_id: LaniusBuffer<u32>,
    pub(super) import_module_file_id: LaniusBuffer<u32>,
    pub(super) import_path_id: LaniusBuffer<u32>,
    pub(super) import_kind: LaniusBuffer<u32>,
    pub(super) import_owner_hir: LaniusBuffer<u32>,
    pub(super) import_module_id: LaniusBuffer<u32>,
    pub(super) import_target_module_id: LaniusBuffer<u32>,
    pub(super) import_target_dependency_module_id: Option<LaniusBuffer<u32>>,
    pub(super) import_status: LaniusBuffer<u32>,
    pub(super) import_edge_key_order: LaniusBuffer<u32>,
    pub(super) import_edge_key_order_tmp: LaniusBuffer<u32>,
    pub(super) import_edge_key_radix_dispatch_args: LaniusBuffer<u32>,
    pub(super) decl_module_file_id: LaniusBuffer<u32>,
    pub(super) decl_module_id: LaniusBuffer<u32>,
    pub(super) decl_name_token: LaniusBuffer<u32>,
    pub(super) decl_id_by_name_token: LaniusBuffer<u32>,
    pub(super) decl_name_id: LaniusBuffer<u32>,
    pub(super) decl_kind: LaniusBuffer<u32>,
    pub(super) decl_namespace: LaniusBuffer<u32>,
    pub(super) decl_visibility: LaniusBuffer<u32>,
    pub(super) decl_hir_node: LaniusBuffer<u32>,
    pub(super) decl_parent_type_decl: LaniusBuffer<u32>,
    pub(super) decl_token_start: LaniusBuffer<u32>,
    pub(super) decl_token_end: LaniusBuffer<u32>,
    pub(super) decl_key_to_decl_id: LaniusBuffer<u32>,
    pub(super) decl_key_order_tmp: LaniusBuffer<u32>,
    pub(super) decl_key_radix_dispatch_args: LaniusBuffer<u32>,
    pub(super) decl_key_radix_block_histogram: LaniusBuffer<u32>,
    pub(super) decl_key_radix_block_bucket_prefix: LaniusBuffer<u32>,
    pub(super) decl_key_radix_bucket_total: LaniusBuffer<u32>,
    pub(super) decl_key_radix_bucket_base: LaniusBuffer<u32>,
    pub(super) decl_status: LaniusBuffer<u32>,
    pub(super) decl_duplicate_of: LaniusBuffer<u32>,
    pub(super) decl_type_key_flag: LaniusBuffer<u32>,
    pub(super) decl_value_key_flag: LaniusBuffer<u32>,
    pub(super) decl_type_key_prefix: LaniusBuffer<u32>,
    pub(super) decl_value_key_prefix: LaniusBuffer<u32>,
    pub(super) decl_type_key_count_out: LaniusBuffer<u32>,
    pub(super) decl_value_key_count_out: LaniusBuffer<u32>,
    pub(super) decl_type_key_to_decl_id: LaniusBuffer<u32>,
    pub(super) decl_value_key_to_decl_id: LaniusBuffer<u32>,
    pub(super) interface_public_decl_count: LaniusBuffer<u32>,
    pub(super) interface_public_decl_local_id: LaniusBuffer<u32>,
    pub(super) interface_public_decl_index_by_local: LaniusBuffer<u32>,
    pub(super) interface_public_decl_index_by_hir: LaniusBuffer<u32>,
    pub(super) import_visible_type_count: LaniusBuffer<u32>,
    pub(super) import_visible_value_count: LaniusBuffer<u32>,
    pub(super) import_visible_type_prefix: LaniusBuffer<u32>,
    pub(super) import_visible_value_prefix: LaniusBuffer<u32>,
    pub(super) import_visible_type_count_out: LaniusBuffer<u32>,
    pub(super) import_visible_value_count_out: LaniusBuffer<u32>,
    pub(super) import_visible_type_module_id: LaniusBuffer<u32>,
    pub(super) import_visible_type_name_id: LaniusBuffer<u32>,
    pub(super) import_visible_type_decl_id: LaniusBuffer<u32>,
    pub(super) import_visible_type_key_order: LaniusBuffer<u32>,
    pub(super) import_visible_type_key_order_tmp: LaniusBuffer<u32>,
    pub(super) import_visible_type_key_module_id: LaniusBuffer<u32>,
    pub(super) import_visible_type_key_name_id: LaniusBuffer<u32>,
    pub(super) import_visible_type_key_to_decl_id: LaniusBuffer<u32>,
    pub(super) import_visible_type_status: LaniusBuffer<u32>,
    pub(super) import_visible_type_duplicate_of: LaniusBuffer<u32>,
    pub(super) import_visible_type_key_radix_dispatch_args: LaniusBuffer<u32>,
    pub(super) import_visible_value_module_id: LaniusBuffer<u32>,
    pub(super) import_visible_value_name_id: LaniusBuffer<u32>,
    pub(super) import_visible_value_decl_id: LaniusBuffer<u32>,
    pub(super) import_visible_value_key_order: LaniusBuffer<u32>,
    pub(super) import_visible_value_key_order_tmp: LaniusBuffer<u32>,
    pub(super) import_visible_value_key_module_id: LaniusBuffer<u32>,
    pub(super) import_visible_value_key_name_id: LaniusBuffer<u32>,
    pub(super) import_visible_value_key_to_decl_id: LaniusBuffer<u32>,
    pub(super) import_visible_value_status: LaniusBuffer<u32>,
    pub(super) import_visible_value_duplicate_of: LaniusBuffer<u32>,
    pub(super) import_visible_value_key_radix_dispatch_args: LaniusBuffer<u32>,
    pub(super) import_visible_validate_dispatch_args: LaniusBuffer<u32>,
    pub(super) import_visible_key_radix_block_histogram: LaniusBuffer<u32>,
    pub(super) import_visible_key_radix_block_bucket_prefix: LaniusBuffer<u32>,
    pub(super) import_visible_key_radix_bucket_total: LaniusBuffer<u32>,
    pub(super) import_visible_key_radix_bucket_base: LaniusBuffer<u32>,
    pub(super) resolved_type_decl: LaniusBuffer<u32>,
    pub(super) resolved_value_decl: LaniusBuffer<u32>,
    pub(super) resolved_type_status: LaniusBuffer<u32>,
    pub(super) resolved_value_status: LaniusBuffer<u32>,
    pub(super) path_record_prefix: LaniusBuffer<u32>,
    pub(super) path_scan_local_prefix: LaniusBuffer<u32>,
    pub(super) path_scan_block_sum: LaniusBuffer<u32>,
    pub(super) path_scan_prefix_a: LaniusBuffer<u32>,
    pub(super) path_scan_prefix_b: LaniusBuffer<u32>,
    pub(super) path_start: LaniusBuffer<u32>,
    pub(super) path_len: LaniusBuffer<u32>,
    pub(super) path_segment_count: LaniusBuffer<u32>,
    pub(super) path_segment_base: LaniusBuffer<u32>,
    pub(super) path_segment_name_id: LaniusBuffer<u32>,
    pub(super) path_segment_token: LaniusBuffer<u32>,
    pub(super) path_segment_count_out: LaniusBuffer<u32>,
    pub(super) path_owner_hir: LaniusBuffer<u32>,
    pub(super) path_owner_token: LaniusBuffer<u32>,
    pub(super) path_id_by_owner_hir: LaniusBuffer<u32>,
    pub(super) path_id_by_owner_token: LaniusBuffer<u32>,
    pub(super) path_owner_module_id: LaniusBuffer<u32>,
    pub(super) path_kind: LaniusBuffer<u32>,
    pub(super) path_count_out: LaniusBuffer<u32>,
    pub(super) path_dispatch_args: LaniusBuffer<u32>,
    pub(super) import_dispatch_args: LaniusBuffer<u32>,
    pub(super) scan_steps: Vec<NameScanStep>,
    pub(super) record_scan_steps: Vec<NameScanStep>,
}

impl Buffers {
    /// Allocates module/path storage and aliases dead scratch buffers where safe.
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
        let retained_path_external = inputs.external_scratch;
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
        let record_family_bits = typed_alias_storage_u32(
            inputs.record_family_bits_scratch,
            hir_node_capacity.max(1) as usize,
        );
        // Record-family flags feed module/path scans and resident visible-decl
        // scans. Struct-init by-node ordinals are recorded later, after those scans.
        let record_family_flag = typed_alias_storage_u32(
            inputs.record_family_flag_scratch,
            hir_node_capacity.max(1) as usize,
        );
        let module_record_flag = record_family_flag.clone();
        let import_record_flag = record_family_flag.clone();
        let decl_record_flag = record_family_flag.clone();
        let path_record_flag = record_family_flag.clone();
        // Parser list-workspace buffers are dead before typecheck starts. Use one
        // as shared HIR-keyed module/import/decl/path prefix scratch instead of
        // allocating a second max-capacity buffer.
        let module_record_prefix = typed_alias_or_storage_u32(
            device,
            "type_check.resident.module_record_prefix",
            hir_node_capacity as usize,
            external.map(|scratch| scratch.module_record_prefix),
        );
        // Module, import, and declaration record prefixes are consumed by their
        // scatter passes before the next record-family scan runs, so one prefix
        // buffer is enough.
        let import_record_prefix = module_record_prefix.clone();
        let decl_record_prefix = module_record_prefix.clone();
        // The counted-scan local prefix is scratch for module/path and visible
        // declaration scans. Reuse a dead parser list-workspace buffer.
        let record_scan_local_prefix = typed_alias_or_storage_u32(
            device,
            "type_check.resident.record_scan_local_prefix",
            hir_node_capacity as usize,
            external.map(|scratch| scratch.record_scan_local_prefix),
        );
        let record_scan_block_sum = typed_storage_u32_rw(
            device,
            "type_check.resident.record_scan_block_sum",
            n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let record_scan_prefix_a = typed_storage_u32_rw(
            device,
            "type_check.resident.record_scan_prefix_a",
            n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let record_scan_prefix_b = typed_storage_u32_rw(
            device,
            "type_check.resident.record_scan_prefix_b",
            n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        // Module/import/decl key radix histograms are phase-local scratch. Borrow
        // dead parser delimiter workspaces when they are large enough; very small
        // tests still need the 256-bucket minimum allocation.
        let key_radix_block_histogram = typed_reuse_storage_u32(
            device,
            "type_check.resident.module_path_key_radix_block_histogram",
            key_radix_histogram_len,
            external.map(|scratch| scratch.module_path_key_radix_block_histogram),
        );
        let key_radix_block_bucket_prefix = typed_reuse_storage_u32(
            device,
            "type_check.resident.module_path_key_radix_block_bucket_prefix",
            key_radix_histogram_len,
            external.map(|scratch| scratch.module_path_key_radix_block_bucket_prefix),
        );
        let key_radix_bucket_total = typed_storage_u32_rw(
            device,
            "type_check.resident.module_path_key_radix_bucket_total",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let key_radix_bucket_base = typed_storage_u32_rw(
            device,
            "type_check.resident.module_path_key_radix_bucket_base",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_count_out = typed_storage_u32_rw(
            device,
            "type_check.resident.module_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let module_table_count_out = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.module_table_count_out",
            1,
            layout.module_capacity_u32,
            wgpu::BufferUsages::empty(),
        );
        let import_count_out = typed_storage_u32_rw(
            device,
            "type_check.resident.import_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let decl_count_out = typed_storage_u32_rw(
            device,
            "type_check.resident.decl_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let module_file_id = typed_storage_u32_rw(
            device,
            "type_check.resident.module_file_id",
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_path_id = typed_storage_u32_rw(
            device,
            "type_check.resident.module_path_id",
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_owner_hir = typed_storage_u32_rw(
            device,
            "type_check.resident.module_owner_hir",
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_status = typed_storage_u32_rw(
            device,
            "type_check.resident.module_status",
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_key_segment_count = typed_storage_u32_rw(
            device,
            "type_check.resident.module_key_segment_count",
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_key_segment_base = typed_storage_u32_rw(
            device,
            "type_check.resident.module_key_segment_base",
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_key_segment_capacity = module_capacity
            .max(1)
            .saturating_mul(MODULE_KEY_SEGMENT_ROW_WIDTH);
        let module_key_segment_name_id = typed_storage_u32_rw(
            device,
            "type_check.resident.module_key_segment_name_id",
            module_key_segment_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_key_to_module_id = typed_storage_u32_rw(
            device,
            "type_check.resident.module_key_to_module_id",
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_key_order_tmp = typed_storage_u32_rw(
            device,
            "type_check.resident.module_key_order_tmp",
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_key_radix_dispatch_args = typed_storage_u32_rw(
            device,
            "type_check.resident.module_key_radix_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let module_key_radix_block_histogram = key_radix_block_histogram.clone();
        let module_key_radix_block_bucket_prefix = key_radix_block_bucket_prefix.clone();
        let module_key_radix_bucket_total = key_radix_bucket_total.clone();
        let module_key_radix_bucket_base = key_radix_bucket_base.clone();
        let module_id_by_file_id = typed_storage_u32_rw(
            device,
            "type_check.resident.module_id_by_file_id",
            module_capacity,
            wgpu::BufferUsages::empty(),
        );
        let external: Option<GpuTypeCheckExternalScratchBuffers<'_>> = None;
        let import_module_file_id = typed_storage_u32_rw(
            device,
            "type_check.resident.import_module_file_id",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_path_id = typed_storage_u32_rw(
            device,
            "type_check.resident.import_path_id",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_kind = typed_storage_u32_rw(
            device,
            "type_check.resident.import_kind",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_owner_hir = typed_storage_u32_rw(
            device,
            "type_check.resident.import_owner_hir",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_module_id = typed_storage_u32_rw(
            device,
            "type_check.resident.import_module_id",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_target_module_id = typed_storage_u32_rw(
            device,
            "type_check.resident.import_target_module_id",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_target_dependency_module_id = inputs.dependency_interfaces.map(|_| {
            typed_storage_u32_rw(
                device,
                "type_check.resident.import_target_dependency_module_id",
                import_record_capacity,
                wgpu::BufferUsages::empty(),
            )
        });
        let import_status = typed_storage_u32_rw(
            device,
            "type_check.resident.import_status",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_edge_key_order = typed_storage_u32_rw(
            device,
            "type_check.resident.import_edge_key_order",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_edge_key_order_tmp = typed_storage_u32_rw(
            device,
            "type_check.resident.import_edge_key_order_tmp",
            import_record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_edge_key_radix_dispatch_args = typed_storage_u32_rw(
            device,
            "type_check.resident.import_edge_key_radix_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        // Declaration tables are retained through module/path resolution, but they
        // are not part of the x86 handoff. Use parser token/tree workspaces that
        // are dead after HIR construction.
        let decl_module_file_id = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_module_file_id",
            record_capacity,
            external.map(|scratch| scratch.decl_module_file_id),
        );
        let decl_module_id = typed_storage_u32_rw(
            device,
            "type_check.resident.decl_module_id",
            record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let decl_name_id = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_name_id",
            record_capacity,
            external.map(|scratch| scratch.decl_name_id),
        );
        // Name-radix scratch is dead before module/path recording runs. These
        // declaration metadata buffers are retained for x86, so keep them in
        // typechecker-owned scratch rather than parser scratch that backend passes
        // may later borrow for their own phase-local work.
        let decl_name_token = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_name_token",
            record_capacity,
            Some(inputs.decl_name_token_scratch),
        );
        let decl_id_by_name_token = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_id_by_name_token",
            token_capacity.max(1) as usize,
            Some(inputs.decl_id_by_name_token_scratch),
        );
        let decl_kind = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_kind",
            record_capacity,
            Some(inputs.decl_kind_scratch),
        );
        let decl_namespace = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_namespace",
            record_capacity,
            external.map(|scratch| scratch.decl_namespace),
        );
        let decl_visibility = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_visibility",
            record_capacity,
            external.map(|scratch| scratch.decl_visibility),
        );
        // Canonical name hashes remain live through dependency resolution and
        // semantic-interface export. These declaration rows therefore need
        // independent retained storage; aliasing them onto the hash tables
        // made exported identities depend on which declaration rows happened
        // to overwrite which names.
        let decl_hir_node = typed_storage_u32_rw(
            device,
            "type_check.resident.decl_hir_node",
            record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let decl_parent_type_decl = typed_storage_u32_rw(
            device,
            "type_check.resident.decl_parent_type_decl",
            record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let decl_token_start = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_token_start",
            record_capacity,
            external.map(|scratch| scratch.decl_token_start),
        );
        let decl_token_end = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_token_end",
            record_capacity,
            external.map(|scratch| scratch.decl_token_end),
        );
        let decl_key_to_decl_id = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_key_to_decl_id",
            record_capacity,
            external.map(|scratch| scratch.decl_key_to_decl_id),
        );
        let decl_key_order_tmp = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_key_order_tmp",
            record_capacity,
            external.map(|scratch| scratch.decl_key_order_tmp),
        );
        let decl_key_radix_dispatch_args = typed_storage_u32_rw(
            device,
            "type_check.resident.decl_key_radix_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let decl_key_radix_block_histogram = key_radix_block_histogram.clone();
        let decl_key_radix_block_bucket_prefix = key_radix_block_bucket_prefix.clone();
        let decl_key_radix_bucket_total = key_radix_bucket_total.clone();
        let decl_key_radix_bucket_base = key_radix_bucket_base.clone();
        let decl_status = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_status",
            record_capacity,
            external.map(|scratch| scratch.decl_status),
        );
        // Duplicate rows are consumed before type-instance passes populate the
        // HIR-keyed generic-param count table.
        let decl_duplicate_of = typed_alias_or_storage_u32(
            device,
            "type_check.resident.decl_duplicate_of",
            record_capacity,
            external.map(|scratch| scratch.type_decl_generic_param_count_by_node),
        );
        // Declaration namespace/public flags are consumed during module-path
        // visibility setup, before type-instance argument tag/payload tables are
        // written by later typecheck passes.
        let decl_type_key_flag = typed_alias_or_storage_u32(
            device,
            "type_check.resident.decl_type_key_flag",
            record_capacity,
            external.map(|scratch| scratch.type_instance_arg_ref_tag),
        );
        let decl_value_key_flag = typed_alias_or_storage_u32(
            device,
            "type_check.resident.decl_value_key_flag",
            record_capacity,
            external.map(|scratch| scratch.type_instance_arg_ref_payload),
        );
        // Declaration key prefixes are consumed before import-visible key scans
        // populate their prefixes, so both families can share the same external
        // token-capacity prefix workspaces.
        let decl_type_key_prefix = typed_alias_or_storage_u32(
            device,
            "type_check.resident.decl_type_key_prefix",
            record_capacity,
            external.map(|scratch| scratch.import_visible_type_prefix),
        );
        let decl_value_key_prefix = typed_alias_or_storage_u32(
            device,
            "type_check.resident.decl_value_key_prefix",
            record_capacity,
            external.map(|scratch| scratch.import_visible_value_prefix),
        );
        let decl_type_key_count_out = typed_storage_u32_rw(
            device,
            "type_check.resident.decl_type_key_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let decl_value_key_count_out = typed_storage_u32_rw(
            device,
            "type_check.resident.decl_value_key_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        // Type declaration-key lookup is retained by module/path consumers, but
        // lexer DFA summary scratch is dead after tokenization and is not part of
        // the typecheck or x86 input surface.
        let decl_type_key_to_decl_id = typed_alias_or_storage_u32(
            device,
            "type_check.resident.decl_type_key_to_decl_id",
            record_capacity,
            None,
        );
        // Module-path value-key lookup is consumed inside typecheck and is not
        // retained by the x86 handoff. Reuse dead parser list-workspace rows.
        let decl_value_key_to_decl_id = typed_alias_or_storage_u32(
            device,
            "type_check.resident.decl_value_key_to_decl_id",
            record_capacity,
            None,
        );
        // Persisted semantic-interface declaration identity crosses the point
        // where namespace/public-key scratch is reused by type instances.
        let interface_public_decl_count = typed_storage_u32_rw(
            device,
            "type_check.resident.interface_public_decl_count",
            1,
            wgpu::BufferUsages::empty(),
        );
        let interface_public_decl_local_id = typed_storage_u32_rw(
            device,
            "type_check.resident.interface_public_decl_local_id",
            record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let interface_public_decl_index_by_local = typed_storage_u32_rw(
            device,
            "type_check.resident.interface_public_decl_index_by_local",
            record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let interface_public_decl_index_by_hir = typed_storage_u32_rw(
            device,
            "type_check.resident.interface_public_decl_index_by_hir",
            record_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_count = typed_alias_or_storage_u32(
            device,
            "type_check.resident.import_visible_type_count",
            record_capacity,
            None,
        );
        let import_visible_value_count = typed_alias_or_storage_u32(
            device,
            "type_check.resident.import_visible_value_count",
            record_capacity,
            None,
        );
        let import_visible_type_prefix = typed_alias_or_storage_u32(
            device,
            "type_check.resident.import_visible_type_prefix",
            record_capacity,
            None,
        );
        let import_visible_value_prefix = typed_alias_or_storage_u32(
            device,
            "type_check.resident.import_visible_value_prefix",
            record_capacity,
            None,
        );
        let import_visible_type_count_out = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_count_out = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_module_id = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_module_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_name_id = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_name_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_decl_id = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_decl_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_key_order = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_key_order",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_key_order_tmp = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_key_order_tmp",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_key_module_id = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_key_module_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_key_name_id = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_key_name_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_key_to_decl_id = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_key_to_decl_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_status = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_status",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_duplicate_of = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_duplicate_of",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_type_key_radix_dispatch_args = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_type_key_radix_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let import_visible_value_module_id = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_module_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_name_id = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_name_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_decl_id = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_decl_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_key_order = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_key_order",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_key_order_tmp = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_key_order_tmp",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_key_module_id = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_key_module_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_key_name_id = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_key_name_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_key_to_decl_id = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_key_to_decl_id",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_status = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_status",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_duplicate_of = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_duplicate_of",
            import_visible_capacity,
            wgpu::BufferUsages::empty(),
        );
        let import_visible_value_key_radix_dispatch_args = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_value_key_radix_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let import_visible_validate_dispatch_args = typed_storage_u32_rw(
            device,
            "type_check.resident.import_visible_validate_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let import_visible_key_radix_block_histogram = key_radix_block_histogram;
        let import_visible_key_radix_block_bucket_prefix = key_radix_block_bucket_prefix;
        let import_visible_key_radix_bucket_total = key_radix_bucket_total;
        let import_visible_key_radix_bucket_base = key_radix_bucket_base;
        let resolved_type_decl = typed_alias_or_storage_u32(
            device,
            "type_check.resident.resolved_type_decl",
            record_capacity,
            retained_path_external.map(|scratch| scratch.resolved_type_decl),
        );
        let resolved_value_decl = typed_alias_or_storage_u32(
            device,
            "type_check.resident.resolved_value_decl",
            record_capacity,
            retained_path_external.map(|scratch| scratch.resolved_value_decl),
        );
        let resolved_type_status = typed_alias_or_storage_u32(
            device,
            "type_check.resident.resolved_type_status",
            record_capacity,
            retained_path_external.map(|scratch| scratch.resolved_type_status),
        );
        let resolved_value_status = typed_alias_or_storage_u32(
            device,
            "type_check.resident.resolved_value_status",
            record_capacity,
            retained_path_external.map(|scratch| scratch.resolved_value_status),
        );
        // Path prefixes are only needed until path records have been scattered.
        // Later module/import scatters read the retained path_id_by_owner_hir table,
        // so this prefix can share the module/import/decl prefix scratch.
        let path_record_prefix = module_record_prefix.clone();
        let path_scan_local_prefix = record_scan_local_prefix.clone();
        let path_scan_block_sum = record_scan_block_sum.clone();
        let path_scan_prefix_a = record_scan_prefix_a.clone();
        let path_scan_prefix_b = record_scan_prefix_b.clone();
        let path_start = typed_alias_or_storage_u32(
            device,
            "type_check.resident.path_start",
            record_capacity,
            retained_path_external.map(|scratch| scratch.path_start),
        );
        let path_len = typed_alias_or_storage_u32(
            device,
            "type_check.resident.path_len",
            record_capacity,
            retained_path_external.map(|scratch| scratch.path_len),
        );
        let path_segment_count = typed_alias_or_storage_u32(
            device,
            "type_check.resident.path_segment_count",
            record_capacity,
            retained_path_external.map(|scratch| scratch.path_segment_count),
        );
        let path_segment_base = typed_alias_or_storage_u32(
            device,
            "type_check.resident.path_segment_base",
            record_capacity,
            retained_path_external.map(|scratch| scratch.path_segment_base),
        );
        let path_segment_capacity = token_capacity.max(1) as usize;
        let path_segment_name_id = typed_alias_or_storage_u32(
            device,
            "type_check.resident.path_segment_name_id",
            path_segment_capacity,
            retained_path_external.map(|scratch| scratch.path_segment_name_id),
        );
        let path_segment_token = typed_alias_or_storage_u32(
            device,
            "type_check.resident.path_segment_token",
            path_segment_capacity,
            retained_path_external.map(|scratch| scratch.path_segment_token),
        );
        let path_segment_count_out = typed_storage_u32_rw(
            device,
            "type_check.resident.path_segment_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let path_owner_hir = typed_alias_or_storage_u32(
            device,
            "type_check.resident.path_owner_hir",
            record_capacity,
            retained_path_external.map(|scratch| scratch.path_owner_hir),
        );
        let path_owner_token = typed_alias_or_storage_u32(
            device,
            "type_check.resident.path_owner_token",
            record_capacity,
            retained_path_external.map(|scratch| scratch.path_owner_token),
        );
        // Path ids are retained for later typecheck and x86 lowering, but the
        // parser list workspace is no longer read after HIR construction, so it
        // can carry this owner-HIR map.
        let path_id_by_owner_hir = typed_alias_or_storage_u32(
            device,
            "type_check.resident.path_id_by_owner_hir",
            hir_node_capacity.max(1) as usize,
            retained_path_external.map(|scratch| scratch.path_id_by_owner_hir),
        );
        let path_id_by_owner_token = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.path_id_by_owner_token",
            token_capacity.max(1) as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let path_owner_module_id = typed_alias_or_storage_u32(
            device,
            "type_check.resident.path_owner_module_id",
            record_capacity,
            retained_path_external.map(|scratch| scratch.path_owner_module_id),
        );
        let path_kind = typed_alias_or_storage_u32(
            device,
            "type_check.resident.path_kind",
            record_capacity,
            retained_path_external.map(|scratch| scratch.path_kind),
        );
        let path_count_out = typed_storage_u32_rw(
            device,
            "type_check.resident.path_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let path_dispatch_args = typed_storage_u32_rw(
            device,
            "type_check.resident.path_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let import_dispatch_args = typed_storage_u32_rw(
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
            import_target_dependency_module_id,
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
            interface_public_decl_count,
            interface_public_decl_local_id,
            interface_public_decl_index_by_local,
            interface_public_decl_index_by_hir,
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
            path_id_by_owner_token,
            path_owner_module_id,
            path_kind,
            path_count_out,
            path_dispatch_args,
            import_dispatch_args,
            scan_steps,
            record_scan_steps,
        }
    }
}
