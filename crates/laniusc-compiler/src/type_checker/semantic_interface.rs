use super::*;
use crate::compiler::{
    GPU_SEMANTIC_INTERFACE_VERSION,
    GpuSemanticInterfaceArtifact,
    GpuSemanticInterfaceDeclarationRecord,
    GpuSemanticInterfaceIdentityArtifact,
    GpuSemanticInterfaceMemberRecord,
    GpuSemanticInterfaceModuleRecord,
    GpuSemanticInterfaceModuleSegmentRecord,
    GpuSemanticInterfaceTypeEdge,
    GpuSemanticInterfaceTypeRecord,
};

const MODULE_WORDS: usize = 2;
const MODULE_SEGMENT_WORDS: usize = 4;
const DECLARATION_WORDS: usize = 14;
const COUNT_WORDS: usize = 5;
const STATUS_WORDS: usize = 4;
const TYPE_WORDS: usize = 9;
const MEMBER_WORDS: usize = 10;

struct RecordedSemanticInterfaceTypeTopology {
    type_capacity: usize,
    edge_capacity: usize,
    member_capacity: usize,
    _parent: LaniusBuffer<u32>,
    _child_ordinal: LaniusBuffer<u32>,
    _seed_owner: LaniusBuffer<u32>,
    _direct_type_hir_by_decl: LaniusBuffer<u32>,
    _root_link_a: LaniusBuffer<u32>,
    _root_link_b: LaniusBuffer<u32>,
    _root_owner_a: LaniusBuffer<u32>,
    _root_owner_b: LaniusBuffer<u32>,
    _reverse_flag: LaniusBuffer<u32>,
    _reverse_prefix: LaniusBuffer<u32>,
    _scan_local_prefix: LaniusBuffer<u32>,
    _scan_block_sum: LaniusBuffer<u32>,
    _scan_prefix_a: LaniusBuffer<u32>,
    _scan_prefix_b: LaniusBuffer<u32>,
    _count: LaniusBuffer<u32>,
    _scan_count: LaniusBuffer<u32>,
    _dispatch_args: LaniusBuffer<u32>,
    _hir_order: LaniusBuffer<u32>,
    _index_by_hir: LaniusBuffer<u32>,
    _edge_count: LaniusBuffer<u32>,
    _edge_prefix: LaniusBuffer<u32>,
    _edge_total: LaniusBuffer<u32>,
    _edges: LaniusBuffer<u32>,
    _edge_written: LaniusBuffer<u32>,
    _local_decl_by_hir: LaniusBuffer<u32>,
    _path_classification: LaniusBuffer<u32>,
    _types: LaniusBuffer<u32>,
    _signature_type_flag: LaniusBuffer<u32>,
    _signature_type_prefix: LaniusBuffer<u32>,
    _signature_type_total: LaniusBuffer<u32>,
    _signature_edge_count: LaniusBuffer<u32>,
    _signature_edge_prefix: LaniusBuffer<u32>,
    _signature_edge_total: LaniusBuffer<u32>,
    _signature_type_by_decl: LaniusBuffer<u32>,
    _complete_type_count: LaniusBuffer<u32>,
    _complete_edge_total: LaniusBuffer<u32>,
    _signature_scan_count: LaniusBuffer<u32>,
    _signature_dispatch_args: LaniusBuffer<u32>,
    _signature_scan_local_prefix: LaniusBuffer<u32>,
    _signature_scan_block_sum: LaniusBuffer<u32>,
    _signature_scan_prefix_a: LaniusBuffer<u32>,
    _signature_scan_prefix_b: LaniusBuffer<u32>,
    _variant_count_by_hir: LaniusBuffer<u32>,
    _field_count_by_hir: LaniusBuffer<u32>,
    _generic_type_count_by_decl: LaniusBuffer<u32>,
    _generic_const_count_by_decl: LaniusBuffer<u32>,
    _member_count: LaniusBuffer<u32>,
    _member_prefix: LaniusBuffer<u32>,
    _member_total: LaniusBuffer<u32>,
    _members: LaniusBuffer<u32>,
    _member_name_id: LaniusBuffer<u32>,
    _member_index_by_generic_row: LaniusBuffer<u32>,
    _member_written: LaniusBuffer<u32>,
    _params: LaniusBuffer<SemanticInterfaceTypeTopologyParams>,
    count_readback: wgpu::Buffer,
    edge_total_readback: wgpu::Buffer,
    types_readback: wgpu::Buffer,
    edges_readback: wgpu::Buffer,
    edge_written_readback: wgpu::Buffer,
    member_total_readback: wgpu::Buffer,
    member_written_readback: wgpu::Buffer,
    members_readback: wgpu::Buffer,
}

/// GPU outputs and host-visible copies recorded for one bounded unit's public
/// semantic identities. The input semantic tables remain owned by the resident
/// type checker until the enclosing compilation submission completes.
pub struct RecordedSemanticInterface {
    expected_library_id: u32,
    expected_unit_id: u32,
    module_capacity: usize,
    module_segment_capacity: usize,
    declaration_capacity: usize,
    name_byte_capacity: usize,
    _name_ref_len: LaniusBuffer<u32>,
    _name_ref_prefix: LaniusBuffer<u32>,
    _scan_local_prefix: LaniusBuffer<u32>,
    _scan_block_sum: LaniusBuffer<u32>,
    _scan_prefix_a: LaniusBuffer<u32>,
    _scan_prefix_b: LaniusBuffer<u32>,
    _scan_total: LaniusBuffer<u32>,
    _scan_count: LaniusBuffer<u32>,
    _scan_dispatch_args: LaniusBuffer<u32>,
    _module_segment_prefix: LaniusBuffer<u32>,
    _module_scan_local_prefix: LaniusBuffer<u32>,
    _module_scan_block_sum: LaniusBuffer<u32>,
    _module_scan_prefix_a: LaniusBuffer<u32>,
    _module_scan_prefix_b: LaniusBuffer<u32>,
    _module_segment_total: LaniusBuffer<u32>,
    _module_scan_dispatch_args: LaniusBuffer<u32>,
    _modules: LaniusBuffer<u32>,
    _module_segments: LaniusBuffer<u32>,
    _declarations: LaniusBuffer<u32>,
    _name_byte_words: LaniusBuffer<u32>,
    _counts: LaniusBuffer<u32>,
    _status: LaniusBuffer<u32>,
    _type_topology: RecordedSemanticInterfaceTypeTopology,
    modules_readback: wgpu::Buffer,
    module_segments_readback: wgpu::Buffer,
    declarations_readback: wgpu::Buffer,
    name_bytes_readback: wgpu::Buffer,
    counts_readback: wgpu::Buffer,
    status_readback: wgpu::Buffer,
}

impl GpuTypeChecker {
    /// Records canonical public module/declaration identities for the current
    /// resident type-check result. This must be called after type-check passes
    /// have been recorded and before the resident state is released.
    pub fn record_semantic_interface(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        library_id: u32,
        unit_id: u32,
        source_len: u32,
        source_bytes: &wgpu::Buffer,
        hir: GpuSemanticInterfaceHirBuffers<'_>,
    ) -> Result<RecordedSemanticInterface> {
        let guard = self
            .resident_state
            .lock()
            .expect("GpuTypeChecker.resident_state poisoned");
        let state = guard.as_ref().ok_or_else(|| {
            anyhow::anyhow!("semantic-interface export requires resident type-check state")
        })?;
        let module_path = state.module_path.as_ref().ok_or_else(|| {
            anyhow::anyhow!("semantic-interface export requires resident module/declaration tables")
        })?;
        let inputs = GpuSemanticInterfaceIdentityBuffers {
            name_count_out: &state.name_scan_total,
            name_spans: &state.name_spans,
            name_hash_lo: &state.name_order_in,
            name_hash_hi: &state.name_order_tmp,
            name_id_by_token: &state.name_id_by_token,
            language_symbol_bytes: &state.language_symbol_bytes,
            module_count_out: &module_path.module_count_out,
            module_key_segment_count: &module_path.module_key_segment_count,
            module_key_segment_base: &module_path.module_key_segment_base,
            module_key_segment_name_id: &module_path.module_key_segment_name_id,
            decl_count_out: &module_path.decl_count_out,
            decl_module_id: &module_path.decl_module_id,
            decl_name_id: &module_path.decl_name_id,
            decl_kind: &module_path.decl_kind,
            decl_namespace: &module_path.decl_namespace,
            decl_visibility: &module_path.decl_visibility,
            decl_parent_type_decl: &module_path.decl_parent_type_decl,
            decl_hir_node: &module_path.decl_hir_node,
            public_decl_count: &module_path.interface_public_decl_count,
            public_decl_local_id: &module_path.interface_public_decl_local_id,
            public_decl_index_by_local: &module_path.interface_public_decl_index_by_local,
            public_decl_index_by_hir: &module_path.interface_public_decl_index_by_hir,
            type_expr_ref_tag: &state.type_expr_ref_tag,
            type_expr_ref_payload: &state.type_expr_ref_payload,
            type_generic_param_slot_by_token: &state.type_generic_param_slot_by_token,
            type_const_param_slot_by_token: &state.type_const_param_slot_by_token,
            type_instance_decl_token: &state.type_instance_decl_token,
            type_instance_external_canonical: &state.type_instance_external_canonical,
            dependency_type_count: module_path
                .dependency_interfaces
                .as_ref()
                .map_or(0, |dependencies| dependencies.type_count),
            dependency_type_words: module_path
                .dependency_interfaces
                .as_ref()
                .map_or(&state.type_instance_external_canonical, |dependencies| {
                    &dependencies.type_words
                }),
            path_id_by_owner_token: &module_path.path_id_by_owner_token,
            resolved_type_decl: &module_path.resolved_type_decl,
            decl_id_by_name_token: &module_path.decl_id_by_name_token,
            generic_param_count_out: &state.generic_param_count_out,
            generic_param_owner_token: &state.generic_param_owner_token,
            generic_param_name_id: &state.generic_param_name_id,
            generic_param_token: &state.generic_param_token,
            generic_param_kind: &state.generic_param_kind,
            type_decl_generic_param_count_by_owner_token: &state
                .type_decl_generic_param_count_by_owner_token,
            type_decl_const_param_count_by_owner_token: &state
                .type_decl_const_param_count_by_owner_token,
        };
        self.record_semantic_interface_from_buffers(
            device,
            encoder,
            library_id,
            unit_id,
            source_len,
            source_bytes,
            hir,
            inputs,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn record_semantic_interface_from_buffers(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        library_id: u32,
        unit_id: u32,
        source_len: u32,
        source_bytes: &wgpu::Buffer,
        hir: GpuSemanticInterfaceHirBuffers<'_>,
        inputs: GpuSemanticInterfaceIdentityBuffers<'_>,
    ) -> Result<RecordedSemanticInterface> {
        let name_capacity = u32_capacity(inputs.name_spans, 4, "name spans")?;
        let module_capacity = u32_capacity(
            inputs.module_key_segment_count,
            1,
            "module key segment counts",
        )?;
        let decl_capacity = u32_capacity(
            inputs.public_decl_local_id,
            1,
            "persisted public declarations",
        )?;
        if u32_capacity(
            inputs.public_decl_index_by_local,
            1,
            "local-to-persisted public declarations",
        )? != decl_capacity
        {
            return Err(anyhow::anyhow!(
                "semantic-interface public declaration maps have different capacities"
            ));
        }
        let module_segment_capacity = u32_capacity(
            inputs.module_key_segment_name_id,
            1,
            "module key segment names",
        )?;
        let member_capacity =
            u32_capacity(hir.compact_hir_core, 4, "semantic-interface compact HIR")?
                .checked_add(u32_capacity(
                    inputs.type_expr_ref_tag,
                    1,
                    "semantic-interface member tokens",
                )?)
                .ok_or_else(|| {
                    anyhow::anyhow!("semantic-interface member capacity overflows u32")
                })?;
        let name_ref_count = module_segment_capacity
            .checked_add(decl_capacity)
            .and_then(|value| value.checked_add(member_capacity))
            .ok_or_else(|| {
                anyhow::anyhow!("semantic-interface name-reference capacity overflows u32")
            })?;
        let declaration_capacity = decl_capacity;
        let name_byte_capacity = source_len
            .checked_mul(2)
            .ok_or_else(|| anyhow::anyhow!("semantic-interface name-byte capacity overflows u32"))?
            .checked_add(u32::try_from(LANGUAGE_SYMBOL_BYTES.len()).unwrap_or(u32::MAX))
            .ok_or_else(|| anyhow::anyhow!("semantic-interface name-byte capacity overflows u32"))?
            .max(1);
        let scan_n_blocks = name_ref_count.max(1).div_ceil(256).max(1);
        let module_scan_n_blocks = module_capacity.max(1).div_ceil(256).max(1);
        let identity_work_capacity = module_segment_capacity
            .max(module_capacity)
            .max(decl_capacity)
            .max(member_capacity);

        let name_ref_len = typed_storage_u32_rw(
            device,
            "type_check.interface.name_ref_len",
            name_ref_count as usize,
            wgpu::BufferUsages::COPY_DST,
        );
        let name_ref_prefix = typed_storage_u32_rw(
            device,
            "type_check.interface.name_ref_prefix",
            name_ref_count as usize,
            wgpu::BufferUsages::empty(),
        );
        let scan_local_prefix = typed_storage_u32_rw(
            device,
            "type_check.interface.scan_local_prefix",
            name_ref_count as usize,
            wgpu::BufferUsages::empty(),
        );
        let scan_block_sum = typed_storage_u32_rw(
            device,
            "type_check.interface.scan_block_sum",
            scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let scan_prefix_a = typed_storage_u32_rw(
            device,
            "type_check.interface.scan_prefix_a",
            scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let scan_prefix_b = typed_storage_u32_rw(
            device,
            "type_check.interface.scan_prefix_b",
            scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let scan_total = typed_storage_u32_rw(
            device,
            "type_check.interface.scan_total",
            1,
            wgpu::BufferUsages::empty(),
        );
        let scan_count = initialized_u32_buffer(
            device,
            "type_check.interface.scan_count",
            &[name_ref_count],
            wgpu::BufferUsages::STORAGE,
        );
        let [tgsx, tgsy, _] = self.passes.counted_scan_local.thread_group_size;
        let (dispatch_x, dispatch_y, dispatch_z) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(name_ref_count.max(1)),
            [tgsx, tgsy, 1],
        )?;
        let scan_dispatch_args = initialized_u32_buffer(
            device,
            "type_check.interface.scan_dispatch_args",
            &[dispatch_x, dispatch_y, dispatch_z],
            wgpu::BufferUsages::INDIRECT,
        );
        let scan_steps = make_name_scan_steps(
            device,
            NameScanParams {
                n_items: name_ref_count,
                n_blocks: scan_n_blocks,
                scan_step: 0,
            },
        );
        let scan = create_counted_u32_scan_bind_groups_with_passes(
            &self.passes,
            device,
            "type_check.interface.name_scan",
            &scan_steps,
            &scan_count,
            &name_ref_len,
            &name_ref_prefix,
            &scan_total,
            &scan_local_prefix,
            &scan_block_sum,
            &scan_prefix_a,
            &scan_prefix_b,
        )?;
        let module_segment_prefix = typed_storage_u32_rw(
            device,
            "type_check.interface.module_segment_prefix",
            module_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_scan_local_prefix = typed_storage_u32_rw(
            device,
            "type_check.interface.module_scan_local_prefix",
            module_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_scan_block_sum = typed_storage_u32_rw(
            device,
            "type_check.interface.module_scan_block_sum",
            module_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_scan_prefix_a = typed_storage_u32_rw(
            device,
            "type_check.interface.module_scan_prefix_a",
            module_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_scan_prefix_b = typed_storage_u32_rw(
            device,
            "type_check.interface.module_scan_prefix_b",
            module_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_segment_total = typed_storage_u32_rw(
            device,
            "type_check.interface.module_segment_total",
            1,
            wgpu::BufferUsages::empty(),
        );
        let (module_dispatch_x, module_dispatch_y, module_dispatch_z) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(module_capacity.max(1)),
            [tgsx, tgsy, 1],
        )?;
        let module_scan_dispatch_args = initialized_u32_buffer(
            device,
            "type_check.interface.module_scan_dispatch_args",
            &[module_dispatch_x, module_dispatch_y, module_dispatch_z],
            wgpu::BufferUsages::INDIRECT,
        );
        let module_scan_steps = make_name_scan_steps(
            device,
            NameScanParams {
                n_items: module_capacity,
                n_blocks: module_scan_n_blocks,
                scan_step: 0,
            },
        );
        let module_scan = create_counted_u32_scan_bind_groups_with_passes(
            &self.passes,
            device,
            "type_check.interface.module_segment_scan",
            &module_scan_steps,
            inputs.module_count_out,
            inputs.module_key_segment_count,
            &module_segment_prefix,
            &module_segment_total,
            &module_scan_local_prefix,
            &module_scan_block_sum,
            &module_scan_prefix_a,
            &module_scan_prefix_b,
        )?;

        let modules = typed_storage_u32_rw(
            device,
            "type_check.interface.modules",
            (module_capacity as usize).saturating_mul(MODULE_WORDS),
            wgpu::BufferUsages::empty(),
        );
        let module_segments = typed_storage_u32_rw(
            device,
            "type_check.interface.module_segments",
            (module_segment_capacity as usize).saturating_mul(MODULE_SEGMENT_WORDS),
            wgpu::BufferUsages::empty(),
        );
        let declarations = typed_storage_u32_rw(
            device,
            "type_check.interface.declarations",
            (declaration_capacity as usize).saturating_mul(DECLARATION_WORDS),
            wgpu::BufferUsages::empty(),
        );
        let name_word_capacity = (name_byte_capacity as usize).div_ceil(4);
        let name_byte_words = typed_storage_u32_rw(
            device,
            "type_check.interface.name_byte_words",
            name_word_capacity,
            wgpu::BufferUsages::COPY_DST,
        );
        let counts = typed_storage_u32_rw(
            device,
            "type_check.interface.counts",
            COUNT_WORDS,
            wgpu::BufferUsages::COPY_DST,
        );
        let status = initialized_u32_buffer(
            device,
            "type_check.interface.status",
            &[0, u32::MAX, u32::MAX, u32::MAX],
            wgpu::BufferUsages::STORAGE,
        );
        let type_topology = self.record_semantic_interface_type_topology(
            device, encoder, library_id, unit_id, hir, &inputs, &status,
        )?;

        let size_params = uniform_from_val(
            device,
            "type_check.interface.identity_size_params",
            &SemanticInterfaceIdentitySizeParams {
                name_capacity,
                module_capacity,
                decl_capacity,
                module_segment_capacity,
                module_index_capacity: module_capacity,
                member_capacity,
            },
        );
        let size_bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.interface.identity_sizes"),
            &self.passes.interface_identity_sizes,
            0,
            &[
                ("gParams", size_params.as_entire_binding()),
                ("name_count_out", inputs.name_count_out.as_entire_binding()),
                ("name_spans", inputs.name_spans.as_entire_binding()),
                (
                    "module_count_out",
                    inputs.module_count_out.as_entire_binding(),
                ),
                (
                    "module_key_segment_count",
                    inputs.module_key_segment_count.as_entire_binding(),
                ),
                (
                    "module_key_segment_base",
                    inputs.module_key_segment_base.as_entire_binding(),
                ),
                (
                    "module_key_segment_name_id",
                    inputs.module_key_segment_name_id.as_entire_binding(),
                ),
                (
                    "module_segment_prefix",
                    module_segment_prefix.as_entire_binding(),
                ),
                (
                    "module_segment_total",
                    module_segment_total.as_entire_binding(),
                ),
                (
                    "public_decl_count",
                    inputs.public_decl_count.as_entire_binding(),
                ),
                (
                    "public_decl_local_id",
                    inputs.public_decl_local_id.as_entire_binding(),
                ),
                ("decl_name_id", inputs.decl_name_id.as_entire_binding()),
                (
                    "interface_member_total",
                    type_topology._member_total.as_entire_binding(),
                ),
                (
                    "interface_member_name_id",
                    type_topology._member_name_id.as_entire_binding(),
                ),
                ("interface_name_ref_len", name_ref_len.as_entire_binding()),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;

        let record_params = uniform_from_val(
            device,
            "type_check.interface.identity_record_params",
            &SemanticInterfaceIdentityRecordParams {
                library_id,
                name_capacity,
                module_capacity,
                decl_capacity,
                module_segment_capacity,
                module_index_capacity: module_capacity,
                name_byte_capacity,
                member_capacity,
            },
        );
        let record_bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.interface.identity_records"),
            &self.passes.interface_identity_records,
            0,
            &[
                ("gParams", record_params.as_entire_binding()),
                ("name_count_out", inputs.name_count_out.as_entire_binding()),
                ("name_spans", inputs.name_spans.as_entire_binding()),
                ("name_hash_lo", inputs.name_hash_lo.as_entire_binding()),
                ("name_hash_hi", inputs.name_hash_hi.as_entire_binding()),
                (
                    "module_count_out",
                    inputs.module_count_out.as_entire_binding(),
                ),
                (
                    "module_key_segment_count",
                    inputs.module_key_segment_count.as_entire_binding(),
                ),
                (
                    "module_key_segment_base",
                    inputs.module_key_segment_base.as_entire_binding(),
                ),
                (
                    "module_key_segment_name_id",
                    inputs.module_key_segment_name_id.as_entire_binding(),
                ),
                (
                    "module_segment_prefix",
                    module_segment_prefix.as_entire_binding(),
                ),
                (
                    "module_segment_total",
                    module_segment_total.as_entire_binding(),
                ),
                (
                    "public_decl_count",
                    inputs.public_decl_count.as_entire_binding(),
                ),
                (
                    "public_decl_local_id",
                    inputs.public_decl_local_id.as_entire_binding(),
                ),
                (
                    "public_decl_index_by_local",
                    inputs.public_decl_index_by_local.as_entire_binding(),
                ),
                ("decl_module_id", inputs.decl_module_id.as_entire_binding()),
                ("decl_name_id", inputs.decl_name_id.as_entire_binding()),
                ("decl_namespace", inputs.decl_namespace.as_entire_binding()),
                ("decl_kind", inputs.decl_kind.as_entire_binding()),
                (
                    "decl_parent_type_decl",
                    inputs.decl_parent_type_decl.as_entire_binding(),
                ),
                ("interface_name_ref_len", name_ref_len.as_entire_binding()),
                (
                    "interface_name_ref_prefix",
                    name_ref_prefix.as_entire_binding(),
                ),
                (
                    "interface_signature_type_by_decl",
                    type_topology._signature_type_by_decl.as_entire_binding(),
                ),
                (
                    "interface_member_prefix",
                    type_topology._member_prefix.as_entire_binding(),
                ),
                (
                    "interface_member_count",
                    type_topology._member_count.as_entire_binding(),
                ),
                (
                    "interface_member_total",
                    type_topology._member_total.as_entire_binding(),
                ),
                (
                    "interface_member_name_id",
                    type_topology._member_name_id.as_entire_binding(),
                ),
                ("interface_modules", modules.as_entire_binding()),
                (
                    "interface_module_segments",
                    module_segments.as_entire_binding(),
                ),
                (
                    "interface_declaration_words",
                    declarations.as_entire_binding(),
                ),
                (
                    "interface_member_words",
                    type_topology._members.as_entire_binding(),
                ),
                ("interface_counts", counts.as_entire_binding()),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;

        let byte_params = uniform_from_val(
            device,
            "type_check.interface.identity_byte_params",
            &SemanticInterfaceIdentityByteParams {
                name_capacity,
                source_len,
                name_ref_count,
                module_segment_capacity,
                module_index_capacity: module_capacity,
                decl_capacity,
                member_capacity,
            },
        );
        let byte_bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.interface.identity_bytes"),
            &self.passes.interface_identity_bytes,
            0,
            &[
                ("gParams", byte_params.as_entire_binding()),
                ("name_count_out", inputs.name_count_out.as_entire_binding()),
                ("name_spans", inputs.name_spans.as_entire_binding()),
                (
                    "module_count_out",
                    inputs.module_count_out.as_entire_binding(),
                ),
                (
                    "module_key_segment_count",
                    inputs.module_key_segment_count.as_entire_binding(),
                ),
                (
                    "module_key_segment_base",
                    inputs.module_key_segment_base.as_entire_binding(),
                ),
                (
                    "module_key_segment_name_id",
                    inputs.module_key_segment_name_id.as_entire_binding(),
                ),
                (
                    "module_segment_prefix",
                    module_segment_prefix.as_entire_binding(),
                ),
                (
                    "module_segment_total",
                    module_segment_total.as_entire_binding(),
                ),
                (
                    "public_decl_count",
                    inputs.public_decl_count.as_entire_binding(),
                ),
                (
                    "public_decl_local_id",
                    inputs.public_decl_local_id.as_entire_binding(),
                ),
                ("decl_name_id", inputs.decl_name_id.as_entire_binding()),
                (
                    "interface_member_total",
                    type_topology._member_total.as_entire_binding(),
                ),
                (
                    "interface_member_name_id",
                    type_topology._member_name_id.as_entire_binding(),
                ),
                ("interface_name_ref_len", name_ref_len.as_entire_binding()),
                (
                    "interface_name_ref_prefix",
                    name_ref_prefix.as_entire_binding(),
                ),
                ("source_bytes", source_bytes.as_entire_binding()),
                (
                    "language_symbol_bytes",
                    inputs.language_symbol_bytes.as_entire_binding(),
                ),
                (
                    "interface_name_byte_words",
                    name_byte_words.as_entire_binding(),
                ),
            ],
        )?;

        record_typecheck_clear_buffer(encoder, &name_ref_len, 0, None);
        record_typecheck_clear_buffer(encoder, &name_byte_words, 0, None);
        record_typecheck_clear_buffer(encoder, &counts, 0, None);
        record_counted_u32_scan_bind_groups_with_passes(
            &self.passes,
            encoder,
            module_scan_n_blocks,
            &module_scan_dispatch_args,
            &module_scan,
            "type_check.interface.module_segment_scan",
        )?;
        record_compute(
            encoder,
            &self.passes.interface_identity_sizes,
            &size_bind_group,
            "type_check.interface.identity_sizes",
            identity_work_capacity,
        )?;
        record_counted_u32_scan_bind_groups_with_passes(
            &self.passes,
            encoder,
            scan_n_blocks,
            &scan_dispatch_args,
            &scan,
            "type_check.interface.name_scan",
        )?;
        record_compute(
            encoder,
            &self.passes.interface_identity_records,
            &record_bind_group,
            "type_check.interface.identity_records",
            identity_work_capacity,
        )?;
        record_compute(
            encoder,
            &self.passes.interface_identity_bytes,
            &byte_bind_group,
            "type_check.interface.identity_bytes",
            name_ref_count,
        )?;

        let module_words = (module_capacity as usize).saturating_mul(MODULE_WORDS);
        let segment_words = (module_segment_capacity as usize).saturating_mul(MODULE_SEGMENT_WORDS);
        let declaration_words = (declaration_capacity as usize).saturating_mul(DECLARATION_WORDS);
        let modules_readback =
            readback_u32s(device, "rb.type_check.interface.modules", module_words);
        let module_segments_readback = readback_u32s(
            device,
            "rb.type_check.interface.module_segments",
            segment_words,
        );
        let declarations_readback = readback_u32s(
            device,
            "rb.type_check.interface.declarations",
            declaration_words,
        );
        let name_bytes_readback = readback_u32s(
            device,
            "rb.type_check.interface.name_bytes",
            name_word_capacity,
        );
        let counts_readback = readback_u32s(device, "rb.type_check.interface.counts", COUNT_WORDS);
        let status_readback = readback_u32s(device, "rb.type_check.interface.status", STATUS_WORDS);
        record_typecheck_copy_buffer_to_buffer(
            encoder,
            &modules,
            0,
            &modules_readback,
            0,
            (module_words.max(1) * 4) as u64,
        );
        record_typecheck_copy_buffer_to_buffer(
            encoder,
            &module_segments,
            0,
            &module_segments_readback,
            0,
            (segment_words.max(1) * 4) as u64,
        );
        record_typecheck_copy_buffer_to_buffer(
            encoder,
            &declarations,
            0,
            &declarations_readback,
            0,
            (declaration_words.max(1) * 4) as u64,
        );
        record_typecheck_copy_buffer_to_buffer(
            encoder,
            &type_topology._members,
            0,
            &type_topology.members_readback,
            0,
            u64::from(member_capacity).saturating_mul(MEMBER_WORDS as u64 * 4),
        );
        record_typecheck_copy_buffer_to_buffer(
            encoder,
            &name_byte_words,
            0,
            &name_bytes_readback,
            0,
            (name_word_capacity.max(1) * 4) as u64,
        );
        record_typecheck_copy_buffer_to_buffer(encoder, &counts, 0, &counts_readback, 0, 20);
        record_typecheck_copy_buffer_to_buffer(encoder, &status, 0, &status_readback, 0, 16);

        Ok(RecordedSemanticInterface {
            expected_library_id: library_id,
            expected_unit_id: unit_id,
            module_capacity: module_capacity as usize,
            module_segment_capacity: module_segment_capacity as usize,
            declaration_capacity: declaration_capacity as usize,
            name_byte_capacity: name_byte_capacity as usize,
            _name_ref_len: name_ref_len,
            _name_ref_prefix: name_ref_prefix,
            _scan_local_prefix: scan_local_prefix,
            _scan_block_sum: scan_block_sum,
            _scan_prefix_a: scan_prefix_a,
            _scan_prefix_b: scan_prefix_b,
            _scan_total: scan_total,
            _scan_count: scan_count,
            _scan_dispatch_args: scan_dispatch_args,
            _module_segment_prefix: module_segment_prefix,
            _module_scan_local_prefix: module_scan_local_prefix,
            _module_scan_block_sum: module_scan_block_sum,
            _module_scan_prefix_a: module_scan_prefix_a,
            _module_scan_prefix_b: module_scan_prefix_b,
            _module_segment_total: module_segment_total,
            _module_scan_dispatch_args: module_scan_dispatch_args,
            _modules: modules,
            _module_segments: module_segments,
            _declarations: declarations,
            _name_byte_words: name_byte_words,
            _counts: counts,
            _status: status,
            _type_topology: type_topology,
            modules_readback,
            module_segments_readback,
            declarations_readback,
            name_bytes_readback,
            counts_readback,
            status_readback,
        })
    }

    fn record_semantic_interface_type_topology(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        library_id: u32,
        unit_id: u32,
        hir: GpuSemanticInterfaceHirBuffers<'_>,
        inputs: &GpuSemanticInterfaceIdentityBuffers<'_>,
        status: &wgpu::Buffer,
    ) -> Result<RecordedSemanticInterfaceTypeTopology> {
        let hir_capacity = u32_capacity(hir.compact_hir_core, 4, "semantic-interface compact HIR")?;
        let decl_capacity = u32_capacity(
            inputs.public_decl_local_id,
            1,
            "semantic-interface public declarations",
        )?;
        let capacity = hir_capacity.max(1);
        let token_capacity = u32_capacity(
            inputs.type_expr_ref_tag,
            1,
            "semantic-interface type reference tags",
        )?;
        let type_capacity = capacity
            .checked_add(decl_capacity)
            .and_then(|value| value.checked_add(1))
            .ok_or_else(|| anyhow::anyhow!("semantic-interface type capacity overflows u32"))?;
        let edge_capacity = capacity.checked_add(decl_capacity).ok_or_else(|| {
            anyhow::anyhow!("semantic-interface type-edge capacity overflows u32")
        })?;
        let n_blocks = capacity.div_ceil(256).max(1);
        let params = uniform_from_val(
            device,
            "type_check.interface.type_topology.params",
            &SemanticInterfaceTypeTopologyParams {
                hir_capacity: capacity,
                decl_capacity,
                token_capacity,
                library_id,
                unit_id,
                dependency_type_count: inputs.dependency_type_count,
            },
        );
        let parent = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.parent",
            capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let seed_owner = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.seed_owner",
            capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let child_ordinal = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.child_ordinal",
            capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let direct_type_hir_by_decl = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.direct_type_hir_by_decl",
            decl_capacity.max(1) as usize,
            wgpu::BufferUsages::empty(),
        );
        let index_by_hir = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.index_by_hir",
            capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let root_link_a = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.root_link_a",
            capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let root_link_b = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.root_link_b",
            capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let root_owner_a = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.root_owner_a",
            capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let root_owner_b = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.root_owner_b",
            capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let reverse_flag = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.reverse_flag",
            capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let reverse_prefix = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.reverse_prefix",
            capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let scan_local_prefix = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.scan_local_prefix",
            capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let scan_block_sum = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.scan_block_sum",
            n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let scan_prefix_a = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.scan_prefix_a",
            n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let scan_prefix_b = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.scan_prefix_b",
            n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let count = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.count",
            1,
            wgpu::BufferUsages::empty(),
        );
        let scan_count = initialized_u32_buffer(
            device,
            "type_check.interface.type_topology.scan_count",
            &[capacity],
            wgpu::BufferUsages::STORAGE,
        );
        let hir_order = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.hir_order",
            capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let edge_count = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.edge_count",
            capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let edge_prefix = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.edge_prefix",
            capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let edge_total = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.edge_total",
            1,
            wgpu::BufferUsages::empty(),
        );
        let edges = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.edges",
            edge_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let edge_written = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.edge_written",
            edge_capacity as usize,
            wgpu::BufferUsages::COPY_DST,
        );
        let types = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.types",
            (type_capacity as usize).saturating_mul(TYPE_WORDS),
            wgpu::BufferUsages::empty(),
        );
        let local_decl_by_hir = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.local_decl_by_hir",
            capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let path_classification = typed_storage_u32_rw(
            device,
            "type_check.interface.type_topology.path_classification",
            (capacity as usize).saturating_mul(4),
            wgpu::BufferUsages::empty(),
        );
        let signature_capacity = decl_capacity.max(1);
        let signature_n_blocks = signature_capacity.div_ceil(256).max(1);
        let signature_type_flag = typed_storage_u32_rw(
            device,
            "type_check.interface.signature.type_flag",
            signature_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let signature_type_prefix = typed_storage_u32_rw(
            device,
            "type_check.interface.signature.type_prefix",
            signature_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let signature_type_total = typed_storage_u32_rw(
            device,
            "type_check.interface.signature.type_total",
            1,
            wgpu::BufferUsages::empty(),
        );
        let signature_edge_count = typed_storage_u32_rw(
            device,
            "type_check.interface.signature.edge_count",
            signature_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let signature_edge_prefix = typed_storage_u32_rw(
            device,
            "type_check.interface.signature.edge_prefix",
            signature_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let signature_edge_total = typed_storage_u32_rw(
            device,
            "type_check.interface.signature.edge_total",
            1,
            wgpu::BufferUsages::empty(),
        );
        let signature_type_by_decl = typed_storage_u32_rw(
            device,
            "type_check.interface.signature.type_by_decl",
            signature_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let complete_type_count = typed_storage_u32_rw(
            device,
            "type_check.interface.complete_type_count",
            1,
            wgpu::BufferUsages::empty(),
        );
        let complete_edge_total = typed_storage_u32_rw(
            device,
            "type_check.interface.complete_edge_total",
            1,
            wgpu::BufferUsages::empty(),
        );
        let signature_scan_count = initialized_u32_buffer(
            device,
            "type_check.interface.signature.scan_count",
            &[signature_capacity],
            wgpu::BufferUsages::STORAGE,
        );
        let signature_scan_local_prefix = typed_storage_u32_rw(
            device,
            "type_check.interface.signature.scan_local_prefix",
            signature_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let signature_scan_block_sum = typed_storage_u32_rw(
            device,
            "type_check.interface.signature.scan_block_sum",
            signature_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let signature_scan_prefix_a = typed_storage_u32_rw(
            device,
            "type_check.interface.signature.scan_prefix_a",
            signature_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let signature_scan_prefix_b = typed_storage_u32_rw(
            device,
            "type_check.interface.signature.scan_prefix_b",
            signature_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let member_capacity = capacity
            .checked_add(token_capacity)
            .ok_or_else(|| anyhow::anyhow!("semantic-interface member capacity overflows u32"))?;
        let variant_count_by_hir = typed_storage_u32_rw(
            device,
            "type_check.interface.members.variant_count_by_hir",
            capacity as usize,
            wgpu::BufferUsages::COPY_DST,
        );
        let field_count_by_hir = typed_storage_u32_rw(
            device,
            "type_check.interface.members.field_count_by_hir",
            capacity as usize,
            wgpu::BufferUsages::COPY_DST,
        );
        let generic_type_count_by_decl = typed_storage_u32_rw(
            device,
            "type_check.interface.members.generic_type_count_by_decl",
            signature_capacity as usize,
            wgpu::BufferUsages::COPY_DST,
        );
        let generic_const_count_by_decl = typed_storage_u32_rw(
            device,
            "type_check.interface.members.generic_const_count_by_decl",
            signature_capacity as usize,
            wgpu::BufferUsages::COPY_DST,
        );
        let member_count = typed_storage_u32_rw(
            device,
            "type_check.interface.members.count",
            signature_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let member_prefix = typed_storage_u32_rw(
            device,
            "type_check.interface.members.prefix",
            signature_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let member_total = typed_storage_u32_rw(
            device,
            "type_check.interface.members.total",
            1,
            wgpu::BufferUsages::empty(),
        );
        let members = typed_storage_u32_rw(
            device,
            "type_check.interface.members.records",
            (member_capacity as usize).saturating_mul(MEMBER_WORDS),
            wgpu::BufferUsages::empty(),
        );
        let member_name_id = typed_storage_u32_rw(
            device,
            "type_check.interface.members.name_id",
            member_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let member_index_by_generic_row = typed_storage_u32_rw(
            device,
            "type_check.interface.members.index_by_generic_row",
            token_capacity.max(1) as usize,
            wgpu::BufferUsages::empty(),
        );
        let member_written = typed_storage_u32_rw(
            device,
            "type_check.interface.members.written",
            member_capacity as usize,
            wgpu::BufferUsages::COPY_DST,
        );
        let signature_scan_steps = make_name_scan_steps(
            device,
            NameScanParams {
                n_items: signature_capacity,
                n_blocks: signature_n_blocks,
                scan_step: 0,
            },
        );
        let signature_type_scan = create_counted_u32_scan_bind_groups_with_passes(
            &self.passes,
            device,
            "type_check.interface.signature.type_scan",
            &signature_scan_steps,
            &signature_scan_count,
            &signature_type_flag,
            &signature_type_prefix,
            &signature_type_total,
            &signature_scan_local_prefix,
            &signature_scan_block_sum,
            &signature_scan_prefix_a,
            &signature_scan_prefix_b,
        )?;
        let signature_edge_scan = create_counted_u32_scan_bind_groups_with_passes(
            &self.passes,
            device,
            "type_check.interface.signature.edge_scan",
            &signature_scan_steps,
            &signature_scan_count,
            &signature_edge_count,
            &signature_edge_prefix,
            &signature_edge_total,
            &signature_scan_local_prefix,
            &signature_scan_block_sum,
            &signature_scan_prefix_a,
            &signature_scan_prefix_b,
        )?;
        let member_scan = create_counted_u32_scan_bind_groups_with_passes(
            &self.passes,
            device,
            "type_check.interface.members.scan",
            &signature_scan_steps,
            &signature_scan_count,
            &member_count,
            &member_prefix,
            &member_total,
            &signature_scan_local_prefix,
            &signature_scan_block_sum,
            &signature_scan_prefix_a,
            &signature_scan_prefix_b,
        )?;
        let (signature_dispatch_x, signature_dispatch_y, signature_dispatch_z) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(signature_capacity),
            [
                self.passes.counted_scan_local.thread_group_size[0],
                self.passes.counted_scan_local.thread_group_size[1],
                1,
            ],
        )?;
        let signature_dispatch_args = initialized_u32_buffer(
            device,
            "type_check.interface.signature.dispatch_args",
            &[
                signature_dispatch_x,
                signature_dispatch_y,
                signature_dispatch_z,
            ],
            wgpu::BufferUsages::INDIRECT,
        );
        let [tgsx, tgsy, _] = self.passes.counted_scan_local.thread_group_size;
        let (dispatch_x, dispatch_y, dispatch_z) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(capacity),
            [tgsx, tgsy, 1],
        )?;
        let dispatch_args = initialized_u32_buffer(
            device,
            "type_check.interface.type_topology.dispatch_args",
            &[dispatch_x, dispatch_y, dispatch_z],
            wgpu::BufferUsages::INDIRECT,
        );
        let scan_steps = make_name_scan_steps(
            device,
            NameScanParams {
                n_items: capacity,
                n_blocks,
                scan_step: 0,
            },
        );
        let scan = create_counted_u32_scan_bind_groups_with_passes(
            &self.passes,
            device,
            "type_check.interface.type_topology.scan",
            &scan_steps,
            &scan_count,
            &reverse_flag,
            &reverse_prefix,
            &count,
            &scan_local_prefix,
            &scan_block_sum,
            &scan_prefix_a,
            &scan_prefix_b,
        )?;
        let edge_scan = create_counted_u32_scan_bind_groups_with_passes(
            &self.passes,
            device,
            "type_check.interface.type_topology.edge_scan",
            &scan_steps,
            &scan_count,
            &edge_count,
            &edge_prefix,
            &edge_total,
            &scan_local_prefix,
            &scan_block_sum,
            &scan_prefix_a,
            &scan_prefix_b,
        )?;

        let bind =
            |label: &str, pass: &PassData, bindings: &[(&str, wgpu::BindingResource<'_>)]| {
                bind_group::create_bind_group_from_bindings(device, Some(label), pass, 0, bindings)
            };
        let init = bind(
            "type_check.interface.type_topology.init",
            &self.passes.interface_type_topology_init,
            &[
                ("gParams", params.as_entire_binding()),
                ("interface_type_parent", parent.as_entire_binding()),
                (
                    "interface_type_child_ordinal",
                    child_ordinal.as_entire_binding(),
                ),
                ("interface_type_seed_owner", seed_owner.as_entire_binding()),
                (
                    "interface_type_index_by_hir",
                    index_by_hir.as_entire_binding(),
                ),
            ],
        )?;
        let attach_unary = bind(
            "type_check.interface.type_topology.attach_unary",
            &self.passes.interface_type_topology_attach_unary,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "compact_hir_count",
                    hir.compact_hir_count.as_entire_binding(),
                ),
                ("compact_hir_core", hir.compact_hir_core.as_entire_binding()),
                (
                    "compact_hir_payload",
                    hir.compact_hir_payload.as_entire_binding(),
                ),
                (
                    "compact_type_arg_count",
                    hir.compact_type_arg_count.as_entire_binding(),
                ),
                (
                    "compact_type_args",
                    hir.compact_type_args.as_entire_binding(),
                ),
                ("interface_type_parent", parent.as_entire_binding()),
                (
                    "interface_type_child_ordinal",
                    child_ordinal.as_entire_binding(),
                ),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let seed_declarations = bind(
            "type_check.interface.type_topology.seed_declarations",
            &self.passes.interface_type_topology_seed_declarations,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "compact_hir_count",
                    hir.compact_hir_count.as_entire_binding(),
                ),
                ("compact_hir_core", hir.compact_hir_core.as_entire_binding()),
                (
                    "public_decl_count",
                    inputs.public_decl_count.as_entire_binding(),
                ),
                (
                    "public_decl_local_id",
                    inputs.public_decl_local_id.as_entire_binding(),
                ),
                ("decl_hir_node", inputs.decl_hir_node.as_entire_binding()),
                ("decl_kind", inputs.decl_kind.as_entire_binding()),
                (
                    "compact_fn_return_type",
                    hir.compact_fn_return_type.as_entire_binding(),
                ),
                (
                    "compact_type_alias_target",
                    hir.compact_type_alias_target.as_entire_binding(),
                ),
                (
                    "compact_const_type",
                    hir.compact_const_type.as_entire_binding(),
                ),
                ("interface_type_parent", parent.as_entire_binding()),
                ("interface_type_seed_owner", seed_owner.as_entire_binding()),
                (
                    "interface_decl_direct_type_hir",
                    direct_type_hir_by_decl.as_entire_binding(),
                ),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let seed_params = bind(
            "type_check.interface.type_topology.seed_params",
            &self.passes.interface_type_topology_seed_params,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "compact_hir_count",
                    hir.compact_hir_count.as_entire_binding(),
                ),
                ("compact_hir_core", hir.compact_hir_core.as_entire_binding()),
                (
                    "compact_param_count",
                    hir.compact_param_count.as_entire_binding(),
                ),
                ("compact_params", hir.compact_params.as_entire_binding()),
                (
                    "public_decl_index_by_hir",
                    inputs.public_decl_index_by_hir.as_entire_binding(),
                ),
                ("interface_type_parent", parent.as_entire_binding()),
                ("interface_type_seed_owner", seed_owner.as_entire_binding()),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let seed_fields = bind(
            "type_check.interface.type_topology.seed_fields",
            &self.passes.interface_type_topology_seed_fields,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "compact_hir_count",
                    hir.compact_hir_count.as_entire_binding(),
                ),
                ("compact_hir_core", hir.compact_hir_core.as_entire_binding()),
                (
                    "compact_field_count",
                    hir.compact_field_count.as_entire_binding(),
                ),
                ("compact_fields", hir.compact_fields.as_entire_binding()),
                (
                    "public_decl_index_by_hir",
                    inputs.public_decl_index_by_hir.as_entire_binding(),
                ),
                ("interface_type_parent", parent.as_entire_binding()),
                ("interface_type_seed_owner", seed_owner.as_entire_binding()),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let seed_variants = bind(
            "type_check.interface.type_topology.seed_variants",
            &self.passes.interface_type_topology_seed_variants,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "compact_hir_count",
                    hir.compact_hir_count.as_entire_binding(),
                ),
                ("compact_hir_core", hir.compact_hir_core.as_entire_binding()),
                (
                    "compact_variant_count",
                    hir.compact_variant_count.as_entire_binding(),
                ),
                (
                    "compact_variant_payload_row_count",
                    hir.compact_variant_payload_row_count.as_entire_binding(),
                ),
                ("compact_variants", hir.compact_variants.as_entire_binding()),
                (
                    "compact_variant_payloads",
                    hir.compact_variant_payloads.as_entire_binding(),
                ),
                (
                    "decl_id_by_name_token",
                    inputs.decl_id_by_name_token.as_entire_binding(),
                ),
                (
                    "public_decl_index_by_local",
                    inputs.public_decl_index_by_local.as_entire_binding(),
                ),
                ("interface_type_parent", parent.as_entire_binding()),
                ("interface_type_seed_owner", seed_owner.as_entire_binding()),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let root_init = bind(
            "type_check.interface.type_topology.root_init",
            &self.passes.interface_type_topology_root_init,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "compact_hir_count",
                    hir.compact_hir_count.as_entire_binding(),
                ),
                ("compact_hir_core", hir.compact_hir_core.as_entire_binding()),
                ("interface_type_parent", parent.as_entire_binding()),
                ("interface_type_root_link", root_link_a.as_entire_binding()),
                (
                    "interface_type_root_owner",
                    root_owner_a.as_entire_binding(),
                ),
            ],
        )?;
        let root_step_ab = bind(
            "type_check.interface.type_topology.root_step_ab",
            &self.passes.interface_type_topology_root_step,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "interface_type_root_link_in",
                    root_link_a.as_entire_binding(),
                ),
                (
                    "interface_type_root_owner_in",
                    root_owner_a.as_entire_binding(),
                ),
                (
                    "interface_type_root_link_out",
                    root_link_b.as_entire_binding(),
                ),
                (
                    "interface_type_root_owner_out",
                    root_owner_b.as_entire_binding(),
                ),
            ],
        )?;
        let root_step_ba = bind(
            "type_check.interface.type_topology.root_step_ba",
            &self.passes.interface_type_topology_root_step,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "interface_type_root_link_in",
                    root_link_b.as_entire_binding(),
                ),
                (
                    "interface_type_root_owner_in",
                    root_owner_b.as_entire_binding(),
                ),
                (
                    "interface_type_root_link_out",
                    root_link_a.as_entire_binding(),
                ),
                (
                    "interface_type_root_owner_out",
                    root_owner_a.as_entire_binding(),
                ),
            ],
        )?;
        let root_steps = u32::BITS - (capacity - 1).leading_zeros();
        let final_root_owner = if root_steps & 1 == 0 {
            &root_owner_a
        } else {
            &root_owner_b
        };
        let mark_reverse = bind(
            "type_check.interface.type_topology.mark_reverse",
            &self.passes.interface_type_topology_mark_reverse,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "compact_hir_count",
                    hir.compact_hir_count.as_entire_binding(),
                ),
                ("compact_hir_core", hir.compact_hir_core.as_entire_binding()),
                (
                    "interface_type_root_owner",
                    final_root_owner.as_entire_binding(),
                ),
                ("interface_type_seed_owner", seed_owner.as_entire_binding()),
                (
                    "interface_type_reverse_flag",
                    reverse_flag.as_entire_binding(),
                ),
            ],
        )?;
        let scatter = bind(
            "type_check.interface.type_topology.scatter",
            &self.passes.interface_type_topology_scatter,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "interface_type_reverse_flag",
                    reverse_flag.as_entire_binding(),
                ),
                (
                    "interface_type_reverse_prefix",
                    reverse_prefix.as_entire_binding(),
                ),
                ("interface_type_hir_order", hir_order.as_entire_binding()),
                (
                    "interface_type_index_by_hir",
                    index_by_hir.as_entire_binding(),
                ),
            ],
        )?;
        let edge_counts = bind(
            "type_check.interface.type_topology.edge_counts",
            &self.passes.interface_type_topology_edge_counts,
            &[
                ("gParams", params.as_entire_binding()),
                ("interface_type_count", count.as_entire_binding()),
                ("interface_type_hir_order", hir_order.as_entire_binding()),
                (
                    "compact_hir_payload",
                    hir.compact_hir_payload.as_entire_binding(),
                ),
                (
                    "compact_type_arg_ranges",
                    hir.compact_type_arg_ranges.as_entire_binding(),
                ),
                ("interface_type_edge_count", edge_count.as_entire_binding()),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let edge_scatter = bind(
            "type_check.interface.type_topology.edge_scatter",
            &self.passes.interface_type_topology_edge_scatter,
            &[
                ("gParams", params.as_entire_binding()),
                ("interface_type_count", count.as_entire_binding()),
                ("interface_type_parent", parent.as_entire_binding()),
                (
                    "interface_type_child_ordinal",
                    child_ordinal.as_entire_binding(),
                ),
                (
                    "interface_type_index_by_hir",
                    index_by_hir.as_entire_binding(),
                ),
                (
                    "interface_type_edge_prefix",
                    edge_prefix.as_entire_binding(),
                ),
                ("interface_type_edge_count", edge_count.as_entire_binding()),
                ("interface_type_edges", edges.as_entire_binding()),
                (
                    "interface_type_edge_written",
                    edge_written.as_entire_binding(),
                ),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let resolve_local_decl = bind(
            "type_check.interface.type_topology.resolve_local_decl",
            &self.passes.interface_type_topology_resolve_local_decl,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "compact_hir_count",
                    hir.compact_hir_count.as_entire_binding(),
                ),
                ("compact_hir_core", hir.compact_hir_core.as_entire_binding()),
                (
                    "type_expr_ref_tag",
                    inputs.type_expr_ref_tag.as_entire_binding(),
                ),
                (
                    "type_expr_ref_payload",
                    inputs.type_expr_ref_payload.as_entire_binding(),
                ),
                (
                    "type_instance_decl_token",
                    inputs.type_instance_decl_token.as_entire_binding(),
                ),
                (
                    "path_id_by_owner_token",
                    inputs.path_id_by_owner_token.as_entire_binding(),
                ),
                (
                    "resolved_type_decl",
                    inputs.resolved_type_decl.as_entire_binding(),
                ),
                (
                    "decl_id_by_name_token",
                    inputs.decl_id_by_name_token.as_entire_binding(),
                ),
                (
                    "interface_type_local_decl_by_hir",
                    local_decl_by_hir.as_entire_binding(),
                ),
            ],
        )?;
        let classify_path = bind(
            "type_check.interface.type_topology.classify_path",
            &self.passes.interface_type_topology_classify_path,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "compact_hir_count",
                    hir.compact_hir_count.as_entire_binding(),
                ),
                ("compact_hir_core", hir.compact_hir_core.as_entire_binding()),
                (
                    "compact_hir_payload",
                    hir.compact_hir_payload.as_entire_binding(),
                ),
                (
                    "type_expr_ref_tag",
                    inputs.type_expr_ref_tag.as_entire_binding(),
                ),
                (
                    "type_expr_ref_payload",
                    inputs.type_expr_ref_payload.as_entire_binding(),
                ),
                (
                    "type_generic_param_slot_by_token",
                    inputs.type_generic_param_slot_by_token.as_entire_binding(),
                ),
                (
                    "type_instance_external_canonical",
                    inputs.type_instance_external_canonical.as_entire_binding(),
                ),
                (
                    "dependency_type_words",
                    inputs.dependency_type_words.as_entire_binding(),
                ),
                (
                    "interface_type_local_decl_by_hir",
                    local_decl_by_hir.as_entire_binding(),
                ),
                (
                    "public_decl_index_by_local",
                    inputs.public_decl_index_by_local.as_entire_binding(),
                ),
                (
                    "interface_type_path_classification",
                    path_classification.as_entire_binding(),
                ),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let type_records = bind(
            "type_check.interface.type_topology.type_records",
            &self.passes.interface_type_topology_type_records,
            &[
                ("gParams", params.as_entire_binding()),
                ("interface_type_count", count.as_entire_binding()),
                ("interface_type_hir_order", hir_order.as_entire_binding()),
                (
                    "interface_type_edge_prefix",
                    edge_prefix.as_entire_binding(),
                ),
                ("interface_type_edge_count", edge_count.as_entire_binding()),
                (
                    "compact_hir_payload",
                    hir.compact_hir_payload.as_entire_binding(),
                ),
                (
                    "interface_type_path_classification",
                    path_classification.as_entire_binding(),
                ),
                ("interface_types", types.as_entire_binding()),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let array_lengths = bind(
            "type_check.interface.type_topology.array_lengths",
            &self.passes.interface_type_topology_array_lengths,
            &[
                ("gParams", params.as_entire_binding()),
                ("interface_type_count", count.as_entire_binding()),
                ("interface_type_hir_order", hir_order.as_entire_binding()),
                (
                    "compact_hir_payload",
                    hir.compact_hir_payload.as_entire_binding(),
                ),
                (
                    "type_const_param_slot_by_token",
                    inputs.type_const_param_slot_by_token.as_entire_binding(),
                ),
                ("interface_types", types.as_entire_binding()),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let signature_flags = bind(
            "type_check.interface.signature.flags",
            &self.passes.interface_signature_flags,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "public_decl_count",
                    inputs.public_decl_count.as_entire_binding(),
                ),
                (
                    "public_decl_local_id",
                    inputs.public_decl_local_id.as_entire_binding(),
                ),
                ("decl_kind", inputs.decl_kind.as_entire_binding()),
                ("decl_hir_node", inputs.decl_hir_node.as_entire_binding()),
                (
                    "compact_hir_count",
                    hir.compact_hir_count.as_entire_binding(),
                ),
                (
                    "compact_param_ranges",
                    hir.compact_param_ranges.as_entire_binding(),
                ),
                (
                    "compact_variant_count",
                    hir.compact_variant_count.as_entire_binding(),
                ),
                (
                    "compact_variant_payload_count",
                    hir.compact_variant_payload_count.as_entire_binding(),
                ),
                (
                    "interface_signature_type_flag",
                    signature_type_flag.as_entire_binding(),
                ),
                (
                    "interface_signature_edge_count",
                    signature_edge_count.as_entire_binding(),
                ),
                (
                    "interface_signature_type_by_decl",
                    signature_type_by_decl.as_entire_binding(),
                ),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let signature_totals = bind(
            "type_check.interface.signature.totals",
            &self.passes.interface_signature_totals,
            &[
                ("gParams", params.as_entire_binding()),
                ("interface_type_count", count.as_entire_binding()),
                ("interface_type_edge_total", edge_total.as_entire_binding()),
                (
                    "interface_signature_type_total",
                    signature_type_total.as_entire_binding(),
                ),
                (
                    "interface_signature_edge_total",
                    signature_edge_total.as_entire_binding(),
                ),
                ("interface_types", types.as_entire_binding()),
                (
                    "interface_complete_type_count",
                    complete_type_count.as_entire_binding(),
                ),
                (
                    "interface_complete_edge_total",
                    complete_edge_total.as_entire_binding(),
                ),
            ],
        )?;
        let signature_direct_types = bind(
            "type_check.interface.signature.direct_types",
            &self.passes.interface_signature_direct_types,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "public_decl_count",
                    inputs.public_decl_count.as_entire_binding(),
                ),
                (
                    "interface_signature_type_flag",
                    signature_type_flag.as_entire_binding(),
                ),
                (
                    "interface_decl_direct_type_hir",
                    direct_type_hir_by_decl.as_entire_binding(),
                ),
                (
                    "interface_type_index_by_hir",
                    index_by_hir.as_entire_binding(),
                ),
                (
                    "interface_signature_type_by_decl",
                    signature_type_by_decl.as_entire_binding(),
                ),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let signature_synthetic_types = bind(
            "type_check.interface.signature.synthetic_types",
            &self.passes.interface_signature_synthetic_types,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "public_decl_count",
                    inputs.public_decl_count.as_entire_binding(),
                ),
                (
                    "public_decl_local_id",
                    inputs.public_decl_local_id.as_entire_binding(),
                ),
                ("decl_kind", inputs.decl_kind.as_entire_binding()),
                ("interface_type_count", count.as_entire_binding()),
                ("interface_type_edge_total", edge_total.as_entire_binding()),
                (
                    "interface_signature_type_flag",
                    signature_type_flag.as_entire_binding(),
                ),
                (
                    "interface_signature_type_prefix",
                    signature_type_prefix.as_entire_binding(),
                ),
                (
                    "interface_signature_edge_count",
                    signature_edge_count.as_entire_binding(),
                ),
                (
                    "interface_signature_edge_prefix",
                    signature_edge_prefix.as_entire_binding(),
                ),
                (
                    "interface_signature_type_by_decl",
                    signature_type_by_decl.as_entire_binding(),
                ),
                ("interface_types", types.as_entire_binding()),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let signature_param_edges = bind(
            "type_check.interface.signature.param_edges",
            &self.passes.interface_signature_param_edges,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "compact_param_count",
                    hir.compact_param_count.as_entire_binding(),
                ),
                ("compact_params", hir.compact_params.as_entire_binding()),
                (
                    "public_decl_index_by_hir",
                    inputs.public_decl_index_by_hir.as_entire_binding(),
                ),
                (
                    "interface_signature_edge_count",
                    signature_edge_count.as_entire_binding(),
                ),
                (
                    "interface_signature_edge_prefix",
                    signature_edge_prefix.as_entire_binding(),
                ),
                ("interface_type_edge_total", edge_total.as_entire_binding()),
                (
                    "interface_type_index_by_hir",
                    index_by_hir.as_entire_binding(),
                ),
                ("interface_type_edges", edges.as_entire_binding()),
                (
                    "interface_type_edge_written",
                    edge_written.as_entire_binding(),
                ),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let signature_return_edges = bind(
            "type_check.interface.signature.return_edges",
            &self.passes.interface_signature_return_edges,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "public_decl_count",
                    inputs.public_decl_count.as_entire_binding(),
                ),
                (
                    "public_decl_local_id",
                    inputs.public_decl_local_id.as_entire_binding(),
                ),
                ("decl_kind", inputs.decl_kind.as_entire_binding()),
                ("interface_type_count", count.as_entire_binding()),
                ("interface_type_edge_total", edge_total.as_entire_binding()),
                (
                    "interface_signature_edge_count",
                    signature_edge_count.as_entire_binding(),
                ),
                (
                    "interface_signature_edge_prefix",
                    signature_edge_prefix.as_entire_binding(),
                ),
                (
                    "interface_decl_direct_type_hir",
                    direct_type_hir_by_decl.as_entire_binding(),
                ),
                (
                    "interface_type_index_by_hir",
                    index_by_hir.as_entire_binding(),
                ),
                (
                    "decl_parent_type_decl",
                    inputs.decl_parent_type_decl.as_entire_binding(),
                ),
                (
                    "public_decl_index_by_local",
                    inputs.public_decl_index_by_local.as_entire_binding(),
                ),
                (
                    "interface_signature_type_by_decl",
                    signature_type_by_decl.as_entire_binding(),
                ),
                ("interface_type_edges", edges.as_entire_binding()),
                (
                    "interface_type_edge_written",
                    edge_written.as_entire_binding(),
                ),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let signature_variant_payload_edges = bind(
            "type_check.interface.signature.variant_payload_edges",
            &self.passes.interface_signature_variant_payload_edges,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "compact_variant_payload_row_count",
                    hir.compact_variant_payload_row_count.as_entire_binding(),
                ),
                (
                    "compact_variant_count",
                    hir.compact_variant_count.as_entire_binding(),
                ),
                ("compact_variants", hir.compact_variants.as_entire_binding()),
                (
                    "compact_variant_payloads",
                    hir.compact_variant_payloads.as_entire_binding(),
                ),
                (
                    "decl_id_by_name_token",
                    inputs.decl_id_by_name_token.as_entire_binding(),
                ),
                (
                    "public_decl_index_by_local",
                    inputs.public_decl_index_by_local.as_entire_binding(),
                ),
                (
                    "interface_signature_edge_count",
                    signature_edge_count.as_entire_binding(),
                ),
                (
                    "interface_signature_edge_prefix",
                    signature_edge_prefix.as_entire_binding(),
                ),
                ("interface_type_edge_total", edge_total.as_entire_binding()),
                (
                    "interface_type_index_by_hir",
                    index_by_hir.as_entire_binding(),
                ),
                ("interface_type_edges", edges.as_entire_binding()),
                (
                    "interface_type_edge_written",
                    edge_written.as_entire_binding(),
                ),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let members_variant_counts = bind(
            "type_check.interface.members.variant_counts",
            &self.passes.interface_members_variant_counts,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "compact_field_count",
                    hir.compact_field_count.as_entire_binding(),
                ),
                ("compact_fields", hir.compact_fields.as_entire_binding()),
                (
                    "compact_variant_count",
                    hir.compact_variant_count.as_entire_binding(),
                ),
                ("compact_variants", hir.compact_variants.as_entire_binding()),
                (
                    "interface_field_count_by_hir",
                    field_count_by_hir.as_entire_binding(),
                ),
                (
                    "interface_variant_count_by_hir",
                    variant_count_by_hir.as_entire_binding(),
                ),
            ],
        )?;
        let members_generic_counts = bind(
            "type_check.interface.members.generic_counts",
            &self.passes.interface_members_generic_counts,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "generic_param_count_out",
                    inputs.generic_param_count_out.as_entire_binding(),
                ),
                (
                    "generic_param_owner_token",
                    inputs.generic_param_owner_token.as_entire_binding(),
                ),
                (
                    "generic_param_token",
                    inputs.generic_param_token.as_entire_binding(),
                ),
                (
                    "generic_param_kind",
                    inputs.generic_param_kind.as_entire_binding(),
                ),
                (
                    "type_generic_param_slot_by_token",
                    inputs.type_generic_param_slot_by_token.as_entire_binding(),
                ),
                (
                    "type_const_param_slot_by_token",
                    inputs.type_const_param_slot_by_token.as_entire_binding(),
                ),
                (
                    "decl_id_by_name_token",
                    inputs.decl_id_by_name_token.as_entire_binding(),
                ),
                (
                    "public_decl_index_by_local",
                    inputs.public_decl_index_by_local.as_entire_binding(),
                ),
                (
                    "interface_generic_type_count_by_decl",
                    generic_type_count_by_decl.as_entire_binding(),
                ),
                (
                    "interface_generic_const_count_by_decl",
                    generic_const_count_by_decl.as_entire_binding(),
                ),
            ],
        )?;
        let members_counts = bind(
            "type_check.interface.members.counts",
            &self.passes.interface_members_counts,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "public_decl_count",
                    inputs.public_decl_count.as_entire_binding(),
                ),
                (
                    "public_decl_local_id",
                    inputs.public_decl_local_id.as_entire_binding(),
                ),
                ("decl_kind", inputs.decl_kind.as_entire_binding()),
                ("decl_hir_node", inputs.decl_hir_node.as_entire_binding()),
                (
                    "compact_hir_count",
                    hir.compact_hir_count.as_entire_binding(),
                ),
                (
                    "compact_param_ranges",
                    hir.compact_param_ranges.as_entire_binding(),
                ),
                (
                    "interface_field_count_by_hir",
                    field_count_by_hir.as_entire_binding(),
                ),
                (
                    "interface_variant_count_by_hir",
                    variant_count_by_hir.as_entire_binding(),
                ),
                (
                    "interface_generic_type_count_by_decl",
                    generic_type_count_by_decl.as_entire_binding(),
                ),
                (
                    "interface_generic_const_count_by_decl",
                    generic_const_count_by_decl.as_entire_binding(),
                ),
                ("interface_member_count", member_count.as_entire_binding()),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let members_scatter_hir = bind(
            "type_check.interface.members.scatter_hir",
            &self.passes.interface_members_scatter_hir,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "compact_param_count",
                    hir.compact_param_count.as_entire_binding(),
                ),
                ("compact_params", hir.compact_params.as_entire_binding()),
                (
                    "compact_field_count",
                    hir.compact_field_count.as_entire_binding(),
                ),
                ("compact_fields", hir.compact_fields.as_entire_binding()),
                (
                    "compact_variant_count",
                    hir.compact_variant_count.as_entire_binding(),
                ),
                ("compact_variants", hir.compact_variants.as_entire_binding()),
                (
                    "public_decl_index_by_hir",
                    inputs.public_decl_index_by_hir.as_entire_binding(),
                ),
                (
                    "public_decl_index_by_local",
                    inputs.public_decl_index_by_local.as_entire_binding(),
                ),
                (
                    "decl_id_by_name_token",
                    inputs.decl_id_by_name_token.as_entire_binding(),
                ),
                (
                    "name_id_by_token",
                    inputs.name_id_by_token.as_entire_binding(),
                ),
                (
                    "interface_generic_type_count_by_decl",
                    generic_type_count_by_decl.as_entire_binding(),
                ),
                (
                    "interface_generic_const_count_by_decl",
                    generic_const_count_by_decl.as_entire_binding(),
                ),
                ("interface_member_prefix", member_prefix.as_entire_binding()),
                (
                    "interface_type_index_by_hir",
                    index_by_hir.as_entire_binding(),
                ),
                (
                    "interface_signature_type_by_decl",
                    signature_type_by_decl.as_entire_binding(),
                ),
                ("interface_member_words", members.as_entire_binding()),
                (
                    "interface_member_name_id",
                    member_name_id.as_entire_binding(),
                ),
                (
                    "interface_member_written",
                    member_written.as_entire_binding(),
                ),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let members_scatter_generic = bind(
            "type_check.interface.members.scatter_generic",
            &self.passes.interface_members_scatter_generic,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "generic_param_count_out",
                    inputs.generic_param_count_out.as_entire_binding(),
                ),
                (
                    "generic_param_owner_token",
                    inputs.generic_param_owner_token.as_entire_binding(),
                ),
                (
                    "generic_param_name_id",
                    inputs.generic_param_name_id.as_entire_binding(),
                ),
                (
                    "generic_param_token",
                    inputs.generic_param_token.as_entire_binding(),
                ),
                (
                    "generic_param_kind",
                    inputs.generic_param_kind.as_entire_binding(),
                ),
                (
                    "type_generic_param_slot_by_token",
                    inputs.type_generic_param_slot_by_token.as_entire_binding(),
                ),
                (
                    "type_const_param_slot_by_token",
                    inputs.type_const_param_slot_by_token.as_entire_binding(),
                ),
                (
                    "interface_generic_type_count_by_decl",
                    generic_type_count_by_decl.as_entire_binding(),
                ),
                (
                    "decl_id_by_name_token",
                    inputs.decl_id_by_name_token.as_entire_binding(),
                ),
                (
                    "public_decl_index_by_local",
                    inputs.public_decl_index_by_local.as_entire_binding(),
                ),
                ("interface_member_prefix", member_prefix.as_entire_binding()),
                ("interface_member_words", members.as_entire_binding()),
                (
                    "interface_member_name_id",
                    member_name_id.as_entire_binding(),
                ),
                (
                    "interface_member_index_by_generic_row",
                    member_index_by_generic_row.as_entire_binding(),
                ),
                (
                    "interface_member_written",
                    member_written.as_entire_binding(),
                ),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let members_normalize_types = bind(
            "type_check.interface.members.normalize_types",
            &self.passes.interface_members_normalize_types,
            &[
                ("gParams", params.as_entire_binding()),
                ("interface_type_count", count.as_entire_binding()),
                ("interface_type_hir_order", hir_order.as_entire_binding()),
                (
                    "interface_type_root_owner",
                    final_root_owner.as_entire_binding(),
                ),
                ("interface_type_seed_owner", seed_owner.as_entire_binding()),
                ("interface_member_prefix", member_prefix.as_entire_binding()),
                ("interface_member_total", member_total.as_entire_binding()),
                (
                    "interface_generic_type_count_by_decl",
                    generic_type_count_by_decl.as_entire_binding(),
                ),
                ("interface_types", types.as_entire_binding()),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;
        let validate = bind(
            "type_check.interface.type_topology.validate",
            &self.passes.interface_type_topology_validate,
            &[
                ("gParams", params.as_entire_binding()),
                ("interface_type_count", count.as_entire_binding()),
                ("interface_type_hir_order", hir_order.as_entire_binding()),
                ("interface_type_parent", parent.as_entire_binding()),
                (
                    "interface_type_index_by_hir",
                    index_by_hir.as_entire_binding(),
                ),
                ("interface_status", status.as_entire_binding()),
            ],
        )?;

        record_typecheck_clear_buffer(encoder, &edge_written, 0, None);
        record_typecheck_clear_buffer(encoder, &field_count_by_hir, 0, None);
        record_typecheck_clear_buffer(encoder, &variant_count_by_hir, 0, None);
        record_typecheck_clear_buffer(encoder, &generic_type_count_by_decl, 0, None);
        record_typecheck_clear_buffer(encoder, &generic_const_count_by_decl, 0, None);
        record_typecheck_clear_buffer(encoder, &member_written, 0, None);
        record_compute(
            encoder,
            &self.passes.interface_type_topology_init,
            &init,
            "type_check.interface.type_topology.init",
            capacity,
        )?;
        record_compute(
            encoder,
            &self.passes.interface_type_topology_attach_unary,
            &attach_unary,
            "type_check.interface.type_topology.attach_unary",
            capacity,
        )?;
        for (pass, group, label) in [
            (
                &self.passes.interface_type_topology_seed_declarations,
                &seed_declarations,
                "type_check.interface.type_topology.seed_declarations",
            ),
            (
                &self.passes.interface_type_topology_seed_params,
                &seed_params,
                "type_check.interface.type_topology.seed_params",
            ),
            (
                &self.passes.interface_type_topology_seed_fields,
                &seed_fields,
                "type_check.interface.type_topology.seed_fields",
            ),
            (
                &self.passes.interface_type_topology_seed_variants,
                &seed_variants,
                "type_check.interface.type_topology.seed_variants",
            ),
        ] {
            record_compute(encoder, pass, group, label, capacity)?;
        }
        record_compute(
            encoder,
            &self.passes.interface_type_topology_root_init,
            &root_init,
            "type_check.interface.type_topology.root_init",
            capacity,
        )?;
        for step in 0..root_steps {
            let group = if step & 1 == 0 {
                &root_step_ab
            } else {
                &root_step_ba
            };
            record_compute(
                encoder,
                &self.passes.interface_type_topology_root_step,
                group,
                "type_check.interface.type_topology.root_step",
                capacity,
            )?;
        }
        record_compute(
            encoder,
            &self.passes.interface_type_topology_mark_reverse,
            &mark_reverse,
            "type_check.interface.type_topology.mark_reverse",
            capacity,
        )?;
        record_counted_u32_scan_bind_groups_with_passes(
            &self.passes,
            encoder,
            n_blocks,
            &dispatch_args,
            &scan,
            "type_check.interface.type_topology.scan",
        )?;
        record_compute(
            encoder,
            &self.passes.interface_type_topology_scatter,
            &scatter,
            "type_check.interface.type_topology.scatter",
            capacity,
        )?;
        record_compute(
            encoder,
            &self.passes.interface_type_topology_edge_counts,
            &edge_counts,
            "type_check.interface.type_topology.edge_counts",
            capacity,
        )?;
        record_counted_u32_scan_bind_groups_with_passes(
            &self.passes,
            encoder,
            n_blocks,
            &dispatch_args,
            &edge_scan,
            "type_check.interface.type_topology.edge_scan",
        )?;
        record_compute(
            encoder,
            &self.passes.interface_type_topology_edge_scatter,
            &edge_scatter,
            "type_check.interface.type_topology.edge_scatter",
            capacity,
        )?;
        for (pass, group, label) in [
            (
                &self.passes.interface_type_topology_resolve_local_decl,
                &resolve_local_decl,
                "type_check.interface.type_topology.resolve_local_decl",
            ),
            (
                &self.passes.interface_type_topology_classify_path,
                &classify_path,
                "type_check.interface.type_topology.classify_path",
            ),
            (
                &self.passes.interface_type_topology_type_records,
                &type_records,
                "type_check.interface.type_topology.type_records",
            ),
            (
                &self.passes.interface_type_topology_array_lengths,
                &array_lengths,
                "type_check.interface.type_topology.array_lengths",
            ),
        ] {
            record_compute(encoder, pass, group, label, capacity)?;
        }
        record_compute(
            encoder,
            &self.passes.interface_type_topology_validate,
            &validate,
            "type_check.interface.type_topology.validate",
            capacity,
        )?;
        record_compute(
            encoder,
            &self.passes.interface_signature_flags,
            &signature_flags,
            "type_check.interface.signature.flags",
            signature_capacity,
        )?;
        record_counted_u32_scan_bind_groups_with_passes(
            &self.passes,
            encoder,
            signature_n_blocks,
            &signature_dispatch_args,
            &signature_type_scan,
            "type_check.interface.signature.type_scan",
        )?;
        record_counted_u32_scan_bind_groups_with_passes(
            &self.passes,
            encoder,
            signature_n_blocks,
            &signature_dispatch_args,
            &signature_edge_scan,
            "type_check.interface.signature.edge_scan",
        )?;
        record_compute(
            encoder,
            &self.passes.interface_signature_totals,
            &signature_totals,
            "type_check.interface.signature.totals",
            1,
        )?;
        for (pass, group, label, work) in [
            (
                &self.passes.interface_signature_direct_types,
                &signature_direct_types,
                "type_check.interface.signature.direct_types",
                signature_capacity,
            ),
            (
                &self.passes.interface_signature_synthetic_types,
                &signature_synthetic_types,
                "type_check.interface.signature.synthetic_types",
                signature_capacity,
            ),
            (
                &self.passes.interface_signature_param_edges,
                &signature_param_edges,
                "type_check.interface.signature.param_edges",
                capacity,
            ),
            (
                &self.passes.interface_signature_variant_payload_edges,
                &signature_variant_payload_edges,
                "type_check.interface.signature.variant_payload_edges",
                capacity,
            ),
            (
                &self.passes.interface_signature_return_edges,
                &signature_return_edges,
                "type_check.interface.signature.return_edges",
                signature_capacity,
            ),
        ] {
            record_compute(encoder, pass, group, label, work)?;
        }
        record_compute(
            encoder,
            &self.passes.interface_members_variant_counts,
            &members_variant_counts,
            "type_check.interface.members.variant_counts",
            capacity,
        )?;
        record_compute(
            encoder,
            &self.passes.interface_members_generic_counts,
            &members_generic_counts,
            "type_check.interface.members.generic_counts",
            token_capacity.max(1),
        )?;
        record_compute(
            encoder,
            &self.passes.interface_members_counts,
            &members_counts,
            "type_check.interface.members.counts",
            signature_capacity,
        )?;
        record_counted_u32_scan_bind_groups_with_passes(
            &self.passes,
            encoder,
            signature_n_blocks,
            &signature_dispatch_args,
            &member_scan,
            "type_check.interface.members.scan",
        )?;
        record_compute(
            encoder,
            &self.passes.interface_members_scatter_hir,
            &members_scatter_hir,
            "type_check.interface.members.scatter_hir",
            capacity,
        )?;
        record_compute(
            encoder,
            &self.passes.interface_members_scatter_generic,
            &members_scatter_generic,
            "type_check.interface.members.scatter_generic",
            token_capacity.max(1),
        )?;
        record_compute(
            encoder,
            &self.passes.interface_members_normalize_types,
            &members_normalize_types,
            "type_check.interface.members.normalize_types",
            capacity,
        )?;

        let count_readback = readback_u32s(device, "rb.type_check.interface.type_count", 1);
        let edge_total_readback =
            readback_u32s(device, "rb.type_check.interface.type_edge_total", 1);
        let types_readback = readback_u32s(
            device,
            "rb.type_check.interface.types",
            (type_capacity as usize).saturating_mul(TYPE_WORDS),
        );
        let edges_readback = readback_u32s(
            device,
            "rb.type_check.interface.type_edges",
            edge_capacity as usize,
        );
        let edge_written_readback = readback_u32s(
            device,
            "rb.type_check.interface.type_edge_written",
            edge_capacity as usize,
        );
        let member_total_readback =
            readback_u32s(device, "rb.type_check.interface.member_total", 1);
        let member_written_readback = readback_u32s(
            device,
            "rb.type_check.interface.member_written",
            member_capacity as usize,
        );
        let members_readback = readback_u32s(
            device,
            "rb.type_check.interface.members",
            (member_capacity as usize).saturating_mul(MEMBER_WORDS),
        );
        record_typecheck_copy_buffer_to_buffer(
            encoder,
            &complete_type_count,
            0,
            &count_readback,
            0,
            4,
        );
        record_typecheck_copy_buffer_to_buffer(
            encoder,
            &complete_edge_total,
            0,
            &edge_total_readback,
            0,
            4,
        );
        record_typecheck_copy_buffer_to_buffer(
            encoder,
            &types,
            0,
            &types_readback,
            0,
            u64::from(type_capacity).saturating_mul(TYPE_WORDS as u64 * 4),
        );
        record_typecheck_copy_buffer_to_buffer(
            encoder,
            &edges,
            0,
            &edges_readback,
            0,
            u64::from(edge_capacity).saturating_mul(4),
        );
        record_typecheck_copy_buffer_to_buffer(
            encoder,
            &member_total,
            0,
            &member_total_readback,
            0,
            4,
        );
        record_typecheck_copy_buffer_to_buffer(
            encoder,
            &member_written,
            0,
            &member_written_readback,
            0,
            u64::from(member_capacity).saturating_mul(4),
        );
        record_typecheck_copy_buffer_to_buffer(
            encoder,
            &edge_written,
            0,
            &edge_written_readback,
            0,
            u64::from(edge_capacity).saturating_mul(4),
        );

        Ok(RecordedSemanticInterfaceTypeTopology {
            type_capacity: type_capacity as usize,
            edge_capacity: edge_capacity as usize,
            member_capacity: member_capacity as usize,
            _parent: parent,
            _child_ordinal: child_ordinal,
            _seed_owner: seed_owner,
            _direct_type_hir_by_decl: direct_type_hir_by_decl,
            _root_link_a: root_link_a,
            _root_link_b: root_link_b,
            _root_owner_a: root_owner_a,
            _root_owner_b: root_owner_b,
            _reverse_flag: reverse_flag,
            _reverse_prefix: reverse_prefix,
            _scan_local_prefix: scan_local_prefix,
            _scan_block_sum: scan_block_sum,
            _scan_prefix_a: scan_prefix_a,
            _scan_prefix_b: scan_prefix_b,
            _count: count,
            _scan_count: scan_count,
            _dispatch_args: dispatch_args,
            _hir_order: hir_order,
            _index_by_hir: index_by_hir,
            _edge_count: edge_count,
            _edge_prefix: edge_prefix,
            _edge_total: edge_total,
            _edges: edges,
            _edge_written: edge_written,
            _local_decl_by_hir: local_decl_by_hir,
            _path_classification: path_classification,
            _types: types,
            _signature_type_flag: signature_type_flag,
            _signature_type_prefix: signature_type_prefix,
            _signature_type_total: signature_type_total,
            _signature_edge_count: signature_edge_count,
            _signature_edge_prefix: signature_edge_prefix,
            _signature_edge_total: signature_edge_total,
            _signature_type_by_decl: signature_type_by_decl,
            _complete_type_count: complete_type_count,
            _complete_edge_total: complete_edge_total,
            _signature_scan_count: signature_scan_count,
            _signature_dispatch_args: signature_dispatch_args,
            _signature_scan_local_prefix: signature_scan_local_prefix,
            _signature_scan_block_sum: signature_scan_block_sum,
            _signature_scan_prefix_a: signature_scan_prefix_a,
            _signature_scan_prefix_b: signature_scan_prefix_b,
            _variant_count_by_hir: variant_count_by_hir,
            _field_count_by_hir: field_count_by_hir,
            _generic_type_count_by_decl: generic_type_count_by_decl,
            _generic_const_count_by_decl: generic_const_count_by_decl,
            _member_count: member_count,
            _member_prefix: member_prefix,
            _member_total: member_total,
            _members: members,
            _member_name_id: member_name_id,
            _member_index_by_generic_row: member_index_by_generic_row,
            _member_written: member_written,
            _params: params,
            count_readback,
            edge_total_readback,
            types_readback,
            edges_readback,
            edge_written_readback,
            member_total_readback,
            member_written_readback,
            members_readback,
        })
    }

    /// Decodes and validates the identity portion after the caller submits the
    /// command encoder containing `record_semantic_interface`.
    fn decode_semantic_interface_identity(
        &self,
        device: &wgpu::Device,
        recorded: &RecordedSemanticInterface,
    ) -> Result<GpuSemanticInterfaceIdentityArtifact> {
        let counts = readback_words(
            device,
            &recorded.counts_readback,
            "semantic-interface counts",
        )?;
        let status = readback_words(
            device,
            &recorded.status_readback,
            "semantic-interface status",
        )?;
        let status_bits = status.first().copied().unwrap_or(u32::MAX);
        if status_bits != 0 {
            return Err(anyhow::anyhow!(
                "semantic-interface GPU identity export failed: status=0x{status_bits:08x}, detail={}, name_id={}, name_len={}",
                status.get(1).copied().unwrap_or(u32::MAX),
                status.get(2).copied().unwrap_or(u32::MAX),
                status.get(3).copied().unwrap_or(u32::MAX),
            ));
        }
        validate_recorded_type_topology(device, &recorded._type_topology)?;
        if counts.len() != COUNT_WORDS {
            return Err(anyhow::anyhow!(
                "semantic-interface count readback has {} words; expected {COUNT_WORDS}",
                counts.len()
            ));
        }
        let library_id = counts[0];
        let module_count = checked_readback_count("module", counts[1], recorded.module_capacity)?;
        let module_segment_count = checked_readback_count(
            "module segment",
            counts[2],
            recorded.module_segment_capacity,
        )?;
        let declaration_count =
            checked_readback_count("declaration", counts[3], recorded.declaration_capacity)?;
        let name_byte_count =
            checked_readback_count("name byte", counts[4], recorded.name_byte_capacity)?;
        if library_id != recorded.expected_library_id {
            return Err(anyhow::anyhow!(
                "semantic-interface library id changed during GPU export: expected {}, got {library_id}",
                recorded.expected_library_id
            ));
        }

        let module_words = readback_words(
            device,
            &recorded.modules_readback,
            "semantic-interface modules",
        )?;
        let segment_words = readback_words(
            device,
            &recorded.module_segments_readback,
            "semantic-interface module segments",
        )?;
        let declaration_words = readback_words(
            device,
            &recorded.declarations_readback,
            "semantic-interface declarations",
        )?;
        let name_words = readback_words(
            device,
            &recorded.name_bytes_readback,
            "semantic-interface name bytes",
        )?;

        let modules = module_words
            .chunks_exact(MODULE_WORDS)
            .take(module_count)
            .map(|row| GpuSemanticInterfaceModuleRecord {
                first_segment: row[0],
                segment_count: row[1],
            })
            .collect();
        let module_segments = segment_words
            .chunks_exact(MODULE_SEGMENT_WORDS)
            .take(module_segment_count)
            .map(|row| GpuSemanticInterfaceModuleSegmentRecord {
                name_hash_lo: row[0],
                name_hash_hi: row[1],
                name_byte_start: row[2],
                name_byte_len: row[3],
            })
            .collect();
        let declarations = declaration_words
            .chunks_exact(DECLARATION_WORDS)
            .take(declaration_count)
            .map(|row| GpuSemanticInterfaceDeclarationRecord {
                module: row[0],
                name_hash_lo: row[1],
                name_hash_hi: row[2],
                name_byte_start: row[3],
                name_byte_len: row[4],
                namespace: row[5],
                kind: row[6],
                signature_type: row[7],
                first_member: row[8],
                member_count: row[9],
                owner_declaration: row[10],
                flags: row[11],
                value_lo: row[12],
                value_hi: row[13],
            })
            .collect();
        let mut name_bytes = Vec::with_capacity(name_byte_count);
        for word in name_words {
            name_bytes.extend_from_slice(&word.to_le_bytes());
        }
        name_bytes.truncate(name_byte_count);
        let artifact = GpuSemanticInterfaceIdentityArtifact {
            library_id,
            unit_id: recorded.expected_unit_id,
            modules,
            module_segments,
            declarations,
            name_bytes,
        };
        artifact.validate().map_err(|reason| {
            anyhow::anyhow!("invalid GPU semantic-interface identity: {reason}")
        })?;
        Ok(artifact)
    }

    /// Decodes and validates the complete public semantic interface after the
    /// caller submits the command encoder containing the recorded GPU work.
    pub fn finish_semantic_interface(
        &self,
        device: &wgpu::Device,
        recorded: &RecordedSemanticInterface,
    ) -> Result<GpuSemanticInterfaceArtifact> {
        let identity = self.decode_semantic_interface_identity(device, recorded)?;
        let topology = &recorded._type_topology;
        let type_count_words = readback_words(
            device,
            &topology.count_readback,
            "semantic-interface type count",
        )?;
        let edge_count_words = readback_words(
            device,
            &topology.edge_total_readback,
            "semantic-interface type edge count",
        )?;
        let member_count_words = readback_words(
            device,
            &topology.member_total_readback,
            "semantic-interface member count",
        )?;
        let type_count = checked_readback_count(
            "type",
            type_count_words.first().copied().unwrap_or(u32::MAX),
            topology.type_capacity,
        )?;
        let edge_count = checked_readback_count(
            "type edge",
            edge_count_words.first().copied().unwrap_or(u32::MAX),
            topology.edge_capacity,
        )?;
        let member_count = checked_readback_count(
            "member",
            member_count_words.first().copied().unwrap_or(u32::MAX),
            topology.member_capacity,
        )?;
        let type_words = readback_words(
            device,
            &topology.types_readback,
            "semantic-interface type records",
        )?;
        let edge_words = readback_words(
            device,
            &topology.edges_readback,
            "semantic-interface type edges",
        )?;
        let member_words = readback_words(
            device,
            &topology.members_readback,
            "semantic-interface member records",
        )?;
        if type_words.len() < type_count.saturating_mul(TYPE_WORDS)
            || edge_words.len() < edge_count
            || member_words.len() < member_count.saturating_mul(MEMBER_WORDS)
        {
            return Err(anyhow::anyhow!(
                "semantic-interface complete readback is shorter than its GPU counts"
            ));
        }

        let types = type_words
            .chunks_exact(TYPE_WORDS)
            .take(type_count)
            .map(|row| GpuSemanticInterfaceTypeRecord {
                kind: row[0],
                payload_lo: row[1],
                payload_hi: row[2],
                first_edge: row[3],
                edge_count: row[4],
                length_kind: row[5],
                length_lo: row[6],
                length_hi: row[7],
                nominal_unit_id: row[8],
            })
            .collect();
        let type_edges = edge_words
            .iter()
            .take(edge_count)
            .map(|&type_index| GpuSemanticInterfaceTypeEdge { type_index })
            .collect();
        let members = member_words
            .chunks_exact(MEMBER_WORDS)
            .take(member_count)
            .map(|row| GpuSemanticInterfaceMemberRecord {
                owner_declaration: row[0],
                kind: row[1],
                ordinal: row[2],
                name_hash_lo: row[3],
                name_hash_hi: row[4],
                name_byte_start: row[5],
                name_byte_len: row[6],
                type_index: row[7],
                value_lo: row[8],
                value_hi: row[9],
            })
            .collect();
        let artifact = GpuSemanticInterfaceArtifact {
            version: GPU_SEMANTIC_INTERFACE_VERSION,
            library_id: identity.library_id,
            unit_id: identity.unit_id,
            modules: identity.modules,
            module_segments: identity.module_segments,
            declarations: identity.declarations,
            types,
            type_edges,
            members,
            name_bytes: identity.name_bytes,
        };
        artifact.validate().map_err(|reason| {
            let member_ranges = artifact
                .declarations
                .iter()
                .take(16)
                .map(|declaration| (declaration.first_member, declaration.member_count))
                .collect::<Vec<_>>();
            anyhow::anyhow!(
                "invalid complete GPU semantic interface: {reason}; first member ranges: {member_ranges:?}"
            )
        })?;
        Ok(artifact)
    }
}

fn validate_recorded_type_topology(
    device: &wgpu::Device,
    recorded: &RecordedSemanticInterfaceTypeTopology,
) -> Result<()> {
    let count_words = readback_words(
        device,
        &recorded.count_readback,
        "semantic-interface type count",
    )?;
    let edge_total_words = readback_words(
        device,
        &recorded.edge_total_readback,
        "semantic-interface type edge count",
    )?;
    let count = checked_readback_count(
        "type",
        count_words.first().copied().unwrap_or(u32::MAX),
        recorded.type_capacity,
    )?;
    let edge_total = checked_readback_count(
        "type edge",
        edge_total_words.first().copied().unwrap_or(u32::MAX),
        recorded.edge_capacity,
    )?;
    let type_words = readback_words(
        device,
        &recorded.types_readback,
        "semantic-interface type records",
    )?;
    let edges = readback_words(
        device,
        &recorded.edges_readback,
        "semantic-interface type edges",
    )?;
    let edge_written = readback_words(
        device,
        &recorded.edge_written_readback,
        "semantic-interface type edge written flags",
    )?;
    if type_words.len() < count.saturating_mul(TYPE_WORDS)
        || edges.len() < edge_total
        || edge_written.len() < edge_total
    {
        return Err(anyhow::anyhow!(
            "semantic-interface type readback is shorter than its GPU counts"
        ));
    }
    if let Some((index, &flag)) = edge_written[..edge_total]
        .iter()
        .enumerate()
        .find(|(_, flag)| **flag != 1)
    {
        return Err(anyhow::anyhow!(
            "semantic-interface type edge {index} has invalid written flag {flag}"
        ));
    }
    let member_total_words = readback_words(
        device,
        &recorded.member_total_readback,
        "semantic-interface member count",
    )?;
    let member_total = checked_readback_count(
        "member",
        member_total_words.first().copied().unwrap_or(u32::MAX),
        recorded.member_capacity,
    )?;
    let member_written = readback_words(
        device,
        &recorded.member_written_readback,
        "semantic-interface member written flags",
    )?;
    if member_written.len() < member_total {
        return Err(anyhow::anyhow!(
            "semantic-interface member written readback is shorter than its GPU count"
        ));
    }
    if let Some((index, &flag)) = member_written[..member_total]
        .iter()
        .enumerate()
        .find(|(_, flag)| **flag != 1)
    {
        return Err(anyhow::anyhow!(
            "semantic-interface member {index} has invalid written flag {flag}; flags={:?}",
            &member_written[..member_total.min(16)]
        ));
    }
    for index in 0..count {
        let row = &type_words[index * TYPE_WORDS..(index + 1) * TYPE_WORDS];
        let kind = row[0];
        let first_edge = row[3] as usize;
        let edge_count = row[4] as usize;
        let edge_end = first_edge.checked_add(edge_count).ok_or_else(|| {
            anyhow::anyhow!("semantic-interface type record {index} edge range overflows")
        })?;
        if edge_end > edge_total {
            return Err(anyhow::anyhow!(
                "semantic-interface type record {index} edge range {first_edge}..{edge_end} exceeds {edge_total}"
            ));
        }
        if !matches!(kind, 1..=8) {
            return Err(anyhow::anyhow!(
                "semantic-interface type record {index} has unsupported kind {kind}"
            ));
        }
        if matches!(kind, 1 | 2 | 8) && edge_count != 0 {
            return Err(anyhow::anyhow!(
                "semantic-interface leaf type record {index} has {edge_count} edges"
            ));
        }
        if matches!(kind, 4..=6) && edge_count != 1 {
            return Err(anyhow::anyhow!(
                "semantic-interface unary type record {index} has {edge_count} edges"
            ));
        }
        if kind == 7 && edge_count == 0 {
            return Err(anyhow::anyhow!(
                "semantic-interface function type record {index} has no return edge"
            ));
        }
        if kind == 4 && !matches!(row[5], 1 | 2) {
            return Err(anyhow::anyhow!(
                "semantic-interface array type record {index} has invalid length kind {}",
                row[5]
            ));
        }
        for &target in &edges[first_edge..edge_end] {
            if target as usize >= index {
                return Err(anyhow::anyhow!(
                    "semantic-interface type record {index} edge target {target} is not in prior topological order"
                ));
            }
        }
    }
    Ok(())
}

fn u32_capacity(buffer: &wgpu::Buffer, words_per_row: u64, label: &str) -> Result<u32> {
    let row_bytes = words_per_row
        .checked_mul(4)
        .ok_or_else(|| anyhow::anyhow!("{label} row size overflows"))?;
    if buffer.size() % row_bytes != 0 {
        return Err(anyhow::anyhow!(
            "{label} buffer has {} bytes, which is not divisible by row size {row_bytes}",
            buffer.size()
        ));
    }
    u32::try_from(buffer.size() / row_bytes)
        .map_err(|_| anyhow::anyhow!("{label} capacity exceeds u32"))
}

fn initialized_u32_buffer(
    device: &wgpu::Device,
    label: &str,
    words: &[u32],
    extra_usage: wgpu::BufferUsages,
) -> LaniusBuffer<u32> {
    let mut bytes = Vec::with_capacity(words.len() * 4);
    for word in words {
        bytes.extend_from_slice(&word.to_le_bytes());
    }
    let raw = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &bytes,
        usage: wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_SRC
            | wgpu::BufferUsages::COPY_DST
            | extra_usage,
    });
    LaniusBuffer::new_labeled((raw, bytes.len() as u64), words.len(), label)
}

fn readback_words(device: &wgpu::Device, buffer: &wgpu::Buffer, label: &str) -> Result<Vec<u32>> {
    let slice = buffer.slice(..);
    crate::gpu::passes_core::map_readback_blocking(device, &slice, label)?;
    let mapped = slice.get_mapped_range();
    if mapped.len() % 4 != 0 {
        drop(mapped);
        buffer.unmap();
        return Err(anyhow::anyhow!(
            "{label} readback byte length is not word aligned"
        ));
    }
    let words = mapped
        .chunks_exact(4)
        .map(|bytes| u32::from_le_bytes(bytes.try_into().expect("four-byte chunk")))
        .collect();
    drop(mapped);
    buffer.unmap();
    Ok(words)
}

fn checked_readback_count(label: &str, count: u32, capacity: usize) -> Result<usize> {
    let count = count as usize;
    if count > capacity {
        return Err(anyhow::anyhow!(
            "semantic-interface {label} count {count} exceeds readback capacity {capacity}"
        ));
    }
    Ok(count)
}
