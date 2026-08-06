use super::*;
use crate::{
    compiler::{GPU_SEMANTIC_INTERFACE_VERSION, GpuSemanticInterfaceArtifact},
    gpu::{
        buffers::readback_bytes,
        readback::{PagedReadback, read_u32_words},
    },
};

const MODULE_WORDS: usize = 2;
const MODULE_SEGMENT_WORDS: usize = 4;
const DECLARATION_WORDS: usize = 14;
const COUNT_WORDS: usize = 5;
const TYPE_WORDS: usize = 9;
const MEMBER_WORDS: usize = 10;

#[allow(clippy::too_many_arguments)]
fn graph_prefix_scan(
    device: &wgpu::Device,
    kernels: &KernelRegistry,
    label: &'static str,
    params: PrefixScanParams,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    scan: compiler_graph::SemanticInterfaceScan,
    count: &wgpu::Buffer,
    dispatch_args: &wgpu::Buffer,
    input: &wgpu::Buffer,
    output_prefix: &LaniusBuffer<u32>,
    total: &LaniusBuffer<u32>,
    workspace: PrefixScanWorkspace<&LaniusBuffer<u32>>,
) -> Result<PrefixScanOperation> {
    let mut resources = ResourceMap::new();
    for (name, buffer) in [
        ("scan_count", count),
        ("scan_input", input),
        ("scan_dispatch_args", dispatch_args),
    ] {
        resources.add(name, buffer.as_entire_binding());
    }
    resources.buffers([
        ("scan_output_prefix", output_prefix),
        ("scan_total", total),
        ("scan_local_prefix", workspace.local_prefix),
        ("scan_block_sum", workspace.block_sum),
        ("scan_block_prefix", workspace.block_prefix),
        ("scan_hierarchy", workspace.hierarchy),
    ]);
    graph.validate_semantic_interface_scan(scan, &resources)?;
    PrefixScanOperation::with_workspace(
        device,
        kernels,
        label,
        params,
        count,
        dispatch_args,
        input,
        output_prefix,
        total,
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
        encoder: &mut wgpu::CommandEncoder,
        library_id: u32,
        unit_id: u32,
        source_len: u32,
        token_capacity: u32,
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
        ];
        let inputs = GpuSemanticInterfaceIdentityBuffers {
            name_capacity: state.name_capacity,
            module_capacity: u32::try_from(module_path.module_key_segment_count.count)
                .unwrap_or(u32::MAX),
            declaration_capacity: u32::try_from(module_path.interface_public_decl_local_id.count)
                .unwrap_or(u32::MAX),
            module_segment_capacity: u32::try_from(module_path.module_key_segment_name_id.count)
                .unwrap_or(u32::MAX),
            name_count_out: &name_scan_total,
            name_spans: &name_spans,
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
            function_host_service_by_hir: &graph_buffers[14],
            public_decl_count: &module_path.interface_public_decl_count,
            public_decl_local_id: &module_path.interface_public_decl_local_id,
            public_decl_index_by_local: &module_path.interface_public_decl_index_by_local,
            public_decl_index_by_hir: &module_path.interface_public_decl_index_by_hir,
            type_expr_ref_tag: &graph_buffers[0],
            type_expr_ref_payload: &graph_buffers[1],
            type_generic_param_slot_by_token: &graph_buffers[2],
            type_const_param_slot_by_token: &graph_buffers[3],
            type_instance_decl_token: &state.type_instance_decl_token,
            external_type_library_id: &graph_buffers[11],
            external_type_unit_id: &graph_buffers[12],
            external_type_local_index: &graph_buffers[13],
            path_id_by_owner_token: &module_path.path_id_by_owner_token,
            resolved_type_decl: &module_path.resolved_type_decl,
            decl_id_by_name_token: &module_path.decl_id_by_name_token,
            generic_param_count_out: &graph_buffers[4],
            generic_param_owner_token: &graph_buffers[5],
            generic_param_name_id: &graph_buffers[6],
            generic_param_token: &graph_buffers[7],
            generic_param_kind: &graph_buffers[8],
            type_decl_generic_param_count_by_owner_token: &graph_buffers[9],
            type_decl_const_param_count_by_owner_token: &graph_buffers[10],
        };
        self.record_semantic_interface_from_buffers(
            device,
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
        let scan_scratch = typecheck_graph.semantic_interface_scan_workspace();

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
            device,
            "type_check.interface.scan_dispatch_args",
            &[dispatch_x, dispatch_y, dispatch_z],
            wgpu::BufferUsages::INDIRECT,
        );
        let scan = graph_prefix_scan(
            device,
            &self.passes,
            "type_check.interface.name_scan",
            PrefixScanParams {
                n_items: name_ref_count,
                n_blocks: scan_n_blocks,
                scan_step: 0,
            },
            typecheck_graph,
            compiler_graph::SemanticInterfaceScan::Names,
            &scan_count,
            &scan_dispatch_args,
            &name_ref_len,
            &name_ref_prefix,
            &scan_total,
            scan_scratch,
        )?;
        let module_segment_prefix = typed_storage_u32_rw(
            device,
            "type_check.interface.module_segment_prefix",
            module_capacity as usize,
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
        let module_scan = graph_prefix_scan(
            device,
            &self.passes,
            "type_check.interface.module_segment_scan",
            PrefixScanParams {
                n_items: module_capacity,
                n_blocks: module_scan_n_blocks,
                scan_step: 0,
            },
            typecheck_graph,
            compiler_graph::SemanticInterfaceScan::Modules,
            inputs.module_count_out,
            &module_scan_dispatch_args,
            inputs.module_key_segment_count,
            &module_segment_prefix,
            &module_segment_total,
            scan_scratch,
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
            device,
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
        identity_resources.buffer("name_count_out", inputs.name_count_out);
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
        identity_resources.buffer("public_decl_count", inputs.public_decl_count);
        identity_resources.buffer("public_decl_local_id", inputs.public_decl_local_id);
        identity_resources.buffer(
            "public_decl_index_by_local",
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
        let size_bind_group = identity_resources.reflected_bind_group_with_overrides(
            device,
            "type_check.interface.identity_sizes",
            &self
                .passes
                .kernel("type_checker/interface/00_identity_sizes"),
            &[("gParams", size_params.as_entire_binding())],
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
                hir_capacity: semantic_hir_capacity,
            },
        );
        let record_bind_group = identity_resources.reflected_bind_group_with_overrides(
            device,
            "type_check.interface.identity_records",
            &self
                .passes
                .kernel("type_checker/interface/01_identity_records"),
            &[("gParams", record_params.as_entire_binding())],
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
        let byte_bind_group = identity_resources.reflected_bind_group_with_overrides(
            device,
            "type_check.interface.identity_bytes",
            &self
                .passes
                .kernel("type_checker/interface/02_identity_bytes"),
            &[("gParams", byte_params.as_entire_binding())],
        )?;

        record_typecheck_clear_buffer(encoder, &name_ref_len, 0, None);
        record_typecheck_clear_buffer(encoder, &name_byte_words, 0, None);
        record_typecheck_clear_buffer(encoder, &counts, 0, None);
        module_scan.record(encoder)?;
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/00_identity_sizes"),
            &size_bind_group,
            "type_check.interface.identity_sizes",
            identity_work_capacity,
        )?;
        scan.record(encoder)?;
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/01_identity_records"),
            &record_bind_group,
            "type_check.interface.identity_records",
            identity_work_capacity,
        )?;
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/02_identity_bytes"),
            &byte_bind_group,
            "type_check.interface.identity_bytes",
            name_ref_count,
        )?;

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
        let artifact_words = typed_storage_u32_rw(
            device,
            "type_check.interface.artifact.words",
            artifact_word_capacity,
            wgpu::BufferUsages::COPY_SRC,
        );
        let artifact_length = typed_storage_u32_rw(
            device,
            "type_check.interface.artifact.length",
            1,
            wgpu::BufferUsages::COPY_SRC,
        );
        let metadata_readback = readback_bytes(
            device,
            "type_check.interface.artifact.metadata.readback",
            20,
            20,
        );
        let artifact_readback = PagedReadback::new(
            device,
            "type_check.interface.artifact.readback",
            artifact_capacity.min(4 << 20),
        );
        let artifact_params = uniform_from_val(
            device,
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
        let artifact_bind_group = artifact_resources.reflected_bind_group_with_overrides(
            device,
            "type_check.interface.artifact",
            artifact_kernel,
            &[("gParams", artifact_params.as_entire_binding())],
        )?;
        let artifact_work_capacity = module_capacity
            .max(module_segment_capacity)
            .max(declaration_capacity)
            .max(type_topology.type_capacity as u32)
            .max(type_topology.edge_capacity as u32)
            .max(type_topology.member_capacity as u32)
            .max(name_byte_capacity.div_ceil(4))
            .max(1);
        record_compute(
            encoder,
            artifact_kernel,
            &artifact_bind_group,
            "type_check.interface.artifact",
            artifact_work_capacity,
        )?;
        record_typecheck_copy_buffer_to_buffer(
            encoder,
            &artifact_length,
            0,
            &metadata_readback.buffer,
            0,
            4,
        );
        record_typecheck_copy_buffer_to_buffer(
            encoder,
            &status,
            0,
            &metadata_readback.buffer,
            4,
            16,
        );
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
        encoder: &mut wgpu::CommandEncoder,
        library_id: u32,
        unit_id: u32,
        token_capacity: u32,
        hir: GpuSemanticInterfaceHirBuffers<'_>,
        inputs: &GpuSemanticInterfaceIdentityBuffers<'_>,
        status: &wgpu::Buffer,
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
        let params = uniform_from_val(
            device,
            "type_check.interface.type_topology.params",
            &SemanticInterfaceTypeTopologyParams {
                hir_capacity: capacity,
                decl_capacity,
                token_capacity,
                library_id,
                unit_id,
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
        let member_capacity = capacity
            .checked_mul(2)
            .and_then(|value| value.checked_add(token_capacity))
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
        let member_cursor = typed_storage_u32_rw(
            device,
            "type_check.interface.members.cursor",
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
        let signature_scan_params = PrefixScanParams {
            n_items: signature_capacity,
            n_blocks: signature_n_blocks,
            scan_step: 0,
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
            device,
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
            &self.passes,
            "type_check.interface.signature.type_scan",
            signature_scan_params,
            typecheck_graph,
            compiler_graph::SemanticInterfaceScan::SignatureTypes,
            &signature_scan_count,
            &signature_dispatch_args,
            &signature_type_flag,
            &signature_type_prefix,
            &signature_type_total,
            scan_scratch,
        )?;
        let signature_edge_scan = graph_prefix_scan(
            device,
            &self.passes,
            "type_check.interface.signature.edge_scan",
            signature_scan_params,
            typecheck_graph,
            compiler_graph::SemanticInterfaceScan::SignatureEdges,
            &signature_scan_count,
            &signature_dispatch_args,
            &signature_edge_count,
            &signature_edge_prefix,
            &signature_edge_total,
            scan_scratch,
        )?;
        let member_scan = graph_prefix_scan(
            device,
            &self.passes,
            "type_check.interface.members.scan",
            signature_scan_params,
            typecheck_graph,
            compiler_graph::SemanticInterfaceScan::Members,
            &signature_scan_count,
            &signature_dispatch_args,
            &member_count,
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
            device,
            "type_check.interface.type_topology.dispatch_args",
            &[dispatch_x, dispatch_y, dispatch_z],
            wgpu::BufferUsages::INDIRECT,
        );
        let scan_params = PrefixScanParams {
            n_items: capacity,
            n_blocks,
            scan_step: 0,
        };
        let scan = graph_prefix_scan(
            device,
            &self.passes,
            "type_check.interface.type_topology.scan",
            scan_params,
            typecheck_graph,
            compiler_graph::SemanticInterfaceScan::TypeOrder,
            &scan_count,
            &dispatch_args,
            &reverse_flag,
            &reverse_prefix,
            &count,
            scan_scratch,
        )?;
        let edge_scan = graph_prefix_scan(
            device,
            &self.passes,
            "type_check.interface.type_topology.edge_scan",
            scan_params,
            typecheck_graph,
            compiler_graph::SemanticInterfaceScan::TypeEdges,
            &scan_count,
            &dispatch_args,
            &edge_count,
            &edge_prefix,
            &edge_total,
            scan_scratch,
        )?;

        let root_steps = u32::BITS - (capacity - 1).leading_zeros();
        let final_root_owner = if root_steps & 1 == 0 {
            &root_owner_a
        } else {
            &root_owner_b
        };

        let mut topology_resources = ResourceMap::new();
        macro_rules! register_resources {
            ($($name:literal => $buffer:expr),* $(,)?) => {
                $(topology_resources.add($name, $buffer.as_entire_binding());)*
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
            "compact_variant_count" => hir.compact_variant_count,
            "compact_variant_payload_count" => hir.compact_variant_payload_count,
            "compact_variant_payload_row_count" => hir.compact_variant_payload_row_count,
            "compact_variant_payloads" => hir.compact_variant_payloads,
            "compact_method_count" => hir.compact_method_count,
            "compact_method_cores" => hir.compact_method_cores,
            "compact_method_signatures" => hir.compact_method_signatures,
            "compact_variants" => hir.compact_variants,
            "decl_hir_node" => inputs.decl_hir_node,
            "decl_id_by_name_token" => inputs.decl_id_by_name_token,
            "decl_kind" => inputs.decl_kind,
            "decl_parent_type_decl" => inputs.decl_parent_type_decl,
            "external_type_library_id" => inputs.external_type_library_id,
            "external_type_unit_id" => inputs.external_type_unit_id,
            "external_type_local_index" => inputs.external_type_local_index,
            "generic_param_count_out" => inputs.generic_param_count_out,
            "generic_param_kind" => inputs.generic_param_kind,
            "generic_param_name_id" => inputs.generic_param_name_id,
            "generic_param_owner_token" => inputs.generic_param_owner_token,
            "generic_param_token" => inputs.generic_param_token,
            "name_id_by_token" => inputs.name_id_by_token,
            "path_id_by_owner_token" => inputs.path_id_by_owner_token,
            "public_decl_count" => inputs.public_decl_count,
            "public_decl_index_by_hir" => inputs.public_decl_index_by_hir,
            "public_decl_index_by_local" => inputs.public_decl_index_by_local,
            "public_decl_local_id" => inputs.public_decl_local_id,
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
        macro_rules! bind_topology {
            ($label:literal, $kernel:literal) => {
                topology_resources.reflected_bind_group_with_overrides(
                    device,
                    $label,
                    &self.passes.kernel($kernel),
                    &[],
                )
            };
            ($label:literal, $kernel:literal, $overrides:expr) => {
                topology_resources.reflected_bind_group_with_overrides(
                    device,
                    $label,
                    &self.passes.kernel($kernel),
                    $overrides,
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
            "type_checker/interface/type_topology/03_root_init",
            &[(
                "interface_type_root_owner",
                root_owner_a.as_entire_binding()
            )]
        )?;
        let root_step_ab = bind_topology!(
            "type_check.interface.type_topology.root_step_ab",
            "type_checker/interface/type_topology/04_root_step",
            &[
                (
                    "interface_type_root_link_in",
                    root_link_a.as_entire_binding()
                ),
                (
                    "interface_type_root_owner_in",
                    root_owner_a.as_entire_binding()
                ),
                (
                    "interface_type_root_link_out",
                    root_link_b.as_entire_binding()
                ),
                (
                    "interface_type_root_owner_out",
                    root_owner_b.as_entire_binding()
                ),
            ]
        )?;
        let root_step_ba = bind_topology!(
            "type_check.interface.type_topology.root_step_ba",
            "type_checker/interface/type_topology/04_root_step",
            &[
                (
                    "interface_type_root_link_in",
                    root_link_b.as_entire_binding()
                ),
                (
                    "interface_type_root_owner_in",
                    root_owner_b.as_entire_binding()
                ),
                (
                    "interface_type_root_link_out",
                    root_link_a.as_entire_binding()
                ),
                (
                    "interface_type_root_owner_out",
                    root_owner_a.as_entire_binding()
                ),
            ]
        )?;
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
            "type_checker/interface/signature/00_flags"
        )?;
        let signature_totals = bind_topology!(
            "type_check.interface.signature.totals",
            "type_checker/interface/signature/01_totals"
        )?;
        let signature_direct_types = bind_topology!(
            "type_check.interface.signature.direct_types",
            "type_checker/interface/signature/01b_direct_types"
        )?;
        let signature_synthetic_types = bind_topology!(
            "type_check.interface.signature.synthetic_types",
            "type_checker/interface/signature/01c_synthetic_types"
        )?;
        let signature_param_edges = bind_topology!(
            "type_check.interface.signature.param_edges",
            "type_checker/interface/signature/02_param_edges"
        )?;
        let signature_return_edges = bind_topology!(
            "type_check.interface.signature.return_edges",
            "type_checker/interface/signature/03_return_edges"
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
            "type_checker/interface/members/00b_generic_counts"
        )?;
        let members_counts = bind_topology!(
            "type_check.interface.members.counts",
            "type_checker/interface/members/01_counts"
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
            "type_checker/interface/members/03_scatter_generic"
        )?;
        let members_normalize_types = bind_topology!(
            "type_check.interface.members.normalize_types",
            "type_checker/interface/members/04_normalize_types"
        )?;
        let validate = bind_topology!(
            "type_check.interface.type_topology.validate",
            "type_checker/interface/type_topology/07_validate"
        )?;

        record_typecheck_clear_buffer(encoder, &edge_written, 0, None);
        record_typecheck_clear_buffer(encoder, &field_count_by_hir, 0, None);
        record_typecheck_clear_buffer(encoder, &variant_count_by_hir, 0, None);
        record_typecheck_clear_buffer(encoder, &generic_type_count_by_decl, 0, None);
        record_typecheck_clear_buffer(encoder, &generic_const_count_by_decl, 0, None);
        record_typecheck_clear_buffer(encoder, &member_written, 0, None);
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/type_topology/00_init"),
            &init,
            "type_check.interface.type_topology.init",
            capacity,
        )?;
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/type_topology/01_attach_unary"),
            &attach_unary,
            "type_check.interface.type_topology.attach_unary",
            capacity,
        )?;
        for (pass, group, label) in [
            (
                &self
                    .passes
                    .kernel("type_checker/interface/type_topology/02_seed_declarations"),
                &seed_declarations,
                "type_check.interface.type_topology.seed_declarations",
            ),
            (
                &self
                    .passes
                    .kernel("type_checker/interface/type_topology/02b_seed_params"),
                &seed_params,
                "type_check.interface.type_topology.seed_params",
            ),
            (
                &self
                    .passes
                    .kernel("type_checker/interface/type_topology/02c_seed_fields"),
                &seed_fields,
                "type_check.interface.type_topology.seed_fields",
            ),
            (
                &self
                    .passes
                    .kernel("type_checker/interface/type_topology/02d_seed_variants"),
                &seed_variants,
                "type_check.interface.type_topology.seed_variants",
            ),
        ] {
            record_compute(encoder, pass, group, label, capacity)?;
        }
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/type_topology/03_root_init"),
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
                &self
                    .passes
                    .kernel("type_checker/interface/type_topology/04_root_step"),
                group,
                "type_check.interface.type_topology.root_step",
                capacity,
            )?;
        }
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/type_topology/05_mark_reverse"),
            &mark_reverse,
            "type_check.interface.type_topology.mark_reverse",
            capacity,
        )?;
        scan.record(encoder)?;
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/type_topology/06_scatter"),
            &scatter,
            "type_check.interface.type_topology.scatter",
            capacity,
        )?;
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/type_topology/08_edge_counts"),
            &edge_counts,
            "type_check.interface.type_topology.edge_counts",
            capacity,
        )?;
        edge_scan.record(encoder)?;
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/type_topology/09_edge_scatter"),
            &edge_scatter,
            "type_check.interface.type_topology.edge_scatter",
            capacity,
        )?;
        for (pass, group, label) in [
            (
                &self
                    .passes
                    .kernel("type_checker/interface/type_topology/10_resolve_local_decl"),
                &resolve_local_decl,
                "type_check.interface.type_topology.resolve_local_decl",
            ),
            (
                &self
                    .passes
                    .kernel("type_checker/interface/type_topology/11_classify_path"),
                &classify_path,
                "type_check.interface.type_topology.classify_path",
            ),
            (
                &self
                    .passes
                    .kernel("type_checker/interface/type_topology/12_type_records"),
                &type_records,
                "type_check.interface.type_topology.type_records",
            ),
            (
                &self
                    .passes
                    .kernel("type_checker/interface/type_topology/13_array_lengths"),
                &array_lengths,
                "type_check.interface.type_topology.array_lengths",
            ),
        ] {
            record_compute(encoder, pass, group, label, capacity)?;
        }
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/type_topology/07_validate"),
            &validate,
            "type_check.interface.type_topology.validate",
            capacity,
        )?;
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/signature/00_flags"),
            &signature_flags,
            "type_check.interface.signature.flags",
            signature_capacity,
        )?;
        signature_type_scan.record(encoder)?;
        signature_edge_scan.record(encoder)?;
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/signature/01_totals"),
            &signature_totals,
            "type_check.interface.signature.totals",
            1,
        )?;
        for (pass, group, label, work) in [
            (
                &self
                    .passes
                    .kernel("type_checker/interface/signature/01b_direct_types"),
                &signature_direct_types,
                "type_check.interface.signature.direct_types",
                signature_capacity,
            ),
            (
                &self
                    .passes
                    .kernel("type_checker/interface/signature/01c_synthetic_types"),
                &signature_synthetic_types,
                "type_check.interface.signature.synthetic_types",
                signature_capacity,
            ),
            (
                &self
                    .passes
                    .kernel("type_checker/interface/signature/02_param_edges"),
                &signature_param_edges,
                "type_check.interface.signature.param_edges",
                capacity,
            ),
            (
                &self
                    .passes
                    .kernel("type_checker/interface/signature/02b_variant_payload_edges"),
                &signature_variant_payload_edges,
                "type_check.interface.signature.variant_payload_edges",
                capacity,
            ),
            (
                &self
                    .passes
                    .kernel("type_checker/interface/signature/03_return_edges"),
                &signature_return_edges,
                "type_check.interface.signature.return_edges",
                signature_capacity,
            ),
        ] {
            record_compute(encoder, pass, group, label, work)?;
        }
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/members/00_variant_counts"),
            &members_variant_counts,
            "type_check.interface.members.variant_counts",
            capacity,
        )?;
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/members/00b_generic_counts"),
            &members_generic_counts,
            "type_check.interface.members.generic_counts",
            token_capacity.max(1),
        )?;
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/members/01_counts"),
            &members_counts,
            "type_check.interface.members.counts",
            signature_capacity,
        )?;
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/members/00c_method_counts"),
            &members_method_counts,
            "type_check.interface.members.method_counts",
            capacity,
        )?;
        member_scan.record(encoder)?;
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/members/02_scatter_hir"),
            &members_scatter_hir,
            "type_check.interface.members.scatter_hir",
            capacity,
        )?;
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/members/03_scatter_generic"),
            &members_scatter_generic,
            "type_check.interface.members.scatter_generic",
            token_capacity.max(1),
        )?;
        record_compute(
            encoder,
            &self
                .passes
                .kernel("type_checker/interface/members/04_normalize_types"),
            &members_normalize_types,
            "type_check.interface.members.normalize_types",
            capacity,
        )?;

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
