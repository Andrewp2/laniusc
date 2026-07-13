use super::*;
use crate::compiler::{
    GpuSemanticInterfaceDeclarationRecord,
    GpuSemanticInterfaceIdentityArtifact,
    GpuSemanticInterfaceModuleRecord,
    GpuSemanticInterfaceModuleSegmentRecord,
};

const MODULE_WORDS: usize = 2;
const MODULE_SEGMENT_WORDS: usize = 4;
const DECLARATION_WORDS: usize = 14;
const COUNT_WORDS: usize = 5;
const STATUS_WORDS: usize = 4;

/// GPU outputs and host-visible copies recorded for one bounded unit's public
/// semantic identities. The input semantic tables remain owned by the resident
/// type checker until the enclosing compilation submission completes.
pub struct RecordedSemanticInterfaceIdentity {
    expected_library_id: u32,
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
    pub fn record_semantic_interface_identity(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        library_id: u32,
        source_len: u32,
        source_bytes: &wgpu::Buffer,
    ) -> Result<RecordedSemanticInterfaceIdentity> {
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
            public_decl_count: &module_path.interface_public_decl_count,
            public_decl_local_id: &module_path.interface_public_decl_local_id,
            public_decl_index_by_local: &module_path.interface_public_decl_index_by_local,
            decl_type_ref_tag: &state.decl_type_ref_tag,
            decl_type_ref_payload: &state.decl_type_ref_payload,
            fn_return_ref_tag: &state.fn_return_ref_tag,
            fn_return_ref_payload: &state.fn_return_ref_payload,
        };
        self.record_semantic_interface_identity_from_buffers(
            device,
            encoder,
            library_id,
            source_len,
            source_bytes,
            inputs,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn record_semantic_interface_identity_from_buffers(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        library_id: u32,
        source_len: u32,
        source_bytes: &wgpu::Buffer,
        inputs: GpuSemanticInterfaceIdentityBuffers<'_>,
    ) -> Result<RecordedSemanticInterfaceIdentity> {
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
        if module_capacity == 0 || module_segment_capacity % module_capacity != 0 {
            return Err(anyhow::anyhow!(
                "module segment capacity {module_segment_capacity} is not a fixed-width multiple of module capacity {module_capacity}"
            ));
        }
        let module_segment_row_width = module_segment_capacity / module_capacity;
        let name_ref_count = module_segment_capacity
            .checked_add(decl_capacity)
            .ok_or_else(|| {
                anyhow::anyhow!("semantic-interface name-reference capacity overflows u32")
            })?;
        let declaration_capacity = decl_capacity;
        let name_byte_capacity = source_len
            .checked_add(u32::try_from(LANGUAGE_SYMBOL_BYTES.len()).unwrap_or(u32::MAX))
            .ok_or_else(|| anyhow::anyhow!("semantic-interface name-byte capacity overflows u32"))?
            .max(1);
        let scan_n_blocks = name_ref_count.max(1).div_ceil(256).max(1);
        let module_scan_n_blocks = module_capacity.max(1).div_ceil(256).max(1);
        let identity_work_capacity = module_segment_capacity
            .max(module_capacity)
            .max(decl_capacity);

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

        let size_params = uniform_from_val(
            device,
            "type_check.interface.identity_size_params",
            &SemanticInterfaceIdentitySizeParams {
                name_capacity,
                module_capacity,
                decl_capacity,
                module_segment_capacity,
                module_segment_row_width,
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
                ("public_decl_count", inputs.public_decl_count.as_entire_binding()),
                (
                    "public_decl_local_id",
                    inputs.public_decl_local_id.as_entire_binding(),
                ),
                ("decl_name_id", inputs.decl_name_id.as_entire_binding()),
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
                module_segment_row_width,
                name_byte_capacity,
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
                ("public_decl_count", inputs.public_decl_count.as_entire_binding()),
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
                ("interface_modules", modules.as_entire_binding()),
                (
                    "interface_module_segments",
                    module_segments.as_entire_binding(),
                ),
                (
                    "interface_declaration_words",
                    declarations.as_entire_binding(),
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
                module_segment_row_width,
                decl_capacity,
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
                ("public_decl_count", inputs.public_decl_count.as_entire_binding()),
                (
                    "public_decl_local_id",
                    inputs.public_decl_local_id.as_entire_binding(),
                ),
                ("decl_name_id", inputs.decl_name_id.as_entire_binding()),
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
            &name_byte_words,
            0,
            &name_bytes_readback,
            0,
            (name_word_capacity.max(1) * 4) as u64,
        );
        record_typecheck_copy_buffer_to_buffer(encoder, &counts, 0, &counts_readback, 0, 20);
        record_typecheck_copy_buffer_to_buffer(encoder, &status, 0, &status_readback, 0, 16);

        Ok(RecordedSemanticInterfaceIdentity {
            expected_library_id: library_id,
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
            modules_readback,
            module_segments_readback,
            declarations_readback,
            name_bytes_readback,
            counts_readback,
            status_readback,
        })
    }

    /// Decodes and validates the identity artifact after the caller submits the
    /// command encoder containing `record_semantic_interface_identity`.
    pub fn finish_semantic_interface_identity(
        &self,
        device: &wgpu::Device,
        recorded: &RecordedSemanticInterfaceIdentity,
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
    LaniusBuffer::new((raw, bytes.len() as u64), words.len())
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
