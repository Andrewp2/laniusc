use anyhow::Result;

use super::{super::*, inputs::CreateInputs};

/// Bind groups for projecting resolved paths into semantic type/value facts.
///
/// This is the bridge from module lookup tables to the rest of type checking:
/// type paths become type refs, value paths become call/const/enum facts, and
/// match patterns get bound to enum payload rows.
pub(in crate::type_checker) struct ProjectionBindGroups {
    pub(in crate::type_checker) clear_type_path_types: ComputeOperation,
    pub(in crate::type_checker) project_type_paths: ComputeOperation,
    pub(in crate::type_checker) project_type_paths_after_aliases: ComputeInvocation,
    pub(in crate::type_checker) project_type_paths_after_projected_aliases: ComputeInvocation,
    pub(in crate::type_checker) project_type_paths_after_alias_equivalence: ComputeInvocation,
    pub(in crate::type_checker) validate_type_paths: ComputeOperation,
    pub(in crate::type_checker) type_aliases: Option<Box<TypeAliasProjection>>,
    pub(in crate::type_checker) project_type_instances: ComputeOperation,
    pub(in crate::type_checker) mark_value_call_paths: ComputeOperation,
    pub(in crate::type_checker) project_value_paths: ComputeOperation,
    pub(in crate::type_checker) consume_value_calls: ComputeOperation,
    pub(in crate::type_checker) consume_value_calls_after_methods: ComputeInvocation,
    pub(in crate::type_checker) mirror_value_call_leaf: ComputeOperation,
    pub(in crate::type_checker) mirror_value_call_leaf_after_row_args: ComputeInvocation,
    pub(in crate::type_checker) mirror_value_call_leaf_after_methods: ComputeInvocation,
    pub(in crate::type_checker) mirror_value_call_leaf_after_method_row_args: ComputeInvocation,
    pub(in crate::type_checker) consume_value_consts: ComputeOperation,
    pub(in crate::type_checker) consume_value_enum_units: ComputeOperation,
    pub(in crate::type_checker) consume_value_enum_calls: ComputeOperation,
    pub(in crate::type_checker) validate_value_enum_call_payloads: ComputeOperation,
    pub(in crate::type_checker) finalize_value_enum_calls: ComputeOperation,
    pub(in crate::type_checker) bind_match_patterns: ComputeOperation,
    pub(in crate::type_checker) type_match_payloads: ComputeOperation,
    pub(in crate::type_checker) type_match_exprs: ComputeOperation,
}

/// Parallel root discovery and projection resources for local type aliases.
///
/// The ping-pong roots collapse declaration-only alias chains by pointer
/// jumping. Keeping this family boxed avoids adding another large resident
/// resource group to module-path construction's stack frame.
pub(in crate::type_checker) struct TypeAliasProjection {
    clear_forwarding: ComputeOperation,
    init_forwarding: ComputeOperation,
    validate_forwarding_args: ComputeOperation,
    init_roots: ComputeOperation,
    jump_a_to_b: Option<ComputeOperation>,
    jump_b_to_a: Option<ComputeOperation>,
    final_jump_a_to_b: Option<ComputeInvocation>,
    jump_rounds: u32,
    clear_equivalence: ComputeOperation,
    init_decl_edges: ComputeOperation,
    init_arg_edges: ComputeOperation,
    hook_equivalence_a: ComputeOperation,
    hook_equivalence_b: Option<ComputeOperation>,
    jump_equivalence_a_to_b: ComputeOperation,
    jump_equivalence_b_to_a: Option<ComputeOperation>,
    final_hook_equivalence_a: Option<ComputeInvocation>,
    final_jump_equivalence_a_to_b: Option<ComputeInvocation>,
    equivalence_rounds: u32,
    select_generic_sources: ComputeOperation,
    select_concrete_sources: ComputeOperation,
    finalize_equivalence: ComputeOperation,
    project_instances: ComputeOperation,
    project: ComputeOperation,
    project_after_projected_refs: ComputeInvocation,
    _root_a: LaniusBuffer<u32>,
    _root_b: LaniusBuffer<u32>,
    _forwarding: LaniusBuffer<u32>,
    _forwarding_target_decl: LaniusBuffer<u32>,
    _forwarding_valid_arg_count: LaniusBuffer<u32>,
    _decl_by_target_hir: LaniusBuffer<u32>,
    _equiv_parent_a: LaniusBuffer<u32>,
    _equiv_parent_b: LaniusBuffer<u32>,
    _equiv_edge_0: LaniusBuffer<u32>,
    _equiv_edge_1: LaniusBuffer<u32>,
    _equiv_component_source: LaniusBuffer<u32>,
    _normalized_source: LaniusBuffer<u32>,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) enum TypeAliasProjectStage {
    Initial,
    AfterProjectedRefs,
}

impl TypeAliasProjection {
    pub(in crate::type_checker) fn record_roots(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        self.clear_forwarding.record(encoder)?;
        self.init_forwarding.record(encoder)?;
        self.validate_forwarding_args.record(encoder)?;
        self.init_roots.record(encoder)?;
        for round in 0..self.jump_rounds {
            let a_to_b = self
                .jump_a_to_b
                .as_ref()
                .expect("an A-to-B operation exists whenever alias-root rounds are recorded");
            if round + 1 == self.jump_rounds && self.jump_rounds % 2 != 0 {
                if let Some(final_invocation) = &self.final_jump_a_to_b {
                    a_to_b.record_invocation(encoder, final_invocation)?;
                } else {
                    a_to_b.record(encoder)?;
                }
            } else if round % 2 == 0 {
                a_to_b.record(encoder)?;
            } else {
                self.jump_b_to_a
                    .as_ref()
                    .expect("a B-to-A operation exists for multi-round alias roots")
                    .record(encoder)?;
            }
        }
        Ok(())
    }

    pub(in crate::type_checker) fn record_equivalence(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        self.clear_equivalence.record(encoder)?;
        self.init_decl_edges.record(encoder)?;
        self.init_arg_edges.record(encoder)?;
        for round in 0..self.equivalence_rounds {
            let final_odd =
                round + 1 == self.equivalence_rounds && self.equivalence_rounds % 2 != 0;
            if final_odd {
                if let (Some(hook), Some(jump)) = (
                    &self.final_hook_equivalence_a,
                    &self.final_jump_equivalence_a_to_b,
                ) {
                    self.hook_equivalence_a.record_invocation(encoder, hook)?;
                    self.jump_equivalence_a_to_b
                        .record_invocation(encoder, jump)?;
                } else {
                    self.hook_equivalence_a.record(encoder)?;
                    self.jump_equivalence_a_to_b.record(encoder)?;
                }
            } else if round % 2 == 0 {
                self.hook_equivalence_a.record(encoder)?;
                self.jump_equivalence_a_to_b.record(encoder)?;
            } else {
                self.hook_equivalence_b
                    .as_ref()
                    .expect("a B hook exists for multi-round alias equivalence")
                    .record(encoder)?;
                self.jump_equivalence_b_to_a
                    .as_ref()
                    .expect("a B-to-A jump exists for multi-round alias equivalence")
                    .record(encoder)?;
            }
        }
        self.select_generic_sources.record(encoder)?;
        self.select_concrete_sources.record(encoder)?;
        self.finalize_equivalence.record(encoder)
    }

    pub(in crate::type_checker) fn record_projection(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        stage: TypeAliasProjectStage,
    ) -> Result<()> {
        match stage {
            TypeAliasProjectStage::Initial => self.project.record(encoder),
            TypeAliasProjectStage::AfterProjectedRefs => self
                .project
                .record_invocation(encoder, &self.project_after_projected_refs),
        }
    }

    pub(in crate::type_checker) fn record_instances(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        self.project_instances.record(encoder)
    }
}

/// Creates bind groups for path projection and value/type path validation.
pub(in crate::type_checker) fn create_projection_bind_groups(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    inputs: &CreateInputs<'_>,
    resources: &ResourceMap<'_>,
) -> Result<ProjectionBindGroups> {
    let clear_type_path_types = ComputeOperation::direct_spec(
        device,
        graph,
        resources,
        passes,
        TYPE_PATH_STATE_CLEAR,
        inputs.token_capacity.max(1),
    )?;
    let path_dispatch_args = graph.u32_buffer("path_dispatch_args")?;
    let project_type_paths = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        TYPE_PATHS_PROJECT,
        &path_dispatch_args,
    )?;
    let project_type_paths_after_aliases =
        project_type_paths.invocation(graph, TYPE_PATHS_PROJECT_AFTER_ALIASES.name)?;
    let project_type_paths_after_projected_aliases =
        project_type_paths.invocation(graph, TYPE_PATHS_PROJECT_AFTER_PROJECTED_ALIASES.name)?;
    let project_type_paths_after_alias_equivalence =
        project_type_paths.invocation(graph, TYPE_PATHS_PROJECT_AFTER_ALIAS_EQUIVALENCE.name)?;
    let validate_type_paths = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        TYPE_PATHS_VALIDATE,
        &path_dispatch_args,
    )?;
    let aliases_required = type_alias_passes_required(inputs.hir_items.parser_feature_flags);
    let type_aliases = if aliases_required {
        let alias_root_capacity = if aliases_required {
            inputs.hir_items.module_record_capacity.max(1)
        } else {
            1
        };
        let alias_root_a = graph.u32_buffer("alias_root_a")?;
        let alias_root_b = graph.u32_buffer("alias_root_b")?;
        let alias_forwarding = graph.u32_buffer("alias_forwarding")?;
        let alias_forwarding_target_decl = graph.u32_buffer("alias_forwarding_target_decl")?;
        let alias_forwarding_valid_arg_count =
            graph.u32_buffer("alias_forwarding_valid_arg_count")?;
        let alias_decl_by_target_hir = graph.u32_buffer("alias_decl_by_target_hir")?;
        let alias_equiv_capacity = if aliases_required {
            inputs
                .token_capacity
                .saturating_add(inputs.hir_node_capacity)
                .max(1)
        } else {
            1
        };
        let alias_equiv_parent_a = graph.u32_buffer("alias_equiv_parent_a")?;
        let alias_equiv_parent_b = graph.u32_buffer("alias_equiv_parent_b")?;
        // Forwarding is consumed by root initialization before equivalence graph
        // construction begins. Rebuild those same HIR-wide rows as the two graph
        // edges and the durable normalized source table.
        let alias_equiv_edge_0 = alias_forwarding.clone();
        let alias_equiv_edge_1 = alias_forwarding_target_decl.clone();
        let alias_equiv_component_source = graph.u32_buffer("alias_equiv_component_source")?;
        let alias_normalized_source = alias_forwarding_valid_arg_count.clone();
        let mut alias_resources = resources.clone();
        alias_resources.buffer("alias_forwarding", &alias_forwarding);
        alias_resources.buffer(
            "alias_forwarding_target_decl",
            &alias_forwarding_target_decl,
        );
        alias_resources.buffer(
            "alias_forwarding_valid_arg_count",
            &alias_forwarding_valid_arg_count,
        );
        alias_resources.buffer("alias_decl_by_target_hir", &alias_decl_by_target_hir);
        alias_resources.buffer("alias_source_hir_by_target_hir", &alias_decl_by_target_hir);
        alias_resources.buffer("alias_equiv_parent_a", &alias_equiv_parent_a);
        alias_resources.buffer("alias_equiv_parent_b", &alias_equiv_parent_b);
        alias_resources.buffer("alias_equiv_edge_0", &alias_equiv_edge_0);
        alias_resources.buffer("alias_equiv_edge_1", &alias_equiv_edge_1);
        alias_resources.buffer(
            "alias_equiv_component_source",
            &alias_equiv_component_source,
        );
        alias_resources.buffer("alias_normalized_source", &alias_normalized_source);

        let hir_work = inputs.hir_node_capacity.max(1);
        let decl_key_radix_dispatch_args = graph.u32_buffer("decl_key_radix_dispatch_args")?;
        let clear_type_alias_forwarding = ComputeOperation::direct_spec(
            device,
            graph,
            &alias_resources,
            passes,
            TYPE_ALIAS_FORWARDING_CLEAR,
            hir_work,
        )?;
        let init_type_alias_forwarding = ComputeOperation::indirect_spec(
            device,
            graph,
            &alias_resources,
            passes,
            TYPE_ALIAS_FORWARDING_INITIALIZE,
            &decl_key_radix_dispatch_args,
        )?;
        let validate_type_alias_forwarding_args = ComputeOperation::direct_spec(
            device,
            graph,
            &alias_resources,
            passes,
            TYPE_ALIAS_FORWARDING_VALIDATE,
            hir_work,
        )?;
        let init_type_alias_roots = ComputeOperation::indirect_spec(
            device,
            graph,
            &alias_resources,
            passes,
            TYPE_ALIAS_ROOT_INITIALIZE,
            &decl_key_radix_dispatch_args,
        )?;
        let mut alias_root_jump_rounds = 0;
        let mut alias_root_covered_nodes = 1u64;
        while alias_root_covered_nodes < u64::from(alias_root_capacity) {
            alias_root_jump_rounds += 1;
            alias_root_covered_nodes = alias_root_covered_nodes.saturating_mul(16);
        }
        let jump_type_alias_roots_a_to_b = if alias_root_jump_rounds == 0 {
            None
        } else {
            let spec = if alias_root_jump_rounds == 1 {
                TYPE_ALIAS_ROOT_JUMP_FINAL_A_TO_B
            } else {
                TYPE_ALIAS_ROOT_JUMP_A_TO_B
            };
            Some(ComputeOperation::indirect_spec(
                device,
                graph,
                &alias_resources,
                passes,
                spec,
                &decl_key_radix_dispatch_args,
            )?)
        };
        let jump_type_alias_roots_b_to_a = if alias_root_jump_rounds >= 2 {
            Some(ComputeOperation::indirect_spec(
                device,
                graph,
                &alias_resources,
                passes,
                TYPE_ALIAS_ROOT_JUMP_B_TO_A,
                &decl_key_radix_dispatch_args,
            )?)
        } else {
            None
        };
        let final_jump_type_alias_roots_a_to_b =
            if alias_root_jump_rounds > 1 && alias_root_jump_rounds % 2 != 0 {
                Some(
                    jump_type_alias_roots_a_to_b
                        .as_ref()
                        .expect("multi-round alias roots have an A-to-B operation")
                        .invocation(graph, TYPE_ALIAS_ROOT_JUMP_FINAL_A_TO_B.name)?,
                )
            } else {
                None
            };
        let graph_work = inputs
            .token_capacity
            .saturating_add(inputs.hir_node_capacity)
            .max(1);
        let clear_alias_equivalence = ComputeOperation::direct_spec(
            device,
            graph,
            &alias_resources,
            passes,
            TYPE_ALIAS_EQUIVALENCE_CLEAR,
            graph_work,
        )?;
        let init_alias_decl_edges = ComputeOperation::indirect_spec(
            device,
            graph,
            &alias_resources,
            passes,
            TYPE_ALIAS_EQUIVALENCE_DECL_EDGES_INITIALIZE,
            &decl_key_radix_dispatch_args,
        )?;
        let init_alias_arg_edges = ComputeOperation::direct_spec(
            device,
            graph,
            &alias_resources,
            passes,
            TYPE_ALIAS_EQUIVALENCE_ARG_EDGES_INITIALIZE,
            hir_work,
        )?;
        // Each round performs min-parent hooking followed by a bounded walk of up
        // to 16 parent links. One base-16 capacity-covering logarithm is enough to
        // contract the longest possible component chain.
        let mut alias_equivalence_rounds = 1;
        let mut covered_nodes = 16u64;
        while covered_nodes < u64::from(alias_equiv_capacity) {
            alias_equivalence_rounds += 1;
            covered_nodes = covered_nodes.saturating_mul(16);
        }
        let (hook_alias_equivalence_a_spec, jump_alias_equivalence_a_to_b_spec) =
            if alias_equivalence_rounds == 1 {
                (
                    TYPE_ALIAS_EQUIVALENCE_FINAL_HOOK_A,
                    TYPE_ALIAS_EQUIVALENCE_FINAL_JUMP_A_TO_B,
                )
            } else {
                (
                    TYPE_ALIAS_EQUIVALENCE_HOOK_A,
                    TYPE_ALIAS_EQUIVALENCE_JUMP_A_TO_B,
                )
            };
        let hook_alias_equivalence_a = ComputeOperation::direct_spec(
            device,
            graph,
            &alias_resources,
            passes,
            hook_alias_equivalence_a_spec,
            hir_work,
        )?;
        let jump_alias_equivalence_a_to_b = ComputeOperation::direct_spec(
            device,
            graph,
            &alias_resources,
            passes,
            jump_alias_equivalence_a_to_b_spec,
            graph_work,
        )?;
        let hook_alias_equivalence_b = if alias_equivalence_rounds >= 2 {
            Some(ComputeOperation::direct_spec(
                device,
                graph,
                &alias_resources,
                passes,
                TYPE_ALIAS_EQUIVALENCE_HOOK_B,
                hir_work,
            )?)
        } else {
            None
        };
        let jump_alias_equivalence_b_to_a = if alias_equivalence_rounds >= 2 {
            Some(ComputeOperation::direct_spec(
                device,
                graph,
                &alias_resources,
                passes,
                TYPE_ALIAS_EQUIVALENCE_JUMP_B_TO_A,
                graph_work,
            )?)
        } else {
            None
        };
        let (final_hook_alias_equivalence_a, final_jump_alias_equivalence_a_to_b) =
            if alias_equivalence_rounds > 1 && alias_equivalence_rounds % 2 != 0 {
                (
                    Some(
                        hook_alias_equivalence_a
                            .invocation(graph, TYPE_ALIAS_EQUIVALENCE_FINAL_HOOK_A.name)?,
                    ),
                    Some(
                        jump_alias_equivalence_a_to_b
                            .invocation(graph, TYPE_ALIAS_EQUIVALENCE_FINAL_JUMP_A_TO_B.name)?,
                    ),
                )
            } else {
                (None, None)
            };
        let select_alias_generic_sources = ComputeOperation::direct(
            device,
            graph,
            &alias_resources,
            TYPE_ALIAS_GENERIC_SOURCES_SELECT_PASS,
            &passes.kernel("type_checker/modules/10e0h_select_type_alias_generic_sources"),
            hir_work,
        )?;
        let select_alias_concrete_sources = ComputeOperation::direct(
            device,
            graph,
            &alias_resources,
            TYPE_ALIAS_CONCRETE_SOURCES_SELECT_PASS,
            &passes.kernel("type_checker/modules/10e0i_select_type_alias_concrete_sources"),
            hir_work,
        )?;
        let finalize_alias_equivalence = ComputeOperation::indirect(
            device,
            graph,
            &alias_resources,
            TYPE_ALIAS_EQUIVALENCE_FINALIZE_PASS,
            &passes.kernel("type_checker/modules/10e0j_finalize_type_alias_equivalence"),
            &decl_key_radix_dispatch_args,
        )?;
        let project_type_alias_instances = ComputeOperation::indirect_spec(
            device,
            graph,
            &alias_resources,
            passes,
            TYPE_ALIAS_INSTANCES_PROJECT,
            inputs.hir_active_dispatch_args,
        )?;
        let project_type_aliases = ComputeOperation::indirect(
            device,
            graph,
            &alias_resources,
            TYPE_ALIAS_PROJECT_PASS,
            &passes.kernel("type_checker/modules/10e2_project_type_aliases"),
            &decl_key_radix_dispatch_args,
        )?;
        let project_type_aliases_after_projected_refs =
            project_type_aliases.invocation(graph, TYPE_ALIAS_PROJECT_AFTER_PROJECTED_REFS_PASS)?;
        Some(Box::new(TypeAliasProjection {
            clear_forwarding: clear_type_alias_forwarding,
            init_forwarding: init_type_alias_forwarding,
            validate_forwarding_args: validate_type_alias_forwarding_args,
            init_roots: init_type_alias_roots,
            jump_a_to_b: jump_type_alias_roots_a_to_b,
            jump_b_to_a: jump_type_alias_roots_b_to_a,
            final_jump_a_to_b: final_jump_type_alias_roots_a_to_b,
            jump_rounds: alias_root_jump_rounds,
            clear_equivalence: clear_alias_equivalence,
            init_decl_edges: init_alias_decl_edges,
            init_arg_edges: init_alias_arg_edges,
            hook_equivalence_a: hook_alias_equivalence_a,
            hook_equivalence_b: hook_alias_equivalence_b,
            jump_equivalence_a_to_b: jump_alias_equivalence_a_to_b,
            jump_equivalence_b_to_a: jump_alias_equivalence_b_to_a,
            final_hook_equivalence_a: final_hook_alias_equivalence_a,
            final_jump_equivalence_a_to_b: final_jump_alias_equivalence_a_to_b,
            equivalence_rounds: alias_equivalence_rounds,
            select_generic_sources: select_alias_generic_sources,
            select_concrete_sources: select_alias_concrete_sources,
            finalize_equivalence: finalize_alias_equivalence,
            project_instances: project_type_alias_instances,
            project: project_type_aliases,
            project_after_projected_refs: project_type_aliases_after_projected_refs,
            _root_a: alias_root_a,
            _root_b: alias_root_b,
            _forwarding: alias_forwarding,
            _forwarding_target_decl: alias_forwarding_target_decl,
            _forwarding_valid_arg_count: alias_forwarding_valid_arg_count,
            _decl_by_target_hir: alias_decl_by_target_hir,
            _equiv_parent_a: alias_equiv_parent_a,
            _equiv_parent_b: alias_equiv_parent_b,
            _equiv_edge_0: alias_equiv_edge_0,
            _equiv_edge_1: alias_equiv_edge_1,
            _equiv_component_source: alias_equiv_component_source,
            _normalized_source: alias_normalized_source,
        }))
    } else {
        None
    };
    let project_type_instances = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        TYPE_INSTANCES_PROJECT,
        &path_dispatch_args,
    )?;
    let mark_value_call_paths = ComputeOperation::direct_spec(
        device,
        graph,
        resources,
        passes,
        VALUE_CALL_PATHS_MARK,
        inputs.token_capacity.max(inputs.hir_node_capacity).max(1),
    )?;
    let project_value_paths = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        VALUE_PATHS_PROJECT,
        &path_dispatch_args,
    )?;
    let consume_value_calls = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        VALUE_CALLS_CONSUME,
        &path_dispatch_args,
    )?;
    let consume_value_calls_after_methods =
        consume_value_calls.invocation(graph, VALUE_CALLS_CONSUME_AFTER_METHODS.name)?;
    let mirror_value_call_leaf = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        VALUE_CALL_LEAF_MIRROR,
        &path_dispatch_args,
    )?;
    let mirror_value_call_leaf_after_row_args =
        mirror_value_call_leaf.invocation(graph, VALUE_CALL_LEAF_MIRROR_AFTER_ROW_ARGS.name)?;
    let mirror_value_call_leaf_after_methods =
        mirror_value_call_leaf.invocation(graph, VALUE_CALL_LEAF_MIRROR_AFTER_METHODS.name)?;
    let mirror_value_call_leaf_after_method_row_args = mirror_value_call_leaf
        .invocation(graph, VALUE_CALL_LEAF_MIRROR_AFTER_METHOD_ROW_ARGS.name)?;
    let consume_value_consts = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        VALUE_CONSTS_CONSUME,
        &path_dispatch_args,
    )?;
    let consume_value_enum_units = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        VALUE_ENUM_UNITS_CONSUME,
        &path_dispatch_args,
    )?;
    let consume_value_enum_calls = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        VALUE_ENUM_CALLS_CONSUME,
        &path_dispatch_args,
    )?;
    let validate_value_enum_call_payloads = ComputeOperation::direct_spec(
        device,
        graph,
        resources,
        passes,
        VALUE_ENUM_CALL_PAYLOADS_VALIDATE,
        inputs.hir_node_capacity.saturating_mul(4).max(1),
    )?;
    let finalize_value_enum_calls = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        VALUE_ENUM_CALLS_FINALIZE,
        &path_dispatch_args,
    )?;
    let match_hir_dispatch_args = graph.u32_buffer("match_hir_dispatch_args")?;
    let bind_match_patterns = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        MATCH_PATTERNS_BIND,
        &match_hir_dispatch_args,
    )?;
    let type_match_payloads = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        MATCH_PAYLOADS_TYPE,
        &match_hir_dispatch_args,
    )?;
    let type_match_exprs = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        MATCH_EXPRS_TYPE,
        inputs.hir_active_dispatch_args,
    )?;

    Ok(ProjectionBindGroups {
        clear_type_path_types,
        project_type_paths,
        project_type_paths_after_aliases,
        project_type_paths_after_projected_aliases,
        project_type_paths_after_alias_equivalence,
        validate_type_paths,
        type_aliases,
        project_type_instances,
        mark_value_call_paths,
        project_value_paths,
        consume_value_calls,
        consume_value_calls_after_methods,
        mirror_value_call_leaf,
        mirror_value_call_leaf_after_row_args,
        mirror_value_call_leaf_after_methods,
        mirror_value_call_leaf_after_method_row_args,
        consume_value_consts,
        consume_value_enum_units,
        consume_value_enum_calls,
        validate_value_enum_call_payloads,
        finalize_value_enum_calls,
        bind_match_patterns,
        type_match_payloads,
        type_match_exprs,
    })
}
