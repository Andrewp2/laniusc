//! Capacity-specialized parser ownership and execution graph.
//!
//! Parser intermediates are lifetime-colored workspace resources. Only host
//! readback buffers remain external to the graph; compact HIR is the retained
//! output consumed by type checking and lowering.

pub(in crate::parser) mod hir;
pub(in crate::parser) mod token_frontend;

use crate::{
    gpu::{
        compiler_graph::{
            AccessMode,
            CompilerGraphBindings,
            CompilerGraphBuilder,
            CompilerPhase,
            MaterializedCompilerGraph,
            PassAccess,
            PassDesc,
            ReflectedResourceBinding,
            ResourceClass,
            ResourceDesc,
            ResourceDomain,
            ResourceId,
        },
        operations::{
            ClearBufferOperation,
            ClearBuffersOperation,
            ComputeOperation,
            CopyBufferOperation,
            CopyBuffersOperation,
            ResetGraphAllocationsOperation,
        },
        passes_core::{Pass, PassData},
        resource_registry::ResourceMap,
        scan::{ScanFinalize, hierarchical_scan_levels, ping_pong_scan_steps},
        workspace::WorkspaceUsageClass,
    },
    parser::{buffers::ParserBuffers, debug::DebugOutput, passes::ParserPasses},
};

pub(in crate::parser) const ACTIVE_PAIR_DISPATCH: &str = "parser.active_pair_dispatch_args";
pub(in crate::parser) const PACK_TOTALS_BLOCKS: &str = "pack_totals_blocks";
pub(in crate::parser) const PACK_TOTALS_REDUCE_A_TO_B: &str = "pack_totals_reduce.a_to_b";
pub(in crate::parser) const PACK_TOTALS_REDUCE_B_TO_A: &str = "pack_totals_reduce.b_to_a";
pub(in crate::parser) const PACK_TOTALS_REDUCE_FINAL_A_TO_B: &str =
    "pack_totals_reduce.final_a_to_b";
pub(in crate::parser) const PACK_TOTALS_STATUS: &str = "pack_totals_status";
pub(in crate::parser) const PACK_OFFSETS_STATUS: &str = "pack_offsets_status";
pub(in crate::parser) const PACK_STATUS_PROMOTE: &str = "parser.pack_status.promote";
pub(in crate::parser) const PACK_OFFSETS_LOCAL: &str = "pack_offsets_scan.local";
pub(in crate::parser) const PACK_OFFSETS_APPLY: &str = "pack_offsets_scan.apply";
pub(in crate::parser) const TREE_FEATURE_DISPATCH: &str = "parser.tree_feature_dispatch_args";
pub(in crate::parser) const BRACKET_SCAN_UP: &str = "brackets_02_scan_block_prefix.up";
pub(in crate::parser) const BRACKET_SCAN_DOWN: &str = "brackets_02_scan_block_prefix.down";
pub(in crate::parser) const BRACKET_SCAN_FINALIZE: &str = "brackets_02_scan_block_prefix.finalize";
pub(in crate::parser) const TREE_PREFIX_B_TO_A: &str = "tree_prefix_02_scan_blocks.b_to_a";
pub(in crate::parser) const TREE_PREFIX_A_TO_B: &str = "tree_prefix_02_scan_blocks.a_to_b";
pub(in crate::parser) const HIR_SEMANTIC_SCAN_UP: &str = "hir_semantic_prefix_01_blocks.up";
pub(in crate::parser) const HIR_SEMANTIC_SCAN_DOWN: &str = "hir_semantic_prefix_01_blocks.down";
pub(in crate::parser) const HIR_CANONICAL_IDENTITY_SCAN_UP: &str =
    "hir_canonical_identity_prefix.up";
pub(in crate::parser) const HIR_CANONICAL_IDENTITY_SCAN_DOWN: &str =
    "hir_canonical_identity_prefix.down";
pub(in crate::parser) const HIR_STRUCT_RANK_SCAN_UP: &str = "hir_struct_rank_prefix_01_blocks.up";
pub(in crate::parser) const HIR_STRUCT_RANK_SCAN_DOWN: &str =
    "hir_struct_rank_prefix_01_blocks.down";
pub(in crate::parser) const HIR_ENUM_RANK_SCAN_UP: &str = "hir_enum_rank_prefix_01_blocks.up";
pub(in crate::parser) const HIR_ENUM_RANK_SCAN_DOWN: &str = "hir_enum_rank_prefix_01_blocks.down";
pub(in crate::parser) const HIR_MATCH_RANK_SCAN_UP: &str = "hir_match_rank_prefix_01_blocks.up";
pub(in crate::parser) const HIR_MATCH_RANK_SCAN_DOWN: &str = "hir_match_rank_prefix_01_blocks.down";
pub(in crate::parser) const HIR_PATH_SEGMENT_SCAN_UP: &str = "hir_canonical_path_segment_prefix.up";
pub(in crate::parser) const HIR_PATH_SEGMENT_SCAN_DOWN: &str =
    "hir_canonical_path_segment_prefix.down";
pub(in crate::parser) const HIR_TYPE_PATH_LEAF_STEPS: [&str; 8] = [
    "hir_type_path_leaf_step.0",
    "hir_type_path_leaf_step.1",
    "hir_type_path_leaf_step.2",
    "hir_type_path_leaf_step.3",
    "hir_type_path_leaf_step.4",
    "hir_type_path_leaf_step.5",
    "hir_type_path_leaf_step.6",
    "hir_type_path_leaf_step.7",
];
pub(in crate::parser) const HIR_TYPE_PATH_LEAF_FINALIZE: &str = "hir_type_path_leaf_step.finalize";
pub(in crate::parser) const TREE_DEPTH_STATUS_CLEAR: &str = "parser.tree_depth_status.clear";
pub(in crate::parser) const HIR_EXPR_NAME_ROLE_CLEAR: &str = "parser.hir_expr_name_role.clear";
pub(in crate::parser) const SOURCE_FILE_TOKEN_END_CLEAR: &str =
    "parser.source_file_token_end.clear";
pub(in crate::parser) const HIR_TYPE_PATH_LEAF_LINK_B_CLEAR: &str =
    "parser.hir_type_path_leaf_link_b.clear";
pub(in crate::parser) const TOKEN_FILE_ID_CLEAR: &str = "parser.token_file_id.clear";
pub(in crate::parser) const TOKEN_FILE_ID_COPY: &str = "parser.token_file_id.copy";
pub(in crate::parser) const JOB_STORAGE_RESET: &str = "parser.workspace.clear_job_storage";
pub(in crate::parser) const STACK_EFFECT_CLEAR: &str = "parser.stack_effect.clear";
pub(in crate::parser) const HIR_CANONICAL_IDENTITY_CLEAR: &str =
    "parser.hir_canonical.identity.clear";
pub(in crate::parser) const HIR_COUNTS_READBACK: &str = "parser.hir_counts.readback";

pub(in crate::parser) struct ParserStatusReadbackOperations {
    full: [CopyBufferOperation; 3],
    partial: [CopyBufferOperation; 2],
}

pub(in crate::parser) struct ParserDispatchOperations {
    active_pair: ComputeOperation,
    tree_features: ComputeOperation,
}

pub(in crate::parser) struct ParserClearOperations {
    token_file_id: ClearBufferOperation,
    token_feature_flags: Option<ClearBufferOperation>,
    token_impl_header_kind: Option<ClearBufferOperation>,
    token_braced_rhs_statement_kind: Option<ClearBufferOperation>,
    tree_depth_status: ClearBufferOperation,
    hir_expr_name_role: ClearBufferOperation,
    source_file_token_end: ClearBufferOperation,
    hir_type_path_leaf_link_b: ClearBufferOperation,
    hir_type_arg_owner_b: ClearBufferOperation,
    hir_type_arg_link_b: ClearBufferOperation,
    hir_type_arg_rank_b: ClearBufferOperation,
    hir_item_kind: ClearBufferOperation,
    hir_path_root_owner: ClearBufferOperation,
    hir_path_segment_count: ClearBufferOperation,
    hir_string_decoded_len: ClearBufferOperation,
    hir_string_data_words: ClearBufferOperation,
    hir_call_arg_count: ClearBufferOperation,
    phase_clears: std::collections::HashMap<&'static str, ClearBuffersOperation>,
}

impl ParserClearOperations {
    pub(in crate::parser) fn record_token_file_id(&self, encoder: &mut wgpu::CommandEncoder) {
        self.token_file_id.record(encoder);
    }

    pub(in crate::parser) fn record_token_feature_flags(&self, encoder: &mut wgpu::CommandEncoder) {
        if let Some(operation) = &self.token_feature_flags {
            operation.record(encoder);
        }
    }

    pub(in crate::parser) fn record_token_impl_header_kind(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) {
        if let Some(operation) = &self.token_impl_header_kind {
            operation.record(encoder);
        }
    }

    pub(in crate::parser) fn record_token_braced_rhs_statement_kind(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) {
        if let Some(operation) = &self.token_braced_rhs_statement_kind {
            operation.record(encoder);
        }
    }

    pub(in crate::parser) fn record_tree_depth_status(&self, encoder: &mut wgpu::CommandEncoder) {
        self.tree_depth_status.record(encoder);
    }

    pub(in crate::parser) fn record_hir_expr_name_role(&self, encoder: &mut wgpu::CommandEncoder) {
        self.hir_expr_name_role.record(encoder);
    }

    pub(in crate::parser) fn record_source_file_token_end(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) {
        self.source_file_token_end.record(encoder);
    }

    pub(in crate::parser) fn record_hir_type_path_leaf_link_b(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) {
        self.hir_type_path_leaf_link_b.record(encoder);
    }

    pub(in crate::parser) fn record_hir_type_arg_secondary_rows(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) {
        self.hir_type_arg_owner_b.record(encoder);
        self.hir_type_arg_link_b.record(encoder);
        self.hir_type_arg_rank_b.record(encoder);
    }

    pub(in crate::parser) fn record_hir_item_kind(&self, encoder: &mut wgpu::CommandEncoder) {
        self.hir_item_kind.record(encoder);
    }

    pub(in crate::parser) fn record_hir_path_metadata(&self, encoder: &mut wgpu::CommandEncoder) {
        self.hir_path_root_owner.record(encoder);
        self.hir_path_segment_count.record(encoder);
    }

    pub(in crate::parser) fn record_hir_string_storage(&self, encoder: &mut wgpu::CommandEncoder) {
        self.hir_string_decoded_len.record(encoder);
        self.hir_string_data_words.record(encoder);
    }

    pub(in crate::parser) fn record_hir_call_arg_count(&self, encoder: &mut wgpu::CommandEncoder) {
        self.hir_call_arg_count.record(encoder);
    }

    pub(in crate::parser) fn record_phase(
        &self,
        name: &'static str,
        encoder: &mut wgpu::CommandEncoder,
    ) -> anyhow::Result<()> {
        self.phase_clears
            .get(name)
            .ok_or_else(|| anyhow::anyhow!("parser graph has no materialized clear `{name}`"))?
            .record(encoder);
        Ok(())
    }
}

impl ParserDispatchOperations {
    pub(in crate::parser) fn record_active_pair(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> anyhow::Result<()> {
        self.active_pair.record(encoder)
    }

    pub(in crate::parser) fn record_tree_features(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> anyhow::Result<()> {
        self.tree_features.record(encoder)
    }
}

impl ParserStatusReadbackOperations {
    pub(in crate::parser) fn record_full(&self, encoder: &mut wgpu::CommandEncoder) {
        for operation in &self.full {
            operation.record(encoder);
        }
    }

    pub(in crate::parser) fn record_partial(&self, encoder: &mut wgpu::CommandEncoder) {
        for operation in &self.partial {
            operation.record(encoder);
        }
    }
}

pub(in crate::parser) struct ParserCompilerGraph {
    materialized: MaterializedCompilerGraph,
    bindings: CompilerGraphBindings,
}

pub(in crate::parser) type ParserGraphCopy<'a> = (
    &'static str,
    crate::gpu::buffers::TrackedBufferView<'a>,
    &'static str,
    crate::gpu::buffers::TrackedBufferView<'a>,
    u64,
);

pub(in crate::parser) struct ParserCopyOperations {
    operations: std::collections::HashMap<&'static str, CopyBuffersOperation>,
}

impl ParserCopyOperations {
    pub(in crate::parser) fn new<'a>(
        graph: &ParserCompilerGraph,
        specs: impl IntoIterator<Item = (&'static str, Vec<ParserGraphCopy<'a>>)>,
    ) -> anyhow::Result<Self> {
        let mut operations = std::collections::HashMap::new();
        for (name, copies) in specs {
            if graph.materialized.graph().pass_id(name).is_none() {
                continue;
            }
            let operation = CopyBuffersOperation::prefixes(&graph.materialized, name, &copies)?;
            if operations.insert(name, operation).is_some() {
                anyhow::bail!("duplicate parser finalizer operation `{name}`");
            }
        }
        Ok(Self { operations })
    }

    pub(in crate::parser) fn record(
        &self,
        name: &'static str,
        encoder: &mut wgpu::CommandEncoder,
    ) -> anyhow::Result<()> {
        self.operations
            .get(name)
            .ok_or_else(|| anyhow::anyhow!("parser graph has no active finalizer `{name}`"))?
            .record(encoder);
        Ok(())
    }
}

#[derive(Clone, Copy)]
pub(in crate::parser) struct ParserGraphCapacity {
    pub source_capacity: u32,
    pub n_tokens: u32,
    pub token_capacity: u32,
    pub pair_capacity: u32,
    pub total_sc: u32,
    pub tree_capacity: u32,
    pub bracket_blocks: u32,
    pub tree_node_blocks: u32,
    pub tree_prefix_blocks: u32,
    pub action_table_bytes: u64,
    pub table_blob_words: u32,
    pub production_count: u32,
    pub parser_feature_flags: u32,
    pub emit_stack_matches: bool,
    pub retain_debug_hir_buffers: bool,
    pub preclassified_token_kinds: bool,
}

impl ParserCompilerGraph {
    pub(in crate::parser) fn new(
        device: &wgpu::Device,
        capacity: ParserGraphCapacity,
        passes: &ParserPasses,
    ) -> anyhow::Result<Self> {
        let graph = build_graph(capacity, passes).map_err(anyhow::Error::msg)?;
        let materialized = MaterializedCompilerGraph::new_with_upstream_storage(
            device,
            "parser.frontend",
            graph,
            &[],
        )
        .map_err(anyhow::Error::msg)?;
        let bindings = materialized.bindings()?;
        Ok(Self {
            materialized,
            bindings,
        })
    }

    /// Starts an operation resource set from the graph-owned parser workspace.
    /// Operation builders add only uniforms and true phase inputs; parser
    /// intermediates are resolved from the graph's canonical resource table.
    pub(in crate::parser) fn operation_resources(
        &self,
        operation: &'static str,
    ) -> anyhow::Result<ResourceMap<'_>> {
        let mut resources = ResourceMap::new();
        resources.attach_graph(self.materialized.graph(), self.materialized.allocations());
        resources.register_pass_bindings(self.materialized.graph(), &self.bindings, operation)?;
        Ok(resources)
    }

    /// Adds the two lexer-owned inputs consumed by token-front-end operations.
    pub(in crate::parser) fn token_operation_resources<'a>(
        &'a self,
        operation: &'static str,
        token_words: &'a wgpu::Buffer,
        lexer_token_count: &'a wgpu::Buffer,
    ) -> anyhow::Result<ResourceMap<'a>> {
        let mut resources = self.operation_resources(operation)?;
        resources.graph_buffer(self.materialized.graph(), "token_words", token_words)?;
        resources.graph_buffer(
            self.materialized.graph(),
            "lexer_token_count",
            lexer_token_count,
        )?;
        Ok(resources)
    }

    pub(in crate::parser) fn buffer<T>(
        &self,
        name: &str,
    ) -> anyhow::Result<crate::gpu::buffers::LaniusBuffer<T>> {
        self.materialized.buffer(name)
    }

    pub(in crate::parser) fn validate_reflected_runtime_bindings(
        &self,
        operation: &'static str,
        resources: &std::collections::HashMap<String, wgpu::BindingResource<'_>>,
        dispatch_args: Option<&crate::gpu::buffers::LaniusBuffer<u32>>,
    ) -> anyhow::Result<()> {
        self.materialized
            .validate_reflected_runtime_bindings(operation, resources, dispatch_args)
    }

    pub(in crate::parser) fn status_readback_operations(
        &self,
        ll1_status: &crate::gpu::buffers::LaniusBuffer<u32>,
        partial_parse_status: &crate::gpu::buffers::LaniusBuffer<u32>,
        token_feature_flags: &crate::gpu::buffers::LaniusBuffer<u32>,
        tree_depth_status: &crate::gpu::buffers::LaniusBuffer<u32>,
        readback: &crate::gpu::buffers::LaniusBuffer<u8>,
    ) -> anyhow::Result<ParserStatusReadbackOperations> {
        let copy = |name,
                    source_binding,
                    source: &crate::gpu::buffers::LaniusBuffer<u32>,
                    destination_offset,
                    size| {
            CopyBufferOperation::new(
                &self.materialized,
                name,
                source_binding,
                source,
                0,
                "status_readback",
                readback,
                destination_offset,
                size,
            )
        };
        Ok(ParserStatusReadbackOperations {
            full: [
                copy(
                    "parser.status.ll1.readback",
                    "ll1_status",
                    ll1_status,
                    0,
                    24,
                )?,
                copy(
                    "parser.status.token_features.readback",
                    "token_feature_flags",
                    token_feature_flags,
                    24,
                    4,
                )?,
                copy(
                    "parser.status.tree_depth.readback",
                    "tree_depth_status",
                    tree_depth_status,
                    28,
                    4,
                )?,
            ],
            partial: [
                copy(
                    "parser.status.partial_parse.readback",
                    "partial_parse_status",
                    partial_parse_status,
                    0,
                    24,
                )?,
                copy(
                    "parser.status.partial_token_features.readback",
                    "token_feature_flags",
                    token_feature_flags,
                    24,
                    4,
                )?,
            ],
        })
    }

    pub(in crate::parser) fn clear_operations(
        &self,
        buffers: &ParserBuffers,
    ) -> anyhow::Result<ParserClearOperations> {
        let clear = |name, binding, buffer| {
            ClearBufferOperation::entire(&self.materialized, name, binding, buffer)
        };
        let optional_clear = |name, binding, buffer| -> anyhow::Result<_> {
            self.materialized
                .graph()
                .pass_id(name)
                .map(|_| clear(name, binding, buffer))
                .transpose()
        };
        let raw_tree_bytes = u64::from(buffers.tree_capacity) * 4;
        let clear_tree_range = |name, binding, buffer| {
            ClearBufferOperation::range(
                &self.materialized,
                name,
                binding,
                buffer,
                0,
                raw_tree_bytes,
            )
        };
        let mut phase_clears = std::collections::HashMap::new();
        let mut phase_clear =
            |name: &'static str,
             resources: &[(&'static str, crate::gpu::buffers::TrackedBufferView<'_>)]|
             -> anyhow::Result<()> {
                if self.materialized.graph().pass_id(name).is_some() {
                    phase_clears.insert(
                        name,
                        ClearBuffersOperation::new(&self.materialized, name, resources)?,
                    );
                }
                Ok(())
            };
        phase_clear(
            STACK_EFFECT_CLEAR,
            &[
                ("bracket_valid", (&buffers.valid_out).into()),
                ("bracket_depths", (&buffers.depths_out).into()),
                ("bracket_block_sum", (&buffers.b_block_sum).into()),
                ("bracket_block_minpref", (&buffers.b_block_minpref).into()),
                ("bracket_block_row_min", (&buffers.b_block_row_min).into()),
                ("bracket_block_maxdepth", (&buffers.b_block_maxdepth).into()),
            ],
        )?;
        phase_clear(
            HIR_CANONICAL_IDENTITY_CLEAR,
            &[
                (
                    "hir_canonical_anchor_owner",
                    (&buffers.hir_canonical_anchor_owner).into(),
                ),
                ("hir_canonical_count", (&buffers.hir_canonical_count).into()),
                (
                    "hir_canonical_status",
                    (&buffers.hir_canonical_status).into(),
                ),
            ],
        )?;
        phase_clear(
            hir::CANONICAL_VARIANT_CLEAR,
            &[
                (
                    "hir_variant_table_count",
                    (&buffers.hir_variant_table_count).into(),
                ),
                (
                    "hir_variant_family_flag",
                    (&buffers.hir_variant_family_flag).into(),
                ),
                (
                    "hir_canonical_anchor_owner",
                    (&buffers.hir_canonical_anchor_owner).into(),
                ),
                (
                    "hir_variant_raw_to_row",
                    (&buffers.hir_variant_raw_to_row).into(),
                ),
            ],
        )?;
        phase_clear(
            hir::CANONICAL_VARIANT_PAYLOAD_CLEAR,
            &[
                (
                    "hir_variant_payload_table_count",
                    (&buffers.hir_variant_payload_table_count).into(),
                ),
                (
                    "hir_variant_payload_family_flag",
                    (&buffers.hir_variant_payload_family_flag).into(),
                ),
                (
                    "hir_canonical_anchor_owner",
                    (&buffers.hir_canonical_anchor_owner).into(),
                ),
            ],
        )?;
        phase_clear(
            hir::CANONICAL_CALL_ARGUMENT_CLEAR,
            &[(
                "hir_call_arg_table_count",
                (&buffers.hir_call_arg_table_count).into(),
            )],
        )?;
        phase_clear(
            hir::CANONICAL_ARRAY_ELEMENT_CLEAR,
            &[
                (
                    "hir_array_element_table_count",
                    (&buffers.hir_array_element_table_count).into(),
                ),
                (
                    "hir_array_element_family_flag",
                    (&buffers.hir_array_element_family_flag).into(),
                ),
                (
                    "hir_canonical_anchor_owner",
                    (&buffers.hir_canonical_anchor_owner).into(),
                ),
            ],
        )?;
        phase_clear(
            hir::CANONICAL_MATCH_OUTPUTS_CLEAR,
            &[
                (
                    "hir_match_arm_table_count",
                    (&buffers.hir_match_arm_table_count).into(),
                ),
                (
                    "hir_match_payload_table_count",
                    (&buffers.hir_match_payload_table_count).into(),
                ),
                (
                    "hir_match_pattern_payload_count",
                    (&buffers.hir_match_pattern_payload_count).into(),
                ),
            ],
        )?;
        phase_clear(
            hir::CANONICAL_MATCH_ARM_CLEAR,
            &[
                (
                    "hir_match_arm_family_flag",
                    (&buffers.hir_match_arm_family_flag).into(),
                ),
                (
                    "hir_canonical_anchor_owner",
                    (&buffers.hir_canonical_anchor_owner).into(),
                ),
                (
                    "hir_match_arm_raw_to_row",
                    (&buffers.hir_match_arm_raw_to_row).into(),
                ),
            ],
        )?;
        phase_clear(
            hir::CANONICAL_MATCH_PAYLOAD_CLEAR,
            &[
                (
                    "hir_match_payload_family_flag",
                    (&buffers.hir_match_payload_family_flag).into(),
                ),
                (
                    "hir_canonical_anchor_owner",
                    (&buffers.hir_canonical_anchor_owner).into(),
                ),
            ],
        )?;
        phase_clear(
            hir::CANONICAL_FIELD_CLEAR,
            &[
                (
                    "hir_field_table_count",
                    (&buffers.hir_field_table_count).into(),
                ),
                (
                    "hir_field_family_flag",
                    (&buffers.hir_field_family_flag).into(),
                ),
                (
                    "hir_canonical_anchor_owner",
                    (&buffers.hir_canonical_anchor_owner).into(),
                ),
            ],
        )?;
        phase_clear(
            hir::CANONICAL_PARAMETER_CLEAR,
            &[(
                "hir_param_table_count",
                (&buffers.hir_param_table_count).into(),
            )],
        )?;
        phase_clear(
            hir::CANONICAL_TYPE_ARGUMENT_CLEAR,
            &[(
                "hir_type_arg_table_count",
                (&buffers.hir_type_arg_table_count).into(),
            )],
        )?;
        phase_clear(
            hir::CANONICAL_EXPR_FOREST_CLEAR,
            &[
                (
                    "hir_canonical_expr_parent_encoded",
                    (&buffers.hir_canonical_expr_parent_encoded).into(),
                ),
                (
                    "hir_canonical_expr_forest_status",
                    (&buffers.hir_canonical_expr_forest_status).into(),
                ),
            ],
        )?;
        phase_clear(
            hir::CANONICAL_GENERIC_PARAMETER_CLEAR,
            &[
                (
                    "hir_generic_param_table_count",
                    (&buffers.hir_generic_param_table_count).into(),
                ),
                (
                    "hir_canonical_anchor_owner",
                    (&buffers.hir_canonical_anchor_owner).into(),
                ),
            ],
        )?;
        phase_clear(
            hir::CANONICAL_PATH_SEGMENT_CLEAR,
            &[(
                "hir_path_segment_table_count",
                (&buffers.hir_path_segment_table_count).into(),
            )],
        )?;
        phase_clear(
            hir::CANONICAL_PATH_CLEAR,
            &[(
                "hir_path_table_count",
                (&buffers.hir_path_table_count).into(),
            )],
        )?;
        phase_clear(
            hir::CANONICAL_METHOD_CLEAR,
            &[(
                "hir_method_table_count",
                (&buffers.hir_method_table_count).into(),
            )],
        )?;
        phase_clear(
            hir::CANONICAL_PREDICATE_CLEAR,
            &[(
                "hir_predicate_table_count",
                (&buffers.hir_predicate_table_count).into(),
            )],
        )?;
        Ok(ParserClearOperations {
            token_file_id: clear(
                TOKEN_FILE_ID_CLEAR,
                "token_file_id",
                &buffers.default_token_file_id,
            )?,
            token_feature_flags: optional_clear(
                token_frontend::FEATURE_FLAGS_CLEAR,
                "token_feature_flags",
                &buffers.token_feature_flags,
            )?,
            token_impl_header_kind: optional_clear(
                token_frontend::IMPL_HEADER_KIND_CLEAR,
                "token_impl_header_kind",
                &buffers.token_impl_header_kind,
            )?,
            token_braced_rhs_statement_kind: optional_clear(
                token_frontend::BRACED_RHS_STATEMENT_KIND_CLEAR,
                "braced_rhs_statement_kind",
                &buffers.token_braced_rhs_statement_kind,
            )?,
            tree_depth_status: clear(
                TREE_DEPTH_STATUS_CLEAR,
                "tree_depth_status",
                &buffers.tree_depth_status,
            )?,
            hir_expr_name_role: clear(
                HIR_EXPR_NAME_ROLE_CLEAR,
                "hir_expr_name_role",
                &buffers.hir_expr_name_role,
            )?,
            source_file_token_end: clear(
                SOURCE_FILE_TOKEN_END_CLEAR,
                "source_file_token_end",
                &buffers.source_file_token_end,
            )?,
            hir_type_path_leaf_link_b: ClearBufferOperation::range(
                &self.materialized,
                HIR_TYPE_PATH_LEAF_LINK_B_CLEAR,
                "hir_type_path_leaf_link_b",
                &buffers.hir_type_path_leaf_link_b,
                0,
                u64::from(buffers.tree_capacity) * 4,
            )?,
            hir_type_arg_owner_b: clear_tree_range(
                hir::TYPE_ARG_OWNER_B_CLEAR,
                "hir_type_arg_owner_b",
                &buffers.hir_type_arg_owner_b,
            )?,
            hir_type_arg_link_b: clear_tree_range(
                hir::TYPE_ARG_LINK_B_CLEAR,
                "hir_type_arg_link_b",
                &buffers.hir_type_arg_link_b,
            )?,
            hir_type_arg_rank_b: clear_tree_range(
                hir::TYPE_ARG_RANK_B_CLEAR,
                "hir_type_arg_rank_b",
                &buffers.hir_type_arg_rank_b,
            )?,
            hir_item_kind: clear(
                hir::ITEM_KIND_CLEAR,
                "hir_item_kind",
                &buffers.hir_item_kind,
            )?,
            hir_path_root_owner: clear(
                hir::PATH_ROOT_OWNER_CLEAR,
                "hir_path_root_owner",
                &buffers.hir_path_root_owner,
            )?,
            hir_path_segment_count: clear(
                hir::PATH_SEGMENT_COUNT_CLEAR,
                "hir_path_segment_count",
                &buffers.hir_path_segment_count,
            )?,
            hir_string_decoded_len: clear(
                hir::STRING_DECODED_LEN_CLEAR,
                "hir_string_decoded_len",
                &buffers.hir_string_decoded_len,
            )?,
            hir_string_data_words: clear(
                hir::STRING_DATA_WORDS_CLEAR,
                "hir_string_data_words",
                &buffers.hir_string_data_words,
            )?,
            hir_call_arg_count: clear(
                hir::CALL_ARG_COUNT_CLEAR,
                "hir_call_arg_count",
                &buffers.hir_call_arg_count,
            )?,
            phase_clears,
        })
    }

    pub(in crate::parser) fn token_file_id_copy_operation(
        &self,
        source: &wgpu::Buffer,
        destination: &crate::gpu::buffers::LaniusBuffer<u32>,
    ) -> anyhow::Result<CopyBufferOperation> {
        let size = source.size().min(destination.byte_size as u64);
        CopyBufferOperation::new_external_input(
            &self.materialized,
            TOKEN_FILE_ID_COPY,
            "lexer_token_file_id",
            source,
            0,
            "token_file_id",
            destination,
            0,
            size,
        )
    }

    pub(in crate::parser) fn job_storage_reset_operation(
        &self,
        buffers: &[crate::gpu::buffers::ResettableBuffer],
    ) -> anyhow::Result<ResetGraphAllocationsOperation> {
        ResetGraphAllocationsOperation::new_tracked(&self.materialized, JOB_STORAGE_RESET, buffers)
    }

    #[allow(clippy::too_many_arguments)]
    pub(in crate::parser) fn dispatch_operations(
        &self,
        device: &wgpu::Device,
        passes: &ParserPasses,
        params_llp: &crate::gpu::buffers::LaniusBuffer<crate::parser::passes::llp_pairs::LLPParams>,
        token_count: &crate::gpu::buffers::LaniusBuffer<u32>,
        active_pair_thread_dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        tree_prefix_params: &crate::gpu::buffers::LaniusBuffer<
            crate::parser::passes::tree::prefix::local::Params,
        >,
        ll1_status: &crate::gpu::buffers::LaniusBuffer<u32>,
        token_feature_flags: &crate::gpu::buffers::LaniusBuffer<u32>,
        tree_enum_dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        tree_match_dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        tree_struct_dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
    ) -> anyhow::Result<ParserDispatchOperations> {
        let mut active = ResourceMap::new();
        active.buffer("gParams", params_llp);
        active.buffer("token_count", token_count);
        active.buffer(
            "active_pair_thread_dispatch_args",
            active_pair_thread_dispatch_args,
        );
        let mut tree = ResourceMap::new();
        tree.buffer("gTree", tree_prefix_params);
        tree.buffer("ll1_status", ll1_status);
        tree.buffer("token_feature_flags", token_feature_flags);
        tree.buffer("tree_enum_dispatch_args", tree_enum_dispatch_args);
        tree.buffer("tree_match_dispatch_args", tree_match_dispatch_args);
        tree.buffer("tree_struct_dispatch_args", tree_struct_dispatch_args);

        Ok(ParserDispatchOperations {
            active_pair: ComputeOperation::direct(
                device,
                &self.materialized,
                &active,
                ACTIVE_PAIR_DISPATCH,
                &passes.active_pair_dispatch_args,
                1,
            )?,
            tree_features: ComputeOperation::direct(
                device,
                &self.materialized,
                &tree,
                TREE_FEATURE_DISPATCH,
                &passes.tree_feature_dispatch_args,
                1,
            )?,
        })
    }

    pub(in crate::parser) fn direct_operation(
        &self,
        device: &wgpu::Device,
        resources: &ResourceMap<'_>,
        name: &'static str,
        pass: &PassData,
        capacity: u32,
    ) -> anyhow::Result<ComputeOperation> {
        ComputeOperation::direct(device, &self.materialized, resources, name, pass, capacity)
    }
}

fn storage(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    domain: ResourceDomain,
    class: ResourceClass,
    bytes: u64,
) -> Result<ResourceId, String> {
    graph.add_resource(ResourceDesc {
        name,
        domain,
        class,
        bytes: bytes.max(4),
        usage: WorkspaceUsageClass::Storage,
    })
}

pub(super) fn external(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    domain: ResourceDomain,
    bytes: u64,
) -> Result<ResourceId, String> {
    storage(graph, name, domain, ResourceClass::External, bytes)
}

pub(super) fn input(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    domain: ResourceDomain,
    bytes: u64,
) -> Result<ResourceId, String> {
    storage(graph, name, domain, ResourceClass::Input, bytes)
}

pub(super) fn workspace(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    domain: ResourceDomain,
    bytes: u64,
) -> Result<ResourceId, String> {
    storage(graph, name, domain, ResourceClass::Workspace, bytes)
}

pub(super) fn output(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    domain: ResourceDomain,
    bytes: u64,
) -> Result<ResourceId, String> {
    let resource = storage(graph, name, domain, ResourceClass::Output, bytes)?;
    // Parser graph arenas are cleared at the reusable-job boundary. Compact
    // optional families therefore legitimately publish zero rows when their
    // feature-specific producer is absent from this capacity-specialized
    // schedule.
    graph.mark_zero_initialized(resource)?;
    Ok(resource)
}

/// Parser relations whose complete producer/consumer lifetime is represented
/// by this graph and which therefore use lifetime-colored workspace.
fn graph_owned_workspace(name: &str) -> bool {
    matches!(
        name,
        "out_sc"
            | "bracket_exscan_inblock"
            | "bracket_depths"
            | "bracket_layer"
            | "match_for_index"
            | "bracket_block_sum"
            | "token_file_id"
            | "bracket_block_minpref"
            | "bracket_block_row_min"
            | "bracket_block_maxdepth"
            | "bracket_block_prefix"
            | "bracket_prefix_sum"
            | "bracket_prefix_min"
            | "bracket_hierarchy_sum"
            | "bracket_hierarchy_min"
            | "bracket_min_tree"
            | "bracket_valid"
            | "sc_offsets"
            | "emit_offsets"
            | "pack_sc_prefix_a"
            | "pack_sc_prefix_b"
            | "pack_emit_prefix_a"
            | "pack_emit_prefix_b"
            | "tree_block_sum"
            | "tree_prefix_inblock"
            | "tree_block_prefix_a"
            | "tree_block_prefix_b"
            | "tree_block_prefix"
            | "tree_prefix"
            | "tree_prefix_block_max"
            | "tree_prefix_block_max_tree"
            | "tree_depth_status"
            | "tree_depth_block_max"
            | "tree_depth"
            | "prev_sibling"
            | "node_kind"
            | "parent"
            | "first_child"
            | "next_sibling"
            | "subtree_end"
            | "hir_kind"
            | "hir_semantic_flag"
            | "hir_semantic_local_prefix"
            | "hir_semantic_block_sum"
            | "hir_semantic_block_prefix_a"
            | "hir_semantic_block_prefix_b"
            | "hir_node_dense_id"
            | "hir_semantic_dense_node"
            | "hir_semantic_prefix_before_node"
            | "hir_semantic_count"
            | "hir_semantic_subtree_end"
            | "hir_semantic_parent"
            | "hir_semantic_first_child"
            | "hir_semantic_next_sibling"
            | "hir_semantic_depth"
            | "hir_semantic_child_index"
            | "hir_token_pos"
            | "hir_token_end"
            | "hir_token_file_id"
            | "source_file_token_end"
            | "out_headers"
            | "partial_parse_status"
            | "out_emit"
            | "out_emit_pos"
            | "hir_type_form"
            | "hir_type_value_node"
            | "hir_type_len_token"
            | "hir_type_len_value"
            | "hir_type_path_leaf_node"
            | "hir_bound_path_owner_by_leaf"
            | "hir_type_path_leaf_link_a"
            | "hir_type_path_leaf_link_b"
            | "hir_type_path_leaf_value_a"
            | "hir_type_path_leaf_value_b"
            | "hir_type_arg_start"
            | "hir_type_arg_count"
            | "hir_type_arg_next"
            | "hir_item_name_token"
            | "hir_item_namespace"
            | "hir_item_visibility"
            | "hir_item_path_start"
            | "hir_item_path_end"
            | "hir_item_path_node"
            | "hir_item_import_target_kind"
            | "hir_param_type_node"
            | "hir_type_alias_target_node"
            | "hir_fn_return_type_node"
            | "hir_method_owner_node"
            | "hir_method_impl_node"
            | "hir_method_name_token"
            | "hir_method_first_param_token"
            | "hir_method_receiver_mode"
            | "hir_method_visibility"
            | "hir_method_signature_flags"
            | "hir_method_impl_receiver_type_node"
            | "hir_canonical_prefix_before_raw"
            | "hir_canonical_alias_to_dense"
            | "hir_canonical_raw_to_dense"
            | "hir_stmt_scope_end"
            | "hir_nearest_stmt_node"
            | "hir_nearest_block_node"
            | "hir_nearest_enclosing_control_node"
            | "hir_nearest_loop_node"
            | "hir_nearest_fn_node"
            | "hir_nearest_array_element_node"
            | "hir_call_context_stmt_node"
            | "hir_array_lit_context_stmt_node"
            | "hir_struct_lit_context_stmt_node"
            | "hir_expr_record"
            | "hir_expr_name_role"
            | "hir_expr_result_root_node"
            | "hir_param_record"
            | "hir_member_receiver_node"
            | "hir_member_receiver_token"
            | "hir_member_name_token"
            | "hir_call_callee_node"
            | "hir_call_callee_path_node"
            | "hir_call_parent_by_callee"
            | "hir_call_arg_start"
            | "hir_call_arg_end"
            | "hir_call_arg_count"
            | "hir_call_arg_parent_call"
            | "hir_call_arg_ordinal"
            | "hir_stmt_record"
            | "hir_call_arg_ranges"
            | "hir_match_arm_ranges"
            | "hir_match_pattern_to_arm"
            | "hir_canonical_status"
            | "hir_canonical_dense_to_raw"
    )
}

/// Raw parser relations that become observable phase outputs when detailed
/// parser diagnostics are requested. Production compilation consumes these
/// rows entirely inside the parser graph, so they remain colorable workspace
/// there. The standalone/debug parser copies them after graph execution and
/// must therefore retain their physical contents through graph completion.
fn retained_debug_parser_output(name: &str) -> bool {
    matches!(
        name,
        "out_sc"
            | "bracket_depths"
            | "bracket_valid"
            | "match_for_index"
            | "node_kind"
            | "token_file_id"
            | "parent"
            | "first_child"
            | "next_sibling"
            | "prev_sibling"
            | "tree_depth"
            | "subtree_end"
            | "hir_kind"
            | "hir_semantic_dense_node"
            | "hir_semantic_prefix_before_node"
            | "hir_semantic_subtree_end"
            | "hir_semantic_parent"
            | "hir_semantic_first_child"
            | "hir_semantic_next_sibling"
            | "hir_semantic_depth"
            | "hir_semantic_child_index"
            | "hir_token_pos"
            | "hir_token_end"
            | "hir_token_file_id"
            | "out_headers"
            | "out_emit"
            | "hir_type_form"
            | "hir_type_value_node"
            | "hir_type_len_token"
            | "hir_type_len_value"
            | "hir_type_path_leaf_node"
            | "hir_bound_path_owner_by_leaf"
            | "hir_type_path_leaf_link_a"
            | "hir_type_path_leaf_link_b"
            | "hir_type_path_leaf_value_a"
            | "hir_type_path_leaf_value_b"
            | "hir_type_arg_start"
            | "hir_type_arg_count"
            | "hir_type_arg_next"
            | "hir_item_name_token"
            | "hir_item_namespace"
            | "hir_item_visibility"
            | "hir_item_path_start"
            | "hir_item_path_end"
            | "hir_item_path_node"
            | "hir_item_import_target_kind"
            | "hir_param_type_node"
            | "hir_type_alias_target_node"
            | "hir_fn_return_type_node"
            | "hir_method_owner_node"
            | "hir_method_impl_node"
            | "hir_method_name_token"
            | "hir_method_first_param_token"
            | "hir_method_receiver_mode"
            | "hir_method_visibility"
            | "hir_method_signature_flags"
            | "hir_method_impl_receiver_type_node"
            | "hir_canonical_prefix_before_raw"
            | "hir_canonical_alias_to_dense"
            | "hir_canonical_raw_to_dense"
            | "hir_stmt_scope_end"
            | "hir_nearest_stmt_node"
            | "hir_nearest_block_node"
            | "hir_nearest_enclosing_control_node"
            | "hir_nearest_loop_node"
            | "hir_nearest_fn_node"
            | "hir_nearest_array_element_node"
            | "hir_call_context_stmt_node"
            | "hir_array_lit_context_stmt_node"
            | "hir_struct_lit_context_stmt_node"
            | "hir_expr_record"
            | "hir_expr_name_role"
            | "hir_expr_result_root_node"
            | "hir_param_record"
            | "hir_member_receiver_node"
            | "hir_member_receiver_token"
            | "hir_member_name_token"
            | "hir_call_callee_node"
            | "hir_call_callee_path_node"
            | "hir_call_parent_by_callee"
            | "hir_call_arg_start"
            | "hir_call_arg_end"
            | "hir_call_arg_count"
            | "hir_call_arg_parent_call"
            | "hir_call_arg_ordinal"
            | "hir_stmt_record"
            | "hir_call_arg_ranges"
            | "hir_match_arm_ranges"
            | "hir_match_pattern_to_arm"
            | "hir_canonical_status"
            | "hir_canonical_dense_to_raw"
    )
}

fn parser_resource_class(capacity: ParserGraphCapacity, name: &str) -> ResourceClass {
    if matches!(name, "action_table" | "tables_blob" | "prod_arity") {
        ResourceClass::Input
    } else if name == "ll1_status" {
        ResourceClass::Output
    } else if matches!(name, "token_kinds" | "token_count" | "token_feature_flags") {
        if capacity.preclassified_token_kinds {
            ResourceClass::Input
        } else {
            ResourceClass::Output
        }
    } else if retained_hir_output(name)
        || (capacity.retain_debug_hir_buffers && retained_debug_parser_output(name))
    {
        ResourceClass::Output
    } else if graph_owned_workspace(name) {
        ResourceClass::Workspace
    } else {
        ResourceClass::External
    }
}

pub(super) fn retained_hir_output(name: &str) -> bool {
    matches!(
        name,
        "hir_canonical_count"
            | "hir_canonical_anchor_owner"
            | "hir_canonical_scope_end"
            | "hir_canonical_nearest_loop"
            | "hir_canonical_nearest_block"
            | "hir_canonical_nearest_control"
            | "hir_canonical_nearest_fn"
            | "hir_canonical_fn_return_type"
            | "hir_canonical_type_root_owner"
            | "hir_canonical_type_alias_target"
            | "hir_canonical_const_type"
            | "hir_canonical_const_value"
            | "hir_canonical_expr_parent"
            | "hir_canonical_expr_root"
            | "hir_call_arg_table_count"
            | "hir_call_args"
            | "hir_param_table_count"
            | "hir_param_rows"
            | "hir_param_ranges"
            | "hir_type_arg_table_count"
            | "hir_type_arg_rows"
            | "hir_type_arg_ranges"
            | "hir_generic_param_table_count"
            | "hir_generic_param_rows"
            | "hir_generic_param_ranges"
            | "hir_path_table_count"
            | "hir_path_rows"
            | "hir_path_segment_table_count"
            | "hir_path_segment_rows"
            | "hir_field_table_count"
            | "hir_field_rows"
            | "hir_variant_table_count"
            | "hir_variant_rows"
            | "hir_variant_compact_payload_start"
            | "hir_variant_compact_payload_count"
            | "hir_variant_payload_table_count"
            | "hir_variant_payload_rows"
            | "hir_match_arm_table_count"
            | "hir_match_arm_rows"
            | "hir_match_compact_payload_start"
            | "hir_match_compact_payload_count"
            | "hir_match_pattern_payload_count"
            | "hir_match_payload_table_count"
            | "hir_match_payload_rows"
            | "hir_array_compact_element_start"
            | "hir_array_compact_element_count"
            | "hir_array_element_table_count"
            | "hir_array_element_rows"
            | "hir_string_count"
            | "hir_canonical_string_rows"
            | "hir_string_data_words"
            | "hir_string_pool_len"
            | "hir_method_table_count"
            | "hir_method_core_rows"
            | "hir_method_signature_rows"
            | "hir_predicate_table_count"
            | "hir_predicate_rows"
    )
}

pub(super) fn workspace_indirect(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    bytes: u64,
) -> Result<ResourceId, String> {
    graph.add_resource(ResourceDesc {
        name,
        domain: ResourceDomain::DispatchArguments,
        class: ResourceClass::Workspace,
        bytes,
        usage: WorkspaceUsageClass::StorageIndirect,
    })
}

fn binding(
    graph: &CompilerGraphBuilder,
    binding: &'static str,
    resource: &'static str,
    mode: Option<AccessMode>,
) -> Result<ReflectedResourceBinding, String> {
    Ok(ReflectedResourceBinding {
        binding,
        resource: graph
            .resource_id(resource)
            .ok_or_else(|| format!("parser graph has no resource `{resource}`"))?,
        mode,
    })
}

pub(super) fn reflected(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    phase: CompilerPhase,
    domain: ResourceDomain,
    data: &PassData,
    aliases: &[(&'static str, &'static str, Option<AccessMode>)],
) -> Result<(), String> {
    let aliases = aliases
        .iter()
        .map(|&(binding_name, resource, mode)| binding(graph, binding_name, resource, mode))
        .collect::<Result<Vec<_>, _>>()?;
    graph.add_reflected_compute_pass_by_name(name, phase, domain, &data.reflection, &aliases)?;
    Ok(())
}

pub(super) fn static_pass<P>(
    graph: &mut CompilerGraphBuilder,
    pass: &P,
    phase: CompilerPhase,
    domain: ResourceDomain,
    aliases: &[(&'static str, &'static str, Option<AccessMode>)],
) -> Result<(), String>
where
    P: Pass<ParserBuffers, DebugOutput>,
{
    reflected(graph, P::NAME, phase, domain, pass.data(), aliases)
}

fn indirect(
    graph: &mut CompilerGraphBuilder,
    pass: &'static str,
    resource: &'static str,
) -> Result<(), String> {
    graph.add_indirect_dispatch(pass, resource)
}

pub(super) fn clear(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    phase: CompilerPhase,
    resources: &[(&'static str, &'static str)],
) -> Result<(), String> {
    let bindings = resources
        .iter()
        .map(|&(binding, resource)| {
            graph
                .resource_id(resource)
                .map(|resource| (binding, resource))
                .ok_or_else(|| format!("parser clear {name} names unknown resource `{resource}`"))
        })
        .collect::<Result<Vec<_>, _>>()?;
    graph.add_buffers_clear_pass(name, phase, &bindings)?;
    Ok(())
}

fn build_graph(
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
) -> Result<crate::gpu::compiler_graph::CompilerGraph, String> {
    let mut graph = CompilerGraphBuilder::new();
    let token_rows = u64::from(capacity.n_tokens.max(1));
    let input_token_rows = u64::from(capacity.token_capacity.max(1));
    let pair_rows = u64::from(capacity.pair_capacity.max(1));
    let stack_rows = u64::from(capacity.total_sc.max(1));
    let tree_rows = u64::from(capacity.tree_capacity.max(1));
    let bracket_blocks = u64::from(capacity.bracket_blocks.max(1));
    let tree_blocks = u64::from(capacity.tree_node_blocks.max(1));
    let prefix_blocks = u64::from(capacity.tree_prefix_blocks.max(1));
    let bracket_leaf_base = capacity.bracket_blocks.max(1).next_power_of_two();
    let prefix_leaf_base = capacity.tree_prefix_blocks.max(1).next_power_of_two();

    for (name, domain, bytes) in [
        ("token_kinds", ResourceDomain::Tokens, token_rows * 4),
        ("token_count", ResourceDomain::Tokens, 4),
        ("token_file_id", ResourceDomain::Tokens, token_rows * 4),
        (
            "action_table",
            ResourceDomain::Bytes,
            capacity.action_table_bytes,
        ),
        ("out_headers", ResourceDomain::Tokens, pair_rows * 16),
        ("sc_offsets", ResourceDomain::Tokens, pair_rows * 4),
        ("emit_offsets", ResourceDomain::Tokens, pair_rows * 4),
        ("partial_parse_status", ResourceDomain::Tokens, 24),
        ("pack_sc_prefix_a", ResourceDomain::Tokens, pair_rows * 4),
        ("pack_sc_prefix_b", ResourceDomain::Tokens, pair_rows * 4),
        ("pack_emit_prefix_a", ResourceDomain::Tokens, pair_rows * 4),
        ("pack_emit_prefix_b", ResourceDomain::Tokens, pair_rows * 4),
        (
            "tables_blob",
            ResourceDomain::Bytes,
            u64::from(capacity.table_blob_words.max(1)) * 4,
        ),
        ("out_sc", ResourceDomain::RawNodes, stack_rows * 4),
        ("out_emit", ResourceDomain::RawNodes, tree_rows * 4),
        ("out_emit_pos", ResourceDomain::RawNodes, tree_rows * 4),
        (
            "bracket_exscan_inblock",
            ResourceDomain::RawNodes,
            stack_rows * 4,
        ),
        (
            "bracket_block_sum",
            ResourceDomain::RawNodes,
            bracket_blocks * 4,
        ),
        (
            "bracket_block_minpref",
            ResourceDomain::RawNodes,
            bracket_blocks * 4,
        ),
        (
            "bracket_block_row_min",
            ResourceDomain::RawNodes,
            bracket_blocks * 4,
        ),
        (
            "bracket_block_maxdepth",
            ResourceDomain::RawNodes,
            bracket_blocks * 4,
        ),
        (
            "bracket_block_prefix",
            ResourceDomain::RawNodes,
            bracket_blocks * 4,
        ),
        (
            "bracket_prefix_sum",
            ResourceDomain::RawNodes,
            bracket_blocks * 4,
        ),
        (
            "bracket_prefix_min",
            ResourceDomain::RawNodes,
            bracket_blocks * 4,
        ),
        (
            "bracket_hierarchy_sum",
            ResourceDomain::RawNodes,
            bracket_blocks * 4,
        ),
        (
            "bracket_hierarchy_min",
            ResourceDomain::RawNodes,
            bracket_blocks * 4,
        ),
        (
            "bracket_min_tree",
            ResourceDomain::RawNodes,
            u64::from(bracket_leaf_base) * 8,
        ),
        ("bracket_depths", ResourceDomain::RawNodes, 12),
        ("bracket_valid", ResourceDomain::RawNodes, 4),
        ("bracket_layer", ResourceDomain::RawNodes, stack_rows * 4),
        (
            "match_for_index",
            ResourceDomain::RawNodes,
            if capacity.emit_stack_matches {
                stack_rows
            } else {
                tree_rows
            } * 4,
        ),
        ("ll1_status", ResourceDomain::Tokens, 24),
        ("token_feature_flags", ResourceDomain::Tokens, 4),
        ("status_readback", ResourceDomain::Tokens, 32),
        ("hir_count_readback", ResourceDomain::HirNodes, 120),
        (
            "tree_prefix_inblock",
            ResourceDomain::RawNodes,
            tree_rows * 4,
        ),
        ("tree_block_sum", ResourceDomain::RawNodes, tree_blocks * 4),
        (
            "tree_block_prefix_a",
            ResourceDomain::RawNodes,
            tree_blocks * 4,
        ),
        (
            "tree_block_prefix_b",
            ResourceDomain::RawNodes,
            tree_blocks * 4,
        ),
        (
            "tree_block_prefix",
            ResourceDomain::RawNodes,
            tree_blocks * 4,
        ),
        ("tree_prefix", ResourceDomain::RawNodes, (tree_rows + 1) * 4),
        (
            "tree_prefix_block_max",
            ResourceDomain::RawNodes,
            prefix_blocks * 4,
        ),
        (
            "tree_prefix_block_max_tree",
            ResourceDomain::RawNodes,
            u64::from(prefix_leaf_base) * 8,
        ),
        (
            "prod_arity",
            ResourceDomain::RawNodes,
            u64::from(capacity.production_count.max(1)) * 4,
        ),
        ("node_kind", ResourceDomain::RawNodes, tree_rows * 4),
        ("parent", ResourceDomain::RawNodes, tree_rows * 4),
        ("first_child", ResourceDomain::RawNodes, tree_rows * 4),
        ("next_sibling", ResourceDomain::RawNodes, tree_rows * 4),
        ("prev_sibling", ResourceDomain::RawNodes, tree_rows * 4),
        ("subtree_end", ResourceDomain::RawNodes, tree_rows * 4),
        ("tree_depth", ResourceDomain::RawNodes, tree_rows * 4),
        ("tree_depth_status", ResourceDomain::RawNodes, 4),
        (
            "tree_depth_block_max",
            ResourceDomain::RawNodes,
            tree_blocks * 4,
        ),
        ("hir_kind", ResourceDomain::RawNodes, tree_rows * 4),
        ("hir_token_pos", ResourceDomain::RawNodes, tree_rows * 4),
        (
            "hir_token_file_id",
            ResourceDomain::RawNodes,
            if capacity.retain_debug_hir_buffers {
                tree_rows * 4
            } else {
                4
            },
        ),
        ("hir_expr_record", ResourceDomain::RawNodes, tree_rows * 16),
        (
            "hir_expr_name_role",
            ResourceDomain::RawNodes,
            if capacity.retain_debug_hir_buffers {
                tree_rows * 4
            } else {
                input_token_rows * 4
            },
        ),
        (
            "hir_expr_result_root_node",
            ResourceDomain::RawNodes,
            tree_rows * 4,
        ),
        ("hir_semantic_flag", ResourceDomain::RawNodes, tree_rows * 4),
        (
            "hir_semantic_local_prefix",
            ResourceDomain::RawNodes,
            tree_rows * 4,
        ),
        (
            "hir_semantic_block_sum",
            ResourceDomain::RawNodes,
            tree_blocks * 4,
        ),
        (
            "hir_semantic_block_prefix_a",
            ResourceDomain::RawNodes,
            tree_blocks * 4,
        ),
        (
            "hir_semantic_block_prefix_b",
            ResourceDomain::RawNodes,
            tree_blocks * 4,
        ),
        ("hir_node_dense_id", ResourceDomain::RawNodes, tree_rows * 4),
        (
            "hir_semantic_prefix_before_node",
            ResourceDomain::RawNodes,
            tree_rows * 4,
        ),
        (
            "hir_semantic_dense_node",
            ResourceDomain::HirNodes,
            tree_rows * 4,
        ),
        ("hir_semantic_count", ResourceDomain::HirNodes, 4),
        (
            "hir_semantic_subtree_end",
            ResourceDomain::HirNodes,
            tree_rows * 4,
        ),
        (
            "hir_semantic_parent",
            ResourceDomain::HirNodes,
            tree_rows * 4,
        ),
        (
            "hir_semantic_first_child",
            ResourceDomain::HirNodes,
            tree_rows * 4,
        ),
        (
            "hir_semantic_next_sibling",
            ResourceDomain::HirNodes,
            tree_rows * 4,
        ),
        (
            "hir_semantic_depth",
            ResourceDomain::HirNodes,
            tree_rows * 4,
        ),
        (
            "hir_semantic_child_index",
            ResourceDomain::HirNodes,
            tree_rows * 4,
        ),
    ] {
        let resource = storage(
            &mut graph,
            name,
            domain,
            parser_resource_class(capacity, name),
            bytes,
        )?;
        if retained_hir_output(name) {
            graph.mark_zero_initialized(resource)?;
        }
    }
    // For a one-pair job the totals reduction has zero ping-pong rounds.
    // `pack_totals_status` still reflects both alternatives although its
    // `read_from_a` uniform selects A. The physical job reset establishes the
    // unused B side, making the reflected conditional read valid at every
    // capacity without inventing a reduction dispatch.
    for name in ["pack_sc_prefix_b", "pack_emit_prefix_b"] {
        graph.mark_zero_initialized(
            graph
                .resource_id(name)
                .expect("pack totals secondary workspace resource"),
        )?;
    }
    input(
        &mut graph,
        "lexer_token_file_id",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    for name in [
        "hir_item_name_token",
        "hir_item_namespace",
        "hir_item_visibility",
        "hir_item_path_start",
        "hir_item_path_end",
        "hir_item_path_node",
        "hir_item_import_target_kind",
        "hir_param_type_node",
        "hir_type_alias_target_node",
        "hir_fn_return_type_node",
        "hir_method_owner_node",
        "hir_method_impl_node",
        "hir_method_name_token",
        "hir_method_first_param_token",
        "hir_method_receiver_mode",
        "hir_method_visibility",
        "hir_method_signature_flags",
        "hir_method_impl_receiver_type_node",
        "hir_stmt_scope_end",
        "hir_nearest_stmt_node",
        "hir_nearest_block_node",
        "hir_nearest_enclosing_control_node",
        "hir_nearest_loop_node",
        "hir_nearest_fn_node",
        "hir_nearest_array_element_node",
        "hir_call_context_stmt_node",
        "hir_array_lit_context_stmt_node",
        "hir_struct_lit_context_stmt_node",
        "hir_member_receiver_node",
        "hir_member_receiver_token",
        "hir_member_name_token",
        "hir_call_callee_node",
        "hir_call_callee_path_node",
        "hir_call_parent_by_callee",
        "hir_call_arg_start",
        "hir_call_arg_end",
        "hir_call_arg_count",
        "hir_call_arg_parent_call",
        "hir_call_arg_ordinal",
    ] {
        let bytes = if matches!(
            name,
            "hir_stmt_scope_end"
                | "hir_nearest_stmt_node"
                | "hir_nearest_block_node"
                | "hir_nearest_enclosing_control_node"
                | "hir_nearest_loop_node"
                | "hir_nearest_fn_node"
                | "hir_nearest_array_element_node"
                | "hir_call_context_stmt_node"
                | "hir_array_lit_context_stmt_node"
                | "hir_struct_lit_context_stmt_node"
        ) {
            if capacity.retain_debug_hir_buffers {
                tree_rows * 4
            } else if name == "hir_stmt_scope_end" {
                input_token_rows * 4
            } else {
                4
            }
        } else if matches!(
            name,
            "hir_member_receiver_node" | "hir_member_receiver_token" | "hir_member_name_token"
        ) {
            if capacity.retain_debug_hir_buffers
                || capacity.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_MEMBERS
                    != 0
            {
                tree_rows * 4
            } else {
                4
            }
        } else if matches!(
            name,
            "hir_call_callee_node"
                | "hir_call_callee_path_node"
                | "hir_call_parent_by_callee"
                | "hir_call_arg_start"
        ) {
            if capacity.retain_debug_hir_buffers {
                tree_rows * 4
            } else if name == "hir_call_callee_node" {
                input_token_rows * 4
            } else {
                4
            }
        } else if matches!(
            name,
            "hir_call_arg_end"
                | "hir_call_arg_count"
                | "hir_call_arg_parent_call"
                | "hir_call_arg_ordinal"
        ) {
            tree_rows * 4
        } else if matches!(
            name,
            "hir_method_owner_node"
                | "hir_method_impl_node"
                | "hir_method_name_token"
                | "hir_method_first_param_token"
                | "hir_method_receiver_mode"
                | "hir_method_visibility"
                | "hir_method_signature_flags"
                | "hir_method_impl_receiver_type_node"
        ) {
            let predicates_enabled = capacity.parser_feature_flags
                & crate::lexer::features::PARSER_FEATURE_PREDICATES
                != 0;
            if predicates_enabled || capacity.retain_debug_hir_buffers {
                tree_rows * 4
            } else {
                4
            }
        } else if capacity.retain_debug_hir_buffers
            && matches!(
                name,
                "hir_type_alias_target_node" | "hir_fn_return_type_node"
            )
        {
            tree_rows * 4
        } else {
            input_token_rows * 4
        };
        storage(
            &mut graph,
            name,
            ResourceDomain::HirNodes,
            parser_resource_class(capacity, name),
            bytes,
        )?;
    }
    workspace(
        &mut graph,
        "hir_expr_result_root_scratch_node",
        ResourceDomain::HirNodes,
        tree_rows * 4,
    )?;
    for (name, bytes) in [
        ("source_file_token_end", input_token_rows * 4),
        ("hir_token_end", tree_rows * 4),
        ("hir_param_record", input_token_rows * 16),
        ("hir_stmt_record", tree_rows * 16),
        ("hir_type_form", tree_rows * 4),
        ("hir_type_value_node", tree_rows * 4),
        ("hir_type_len_token", tree_rows * 4),
        ("hir_type_len_value", tree_rows * 4),
        ("hir_type_path_leaf_node", tree_rows * 4),
        ("hir_bound_path_owner_by_leaf", tree_rows * 4),
        ("hir_type_arg_start", tree_rows * 4),
        ("hir_type_arg_count", tree_rows * 4),
        ("hir_type_arg_next", tree_rows * 4),
        ("hir_type_path_leaf_link_a", tree_rows * 4),
        ("hir_type_path_leaf_link_b", tree_rows * 4),
        ("hir_type_path_leaf_value_a", tree_rows * 4),
        ("hir_type_path_leaf_value_b", tree_rows * 4),
        ("hir_canonical_alias_to_dense", tree_rows * 4),
        ("hir_canonical_anchor_owner", input_token_rows * 4),
        ("hir_canonical_status", 13 * 4),
        ("hir_canonical_prefix_before_raw", tree_rows * 4),
        ("hir_canonical_dense_to_raw", input_token_rows * 4),
        ("hir_canonical_raw_to_dense", tree_rows * 4),
        ("hir_canonical_count", 4),
        ("hir_array_compact_element_start", input_token_rows * 4),
        ("hir_array_compact_element_count", input_token_rows * 4),
        ("hir_call_arg_ranges", input_token_rows * 8),
        ("hir_match_arm_ranges", input_token_rows * 8),
        ("hir_match_pattern_to_arm", input_token_rows * 4),
        ("hir_param_ranges", input_token_rows * 8),
        ("hir_type_arg_ranges", input_token_rows * 8),
    ] {
        if !capacity.retain_debug_hir_buffers
            && matches!(
                name,
                "hir_canonical_prefix_before_raw"
                    | "hir_canonical_alias_to_dense"
                    | "hir_canonical_raw_to_dense"
            )
        {
            continue;
        }
        let resource = storage(
            &mut graph,
            name,
            ResourceDomain::HirNodes,
            parser_resource_class(capacity, name),
            bytes,
        )?;
        if retained_hir_output(name) {
            graph.mark_zero_initialized(resource)?;
        }
    }
    if !capacity.retain_debug_hir_buffers {
        for (alias, storage_name) in [
            (
                "hir_canonical_prefix_before_raw",
                "hir_semantic_child_index",
            ),
            ("hir_canonical_alias_to_dense", "hir_semantic_subtree_end"),
            ("hir_canonical_raw_to_dense", "hir_semantic_depth"),
        ] {
            graph.add_resource_alias(
                alias,
                graph
                    .resource_id(storage_name)
                    .expect("canonical identity alias storage graph resource"),
            )?;
        }
    }
    graph.add_resource_alias(
        "hir_type_path_owner_by_leaf",
        graph
            .resource_id("hir_type_path_leaf_link_b")
            .expect("type-path leaf link graph resource"),
    )?;
    graph.mark_zero_initialized(
        graph
            .resource_id("hir_bound_path_owner_by_leaf")
            .expect("bound-path owner graph resource"),
    )?;
    token_frontend::register_resources(&mut graph, capacity)?;
    hir::register_resources(&mut graph, capacity)?;
    for name in [
        "active_pair_thread_dispatch_args",
        "active_stack_thread_dispatch_args",
        "tree_active_dispatch_args",
        "tree_enum_dispatch_args",
        "tree_match_dispatch_args",
        "tree_struct_dispatch_args",
        "hir_semantic_dispatch_args",
    ] {
        workspace_indirect(&mut graph, name, 12)?;
    }
    let raw_relation_dispatch_rows =
        crate::parser::passes::hir::semantic::parent::step::canonical_relation_step_capacity(
            capacity.tree_capacity,
        )
        .max(1);
    workspace_indirect(
        &mut graph,
        "hir_raw_relation_dispatch_args",
        u64::from(raw_relation_dispatch_rows) * 12,
    )?;
    workspace_indirect(
        &mut graph,
        "hir_semantic_relation_dispatch_args",
        u64::from(raw_relation_dispatch_rows) * 12,
    )?;
    let local_relation_dispatch_rows =
        crate::parser::passes::hir::semantic::parent::step::bounded_walk_steps_after_local_span(
            capacity.tree_capacity,
            crate::parser::passes::hir::nodes::SEMANTIC_PARENT_LOCAL_ANCESTOR_SPAN,
        )
        .max(1);
    workspace_indirect(
        &mut graph,
        "hir_local_relation_dispatch_args",
        u64::from(local_relation_dispatch_rows) * 12,
    )?;

    graph.add_physical_reset_pass(JOB_STORAGE_RESET, CompilerPhase::Parse)?;

    if !capacity.preclassified_token_kinds {
        token_frontend::register_schedule(&mut graph, capacity, &passes.token_frontend)?;
    }

    clear(
        &mut graph,
        TOKEN_FILE_ID_CLEAR,
        CompilerPhase::Parse,
        &[("token_file_id", "token_file_id")],
    )?;
    graph.add_buffer_copy_pass(
        TOKEN_FILE_ID_COPY,
        CompilerPhase::Parse,
        "lexer_token_file_id",
        graph
            .resource_id("lexer_token_file_id")
            .expect("lexer token-file input resource"),
        "token_file_id",
        graph
            .resource_id("token_file_id")
            .expect("parser token-file resource"),
    )?;

    reflected(
        &mut graph,
        ACTIVE_PAIR_DISPATCH,
        CompilerPhase::Parse,
        ResourceDomain::DispatchArguments,
        &passes.active_pair_dispatch_args,
        &[(
            "active_pair_thread_dispatch_args",
            "active_pair_thread_dispatch_args",
            Some(AccessMode::Write),
        )],
    )?;
    static_pass(
        &mut graph,
        &passes.llp_pairs,
        CompilerPhase::Parse,
        ResourceDomain::Tokens,
        &[("out_headers", "out_headers", Some(AccessMode::Write))],
    )?;
    indirect(&mut graph, "llp_pairs", "active_pair_thread_dispatch_args")?;

    reflected(
        &mut graph,
        PACK_TOTALS_BLOCKS,
        CompilerPhase::Parse,
        ResourceDomain::Tokens,
        passes.pack_totals_blocks.data(),
        &[
            ("sc_block_sum", "pack_sc_prefix_a", Some(AccessMode::Write)),
            (
                "emit_block_sum",
                "pack_emit_prefix_a",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    let pack_total_reduce_steps =
        crate::parser::buffers::pack_total_reduce_step_count(capacity.pair_capacity);
    let register_pack_total_reduce = |graph: &mut CompilerGraphBuilder,
                                      name: &'static str,
                                      read_a: bool|
     -> Result<(), String> {
        let (sc_in, emit_in, sc_out, emit_out) = if read_a {
            (
                "pack_sc_prefix_a",
                "pack_emit_prefix_a",
                "pack_sc_prefix_b",
                "pack_emit_prefix_b",
            )
        } else {
            (
                "pack_sc_prefix_b",
                "pack_emit_prefix_b",
                "pack_sc_prefix_a",
                "pack_emit_prefix_a",
            )
        };
        reflected(
            graph,
            name,
            CompilerPhase::Parse,
            ResourceDomain::Tokens,
            passes.pack_totals_reduce.data(),
            &[
                ("sc_in", sc_in, Some(AccessMode::Read)),
                ("emit_in", emit_in, Some(AccessMode::Read)),
                ("sc_out", sc_out, Some(AccessMode::Write)),
                ("emit_out", emit_out, Some(AccessMode::Write)),
            ],
        )
    };
    // The resident workspace can be reused with any active token count up to
    // its capacity. That active count can change the reduction-step parity, so
    // the graph must describe every operation the workspace may execute rather
    // than only the path implied by its physical capacity.
    register_pack_total_reduce(&mut graph, PACK_TOTALS_REDUCE_A_TO_B, true)?;
    register_pack_total_reduce(&mut graph, PACK_TOTALS_REDUCE_B_TO_A, false)?;
    let paired_reduce_steps = pack_total_reduce_steps / 2;
    if paired_reduce_steps > 0 {
        graph.repeat_pass_range(
            paired_reduce_steps,
            PACK_TOTALS_REDUCE_A_TO_B,
            PACK_TOTALS_REDUCE_B_TO_A,
        )?;
    }
    register_pack_total_reduce(&mut graph, PACK_TOTALS_REDUCE_FINAL_A_TO_B, true)?;
    reflected(
        &mut graph,
        PACK_TOTALS_STATUS,
        CompilerPhase::Parse,
        ResourceDomain::Tokens,
        passes.pack_totals_status.data(),
        &[
            ("sc_total_a", "pack_sc_prefix_a", Some(AccessMode::Read)),
            ("sc_total_b", "pack_sc_prefix_b", Some(AccessMode::Read)),
            ("emit_total_a", "pack_emit_prefix_a", Some(AccessMode::Read)),
            ("emit_total_b", "pack_emit_prefix_b", Some(AccessMode::Read)),
            (
                "partial_parse_status",
                "partial_parse_status",
                Some(AccessMode::Write),
            ),
            (
                "active_stack_thread_dispatch_args",
                "active_stack_thread_dispatch_args",
                Some(AccessMode::Write),
            ),
        ],
    )?;

    let (pack_local, pack_up, pack_down, pack_apply) = passes.pack_offsets.graph_passes();
    let pack_common = [
        ("sc_workspace", "pack_sc_prefix_a", None),
        ("emit_workspace", "pack_emit_prefix_a", None),
        ("sc_block_prefix", "pack_sc_prefix_b", None),
        ("emit_block_prefix", "pack_emit_prefix_b", None),
    ];
    let pack_local_aliases = [
        ("sc_workspace", "pack_sc_prefix_a", Some(AccessMode::Write)),
        (
            "emit_workspace",
            "pack_emit_prefix_a",
            Some(AccessMode::Write),
        ),
        ("sc_block_prefix", "pack_sc_prefix_b", None),
        ("emit_block_prefix", "pack_emit_prefix_b", None),
        ("sc_offsets", "sc_offsets", Some(AccessMode::Write)),
        ("emit_offsets", "emit_offsets", Some(AccessMode::Write)),
    ];
    reflected(
        &mut graph,
        PACK_OFFSETS_LOCAL,
        CompilerPhase::Parse,
        ResourceDomain::Tokens,
        pack_local,
        &pack_local_aliases,
    )?;
    indirect(
        &mut graph,
        PACK_OFFSETS_LOCAL,
        "active_pair_thread_dispatch_args",
    )?;
    let pack_levels = hierarchical_scan_levels(capacity.pair_capacity.div_ceil(256).max(1));
    if !pack_levels.is_empty() {
        reflected(
            &mut graph,
            "pack_offsets_scan.hierarchy_up",
            CompilerPhase::Parse,
            ResourceDomain::Tokens,
            pack_up,
            &pack_common,
        )?;
        graph.repeat_pass_range(
            pack_levels.len() as u32,
            "pack_offsets_scan.hierarchy_up",
            "pack_offsets_scan.hierarchy_up",
        )?;
    }
    if pack_levels.len() > 1 {
        reflected(
            &mut graph,
            "pack_offsets_scan.hierarchy_down",
            CompilerPhase::Parse,
            ResourceDomain::Tokens,
            pack_down,
            &pack_common,
        )?;
        graph.repeat_pass_range(
            (pack_levels.len() - 1) as u32,
            "pack_offsets_scan.hierarchy_down",
            "pack_offsets_scan.hierarchy_down",
        )?;
    }
    reflected(
        &mut graph,
        PACK_OFFSETS_APPLY,
        CompilerPhase::Parse,
        ResourceDomain::Tokens,
        pack_apply,
        &pack_common,
    )?;
    indirect(
        &mut graph,
        PACK_OFFSETS_APPLY,
        "active_pair_thread_dispatch_args",
    )?;
    reflected(
        &mut graph,
        PACK_OFFSETS_STATUS,
        CompilerPhase::Parse,
        ResourceDomain::Tokens,
        passes.pack_offsets_status.data(),
        &[(
            "active_stack_thread_dispatch_args",
            "active_stack_thread_dispatch_args",
            Some(AccessMode::Write),
        )],
    )?;
    indirect(
        &mut graph,
        PACK_OFFSETS_STATUS,
        "active_pair_thread_dispatch_args",
    )?;
    static_pass(
        &mut graph,
        &passes.pack_varlen,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        &[],
    )?;
    graph.mark_pass_bindings_initialize("pack_varlen", &["out_sc", "out_emit", "out_emit_pos"])?;
    indirect(
        &mut graph,
        "pack_varlen",
        "active_pair_thread_dispatch_args",
    )?;
    graph.add_buffer_copy_pass(
        PACK_STATUS_PROMOTE,
        CompilerPhase::Parse,
        "partial_parse_status",
        graph
            .resource_id("partial_parse_status")
            .expect("partial parser status resource"),
        "ll1_status",
        graph
            .resource_id("ll1_status")
            .expect("LL(1) status resource"),
    )?;

    clear(
        &mut graph,
        STACK_EFFECT_CLEAR,
        CompilerPhase::Parse,
        &[
            ("bracket_valid", "bracket_valid"),
            ("bracket_depths", "bracket_depths"),
            ("bracket_block_sum", "bracket_block_sum"),
            ("bracket_block_minpref", "bracket_block_minpref"),
            ("bracket_block_row_min", "bracket_block_row_min"),
            ("bracket_block_maxdepth", "bracket_block_maxdepth"),
        ],
    )?;

    let bracket_aliases: [(&str, &str, Option<AccessMode>); 5] = [
        ("exscan_inblock", "bracket_exscan_inblock", None),
        ("block_sum", "bracket_block_sum", None),
        ("block_minpref", "bracket_block_minpref", None),
        ("block_row_min", "bracket_block_row_min", None),
        ("block_maxdepth", "bracket_block_maxdepth", None),
    ];
    static_pass(
        &mut graph,
        &passes.b01,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        &[
            ("sc_stream", "out_sc", None),
            (
                bracket_aliases[0].0,
                bracket_aliases[0].1,
                Some(AccessMode::Write),
            ),
            (
                bracket_aliases[1].0,
                bracket_aliases[1].1,
                Some(AccessMode::Write),
            ),
            (
                bracket_aliases[2].0,
                bracket_aliases[2].1,
                Some(AccessMode::Write),
            ),
            (
                bracket_aliases[3].0,
                bracket_aliases[3].1,
                Some(AccessMode::Write),
            ),
            (
                bracket_aliases[4].0,
                bracket_aliases[4].1,
                Some(AccessMode::Write),
            ),
        ],
    )?;
    indirect(
        &mut graph,
        "brackets_01_scan_inblock",
        "active_stack_thread_dispatch_args",
    )?;
    let (bracket_up, bracket_down, bracket_finalize) = passes.b02.graph_passes();
    let bracket_scan_aliases = [
        ("block_sum", "bracket_block_sum", None),
        ("block_minpref", "bracket_block_minpref", None),
        ("block_maxdepth", "bracket_block_maxdepth", None),
        ("prefix_sum", "bracket_prefix_sum", None),
        ("prefix_min", "bracket_prefix_min", None),
        ("hierarchy_sum", "bracket_hierarchy_sum", None),
        ("hierarchy_min", "bracket_hierarchy_min", None),
        ("block_prefix", "bracket_block_prefix", None),
        ("out_depths", "bracket_depths", None),
        ("out_valid", "bracket_valid", None),
    ];
    let bracket_levels = hierarchical_scan_levels(capacity.bracket_blocks.max(1));
    reflected(
        &mut graph,
        BRACKET_SCAN_UP,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        bracket_up,
        &bracket_scan_aliases,
    )?;
    graph.mark_pass_bindings_initialize(
        BRACKET_SCAN_UP,
        &["prefix_sum", "prefix_min", "hierarchy_sum", "hierarchy_min"],
    )?;
    graph.repeat_pass_range(
        bracket_levels.len() as u32,
        BRACKET_SCAN_UP,
        BRACKET_SCAN_UP,
    )?;
    if bracket_levels.len() > 1 {
        reflected(
            &mut graph,
            BRACKET_SCAN_DOWN,
            CompilerPhase::Parse,
            ResourceDomain::RawNodes,
            bracket_down,
            &bracket_scan_aliases,
        )?;
        graph.repeat_pass_range(
            (bracket_levels.len() - 1) as u32,
            BRACKET_SCAN_DOWN,
            BRACKET_SCAN_DOWN,
        )?;
    }
    reflected(
        &mut graph,
        BRACKET_SCAN_FINALIZE,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        bracket_finalize,
        &[
            bracket_scan_aliases[0],
            bracket_scan_aliases[1],
            bracket_scan_aliases[2],
            bracket_scan_aliases[3],
            bracket_scan_aliases[4],
            bracket_scan_aliases[5],
            bracket_scan_aliases[6],
            (
                bracket_scan_aliases[7].0,
                bracket_scan_aliases[7].1,
                Some(AccessMode::Write),
            ),
            bracket_scan_aliases[8],
            (
                bracket_scan_aliases[9].0,
                bracket_scan_aliases[9].1,
                Some(AccessMode::Write),
            ),
        ],
    )?;
    static_pass(
        &mut graph,
        &passes.b03,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        &[
            ("sc_stream", "out_sc", None),
            ("exscan_inblock", "bracket_exscan_inblock", None),
            ("block_prefix", "bracket_block_prefix", None),
            ("out_depths_ro", "bracket_depths", None),
            ("layer", "bracket_layer", Some(AccessMode::Write)),
        ],
    )?;
    indirect(
        &mut graph,
        "brackets_03_apply_prefix",
        "active_stack_thread_dispatch_args",
    )?;
    reflected(
        &mut graph,
        "brackets_04_build_min_tree",
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        passes.b_min_tree.graph_pass(),
        &[
            ("block_row_min", "bracket_block_row_min", None),
            ("block_prefix", "bracket_block_prefix", None),
            ("min_tree", "bracket_min_tree", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize("brackets_04_build_min_tree", &["min_tree"])?;
    graph.repeat_pass_range(
        bracket_leaf_base.trailing_zeros() + 1,
        "brackets_04_build_min_tree",
        "brackets_04_build_min_tree",
    )?;
    if capacity.emit_stack_matches {
        static_pass(
            &mut graph,
            &passes.b_clear_matches,
            CompilerPhase::Parse,
            ResourceDomain::RawNodes,
            &[(
                "match_for_index",
                "match_for_index",
                Some(AccessMode::Write),
            )],
        )?;
        indirect(
            &mut graph,
            "brackets_04_clear_matches",
            "active_stack_thread_dispatch_args",
        )?;
    }
    static_pass(
        &mut graph,
        &passes.pse04,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        &[
            ("sc_stream", "out_sc", None),
            ("layer", "bracket_layer", None),
            ("block_row_min", "bracket_block_row_min", None),
            ("block_prefix", "bracket_block_prefix", None),
            ("min_tree", "bracket_min_tree", None),
            ("out_valid", "bracket_valid", None),
            (
                "match_for_index",
                "match_for_index",
                Some(if capacity.emit_stack_matches {
                    AccessMode::ReadWrite
                } else {
                    AccessMode::Write
                }),
            ),
        ],
    )?;
    indirect(
        &mut graph,
        "brackets_pse_04_pair_by_layer",
        "active_stack_thread_dispatch_args",
    )?;
    static_pass(
        &mut graph,
        &passes.status_from_brackets,
        CompilerPhase::Parse,
        ResourceDomain::Tokens,
        &[
            ("bracket_depths", "bracket_depths", None),
            ("bracket_valid", "bracket_valid", None),
        ],
    )?;

    static_pass(
        &mut graph,
        &passes.tree_active_dispatch_args,
        CompilerPhase::Parse,
        ResourceDomain::DispatchArguments,
        &[
            ("tree_count_status", "ll1_status", None),
            (
                "tree_active_dispatch_args",
                "tree_active_dispatch_args",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    reflected(
        &mut graph,
        TREE_FEATURE_DISPATCH,
        CompilerPhase::Parse,
        ResourceDomain::DispatchArguments,
        &passes.tree_feature_dispatch_args,
        &[
            ("tree_count_status", "ll1_status", None),
            (
                "tree_enum_dispatch_args",
                "tree_enum_dispatch_args",
                Some(AccessMode::Write),
            ),
            (
                "tree_match_dispatch_args",
                "tree_match_dispatch_args",
                Some(AccessMode::Write),
            ),
            (
                "tree_struct_dispatch_args",
                "tree_struct_dispatch_args",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    static_pass(
        &mut graph,
        &passes.tree_prefix_01,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        &[
            ("emit_stream", "out_emit", None),
            ("tree_count_status", "partial_parse_status", None),
            ("node_kind", "node_kind", Some(AccessMode::Write)),
            (
                "prefix_inblock",
                "tree_prefix_inblock",
                Some(AccessMode::Write),
            ),
            ("block_sum", "tree_block_sum", Some(AccessMode::Write)),
        ],
    )?;
    let tree_steps = ping_pong_scan_steps(
        capacity.tree_node_blocks.max(1),
        ScanFinalize::Always(capacity.tree_node_blocks.max(1)),
    );
    reflected(
        &mut graph,
        TREE_PREFIX_B_TO_A,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        passes.tree_prefix_02.data(),
        &[
            ("block_sum", "tree_block_sum", None),
            ("prefix_in", "tree_block_prefix_b", Some(AccessMode::Read)),
            ("prefix_out", "tree_block_prefix_a", Some(AccessMode::Write)),
            ("block_prefix", "tree_block_prefix", Some(AccessMode::Write)),
        ],
    )?;
    graph.mark_pass_bindings_first_invocation_skips_read(TREE_PREFIX_B_TO_A, &["prefix_in"])?;
    reflected(
        &mut graph,
        TREE_PREFIX_A_TO_B,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        passes.tree_prefix_02.data(),
        &[
            ("block_sum", "tree_block_sum", None),
            ("prefix_in", "tree_block_prefix_a", Some(AccessMode::Read)),
            ("prefix_out", "tree_block_prefix_b", Some(AccessMode::Write)),
            ("block_prefix", "tree_block_prefix", Some(AccessMode::Write)),
        ],
    )?;
    graph.repeat_pass_range(
        (tree_steps.len() as u32).div_ceil(2),
        TREE_PREFIX_B_TO_A,
        TREE_PREFIX_A_TO_B,
    )?;
    static_pass(
        &mut graph,
        &passes.tree_prefix_03,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("prefix_inblock", "tree_prefix_inblock", None),
            ("block_sum", "tree_block_sum", None),
            ("block_prefix", "tree_block_prefix", None),
            ("tree_prefix", "tree_prefix", Some(AccessMode::Write)),
            (
                "prefix_block_max",
                "tree_prefix_block_max",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    static_pass(
        &mut graph,
        &passes.tree_prefix_04,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        &[
            ("prefix_block_max", "tree_prefix_block_max", None),
            ("prefix_block_max_tree", "tree_prefix_block_max_tree", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        "tree_prefix_04_build_max_tree",
        &["prefix_block_max_tree"],
    )?;
    graph.repeat_pass_range(
        prefix_leaf_base.trailing_zeros() + 1,
        "tree_prefix_04_build_max_tree",
        "tree_prefix_04_build_max_tree",
    )?;
    static_pass(
        &mut graph,
        &passes.tree_parent,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        &[
            ("emit_stream", "out_emit", None),
            ("tree_count_status", "partial_parse_status", None),
            ("node_kind", "node_kind", Some(AccessMode::Write)),
            ("parent", "parent", Some(AccessMode::Write)),
            ("prefix_block_max", "tree_prefix_block_max", None),
            ("prefix_block_max_tree", "tree_prefix_block_max_tree", None),
        ],
    )?;
    indirect(
        &mut graph,
        "tree_parent_parallel",
        "tree_active_dispatch_args",
    )?;
    static_pass(
        &mut graph,
        &passes.tree_spans,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("first_child", "first_child", Some(AccessMode::Write)),
            ("next_sibling", "next_sibling", Some(AccessMode::Write)),
            ("subtree_end", "subtree_end", Some(AccessMode::Write)),
            ("prefix_block_max", "tree_prefix_block_max", None),
            ("prefix_block_max_tree", "tree_prefix_block_max_tree", None),
        ],
    )?;
    indirect(&mut graph, "tree_spans", "tree_active_dispatch_args")?;
    static_pass(
        &mut graph,
        &passes.tree_prev_sibling_clear,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        &[],
    )?;
    graph.mark_pass_bindings_initialize("tree_prev_sibling_clear", &["prev_sibling"])?;
    indirect(
        &mut graph,
        "tree_prev_sibling_clear",
        "tree_active_dispatch_args",
    )?;
    static_pass(
        &mut graph,
        &passes.tree_prev_sibling_scatter,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    indirect(
        &mut graph,
        "tree_prev_sibling_scatter",
        "tree_active_dispatch_args",
    )?;
    static_pass(
        &mut graph,
        &passes.hir_nodes,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        &[
            ("emit_stream", "out_emit", None),
            ("emit_pos", "out_emit_pos", None),
            ("tree_count_status", "partial_parse_status", None),
            ("hir_kind", "hir_kind", Some(AccessMode::Write)),
            ("hir_token_pos", "hir_token_pos", Some(AccessMode::Write)),
            (
                "hir_token_file_id",
                "hir_token_file_id",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    indirect(&mut graph, "hir_nodes", "tree_active_dispatch_args")?;
    clear(
        &mut graph,
        HIR_EXPR_NAME_ROLE_CLEAR,
        CompilerPhase::Parse,
        &[("hir_expr_name_role", "hir_expr_name_role")],
    )?;
    static_pass(
        &mut graph,
        &passes.hir_expr_fields,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_expr_fields",
        &["hir_expr_record", "hir_expr_result_root_node"],
    )?;
    indirect(&mut graph, "hir_expr_fields", "tree_active_dispatch_args")?;
    clear(
        &mut graph,
        TREE_DEPTH_STATUS_CLEAR,
        CompilerPhase::Parse,
        &[("tree_depth_status", "tree_depth_status")],
    )?;
    static_pass(
        &mut graph,
        &passes.tree_depth_traverse,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("tree_depth_value_a", "tree_depth", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize("tree_depth_traverse", &["tree_depth_value_a"])?;
    indirect(
        &mut graph,
        "tree_depth_traverse",
        "tree_active_dispatch_args",
    )?;
    static_pass(
        &mut graph,
        &passes.tree_depth_block_max,
        CompilerPhase::Parse,
        ResourceDomain::RawNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "tree_depth_block_max",
                "tree_depth_block_max",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    indirect(
        &mut graph,
        "tree_depth_block_max",
        "tree_active_dispatch_args",
    )?;
    static_pass(
        &mut graph,
        &passes.tree_depth_schedule,
        CompilerPhase::Parse,
        ResourceDomain::DispatchArguments,
        &[
            (
                "hir_raw_relation_dispatch_args",
                "hir_raw_relation_dispatch_args",
                Some(AccessMode::Write),
            ),
            (
                "hir_local_relation_dispatch_args",
                "hir_local_relation_dispatch_args",
                Some(AccessMode::Write),
            ),
        ],
    )?;

    static_pass(
        &mut graph,
        &passes.hir_semantic_prefix_local,
        CompilerPhase::Hir,
        ResourceDomain::RawNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "hir_semantic_flag",
                "hir_semantic_flag",
                Some(AccessMode::Write),
            ),
            (
                "hir_semantic_local_prefix",
                "hir_semantic_local_prefix",
                Some(AccessMode::Write),
            ),
            (
                "hir_semantic_block_sum",
                "hir_semantic_block_sum",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    let semantic_scan_levels = hierarchical_scan_levels(capacity.tree_node_blocks.max(1));
    let (semantic_scan_up, semantic_scan_down) = passes.hir_semantic_prefix_blocks.graph_passes();
    let semantic_scan_aliases = [
        ("block_sum", "hir_semantic_block_sum", None),
        ("block_prefix", "hir_semantic_block_prefix_a", None),
        ("block_hierarchy", "hir_semantic_block_prefix_b", None),
    ];
    reflected(
        &mut graph,
        HIR_SEMANTIC_SCAN_UP,
        CompilerPhase::Hir,
        ResourceDomain::RawNodes,
        semantic_scan_up,
        &semantic_scan_aliases,
    )?;
    graph.mark_pass_bindings_initialize(
        HIR_SEMANTIC_SCAN_UP,
        &["block_prefix", "block_hierarchy"],
    )?;
    graph.repeat_pass_range(
        semantic_scan_levels.len() as u32,
        HIR_SEMANTIC_SCAN_UP,
        HIR_SEMANTIC_SCAN_UP,
    )?;
    if semantic_scan_levels.len() > 1 {
        reflected(
            &mut graph,
            HIR_SEMANTIC_SCAN_DOWN,
            CompilerPhase::Hir,
            ResourceDomain::RawNodes,
            semantic_scan_down,
            &semantic_scan_aliases,
        )?;
        graph.repeat_pass_range(
            (semantic_scan_levels.len() - 1) as u32,
            HIR_SEMANTIC_SCAN_DOWN,
            HIR_SEMANTIC_SCAN_DOWN,
        )?;
    }
    static_pass(
        &mut graph,
        &passes.hir_semantic_compact_scatter,
        CompilerPhase::Hir,
        ResourceDomain::RawNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "hir_node_dense_id",
                "hir_node_dense_id",
                Some(AccessMode::Write),
            ),
            (
                "hir_semantic_dense_node",
                "hir_semantic_dense_node",
                Some(AccessMode::Write),
            ),
            (
                "hir_semantic_prefix_before_node",
                "hir_semantic_prefix_before_node",
                Some(AccessMode::Write),
            ),
            (
                "hir_semantic_count",
                "hir_semantic_count",
                Some(AccessMode::Write),
            ),
            (
                "hir_semantic_block_prefix",
                "hir_semantic_block_prefix_a",
                None,
            ),
        ],
    )?;
    static_pass(
        &mut graph,
        &passes.hir_semantic_dispatch_args,
        CompilerPhase::Hir,
        ResourceDomain::DispatchArguments,
        &[
            (
                "hir_semantic_dispatch_args",
                "hir_semantic_dispatch_args",
                Some(AccessMode::Write),
            ),
            (
                "hir_raw_relation_dispatch_args",
                "hir_raw_relation_dispatch_args",
                None,
            ),
            (
                "hir_semantic_relation_dispatch_args",
                "hir_semantic_relation_dispatch_args",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    static_pass(
        &mut graph,
        &passes.hir_semantic_subtree_end,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "hir_semantic_subtree_end",
                "hir_semantic_subtree_end",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    indirect(
        &mut graph,
        "hir_semantic_subtree_end",
        "hir_semantic_dispatch_args",
    )?;
    static_pass(
        &mut graph,
        &passes.hir_semantic_parent_traverse,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "hir_semantic_parent",
                "hir_semantic_parent",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    indirect(
        &mut graph,
        "hir_semantic_parent_traverse",
        "hir_semantic_dispatch_args",
    )?;
    static_pass(
        &mut graph,
        &passes.hir_semantic_nav,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "hir_semantic_first_child",
                "hir_semantic_first_child",
                Some(AccessMode::Write),
            ),
            (
                "hir_semantic_next_sibling",
                "hir_semantic_next_sibling",
                Some(AccessMode::Write),
            ),
            (
                "hir_semantic_depth",
                "hir_semantic_depth",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    indirect(&mut graph, "hir_semantic_nav", "hir_semantic_dispatch_args")?;
    static_pass(
        &mut graph,
        &passes.hir_semantic_child_index_traverse,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "hir_semantic_child_index",
                "hir_semantic_child_index",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    indirect(
        &mut graph,
        "hir_semantic_child_index_traverse",
        "hir_semantic_dispatch_args",
    )?;

    clear(
        &mut graph,
        SOURCE_FILE_TOKEN_END_CLEAR,
        CompilerPhase::Hir,
        &[("source_file_token_end", "source_file_token_end")],
    )?;
    static_pass(
        &mut graph,
        &passes.source_file_token_end,
        CompilerPhase::Hir,
        ResourceDomain::Tokens,
        &[],
    )?;
    static_pass(
        &mut graph,
        &passes.hir_record_clear_base,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_record_clear_base",
        &[
            "hir_item_name_token",
            "hir_item_namespace",
            "hir_item_visibility",
            "hir_item_path_start",
            "hir_item_path_end",
            "hir_item_path_node",
            "hir_item_import_target_kind",
            "hir_param_type_node",
            "hir_param_record",
            "hir_stmt_record",
            "hir_type_alias_target_node",
            "hir_fn_return_type_node",
            "hir_method_owner_node",
            "hir_method_impl_node",
            "hir_method_name_token",
            "hir_method_first_param_token",
            "hir_method_receiver_mode",
            "hir_method_visibility",
            "hir_method_signature_flags",
            "hir_method_impl_receiver_type_node",
            "hir_stmt_scope_end",
            "hir_nearest_stmt_node",
            "hir_nearest_block_node",
            "hir_nearest_enclosing_control_node",
            "hir_nearest_loop_node",
            "hir_nearest_fn_node",
            "hir_nearest_array_element_node",
            "hir_call_context_stmt_node",
            "hir_array_lit_context_stmt_node",
            "hir_struct_lit_context_stmt_node",
            "hir_type_len_value",
            "hir_expr_result_root_scratch_node",
        ],
    )?;
    static_pass(
        &mut graph,
        &passes.hir_record_clear_calls,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "hir_member_receiver_node",
                "hir_member_receiver_node",
                Some(AccessMode::Write),
            ),
            (
                "hir_member_receiver_token",
                "hir_member_receiver_token",
                Some(AccessMode::Write),
            ),
            (
                "hir_member_name_token",
                "hir_member_name_token",
                Some(AccessMode::Write),
            ),
            (
                "hir_call_callee_node",
                "hir_call_callee_node",
                Some(AccessMode::Write),
            ),
            (
                "hir_call_callee_path_node",
                "hir_call_callee_path_node",
                Some(AccessMode::Write),
            ),
            (
                "hir_call_parent_by_callee",
                "hir_call_parent_by_callee",
                Some(AccessMode::Write),
            ),
            (
                "hir_call_arg_start",
                "hir_call_arg_start",
                Some(AccessMode::Write),
            ),
            (
                "hir_call_arg_end",
                "hir_call_arg_end",
                Some(AccessMode::Write),
            ),
            (
                "hir_call_arg_count",
                "hir_call_arg_count",
                Some(AccessMode::Write),
            ),
            (
                "hir_call_arg_parent_call",
                "hir_call_arg_parent_call",
                Some(AccessMode::Write),
            ),
            (
                "hir_call_arg_ordinal",
                "hir_call_arg_ordinal",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    indirect(
        &mut graph,
        "hir_record_clear_calls",
        "tree_active_dispatch_args",
    )?;
    static_pass(
        &mut graph,
        &passes.hir_type_fields,
        CompilerPhase::Hir,
        ResourceDomain::RawNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_type_fields",
        &[
            "hir_type_form",
            "hir_type_value_node",
            "hir_type_len_token",
            "hir_type_path_leaf_node",
            "hir_type_path_leaf_link_a",
            "hir_type_path_leaf_value_a",
            "hir_type_arg_start",
            "hir_type_arg_count",
            "hir_type_arg_next",
        ],
    )?;
    indirect(&mut graph, "hir_type_fields", "tree_active_dispatch_args")?;
    let type_path_leaf_steps =
        crate::parser::passes::hir::bounded_walk_step_capacity(capacity.tree_capacity) as usize;
    for (step, &name) in HIR_TYPE_PATH_LEAF_STEPS
        .iter()
        .take(type_path_leaf_steps)
        .enumerate()
    {
        let (link_in, value_in, link_out, value_out) = if step % 2 == 0 {
            (
                "hir_type_path_leaf_link_a",
                "hir_type_path_leaf_value_a",
                "hir_type_path_leaf_link_b",
                "hir_type_path_leaf_value_b",
            )
        } else {
            (
                "hir_type_path_leaf_link_b",
                "hir_type_path_leaf_value_b",
                "hir_type_path_leaf_link_a",
                "hir_type_path_leaf_value_a",
            )
        };
        reflected(
            &mut graph,
            name,
            CompilerPhase::Hir,
            ResourceDomain::RawNodes,
            passes.hir_type_path_leaf_step.graph_pass(),
            &[
                ("tree_count_status", "partial_parse_status", None),
                (
                    "hir_type_path_leaf_link_in",
                    link_in,
                    Some(AccessMode::Read),
                ),
                (
                    "hir_type_path_leaf_value_in",
                    value_in,
                    Some(AccessMode::Read),
                ),
                (
                    "hir_type_path_leaf_link_out",
                    link_out,
                    Some(AccessMode::Write),
                ),
                (
                    "hir_type_path_leaf_value_out",
                    value_out,
                    Some(AccessMode::Write),
                ),
            ],
        )?;
        indirect(&mut graph, name, "tree_active_dispatch_args")?;
    }
    if type_path_leaf_steps % 2 == 1 {
        graph.add_pass(PassDesc {
            name: HIR_TYPE_PATH_LEAF_FINALIZE,
            phase: CompilerPhase::Hir,
            dispatch_domain: ResourceDomain::RawNodes,
            accesses: vec![
                PassAccess::read(
                    "hir_type_path_leaf_link_b",
                    graph.resource_id("hir_type_path_leaf_link_b").unwrap(),
                ),
                PassAccess::write(
                    "hir_type_path_leaf_link_a",
                    graph.resource_id("hir_type_path_leaf_link_a").unwrap(),
                ),
                PassAccess::read(
                    "hir_type_path_leaf_value_b",
                    graph.resource_id("hir_type_path_leaf_value_b").unwrap(),
                ),
                PassAccess::write(
                    "hir_type_path_leaf_value_a",
                    graph.resource_id("hir_type_path_leaf_value_a").unwrap(),
                ),
            ],
        })?;
    }
    clear(
        &mut graph,
        HIR_TYPE_PATH_LEAF_LINK_B_CLEAR,
        CompilerPhase::Hir,
        &[("hir_type_path_leaf_link_b", "hir_type_path_leaf_link_b")],
    )?;
    static_pass(
        &mut graph,
        &passes.hir_type_path_leaf_scatter,
        CompilerPhase::Hir,
        ResourceDomain::RawNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    indirect(
        &mut graph,
        "hir_type_path_leaf_scatter",
        "tree_active_dispatch_args",
    )?;
    static_pass(
        &mut graph,
        &passes.hir_spans,
        CompilerPhase::Hir,
        ResourceDomain::RawNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("hir_token_end", "hir_token_end", Some(AccessMode::Write)),
        ],
    )?;
    indirect(&mut graph, "hir_spans", "tree_active_dispatch_args")?;

    clear(
        &mut graph,
        HIR_CANONICAL_IDENTITY_CLEAR,
        CompilerPhase::Hir,
        &[
            ("hir_canonical_anchor_owner", "hir_canonical_anchor_owner"),
            ("hir_canonical_count", "hir_canonical_count"),
            ("hir_canonical_status", "hir_canonical_status"),
        ],
    )?;

    static_pass(
        &mut graph,
        &passes.hir_canonical_mark,
        CompilerPhase::Hir,
        ResourceDomain::RawNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "canonical_anchor_by_raw",
                "hir_canonical_alias_to_dense",
                None,
            ),
            ("canonical_flag", "hir_semantic_flag", None),
            ("canonical_anchor_owner", "hir_canonical_anchor_owner", None),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize("hir_canonical_mark", &["canonical_anchor_by_raw"])?;
    static_pass(
        &mut graph,
        &passes.hir_canonical_local,
        CompilerPhase::Hir,
        ResourceDomain::RawNodes,
        &[
            ("canonical_flag", "hir_semantic_flag", None),
            (
                "canonical_anchor_by_raw",
                "hir_canonical_alias_to_dense",
                None,
            ),
            ("canonical_anchor_owner", "hir_canonical_anchor_owner", None),
            ("canonical_local_prefix", "hir_semantic_local_prefix", None),
            ("canonical_block_sum", "hir_semantic_block_sum", None),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;
    reflected(
        &mut graph,
        HIR_CANONICAL_IDENTITY_SCAN_UP,
        CompilerPhase::Hir,
        ResourceDomain::RawNodes,
        semantic_scan_up,
        &semantic_scan_aliases,
    )?;
    graph.repeat_pass_range(
        semantic_scan_levels.len() as u32,
        HIR_CANONICAL_IDENTITY_SCAN_UP,
        HIR_CANONICAL_IDENTITY_SCAN_UP,
    )?;
    if semantic_scan_levels.len() > 1 {
        reflected(
            &mut graph,
            HIR_CANONICAL_IDENTITY_SCAN_DOWN,
            CompilerPhase::Hir,
            ResourceDomain::RawNodes,
            semantic_scan_down,
            &semantic_scan_aliases,
        )?;
        graph.repeat_pass_range(
            (semantic_scan_levels.len() - 1) as u32,
            HIR_CANONICAL_IDENTITY_SCAN_DOWN,
            HIR_CANONICAL_IDENTITY_SCAN_DOWN,
        )?;
    }
    static_pass(
        &mut graph,
        &passes.hir_canonical_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("canonical_flag", "hir_semantic_flag", None),
            ("canonical_local_prefix", "hir_semantic_local_prefix", None),
            (
                "canonical_block_prefix",
                "hir_semantic_block_prefix_a",
                None,
            ),
            (
                "canonical_prefix_before_raw",
                "hir_canonical_prefix_before_raw",
                None,
            ),
            ("canonical_dense_to_raw", "hir_canonical_dense_to_raw", None),
            ("canonical_raw_to_dense", "hir_canonical_raw_to_dense", None),
            (
                "canonical_count",
                "hir_canonical_count",
                Some(AccessMode::Write),
            ),
            ("canonical_status", "hir_canonical_status", None),
            (
                "array_element_start",
                "hir_array_compact_element_start",
                None,
            ),
            (
                "array_element_count",
                "hir_array_compact_element_count",
                None,
            ),
            ("call_arg_ranges", "hir_call_arg_ranges", None),
            ("match_arm_ranges", "hir_match_arm_ranges", None),
            ("match_pattern_to_arm", "hir_match_pattern_to_arm", None),
            ("param_ranges", "hir_param_ranges", None),
            ("type_arg_ranges", "hir_type_arg_ranges", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_canonical_scatter",
        &[
            "canonical_prefix_before_raw",
            "canonical_dense_to_raw",
            "canonical_raw_to_dense",
            "array_element_start",
            "array_element_count",
            "call_arg_ranges",
            "match_arm_ranges",
            "match_pattern_to_arm",
            "param_ranges",
            "type_arg_ranges",
        ],
    )?;
    static_pass(
        &mut graph,
        &passes.hir_canonical_identity_aliases,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("canonical_anchor_owner", "hir_canonical_anchor_owner", None),
            ("canonical_raw_to_dense", "hir_canonical_raw_to_dense", None),
            ("raw_to_hir", "hir_canonical_alias_to_dense", None),
        ],
    )?;
    hir::register_post_identity_schedule(&mut graph, capacity, passes)?;

    let hir_count_sources = [
        "hir_semantic_count",
        "hir_canonical_count",
        "hir_canonical_status",
        "hir_call_arg_table_count",
        "hir_param_table_count",
        "hir_type_arg_table_count",
        "hir_generic_param_table_count",
        "hir_path_table_count",
        "hir_path_segment_table_count",
        "hir_field_table_count",
        "hir_variant_table_count",
        "hir_variant_payload_table_count",
        "hir_match_arm_table_count",
        "hir_match_payload_table_count",
        "hir_array_element_table_count",
        "hir_string_count",
        "hir_method_table_count",
        "hir_predicate_table_count",
    ];
    let hir_count_sources =
        hir_count_sources.map(|name| (name, graph.resource_id(name).expect("HIR count resource")));
    graph.add_buffers_copy_pass(
        HIR_COUNTS_READBACK,
        CompilerPhase::Hir,
        &hir_count_sources,
        "hir_count_readback",
        graph
            .resource_id("hir_count_readback")
            .expect("HIR count readback resource"),
    )?;

    for (name, source_binding) in [
        ("parser.status.ll1.readback", "ll1_status"),
        (
            "parser.status.token_features.readback",
            "token_feature_flags",
        ),
        ("parser.status.tree_depth.readback", "tree_depth_status"),
        (
            "parser.status.partial_parse.readback",
            "partial_parse_status",
        ),
        (
            "parser.status.partial_token_features.readback",
            "token_feature_flags",
        ),
    ] {
        let source = graph
            .resource_id(source_binding)
            .expect("parser status readback source resource");
        let destination = graph
            .resource_id("status_readback")
            .expect("parser status readback destination resource");
        graph.add_buffer_copy_pass(
            name,
            CompilerPhase::Hir,
            source_binding,
            source,
            "status_readback",
            destination,
        )?;
    }

    graph.build()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frontend_graph_contains_exact_scan_regions() {
        let gpu = crate::gpu::device::global();
        let passes = ParserPasses::new(&gpu.device).unwrap();
        let capacity = ParserGraphCapacity {
            source_capacity: 8192,
            n_tokens: 4098,
            token_capacity: 4096,
            pair_capacity: 4097,
            total_sc: 16384,
            tree_capacity: 131072,
            bracket_blocks: 64,
            tree_node_blocks: 512,
            tree_prefix_blocks: 513,
            action_table_bytes: 4096,
            table_blob_words: 1024,
            production_count: 256,
            parser_feature_flags: 0,
            emit_stack_matches: false,
            retain_debug_hir_buffers: false,
            preclassified_token_kinds: false,
        };
        let graph = build_graph(capacity, &passes).unwrap();
        if std::env::var_os("LANIUS_TEST_PRINT_PARSER_EXTERNALS").is_some() {
            let external = graph
                .resources()
                .iter()
                .filter(|resource| resource.class == ResourceClass::External)
                .map(|resource| resource.name)
                .collect::<Vec<_>>();
            eprintln!(
                "parser external resources ({}): {external:#?}",
                external.len()
            );
        }
        for name in [
            "node_kind",
            "parent",
            "first_child",
            "next_sibling",
            "subtree_end",
            "hir_kind",
            "hir_semantic_dense_node",
        ] {
            let resource = graph.resource_id(name).unwrap();
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "production-only parser relation {name} should remain colorable",
            );
        }
        let debug_graph = build_graph(
            ParserGraphCapacity {
                retain_debug_hir_buffers: true,
                ..capacity
            },
            &passes,
        )
        .unwrap();
        for name in [
            "node_kind",
            "parent",
            "first_child",
            "next_sibling",
            "subtree_end",
            "hir_kind",
            "hir_semantic_dense_node",
        ] {
            let resource = debug_graph.resource_id(name).unwrap();
            assert_eq!(
                debug_graph.resource(resource).unwrap().class,
                ResourceClass::Output,
                "debug parser relation {name} must survive graph completion",
            );
        }
        assert_eq!(
            debug_graph
                .resource(
                    debug_graph
                        .resource_id("hir_call_callee_node")
                        .expect("debug call-callee resource"),
                )
                .expect("debug call-callee description")
                .bytes,
            u64::from(capacity.tree_capacity) * 4,
            "debug call records are raw-tree-indexed and must cover every recovered node",
        );
        assert_eq!(
            graph
                .resource(
                    graph
                        .resource_id("hir_call_callee_node")
                        .expect("production call-callee resource"),
                )
                .expect("production call-callee description")
                .bytes,
            u64::from(capacity.token_capacity) * 4,
            "production call records only retain the token-anchored compactable domain",
        );
        assert!(
            graph.pass_id("tree_prev_sibling_clear").unwrap().index()
                < graph.pass_id("tree_prev_sibling_scatter").unwrap().index()
        );
        assert!(
            graph
                .pass_id(
                    crate::parser::passes::tree::prev::sibling::clear::STRUCT_LITERAL_FIELD_NEXT_CLEAR,
                )
                .unwrap()
                .index()
                < graph.pass_id("hir_struct_field_scatter").unwrap().index()
        );
        for name in [
            "parser.tokens.impl_header.local",
            token_frontend::IMPL_HEADER_SCAN_UP,
            "parser.tokens.impl_header.apply",
            "parser.tokens.delimiters.local",
            token_frontend::DELIMITER_DEPTH_SCAN_UP,
            "parser.tokens.generic_shr.raw_local",
            token_frontend::GENERIC_SHR_RAW_SCAN_UP,
            "parser.tokens.generic_shr.raw_apply",
            "parser.tokens.delimiters.owner_local",
            token_frontend::DELIMITER_OWNER_HEADER_SCAN_UP,
            "parser.tokens.delimiters.owner_apply",
            token_frontend::DELIMITER_OWNER_SCAN_UP,
            "parser.tokens.brace_context",
            "parser.tokens.statement_phase.local",
            token_frontend::STATEMENT_PHASE_SCAN_UP,
            "parser.tokens.statement_phase.apply",
            "parser.tokens.delimiter_match.depth_blocks",
            "parser.tokens.delimiter_match.build_min_tree",
            "parser.tokens.brace_match.pair_pse",
            "parser.tokens.bracket_match.pair_pse",
            "parser.tokens.match_pattern.local",
            token_frontend::MATCH_PATTERN_SCAN_UP,
            "parser.tokens.match_pattern.apply",
            "parser.tokens.where_clause.local",
            token_frontend::WHERE_CLAUSE_SCAN_UP,
            "parser.tokens.where_clause.apply",
            "parser.tokens_to_kinds.pass",
            "parser.tokens.type_path_context.local",
            token_frontend::TYPE_PATH_SCAN_UP,
            "parser.tokens.type_path_context.apply",
            "parser.tokens_to_identifier_kinds.pass",
            "parser.tokens.generic_shr.local",
            token_frontend::GENERIC_SHR_SCAN_UP,
            "parser.tokens.generic_shr.apply",
            "parser.tokens.generic_shr.close_kinds",
            ACTIVE_PAIR_DISPATCH,
            "llp_pairs",
            PACK_TOTALS_BLOCKS,
            PACK_TOTALS_REDUCE_A_TO_B,
            PACK_TOTALS_REDUCE_B_TO_A,
            PACK_TOTALS_REDUCE_FINAL_A_TO_B,
            PACK_TOTALS_STATUS,
            "pack_offsets_scan.local",
            "pack_offsets_scan.apply",
            BRACKET_SCAN_UP,
            BRACKET_SCAN_FINALIZE,
            TREE_PREFIX_B_TO_A,
            TREE_PREFIX_A_TO_B,
            "tree_parent_parallel",
            "hir_nodes",
            "tree_depth_schedule",
            "hir_semantic_prefix_00_local",
            HIR_SEMANTIC_SCAN_UP,
            HIR_SEMANTIC_SCAN_DOWN,
            "hir_semantic_compact_scatter",
            "hir_semantic_dispatch_args",
            "hir_semantic_nav",
            "hir_semantic_child_index_traverse",
            "hir_type_arg_links",
            "hir_type_arg_rank_prefix_00_local",
            "hir_type_arg_rank_prefix_01_blocks.up",
            "hir_type_arg_rank_compact_scatter",
            "hir_type_arg_rank_step.a_to_b",
            "hir_type_arg_rank_step.b_to_a",
            "hir_type_arg_scatter",
            "hir_type_root_owner_init",
            crate::parser::passes::hir::types::root::step::A_TO_B,
            crate::parser::passes::hir::types::root::step::B_TO_A,
            "hir_enum_variant_links",
            crate::parser::passes::hir::enums::variant::rank_step::A_TO_B,
            crate::parser::passes::hir::enums::variant::rank_step::B_TO_A,
            "hir_enum_variant_scatter",
            "hir_item_fields",
            "hir_path_segment_root",
            "hir_path_segment_links",
            crate::parser::passes::hir::path::segment::step::A_TO_B,
            crate::parser::passes::hir::path::segment::step::B_TO_A,
            "hir_path_segment_scatter",
            "hir_type_alias_owner_init",
            crate::parser::passes::hir::types::alias::owner::step::A_TO_B,
            crate::parser::passes::hir::types::alias::owner::step::B_TO_A,
            "hir_type_alias_target",
            "hir_fn_return_type",
            "hir_param_links",
            "hir_param_rank_prefix_00_local",
            "hir_param_rank_prefix_01_blocks.up",
            "hir_param_rank_compact_scatter",
            "hir_param_id_clear",
            "hir_param_id_base",
            "hir_param_id_apply",
            "hir_param_fields",
            crate::parser::passes::hir::expr::result_root_step::A_TO_B,
            crate::parser::passes::hir::expr::result_root_step::B_TO_A,
            "hir_binary_spans",
            crate::parser::passes::hir::binary::span::step::A_TO_B,
            crate::parser::passes::hir::binary::span::step::B_TO_A,
            "hir_binary_span_apply",
            "hir_postfix_fields",
            "hir_member_spans",
            "hir_stmt_fields",
            "parser_hir_literal_values",
            "hir_string_compact_local",
            "hir_string_compact_prefix_01_blocks.up",
            "hir_string_compact_scatter",
            "hir_string_offset_local",
            "hir_string_offset_prefix_01_blocks.up",
            "hir_string_offset_scatter",
            "parser_hir_string_decode",
            "hir_call_fields",
            "hir_call_spans",
            "hir_range_spans",
            "hir_struct_lit_spans",
            "hir_canonical_stmt_compact",
            "hir_canonical_variant_mark",
            "hir_canonical_variant_local",
            "hir_canonical_variant_prefix_01_blocks.up",
            "hir_canonical_variant_scatter",
            "hir_canonical_variant_payload_owner_init",
            crate::parser::passes::hir::semantic::parent::step::CANONICAL_VARIANT_PAYLOAD_OWNER
                .a_to_b,
            crate::parser::passes::hir::semantic::parent::step::CANONICAL_VARIANT_PAYLOAD_OWNER
                .b_to_a,
            "hir_canonical_variant_payload_local",
            "hir_canonical_variant_payload_prefix_01_blocks.up",
            "hir_canonical_variant_payload_scatter",
            "hir_canonical_variant_payload_ordinal",
            "hir_call_arg_links",
            "hir_call_arg_rank_prefix_00_local",
            "hir_call_arg_rank_prefix_01_blocks.up",
            "hir_call_arg_rank_compact_scatter",
            "hir_call_arg_ordinal_step.a_to_b",
            "hir_call_arg_ordinal_step.b_to_a",
            "hir_call_arg_ordinal_scatter",
            "hir_canonical_call_arg_mark",
            "hir_canonical_call_arg_local",
            "hir_canonical_call_arg_prefix_01_blocks.up",
            "hir_canonical_call_arg_scatter",
            "hir_array_element_links",
            "hir_array_element_rank_prefix_00_local",
            "hir_array_element_rank_prefix_01_blocks.up",
            "hir_array_element_rank_compact_scatter",
            "hir_array_element_rank_step.a_to_b",
            "hir_array_element_rank_step.b_to_a",
            "hir_array_element_scatter",
            "hir_canonical_array_element_mark",
            "hir_canonical_array_element_local",
            "hir_canonical_array_element_prefix_01_blocks.up",
            "hir_canonical_array_element_scatter",
            "hir_struct_fields",
            "hir_struct_field_links",
            "hir_struct_rank_prefix_00_local",
            HIR_STRUCT_RANK_SCAN_UP,
            "hir_struct_rank_compact_scatter",
            crate::parser::passes::hir::structs::field::rank_step::A_TO_B,
            crate::parser::passes::hir::structs::field::rank_step::B_TO_A,
            crate::parser::passes::tree::prev::sibling::clear::STRUCT_LITERAL_FIELD_NEXT_CLEAR,
            "hir_struct_field_scatter",
            "hir_canonical_field_mark",
            "hir_canonical_field_local",
            "hir_canonical_field_prefix_01_blocks.up",
            "hir_canonical_field_scatter",
            "hir_context_relations_init",
            crate::parser::passes::hir::context::relations::step::A_TO_B,
            crate::parser::passes::hir::context::relations::step::B_TO_A,
            "hir_context_relations_scatter",
            "hir_stmt_scope",
            "hir_canonical_param_mark",
            "hir_canonical_param_local",
            "hir_canonical_param_prefix_01_blocks.up",
            "hir_canonical_param_scatter",
            "hir_canonical_type_arg_mark",
            "hir_canonical_type_arg_local",
            "hir_canonical_type_arg_prefix_01_blocks.up",
            "hir_canonical_type_arg_scatter",
            "hir_canonical_core",
            "hir_canonical_nav",
            "hir_canonical_expr_forest_edges",
            "hir_canonical_expr_forest_root_init",
            crate::parser::passes::hir::canonical::expr_forest::root_step::A_TO_B,
            crate::parser::passes::hir::canonical::expr_forest::root_step::B_TO_A,
            "hir_canonical_generic_param_candidate_mark",
            "hir_canonical_generic_param_finalize",
            "hir_canonical_generic_param_local",
            "hir_canonical_generic_param_prefix_01_blocks.up",
            "hir_canonical_generic_param_scatter",
            "hir_canonical_path_segment_mark",
            HIR_PATH_SEGMENT_SCAN_UP,
            "hir_canonical_path_segment_scatter",
            "hir_canonical_path_mark",
            "hir_canonical_path_local",
            "hir_canonical_path_prefix_01_blocks.up",
            "hir_canonical_path_scatter",
            "hir_canonical_string_scatter",
            "hir_canonical_predicate_finalize",
            "hir_canonical_predicate_local",
            "hir_canonical_predicate_prefix_01_blocks.up",
            "hir_canonical_predicate_scatter",
            "hir_canonical_validate",
            "hir_canonical_decl_index_clear",
            "hir_canonical_decl_index_scatter",
        ] {
            assert!(
                graph.pass_id(name).is_some(),
                "missing parser operation {name}"
            );
        }
        assert!(
            graph
                .repeated_regions()
                .iter()
                .any(|region| { region.first_pass == graph.pass_id(BRACKET_SCAN_UP).unwrap() })
        );
        for name in [
            token_frontend::DELIMITER_DEPTH_SCAN_UP,
            token_frontend::IMPL_HEADER_SCAN_UP,
            token_frontend::GENERIC_SHR_SCAN_UP,
            "parser.tokens.delimiter_match.build_min_tree",
        ] {
            let pass = graph.pass_id(name).unwrap();
            assert!(
                graph
                    .repeated_regions()
                    .iter()
                    .any(|region| region.first_pass == pass),
                "scalable token operation {name} is not a repeated graph region",
            );
        }
        let mut multi_level_capacity = capacity;
        multi_level_capacity.token_capacity = 100_000;
        multi_level_capacity.n_tokens = 100_002;
        let multi_level = build_graph(multi_level_capacity, &passes).unwrap();
        for name in [
            token_frontend::DELIMITER_DEPTH_SCAN_DOWN,
            token_frontend::IMPL_HEADER_SCAN_DOWN,
            token_frontend::STATEMENT_PHASE_SCAN_DOWN,
            token_frontend::MATCH_PATTERN_SCAN_DOWN,
            token_frontend::WHERE_CLAUSE_SCAN_DOWN,
            token_frontend::TYPE_PATH_SCAN_DOWN,
            token_frontend::GENERIC_SHR_RAW_SCAN_DOWN,
            token_frontend::GENERIC_SHR_SCAN_DOWN,
        ] {
            assert!(
                multi_level.pass_id(name).is_some(),
                "missing multilevel token scan operation {name}",
            );
        }
        assert!(
            graph.repeated_regions().iter().any(|region| {
                region.first_pass == graph.pass_id(HIR_SEMANTIC_SCAN_UP).unwrap()
            })
        );

        let mut match_capacity = capacity;
        // This capacity gives the canonical relation walk even parity but the
        // match-owner walk, after its 32-node local traversal, odd parity.
        // The graph must model the exact schedule used by the recorder.
        match_capacity.tree_capacity = 65_536;
        match_capacity.parser_feature_flags = crate::lexer::features::PARSER_FEATURE_MATCHES;
        let match_graph = build_graph(match_capacity, &passes).unwrap();
        for name in [
            "hir_match_arm_owner_init",
            crate::parser::passes::hir::semantic::parent::step::MATCH_ARM_OWNER.a_to_b,
            crate::parser::passes::hir::semantic::parent::step::MATCH_ARM_OWNER.b_to_a,
            crate::parser::passes::hir::semantic::parent::step::MATCH_ARM_OWNER.a_to_b_final,
            crate::parser::passes::hir::semantic::parent::step::MATCH_ARM_OWNER.finalize,
            "hir_match_arm_links",
            "hir_match_rank_prefix_00_local",
            HIR_MATCH_RANK_SCAN_UP,
            "hir_match_rank_compact_scatter",
            crate::parser::passes::hir::matches::arm::rank_step::A_TO_B,
            crate::parser::passes::hir::matches::arm::rank_step::B_TO_A,
            "hir_match_arm_scatter",
            "hir_canonical_match_arm_mark",
            "hir_canonical_match_arm_local",
            "hir_canonical_match_arm_prefix_01_blocks.up",
            "hir_canonical_match_arm_scatter",
            "hir_canonical_match_payload_mark",
            "hir_canonical_match_payload_local",
            "hir_canonical_match_payload_prefix_01_blocks.up",
            "hir_canonical_match_payload_scatter",
        ] {
            assert!(
                match_graph.pass_id(name).is_some(),
                "missing match-enabled parser operation {name}",
            );
        }

        let mut predicate_capacity = capacity;
        predicate_capacity.parser_feature_flags = crate::lexer::features::PARSER_FEATURE_PREDICATES;
        let predicate_graph = build_graph(predicate_capacity, &passes).unwrap();
        for name in [
            "hir_method_fields",
            "hir_method_signature_status",
            "hir_canonical_method_mark",
            "hir_canonical_method_local",
            "hir_canonical_method_prefix_01_blocks.up",
            "hir_canonical_method_scatter",
        ] {
            assert!(
                predicate_graph.pass_id(name).is_some(),
                "missing predicate-enabled parser operation {name}",
            );
        }
    }
}
