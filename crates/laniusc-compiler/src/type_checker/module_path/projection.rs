use anyhow::Result;

use super::{super::*, buffers::Buffers, inputs::CreateInputs};

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

#[allow(clippy::too_many_arguments)]
fn create_project_type_alias_instances_bind_group(
    device: &wgpu::Device,
    pass: &PassData,
    params: &LaniusBuffer<TypeCheckParams>,
    hir: &GpuTypeCheckHirItemBuffers<'_>,
    path_count_out: &wgpu::Buffer,
    path_id_by_owner_hir: &wgpu::Buffer,
    path_segment_count: &wgpu::Buffer,
    path_segment_base: &wgpu::Buffer,
    path_segment_token: &wgpu::Buffer,
    type_instance_decl_token: &wgpu::Buffer,
    type_decl_hir_node_by_token: &wgpu::Buffer,
    type_generic_param_slot_by_token: &wgpu::Buffer,
    type_instance_arg_row_start: &wgpu::Buffer,
    type_instance_arg_row_count_out: &wgpu::Buffer,
    type_instance_arg_row_ref_tag: &wgpu::Buffer,
    type_instance_arg_row_ref_payload: &wgpu::Buffer,
    alias_normalized_source: &LaniusBuffer<u32>,
    type_expr_ref_tag: &wgpu::Buffer,
    type_expr_ref_payload: &wgpu::Buffer,
) -> Result<Box<wgpu::BindGroup>> {
    bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10e0k_project_type_alias_instances"),
        pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("compact_hir_count", hir.hir.count.as_entire_binding()),
            ("compact_hir_core", hir.hir.core.as_entire_binding()),
            ("compact_hir_payload", hir.hir.payload.as_entire_binding()),
            ("path_count_out", path_count_out.as_entire_binding()),
            (
                "path_id_by_owner_hir",
                path_id_by_owner_hir.as_entire_binding(),
            ),
            ("path_segment_count", path_segment_count.as_entire_binding()),
            ("path_segment_base", path_segment_base.as_entire_binding()),
            ("path_segment_token", path_segment_token.as_entire_binding()),
            (
                "type_instance_decl_token",
                type_instance_decl_token.as_entire_binding(),
            ),
            (
                "type_decl_hir_node_by_token",
                type_decl_hir_node_by_token.as_entire_binding(),
            ),
            (
                "type_generic_param_slot_by_token",
                type_generic_param_slot_by_token.as_entire_binding(),
            ),
            (
                "type_instance_arg_row_start",
                type_instance_arg_row_start.as_entire_binding(),
            ),
            (
                "type_instance_arg_row_count_out",
                type_instance_arg_row_count_out.as_entire_binding(),
            ),
            (
                "type_instance_arg_row_ref_tag",
                type_instance_arg_row_ref_tag.as_entire_binding(),
            ),
            (
                "type_instance_arg_row_ref_payload",
                type_instance_arg_row_ref_payload.as_entire_binding(),
            ),
            (
                "alias_normalized_source",
                alias_normalized_source.as_entire_binding(),
            ),
            ("type_expr_ref_tag", type_expr_ref_tag.as_entire_binding()),
            (
                "type_expr_ref_payload",
                type_expr_ref_payload.as_entire_binding(),
            ),
        ],
    )
    .map(Box::new)
}

/// Creates bind groups for path projection and value/type path validation.
pub(in crate::type_checker) fn create_projection_bind_groups(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    inputs: &CreateInputs<'_>,
    buffers: &Buffers,
) -> Result<ProjectionBindGroups> {
    let CreateInputs {
        params,
        token_buf,
        token_count_buf,
        hir_status_buf,
        hir_kind_buf,
        hir_token_pos_buf,
        hir_token_end_buf,
        status_buf,
        hir_items,
        name_id_by_token,
        language_name_id,
        module_type_path_type,
        module_type_path_status,
        module_value_path_expr_head,
        module_value_path_call_head,
        module_value_path_call_open,
        module_value_path_call_path_id,
        module_value_path_call_leaf,
        module_value_path_associated_method_token,
        module_value_path_associated_receiver_token,
        module_value_path_const_head,
        module_value_path_const_end,
        module_value_path_status,
        visible_decl,
        visible_type,
        enclosing_fn,
        call_fn_index,
        call_return_type,
        call_return_type_token,
        call_generic_slot_type,
        call_generic_slot_ordinal,
        method_call_name_id,
        call_param_count,
        call_arg_record,
        call_arg_row_node,
        call_arg_row_call_node,
        call_arg_row_ordinal,
        call_arg_row_start,
        call_arg_row_count,
        type_expr_ref_tag,
        type_expr_ref_payload,
        type_instance_kind,
        type_instance_decl_token,
        type_instance_arg_start,
        type_instance_arg_count,
        type_instance_arg_ref_tag,
        type_instance_arg_ref_payload,
        type_instance_arg_row_start,
        type_instance_arg_row_count_out,
        type_instance_arg_row_ref_tag,
        type_instance_arg_row_ref_payload,
        type_decl_generic_param_count,
        type_decl_generic_param_count_by_owner_token,
        type_generic_param_slot_by_token,
        type_decl_hir_node_by_token,
        generic_param_count_out,
        generic_param_owner_token,
        generic_param_name_id,
        generic_param_token,
        generic_param_kind,
        generic_param_key_order,
        generic_param_slot_order,
        type_instance_state,
        decl_type_ref_tag,
        decl_type_ref_payload,
        fn_return_ref_tag,
        fn_return_ref_payload,
        ..
    } = inputs;
    let Buffers {
        decl_count_out,
        decl_name_token,
        decl_id_by_name_token,
        decl_kind,
        decl_namespace,
        decl_hir_node,
        decl_parent_type_decl,
        resolved_type_decl,
        resolved_value_decl,
        resolved_type_status,
        resolved_value_status,
        path_segment_count,
        path_segment_base,
        path_segment_token,
        path_owner_hir,
        path_call_hir,
        path_owner_token,
        path_id_by_owner_hir,
        path_kind,
        path_count_out,
        ..
    } = buffers;

    let clear_type_path_types = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10d_clear_type_path_types"),
        &passes.modules_clear_type_path_types,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "module_type_path_type",
                module_type_path_type.as_entire_binding(),
            ),
            (
                "module_type_path_status",
                module_type_path_status.as_entire_binding(),
            ),
            (
                "module_value_path_expr_head",
                module_value_path_expr_head.as_entire_binding(),
            ),
            (
                "module_value_path_call_head",
                module_value_path_call_head.as_entire_binding(),
            ),
            (
                "module_value_path_call_open",
                module_value_path_call_open.as_entire_binding(),
            ),
            (
                "module_value_path_call_path_id",
                module_value_path_call_path_id.as_entire_binding(),
            ),
            (
                "module_value_path_call_leaf",
                module_value_path_call_leaf.as_entire_binding(),
            ),
            (
                "module_value_path_associated_method_token",
                module_value_path_associated_method_token.as_entire_binding(),
            ),
            (
                "module_value_path_associated_receiver_token",
                module_value_path_associated_receiver_token.as_entire_binding(),
            ),
            (
                "module_value_path_const_head",
                module_value_path_const_head.as_entire_binding(),
            ),
            (
                "module_value_path_const_end",
                module_value_path_const_end.as_entire_binding(),
            ),
            (
                "module_value_path_status",
                module_value_path_status.as_entire_binding(),
            ),
        ],
    )?;
    let project_type_paths = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10e_project_type_paths"),
        &passes.modules_project_type_paths,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("path_count_out", path_count_out.as_entire_binding()),
            ("path_kind", path_kind.as_entire_binding()),
            ("path_segment_count", path_segment_count.as_entire_binding()),
            ("path_owner_token", path_owner_token.as_entire_binding()),
            ("resolved_type_decl", resolved_type_decl.as_entire_binding()),
            (
                "resolved_type_status",
                resolved_type_status.as_entire_binding(),
            ),
            ("decl_kind", decl_kind.as_entire_binding()),
            ("decl_namespace", decl_namespace.as_entire_binding()),
            ("decl_name_token", decl_name_token.as_entire_binding()),
            (
                "module_type_path_type",
                module_type_path_type.as_entire_binding(),
            ),
            (
                "module_type_path_status",
                module_type_path_status.as_entire_binding(),
            ),
            ("type_expr_ref_tag", type_expr_ref_tag.as_entire_binding()),
            (
                "type_expr_ref_payload",
                type_expr_ref_payload.as_entire_binding(),
            ),
        ],
    )?;
    let validate_type_paths = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10e3_validate_type_paths"),
        &passes.modules_validate_type_paths,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("path_count_out", path_count_out.as_entire_binding()),
            ("path_kind", path_kind.as_entire_binding()),
            ("path_segment_count", path_segment_count.as_entire_binding()),
            ("path_owner_token", path_owner_token.as_entire_binding()),
            (
                "resolved_type_status",
                resolved_type_status.as_entire_binding(),
            ),
            (
                "resolved_value_status",
                resolved_value_status.as_entire_binding(),
            ),
            (
                "module_value_path_status",
                module_value_path_status.as_entire_binding(),
            ),
            (
                "module_value_path_expr_head",
                module_value_path_expr_head.as_entire_binding(),
            ),
            ("status", status_buf.as_entire_binding()),
        ],
    )?;
    let aliases_required = type_alias_passes_required(inputs.hir_items.parser_feature_flags);
    let alias_root_capacity = if aliases_required {
        inputs.hir_items.module_record_capacity.max(1)
    } else {
        1
    };
    let alias_hir_capacity = if aliases_required {
        inputs.hir_node_capacity.max(1)
    } else {
        1
    };
    let alias_root_a = typed_storage_u32_rw(
        device,
        "type_check.modules.type_alias_root_a",
        alias_root_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let alias_root_b = typed_storage_u32_rw(
        device,
        "type_check.modules.type_alias_root_b",
        alias_root_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let alias_forwarding = typed_storage_u32_rw(
        device,
        "type_check.modules.type_alias_forwarding",
        alias_hir_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let alias_forwarding_target_decl = typed_storage_u32_rw(
        device,
        "type_check.modules.type_alias_forwarding_target_decl",
        alias_hir_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let alias_forwarding_valid_arg_count = typed_storage_u32_rw(
        device,
        "type_check.modules.type_alias_forwarding_valid_arg_count",
        alias_hir_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let alias_decl_by_target_hir = typed_storage_u32_rw(
        device,
        "type_check.modules.type_alias_decl_by_target_hir",
        alias_hir_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let alias_equiv_capacity = if aliases_required {
        inputs
            .token_capacity
            .saturating_add(inputs.hir_node_capacity)
            .max(1)
    } else {
        1
    };
    let alias_equiv_parent_a = typed_storage_u32_rw(
        device,
        "type_check.modules.type_alias_equiv_parent_a",
        alias_equiv_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let alias_equiv_parent_b = typed_storage_u32_rw(
        device,
        "type_check.modules.type_alias_equiv_parent_b",
        alias_equiv_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    // Forwarding is consumed by root initialization before equivalence graph
    // construction begins. Rebuild those same HIR-wide rows as the two graph
    // edges and the durable normalized source table.
    let alias_equiv_edge_0 =
        typed_alias_storage_u32(&alias_forwarding, alias_hir_capacity as usize);
    let alias_equiv_edge_1 =
        typed_alias_storage_u32(&alias_forwarding_target_decl, alias_hir_capacity as usize);
    let alias_equiv_component_source = typed_storage_u32_rw(
        device,
        "type_check.modules.type_alias_equiv_component_source",
        alias_equiv_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let alias_normalized_source = typed_alias_storage_u32(
        &alias_forwarding_valid_arg_count,
        alias_hir_capacity as usize,
    );
    let clear_type_alias_forwarding = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10e0_clear_type_alias_forwarding"),
        &passes.type_aliases.clear_forwarding,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("alias_forwarding", alias_forwarding.as_entire_binding()),
            (
                "alias_forwarding_target_decl",
                alias_forwarding_target_decl.as_entire_binding(),
            ),
            (
                "alias_forwarding_valid_arg_count",
                alias_forwarding_valid_arg_count.as_entire_binding(),
            ),
            (
                "alias_decl_by_target_hir",
                alias_decl_by_target_hir.as_entire_binding(),
            ),
        ],
    )?;
    let init_type_alias_forwarding = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10e0a_init_type_alias_forwarding"),
        &passes.type_aliases.init_forwarding,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("compact_hir_count", hir_items.hir.count.as_entire_binding()),
            (
                "compact_hir_payload",
                hir_items.hir.payload.as_entire_binding(),
            ),
            (
                "compact_type_alias_target",
                hir_items.hir.type_alias_target.as_entire_binding(),
            ),
            (
                "compact_type_arg_ranges",
                hir_items.hir.type_arg_ranges.as_entire_binding(),
            ),
            ("decl_count_out", decl_count_out.as_entire_binding()),
            ("decl_kind", decl_kind.as_entire_binding()),
            ("decl_namespace", decl_namespace.as_entire_binding()),
            ("decl_hir_node", decl_hir_node.as_entire_binding()),
            (
                "path_id_by_owner_hir",
                path_id_by_owner_hir.as_entire_binding(),
            ),
            ("resolved_type_decl", resolved_type_decl.as_entire_binding()),
            (
                "type_decl_generic_param_count_by_owner_token",
                type_decl_generic_param_count_by_owner_token.as_entire_binding(),
            ),
            ("alias_forwarding", alias_forwarding.as_entire_binding()),
            (
                "alias_forwarding_target_decl",
                alias_forwarding_target_decl.as_entire_binding(),
            ),
            (
                "alias_decl_by_target_hir",
                alias_decl_by_target_hir.as_entire_binding(),
            ),
        ],
    )?;
    let validate_type_alias_forwarding_args = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10e0b_validate_type_alias_forwarding_args"),
        &passes.type_aliases.validate_forwarding_args,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("compact_hir_count", hir_items.hir.count.as_entire_binding()),
            ("compact_hir_core", hir_items.hir.core.as_entire_binding()),
            (
                "compact_type_arg_count",
                hir_items.hir.type_arg_count.as_entire_binding(),
            ),
            (
                "compact_type_args",
                hir_items.hir.type_args.as_entire_binding(),
            ),
            (
                "type_generic_param_slot_by_token",
                type_generic_param_slot_by_token.as_entire_binding(),
            ),
            ("alias_forwarding", alias_forwarding.as_entire_binding()),
            (
                "alias_forwarding_valid_arg_count",
                alias_forwarding_valid_arg_count.as_entire_binding(),
            ),
            (
                "alias_decl_by_target_hir",
                alias_decl_by_target_hir.as_entire_binding(),
            ),
        ],
    )?;
    let init_type_alias_roots = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10e1_init_type_alias_roots"),
        &passes.type_aliases.init_roots,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("compact_hir_count", hir_items.hir.count.as_entire_binding()),
            (
                "compact_hir_payload",
                hir_items.hir.payload.as_entire_binding(),
            ),
            (
                "compact_type_alias_target",
                hir_items.hir.type_alias_target.as_entire_binding(),
            ),
            ("decl_count_out", decl_count_out.as_entire_binding()),
            ("decl_kind", decl_kind.as_entire_binding()),
            ("decl_namespace", decl_namespace.as_entire_binding()),
            ("decl_hir_node", decl_hir_node.as_entire_binding()),
            (
                "path_id_by_owner_hir",
                path_id_by_owner_hir.as_entire_binding(),
            ),
            ("resolved_type_decl", resolved_type_decl.as_entire_binding()),
            (
                "type_decl_generic_param_count_by_owner_token",
                type_decl_generic_param_count_by_owner_token.as_entire_binding(),
            ),
            (
                "compact_type_arg_ranges",
                hir_items.hir.type_arg_ranges.as_entire_binding(),
            ),
            ("alias_forwarding", alias_forwarding.as_entire_binding()),
            (
                "alias_forwarding_target_decl",
                alias_forwarding_target_decl.as_entire_binding(),
            ),
            (
                "alias_forwarding_valid_arg_count",
                alias_forwarding_valid_arg_count.as_entire_binding(),
            ),
            ("alias_root_decl", alias_root_a.as_entire_binding()),
        ],
    )?;
    let jump_type_alias_roots_a_to_b = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10e1a_jump_type_alias_roots_a_to_b"),
        &passes.type_aliases.jump_roots,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("alias_root_decl_in", alias_root_a.as_entire_binding()),
            ("alias_root_decl_out", alias_root_b.as_entire_binding()),
        ],
    )?;
    let jump_type_alias_roots_b_to_a = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10e1a_jump_type_alias_roots_b_to_a"),
        &passes.type_aliases.jump_roots,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("alias_root_decl_in", alias_root_b.as_entire_binding()),
            ("alias_root_decl_out", alias_root_a.as_entire_binding()),
        ],
    )?;
    let alias_root_jump_rounds = u32::BITS - alias_root_capacity.saturating_sub(1).leading_zeros();
    let final_alias_root = if alias_root_jump_rounds % 2 == 0 {
        &alias_root_a
    } else {
        &alias_root_b
    };
    let clear_alias_equivalence = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10e0c_clear_type_alias_equivalence"),
        &passes.type_aliases.clear_equivalence,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "alias_equiv_parent_a",
                alias_equiv_parent_a.as_entire_binding(),
            ),
            (
                "alias_equiv_parent_b",
                alias_equiv_parent_b.as_entire_binding(),
            ),
            ("alias_equiv_edge_0", alias_equiv_edge_0.as_entire_binding()),
            ("alias_equiv_edge_1", alias_equiv_edge_1.as_entire_binding()),
            (
                "alias_equiv_component_source",
                alias_equiv_component_source.as_entire_binding(),
            ),
            (
                "alias_normalized_source",
                alias_normalized_source.as_entire_binding(),
            ),
        ],
    )?;
    let init_alias_decl_edges = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10e0d_init_type_alias_decl_edges"),
        &passes.type_aliases.init_decl_edges,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("compact_hir_count", hir_items.hir.count.as_entire_binding()),
            ("compact_hir_core", hir_items.hir.core.as_entire_binding()),
            (
                "compact_hir_payload",
                hir_items.hir.payload.as_entire_binding(),
            ),
            (
                "compact_type_alias_target",
                hir_items.hir.type_alias_target.as_entire_binding(),
            ),
            ("decl_count_out", decl_count_out.as_entire_binding()),
            ("decl_kind", decl_kind.as_entire_binding()),
            ("decl_namespace", decl_namespace.as_entire_binding()),
            ("decl_hir_node", decl_hir_node.as_entire_binding()),
            (
                "path_id_by_owner_hir",
                path_id_by_owner_hir.as_entire_binding(),
            ),
            ("resolved_type_decl", resolved_type_decl.as_entire_binding()),
            (
                "generic_param_count_out",
                generic_param_count_out.as_entire_binding(),
            ),
            (
                "generic_param_owner_token",
                generic_param_owner_token.as_entire_binding(),
            ),
            (
                "generic_param_token",
                generic_param_token.as_entire_binding(),
            ),
            ("generic_param_kind", generic_param_kind.as_entire_binding()),
            (
                "generic_param_slot_order",
                generic_param_slot_order.as_entire_binding(),
            ),
            (
                "type_generic_param_slot_by_token",
                type_generic_param_slot_by_token.as_entire_binding(),
            ),
            ("alias_equiv_edge_0", alias_equiv_edge_0.as_entire_binding()),
            (
                "alias_source_hir_by_target_hir",
                alias_decl_by_target_hir.as_entire_binding(),
            ),
        ],
    )?;
    let init_alias_arg_edges = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10e0e_init_type_alias_arg_edges"),
        &passes.type_aliases.init_arg_edges,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("compact_hir_count", hir_items.hir.count.as_entire_binding()),
            ("compact_hir_core", hir_items.hir.core.as_entire_binding()),
            (
                "compact_hir_payload",
                hir_items.hir.payload.as_entire_binding(),
            ),
            (
                "compact_type_arg_count",
                hir_items.hir.type_arg_count.as_entire_binding(),
            ),
            (
                "compact_type_args",
                hir_items.hir.type_args.as_entire_binding(),
            ),
            (
                "alias_source_hir_by_target_hir",
                alias_decl_by_target_hir.as_entire_binding(),
            ),
            ("decl_count_out", decl_count_out.as_entire_binding()),
            ("decl_kind", decl_kind.as_entire_binding()),
            ("decl_namespace", decl_namespace.as_entire_binding()),
            ("decl_hir_node", decl_hir_node.as_entire_binding()),
            (
                "path_id_by_owner_hir",
                path_id_by_owner_hir.as_entire_binding(),
            ),
            ("resolved_type_decl", resolved_type_decl.as_entire_binding()),
            (
                "generic_param_count_out",
                generic_param_count_out.as_entire_binding(),
            ),
            (
                "generic_param_owner_token",
                generic_param_owner_token.as_entire_binding(),
            ),
            (
                "generic_param_token",
                generic_param_token.as_entire_binding(),
            ),
            ("generic_param_kind", generic_param_kind.as_entire_binding()),
            (
                "generic_param_slot_order",
                generic_param_slot_order.as_entire_binding(),
            ),
            (
                "type_generic_param_slot_by_token",
                type_generic_param_slot_by_token.as_entire_binding(),
            ),
            ("type_expr_ref_tag", type_expr_ref_tag.as_entire_binding()),
            (
                "type_expr_ref_payload",
                type_expr_ref_payload.as_entire_binding(),
            ),
            ("alias_equiv_edge_0", alias_equiv_edge_0.as_entire_binding()),
            ("alias_equiv_edge_1", alias_equiv_edge_1.as_entire_binding()),
        ],
    )?;
    let hook_alias_equivalence = |label: &'static str, parent: &LaniusBuffer<u32>| {
        bind_group::create_bind_group_from_bindings(
            device,
            Some(label),
            &passes.type_aliases.hook_equivalence,
            0,
            &[
                ("gParams", params.as_entire_binding()),
                ("alias_equiv_edge_0", alias_equiv_edge_0.as_entire_binding()),
                ("alias_equiv_edge_1", alias_equiv_edge_1.as_entire_binding()),
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
            bind_group::create_bind_group_from_bindings(
                device,
                Some(label),
                &passes.type_aliases.jump_equivalence,
                0,
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
    // Every round performs both min-parent hooking and a pointer-jump. After
    // r rounds, paths of up to 2^r graph nodes have collapsed, so one
    // capacity-covering logarithm is sufficient. Multiplying this by two
    // replayed the complete convergence schedule a second time.
    let alias_equivalence_rounds =
        (u32::BITS - alias_equiv_capacity.saturating_sub(1).leading_zeros()).max(1);
    let final_alias_equiv_parent = if alias_equivalence_rounds % 2 == 0 {
        &alias_equiv_parent_a
    } else {
        &alias_equiv_parent_b
    };
    let select_alias_generic_sources = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10e0h_select_type_alias_generic_sources"),
        &passes.type_aliases.select_generic_sources,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "generic_param_count_out",
                generic_param_count_out.as_entire_binding(),
            ),
            (
                "generic_param_owner_token",
                generic_param_owner_token.as_entire_binding(),
            ),
            (
                "generic_param_token",
                generic_param_token.as_entire_binding(),
            ),
            ("generic_param_kind", generic_param_kind.as_entire_binding()),
            (
                "type_decl_hir_node_by_token",
                type_decl_hir_node_by_token.as_entire_binding(),
            ),
            (
                "alias_equiv_parent",
                final_alias_equiv_parent.as_entire_binding(),
            ),
            (
                "alias_normalized_source",
                alias_normalized_source.as_entire_binding(),
            ),
        ],
    )?;
    let select_alias_concrete_sources = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10e0i_select_type_alias_concrete_sources"),
        &passes.type_aliases.select_concrete_sources,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("compact_hir_count", hir_items.hir.count.as_entire_binding()),
            ("compact_hir_core", hir_items.hir.core.as_entire_binding()),
            ("type_expr_ref_tag", type_expr_ref_tag.as_entire_binding()),
            (
                "alias_equiv_parent",
                final_alias_equiv_parent.as_entire_binding(),
            ),
            (
                "alias_equiv_component_source",
                alias_equiv_component_source.as_entire_binding(),
            ),
        ],
    )?;
    let finalize_alias_equivalence = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10e0j_finalize_type_alias_equivalence"),
        &passes.type_aliases.finalize_equivalence,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("compact_hir_count", hir_items.hir.count.as_entire_binding()),
            ("compact_hir_core", hir_items.hir.core.as_entire_binding()),
            ("decl_count_out", decl_count_out.as_entire_binding()),
            ("decl_kind", decl_kind.as_entire_binding()),
            ("decl_namespace", decl_namespace.as_entire_binding()),
            ("decl_name_token", decl_name_token.as_entire_binding()),
            ("decl_hir_node", decl_hir_node.as_entire_binding()),
            (
                "alias_equiv_parent",
                final_alias_equiv_parent.as_entire_binding(),
            ),
            (
                "alias_equiv_component_source",
                alias_equiv_component_source.as_entire_binding(),
            ),
            (
                "alias_normalized_source",
                alias_normalized_source.as_entire_binding(),
            ),
            ("type_expr_ref_tag", type_expr_ref_tag.as_entire_binding()),
            (
                "type_expr_ref_payload",
                type_expr_ref_payload.as_entire_binding(),
            ),
            (
                "module_type_path_type",
                module_type_path_type.as_entire_binding(),
            ),
            (
                "module_type_path_status",
                module_type_path_status.as_entire_binding(),
            ),
        ],
    )?;
    let project_type_alias_instances = create_project_type_alias_instances_bind_group(
        device,
        &passes.type_aliases.project_instances,
        params,
        hir_items,
        path_count_out,
        path_id_by_owner_hir,
        path_segment_count,
        path_segment_base,
        path_segment_token,
        type_instance_decl_token,
        type_decl_hir_node_by_token,
        type_generic_param_slot_by_token,
        type_instance_arg_row_start,
        type_instance_arg_row_count_out,
        type_instance_arg_row_ref_tag,
        type_instance_arg_row_ref_payload,
        &alias_normalized_source,
        type_expr_ref_tag,
        type_expr_ref_payload,
    )?;
    let project_type_aliases = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10e2_project_type_aliases"),
        &passes.type_aliases.project,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("compact_hir_count", hir_items.hir.count.as_entire_binding()),
            ("compact_hir_core", hir_items.hir.core.as_entire_binding()),
            (
                "compact_type_alias_target",
                hir_items.hir.type_alias_target.as_entire_binding(),
            ),
            ("decl_count_out", decl_count_out.as_entire_binding()),
            ("decl_kind", decl_kind.as_entire_binding()),
            ("decl_namespace", decl_namespace.as_entire_binding()),
            ("decl_name_token", decl_name_token.as_entire_binding()),
            ("decl_hir_node", decl_hir_node.as_entire_binding()),
            (
                "path_id_by_owner_hir",
                path_id_by_owner_hir.as_entire_binding(),
            ),
            ("resolved_type_decl", resolved_type_decl.as_entire_binding()),
            ("alias_root_decl", final_alias_root.as_entire_binding()),
            ("type_expr_ref_tag", type_expr_ref_tag.as_entire_binding()),
            (
                "type_expr_ref_payload",
                type_expr_ref_payload.as_entire_binding(),
            ),
            (
                "module_type_path_type",
                module_type_path_type.as_entire_binding(),
            ),
            (
                "module_type_path_status",
                module_type_path_status.as_entire_binding(),
            ),
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
    let project_type_instances = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10k_project_type_instances"),
        &passes.modules_project_type_instances,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("path_segment_count", path_segment_count.as_entire_binding()),
            ("path_segment_base", path_segment_base.as_entire_binding()),
            ("path_segment_token", path_segment_token.as_entire_binding()),
            ("path_owner_hir", path_owner_hir.as_entire_binding()),
            ("path_owner_token", path_owner_token.as_entire_binding()),
            ("node_kind", hir_items.node_kind.as_entire_binding()),
            ("parent", hir_items.parent.as_entire_binding()),
            ("resolved_type_decl", resolved_type_decl.as_entire_binding()),
            ("decl_name_token", decl_name_token.as_entire_binding()),
            ("type_instance_kind", type_instance_kind.as_entire_binding()),
            (
                "type_instance_arg_count",
                type_instance_arg_count.as_entire_binding(),
            ),
            (
                "type_decl_generic_param_count",
                type_decl_generic_param_count.as_entire_binding(),
            ),
            ("type_expr_ref_tag", type_expr_ref_tag.as_entire_binding()),
            (
                "type_expr_ref_payload",
                type_expr_ref_payload.as_entire_binding(),
            ),
            (
                "type_instance_decl_token",
                type_instance_decl_token.as_entire_binding(),
            ),
            (
                "type_instance_state",
                type_instance_state.as_entire_binding(),
            ),
            (
                "module_type_path_type",
                module_type_path_type.as_entire_binding(),
            ),
        ],
    )?;
    let mark_value_call_paths = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10f_mark_value_call_paths"),
        &passes.modules_mark_value_call_paths,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("compact_hir_count", hir_items.hir.count.as_entire_binding()),
            ("compact_hir_core", hir_items.hir.core.as_entire_binding()),
            ("compact_hir_links", hir_items.hir.links.as_entire_binding()),
            (
                "compact_hir_payload",
                hir_items.hir.payload.as_entire_binding(),
            ),
            ("path_count_out", path_count_out.as_entire_binding()),
            (
                "path_id_by_owner_hir",
                path_id_by_owner_hir.as_entire_binding(),
            ),
            ("path_owner_token", path_owner_token.as_entire_binding()),
            ("path_kind", path_kind.as_entire_binding()),
            ("path_segment_count", path_segment_count.as_entire_binding()),
            ("path_segment_base", path_segment_base.as_entire_binding()),
            ("path_segment_token", path_segment_token.as_entire_binding()),
            ("call_arg_record", call_arg_record.as_entire_binding()),
            (
                "module_value_path_call_head",
                module_value_path_call_head.as_entire_binding(),
            ),
            (
                "module_value_path_call_open",
                module_value_path_call_open.as_entire_binding(),
            ),
            (
                "module_value_path_call_path_id",
                module_value_path_call_path_id.as_entire_binding(),
            ),
            (
                "module_value_path_call_leaf",
                module_value_path_call_leaf.as_entire_binding(),
            ),
            (
                "module_value_path_associated_method_token",
                module_value_path_associated_method_token.as_entire_binding(),
            ),
            (
                "module_value_path_associated_receiver_token",
                module_value_path_associated_receiver_token.as_entire_binding(),
            ),
            (
                "module_value_path_expr_head",
                module_value_path_expr_head.as_entire_binding(),
            ),
        ],
    )?;
    let project_value_paths = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10g_project_value_paths"),
        &passes.modules_project_value_paths,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("first_child", hir_items.first_child.as_entire_binding()),
            ("next_sibling", hir_items.next_sibling.as_entire_binding()),
            ("subtree_end", hir_items.subtree_end.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            (
                "hir_member_name_token",
                hir_items.member_name_token.as_entire_binding(),
            ),
            ("hir_expr_record", hir_items.expr_record.as_entire_binding()),
            ("hir_stmt_record", hir_items.stmt_record.as_entire_binding()),
            (
                "hir_call_callee_node",
                hir_items.call_callee_node.as_entire_binding(),
            ),
            (
                "compact_variant_count",
                hir_items.hir.variant_count.as_entire_binding(),
            ),
            (
                "compact_variant_payload_count",
                hir_items.hir.variant_payload_count.as_entire_binding(),
            ),
            ("path_count_out", path_count_out.as_entire_binding()),
            ("path_kind", path_kind.as_entire_binding()),
            ("path_segment_count", path_segment_count.as_entire_binding()),
            ("path_segment_base", path_segment_base.as_entire_binding()),
            ("path_segment_token", path_segment_token.as_entire_binding()),
            ("path_owner_token", path_owner_token.as_entire_binding()),
            ("resolved_type_decl", resolved_type_decl.as_entire_binding()),
            (
                "resolved_value_status",
                resolved_value_status.as_entire_binding(),
            ),
            (
                "module_type_path_status",
                module_type_path_status.as_entire_binding(),
            ),
            (
                "module_value_path_call_head",
                module_value_path_call_head.as_entire_binding(),
            ),
            (
                "module_value_path_expr_head",
                module_value_path_expr_head.as_entire_binding(),
            ),
            (
                "module_value_path_associated_method_token",
                module_value_path_associated_method_token.as_entire_binding(),
            ),
            (
                "module_value_path_status",
                module_value_path_status.as_entire_binding(),
            ),
        ],
    )?;
    let consume_value_calls = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10h_consume_value_calls"),
        &passes.modules_consume_value_calls,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("path_count_out", path_count_out.as_entire_binding()),
            ("path_segment_count", path_segment_count.as_entire_binding()),
            ("path_segment_base", path_segment_base.as_entire_binding()),
            ("path_segment_token", path_segment_token.as_entire_binding()),
            ("path_owner_hir", path_owner_hir.as_entire_binding()),
            ("path_owner_token", path_owner_token.as_entire_binding()),
            ("resolved_type_decl", resolved_type_decl.as_entire_binding()),
            (
                "resolved_value_decl",
                resolved_value_decl.as_entire_binding(),
            ),
            (
                "resolved_value_status",
                resolved_value_status.as_entire_binding(),
            ),
            ("decl_name_token", decl_name_token.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            (
                "hir_call_parent_by_callee",
                hir_items.call_parent_by_callee.as_entire_binding(),
            ),
            (
                "hir_call_arg_count",
                hir_items.call_arg_count.as_entire_binding(),
            ),
            ("call_arg_record", call_arg_record.as_entire_binding()),
            ("call_arg_row_count", call_arg_row_count.as_entire_binding()),
            (
                "module_value_path_call_head",
                module_value_path_call_head.as_entire_binding(),
            ),
            (
                "module_value_path_call_open",
                module_value_path_call_open.as_entire_binding(),
            ),
            (
                "module_value_path_associated_method_token",
                module_value_path_associated_method_token.as_entire_binding(),
            ),
            ("call_param_count", call_param_count.as_entire_binding()),
            (
                "module_value_path_status",
                module_value_path_status.as_entire_binding(),
            ),
            ("call_fn_index", call_fn_index.as_entire_binding()),
            ("call_return_type", call_return_type.as_entire_binding()),
            (
                "call_return_type_token",
                call_return_type_token.as_entire_binding(),
            ),
            (
                "method_call_name_id",
                method_call_name_id.as_entire_binding(),
            ),
            ("status", status_buf.as_entire_binding()),
        ],
    )?;
    let mirror_value_call_leaf = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10h2_mirror_value_call_leaf"),
        &passes.modules_mirror_value_call_leaf,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("path_count_out", path_count_out.as_entire_binding()),
            ("path_segment_count", path_segment_count.as_entire_binding()),
            ("path_segment_base", path_segment_base.as_entire_binding()),
            ("path_segment_token", path_segment_token.as_entire_binding()),
            ("path_owner_token", path_owner_token.as_entire_binding()),
            ("call_fn_index", call_fn_index.as_entire_binding()),
            ("call_return_type", call_return_type.as_entire_binding()),
            (
                "call_return_type_token",
                call_return_type_token.as_entire_binding(),
            ),
            (
                "call_generic_slot_type",
                call_generic_slot_type.as_entire_binding(),
            ),
            (
                "call_generic_slot_ordinal",
                call_generic_slot_ordinal.as_entire_binding(),
            ),
        ],
    )?;
    let consume_value_consts = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10i_consume_value_consts"),
        &passes.modules_consume_value_consts,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("node_kind", hir_items.node_kind.as_entire_binding()),
            ("parent", hir_items.parent.as_entire_binding()),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            ("hir_expr_record", hir_items.expr_record.as_entire_binding()),
            ("hir_stmt_record", hir_items.stmt_record.as_entire_binding()),
            (
                "compact_variant_count",
                hir_items.hir.variant_count.as_entire_binding(),
            ),
            (
                "compact_variant_payload_count",
                hir_items.hir.variant_payload_count.as_entire_binding(),
            ),
            ("path_count_out", path_count_out.as_entire_binding()),
            ("path_kind", path_kind.as_entire_binding()),
            ("path_segment_count", path_segment_count.as_entire_binding()),
            ("path_segment_base", path_segment_base.as_entire_binding()),
            ("path_segment_token", path_segment_token.as_entire_binding()),
            ("path_owner_token", path_owner_token.as_entire_binding()),
            (
                "resolved_value_decl",
                resolved_value_decl.as_entire_binding(),
            ),
            (
                "resolved_value_status",
                resolved_value_status.as_entire_binding(),
            ),
            ("decl_kind", decl_kind.as_entire_binding()),
            ("decl_name_token", decl_name_token.as_entire_binding()),
            (
                "module_value_path_call_head",
                module_value_path_call_head.as_entire_binding(),
            ),
            (
                "module_value_path_expr_head",
                module_value_path_expr_head.as_entire_binding(),
            ),
            (
                "module_value_path_status",
                module_value_path_status.as_entire_binding(),
            ),
            (
                "module_value_path_const_head",
                module_value_path_const_head.as_entire_binding(),
            ),
            (
                "module_value_path_const_end",
                module_value_path_const_end.as_entire_binding(),
            ),
            ("visible_decl", visible_decl.as_entire_binding()),
            ("enclosing_fn", enclosing_fn.as_entire_binding()),
            ("visible_type", visible_type.as_entire_binding()),
        ],
    )?;
    let consume_value_enum_units = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10j_consume_value_enum_units"),
        &passes.modules_consume_value_enum_units,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("path_count_out", path_count_out.as_entire_binding()),
            ("path_kind", path_kind.as_entire_binding()),
            ("path_segment_count", path_segment_count.as_entire_binding()),
            ("path_owner_token", path_owner_token.as_entire_binding()),
            (
                "resolved_value_decl",
                resolved_value_decl.as_entire_binding(),
            ),
            (
                "resolved_value_status",
                resolved_value_status.as_entire_binding(),
            ),
            ("decl_kind", decl_kind.as_entire_binding()),
            ("decl_namespace", decl_namespace.as_entire_binding()),
            ("decl_name_token", decl_name_token.as_entire_binding()),
            ("decl_hir_node", decl_hir_node.as_entire_binding()),
            (
                "decl_parent_type_decl",
                decl_parent_type_decl.as_entire_binding(),
            ),
            (
                "compact_variant_count",
                hir_items.hir.variant_count.as_entire_binding(),
            ),
            (
                "compact_variant_payload_count",
                hir_items.hir.variant_payload_count.as_entire_binding(),
            ),
            (
                "module_value_path_call_head",
                module_value_path_call_head.as_entire_binding(),
            ),
            (
                "module_value_path_expr_head",
                module_value_path_expr_head.as_entire_binding(),
            ),
            (
                "module_value_path_status",
                module_value_path_status.as_entire_binding(),
            ),
            ("visible_decl", visible_decl.as_entire_binding()),
            (
                "module_value_path_status",
                module_value_path_status.as_entire_binding(),
            ),
            ("visible_type", visible_type.as_entire_binding()),
        ],
    )?;
    let enum_call_bindings = [
        ("gParams", params.as_entire_binding()),
        ("compact_hir_count", hir_items.hir.count.as_entire_binding()),
        ("compact_hir_core", hir_items.hir.core.as_entire_binding()),
        (
            "compact_hir_payload",
            hir_items.hir.payload.as_entire_binding(),
        ),
        (
            "compact_variant_count",
            hir_items.hir.variant_count.as_entire_binding(),
        ),
        (
            "compact_variants",
            hir_items.hir.variants.as_entire_binding(),
        ),
        (
            "compact_variant_payload_start",
            hir_items.hir.variant_payload_start.as_entire_binding(),
        ),
        (
            "compact_variant_payload_count",
            hir_items.hir.variant_payload_count.as_entire_binding(),
        ),
        (
            "compact_variant_payload_row_count",
            hir_items.hir.variant_payload_row_count.as_entire_binding(),
        ),
        (
            "compact_variant_payloads",
            hir_items.hir.variant_payloads.as_entire_binding(),
        ),
        ("node_kind", hir_items.node_kind.as_entire_binding()),
        ("path_count_out", path_count_out.as_entire_binding()),
        ("path_kind", path_kind.as_entire_binding()),
        ("path_call_hir", path_call_hir.as_entire_binding()),
        ("path_segment_count", path_segment_count.as_entire_binding()),
        ("path_segment_base", path_segment_base.as_entire_binding()),
        ("path_segment_token", path_segment_token.as_entire_binding()),
        ("path_owner_token", path_owner_token.as_entire_binding()),
        (
            "resolved_value_decl",
            resolved_value_decl.as_entire_binding(),
        ),
        (
            "resolved_value_status",
            resolved_value_status.as_entire_binding(),
        ),
        ("decl_kind", decl_kind.as_entire_binding()),
        ("decl_namespace", decl_namespace.as_entire_binding()),
        ("decl_name_token", decl_name_token.as_entire_binding()),
        (
            "decl_parent_type_decl",
            decl_parent_type_decl.as_entire_binding(),
        ),
        ("decl_hir_node", decl_hir_node.as_entire_binding()),
        (
            "module_value_path_call_head",
            module_value_path_call_head.as_entire_binding(),
        ),
        (
            "module_value_path_expr_head",
            module_value_path_expr_head.as_entire_binding(),
        ),
        (
            "type_decl_generic_param_count",
            type_decl_generic_param_count.as_entire_binding(),
        ),
        (
            "type_generic_param_slot_by_token",
            type_generic_param_slot_by_token.as_entire_binding(),
        ),
        (
            "generic_param_count_out",
            generic_param_count_out.as_entire_binding(),
        ),
        (
            "generic_param_owner_token",
            generic_param_owner_token.as_entire_binding(),
        ),
        (
            "generic_param_name_id",
            generic_param_name_id.as_entire_binding(),
        ),
        (
            "generic_param_token",
            generic_param_token.as_entire_binding(),
        ),
        ("generic_param_kind", generic_param_kind.as_entire_binding()),
        (
            "generic_param_key_order",
            generic_param_key_order.as_entire_binding(),
        ),
        ("type_expr_ref_tag", type_expr_ref_tag.as_entire_binding()),
        (
            "type_expr_ref_payload",
            type_expr_ref_payload.as_entire_binding(),
        ),
        (
            "type_instance_decl_token",
            type_instance_decl_token.as_entire_binding(),
        ),
        (
            "type_instance_arg_start",
            type_instance_arg_start.as_entire_binding(),
        ),
        (
            "type_instance_arg_count",
            type_instance_arg_count.as_entire_binding(),
        ),
        (
            "type_instance_arg_ref_tag",
            type_instance_arg_ref_tag.as_entire_binding(),
        ),
        (
            "type_instance_arg_ref_payload",
            type_instance_arg_ref_payload.as_entire_binding(),
        ),
        (
            "type_instance_arg_row_start",
            type_instance_arg_row_start.as_entire_binding(),
        ),
        (
            "type_instance_arg_row_count_out",
            type_instance_arg_row_count_out.as_entire_binding(),
        ),
        (
            "type_instance_arg_row_ref_tag",
            type_instance_arg_row_ref_tag.as_entire_binding(),
        ),
        (
            "type_instance_arg_row_ref_payload",
            type_instance_arg_row_ref_payload.as_entire_binding(),
        ),
        (
            "type_instance_state",
            type_instance_state.as_entire_binding(),
        ),
        ("decl_type_ref_tag", decl_type_ref_tag.as_entire_binding()),
        (
            "decl_type_ref_payload",
            decl_type_ref_payload.as_entire_binding(),
        ),
        ("fn_return_ref_tag", fn_return_ref_tag.as_entire_binding()),
        (
            "fn_return_ref_payload",
            fn_return_ref_payload.as_entire_binding(),
        ),
        ("visible_decl", visible_decl.as_entire_binding()),
        ("enclosing_fn", enclosing_fn.as_entire_binding()),
        ("visible_type", visible_type.as_entire_binding()),
        ("name_id_by_token", name_id_by_token.as_entire_binding()),
        ("call_arg_row_node", call_arg_row_node.as_entire_binding()),
        (
            "call_arg_row_call_node",
            call_arg_row_call_node.as_entire_binding(),
        ),
        (
            "call_arg_row_ordinal",
            call_arg_row_ordinal.as_entire_binding(),
        ),
        ("call_arg_row_start", call_arg_row_start.as_entire_binding()),
        ("call_arg_row_count", call_arg_row_count.as_entire_binding()),
        (
            "module_value_path_status",
            module_value_path_status.as_entire_binding(),
        ),
        ("call_return_type", call_return_type.as_entire_binding()),
    ];
    let consume_value_enum_calls = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10l_consume_value_enum_calls"),
        &passes.modules_consume_value_enum_calls,
        0,
        &enum_call_bindings,
    )?;
    let validate_value_enum_call_payloads = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10l2_validate_value_enum_call_payloads"),
        &passes.modules_validate_value_enum_call_payloads,
        0,
        &enum_call_bindings,
    )?;
    let finalize_value_enum_calls = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10l3_finalize_value_enum_calls"),
        &passes.modules_finalize_value_enum_calls,
        0,
        &enum_call_bindings,
    )?;
    let bind_match_patterns = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10m_bind_match_patterns"),
        &passes.modules_bind_match_patterns,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("compact_hir_count", hir_items.hir.count.as_entire_binding()),
            ("compact_hir_core", hir_items.hir.core.as_entire_binding()),
            ("compact_hir_links", hir_items.hir.links.as_entire_binding()),
            (
                "compact_match_arm_count",
                hir_items.hir.match_arm_count.as_entire_binding(),
            ),
            (
                "compact_match_arms",
                hir_items.hir.match_arms.as_entire_binding(),
            ),
            (
                "compact_match_payload_start",
                hir_items.hir.match_payload_start.as_entire_binding(),
            ),
            (
                "compact_match_payload_count",
                hir_items.hir.match_payload_count.as_entire_binding(),
            ),
            (
                "compact_match_payload_row_count",
                hir_items.hir.match_payload_row_count.as_entire_binding(),
            ),
            (
                "compact_match_payloads",
                hir_items.hir.match_payloads.as_entire_binding(),
            ),
            (
                "compact_variant_count",
                hir_items.hir.variant_count.as_entire_binding(),
            ),
            (
                "compact_variant_payload_count",
                hir_items.hir.variant_payload_count.as_entire_binding(),
            ),
            ("token_words", token_buf.as_entire_binding()),
            ("language_name_id", language_name_id.as_entire_binding()),
            ("node_kind", hir_items.node_kind.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            ("hir_token_end", hir_token_end_buf.as_entire_binding()),
            ("subtree_end", hir_items.subtree_end.as_entire_binding()),
            ("path_count_out", path_count_out.as_entire_binding()),
            ("path_owner_hir", path_owner_hir.as_entire_binding()),
            (
                "path_id_by_owner_hir",
                path_id_by_owner_hir.as_entire_binding(),
            ),
            ("path_owner_token", path_owner_token.as_entire_binding()),
            (
                "resolved_value_decl",
                resolved_value_decl.as_entire_binding(),
            ),
            (
                "resolved_value_status",
                resolved_value_status.as_entire_binding(),
            ),
            ("decl_kind", decl_kind.as_entire_binding()),
            ("decl_name_token", decl_name_token.as_entire_binding()),
            ("decl_hir_node", decl_hir_node.as_entire_binding()),
            (
                "decl_parent_type_decl",
                decl_parent_type_decl.as_entire_binding(),
            ),
            ("name_id_by_token", name_id_by_token.as_entire_binding()),
            ("visible_decl", visible_decl.as_entire_binding()),
            ("visible_type", visible_type.as_entire_binding()),
            (
                "module_value_path_status",
                module_value_path_status.as_entire_binding(),
            ),
            ("status", status_buf.as_entire_binding()),
        ],
    )?;
    let type_match_payloads = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10m2_type_match_payloads"),
        &passes.modules_type_match_payloads,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("compact_hir_count", hir_items.hir.count.as_entire_binding()),
            ("compact_hir_core", hir_items.hir.core.as_entire_binding()),
            (
                "compact_hir_payload",
                hir_items.hir.payload.as_entire_binding(),
            ),
            (
                "compact_match_arm_count",
                hir_items.hir.match_arm_count.as_entire_binding(),
            ),
            (
                "compact_match_arms",
                hir_items.hir.match_arms.as_entire_binding(),
            ),
            (
                "compact_match_payload_row_count",
                hir_items.hir.match_payload_row_count.as_entire_binding(),
            ),
            (
                "compact_match_payloads",
                hir_items.hir.match_payloads.as_entire_binding(),
            ),
            (
                "compact_variant_count",
                hir_items.hir.variant_count.as_entire_binding(),
            ),
            (
                "compact_variant_payload_start",
                hir_items.hir.variant_payload_start.as_entire_binding(),
            ),
            (
                "compact_variant_payload_count",
                hir_items.hir.variant_payload_count.as_entire_binding(),
            ),
            (
                "compact_variant_payload_row_count",
                hir_items.hir.variant_payload_row_count.as_entire_binding(),
            ),
            (
                "compact_variant_payloads",
                hir_items.hir.variant_payloads.as_entire_binding(),
            ),
            ("token_words", token_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("node_kind", hir_items.node_kind.as_entire_binding()),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            ("hir_token_end", hir_token_end_buf.as_entire_binding()),
            ("visible_decl", visible_decl.as_entire_binding()),
            (
                "module_value_path_status",
                module_value_path_status.as_entire_binding(),
            ),
            ("visible_type", visible_type.as_entire_binding()),
            (
                "decl_id_by_name_token",
                decl_id_by_name_token.as_entire_binding(),
            ),
            ("decl_kind", decl_kind.as_entire_binding()),
            ("decl_name_token", decl_name_token.as_entire_binding()),
            ("decl_hir_node", decl_hir_node.as_entire_binding()),
            (
                "decl_parent_type_decl",
                decl_parent_type_decl.as_entire_binding(),
            ),
            ("decl_type_ref_tag", decl_type_ref_tag.as_entire_binding()),
            (
                "decl_type_ref_payload",
                decl_type_ref_payload.as_entire_binding(),
            ),
            ("type_expr_ref_tag", type_expr_ref_tag.as_entire_binding()),
            (
                "type_expr_ref_payload",
                type_expr_ref_payload.as_entire_binding(),
            ),
            (
                "type_instance_decl_token",
                type_instance_decl_token.as_entire_binding(),
            ),
            (
                "type_instance_arg_start",
                type_instance_arg_start.as_entire_binding(),
            ),
            (
                "type_instance_arg_count",
                type_instance_arg_count.as_entire_binding(),
            ),
            (
                "type_instance_arg_ref_tag",
                type_instance_arg_ref_tag.as_entire_binding(),
            ),
            (
                "type_instance_arg_ref_payload",
                type_instance_arg_ref_payload.as_entire_binding(),
            ),
            (
                "type_instance_arg_row_start",
                type_instance_arg_row_start.as_entire_binding(),
            ),
            (
                "type_instance_arg_row_count_out",
                type_instance_arg_row_count_out.as_entire_binding(),
            ),
            (
                "type_instance_arg_row_ref_tag",
                type_instance_arg_row_ref_tag.as_entire_binding(),
            ),
            (
                "type_instance_arg_row_ref_payload",
                type_instance_arg_row_ref_payload.as_entire_binding(),
            ),
            ("name_id_by_token", name_id_by_token.as_entire_binding()),
            (
                "type_generic_param_slot_by_token",
                type_generic_param_slot_by_token.as_entire_binding(),
            ),
        ],
    )?;
    let type_match_exprs = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10n_type_match_exprs"),
        &passes.modules_type_match_exprs,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("compact_hir_count", hir_items.hir.count.as_entire_binding()),
            ("compact_hir_core", hir_items.hir.core.as_entire_binding()),
            (
                "compact_hir_payload",
                hir_items.hir.payload.as_entire_binding(),
            ),
            (
                "compact_match_arm_count",
                hir_items.hir.match_arm_count.as_entire_binding(),
            ),
            (
                "compact_match_arms",
                hir_items.hir.match_arms.as_entire_binding(),
            ),
            ("token_count", token_count_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("node_kind", hir_items.node_kind.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            (
                "hir_call_callee_node",
                hir_items.call_callee_node.as_entire_binding(),
            ),
            ("hir_expr_record", hir_items.expr_record.as_entire_binding()),
            (
                "hir_expr_result_root_node",
                hir_items.expr_result_root_node.as_entire_binding(),
            ),
            (
                "hir_member_name_token",
                hir_items.member_name_token.as_entire_binding(),
            ),
            (
                "hir_struct_lit_head_node",
                hir_items.struct_lit_head_node.as_entire_binding(),
            ),
            ("visible_decl", visible_decl.as_entire_binding()),
            ("visible_type", visible_type.as_entire_binding()),
            ("call_return_type", call_return_type.as_entire_binding()),
            ("status", status_buf.as_entire_binding()),
        ],
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
