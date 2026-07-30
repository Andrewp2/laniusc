use super::{super::*, inputs::CreateInputs, layout::Layout};

/// Owned resident buffers for module/path relations before bind-group assembly.
///
/// `State` keeps these buffers alive after construction; this intermediate
/// owner lets creation code wire discovery, indexing, declaration, and
/// projection bind groups without exposing raw allocation details.
macro_rules! module_path_buffers {
    (
        $(pub(super) $field:ident: $ty:ty,)*
        ; optional $(pub(super) $optional_field:ident: $optional_ty:ty,)*
    ) => {
        #[derive(Clone)]
        pub(in crate::type_checker) struct Buffers {
            $(pub(in crate::type_checker) $field: $ty,)*
            $(pub(in crate::type_checker) $optional_field: Option<$optional_ty>,)*
        }

        impl Buffers {
            pub(in crate::type_checker) fn register_resources<'a>(
                &'a self,
                resources: &mut ResourceMap<'a>,
            ) {
                $(resources.buffer(stringify!($field), &self.$field);)*
                $(if let Some(buffer) = &self.$optional_field {
                    resources.buffer(stringify!($optional_field), buffer);
                })*
                resources.buffers([
                    ("module_record_family_bits", &self.record_family_bits),
                    ("module_record_family_flag", &self.record_family_flag),
                    ("module_record_prefix", &self.module_record_prefix),
                    ("module_record_count_out", &self.module_count_out),
                    ("import_record_count_out", &self.import_count_out),
                ]);
            }
        }
    };
}

/// Allocates the common case for module resources: a zero-initialized `u32`
/// storage array whose diagnostic label is its reflected resource name.
macro_rules! module_storage_buffers {
    ($device:expr; $(
        $field:ident $([$usage:ident])? : $count:expr;
    )*) => {
        $(
            let $field = typed_storage_u32_rw(
                $device,
                concat!("type_check.resident.", stringify!($field)),
                $count,
                module_storage_buffers!(@usage $($usage)?),
            );
        )*
    };
    (@usage) => { wgpu::BufferUsages::empty() };
    (@usage $usage:ident) => { wgpu::BufferUsages::$usage };
}

module_path_buffers! {
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
    pub(super) module_key_canonical_id: LaniusBuffer<u32>,
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
    pub(super) path_segment_count: LaniusBuffer<u32>,
    pub(super) path_len: LaniusBuffer<u32>,
    pub(super) path_segment_base: LaniusBuffer<u32>,
    pub(super) path_segment_name_id: LaniusBuffer<u32>,
    pub(super) path_segment_token: LaniusBuffer<u32>,
    pub(super) path_segment_count_out: LaniusBuffer<u32>,
    pub(super) path_max_segment_count: LaniusBuffer<u32>,
    pub(super) path_prefix_base: LaniusBuffer<u32>,
    pub(super) path_prefix_id_a: LaniusBuffer<u32>,
    pub(super) path_prefix_id_b: LaniusBuffer<u32>,
    pub(super) path_prefix_table_state: LaniusBuffer<u32>,
    pub(super) path_prefix_row_dispatch_args: LaniusBuffer<u32>,
    pub(super) path_prefix_round_dispatch_args: LaniusBuffer<u32>,
    pub(super) path_owner_hir: LaniusBuffer<u32>,
    pub(super) path_call_hir: LaniusBuffer<u32>,
    pub(super) path_owner_token: LaniusBuffer<u32>,
    pub(super) path_id_by_owner_hir: LaniusBuffer<u32>,
    pub(super) path_id_by_owner_token: LaniusBuffer<u32>,
    pub(super) path_owner_module_id: LaniusBuffer<u32>,
    pub(super) path_kind: LaniusBuffer<u32>,
    pub(super) path_count_out: LaniusBuffer<u32>,
    pub(super) path_dispatch_args: LaniusBuffer<u32>,
    pub(super) import_dispatch_args: LaniusBuffer<u32>,
    ; optional
    pub(super) import_target_dependency_module_id: LaniusBuffer<u32>,
}

impl Buffers {
    /// Allocates module/path storage and aliases dead scratch buffers where safe.
    pub(super) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        layout: Layout,
        inputs: &CreateInputs<'_>,
    ) -> Result<Self> {
        let Layout {
            n_blocks,
            record_capacity,
            module_capacity,
            import_record_capacity,
            import_visible_capacity,
            key_radix_histogram_len,
            ..
        } = layout;
        let hir_node_capacity = inputs.hir_node_capacity;
        let token_capacity = inputs.token_capacity;
        let path_segment_capacity = token_capacity.max(1) as usize;
        let path_segment_name_id = graph
            .u32_buffer("path_segment_name_id")?
            .alias(path_segment_capacity);
        // Module/path family rows have graph-owned identities. The compiler graph
        // may still color their phase-local lifetimes onto reusable physical slots,
        // but this constructor never borrows an unrelated semantic relation.
        let record_family_bits = inputs
            .module_record_family_bits
            .alias(hir_node_capacity.max(1) as usize);
        let record_family_flag = inputs
            .module_record_family_flag
            .alias(hir_node_capacity.max(1) as usize);
        let module_record_flag = record_family_flag.clone();
        let import_record_flag = record_family_flag.clone();
        let decl_record_flag = record_family_flag.clone();
        let path_record_flag = record_family_flag.clone();
        let module_record_prefix = inputs
            .module_record_prefix
            .alias(hir_node_capacity.max(1) as usize);
        // Module, import, and declaration record prefixes are consumed by their
        // scatter passes before the next record-family scan runs, so one prefix
        // buffer is enough.
        let import_record_prefix = module_record_prefix.clone();
        let decl_record_prefix = module_record_prefix.clone();
        let record_scan_local_prefix = inputs
            .module_record_scan_workspace
            .local_prefix
            .alias(hir_node_capacity.max(1) as usize);
        let record_scan_block_sum = inputs
            .module_record_scan_workspace
            .block_sum
            .alias(n_blocks.max(1) as usize);
        let record_scan_prefix_a = inputs
            .module_record_scan_workspace
            .block_prefix
            .alias(n_blocks.max(1) as usize);
        let record_scan_prefix_b = inputs
            .module_record_scan_workspace
            .hierarchy
            .alias(n_blocks.max(1) as usize);
        let key_radix_block_histogram = inputs
            .module_path_key_radix_block_histogram
            .alias(key_radix_histogram_len);
        let key_radix_block_bucket_prefix = inputs
            .module_path_key_radix_block_bucket_prefix
            .alias(key_radix_histogram_len);
        let key_radix_bucket_total = inputs
            .module_path_key_radix_bucket_total
            .alias(NAME_RADIX_BUCKETS as usize);
        let key_radix_bucket_base = inputs
            .module_path_key_radix_bucket_base
            .alias(NAME_RADIX_BUCKETS as usize);
        module_storage_buffers!(device;
            module_count_out: 1;
        );
        let module_table_count_out = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.module_table_count_out",
            1,
            layout.module_capacity_u32,
            wgpu::BufferUsages::empty(),
        );
        module_storage_buffers!(device;
            import_count_out: 1;
            decl_count_out: 1;
            module_file_id: module_capacity;
            module_path_id: module_capacity;
            module_owner_hir: module_capacity;
            module_status: module_capacity;
            module_key_canonical_id: module_capacity;
            module_key_segment_count: module_capacity;
            module_key_segment_base: module_capacity;
        );
        let module_key_segment_name_id = path_segment_name_id.clone();
        module_storage_buffers!(device;
            module_key_to_module_id: module_capacity;
            module_key_order_tmp: module_capacity;
            module_key_radix_dispatch_args [INDIRECT]: 3;
        );
        let module_key_radix_block_histogram = key_radix_block_histogram.clone();
        let module_key_radix_block_bucket_prefix = key_radix_block_bucket_prefix.clone();
        let module_key_radix_bucket_total = key_radix_bucket_total.clone();
        let module_key_radix_bucket_base = key_radix_bucket_base.clone();
        module_storage_buffers!(device;
            module_id_by_file_id: module_capacity;
            import_module_file_id: import_record_capacity;
            import_path_id: import_record_capacity;
            import_kind: import_record_capacity;
            import_owner_hir: import_record_capacity;
        );
        let import_module_id = graph
            .u32_buffer("import_module_id")?
            .alias(import_record_capacity);
        let import_target_module_id = graph
            .u32_buffer("import_target_module_id")?
            .alias(import_record_capacity);
        let import_target_dependency_module_id = inputs.dependency_interfaces.map(|_| {
            typed_storage_u32_rw(
                device,
                "type_check.resident.import_target_dependency_module_id",
                import_record_capacity.saturating_mul(4),
                wgpu::BufferUsages::empty(),
            )
        });
        let import_status = graph
            .u32_buffer("import_status")?
            .alias(import_record_capacity);
        module_storage_buffers!(device;
            import_edge_key_order: import_record_capacity;
            import_edge_key_order_tmp: import_record_capacity;
            import_edge_key_radix_dispatch_args [INDIRECT]: 3;
        );
        // Declaration tables are retained through module/path resolution, but they
        // are not part of the x86 handoff. Use parser token/tree workspaces that
        // are dead after HIR construction.
        let decl_module_file_id = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_module_file_id",
            record_capacity,
            None::<&wgpu::Buffer>,
        );
        module_storage_buffers!(device;
            decl_module_id: record_capacity;
        );
        let decl_name_id = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_name_id",
            record_capacity,
            None::<&wgpu::Buffer>,
        );
        // Declaration relations have long type-check lifetimes and therefore
        // own explicit compiler-graph workspace identities. Do not hide them
        // behind the short-lived name-mark rows they replaced.
        let decl_name_token = inputs.decl_name_token.alias(record_capacity);
        let decl_id_by_name_token = inputs
            .decl_id_by_name_token
            .alias(token_capacity.max(1) as usize);
        let decl_kind = inputs.decl_kind.alias(record_capacity);
        let decl_namespace = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_namespace",
            record_capacity,
            None::<&wgpu::Buffer>,
        );
        let decl_visibility = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_visibility",
            record_capacity,
            None::<&wgpu::Buffer>,
        );
        // Canonical name hashes remain live through dependency resolution and
        // semantic-interface export. These declaration rows therefore need
        // independent retained storage; aliasing them onto the hash tables
        // made exported identities depend on which declaration rows happened
        // to overwrite which names.
        module_storage_buffers!(device;
            decl_hir_node: record_capacity;
            decl_parent_type_decl: record_capacity;
        );
        let decl_token_start = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_token_start",
            record_capacity,
            None::<&wgpu::Buffer>,
        );
        let decl_token_end = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_token_end",
            record_capacity,
            None::<&wgpu::Buffer>,
        );
        let decl_key_to_decl_id = graph
            .u32_buffer("decl_key_to_decl_id")?
            .alias(record_capacity);
        let decl_key_order_tmp = typed_reuse_storage_u32(
            device,
            "type_check.resident.decl_key_order_tmp",
            record_capacity,
            None::<&wgpu::Buffer>,
        );
        module_storage_buffers!(device;
            decl_key_radix_dispatch_args [INDIRECT]: 3;
        );
        let decl_key_radix_block_histogram = key_radix_block_histogram.clone();
        let decl_key_radix_block_bucket_prefix = key_radix_block_bucket_prefix.clone();
        let decl_key_radix_bucket_total = key_radix_bucket_total.clone();
        let decl_key_radix_bucket_base = key_radix_bucket_base.clone();
        let decl_status = inputs.decl_status.alias(record_capacity);
        // Duplicate rows are consumed before type-instance passes populate the
        // HIR-keyed generic-param count table.
        let decl_duplicate_of = typed_alias_or_storage_u32(
            device,
            "type_check.resident.decl_duplicate_of",
            record_capacity,
            Some(inputs.type_decl_generic_param_count_by_owner_token),
        );
        // Declaration namespace/public flags are consumed during module-path
        // visibility setup before the graph-owned type-instance argument
        // tag/payload tables are written. Reuse those graph slots directly so
        // this phase no longer keeps parser allocations alive.
        let decl_type_key_flag = typed_alias_or_storage_u32(
            device,
            "type_check.resident.decl_type_key_flag",
            record_capacity,
            Some(inputs.type_instance_arg_ref_tag),
        );
        let decl_value_key_flag = typed_alias_or_storage_u32(
            device,
            "type_check.resident.decl_value_key_flag",
            record_capacity,
            Some(inputs.type_instance_arg_ref_payload),
        );
        // Declaration key prefixes are consumed before import-visible key scans
        // populate their prefixes, so both families can share the same external
        // token-capacity prefix workspaces.
        let decl_type_key_prefix = inputs.decl_type_key_prefix.alias(record_capacity);
        let decl_value_key_prefix = inputs.decl_value_key_prefix.alias(record_capacity);
        let decl_type_key_count_out = inputs.decl_type_key_count_out.clone();
        let decl_value_key_count_out = inputs.decl_value_key_count_out.clone();
        // Type declaration-key lookup is retained by module/path consumers, but
        // lexer DFA summary scratch is dead after tokenization and is not part of
        // the typecheck or x86 input surface.
        let decl_type_key_to_decl_id = typed_alias_or_storage_u32(
            device,
            "type_check.resident.decl_type_key_to_decl_id",
            record_capacity,
            None::<&wgpu::Buffer>,
        );
        // Module-path value-key lookup is consumed inside typecheck and is not
        // retained by the x86 handoff. Reuse dead parser list-workspace rows.
        let decl_value_key_to_decl_id = typed_alias_or_storage_u32(
            device,
            "type_check.resident.decl_value_key_to_decl_id",
            record_capacity,
            None::<&wgpu::Buffer>,
        );
        // Persisted semantic-interface declaration identity crosses the point
        // where namespace/public-key scratch is reused by type instances.
        module_storage_buffers!(device;
            interface_public_decl_count: 1;
            interface_public_decl_local_id: record_capacity;
            interface_public_decl_index_by_local: record_capacity;
            interface_public_decl_index_by_hir: record_capacity;
        );
        let import_visible_type_count = inputs.import_visible_type_count.alias(record_capacity);
        let import_visible_value_count = inputs.import_visible_value_count.alias(record_capacity);
        let import_visible_type_prefix = inputs.import_visible_type_prefix.alias(record_capacity);
        let import_visible_value_prefix = inputs.import_visible_value_prefix.alias(record_capacity);
        let import_visible_type_count_out = inputs.import_visible_type_count_out.clone();
        let import_visible_value_count_out = inputs.import_visible_value_count_out.clone();
        module_storage_buffers!(device;
            import_visible_type_module_id: import_visible_capacity;
            import_visible_type_name_id: import_visible_capacity;
            import_visible_type_decl_id: import_visible_capacity;
            import_visible_type_key_order: import_visible_capacity;
            import_visible_type_key_order_tmp: import_visible_capacity;
            import_visible_type_key_module_id: import_visible_capacity;
            import_visible_type_key_name_id: import_visible_capacity;
            import_visible_type_key_to_decl_id: import_visible_capacity;
            import_visible_type_status: import_visible_capacity;
            import_visible_type_duplicate_of: import_visible_capacity;
            import_visible_type_key_radix_dispatch_args [INDIRECT]: 3;
            import_visible_value_module_id: import_visible_capacity;
            import_visible_value_name_id: import_visible_capacity;
            import_visible_value_decl_id: import_visible_capacity;
            import_visible_value_key_order: import_visible_capacity;
            import_visible_value_key_order_tmp: import_visible_capacity;
            import_visible_value_key_module_id: import_visible_capacity;
            import_visible_value_key_name_id: import_visible_capacity;
            import_visible_value_key_to_decl_id: import_visible_capacity;
            import_visible_value_status: import_visible_capacity;
            import_visible_value_duplicate_of: import_visible_capacity;
            import_visible_value_key_radix_dispatch_args [INDIRECT]: 3;
            import_visible_validate_dispatch_args [INDIRECT]: 3;
        );
        let import_visible_key_radix_block_histogram = key_radix_block_histogram;
        let import_visible_key_radix_block_bucket_prefix = key_radix_block_bucket_prefix;
        let import_visible_key_radix_bucket_total = key_radix_bucket_total;
        let import_visible_key_radix_bucket_base = key_radix_bucket_base;
        let resolved_type_decl = graph
            .u32_buffer("resolved_type_decl")?
            .alias(record_capacity);
        let resolved_value_decl = graph
            .u32_buffer("resolved_value_decl")?
            .alias(record_capacity);
        let resolved_type_status = graph
            .u32_buffer("resolved_type_status")?
            .alias(record_capacity);
        let resolved_value_status = graph
            .u32_buffer("resolved_value_status")?
            .alias(record_capacity);
        // Path prefixes are only needed until path records have been scattered.
        // Later module/import scatters read the retained path_id_by_owner_hir table,
        // so this prefix can share the module/import/decl prefix scratch.
        let path_record_prefix = module_record_prefix.clone();
        let path_scan_local_prefix = record_scan_local_prefix.clone();
        let path_scan_block_sum = record_scan_block_sum.clone();
        let path_scan_prefix_a = record_scan_prefix_a.clone();
        let path_scan_prefix_b = record_scan_prefix_b.clone();
        let path_segment_count = graph
            .u32_buffer("path_segment_count")?
            .alias(record_capacity);
        let path_len = graph.u32_buffer("path_len")?.alias(record_capacity);
        let path_segment_base = graph
            .u32_buffer("path_segment_base")?
            .alias(record_capacity);
        let path_segment_token = graph
            .u32_buffer("path_segment_token")?
            .alias(path_segment_capacity);
        module_storage_buffers!(device;
            path_segment_count_out: 1;
            path_max_segment_count: 1;
            path_prefix_base: path_segment_capacity;
            path_prefix_id_a: path_segment_capacity;
            path_prefix_id_b: path_segment_capacity;
        );
        let path_prefix_table_capacity = path_segment_capacity
            .checked_mul(2)
            .expect("path-prefix table capacity overflow");
        module_storage_buffers!(device;
            path_prefix_table_state: path_prefix_table_capacity;
        );
        let path_prefix_round_count =
            u32::BITS - token_capacity.max(1).saturating_sub(1).leading_zeros();
        module_storage_buffers!(device;
            path_prefix_row_dispatch_args [INDIRECT]: 3;
            path_prefix_round_dispatch_args [INDIRECT]: path_prefix_round_count.max(1) as usize * 3;
        );
        let path_owner_hir = graph.u32_buffer("path_owner_hir")?.alias(record_capacity);
        let path_call_hir = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.path_call_hir",
            record_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let path_owner_token = graph.u32_buffer("path_owner_token")?.alias(record_capacity);
        // Path ids are a retained semantic artifact and are read by passes
        // that also rebuild type metadata in parser list workspaces. Keep the
        // map independent from raw-tree scratch so those workspaces can be
        // recolored without creating a same-dispatch read/write alias.
        let path_id_by_owner_hir = graph
            .u32_buffer("path_id_by_owner_hir")?
            .alias(hir_node_capacity.max(1) as usize);
        let path_id_by_owner_token = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.path_id_by_owner_token",
            token_capacity.max(1) as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let path_owner_module_id = graph
            .u32_buffer("path_owner_module_id")?
            .alias(record_capacity);
        let path_kind = graph.u32_buffer("path_kind")?.alias(record_capacity);
        module_storage_buffers!(device;
            path_count_out: 1;
            path_dispatch_args [INDIRECT]: 3;
            import_dispatch_args [INDIRECT]: 3;
        );

        Ok(Self {
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
            module_key_canonical_id,
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
            path_segment_count,
            path_len,
            path_segment_base,
            path_segment_name_id,
            path_segment_token,
            path_segment_count_out,
            path_max_segment_count,
            path_prefix_base,
            path_prefix_id_a,
            path_prefix_id_b,
            path_prefix_table_state,
            path_prefix_row_dispatch_args,
            path_prefix_round_dispatch_args,
            path_owner_hir,
            path_call_hir,
            path_owner_token,
            path_id_by_owner_hir,
            path_id_by_owner_token,
            path_owner_module_id,
            path_kind,
            path_count_out,
            path_dispatch_args,
            import_dispatch_args,
        })
    }
}
