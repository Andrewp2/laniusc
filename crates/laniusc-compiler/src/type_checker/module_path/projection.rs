use anyhow::Result;

use super::{super::*, inputs::CreateInputs};

/// Bind groups for projecting resolved paths into semantic type/value facts.
///
/// This is the bridge from module lookup tables to the rest of type checking:
/// type paths become type refs, value paths become call/const/enum facts, and
/// match patterns get bound to enum payload rows.
pub(in crate::type_checker) struct ProjectionBindGroups {
    pub(in crate::type_checker) clear_type_path_types: wgpu::BindGroup,
    pub(in crate::type_checker) project_type_paths: wgpu::BindGroup,
    pub(in crate::type_checker) validate_type_paths: wgpu::BindGroup,
    pub(in crate::type_checker) type_aliases: Box<TypeAliasProjection>,
    pub(in crate::type_checker) project_type_instances: wgpu::BindGroup,
    pub(in crate::type_checker) mark_value_call_paths: wgpu::BindGroup,
    pub(in crate::type_checker) project_value_paths: wgpu::BindGroup,
    pub(in crate::type_checker) consume_value_calls: wgpu::BindGroup,
    pub(in crate::type_checker) mirror_value_call_leaf: wgpu::BindGroup,
    pub(in crate::type_checker) consume_value_consts: wgpu::BindGroup,
    pub(in crate::type_checker) consume_value_enum_units: wgpu::BindGroup,
    pub(in crate::type_checker) consume_value_enum_calls: wgpu::BindGroup,
    pub(in crate::type_checker) validate_value_enum_call_payloads: wgpu::BindGroup,
    pub(in crate::type_checker) finalize_value_enum_calls: wgpu::BindGroup,
    pub(in crate::type_checker) bind_match_patterns: wgpu::BindGroup,
    pub(in crate::type_checker) type_match_payloads: wgpu::BindGroup,
    pub(in crate::type_checker) type_match_exprs: wgpu::BindGroup,
}

/// Parallel root discovery and projection resources for local type aliases.
///
/// The ping-pong roots collapse declaration-only alias chains by pointer
/// jumping. Keeping this family boxed avoids adding another large resident
/// resource group to module-path construction's stack frame.
pub(in crate::type_checker) struct TypeAliasProjection {
    pub(in crate::type_checker) clear_forwarding: wgpu::BindGroup,
    pub(in crate::type_checker) init_forwarding: wgpu::BindGroup,
    pub(in crate::type_checker) validate_forwarding_args: wgpu::BindGroup,
    pub(in crate::type_checker) init_roots: wgpu::BindGroup,
    pub(in crate::type_checker) jump_a_to_b: wgpu::BindGroup,
    pub(in crate::type_checker) jump_b_to_a: wgpu::BindGroup,
    pub(in crate::type_checker) jump_rounds: u32,
    pub(in crate::type_checker) clear_equivalence: wgpu::BindGroup,
    pub(in crate::type_checker) init_decl_edges: wgpu::BindGroup,
    pub(in crate::type_checker) init_arg_edges: wgpu::BindGroup,
    pub(in crate::type_checker) hook_equivalence_a: wgpu::BindGroup,
    pub(in crate::type_checker) hook_equivalence_b: wgpu::BindGroup,
    pub(in crate::type_checker) jump_equivalence_a_to_b: wgpu::BindGroup,
    pub(in crate::type_checker) jump_equivalence_b_to_a: wgpu::BindGroup,
    pub(in crate::type_checker) equivalence_rounds: u32,
    pub(in crate::type_checker) select_generic_sources: wgpu::BindGroup,
    pub(in crate::type_checker) select_concrete_sources: wgpu::BindGroup,
    pub(in crate::type_checker) finalize_equivalence: wgpu::BindGroup,
    pub(in crate::type_checker) project_instances: Box<wgpu::BindGroup>,
    pub(in crate::type_checker) project: wgpu::BindGroup,
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

/// Creates bind groups for path projection and value/type path validation.
pub(in crate::type_checker) fn create_projection_bind_groups(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    inputs: &CreateInputs<'_>,
    resources: &ResourceMap<'_>,
) -> Result<ProjectionBindGroups> {
    let params = inputs.params;

    let clear_type_path_types = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10d_clear_type_path_types",
        &passes.kernel("type_checker/modules/10d_clear_type_path_types"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let project_type_paths = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10e_project_type_paths",
        &passes.kernel("type_checker/modules/10e_project_type_paths"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let validate_type_paths = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10e3_validate_type_paths",
        &passes.kernel("type_checker/modules/10e3_validate_type_paths"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let aliases_required = type_alias_passes_required(inputs.hir_items.parser_feature_flags);
    let alias_root_capacity = if aliases_required {
        inputs.hir_items.module_record_capacity.max(1)
    } else {
        1
    };
    let alias_root_a = graph.u32_buffer("alias_root_a")?;
    let alias_root_b = graph.u32_buffer("alias_root_b")?;
    let alias_forwarding = graph.u32_buffer("alias_forwarding")?;
    let alias_forwarding_target_decl = graph.u32_buffer("alias_forwarding_target_decl")?;
    let alias_forwarding_valid_arg_count = graph.u32_buffer("alias_forwarding_valid_arg_count")?;
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

    let clear_type_alias_forwarding = alias_resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10e0_clear_type_alias_forwarding",
        &passes.kernel("type_checker/modules/10e0_clear_type_alias_forwarding"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let init_type_alias_forwarding = alias_resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10e0a_init_type_alias_forwarding",
        &passes.kernel("type_checker/modules/10e0a_init_type_alias_forwarding"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let validate_type_alias_forwarding_args = alias_resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10e0b_validate_type_alias_forwarding_args",
        &passes.kernel("type_checker/modules/10e0b_validate_type_alias_forwarding_args"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let init_type_alias_roots = alias_resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10e1_init_type_alias_roots",
        &passes.kernel("type_checker/modules/10e1_init_type_alias_roots"),
        &[
            ("gParams", params.as_entire_binding()),
            ("alias_root_decl", alias_root_a.as_entire_binding()),
        ],
    )?;
    let jump_type_alias_roots_a_to_b = alias_resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10e1a_jump_type_alias_roots_a_to_b",
        &passes.kernel("type_checker/modules/10e1a_jump_type_alias_roots"),
        &[
            ("gParams", params.as_entire_binding()),
            ("alias_root_decl_in", alias_root_a.as_entire_binding()),
            ("alias_root_decl_out", alias_root_b.as_entire_binding()),
        ],
    )?;
    let jump_type_alias_roots_b_to_a = alias_resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10e1a_jump_type_alias_roots_b_to_a",
        &passes.kernel("type_checker/modules/10e1a_jump_type_alias_roots"),
        &[
            ("gParams", params.as_entire_binding()),
            ("alias_root_decl_in", alias_root_b.as_entire_binding()),
            ("alias_root_decl_out", alias_root_a.as_entire_binding()),
        ],
    )?;
    let mut alias_root_jump_rounds = 0;
    let mut alias_root_covered_nodes = 1u64;
    while alias_root_covered_nodes < u64::from(alias_root_capacity) {
        alias_root_jump_rounds += 1;
        alias_root_covered_nodes = alias_root_covered_nodes.saturating_mul(16);
    }
    let final_alias_root = if alias_root_jump_rounds % 2 == 0 {
        &alias_root_a
    } else {
        &alias_root_b
    };
    let clear_alias_equivalence = alias_resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10e0c_clear_type_alias_equivalence",
        &passes.kernel("type_checker/modules/10e0c_clear_type_alias_equivalence"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let init_alias_decl_edges = alias_resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10e0d_init_type_alias_decl_edges",
        &passes.kernel("type_checker/modules/10e0d_init_type_alias_decl_edges"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let init_alias_arg_edges = alias_resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10e0e_init_type_alias_arg_edges",
        &passes.kernel("type_checker/modules/10e0e_init_type_alias_arg_edges"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let hook_alias_equivalence = |label: &'static str, parent: &LaniusBuffer<u32>| {
        alias_resources.reflected_bind_group_with_overrides(
            device,
            label,
            &passes.kernel("type_checker/modules/10e0f_hook_type_alias_equivalence"),
            &[
                ("gParams", params.as_entire_binding()),
                ("alias_equiv_parent", parent.as_entire_binding()),
            ],
        )
    };
    let hook_alias_equivalence_a = hook_alias_equivalence(
        "type_check_modules_10e0f_hook_type_alias_equivalence_a",
        &alias_equiv_parent_a,
    )?;
    let hook_alias_equivalence_b = hook_alias_equivalence(
        "type_check_modules_10e0f_hook_type_alias_equivalence_b",
        &alias_equiv_parent_b,
    )?;
    let jump_alias_equivalence =
        |label: &'static str, input: &LaniusBuffer<u32>, output: &LaniusBuffer<u32>| {
            alias_resources.reflected_bind_group_with_overrides(
                device,
                label,
                &passes.kernel("type_checker/modules/10e0g_jump_type_alias_equivalence"),
                &[
                    ("gParams", params.as_entire_binding()),
                    ("alias_equiv_parent_in", input.as_entire_binding()),
                    ("alias_equiv_parent_out", output.as_entire_binding()),
                ],
            )
        };
    let jump_alias_equivalence_a_to_b = jump_alias_equivalence(
        "type_check_modules_10e0g_jump_type_alias_equivalence_a_to_b",
        &alias_equiv_parent_a,
        &alias_equiv_parent_b,
    )?;
    let jump_alias_equivalence_b_to_a = jump_alias_equivalence(
        "type_check_modules_10e0g_jump_type_alias_equivalence_b_to_a",
        &alias_equiv_parent_b,
        &alias_equiv_parent_a,
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
    let final_alias_equiv_parent = if alias_equivalence_rounds % 2 == 0 {
        &alias_equiv_parent_a
    } else {
        &alias_equiv_parent_b
    };
    let select_alias_generic_sources = alias_resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10e0h_select_type_alias_generic_sources",
        &passes.kernel("type_checker/modules/10e0h_select_type_alias_generic_sources"),
        &[
            ("gParams", params.as_entire_binding()),
            (
                "alias_equiv_parent",
                final_alias_equiv_parent.as_entire_binding(),
            ),
        ],
    )?;
    let select_alias_concrete_sources = alias_resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10e0i_select_type_alias_concrete_sources",
        &passes.kernel("type_checker/modules/10e0i_select_type_alias_concrete_sources"),
        &[
            ("gParams", params.as_entire_binding()),
            (
                "alias_equiv_parent",
                final_alias_equiv_parent.as_entire_binding(),
            ),
        ],
    )?;
    let finalize_alias_equivalence = alias_resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10e0j_finalize_type_alias_equivalence",
        &passes.kernel("type_checker/modules/10e0j_finalize_type_alias_equivalence"),
        &[
            ("gParams", params.as_entire_binding()),
            (
                "alias_equiv_parent",
                final_alias_equiv_parent.as_entire_binding(),
            ),
        ],
    )?;
    let project_type_alias_instances = alias_resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10e0k_project_type_alias_instances",
        &passes.kernel("type_checker/modules/10e0k_project_type_alias_instances"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let project_type_alias_instances = Box::new(project_type_alias_instances);
    let project_type_aliases = alias_resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10e2_project_type_aliases",
        &passes.kernel("type_checker/modules/10e2_project_type_aliases"),
        &[
            ("gParams", params.as_entire_binding()),
            ("alias_root_decl", final_alias_root.as_entire_binding()),
        ],
    )?;
    let type_aliases = Box::new(TypeAliasProjection {
        clear_forwarding: clear_type_alias_forwarding,
        init_forwarding: init_type_alias_forwarding,
        validate_forwarding_args: validate_type_alias_forwarding_args,
        init_roots: init_type_alias_roots,
        jump_a_to_b: jump_type_alias_roots_a_to_b,
        jump_b_to_a: jump_type_alias_roots_b_to_a,
        jump_rounds: alias_root_jump_rounds,
        clear_equivalence: clear_alias_equivalence,
        init_decl_edges: init_alias_decl_edges,
        init_arg_edges: init_alias_arg_edges,
        hook_equivalence_a: hook_alias_equivalence_a,
        hook_equivalence_b: hook_alias_equivalence_b,
        jump_equivalence_a_to_b: jump_alias_equivalence_a_to_b,
        jump_equivalence_b_to_a: jump_alias_equivalence_b_to_a,
        equivalence_rounds: alias_equivalence_rounds,
        select_generic_sources: select_alias_generic_sources,
        select_concrete_sources: select_alias_concrete_sources,
        finalize_equivalence: finalize_alias_equivalence,
        project_instances: project_type_alias_instances,
        project: project_type_aliases,
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
    });
    let project_type_instances = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10k_project_type_instances",
        &passes.kernel("type_checker/modules/10k_project_type_instances"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let mark_value_call_paths = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10f_mark_value_call_paths",
        &passes.kernel("type_checker/modules/10f_mark_value_call_paths"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let project_value_paths = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10g_project_value_paths",
        &passes.kernel("type_checker/modules/10g_project_value_paths"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let consume_value_calls = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10h_consume_value_calls",
        &passes.kernel("type_checker/modules/10h_consume_value_calls"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let mirror_value_call_leaf = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10h2_mirror_value_call_leaf",
        &passes.kernel("type_checker/modules/10h2_mirror_value_call_leaf"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let consume_value_consts = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10i_consume_value_consts",
        &passes.kernel("type_checker/modules/10i_consume_value_consts"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let consume_value_enum_units = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10j_consume_value_enum_units",
        &passes.kernel("type_checker/modules/10j_consume_value_enum_units"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let consume_value_enum_calls = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10l_consume_value_enum_calls",
        &passes.kernel("type_checker/modules/10l_consume_value_enum_calls"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let validate_value_enum_call_payloads = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10l2_validate_value_enum_call_payloads",
        &passes.kernel("type_checker/modules/10l2_validate_value_enum_call_payloads"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let finalize_value_enum_calls = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10l3_finalize_value_enum_calls",
        &passes.kernel("type_checker/modules/10l3_finalize_value_enum_calls"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let bind_match_patterns = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10m_bind_match_patterns",
        &passes.kernel("type_checker/modules/10m_bind_match_patterns"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let type_match_payloads = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10m2_type_match_payloads",
        &passes.kernel("type_checker/modules/10m2_type_match_payloads"),
        &[("gParams", params.as_entire_binding())],
    )?;
    let type_match_exprs = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_10n_type_match_exprs",
        &passes.kernel("type_checker/modules/10n_type_match_exprs"),
        &[("gParams", params.as_entire_binding())],
    )?;

    Ok(ProjectionBindGroups {
        clear_type_path_types,
        project_type_paths,
        validate_type_paths,
        type_aliases,
        project_type_instances,
        mark_value_call_paths,
        project_value_paths,
        consume_value_calls,
        mirror_value_call_leaf,
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
