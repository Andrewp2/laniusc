use super::*;
use crate::{
    compiler::{GPU_SEMANTIC_INTERFACE_VERSION, GpuSemanticInterfaceArtifact},
    gpu::readback::{PagedReadback, read_u32_words},
};

pub(super) const MODULE_WORDS: usize = 2;
pub(super) const MODULE_SEGMENT_WORDS: usize = 4;
pub(super) const DECLARATION_WORDS: usize = 14;
const COUNT_WORDS: usize = 5;
pub(super) const TYPE_WORDS: usize = 9;
pub(super) const MEMBER_WORDS: usize = 10;

#[allow(clippy::too_many_arguments)]
fn graph_prefix_scan(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    buffer_cache: &CapacityBufferCache,
    kernels: &KernelRegistry,
    label: &'static str,
    params: PrefixScanParams,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    scan: compiler_graph::SemanticInterfaceScan,
    count: TrackedBufferView<'_>,
    dispatch_args: &LaniusBuffer<u32>,
    input: TrackedBufferView<'_>,
    output_prefix: &LaniusBuffer<u32>,
    total: &LaniusBuffer<u32>,
    workspace: PrefixScanWorkspace<&LaniusBuffer<u32>>,
) -> Result<PrefixScanOperation> {
    let mut resources = ResourceMap::new();
    resources.buffer("scan_count", count);
    resources.buffer("scan_input", input);
    resources.buffer("scan_dispatch_args", dispatch_args);
    resources.buffers([
        ("scan_output_prefix", output_prefix),
        ("scan_total", total),
        ("scan_local_prefix", workspace.local_prefix),
        ("scan_block_sum", workspace.block_sum),
        ("scan_block_prefix", workspace.block_prefix),
        ("scan_hierarchy", workspace.hierarchy),
    ]);
    graph.validate_semantic_interface_scan(scan, &resources)?;
    let graph_passes = graph.semantic_interface_scan_passes(scan)?;
    PrefixScanOperation::with_reusable_workspace(
        device,
        queue,
        buffer_cache,
        kernels,
        label,
        graph_passes,
        params,
        count,
        dispatch_args.into(),
        input,
        output_prefix.into(),
        total.into(),
        workspace,
    )
}

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
    _variant_count_by_hir: LaniusBuffer<u32>,
    _field_count_by_hir: LaniusBuffer<u32>,
    _generic_type_count_by_decl: LaniusBuffer<u32>,
    _generic_const_count_by_decl: LaniusBuffer<u32>,
    _member_count: LaniusBuffer<u32>,
    _member_prefix: LaniusBuffer<u32>,
    _member_total: LaniusBuffer<u32>,
    _member_cursor: LaniusBuffer<u32>,
    _members: LaniusBuffer<u32>,
    _member_name_id: LaniusBuffer<u32>,
    _member_index_by_generic_row: LaniusBuffer<u32>,
    _member_written: LaniusBuffer<u32>,
    _params: LaniusBuffer<SemanticInterfaceTypeTopologyParams>,
}

/// GPU outputs and host-visible copies recorded for one bounded unit's public
/// semantic identities. The input semantic tables remain owned by the resident
/// type checker until the enclosing compilation submission completes.
pub struct RecordedSemanticInterface {
    expected_library_id: u32,
    expected_unit_id: u32,
    artifact_capacity: usize,
    _name_ref_len: LaniusBuffer<u32>,
    _name_ref_prefix: LaniusBuffer<u32>,
    _scan_total: LaniusBuffer<u32>,
    _scan_count: LaniusBuffer<u32>,
    _scan_dispatch_args: LaniusBuffer<u32>,
    _module_segment_prefix: LaniusBuffer<u32>,
    _module_segment_total: LaniusBuffer<u32>,
    _module_scan_dispatch_args: LaniusBuffer<u32>,
    _modules: LaniusBuffer<u32>,
    _module_segments: LaniusBuffer<u32>,
    _declarations: LaniusBuffer<u32>,
    _name_byte_words: LaniusBuffer<u32>,
    _counts: LaniusBuffer<u32>,
    _status: LaniusBuffer<u32>,
    _type_topology: RecordedSemanticInterfaceTypeTopology,
    _artifact_words: LaniusBuffer<u32>,
    _artifact_length: LaniusBuffer<u32>,
    metadata_readback: LaniusBuffer<u8>,
    artifact_readback: PagedReadback,
}

impl GpuTypeChecker {
    /// Records canonical public module/declaration identities for the current
    /// resident type-check result. This must be called after type-check passes
    /// have been recorded and before the resident state is released.
    pub fn record_semantic_interface(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        library_id: u32,
        unit_id: u32,
        source_len: u32,
        token_capacity: u32,
        source_bytes: &wgpu::Buffer,
        hir: GpuSemanticInterfaceHirBuffers<'_>,
    ) -> Result<RecordedSemanticInterface> {
        let guard = self
            .resident_workspace
            .lock()
            .expect("GpuTypeChecker.resident_workspace poisoned");
        let state = guard.as_ref().ok_or_else(|| {
            anyhow::anyhow!("semantic-interface export requires resident type-check state")
        })?;
        let module_path = &state.module_path;
        let name_scan_total = state.typecheck_graph.u32_buffer("name_scan_total")?;
        let name_spans = state.typecheck_graph.u32_buffer("name_spans")?;
        let graph_buffers = [
            state.typecheck_graph.u32_buffer("type_expr_ref_tag")?,
            state.typecheck_graph.u32_buffer("type_expr_ref_payload")?,
            state
                .typecheck_graph
                .u32_buffer("type_generic_param_slot_by_token")?,
            state
                .typecheck_graph
                .u32_buffer("type_const_param_slot_by_token")?,
            state
                .typecheck_graph
                .u32_buffer("generic_param_count_out")?,
            state
                .typecheck_graph
                .u32_buffer("generic_param_owner_token")?,
            state.typecheck_graph.u32_buffer("generic_param_name_id")?,
            state.typecheck_graph.u32_buffer("generic_param_token")?,
            state.typecheck_graph.u32_buffer("generic_param_kind")?,
            state
                .typecheck_graph
                .u32_buffer("type_decl_generic_param_count_by_owner_token")?,
            state
                .typecheck_graph
                .u32_buffer("type_decl_const_param_count_by_owner_token")?,
            state
                .typecheck_graph
                .u32_buffer("external_type_library_id")?,
            state.typecheck_graph.u32_buffer("external_type_unit_id")?,
            state
                .typecheck_graph
                .u32_buffer("external_type_local_index")?,
            state
                .typecheck_graph
                .u32_buffer("semantic_function_host_service_by_hir")?,
            state
                .typecheck_graph
                .u32_buffer("semantic_type_ref_tag_by_hir")?,
            state
                .typecheck_graph
                .u32_buffer("semantic_type_ref_payload_by_hir")?,
            state
                .typecheck_graph
                .u32_buffer("semantic_type_external_library_id_by_hir")?,
            state
                .typecheck_graph
                .u32_buffer("semantic_type_external_unit_id_by_hir")?,
            state
                .typecheck_graph
                .u32_buffer("semantic_type_external_local_index_by_hir")?,
            state
                .typecheck_graph
                .u32_buffer("semantic_type_generic_param_slot_by_hir")?,
            state
                .typecheck_graph
                .u32_buffer("semantic_value_const_by_hir")?,
            state
                .typecheck_graph
                .u32_buffer("semantic_value_const_present_by_hir")?,
        ];
        let dependency_visibility = module_path.dependency_visibility.as_deref();
        let inputs = GpuSemanticInterfaceIdentityBuffers {
            name_capacity: state.name_capacity,
            module_capacity: u32::try_from(module_path.module_key_segment_count.count)
                .unwrap_or(u32::MAX),
            declaration_capacity: u32::try_from(module_path.interface_public_decl_local_id.count)
                .unwrap_or(u32::MAX),
            module_segment_capacity: u32::try_from(module_path.module_key_segment_name_id.count)
                .unwrap_or(u32::MAX),
            name_count_out: (&name_scan_total).into(),
            name_spans: (&name_spans).into(),
            name_hash_lo: (&state.name_order_in).into(),
            name_hash_hi: (&state.name_order_tmp).into(),
            name_id_by_token: (&state.name_id_by_token).into(),
            language_symbol_bytes: (&state.language_symbol_bytes).into(),
            module_count_out: (&module_path.module_count_out).into(),
            module_key_segment_count: (&module_path.module_key_segment_count).into(),
            module_key_segment_base: (&module_path.module_key_segment_base).into(),
            module_key_segment_name_id: (&module_path.module_key_segment_name_id).into(),
            decl_count_out: (&module_path.decl_count_out).into(),
            decl_module_id: (&module_path.decl_module_id).into(),
            decl_name_id: (&module_path.decl_name_id).into(),
            decl_kind: (&module_path.decl_kind).into(),
            decl_namespace: (&module_path.decl_namespace).into(),
            decl_visibility: (&module_path.decl_visibility).into(),
            decl_parent_type_decl: (&module_path.decl_parent_type_decl).into(),
            decl_hir_node: (&module_path.decl_hir_node).into(),
            semantic_value_const_by_hir: (&graph_buffers[21]).into(),
            semantic_value_const_present_by_hir: (&graph_buffers[22]).into(),
            function_host_service_by_hir: (&graph_buffers[14]).into(),
            public_decl_count: (&module_path.interface_public_decl_count).into(),
            public_decl_local_id: (&module_path.interface_public_decl_local_id).into(),
            public_decl_index_by_local: (&module_path.interface_public_decl_index_by_local).into(),
            public_decl_index_by_hir: (&module_path.interface_public_decl_index_by_hir).into(),
            type_expr_ref_tag: (&graph_buffers[0]).into(),
            type_expr_ref_payload: (&graph_buffers[1]).into(),
            type_generic_param_slot_by_token: (&graph_buffers[2]).into(),
            type_const_param_slot_by_token: (&graph_buffers[3]).into(),
            type_instance_decl_token: (&state.type_instance_decl_token).into(),
            external_type_library_id: (&graph_buffers[11]).into(),
            external_type_unit_id: (&graph_buffers[12]).into(),
            external_type_local_index: (&graph_buffers[13]).into(),
            semantic_type_ref_tag_by_hir: (&graph_buffers[15]).into(),
            semantic_type_ref_payload_by_hir: (&graph_buffers[16]).into(),
            semantic_type_external_library_id_by_hir: (&graph_buffers[17]).into(),
            semantic_type_external_unit_id_by_hir: (&graph_buffers[18]).into(),
            semantic_type_external_local_index_by_hir: (&graph_buffers[19]).into(),
            semantic_type_generic_param_slot_by_hir: (&graph_buffers[20]).into(),
            resolved_dependency_library_id: dependency_visibility
                .map(|visibility| (&visibility.resolved_dependency_library_id).into())
                .unwrap_or_else(|| (&graph_buffers[11]).into()),
            resolved_dependency_unit_id: dependency_visibility
                .map(|visibility| (&visibility.resolved_dependency_unit_id).into())
                .unwrap_or_else(|| (&graph_buffers[11]).into()),
            resolved_dependency_local_index: dependency_visibility
                .map(|visibility| (&visibility.resolved_dependency_local_index).into())
                .unwrap_or_else(|| (&graph_buffers[11]).into()),
            path_id_by_owner_hir: (&module_path.path_id_by_owner_hir).into(),
            path_id_by_owner_token: (&module_path.path_id_by_owner_token).into(),
            resolved_type_decl: (&module_path.resolved_type_decl).into(),
            decl_id_by_name_token: (&module_path.decl_id_by_name_token).into(),
            generic_param_count_out: (&graph_buffers[4]).into(),
            generic_param_owner_token: (&graph_buffers[5]).into(),
            generic_param_name_id: (&graph_buffers[6]).into(),
            generic_param_token: (&graph_buffers[7]).into(),
            generic_param_kind: (&graph_buffers[8]).into(),
            type_decl_generic_param_count_by_owner_token: (&graph_buffers[9]).into(),
            type_decl_const_param_count_by_owner_token: (&graph_buffers[10]).into(),
        };
        self.record_semantic_interface_from_buffers(
            device,
            queue,
            encoder,
            library_id,
            unit_id,
            source_len,
            token_capacity,
            source_bytes,
            hir,
            inputs,
            &state.typecheck_graph,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn record_semantic_interface_from_buffers(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        library_id: u32,
        unit_id: u32,
        source_len: u32,
        token_capacity: u32,
        source_bytes: &wgpu::Buffer,
        hir: GpuSemanticInterfaceHirBuffers<'_>,
        inputs: GpuSemanticInterfaceIdentityBuffers<'_>,
        typecheck_graph: &compiler_graph::TypeCheckCompilerGraph,
    ) -> Result<RecordedSemanticInterface> {
        let name_capacity = inputs.name_capacity;
        let module_capacity = inputs.module_capacity;
        let decl_storage_capacity = inputs.declaration_capacity;
        let decl_capacity = decl_storage_capacity.min(token_capacity).max(1);
        if inputs.declaration_capacity < decl_capacity {
            return Err(anyhow::anyhow!(
                "semantic-interface public declaration map is shorter than its token-bounded domain"
            ));
        }
        let module_segment_capacity = inputs.module_segment_capacity;
        let semantic_hir_capacity = hir.compact_hir_capacity.min(token_capacity).max(1);
        let member_capacity = semantic_hir_capacity
            .checked_mul(2)
            .and_then(|value| value.checked_add(token_capacity))
            .ok_or_else(|| anyhow::anyhow!("semantic-interface member capacity overflows u32"))?;
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
        let scan_scratch = typecheck_graph.semantic_interface_scan_workspace()?;
        let workspace = |name| typecheck_graph.semantic_interface_buffer(name);

        let name_ref_len = workspace("semantic_interface.name_ref_len")?;
        let (name_ref_prefix, scan_total) = typecheck_graph
            .semantic_interface_scan_outputs(compiler_graph::SemanticInterfaceScan::Names)?;
        let scan_count = initialized_u32_buffer(
            &self.semantic_interface_buffers,
            device,
            queue,
            "type_check.interface.scan_count",
            &[name_ref_count],
            wgpu::BufferUsages::STORAGE,
        );
        let [tgsx, tgsy, _] = self
            .passes
            .kernel("scan/counted/00_local")
            .thread_group_size;
        let (dispatch_x, dispatch_y, dispatch_z) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(name_ref_count.max(1)),
            [tgsx, tgsy, 1],
        )?;
        let scan_dispatch_args = initialized_u32_buffer(
            &self.semantic_interface_buffers,
            device,
            queue,
            "type_check.interface.scan_dispatch_args",
            &[dispatch_x, dispatch_y, dispatch_z],
            wgpu::BufferUsages::INDIRECT,
        );
        let scan = graph_prefix_scan(
            device,
            queue,
            &self.semantic_interface_buffers,
            &self.passes,
            "type_check.interface.name_scan",
            PrefixScanParams {
                n_items: name_ref_count,
                n_blocks: scan_n_blocks,
                min_items: 0,
            },
            typecheck_graph,
            compiler_graph::SemanticInterfaceScan::Names,
            (&scan_count).into(),
            &scan_dispatch_args,
            (&name_ref_len).into(),
            &name_ref_prefix,
            &scan_total,
            scan_scratch,
        )?;
        let (module_segment_prefix, module_segment_total) = typecheck_graph
            .semantic_interface_scan_outputs(compiler_graph::SemanticInterfaceScan::Modules)?;
        let (module_dispatch_x, module_dispatch_y, module_dispatch_z) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(module_capacity.max(1)),
            [tgsx, tgsy, 1],
        )?;
        let module_scan_dispatch_args = initialized_u32_buffer(
            &self.semantic_interface_buffers,
            device,
            queue,
            "type_check.interface.module_scan_dispatch_args",
            &[module_dispatch_x, module_dispatch_y, module_dispatch_z],
            wgpu::BufferUsages::INDIRECT,
        );
        let module_scan = graph_prefix_scan(
            device,
            queue,
            &self.semantic_interface_buffers,
            &self.passes,
            "type_check.interface.module_segment_scan",
            PrefixScanParams {
                n_items: module_capacity,
                n_blocks: module_scan_n_blocks,
                // The interface always serializes an implicit root module,
                // even when no explicit module declaration was counted.
                min_items: u32::from(module_capacity != 0),
            },
            typecheck_graph,
            compiler_graph::SemanticInterfaceScan::Modules,
            inputs.module_count_out.into(),
            &module_scan_dispatch_args,
            inputs.module_key_segment_count.into(),
            &module_segment_prefix,
            &module_segment_total,
            scan_scratch,
        )?;

        let modules = workspace("semantic_interface.modules")?;
        let module_segments = workspace("semantic_interface.module_segments")?;
        let declarations = workspace("semantic_interface.declarations")?;
        let name_word_capacity = (name_byte_capacity as usize).div_ceil(4);
        let name_byte_words = self.semantic_interface_buffers.storage_u32(
            device,
            "type_check.interface.name_byte_words",
            name_word_capacity,
            wgpu::BufferUsages::COPY_DST,
        );
        let counts = self.semantic_interface_buffers.storage_u32(
            device,
            "type_check.interface.counts",
            COUNT_WORDS,
            wgpu::BufferUsages::COPY_DST,
        );
        let status = initialized_u32_buffer(
            &self.semantic_interface_buffers,
            device,
            queue,
            "type_check.interface.status",
            &[0, u32::MAX, u32::MAX, u32::MAX],
            wgpu::BufferUsages::STORAGE,
        );
        let type_topology = self.record_semantic_interface_type_topology(
            device,
            queue,
            encoder,
            library_id,
            unit_id,
            token_capacity,
            hir,
            &inputs,
            &status,
            scan_scratch,
            typecheck_graph,
        )?;
        let mut identity_resources = ResourceMap::new();
        typecheck_graph.register_semantic_interface_bindings(&mut identity_resources)?;
        identity_resources.buffer("name_scan_total", inputs.name_count_out);
        identity_resources.buffer("name_spans", inputs.name_spans);
        identity_resources.buffer("name_hash_lo", inputs.name_hash_lo);
        identity_resources.buffer("name_hash_hi", inputs.name_hash_hi);
        identity_resources.buffer("module_count_out", inputs.module_count_out);
        identity_resources.buffer("module_key_segment_count", inputs.module_key_segment_count);
        identity_resources.buffer("module_key_segment_base", inputs.module_key_segment_base);
        identity_resources.buffer(
            "module_key_segment_name_id",
            inputs.module_key_segment_name_id,
        );
        identity_resources.buffer("module_segment_prefix", &module_segment_prefix);
        identity_resources.buffer("module_segment_total", &module_segment_total);
        identity_resources.buffer("interface_public_decl_count", inputs.public_decl_count);
        identity_resources.buffer(
            "interface_public_decl_local_id",
            inputs.public_decl_local_id,
        );
        identity_resources.buffer(
            "interface_public_decl_index_by_local",
            inputs.public_decl_index_by_local,
        );
        identity_resources.buffer("decl_module_id", inputs.decl_module_id);
        identity_resources.buffer("decl_name_id", inputs.decl_name_id);
        identity_resources.buffer("decl_namespace", inputs.decl_namespace);
        identity_resources.buffer("decl_kind", inputs.decl_kind);
        identity_resources.buffer("decl_parent_type_decl", inputs.decl_parent_type_decl);
        identity_resources.buffer("decl_hir_node", inputs.decl_hir_node);
        identity_resources.buffer("compact_const_value", hir.compact_const_value);
        identity_resources.buffer("compact_hir_core", hir.compact_hir_core);
        identity_resources.buffer("compact_hir_payload", hir.compact_hir_payload);
        identity_resources.buffer(
            "semantic_value_const_by_hir",
            inputs.semantic_value_const_by_hir,
        );
        identity_resources.buffer(
            "semantic_value_const_present_by_hir",
            inputs.semantic_value_const_present_by_hir,
        );
        identity_resources.buffer(
            "semantic_function_host_service_by_hir",
            inputs.function_host_service_by_hir,
        );
        identity_resources.buffer("interface_name_ref_len", &name_ref_len);
        identity_resources.buffer("interface_name_ref_prefix", &name_ref_prefix);
        identity_resources.buffer(
            "interface_signature_type_by_decl",
            &type_topology._signature_type_by_decl,
        );
        identity_resources.buffer("interface_member_prefix", &type_topology._member_prefix);
        identity_resources.buffer("interface_member_count", &type_topology._member_count);
        identity_resources.buffer("interface_member_total", &type_topology._member_total);
        identity_resources.buffer("interface_member_name_id", &type_topology._member_name_id);
        identity_resources.buffer("interface_modules", &modules);
        identity_resources.buffer("interface_module_segments", &module_segments);
        identity_resources.buffer("interface_declaration_words", &declarations);
        identity_resources.buffer("interface_member_words", &type_topology._members);
        identity_resources.buffer("interface_counts", &counts);
        identity_resources.buffer("interface_status", &status);
        identity_resources.buffer("source_bytes", source_bytes);
        identity_resources.buffer("language_symbol_bytes", inputs.language_symbol_bytes);
        identity_resources.buffer("interface_name_byte_words", &name_byte_words);

        let size_params = self.semantic_interface_buffers.uniform(
            device,
            queue,
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
        let interface_graph = typecheck_graph.semantic_interface_graph()?;
        let size_operation = crate::gpu::operations::ComputeOperation::direct_with_uniform(
            device,
            interface_graph,
            &identity_resources,
            "type_check.interface.identity_sizes",
            &self
                .passes
                .kernel("type_checker/interface/00_identity_sizes"),
            &size_params,
            identity_work_capacity,
        )?;

        let record_params = self.semantic_interface_buffers.uniform(
            device,
            queue,
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
                hir_capacity: semantic_hir_capacity,
            },
        );
        let record_operation = crate::gpu::operations::ComputeOperation::direct_with_uniform(
            device,
            interface_graph,
            &identity_resources,
            "type_check.interface.identity_records",
            &self
                .passes
                .kernel("type_checker/interface/01_identity_records"),
            &record_params,
            identity_work_capacity,
        )?;

        let byte_params = self.semantic_interface_buffers.uniform(
            device,
            queue,
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
        let byte_operation = crate::gpu::operations::ComputeOperation::direct_with_uniform(
            device,
            interface_graph,
            &identity_resources,
            "type_check.interface.identity_bytes",
            &self
                .passes
                .kernel("type_checker/interface/02_identity_bytes"),
            &byte_params,
            name_ref_count,
        )?;

        let clear_name_ref = crate::gpu::operations::ClearBufferOperation::entire(
            interface_graph,
            compiler_graph::SEMANTIC_INTERFACE_NAME_REF_CLEAR_PASS,
            "interface_name_ref_len",
            &name_ref_len,
        )?;
        let clear_name_bytes = crate::gpu::operations::ClearBufferOperation::entire(
            interface_graph,
            compiler_graph::SEMANTIC_INTERFACE_NAME_BYTES_CLEAR_PASS,
            "interface_name_byte_words",
            &name_byte_words,
        )?;
        let clear_counts = crate::gpu::operations::ClearBufferOperation::entire(
            interface_graph,
            compiler_graph::SEMANTIC_INTERFACE_COUNTS_CLEAR_PASS,
            "interface_counts",
            &counts,
        )?;
        clear_name_ref.record(encoder);
        clear_name_bytes.record(encoder);
        clear_counts.record(encoder);
        module_scan.record(encoder)?;
        size_operation.record(encoder)?;
        scan.record(encoder)?;
        record_operation.record(encoder)?;
        byte_operation.record(encoder)?;

        let artifact_capacity = semantic_interface_artifact_capacity(
            module_capacity,
            module_segment_capacity,
            declaration_capacity,
            type_topology.type_capacity,
            type_topology.edge_capacity,
            type_topology.member_capacity,
            name_byte_capacity,
        )?;
        if crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false) {
            eprintln!(
                "[gpu_compile_host_timer] semantic_interface.capacity: tokens={token_capacity} modules={module_capacity} module_segments={module_segment_capacity} declarations={declaration_capacity} types={} edges={} members={} names={} artifact_bytes={artifact_capacity}",
                type_topology.type_capacity,
                type_topology.edge_capacity,
                type_topology.member_capacity,
                name_byte_capacity,
            );
        }
        let artifact_word_capacity = artifact_capacity.div_ceil(4);
        let artifact_words = self.semantic_interface_buffers.storage_u32(
            device,
            "type_check.interface.artifact.words",
            artifact_word_capacity,
            wgpu::BufferUsages::COPY_SRC,
        );
        let artifact_length = self.semantic_interface_buffers.storage_u32(
            device,
            "type_check.interface.artifact.length",
            1,
            wgpu::BufferUsages::COPY_SRC,
        );
        let metadata_readback = self.semantic_interface_buffers.buffer(
            device,
            "type_check.interface.artifact.metadata.readback",
            20,
            20,
            wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        );
        let artifact_readback =
            PagedReadback::from_staging(self.semantic_interface_buffers.buffer(
                device,
                "type_check.interface.artifact.readback",
                artifact_capacity.min(4 << 20),
                artifact_capacity.min(4 << 20),
                wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            ));
        let artifact_params = self.semantic_interface_buffers.uniform(
            device,
            queue,
            "type_check.interface.artifact.params",
            &SemanticInterfaceArtifactParams {
                module_capacity,
                module_segment_capacity,
                declaration_capacity,
                type_capacity: type_topology.type_capacity as u32,
                edge_capacity: type_topology.edge_capacity as u32,
                member_capacity: type_topology.member_capacity as u32,
                name_byte_capacity,
                artifact_word_capacity: u32::try_from(artifact_word_capacity).map_err(|_| {
                    anyhow::anyhow!("semantic-interface artifact capacity exceeds u32 words")
                })?,
                unit_id,
                version: GPU_SEMANTIC_INTERFACE_VERSION,
            },
        );
        let mut artifact_resources = ResourceMap::new();
        typecheck_graph.register_semantic_interface_bindings(&mut artifact_resources)?;
        artifact_resources.buffers([
            ("interface_counts", &counts),
            (
                "interface_complete_type_count",
                &type_topology._complete_type_count,
            ),
            (
                "interface_complete_edge_total",
                &type_topology._complete_edge_total,
            ),
            ("interface_member_total", &type_topology._member_total),
            ("interface_modules", &modules),
            ("interface_module_segments", &module_segments),
            ("interface_declaration_words", &declarations),
            ("interface_types", &type_topology._types),
            ("interface_edges", &type_topology._edges),
            ("interface_edge_written", &type_topology._edge_written),
            ("interface_member_words", &type_topology._members),
            ("interface_member_written", &type_topology._member_written),
            ("interface_name_byte_words", &name_byte_words),
            ("interface_status", &status),
            ("interface_artifact_words", &artifact_words),
            ("interface_artifact_length", &artifact_length),
        ]);
        let artifact_kernel = self
            .passes
            .kernel("type_checker/interface/artifact/materialize");
        let artifact_work_capacity = module_capacity
            .max(module_segment_capacity)
            .max(declaration_capacity)
            .max(type_topology.type_capacity as u32)
            .max(type_topology.edge_capacity as u32)
            .max(type_topology.member_capacity as u32)
            .max(name_byte_capacity.div_ceil(4))
            .max(1);
        let artifact_operation = crate::gpu::operations::ComputeOperation::direct_with_uniform(
            device,
            interface_graph,
            &artifact_resources,
            "type_check.interface.artifact",
            artifact_kernel,
            &artifact_params,
            artifact_work_capacity,
        )?;
        let artifact_length_readback = crate::gpu::operations::CopyBufferOperation::new(
            interface_graph,
            compiler_graph::SEMANTIC_INTERFACE_ARTIFACT_LENGTH_READBACK_PASS,
            "interface_artifact_length",
            &artifact_length,
            0,
            "interface_artifact_metadata_readback",
            &metadata_readback,
            0,
            4,
        )?;
        let status_readback = crate::gpu::operations::CopyBufferOperation::new(
            interface_graph,
            compiler_graph::SEMANTIC_INTERFACE_STATUS_READBACK_PASS,
            "interface_status",
            &status,
            0,
            "interface_artifact_metadata_readback",
            &metadata_readback,
            4,
            16,
        )?;
        artifact_operation.record(encoder)?;
        artifact_length_readback.record(encoder);
        status_readback.record(encoder);
        Ok(RecordedSemanticInterface {
            expected_library_id: library_id,
            expected_unit_id: unit_id,
            artifact_capacity,
            _name_ref_len: name_ref_len,
            _name_ref_prefix: name_ref_prefix,
            _scan_total: scan_total,
            _scan_count: scan_count,
            _scan_dispatch_args: scan_dispatch_args,
            _module_segment_prefix: module_segment_prefix,
            _module_segment_total: module_segment_total,
            _module_scan_dispatch_args: module_scan_dispatch_args,
            _modules: modules,
            _module_segments: module_segments,
            _declarations: declarations,
            _name_byte_words: name_byte_words,
            _counts: counts,
            _status: status,
            _type_topology: type_topology,
            _artifact_words: artifact_words,
            _artifact_length: artifact_length,
            metadata_readback,
            artifact_readback,
        })
    }

    fn record_semantic_interface_type_topology(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        library_id: u32,
        unit_id: u32,
        token_capacity: u32,
        hir: GpuSemanticInterfaceHirBuffers<'_>,
        inputs: &GpuSemanticInterfaceIdentityBuffers<'_>,
        status: &LaniusBuffer<u32>,
        scan_scratch: PrefixScanWorkspace<&LaniusBuffer<u32>>,
        typecheck_graph: &compiler_graph::TypeCheckCompilerGraph,
    ) -> Result<RecordedSemanticInterfaceTypeTopology> {
        let hir_storage_capacity = hir.compact_hir_capacity;
        let decl_capacity = inputs.declaration_capacity.min(token_capacity).max(1);
        // Canonical HIR assigns every durable row a unique token/file anchor;
        // parser storage capacity is therefore not the semantic row domain.
        // The same token bound is used by the resident type-check shaders.
        let capacity = hir_storage_capacity.min(token_capacity).max(1);
        let type_capacity = capacity
            .checked_add(decl_capacity)
            .and_then(|value| value.checked_add(1))
            .ok_or_else(|| anyhow::anyhow!("semantic-interface type capacity overflows u32"))?;
        let edge_capacity = capacity.checked_add(decl_capacity).ok_or_else(|| {
            anyhow::anyhow!("semantic-interface type-edge capacity overflows u32")
        })?;
        let n_blocks = capacity.div_ceil(256).max(1);
        let params = self.semantic_interface_buffers.uniform(
            device,
            queue,
            "type_check.interface.type_topology.params",
            &SemanticInterfaceTypeTopologyParams {
                hir_capacity: capacity,
                decl_capacity,
                token_capacity,
                library_id,
                unit_id,
            },
        );
        let workspace = |name| typecheck_graph.semantic_interface_buffer(name);
        let parent = workspace("semantic_interface.type.parent")?;
        let seed_owner = workspace("semantic_interface.type.seed_owner")?;
        let child_ordinal = workspace("semantic_interface.type.child_ordinal")?;
        let direct_type_hir_by_decl = workspace("semantic_interface.type.direct_hir_by_decl")?;
        let index_by_hir = workspace("semantic_interface.type.index_by_hir")?;
        let root_link_a = workspace("semantic_interface.type.root_link_a")?;
        let root_link_b = workspace("semantic_interface.type.root_link_b")?;
        let root_owner_a = workspace("semantic_interface.type.root_owner_a")?;
        let root_owner_b = workspace("semantic_interface.type.root_owner_b")?;
        let reverse_flag = workspace("semantic_interface.type.reverse_flag")?;
        let (reverse_prefix, count) = typecheck_graph
            .semantic_interface_scan_outputs(compiler_graph::SemanticInterfaceScan::TypeOrder)?;
        let scan_count = initialized_u32_buffer(
            &self.semantic_interface_buffers,
            device,
            queue,
            "type_check.interface.type_topology.scan_count",
            &[capacity],
            wgpu::BufferUsages::STORAGE,
        );
        let hir_order = workspace("semantic_interface.type.hir_order")?;
        let edge_count = workspace("semantic_interface.type.edge_count")?;
        let (edge_prefix, edge_total) = typecheck_graph
            .semantic_interface_scan_outputs(compiler_graph::SemanticInterfaceScan::TypeEdges)?;
        let edges = workspace("semantic_interface.type.edges")?;
        let edge_written = workspace("semantic_interface.type.edge_written")?;
        let types = workspace("semantic_interface.type.types")?;
        let local_decl_by_hir = workspace("semantic_interface.type.local_decl_by_hir")?;
        let path_classification = workspace("semantic_interface.type.path_classification")?;
        let signature_capacity = decl_capacity.max(1);
        let signature_n_blocks = signature_capacity.div_ceil(256).max(1);
        let signature_type_flag = workspace("semantic_interface.signature.type_flag")?;
        let (signature_type_prefix, signature_type_total) = typecheck_graph
            .semantic_interface_scan_outputs(
                compiler_graph::SemanticInterfaceScan::SignatureTypes,
            )?;
        let signature_edge_count = workspace("semantic_interface.signature.edge_count")?;
        let (signature_edge_prefix, signature_edge_total) = typecheck_graph
            .semantic_interface_scan_outputs(
                compiler_graph::SemanticInterfaceScan::SignatureEdges,
            )?;
        let signature_type_by_decl = workspace("semantic_interface.signature.type_by_decl")?;
        let complete_type_count = workspace("semantic_interface.complete_type_count")?;
        let complete_edge_total = workspace("semantic_interface.complete_edge_total")?;
        let signature_scan_count = initialized_u32_buffer(
            &self.semantic_interface_buffers,
            device,
            queue,
            "type_check.interface.signature.scan_count",
            &[signature_capacity],
            wgpu::BufferUsages::STORAGE,
        );
        let member_capacity = capacity
            .checked_mul(2)
            .and_then(|value| value.checked_add(token_capacity))
            .ok_or_else(|| anyhow::anyhow!("semantic-interface member capacity overflows u32"))?;
        let variant_count_by_hir = workspace("semantic_interface.members.variant_count_by_hir")?;
        let field_count_by_hir = workspace("semantic_interface.members.field_count_by_hir")?;
        let generic_type_count_by_decl =
            workspace("semantic_interface.members.generic_type_count_by_decl")?;
        let generic_const_count_by_decl =
            workspace("semantic_interface.members.generic_const_count_by_decl")?;
        let member_count = workspace("semantic_interface.members.row_count")?;
        let member_cursor = workspace("semantic_interface.members.cursor")?;
        let (member_prefix, member_total) = typecheck_graph
            .semantic_interface_scan_outputs(compiler_graph::SemanticInterfaceScan::Members)?;
        let members = workspace("semantic_interface.members.records")?;
        let member_name_id = workspace("semantic_interface.members.name_id")?;
        let member_index_by_generic_row =
            workspace("semantic_interface.members.index_by_generic_row")?;
        let member_written = workspace("semantic_interface.members.written")?;
        let signature_scan_params = PrefixScanParams {
            n_items: signature_capacity,
            n_blocks: signature_n_blocks,
            min_items: 0,
        };
        let (signature_dispatch_x, signature_dispatch_y, signature_dispatch_z) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(signature_capacity),
            [
                self.passes
                    .kernel("scan/counted/00_local")
                    .thread_group_size[0],
                self.passes
                    .kernel("scan/counted/00_local")
                    .thread_group_size[1],
                1,
            ],
        )?;
        let signature_dispatch_args = initialized_u32_buffer(
            &self.semantic_interface_buffers,
            device,
            queue,
            "type_check.interface.signature.dispatch_args",
            &[
                signature_dispatch_x,
                signature_dispatch_y,
                signature_dispatch_z,
            ],
            wgpu::BufferUsages::INDIRECT,
        );
        let signature_type_scan = graph_prefix_scan(
            device,
            queue,
            &self.semantic_interface_buffers,
            &self.passes,
            "type_check.interface.signature.type_scan",
            signature_scan_params,
            typecheck_graph,
            compiler_graph::SemanticInterfaceScan::SignatureTypes,
            (&signature_scan_count).into(),
            &signature_dispatch_args,
            (&signature_type_flag).into(),
            &signature_type_prefix,
            &signature_type_total,
            scan_scratch,
        )?;
        let signature_edge_scan = graph_prefix_scan(
            device,
            queue,
            &self.semantic_interface_buffers,
            &self.passes,
            "type_check.interface.signature.edge_scan",
            signature_scan_params,
            typecheck_graph,
            compiler_graph::SemanticInterfaceScan::SignatureEdges,
            (&signature_scan_count).into(),
            &signature_dispatch_args,
            (&signature_edge_count).into(),
            &signature_edge_prefix,
            &signature_edge_total,
            scan_scratch,
        )?;
        let member_scan = graph_prefix_scan(
            device,
            queue,
            &self.semantic_interface_buffers,
            &self.passes,
            "type_check.interface.members.scan",
            signature_scan_params,
            typecheck_graph,
            compiler_graph::SemanticInterfaceScan::Members,
            (&signature_scan_count).into(),
            &signature_dispatch_args,
            (&member_count).into(),
            &member_prefix,
            &member_total,
            scan_scratch,
        )?;
        let [tgsx, tgsy, _] = self
            .passes
            .kernel("scan/counted/00_local")
            .thread_group_size;
        let (dispatch_x, dispatch_y, dispatch_z) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(capacity),
            [tgsx, tgsy, 1],
        )?;
        let dispatch_args = initialized_u32_buffer(
            &self.semantic_interface_buffers,
            device,
            queue,
            "type_check.interface.type_topology.dispatch_args",
            &[dispatch_x, dispatch_y, dispatch_z],
            wgpu::BufferUsages::INDIRECT,
        );
        let scan_params = PrefixScanParams {
            n_items: capacity,
            n_blocks,
            min_items: 0,
        };
        let scan = graph_prefix_scan(
            device,
            queue,
            &self.semantic_interface_buffers,
            &self.passes,
            "type_check.interface.type_topology.scan",
            scan_params,
            typecheck_graph,
            compiler_graph::SemanticInterfaceScan::TypeOrder,
            (&scan_count).into(),
            &dispatch_args,
            (&reverse_flag).into(),
            &reverse_prefix,
            &count,
            scan_scratch,
        )?;
        let edge_scan = graph_prefix_scan(
            device,
            queue,
            &self.semantic_interface_buffers,
            &self.passes,
            "type_check.interface.type_topology.edge_scan",
            scan_params,
            typecheck_graph,
            compiler_graph::SemanticInterfaceScan::TypeEdges,
            (&scan_count).into(),
            &dispatch_args,
            (&edge_count).into(),
            &edge_prefix,
            &edge_total,
            scan_scratch,
        )?;

        // The graph is materialized at daemon workspace capacity, while this
        // job can dispatch fewer active rows. Use the graph's complete
        // ping-pong schedule so downstream bindings select the buffer that was
        // actually written; deriving parity from the active row count can
        // leave the result in A while the graph correctly reads B.
        let root_steps = typecheck_graph.semantic_interface_root_step_count()?;
        let final_root_owner = if root_steps & 1 == 0 {
            &root_owner_a
        } else {
            &root_owner_b
        };

        let mut topology_resources = ResourceMap::new();
        typecheck_graph.register_semantic_interface_bindings(&mut topology_resources)?;
        macro_rules! register_resources {
            ($($name:literal => $buffer:expr),* $(,)?) => {
                $(topology_resources.buffer($name, &$buffer);)*
            };
        }
        register_resources!(
            "gParams" => params,
            "compact_const_type" => hir.compact_const_type,
            "compact_field_count" => hir.compact_field_count,
            "compact_fields" => hir.compact_fields,
            "compact_fn_return_type" => hir.compact_fn_return_type,
            "compact_hir_core" => hir.compact_hir_core,
            "compact_hir_count" => hir.compact_hir_count,
            "compact_hir_payload" => hir.compact_hir_payload,
            "compact_param_count" => hir.compact_param_count,
            "compact_param_ranges" => hir.compact_param_ranges,
            "compact_params" => hir.compact_params,
            "compact_type_alias_target" => hir.compact_type_alias_target,
            "compact_type_arg_count" => hir.compact_type_arg_count,
            "compact_type_arg_ranges" => hir.compact_type_arg_ranges,
            "compact_type_args" => hir.compact_type_args,
            "compact_generic_param_count" => hir.compact_generic_param_count,
            "compact_generic_params" => hir.compact_generic_params,
            "compact_path_count" => hir.compact_path_count,
            "compact_paths" => hir.compact_paths,
            "compact_path_segment_count" => hir.compact_path_segment_count,
            "compact_path_segments" => hir.compact_path_segments,
            "compact_variant_count" => hir.compact_variant_count,
            "compact_variant_payload_count" => hir.compact_variant_payload_count,
            "compact_variant_payload_row_count" => hir.compact_variant_payload_row_count,
            "compact_variant_payloads" => hir.compact_variant_payloads,
            "compact_method_count" => hir.compact_method_count,
            "compact_method_cores" => hir.compact_method_cores,
            "compact_method_signatures" => hir.compact_method_signatures,
            "compact_variants" => hir.compact_variants,
            "decl_hir_node" => inputs.decl_hir_node,
            "decl_count_out" => inputs.decl_count_out,
            "decl_id_by_name_token" => inputs.decl_id_by_name_token,
            "decl_kind" => inputs.decl_kind,
            "decl_parent_type_decl" => inputs.decl_parent_type_decl,
            "external_type_library_id" => inputs.external_type_library_id,
            "external_type_unit_id" => inputs.external_type_unit_id,
            "external_type_local_index" => inputs.external_type_local_index,
            "semantic_type_ref_tag_by_hir" => inputs.semantic_type_ref_tag_by_hir,
            "semantic_type_ref_payload_by_hir" => inputs.semantic_type_ref_payload_by_hir,
            "semantic_type_generic_param_slot_by_hir" => inputs.semantic_type_generic_param_slot_by_hir,
            "semantic_type_external_library_id_by_hir" => inputs.semantic_type_external_library_id_by_hir,
            "semantic_type_external_unit_id_by_hir" => inputs.semantic_type_external_unit_id_by_hir,
            "semantic_type_external_local_index_by_hir" => inputs.semantic_type_external_local_index_by_hir,
            "generic_param_count_out" => inputs.generic_param_count_out,
            "generic_param_kind" => inputs.generic_param_kind,
            "generic_param_name_id" => inputs.generic_param_name_id,
            "generic_param_owner_token" => inputs.generic_param_owner_token,
            "generic_param_token" => inputs.generic_param_token,
            "name_id_by_token" => inputs.name_id_by_token,
            "path_id_by_owner_hir" => inputs.path_id_by_owner_hir,
            "path_id_by_owner_token" => inputs.path_id_by_owner_token,
            "interface_public_decl_count" => inputs.public_decl_count,
            "interface_public_decl_index_by_hir" => inputs.public_decl_index_by_hir,
            "interface_public_decl_index_by_local" => inputs.public_decl_index_by_local,
            "interface_public_decl_local_id" => inputs.public_decl_local_id,
            "resolved_dependency_library_id" => inputs.resolved_dependency_library_id,
            "resolved_dependency_unit_id" => inputs.resolved_dependency_unit_id,
            "resolved_dependency_local_index" => inputs.resolved_dependency_local_index,
            "resolved_type_decl" => inputs.resolved_type_decl,
            "type_const_param_slot_by_token" => inputs.type_const_param_slot_by_token,
            "type_expr_ref_payload" => inputs.type_expr_ref_payload,
            "type_expr_ref_tag" => inputs.type_expr_ref_tag,
            "type_generic_param_slot_by_token" => inputs.type_generic_param_slot_by_token,
            "type_instance_decl_token" => inputs.type_instance_decl_token,
            "interface_complete_edge_total" => complete_edge_total,
            "interface_complete_type_count" => complete_type_count,
            "interface_decl_direct_type_hir" => direct_type_hir_by_decl,
            "interface_field_count_by_hir" => field_count_by_hir,
            "interface_generic_const_count_by_decl" => generic_const_count_by_decl,
            "interface_generic_type_count_by_decl" => generic_type_count_by_decl,
            "interface_member_count" => member_count,
            "interface_member_cursor" => member_cursor,
            "interface_member_index_by_generic_row" => member_index_by_generic_row,
            "interface_member_name_id" => member_name_id,
            "interface_member_prefix" => member_prefix,
            "interface_member_total" => member_total,
            "interface_member_words" => members,
            "interface_member_written" => member_written,
            "interface_signature_edge_count" => signature_edge_count,
            "interface_signature_edge_prefix" => signature_edge_prefix,
            "interface_signature_edge_total" => signature_edge_total,
            "interface_signature_type_by_decl" => signature_type_by_decl,
            "interface_signature_type_flag" => signature_type_flag,
            "interface_signature_type_prefix" => signature_type_prefix,
            "interface_signature_type_total" => signature_type_total,
            "interface_status" => status,
            "interface_type_child_ordinal" => child_ordinal,
            "interface_type_count" => count,
            "interface_type_edge_count" => edge_count,
            "interface_type_edge_prefix" => edge_prefix,
            "interface_type_edge_total" => edge_total,
            "interface_type_edge_written" => edge_written,
            "interface_type_edges" => edges,
            "interface_type_hir_order" => hir_order,
            "interface_type_index_by_hir" => index_by_hir,
            "interface_type_local_decl_by_hir" => local_decl_by_hir,
            "interface_type_parent" => parent,
            "interface_type_path_classification" => path_classification,
            "interface_type_reverse_flag" => reverse_flag,
            "interface_type_reverse_prefix" => reverse_prefix,
            "interface_type_root_link" => root_link_a,
            "interface_type_root_owner" => final_root_owner,
            "interface_type_seed_owner" => seed_owner,
            "interface_types" => types,
            "interface_variant_count_by_hir" => variant_count_by_hir,
        );
        let interface_graph = typecheck_graph.semantic_interface_graph()?;
        macro_rules! bind_topology {
            ($label:literal, $kernel:literal) => {
                crate::gpu::operations::ComputeOperation::direct(
                    device,
                    interface_graph,
                    &topology_resources,
                    $label,
                    &self.passes.kernel($kernel),
                    capacity,
                )
            };
            ($label:literal, $kernel:literal, $work:expr) => {
                crate::gpu::operations::ComputeOperation::direct(
                    device,
                    interface_graph,
                    &topology_resources,
                    $label,
                    &self.passes.kernel($kernel),
                    $work,
                )
            };
        }

        let init = bind_topology!(
            "type_check.interface.type_topology.init",
            "type_checker/interface/type_topology/00_init"
        )?;
        let attach_unary = bind_topology!(
            "type_check.interface.type_topology.attach_unary",
            "type_checker/interface/type_topology/01_attach_unary"
        )?;
        let seed_declarations = bind_topology!(
            "type_check.interface.type_topology.seed_declarations",
            "type_checker/interface/type_topology/02_seed_declarations"
        )?;
        let seed_params = bind_topology!(
            "type_check.interface.type_topology.seed_params",
            "type_checker/interface/type_topology/02b_seed_params"
        )?;
        let seed_fields = bind_topology!(
            "type_check.interface.type_topology.seed_fields",
            "type_checker/interface/type_topology/02c_seed_fields"
        )?;
        let seed_variants = bind_topology!(
            "type_check.interface.type_topology.seed_variants",
            "type_checker/interface/type_topology/02d_seed_variants"
        )?;
        let root_init = bind_topology!(
            "type_check.interface.type_topology.root_init",
            "type_checker/interface/type_topology/03_root_init"
        )?;
        let root_step_operations = compiler_graph::SEMANTIC_INTERFACE_ROOT_STEP_PASSES
            .iter()
            .take(root_steps)
            .map(|&name| {
                crate::gpu::operations::ComputeOperation::direct(
                    device,
                    interface_graph,
                    &topology_resources,
                    name,
                    &self
                        .passes
                        .kernel("type_checker/interface/type_topology/04_root_step"),
                    capacity,
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let mark_reverse = bind_topology!(
            "type_check.interface.type_topology.mark_reverse",
            "type_checker/interface/type_topology/05_mark_reverse"
        )?;
        let scatter = bind_topology!(
            "type_check.interface.type_topology.scatter",
            "type_checker/interface/type_topology/06_scatter"
        )?;
        let edge_counts = bind_topology!(
            "type_check.interface.type_topology.edge_counts",
            "type_checker/interface/type_topology/08_edge_counts"
        )?;
        let edge_scatter = bind_topology!(
            "type_check.interface.type_topology.edge_scatter",
            "type_checker/interface/type_topology/09_edge_scatter"
        )?;
        let resolve_local_decl = bind_topology!(
            "type_check.interface.type_topology.resolve_local_decl",
            "type_checker/interface/type_topology/10_resolve_local_decl"
        )?;
        let classify_path = bind_topology!(
            "type_check.interface.type_topology.classify_path",
            "type_checker/interface/type_topology/11_classify_path"
        )?;
        let type_records = bind_topology!(
            "type_check.interface.type_topology.type_records",
            "type_checker/interface/type_topology/12_type_records"
        )?;
        let array_lengths = bind_topology!(
            "type_check.interface.type_topology.array_lengths",
            "type_checker/interface/type_topology/13_array_lengths"
        )?;
        let signature_flags = bind_topology!(
            "type_check.interface.signature.flags",
            "type_checker/interface/signature/00_flags",
            signature_capacity
        )?;
        let signature_totals = bind_topology!(
            "type_check.interface.signature.totals",
            "type_checker/interface/signature/01_totals",
            1
        )?;
        let signature_direct_types = bind_topology!(
            "type_check.interface.signature.direct_types",
            "type_checker/interface/signature/01b_direct_types",
            signature_capacity
        )?;
        let signature_synthetic_types = bind_topology!(
            "type_check.interface.signature.synthetic_types",
            "type_checker/interface/signature/01c_synthetic_types",
            signature_capacity
        )?;
        let signature_param_edges = bind_topology!(
            "type_check.interface.signature.param_edges",
            "type_checker/interface/signature/02_param_edges"
        )?;
        let signature_return_edges = bind_topology!(
            "type_check.interface.signature.return_edges",
            "type_checker/interface/signature/03_return_edges",
            signature_capacity
        )?;
        let signature_variant_payload_edges = bind_topology!(
            "type_check.interface.signature.variant_payload_edges",
            "type_checker/interface/signature/02b_variant_payload_edges"
        )?;
        let members_variant_counts = bind_topology!(
            "type_check.interface.members.variant_counts",
            "type_checker/interface/members/00_variant_counts"
        )?;
        let members_generic_counts = bind_topology!(
            "type_check.interface.members.generic_counts",
            "type_checker/interface/members/00b_generic_counts",
            token_capacity.max(1)
        )?;
        let members_counts = bind_topology!(
            "type_check.interface.members.counts",
            "type_checker/interface/members/01_counts",
            signature_capacity
        )?;
        let members_method_counts = bind_topology!(
            "type_check.interface.members.method_counts",
            "type_checker/interface/members/00c_method_counts"
        )?;
        let members_scatter_hir = bind_topology!(
            "type_check.interface.members.scatter_hir",
            "type_checker/interface/members/02_scatter_hir"
        )?;
        let members_scatter_generic = bind_topology!(
            "type_check.interface.members.scatter_generic",
            "type_checker/interface/members/03_scatter_generic",
            token_capacity.max(1)
        )?;
        let members_normalize_types = bind_topology!(
            "type_check.interface.members.normalize_types",
            "type_checker/interface/members/04_normalize_types"
        )?;
        let validate = bind_topology!(
            "type_check.interface.type_topology.validate",
            "type_checker/interface/type_topology/07_validate"
        )?;

        let clears = [
            crate::gpu::operations::ClearBufferOperation::entire(
                interface_graph,
                compiler_graph::SEMANTIC_INTERFACE_EDGE_WRITTEN_CLEAR_PASS,
                "interface_type_edge_written",
                &edge_written,
            )?,
            crate::gpu::operations::ClearBufferOperation::entire(
                interface_graph,
                compiler_graph::SEMANTIC_INTERFACE_FIELD_COUNT_CLEAR_PASS,
                "interface_field_count_by_hir",
                &field_count_by_hir,
            )?,
            crate::gpu::operations::ClearBufferOperation::entire(
                interface_graph,
                compiler_graph::SEMANTIC_INTERFACE_VARIANT_COUNT_CLEAR_PASS,
                "interface_variant_count_by_hir",
                &variant_count_by_hir,
            )?,
            crate::gpu::operations::ClearBufferOperation::entire(
                interface_graph,
                compiler_graph::SEMANTIC_INTERFACE_GENERIC_TYPE_COUNT_CLEAR_PASS,
                "interface_generic_type_count_by_decl",
                &generic_type_count_by_decl,
            )?,
            crate::gpu::operations::ClearBufferOperation::entire(
                interface_graph,
                compiler_graph::SEMANTIC_INTERFACE_GENERIC_CONST_COUNT_CLEAR_PASS,
                "interface_generic_const_count_by_decl",
                &generic_const_count_by_decl,
            )?,
            crate::gpu::operations::ClearBufferOperation::entire(
                interface_graph,
                compiler_graph::SEMANTIC_INTERFACE_MEMBER_WRITTEN_CLEAR_PASS,
                "interface_member_written",
                &member_written,
            )?,
        ];
        for clear in &clears {
            clear.record(encoder);
        }
        for operation in [
            &init,
            &attach_unary,
            &seed_declarations,
            &seed_params,
            &seed_fields,
            &seed_variants,
            &root_init,
        ] {
            operation.record(encoder)?;
        }
        for operation in &root_step_operations {
            operation.record(encoder)?;
        }
        mark_reverse.record(encoder)?;
        scan.record(encoder)?;
        scatter.record(encoder)?;
        edge_counts.record(encoder)?;
        edge_scan.record(encoder)?;
        for operation in [
            &edge_scatter,
            &resolve_local_decl,
            &classify_path,
            &type_records,
            &array_lengths,
            &validate,
            &signature_flags,
        ] {
            operation.record(encoder)?;
        }
        signature_type_scan.record(encoder)?;
        signature_edge_scan.record(encoder)?;
        for operation in [
            &signature_totals,
            &signature_direct_types,
            &signature_synthetic_types,
            &signature_param_edges,
            &signature_variant_payload_edges,
            &signature_return_edges,
            &members_variant_counts,
            &members_generic_counts,
            &members_counts,
            &members_method_counts,
        ] {
            operation.record(encoder)?;
        }
        member_scan.record(encoder)?;
        for operation in [
            &members_scatter_hir,
            &members_scatter_generic,
            &members_normalize_types,
        ] {
            operation.record(encoder)?;
        }

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
            _variant_count_by_hir: variant_count_by_hir,
            _field_count_by_hir: field_count_by_hir,
            _generic_type_count_by_decl: generic_type_count_by_decl,
            _generic_const_count_by_decl: generic_const_count_by_decl,
            _member_count: member_count,
            _member_prefix: member_prefix,
            _member_total: member_total,
            _member_cursor: member_cursor,
            _members: members,
            _member_name_id: member_name_id,
            _member_index_by_generic_row: member_index_by_generic_row,
            _member_written: member_written,
            _params: params,
        })
    }

    /// Reads the exact persisted interface emitted by the GPU. Only the small
    /// length/status packet is mapped at capacity; artifact data is transferred
    /// in bounded pages up to the exact length reported by the shader.
    pub fn finish_semantic_interface(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        recorded: &RecordedSemanticInterface,
    ) -> Result<GpuSemanticInterfaceArtifact> {
        let metadata_slice = recorded.metadata_readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(
            device,
            &metadata_slice,
            "semantic-interface artifact metadata",
        )?;
        let mapped = metadata_slice.get_mapped_range();
        let metadata = read_u32_words::<5>(&mapped, "semantic-interface artifact metadata")?;
        drop(mapped);
        recorded.metadata_readback.unmap();
        let [byte_len, status, detail, name_id, name_len] = metadata;
        if status != 0 {
            return Err(anyhow::anyhow!(
                "semantic-interface GPU export failed: status=0x{status:08x}, detail={detail}, name_id={name_id}, name_len={name_len}"
            ));
        }
        let byte_len = byte_len as usize;
        if byte_len > recorded.artifact_capacity {
            return Err(anyhow::anyhow!(
                "semantic-interface artifact requires {byte_len} bytes but its bounded GPU output has {}",
                recorded.artifact_capacity
            ));
        }
        if crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false) {
            eprintln!(
                "[gpu_compile_host_timer] semantic_interface.artifact: bytes={byte_len} capacity_bytes={} amplification={:.3}",
                recorded.artifact_capacity,
                recorded.artifact_capacity as f64 / byte_len.max(1) as f64,
            );
        }
        let bytes = recorded.artifact_readback.read(
            device,
            queue,
            &recorded._artifact_words.buffer,
            0,
            byte_len,
            "semantic-interface artifact",
        )?;
        let artifact = GpuSemanticInterfaceArtifact::from_bytes(&bytes)
            .map_err(|reason| anyhow::anyhow!("invalid GPU semantic interface: {reason}"))?;
        if artifact.library_id != recorded.expected_library_id
            || artifact.unit_id != recorded.expected_unit_id
        {
            return Err(anyhow::anyhow!(
                "semantic-interface identity changed during GPU export: expected [{}, {}], got [{}, {}]",
                recorded.expected_library_id,
                recorded.expected_unit_id,
                artifact.library_id,
                artifact.unit_id,
            ));
        }
        Ok(artifact)
    }
}

fn semantic_interface_artifact_capacity(
    module_capacity: u32,
    module_segment_capacity: u32,
    declaration_capacity: u32,
    type_capacity: usize,
    edge_capacity: usize,
    member_capacity: usize,
    name_byte_capacity: u32,
) -> Result<usize> {
    let table_words = [
        (module_capacity as usize, MODULE_WORDS),
        (module_segment_capacity as usize, MODULE_SEGMENT_WORDS),
        (declaration_capacity as usize, DECLARATION_WORDS),
        (type_capacity, TYPE_WORDS),
        (edge_capacity, 1),
        (member_capacity, MEMBER_WORDS),
    ]
    .into_iter()
    .try_fold(0usize, |total, (rows, words)| {
        rows.checked_mul(words)
            .and_then(|words| total.checked_add(words))
    })
    .ok_or_else(|| anyhow::anyhow!("semantic-interface artifact table capacity overflows"))?;
    72usize
        .checked_add(
            table_words
                .checked_mul(4)
                .ok_or_else(|| anyhow::anyhow!("semantic-interface artifact bytes overflow"))?,
        )
        .and_then(|bytes| bytes.checked_add(name_byte_capacity as usize))
        .ok_or_else(|| anyhow::anyhow!("semantic-interface artifact capacity overflows"))
}

fn initialized_u32_buffer(
    cache: &CapacityBufferCache,
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    label: &str,
    words: &[u32],
    extra_usage: wgpu::BufferUsages,
) -> LaniusBuffer<u32> {
    cache.initialized_u32(device, queue, label, words, extra_usage)
}
