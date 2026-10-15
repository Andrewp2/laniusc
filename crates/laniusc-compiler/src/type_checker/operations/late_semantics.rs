use super::super::*;

/// The two semantic positions at which aggregate type relations are checked.
#[derive(Clone, Copy)]
pub(in crate::type_checker) enum AggregateComparisonStage {
    Calls,
    Final,
}

/// Aggregate arguments are compared through the complete checked type graph.
///
/// The scans, dispatch generation, and indirect comparison kernels share the
/// same physical resources. Graph invocations distinguish their two semantic
/// positions without rebuilding pipelines or bind groups.
pub(in crate::type_checker) struct AggregateComparisonOperation {
    _aggregate_dispatch_params: LaniusBuffer<CountDispatchParams>,
    aggregate_scan: PrefixScanOperation,
    aggregate_dispatch: ComputeOperation,
    aggregate_dispatch_calls: ComputeInvocation,
    aggregate_arguments: ComputeOperation,
    aggregate_arguments_calls: ComputeInvocation,
}

impl AggregateComparisonOperation {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        passes: &TypeCheckPasses,
        aggregate_dispatch_params: &LaniusBuffer<CountDispatchParams>,
        aggregate_dispatch_args: &LaniusBuffer<u32>,
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

        Ok(Self {
            _aggregate_dispatch_params: aggregate_dispatch_params.clone(),
            aggregate_scan,
            aggregate_dispatch,
            aggregate_dispatch_calls,
            aggregate_arguments,
            aggregate_arguments_calls,
        })
    }

    pub(in crate::type_checker) fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        stage: AggregateComparisonStage,
    ) -> Result<()> {
        let aggregate_scan_passes = match stage {
            AggregateComparisonStage::Calls => compiler_graph::AGGREGATE_CALL_SCAN_PASSES,
            AggregateComparisonStage::Final => compiler_graph::AGGREGATE_FINAL_SCAN_PASSES,
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
        Ok(())
    }
}

/// Late expression typing and compact semantic-artifact projection.
pub(in crate::type_checker) struct SemanticProjectionOperations {
    pub(in crate::type_checker) body_specialization: Vec<(u32, ComputeOperation)>,
    pub(in crate::type_checker) calls: ComputeOperation,
    pub(in crate::type_checker) generic_call_results: ComputeOperation,
    pub(in crate::type_checker) canonical_types: CanonicalTypeOperations,
    /// The rows of the IDs the late canonical stage added.
    pub(in crate::type_checker) late_row_seed: ComputeOperation,
    pub(in crate::type_checker) native_word_memo_clear: crate::gpu::operations::ClearBuffersOperation,
    pub(in crate::type_checker) generic_native_words: ComputeOperation,
    pub(in crate::type_checker) body_native_layout_admission: ComputeOperation,
    pub(in crate::type_checker) member_layout: ComputeOperation,
    pub(in crate::type_checker) retained_callables: CompactionOperation,
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
            body_specialization: [
                (
                    "type_check.body_specialization.graph",
                    "type_checker/type/instances/00e_seed_body_type_graph",
                ),
                (
                    "type_check.body_specialization.apply",
                    "type_checker/type/instances/00f_apply_body_specialization",
                ),
                (
                    "type_check.body_specialization.aggregates",
                    "type_checker/type/instances/01d_collect_aggregate_details",
                ),
                (
                    "type_check.body_specialization.constants",
                    "type_checker/type/instances/00g_apply_body_constants",
                ),
                (
                    "type_check.body_specialization.arguments",
                    "type_checker/type/instances/01e_collect_named_arg_refs",
                ),
                (
                    "type_check.body_specialization.declarations",
                    "type_checker/type/instances/01f_decl_refs",
                ),
                (
                    "type_check.body_specialization.bindings",
                    "type_checker/type/instances/01f_decl_refs",
                ),
                (
                    "type_check.body_specialization.clear_application_index",
                    "type_checker/type/instances/02b_clear_application_index",
                ),
                (
                    "type_check.body_specialization.index_applications",
                    "type_checker/type/instances/02c_index_closed_applications",
                ),
                (
                    "type_check.body_specialization.materialize_applications",
                    "type_checker/type/instances/02d_materialize_applications",
                ),
                (
                    "type_check.body_specialization.index_generated_applications",
                    "type_checker/type/instances/02c_index_closed_applications",
                ),
                (
                    "type_check.body_specialization.imported_fields",
                    "type_checker/type/instances/02e_project_imported_fields",
                ),
                (
                    "type_check.body_specialization.member_receivers",
                    "type_checker/type/instances/03a_member_receivers",
                ),
                (
                    "type_check.body_specialization.member_results",
                    "type_checker/type/instances/03_member_results",
                ),
                (
                    "type_check.body_specialization.member_substitute",
                    "type_checker/type/instances/03b_member_substitute",
                ),
                (
                    "type_check.body_specialization.literal_contexts",
                    "type_checker/type/instances/04a2_struct_init_contexts",
                ),
                (
                    "type_check.body_specialization.nested_literal_contexts",
                    "type_checker/type/instances/04a3_nested_struct_contexts",
                ),
                (
                    "type_check.body_specialization.literal_fields",
                    "type_checker/type/instances/04_struct_init_fields",
                ),
                (
                    "type_check.body_specialization.literal_substitute",
                    "type_checker/type/instances/04b_struct_init_substitute",
                ),
                (
                    "type_check.body_specialization.array_literal_refs",
                    "type_checker/type/instances/05b_array_literal_return_refs",
                ),
                (
                    compiler_graph::BODY_SPECIALIZATION_CANONICAL_REARM_PASS,
                    canonical_passes::CANONICAL_REARM_KERNEL,
                ),
                (
                    "type_check.body_specialization.payloads",
                    "type_checker/modules/10m2_type_match_payloads",
                ),
                (
                    "type_check.body_specialization.matches",
                    "type_checker/modules/10n_type_match_exprs",
                ),
                (
                    "type_check.body_specialization.predicates",
                    "type_checker/predicates/03_validate_body_obligations",
                ),
                (
                    "type_check.body_specialization.bound_members",
                    "type_checker/methods/09_route_bound_members",
                ),
            ]
            .into_iter()
            .flat_map(|(name, kernel)| {
                // Bind every accepted reference after installing the lexical
                // environment and before rebuilding application/layout facts.
                std::iter::once((name, kernel)).chain(
                    compiler_graph::BODY_REFERENCE_SPECIALIZATION_PASSES
                        .iter()
                        .filter(move |_| name == "type_check.body_specialization.apply")
                        .map(|&(name, _, _)| {
                            (name, compiler_graph::BODY_REFERENCE_SPECIALIZATION_KERNEL)
                        }),
                )
            })
            .map(|(name, kernel)| {
                // These relations are initialized only for the corresponding
                // parser feature. A reused workspace can contain unrelated
                // scratch in their slots when the feature is absent.
                let required_feature = if kernel.contains("struct_init")
                    || kernel.ends_with("04a3_nested_struct_contexts")
                {
                    crate::lexer::features::PARSER_FEATURE_STRUCTS
                } else if kernel.ends_with("03_validate_body_obligations") {
                    crate::lexer::features::PARSER_FEATURE_PREDICATES
                } else if kernel.ends_with("05b_array_literal_return_refs") {
                    crate::lexer::features::PARSER_FEATURE_ARRAYS
                } else {
                    0
                };
                let capacity = if let Some(&(_, tag_column, _)) =
                    compiler_graph::BODY_REFERENCE_SPECIALIZATION_PASSES
                        .iter()
                        .find(|&&(pass, _, _)| pass == name)
                {
                    let tags: LaniusBuffer<u32> =
                        typed_buffer_from_resources(resources, tag_column)?;
                    u32::try_from(tags.byte_size / 4)?
                } else if name == compiler_graph::BODY_SPECIALIZATION_CANONICAL_REARM_PASS {
                    let words = |name| -> Result<u32> {
                        Ok(u32::try_from(
                            typed_buffer_from_resources::<u32>(resources, name)?.byte_size / 4,
                        )?)
                    };
                    words("canonical_row")? + words("canonical_atom")? + words("canonical_projection")?
                } else if name == "type_check.body_specialization.constants" {
                    let instances: LaniusBuffer<u32> =
                        typed_buffer_from_resources(resources, "type_instance_kind")?;
                    u32::try_from(instances.byte_size / 4)?
                } else if kernel.starts_with("type_checker/type/instances/02")
                    || kernel.ends_with("09_route_bound_members")
                    || kernel.ends_with("03b_member_substitute")
                    || kernel.ends_with("04b_struct_init_substitute")
                {
                    let tokens: LaniusBuffer<u32> =
                        typed_buffer_from_resources(resources, "type_expr_ref_tag")?;
                    (tokens.byte_size / 4) as u32
                } else {
                    hir_capacity
                };
                ComputeOperation::direct(
                    device,
                    graph,
                    resources,
                    name,
                    &passes.kernel(kernel),
                    capacity,
                )
                .map(|operation| (required_feature, operation))
            })
            .collect::<Result<_>>()?,
            retained_callables: CompactionOperation::indirect(
                device,
                graph,
                resources,
                passes,
                compiler_graph::RETAINED_CALLABLE_COMPACTION,
                &typed_buffer_from_resources(resources, "hir_active_dispatch_args")?,
            )?,
            calls: direct(
                compiler_graph::SEMANTIC_CALLS_PROJECT_PASS,
                "type_checker/semantic/artifact/00_calls",
            )?,
            generic_call_results: direct(
                "type_check.semantic_artifact.generic_call_results",
                "type_checker/semantic/artifact/00c_generic_call_results",
            )?,
            canonical_types: CanonicalTypeOperations::new(device, graph, resources, passes)?,
            late_row_seed: {
                let words = |name| -> Result<u32> {
                    Ok(u32::try_from(
                        typed_buffer_from_resources::<u32>(resources, name)?.byte_size / 4,
                    )?)
                };
                ComputeOperation::direct(
                    device,
                    graph,
                    resources,
                    compiler_graph::SUBSTITUTION_LATE_SEED_PASS,
                    &passes.kernel(substitution_passes::SUBSTITUTION_SEED_KERNEL),
                    words("canonical_row")?
                        + words("canonical_atom")?
                        + words("canonical_projection")?,
                )?
            },
            native_word_memo_clear: {
                let memo: LaniusBuffer<u32> =
                    typed_buffer_from_resources(resources, "type_native_word_memo")?;
                crate::gpu::operations::ClearBuffersOperation::new(
                    graph,
                    compiler_graph::SEMANTIC_NATIVE_WORD_MEMO_CLEAR_PASS,
                    &[("type_native_word_memo", (&memo).into())],
                )?
            },
            generic_native_words: ComputeOperation::direct(
                device,
                graph,
                resources,
                "type_check.semantic_artifact.generic_native_words",
                &passes.kernel("type_checker/semantic/artifact/01c_generic_native_words"),
                u32::try_from(
                    typed_buffer_from_resources::<u32>(resources, "type_expr_ref_tag")?.byte_size
                        / 4,
                )?,
            )?,
            body_native_layout_admission: ComputeOperation::direct(
                device,
                graph,
                resources,
                "type_check.body_specialization.native_layout_admission",
                &passes.kernel("type_checker/semantic/artifact/01c2_validate_body_native_layout"),
                generic_body::MAX_BODY_TYPE_NODES as u32,
            )?,
            expression_types_init: direct(
                compiler_graph::INIT_PASS,
                "type_checker/semantic/expression_types/00_init",
            )?,
            member_layout: direct(
                "type_check.semantic_artifact.member_layout",
                "type_checker/semantic/artifact/01d_member_layout",
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

/// Hash-consed canonical type identities (docs/canonical-type-ids.md).
///
/// Three stages share one table, cleared ahead of the dependency pages. The
/// dependency stage interns the resident page's signature types, once per
/// page; the early stage interns the declared rows and constants ahead of
/// the closed application index; the late stage interns what later
/// producers added. The early and late stages first re-arm the candidates
/// that are still empty or unknown. Each stage records round 0, then
/// batches of frontier rounds (indirect dispatches sized on the GPU); every
/// batch ends with a copy of the interning counters, and the host records
/// another batch only while candidates are pending, so the number of rounds
/// is the maximum candidate height.
pub(in crate::type_checker) struct CanonicalTypeOperations {
    clear: ComputeOperation,
    rearm: ComputeOperation,
    round0: ComputeOperation,
    round_args: ComputeOperation,
    round: ComputeOperation,
    counts_readback: crate::gpu::operations::CopyBufferOperation,
    late_round0: ComputeInvocation,
    late_round_args: ComputeInvocation,
    late_round: ComputeInvocation,
    late_counts_readback: crate::gpu::operations::CopyBufferOperation,
    early_rearm: ComputeInvocation,
    dependency_begin: ComputeOperation,
    dependency_round0: ComputeOperation,
    dependency_round_args: ComputeInvocation,
    dependency_round: ComputeOperation,
    dependency_counts_readback: crate::gpu::operations::CopyBufferOperation,
    validate: Vec<ComputeOperation>,
    validation_readback: Option<crate::gpu::operations::CopyBufferOperation>,
    /// Records (`ct_head` rows), argument words (`ct_args`), and the
    /// entries of one frontier list (half of `canonical_frontier`).
    capacity: [u32; 3],
}

/// Which interning stage to record.
#[derive(Clone, Copy, PartialEq, Eq)]
pub(in crate::type_checker) enum CanonicalStage {
    Dependency,
    Early,
    Late,
}

impl CanonicalStage {
    pub(in crate::type_checker) fn label(self) -> &'static str {
        match self {
            Self::Dependency => "dependency",
            Self::Early => "early",
            Self::Late => "late",
        }
    }
}

impl CanonicalTypeOperations {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        passes: &TypeCheckPasses,
    ) -> Result<Self> {
        let words = |name| -> Result<u32> {
            Ok(u32::try_from(typed_buffer_from_resources::<u32>(resources, name)?.byte_size / 4)?)
        };
        let candidates =
            words("canonical_row")? + words("canonical_atom")? + words("canonical_projection")?;
        let direct = |name, kernel, elements| {
            ComputeOperation::direct(device, graph, resources, name, &passes.kernel(kernel), elements)
        };
        let counts_copy = |name| {
            crate::gpu::operations::CopyBufferOperation::new(
                graph,
                name,
                "ct_counts",
                &typed_buffer_from_resources::<u32>(resources, "ct_counts")?,
                0,
                "canonical_counts_readback",
                &typed_buffer_from_resources::<u32>(resources, "canonical_counts_readback")?,
                0,
                canonical_passes::CANONICAL_COUNT_WORDS as u64 * 4,
            )
        };
        let early = &canonical_passes::CANONICAL_EARLY_ROUNDS;
        let late = &canonical_passes::CANONICAL_LATE_ROUNDS;
        let dependency_rows = words("canonical_dependency_type")?;
        let clear = direct(
            canonical_passes::CANONICAL_CLEAR_PASS,
            canonical_passes::CANONICAL_CLEAR_KERNEL,
            words("ct_slot")?
                .max(candidates)
                .max(dependency_rows)
                .max(canonical_passes::CANONICAL_VALIDATION_WORDS as u32),
        )?;
        let rearm = direct(
            canonical_passes::CANONICAL_REARM_PASS,
            canonical_passes::CANONICAL_REARM_KERNEL,
            candidates,
        )?;
        let round0 = direct(early.round0, canonical_passes::CANONICAL_INTERN_KERNEL, candidates)?;
        let round_args = direct(early.round_args, canonical_passes::CANONICAL_ROUND_ARGS_KERNEL, 1)?;
        let round = ComputeOperation::indirect(
            device,
            graph,
            resources,
            early.round,
            &passes.kernel(canonical_passes::CANONICAL_INTERN_KERNEL),
            &typed_buffer_from_resources(resources, "canonical_round_args")?,
        )?;
        let counts_readback = counts_copy(early.counts_readback)?;
        let late_round0 = round0.invocation(graph, late.round0)?;
        let late_round_args = round_args.invocation(graph, late.round_args)?;
        let late_round = round.invocation(graph, late.round)?;
        let late_counts_readback = counts_copy(late.counts_readback)?;
        let early_rearm = rearm.invocation(graph, canonical_passes::CANONICAL_EARLY_REARM_PASS)?;
        let dependency = &canonical_passes::CANONICAL_DEPENDENCY_ROUNDS;
        // Round 0 covers the largest page; lanes past the page's nodes exit.
        let page_rows = words("dependency_canonical_type_roots_a")?;
        let dependency_begin = direct(
            canonical_passes::CANONICAL_DEPENDENCY_BEGIN_PASS,
            canonical_passes::CANONICAL_DEPENDENCY_BEGIN_KERNEL,
            1,
        )?;
        let dependency_round0 = direct(
            dependency.round0,
            canonical_passes::CANONICAL_DEPENDENCY_INTERN_KERNEL,
            page_rows,
        )?;
        let dependency_round_args = round_args.invocation(graph, dependency.round_args)?;
        let dependency_round = ComputeOperation::indirect(
            device,
            graph,
            resources,
            dependency.round,
            &passes.kernel(canonical_passes::CANONICAL_DEPENDENCY_INTERN_KERNEL),
            &typed_buffer_from_resources(resources, "canonical_round_args")?,
        )?;
        let dependency_counts_readback = counts_copy(dependency.counts_readback)?;
        let validation_readback = if canonical_passes::canonical_validation_enabled() {
            Some(crate::gpu::operations::CopyBufferOperation::new(
                graph,
                canonical_passes::CANONICAL_VALIDATION_READBACK_PASS,
                "canonical_validation",
                &typed_buffer_from_resources::<u32>(resources, "canonical_validation")?,
                0,
                "canonical_validation_readback",
                &typed_buffer_from_resources::<u32>(resources, "canonical_validation_readback")?,
                0,
                canonical_passes::CANONICAL_VALIDATION_WORDS as u64 * 4,
            )?)
        } else {
            None
        };
        let validate = if canonical_passes::canonical_validation_enabled() {
            vec![
                direct(
                    canonical_passes::CANONICAL_VALIDATE_PASS,
                    canonical_passes::CANONICAL_VALIDATE_KERNEL,
                    words("ct_slot")?
                        .max(candidates)
                        .max(dependency_rows)
                        .max(words("canonical_crosscheck_links")?)
                        .max(words("canonical_crosscheck_owner")?),
                )?,
                direct(
                    canonical_passes::CANONICAL_CROSSCHECK_BUCKETS_PASS,
                    canonical_passes::CANONICAL_CROSSCHECK_BUCKETS_KERNEL,
                    words("canonical_row")?,
                )?,
                direct(
                    canonical_passes::CANONICAL_CROSSCHECK_PASS,
                    canonical_passes::CANONICAL_CROSSCHECK_KERNEL,
                    words("canonical_row")?,
                )?,
            ]
        } else {
            Vec::new()
        };
        Ok(Self {
            clear,
            rearm,
            round0,
            round_args,
            round,
            counts_readback,
            late_round0,
            late_round_args,
            late_round,
            late_counts_readback,
            early_rearm,
            dependency_begin,
            dependency_round0,
            dependency_round_args,
            dependency_round,
            dependency_counts_readback,
            validate,
            validation_readback,
            capacity: [
                words("ct_head")? / 4,
                words("ct_args")?,
                words("canonical_frontier")? / 2,
            ],
        })
    }

    /// Records, argument words and frontier list entries of the canonical
    /// table.
    pub(in crate::type_checker) fn capacity(&self) -> [u32; 3] {
        self.capacity
    }

    fn record_round(&self, encoder: &mut wgpu::CommandEncoder, stage: CanonicalStage) -> Result<()> {
        match stage {
            CanonicalStage::Dependency => {
                self.dependency_round.record(encoder)?;
                self.round_args.record_invocation(encoder, &self.dependency_round_args)
            }
            CanonicalStage::Early => {
                self.round.record(encoder)?;
                self.round_args.record(encoder)
            }
            CanonicalStage::Late => {
                self.round.record_invocation(encoder, &self.late_round)?;
                self.round_args.record_invocation(encoder, &self.late_round_args)
            }
        }
    }

    fn record_counts_readback(&self, encoder: &mut wgpu::CommandEncoder, stage: CanonicalStage) {
        match stage {
            CanonicalStage::Dependency => self.dependency_counts_readback.record(encoder),
            CanonicalStage::Early => self.counts_readback.record(encoder),
            CanonicalStage::Late => self.late_counts_readback.record(encoder),
        }
    }

    /// Clears the table, ahead of the dependency pages.
    pub(in crate::type_checker) fn record_clear(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.clear.record(encoder)
    }

    /// Records the stage's start (the page's begin, or the re-arm) and its
    /// first batch: round 0 and frontier rounds.
    pub(in crate::type_checker) fn record_first_batch(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        stage: CanonicalStage,
    ) -> Result<()> {
        match stage {
            CanonicalStage::Dependency => {
                self.dependency_begin.record(encoder)?;
                self.dependency_round0.record(encoder)?;
                self.round_args.record_invocation(encoder, &self.dependency_round_args)?;
            }
            CanonicalStage::Early => {
                self.rearm.record_invocation(encoder, &self.early_rearm)?;
                self.round0.record(encoder)?;
                self.round_args.record(encoder)?;
            }
            CanonicalStage::Late => {
                self.rearm.record(encoder)?;
                self.round0.record_invocation(encoder, &self.late_round0)?;
                self.round_args.record_invocation(encoder, &self.late_round_args)?;
            }
        }
        for _ in 1..canonical_passes::CANONICAL_ROUNDS_PER_BATCH {
            self.record_round(encoder, stage)?;
        }
        self.record_counts_readback(encoder, stage);
        Ok(())
    }

    /// Records one more batch of frontier rounds after a readback that still
    /// reported pending candidates.
    pub(in crate::type_checker) fn record_batch(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        stage: CanonicalStage,
    ) -> Result<()> {
        for _ in 0..canonical_passes::CANONICAL_ROUNDS_PER_BATCH {
            self.record_round(encoder, stage)?;
        }
        self.record_counts_readback(encoder, stage);
        Ok(())
    }

    /// Debug validation (`LANIUS_DEBUG_VALIDATE_CANONICAL=1`).
    pub(in crate::type_checker) fn record_validation(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        for operation in &self.validate {
            operation.record(encoder)?;
        }
        if let Some(readback) = &self.validation_readback {
            readback.record(encoder);
        }
        Ok(())
    }
}
