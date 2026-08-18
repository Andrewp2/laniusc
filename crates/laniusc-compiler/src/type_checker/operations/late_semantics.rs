use super::super::*;

/// The two semantic positions at which aggregate type relations are checked.
#[derive(Clone, Copy)]
pub(in crate::type_checker) enum AggregateComparisonStage {
    Calls,
    Final,
}

/// Aggregate and type-subtree comparison as one graph-owned algorithm.
///
/// The scans, dispatch generation, and indirect comparison kernels share the
/// same physical resources. Graph invocations distinguish their two semantic
/// positions without rebuilding pipelines or bind groups.
pub(in crate::type_checker) struct AggregateComparisonOperation {
    _aggregate_dispatch_params: LaniusBuffer<CountDispatchParams>,
    _subtree_dispatch_params: LaniusBuffer<CountDispatchParams>,
    aggregate_scan: PrefixScanOperation,
    aggregate_dispatch: ComputeOperation,
    aggregate_dispatch_calls: ComputeInvocation,
    aggregate_arguments: ComputeOperation,
    aggregate_arguments_calls: ComputeInvocation,
    subtree_scan: PrefixScanOperation,
    subtree_dispatch: ComputeOperation,
    subtree_dispatch_calls: ComputeInvocation,
    subtree_compare: ComputeOperation,
    subtree_compare_calls: ComputeInvocation,
}

impl AggregateComparisonOperation {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        passes: &TypeCheckPasses,
        aggregate_dispatch_params: &LaniusBuffer<CountDispatchParams>,
        aggregate_dispatch_args: &LaniusBuffer<u32>,
        subtree_dispatch_params: &LaniusBuffer<CountDispatchParams>,
        subtree_dispatch_args: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        let aggregate_scan = PrefixScanOperation::from_resource_names(
            device,
            "type_check.conditions.aggregate_compare_scan",
            compiler_graph::AGGREGATE_FINAL_SCAN_PASSES,
            passes,
            resources,
            compiler_graph::AGGREGATE_SCAN_RESOURCES,
        )?;
        let aggregate_dispatch = ComputeOperation::direct_with_uniform(
            device,
            graph,
            resources,
            compiler_graph::AGGREGATE_FINAL_DISPATCH_PASS,
            &passes.kernel("type_checker/count/dispatch_args"),
            aggregate_dispatch_params,
            1,
        )?;
        let aggregate_dispatch_calls =
            aggregate_dispatch.invocation(graph, compiler_graph::AGGREGATE_CALL_DISPATCH_PASS)?;
        let aggregate_arguments = ComputeOperation::indirect(
            device,
            graph,
            resources,
            compiler_graph::CONDITIONS_AGGREGATE_ARGS_FINAL_PASS,
            &passes.kernel("type_checker/conditions/aggregate_args"),
            aggregate_dispatch_args,
        )?;
        let aggregate_arguments_calls = aggregate_arguments
            .invocation(graph, compiler_graph::CONDITIONS_AGGREGATE_ARGS_CALLS_PASS)?;

        let subtree_scan = PrefixScanOperation::from_resource_names(
            device,
            "type_check.conditions.type_subtree_compare_scan",
            compiler_graph::TYPE_SUBTREE_FINAL_SCAN_PASSES,
            passes,
            resources,
            compiler_graph::TYPE_SUBTREE_SCAN_RESOURCES,
        )?;
        let subtree_dispatch = ComputeOperation::direct_with_uniform(
            device,
            graph,
            resources,
            compiler_graph::TYPE_SUBTREE_FINAL_DISPATCH_PASS,
            &passes.kernel("type_checker/count/dispatch_args"),
            subtree_dispatch_params,
            1,
        )?;
        let subtree_dispatch_calls =
            subtree_dispatch.invocation(graph, compiler_graph::TYPE_SUBTREE_CALL_DISPATCH_PASS)?;
        let subtree_compare = ComputeOperation::indirect(
            device,
            graph,
            resources,
            compiler_graph::TYPE_SUBTREE_FINAL_INDIRECT_PASS,
            &passes.kernel("type_checker/conditions/type_subtree"),
            subtree_dispatch_args,
        )?;
        let subtree_compare_calls =
            subtree_compare.invocation(graph, compiler_graph::TYPE_SUBTREE_CALL_INDIRECT_PASS)?;

        Ok(Self {
            _aggregate_dispatch_params: aggregate_dispatch_params.clone(),
            _subtree_dispatch_params: subtree_dispatch_params.clone(),
            aggregate_scan,
            aggregate_dispatch,
            aggregate_dispatch_calls,
            aggregate_arguments,
            aggregate_arguments_calls,
            subtree_scan,
            subtree_dispatch,
            subtree_dispatch_calls,
            subtree_compare,
            subtree_compare_calls,
        })
    }

    pub(in crate::type_checker) fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        stage: AggregateComparisonStage,
    ) -> Result<()> {
        let (aggregate_scan_passes, subtree_scan_passes) = match stage {
            AggregateComparisonStage::Calls => (
                compiler_graph::AGGREGATE_CALL_SCAN_PASSES,
                compiler_graph::TYPE_SUBTREE_CALL_SCAN_PASSES,
            ),
            AggregateComparisonStage::Final => (
                compiler_graph::AGGREGATE_FINAL_SCAN_PASSES,
                compiler_graph::TYPE_SUBTREE_FINAL_SCAN_PASSES,
            ),
        };
        self.aggregate_scan
            .record_with_graph_passes(encoder, aggregate_scan_passes)?;
        match stage {
            AggregateComparisonStage::Calls => {
                self.aggregate_dispatch
                    .record_invocation(encoder, &self.aggregate_dispatch_calls)?;
                self.aggregate_arguments
                    .record_invocation(encoder, &self.aggregate_arguments_calls)?;
            }
            AggregateComparisonStage::Final => {
                self.aggregate_dispatch.record(encoder)?;
                self.aggregate_arguments.record(encoder)?;
            }
        }
        self.subtree_scan
            .record_with_graph_passes(encoder, subtree_scan_passes)?;
        match stage {
            AggregateComparisonStage::Calls => {
                self.subtree_dispatch
                    .record_invocation(encoder, &self.subtree_dispatch_calls)?;
                self.subtree_compare
                    .record_invocation(encoder, &self.subtree_compare_calls)
            }
            AggregateComparisonStage::Final => {
                self.subtree_dispatch.record(encoder)?;
                self.subtree_compare.record(encoder)
            }
        }
    }
}

/// Late expression typing and compact semantic-artifact projection.
pub(in crate::type_checker) struct SemanticProjectionOperations {
    pub(in crate::type_checker) calls: ComputeOperation,
    pub(in crate::type_checker) expression_types_init: ComputeOperation,
    pub(in crate::type_checker) expression_refs: ComputeOperation,
    pub(in crate::type_checker) struct_literal_refs_early_clear:
        crate::gpu::operations::ClearBuffersOperation,
    pub(in crate::type_checker) struct_literal_refs: ComputeOperation,
    pub(in crate::type_checker) struct_literal_refs_early: ComputeInvocation,
    pub(in crate::type_checker) array_index_refs: ComputeOperation,
    pub(in crate::type_checker) compact_expr: ComputeOperation,
    pub(in crate::type_checker) compact_stmt: ComputeOperation,
    pub(in crate::type_checker) compact_aggregate_requests: ComputeOperation,
    pub(in crate::type_checker) artifact: ComputeOperation,
    pub(in crate::type_checker) local_const_literals: ComputeOperation,
    pub(in crate::type_checker) local_const_references: ComputeOperation,
}

impl SemanticProjectionOperations {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        passes: &TypeCheckPasses,
        hir_capacity: u32,
    ) -> Result<Self> {
        let direct = |name, kernel| {
            ComputeOperation::direct(
                device,
                graph,
                resources,
                name,
                &passes.kernel(kernel),
                hir_capacity,
            )
        };
        let struct_literal_refs = direct(
            compiler_graph::SEMANTIC_STRUCT_LITERAL_REFS_PROJECT_PASS,
            "type_checker/semantic/artifact/01a_struct_literal_refs",
        )?;
        let struct_literal_refs_early = struct_literal_refs.invocation(
            graph,
            compiler_graph::SEMANTIC_STRUCT_LITERAL_REFS_EARLY_PROJECT_PASS,
        )?;
        let semantic_expr_ref_tag_by_hir: LaniusBuffer<u32> =
            typed_buffer_from_resources(resources, "semantic_expr_ref_tag_by_hir")?;
        let semantic_expr_ref_payload_by_hir: LaniusBuffer<u32> =
            typed_buffer_from_resources(resources, "semantic_expr_ref_payload_by_hir")?;
        let semantic_aggregate_decl_token_by_hir: LaniusBuffer<u32> =
            typed_buffer_from_resources(resources, "semantic_aggregate_decl_token_by_hir")?;
        let struct_literal_refs_early_clear = crate::gpu::operations::ClearBuffersOperation::new(
            graph,
            compiler_graph::SEMANTIC_STRUCT_LITERAL_REFS_EARLY_CLEAR_PASS,
            &[
                (
                    "semantic_expr_ref_tag_by_hir",
                    (&semantic_expr_ref_tag_by_hir).into(),
                ),
                (
                    "semantic_expr_ref_payload_by_hir",
                    (&semantic_expr_ref_payload_by_hir).into(),
                ),
                (
                    "semantic_aggregate_decl_token_by_hir",
                    (&semantic_aggregate_decl_token_by_hir).into(),
                ),
            ],
        )?;
        Ok(Self {
            calls: direct(
                compiler_graph::SEMANTIC_CALLS_PROJECT_PASS,
                "type_checker/semantic/artifact/00_calls",
            )?,
            expression_types_init: direct(
                compiler_graph::INIT_PASS,
                "type_checker/semantic/expression_types/00_init",
            )?,
            expression_refs: direct(
                compiler_graph::SEMANTIC_EXPRESSION_REFS_PROJECT_PASS,
                "type_checker/semantic/artifact/01_expression_refs",
            )?,
            struct_literal_refs_early_clear,
            struct_literal_refs,
            struct_literal_refs_early,
            array_index_refs: direct(
                compiler_graph::SEMANTIC_ARRAY_INDEX_REFS_PROJECT_PASS,
                "type_checker/semantic/artifact/01b_array_index_refs",
            )?,
            compact_expr: direct(
                compiler_graph::CONDITIONS_COMPACT_EXPR_PASS,
                "type_checker/conditions/compact_expr",
            )?,
            compact_stmt: direct(
                compiler_graph::CONDITIONS_COMPACT_STMT_PASS,
                "type_checker/conditions/compact_stmt",
            )?,
            compact_aggregate_requests: direct(
                compiler_graph::CONDITIONS_COMPACT_AGGREGATE_REQUESTS_PASS,
                "type_checker/conditions/compact_aggregate_requests",
            )?,
            artifact: direct(
                compiler_graph::SEMANTIC_ARTIFACT_PROJECT_PASS,
                "type_checker/semantic/artifact/00_project",
            )?,
            local_const_literals: direct(
                compiler_graph::SEMANTIC_LOCAL_CONST_LITERALS_PROJECT_PASS,
                "type_checker/semantic/artifact/00a_local_const_literals",
            )?,
            local_const_references: direct(
                compiler_graph::SEMANTIC_LOCAL_CONST_REFERENCES_PROJECT_PASS,
                "type_checker/semantic/artifact/00b_local_const_references",
            )?,
        })
    }
}
