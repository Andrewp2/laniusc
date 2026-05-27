use anyhow::Result;

use super::{super::*, buffers::Buffers, inputs::CreateInputs};

pub(in crate::type_checker) struct ProjectionBindGroups {
    pub(in crate::type_checker) clear_type_path_types: wgpu::BindGroup,
    pub(in crate::type_checker) project_type_paths: wgpu::BindGroup,
    pub(in crate::type_checker) validate_type_paths: wgpu::BindGroup,
    pub(in crate::type_checker) project_type_aliases: wgpu::BindGroup,
    pub(in crate::type_checker) project_type_instances: wgpu::BindGroup,
    pub(in crate::type_checker) mark_value_call_paths: wgpu::BindGroup,
    pub(in crate::type_checker) project_value_paths: wgpu::BindGroup,
    pub(in crate::type_checker) consume_value_calls: wgpu::BindGroup,
    pub(in crate::type_checker) mirror_value_call_leaf: wgpu::BindGroup,
    pub(in crate::type_checker) consume_value_consts: wgpu::BindGroup,
    pub(in crate::type_checker) consume_value_enum_units: wgpu::BindGroup,
    pub(in crate::type_checker) consume_value_enum_calls: wgpu::BindGroup,
    pub(in crate::type_checker) bind_match_patterns: wgpu::BindGroup,
    pub(in crate::type_checker) type_match_payloads: wgpu::BindGroup,
    pub(in crate::type_checker) type_match_exprs: wgpu::BindGroup,
}

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
        module_value_path_const_head,
        module_value_path_const_end,
        module_value_path_status,
        visible_decl,
        visible_type,
        enclosing_fn,
        call_fn_index,
        call_return_type,
        call_return_type_token,
        call_param_count,
        call_param_type,
        call_param_ref_tag,
        call_param_ref_payload,
        call_arg_record,
        type_expr_ref_tag,
        type_expr_ref_payload,
        type_instance_kind,
        type_instance_decl_token,
        type_instance_arg_start,
        type_instance_arg_count,
        type_instance_arg_ref_tag,
        type_instance_arg_ref_payload,
        type_decl_generic_param_count,
        type_generic_param_slot_by_token,
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
        decl_token_start,
        resolved_type_decl,
        resolved_value_decl,
        resolved_type_status,
        resolved_value_status,
        path_segment_count,
        path_segment_base,
        path_segment_token,
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
    let project_type_aliases = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10e2_project_type_aliases"),
        &passes.modules_project_type_aliases,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            (
                "hir_type_alias_target_node",
                hir_items.type_alias_target_node.as_entire_binding(),
            ),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
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
            ("path_owner_token", path_owner_token.as_entire_binding()),
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
        ],
    )?;
    let mark_value_call_paths = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10f_mark_value_call_paths"),
        &passes.modules_mark_value_call_paths,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("parent", hir_items.parent.as_entire_binding()),
            ("next_sibling", hir_items.next_sibling.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            ("hir_token_end", hir_token_end_buf.as_entire_binding()),
            (
                "module_value_path_call_head",
                module_value_path_call_head.as_entire_binding(),
            ),
            (
                "module_value_path_call_open",
                module_value_path_call_open.as_entire_binding(),
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
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("node_kind", hir_items.node_kind.as_entire_binding()),
            ("parent", hir_items.parent.as_entire_binding()),
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
                "hir_variant_payload_start",
                hir_items.variant_payload_start.as_entire_binding(),
            ),
            (
                "hir_variant_payload_count",
                hir_items.variant_payload_count.as_entire_binding(),
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
            ("path_owner_token", path_owner_token.as_entire_binding()),
            (
                "resolved_value_decl",
                resolved_value_decl.as_entire_binding(),
            ),
            (
                "resolved_value_status",
                resolved_value_status.as_entire_binding(),
            ),
            ("decl_token_start", decl_token_start.as_entire_binding()),
            ("parent", hir_items.parent.as_entire_binding()),
            (
                "hir_param_record",
                hir_items.param_record.as_entire_binding(),
            ),
            ("hir_expr_record", hir_items.expr_record.as_entire_binding()),
            ("hir_stmt_record", hir_items.stmt_record.as_entire_binding()),
            ("call_arg_record", call_arg_record.as_entire_binding()),
            (
                "module_value_path_call_open",
                module_value_path_call_open.as_entire_binding(),
            ),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            (
                "hir_call_callee_node",
                hir_items.call_callee_node.as_entire_binding(),
            ),
            (
                "hir_call_arg_parent_call",
                hir_items.call_arg_parent_call.as_entire_binding(),
            ),
            (
                "hir_call_arg_ordinal",
                hir_items.call_arg_ordinal.as_entire_binding(),
            ),
            ("call_param_count", call_param_count.as_entire_binding()),
            ("call_param_type", call_param_type.as_entire_binding()),
            ("call_param_ref_tag", call_param_ref_tag.as_entire_binding()),
            (
                "call_param_ref_payload",
                call_param_ref_payload.as_entire_binding(),
            ),
            ("visible_decl", visible_decl.as_entire_binding()),
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
            (
                "type_generic_param_slot_by_token",
                type_generic_param_slot_by_token.as_entire_binding(),
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
                "module_value_path_status",
                module_value_path_status.as_entire_binding(),
            ),
            ("enclosing_fn", enclosing_fn.as_entire_binding()),
            ("call_fn_index", call_fn_index.as_entire_binding()),
            ("call_return_type", call_return_type.as_entire_binding()),
            (
                "call_return_type_token",
                call_return_type_token.as_entire_binding(),
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
                "hir_call_arg_parent_call",
                hir_items.call_arg_parent_call.as_entire_binding(),
            ),
            (
                "hir_variant_payload_start",
                hir_items.variant_payload_start.as_entire_binding(),
            ),
            (
                "hir_variant_payload_count",
                hir_items.variant_payload_count.as_entire_binding(),
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
                "hir_variant_payload_count",
                hir_items.variant_payload_count.as_entire_binding(),
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
            ("visible_type", visible_type.as_entire_binding()),
        ],
    )?;
    let consume_value_enum_calls = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10l_consume_value_enum_calls"),
        &passes.modules_consume_value_enum_calls,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("node_kind", hir_items.node_kind.as_entire_binding()),
            ("parent", hir_items.parent.as_entire_binding()),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            ("hir_expr_record", hir_items.expr_record.as_entire_binding()),
            ("hir_stmt_record", hir_items.stmt_record.as_entire_binding()),
            (
                "hir_call_arg_parent_call",
                hir_items.call_arg_parent_call.as_entire_binding(),
            ),
            (
                "hir_variant_payload_start",
                hir_items.variant_payload_start.as_entire_binding(),
            ),
            (
                "hir_variant_payload_count",
                hir_items.variant_payload_count.as_entire_binding(),
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
            ("call_arg_record", call_arg_record.as_entire_binding()),
            (
                "module_value_path_status",
                module_value_path_status.as_entire_binding(),
            ),
            ("call_return_type", call_return_type.as_entire_binding()),
        ],
    )?;
    let bind_match_patterns = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10m_bind_match_patterns"),
        &passes.modules_bind_match_patterns,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("token_words", token_buf.as_entire_binding()),
            ("language_name_id", language_name_id.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            ("hir_token_end", hir_token_end_buf.as_entire_binding()),
            ("subtree_end", hir_items.subtree_end.as_entire_binding()),
            (
                "hir_match_arm_pattern_node",
                hir_items.match_arm_pattern_node.as_entire_binding(),
            ),
            (
                "hir_match_arm_payload_start",
                hir_items.match_arm_payload_start.as_entire_binding(),
            ),
            (
                "hir_match_arm_payload_count",
                hir_items.match_arm_payload_count.as_entire_binding(),
            ),
            (
                "hir_match_arm_result_node",
                hir_items.match_arm_result_node.as_entire_binding(),
            ),
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
        ],
    )?;
    let type_match_payloads = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10m2_type_match_payloads"),
        &passes.modules_type_match_payloads,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("token_words", token_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            ("hir_token_end", hir_token_end_buf.as_entire_binding()),
            (
                "hir_match_scrutinee_node",
                hir_items.match_scrutinee_node.as_entire_binding(),
            ),
            (
                "hir_match_arm_start",
                hir_items.match_arm_start.as_entire_binding(),
            ),
            (
                "hir_match_arm_count",
                hir_items.match_arm_count.as_entire_binding(),
            ),
            (
                "hir_match_arm_next",
                hir_items.match_arm_next.as_entire_binding(),
            ),
            (
                "hir_match_arm_pattern_node",
                hir_items.match_arm_pattern_node.as_entire_binding(),
            ),
            (
                "hir_match_arm_payload_start",
                hir_items.match_arm_payload_start.as_entire_binding(),
            ),
            (
                "hir_match_arm_payload_count",
                hir_items.match_arm_payload_count.as_entire_binding(),
            ),
            (
                "hir_match_arm_result_node",
                hir_items.match_arm_result_node.as_entire_binding(),
            ),
            (
                "hir_match_payload_owner_arm",
                hir_items.match_payload_owner_arm.as_entire_binding(),
            ),
            (
                "hir_match_payload_match_node",
                hir_items.match_payload_match_node.as_entire_binding(),
            ),
            (
                "hir_match_payload_ordinal",
                hir_items.match_payload_ordinal.as_entire_binding(),
            ),
            (
                "hir_variant_payload_start",
                hir_items.variant_payload_start.as_entire_binding(),
            ),
            (
                "hir_variant_payload_count",
                hir_items.variant_payload_count.as_entire_binding(),
            ),
            ("visible_decl", visible_decl.as_entire_binding()),
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
            ("token_count", token_count_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("node_kind", hir_items.node_kind.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            ("hir_expr_record", hir_items.expr_record.as_entire_binding()),
            (
                "hir_member_name_token",
                hir_items.member_name_token.as_entire_binding(),
            ),
            (
                "hir_struct_lit_head_node",
                hir_items.struct_lit_head_node.as_entire_binding(),
            ),
            (
                "hir_match_arm_start",
                hir_items.match_arm_start.as_entire_binding(),
            ),
            (
                "hir_match_arm_count",
                hir_items.match_arm_count.as_entire_binding(),
            ),
            (
                "hir_match_arm_next",
                hir_items.match_arm_next.as_entire_binding(),
            ),
            (
                "hir_match_arm_result_node",
                hir_items.match_arm_result_node.as_entire_binding(),
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
        project_type_aliases,
        project_type_instances,
        mark_value_call_paths,
        project_value_paths,
        consume_value_calls,
        mirror_value_call_leaf,
        consume_value_consts,
        consume_value_enum_units,
        consume_value_enum_calls,
        bind_match_patterns,
        type_match_payloads,
        type_match_exprs,
    })
}
