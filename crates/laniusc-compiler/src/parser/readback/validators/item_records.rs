use super::super::*;

fn is_known_hir_kind(kind: u32) -> bool {
    matches!(
        kind,
        HIR_NODE_NONE
            | HIR_NODE_FILE
            | HIR_NODE_ITEM
            | HIR_NODE_FN
            | HIR_NODE_PARAM
            | HIR_NODE_TYPE
            | HIR_NODE_BLOCK
            | HIR_NODE_STMT
            | HIR_NODE_LET_STMT
            | HIR_NODE_RETURN_STMT
            | HIR_NODE_IF_STMT
            | HIR_NODE_WHILE_STMT
            | HIR_NODE_BREAK_STMT
            | HIR_NODE_CONTINUE_STMT
            | HIR_NODE_EXPR
            | HIR_NODE_ASSIGN_EXPR
            | HIR_NODE_BINARY_EXPR
            | HIR_NODE_UNARY_EXPR
            | HIR_NODE_POSTFIX_EXPR
            | HIR_NODE_CALL_EXPR
            | HIR_NODE_INDEX_EXPR
            | HIR_NODE_MEMBER_EXPR
            | HIR_NODE_NAME_EXPR
            | HIR_NODE_LITERAL_EXPR
            | HIR_NODE_ARRAY_EXPR
            | HIR_NODE_CONST_ITEM
            | HIR_NODE_ENUM_ITEM
            | HIR_NODE_STRUCT_ITEM
            | HIR_NODE_STRUCT_LITERAL_EXPR
            | HIR_NODE_TYPE_ALIAS_ITEM
            | HIR_NODE_FOR_STMT
            | HIR_NODE_MODULE_ITEM
            | HIR_NODE_IMPORT_ITEM
            | HIR_NODE_PATH_EXPR
            | HIR_NODE_MATCH_EXPR
    )
}

fn is_known_hir_type_form(form: u32) -> bool {
    matches!(
        form,
        HIR_TYPE_FORM_NONE
            | HIR_TYPE_FORM_PATH
            | HIR_TYPE_FORM_ARRAY
            | HIR_TYPE_FORM_SLICE
            | HIR_TYPE_FORM_REF
    )
}

fn expected_hir_kind_for_item_kind(item_kind: u32) -> Result<Option<u32>> {
    match item_kind {
        HIR_ITEM_KIND_NONE => Ok(None),
        HIR_ITEM_KIND_MODULE => Ok(Some(HIR_NODE_MODULE_ITEM)),
        HIR_ITEM_KIND_IMPORT => Ok(Some(HIR_NODE_IMPORT_ITEM)),
        HIR_ITEM_KIND_CONST => Ok(Some(HIR_NODE_CONST_ITEM)),
        HIR_ITEM_KIND_FN | HIR_ITEM_KIND_EXTERN_FN => Ok(Some(HIR_NODE_FN)),
        HIR_ITEM_KIND_STRUCT => Ok(Some(HIR_NODE_STRUCT_ITEM)),
        HIR_ITEM_KIND_ENUM => Ok(Some(HIR_NODE_ENUM_ITEM)),
        HIR_ITEM_KIND_TYPE_ALIAS => Ok(Some(HIR_NODE_TYPE_ALIAS_ITEM)),
        HIR_ITEM_KIND_ENUM_VARIANT | HIR_ITEM_KIND_TRAIT => Ok(Some(HIR_NODE_ITEM)),
        other => Err(anyhow!("unknown item kind {other}")),
    }
}

fn expected_namespace_for_item_kind(item_kind: u32) -> Result<Option<u32>> {
    match item_kind {
        HIR_ITEM_KIND_NONE => Ok(Some(HIR_ITEM_NAMESPACE_NONE)),
        HIR_ITEM_KIND_MODULE | HIR_ITEM_KIND_IMPORT => Ok(Some(HIR_ITEM_NAMESPACE_MODULE)),
        HIR_ITEM_KIND_CONST
        | HIR_ITEM_KIND_FN
        | HIR_ITEM_KIND_EXTERN_FN
        | HIR_ITEM_KIND_ENUM_VARIANT => Ok(Some(HIR_ITEM_NAMESPACE_VALUE)),
        HIR_ITEM_KIND_STRUCT
        | HIR_ITEM_KIND_ENUM
        | HIR_ITEM_KIND_TYPE_ALIAS
        | HIR_ITEM_KIND_TRAIT => Ok(Some(HIR_ITEM_NAMESPACE_TYPE)),
        other => Err(anyhow!("unknown item kind {other}")),
    }
}

fn item_kind_requires_name_token(item_kind: u32) -> bool {
    matches!(
        item_kind,
        HIR_ITEM_KIND_CONST
            | HIR_ITEM_KIND_FN
            | HIR_ITEM_KIND_EXTERN_FN
            | HIR_ITEM_KIND_STRUCT
            | HIR_ITEM_KIND_ENUM
            | HIR_ITEM_KIND_TYPE_ALIAS
            | HIR_ITEM_KIND_ENUM_VARIANT
            | HIR_ITEM_KIND_TRAIT
    )
}

fn is_known_item_visibility(visibility: u32) -> bool {
    matches!(visibility, HIR_ITEM_VIS_PRIVATE | HIR_ITEM_VIS_PUBLIC)
}

/// Validates HIR token position, token end, and file-id source addresses.
pub fn validate_hir_source_address_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    type_file_ids: &[u32],
    item_kinds: &[u32],
    item_file_ids: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || type_forms.len() != row_count
        || type_file_ids.len() != row_count
        || item_kinds.len() != row_count
        || item_file_ids.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR source address record arrays have inconsistent lengths"
        ));
    }

    let mut previous_public_record: Option<(usize, u32, u32, u32)> = None;
    for row in 0..row_count {
        if !is_known_hir_kind(kinds[row]) {
            return Err(anyhow!(
                "parser HIR source address row {row} published unknown HIR node kind {}",
                kinds[row]
            ));
        }
        if !is_known_hir_type_form(type_forms[row]) {
            return Err(anyhow!(
                "parser HIR source address row {row} published unknown type form {}",
                type_forms[row]
            ));
        }

        let expected_item_node_kind = expected_hir_kind_for_item_kind(item_kinds[row])
            .map_err(|err| anyhow!("parser HIR source address row {row} published {err}"))?;
        let has_item_record = expected_item_node_kind.is_some();
        let has_type_record = type_forms[row] != HIR_TYPE_FORM_NONE;
        let has_hir_record = kinds[row] != HIR_NODE_NONE;
        if has_hir_record
            && (token_pos[row] == INVALID
                || token_end[row] == INVALID
                || token_pos[row] >= token_end[row])
        {
            return Err(anyhow!(
                "parser HIR source address row {row} published HIR kind {} without a non-empty token span",
                kinds[row]
            ));
        }
        if has_hir_record && node_file_ids[row] == INVALID {
            return Err(anyhow!(
                "parser HIR source address row {row} published HIR kind {} without a node file id",
                kinds[row]
            ));
        }
        if !has_item_record && !has_type_record {
            continue;
        }

        if has_item_record && item_file_ids[row] != node_file_ids[row] {
            return Err(anyhow!(
                "parser HIR item row {row} published file id {} but node file id is {}",
                item_file_ids[row],
                node_file_ids[row]
            ));
        }
        if let Some(expected_node_kind) = expected_item_node_kind {
            if kinds[row] != expected_node_kind {
                return Err(anyhow!(
                    "parser HIR item row {row} published item kind {} on HIR kind {}, expected {expected_node_kind}",
                    item_kinds[row],
                    kinds[row]
                ));
            }
        }

        if has_type_record {
            if kinds[row] != HIR_NODE_TYPE {
                return Err(anyhow!(
                    "parser HIR type row {row} published type form {} without a type HIR node",
                    type_forms[row]
                ));
            }
            if type_file_ids[row] != node_file_ids[row] {
                return Err(anyhow!(
                    "parser HIR type row {row} published file id {} but node file id is {}",
                    type_file_ids[row],
                    node_file_ids[row]
                ));
            }
        }

        let current_key = (node_file_ids[row], token_pos[row], token_end[row]);
        if let Some((previous_row, previous_file_id, previous_token_pos, previous_token_end)) =
            previous_public_record
        {
            if current_key < (previous_file_id, previous_token_pos, previous_token_end) {
                return Err(anyhow!(
                    "parser HIR source address row {row} is out of flat source order after row {previous_row}: ({}, {}, {}) before ({previous_file_id}, {previous_token_pos}, {previous_token_end})",
                    node_file_ids[row],
                    token_pos[row],
                    token_end[row]
                ));
            }
        }
        previous_public_record = Some((row, node_file_ids[row], token_pos[row], token_end[row]));
    }

    Ok(())
}

/// Validates item kind, namespace, visibility, name, declaration, and file rows.
pub fn validate_hir_item_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    item_kinds: &[u32],
    item_name_tokens: &[u32],
    item_namespaces: &[u32],
    item_visibilities: &[u32],
    item_file_ids: &[u32],
) -> Result<()> {
    let row_count = item_kinds.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || item_name_tokens.len() != row_count
        || item_namespaces.len() != row_count
        || item_visibilities.len() != row_count
        || item_file_ids.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR item record arrays have inconsistent lengths"
        ));
    }

    for row in 0..row_count {
        let item_kind = item_kinds[row];
        let expected_namespace = expected_namespace_for_item_kind(item_kind)
            .map_err(|err| anyhow!("parser HIR item row {row} published {err}"))?;
        if !is_known_item_visibility(item_visibilities[row]) {
            return Err(anyhow!(
                "parser HIR item row {row} published unknown item visibility {}",
                item_visibilities[row]
            ));
        }

        let Some(expected_node_kind) = expected_hir_kind_for_item_kind(item_kind)
            .map_err(|err| anyhow!("parser HIR item row {row} published {err}"))?
        else {
            if item_namespaces[row] != HIR_ITEM_NAMESPACE_NONE {
                return Err(anyhow!(
                    "parser HIR non-item row {row} published item namespace {}",
                    item_namespaces[row]
                ));
            }
            if item_name_tokens[row] != INVALID {
                return Err(anyhow!(
                    "parser HIR non-item row {row} retained item name metadata"
                ));
            }
            if item_file_ids[row] != INVALID && item_file_ids[row] != node_file_ids[row] {
                return Err(anyhow!(
                    "parser HIR non-item row {row} published file id {} but node file id is {}",
                    item_file_ids[row],
                    node_file_ids[row]
                ));
            }
            continue;
        };

        if kinds[row] != expected_node_kind {
            return Err(anyhow!(
                "parser HIR item row {row} published item kind {item_kind} on HIR kind {}, expected {expected_node_kind}",
                kinds[row]
            ));
        }
        if item_namespaces[row] != expected_namespace.unwrap_or(HIR_ITEM_NAMESPACE_NONE) {
            return Err(anyhow!(
                "parser HIR item row {row} published namespace {} for item kind {item_kind}",
                item_namespaces[row]
            ));
        }
        if token_pos[row] == INVALID
            || token_end[row] == INVALID
            || token_pos[row] >= token_end[row]
            || node_file_ids[row] == INVALID
        {
            return Err(anyhow!(
                "parser HIR item row {row} published item kind {item_kind} without source-addressable ownership"
            ));
        }
        if item_file_ids[row] != node_file_ids[row] {
            return Err(anyhow!(
                "parser HIR item row {row} published file id {} but node file id is {}",
                item_file_ids[row],
                node_file_ids[row]
            ));
        }

        let name_token = item_name_tokens[row];
        if item_kind_requires_name_token(item_kind) {
            if name_token == INVALID || name_token < token_pos[row] || name_token >= token_end[row]
            {
                return Err(anyhow!(
                    "parser HIR item row {row} published item kind {item_kind} without an in-span name token"
                ));
            }
            if matches!(item_kind, HIR_ITEM_KIND_FN | HIR_ITEM_KIND_EXTERN_FN)
                && name_token <= token_pos[row]
            {
                return Err(anyhow!(
                    "parser HIR function item row {row} published a name token that does not follow its declaration token"
                ));
            }
        } else if name_token != INVALID {
            return Err(anyhow!(
                "parser HIR item row {row} published a name token for path-owned item kind {item_kind}"
            ));
        }
    }

    Ok(())
}

/// Validates type-alias target-node records.
pub fn validate_hir_type_alias_target_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    type_file_ids: &[u32],
    item_kinds: &[u32],
    item_name_tokens: &[u32],
    item_file_ids: &[u32],
    target_nodes: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || type_forms.len() != row_count
        || type_file_ids.len() != row_count
        || item_kinds.len() != row_count
        || item_name_tokens.len() != row_count
        || item_file_ids.len() != row_count
        || target_nodes.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR type-alias target record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let mut target_owners = vec![INVALID; row_count];
    for row in 0..row_count {
        let is_type_alias = item_kinds[row] == HIR_ITEM_KIND_TYPE_ALIAS;
        let target = target_nodes[row];

        if !is_type_alias {
            if kinds[row] == HIR_NODE_TYPE_ALIAS_ITEM {
                return Err(anyhow!(
                    "parser HIR type-alias row {row} has no parser-owned type-alias item metadata"
                ));
            }
            if target != INVALID {
                return Err(anyhow!(
                    "parser HIR row {row} published a type-alias target without type-alias item metadata"
                ));
            }
            continue;
        }

        if kinds[row] != HIR_NODE_TYPE_ALIAS_ITEM {
            return Err(anyhow!(
                "parser HIR type-alias row {row} published item metadata on HIR kind {}",
                kinds[row]
            ));
        }
        if !has_non_empty_span(row) || node_file_ids[row] == INVALID {
            return Err(anyhow!(
                "parser HIR type-alias row {row} published item metadata without a source-addressable alias span"
            ));
        }
        if item_file_ids[row] != node_file_ids[row] {
            return Err(anyhow!(
                "parser HIR type-alias row {row} has inconsistent item and node file ids"
            ));
        }

        let name_token = item_name_tokens[row];
        if name_token == INVALID || name_token < token_pos[row] || name_token >= token_end[row] {
            return Err(anyhow!(
                "parser HIR type-alias row {row} published a name token outside its alias span"
            ));
        }

        if target == INVALID || target as usize >= row_count || target as usize == row {
            return Err(anyhow!(
                "parser HIR type-alias row {row} published no in-table target type row"
            ));
        }
        let target = target as usize;
        if kinds[target] != HIR_NODE_TYPE || type_forms[target] == HIR_TYPE_FORM_NONE {
            return Err(anyhow!(
                "parser HIR type-alias row {row} target row {target} is not a concrete type record"
            ));
        }
        if !has_non_empty_span(target) {
            return Err(anyhow!(
                "parser HIR type-alias row {row} target row {target} lacks a non-empty token span"
            ));
        }
        if node_file_ids[target] != node_file_ids[row]
            || type_file_ids[target] != node_file_ids[row]
        {
            return Err(anyhow!(
                "parser HIR type-alias row {row} target row {target} has a different file id"
            ));
        }
        if token_pos[target] < token_pos[row] || token_end[target] > token_end[row] {
            return Err(anyhow!(
                "parser HIR type-alias row {row} target row {target} falls outside the alias span"
            ));
        }
        if token_pos[target] <= name_token {
            return Err(anyhow!(
                "parser HIR type-alias row {row} target row {target} does not follow the alias name token"
            ));
        }

        let previous_owner = target_owners[target];
        if previous_owner != INVALID {
            return Err(anyhow!(
                "parser HIR type-alias row {row} shares target row {target} with alias row {previous_owner}"
            ));
        }
        target_owners[target] = row as u32;
    }

    Ok(())
}

/// Validates parser-owned type form and type payload records.
pub fn validate_hir_type_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    type_value_nodes: &[u32],
    type_len_tokens: &[u32],
    type_len_values: &[u32],
    type_file_ids: &[u32],
    type_path_leaf_nodes: &[u32],
) -> Result<()> {
    let node_kinds = vec![INVALID; kinds.len()];
    validate_hir_type_records_with_node_kinds(
        &node_kinds,
        kinds,
        token_pos,
        token_end,
        node_file_ids,
        type_forms,
        type_value_nodes,
        type_len_tokens,
        type_len_values,
        type_file_ids,
        type_path_leaf_nodes,
    )
}

/// Validates type records using tree node kinds as an additional shape oracle.
pub fn validate_hir_type_records_with_node_kinds(
    node_kinds: &[u32],
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    type_value_nodes: &[u32],
    type_len_tokens: &[u32],
    type_len_values: &[u32],
    type_file_ids: &[u32],
    type_path_leaf_nodes: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if node_kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || type_forms.len() != row_count
        || type_value_nodes.len() != row_count
        || type_len_tokens.len() != row_count
        || type_len_values.len() != row_count
        || type_file_ids.len() != row_count
        || type_path_leaf_nodes.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR type record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let require_type_owner = |owner: usize, label: &str| -> Result<()> {
        if kinds[owner] != HIR_NODE_TYPE {
            return Err(anyhow!(
                "parser HIR type row {owner} published {label} on HIR kind {}",
                kinds[owner]
            ));
        }
        if !has_non_empty_span(owner) || node_file_ids[owner] == INVALID {
            return Err(anyhow!(
                "parser HIR type row {owner} published {label} without a source-addressable type row"
            ));
        }
        if type_file_ids[owner] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR type row {owner} published file id {} but node file id is {}",
                type_file_ids[owner],
                node_file_ids[owner]
            ));
        }
        Ok(())
    };

    let require_parser_node_inside_owner = |owner: usize,
                                            node: u32,
                                            label: &str|
     -> Result<usize> {
        if node == INVALID || node as usize >= row_count {
            return Err(anyhow!(
                "parser HIR type row {owner} published {label} without an in-table parser-owned row"
            ));
        }
        let node = node as usize;
        if node == owner {
            return Err(anyhow!(
                "parser HIR type row {owner} published {label} as a self edge"
            ));
        }
        if !has_non_empty_span(node) {
            return Err(anyhow!(
                "parser HIR type row {owner} published {label} row {node} without a non-empty token span"
            ));
        }
        if node_file_ids[node] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR type row {owner} published {label} row {node} with a different file id"
            ));
        }
        if token_pos[node] < token_pos[owner] || token_end[node] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR type row {owner} published {label} row {node} outside the owner type span"
            ));
        }
        Ok(node)
    };

    let require_path_leaf = |owner: usize, path_node: usize| -> Result<usize> {
        let leaf = type_path_leaf_nodes[owner];
        if leaf == INVALID || leaf as usize >= row_count {
            return Err(anyhow!(
                "parser HIR path/type row {owner} published no in-table parser-owned path leaf"
            ));
        }
        let leaf = leaf as usize;
        if !has_non_empty_span(leaf) {
            return Err(anyhow!(
                "parser HIR path/type row {owner} published path leaf row {leaf} without a non-empty token span"
            ));
        }
        if kinds[leaf] != HIR_NODE_NONE {
            return Err(anyhow!(
                "parser HIR path/type row {owner} published path leaf row {leaf} on concrete HIR kind {} instead of a parser path-segment row",
                kinds[leaf]
            ));
        }
        if node_file_ids[leaf] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR path/type row {owner} published path leaf row {leaf} with a different file id"
            ));
        }
        if token_pos[leaf] < token_pos[path_node] || token_end[leaf] > token_end[path_node] {
            return Err(anyhow!(
                "parser HIR path/type row {owner} published path leaf row {leaf} outside path node {path_node}"
            ));
        }
        if token_end[leaf] != token_end[path_node] {
            return Err(anyhow!(
                "parser HIR path/type row {owner} published path leaf row {leaf} that is not the terminal segment of path node {path_node}"
            ));
        }
        Ok(leaf)
    };

    let require_no_len = |row: usize, label: &str| -> Result<()> {
        if type_len_tokens[row] != INVALID || type_len_values[row] != INVALID {
            return Err(anyhow!(
                "parser HIR type row {row} published {label} with array length metadata"
            ));
        }
        Ok(())
    };

    for row in 0..row_count {
        if kinds[row] == HIR_NODE_PATH_EXPR {
            if !has_non_empty_span(row) || node_file_ids[row] == INVALID {
                return Err(anyhow!(
                    "parser HIR path row {row} published a path leaf without a source-addressable path row"
                ));
            }
            require_path_leaf(row, row)?;
        } else if type_path_leaf_nodes[row] != INVALID
            && type_forms[row] != HIR_TYPE_FORM_PATH
            && node_kinds[row] != PROD_BOUND_TYPE_IDENT
        {
            return Err(anyhow!(
                "parser HIR row {row} published path leaf row {} without a path HIR/type owner (hir_kind={}, node_kind={}, type_form={})",
                type_path_leaf_nodes[row],
                kinds[row],
                node_kinds[row],
                type_forms[row]
            ));
        }

        match type_forms[row] {
            HIR_TYPE_FORM_NONE => {
                if kinds[row] == HIR_NODE_TYPE {
                    return Err(anyhow!(
                        "parser HIR type row {row} has a type HIR kind but no concrete type record"
                    ));
                }
                if type_value_nodes[row] != INVALID
                    || type_len_tokens[row] != INVALID
                    || type_len_values[row] != INVALID
                {
                    return Err(anyhow!(
                        "parser HIR row {row} published type metadata without a concrete type record"
                    ));
                }
            }
            HIR_TYPE_FORM_PATH => {
                require_type_owner(row, "path type record")?;
                let path_node =
                    require_parser_node_inside_owner(row, type_value_nodes[row], "path node")?;
                if kinds[path_node] != HIR_NODE_PATH_EXPR {
                    return Err(anyhow!(
                        "parser HIR type row {row} published path type record without a parser-owned path node record"
                    ));
                }
                if token_pos[path_node] != token_pos[row] {
                    return Err(anyhow!(
                        "parser HIR type row {row} path type span does not start at parser-owned path node {path_node}"
                    ));
                }
                let path_leaf = require_path_leaf(row, path_node)?;
                let path_node_leaf = require_path_leaf(path_node, path_node)?;
                if path_leaf != path_node_leaf {
                    return Err(anyhow!(
                        "parser HIR type row {row} published path leaf row {path_leaf} different from parser-owned path node {path_node} leaf row {path_node_leaf}"
                    ));
                }
                require_no_len(row, "path type record")?;
            }
            HIR_TYPE_FORM_ARRAY | HIR_TYPE_FORM_SLICE | HIR_TYPE_FORM_REF => {
                let label = match type_forms[row] {
                    HIR_TYPE_FORM_ARRAY => "array type record",
                    HIR_TYPE_FORM_SLICE => "slice type record",
                    _ => "reference type record",
                };
                require_type_owner(row, label)?;
                let operand =
                    require_parser_node_inside_owner(row, type_value_nodes[row], "operand type")?;
                if kinds[operand] != HIR_NODE_TYPE || type_forms[operand] == HIR_TYPE_FORM_NONE {
                    return Err(anyhow!(
                        "parser HIR type row {row} published operand row {operand} without a concrete type operand"
                    ));
                }
                if type_path_leaf_nodes[row] != INVALID {
                    return Err(anyhow!(
                        "parser HIR type row {row} published {label} with path leaf metadata"
                    ));
                }
                if type_forms[row] == HIR_TYPE_FORM_ARRAY {
                    let len_token = type_len_tokens[row];
                    if len_token == INVALID
                        || len_token < token_pos[row]
                        || len_token >= token_end[row]
                    {
                        return Err(anyhow!(
                            "parser HIR type row {row} published array type record without an in-span length token"
                        ));
                    }
                } else {
                    require_no_len(row, label)?;
                }
            }
            other => {
                return Err(anyhow!(
                    "parser HIR type row {row} published unknown type record form {other}"
                ));
            }
        }
    }

    Ok(())
}

fn is_hir_function_item_kind(kind: u32) -> bool {
    matches!(kind, HIR_ITEM_KIND_FN | HIR_ITEM_KIND_EXTERN_FN)
}

fn is_hir_function_return_owner(kind: u32, item_kind: u32) -> bool {
    kind == HIR_NODE_FN && (item_kind == HIR_ITEM_KIND_NONE || is_hir_function_item_kind(item_kind))
}

/// Validates function and method return-type records.
pub fn validate_hir_function_return_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    type_file_ids: &[u32],
    return_type_nodes: &[u32],
    item_kinds: &[u32],
    item_name_tokens: &[u32],
    item_file_ids: &[u32],
    method_signature_flags: &[u32],
    method_name_tokens: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || type_forms.len() != row_count
        || type_file_ids.len() != row_count
        || return_type_nodes.len() != row_count
        || item_kinds.len() != row_count
        || item_name_tokens.len() != row_count
        || item_file_ids.len() != row_count
        || method_signature_flags.len() != row_count
        || method_name_tokens.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR function return record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let signature_flag_mask = HIR_METHOD_SIGNATURE_HAS_GENERICS
        | HIR_METHOD_SIGNATURE_HAS_WHERE
        | HIR_METHOD_SIGNATURE_INHERENT_IMPL;
    for row in 0..row_count {
        let flags = method_signature_flags[row];
        if flags == 0 {
            continue;
        }
        if flags & !signature_flag_mask != 0 {
            return Err(anyhow!(
                "parser HIR function return row {row} published unknown method signature flags {flags}"
            ));
        }
        if kinds[row] != HIR_NODE_FN || item_kinds[row] != HIR_ITEM_KIND_NONE {
            return Err(anyhow!(
                "parser HIR function return row {row} published method signature flags without a parser-owned method row"
            ));
        }
        if !has_non_empty_span(row) || node_file_ids[row] == INVALID {
            return Err(anyhow!(
                "parser HIR function return row {row} published method signature flags without a source-addressable method row"
            ));
        }
        let method_name_token = method_name_tokens[row];
        if method_name_token == INVALID
            || method_name_token < token_pos[row]
            || method_name_token >= token_end[row]
        {
            return Err(anyhow!(
                "parser HIR function return row {row} published method signature flags without an in-span parser-owned method name token"
            ));
        }
        if method_name_token <= token_pos[row] {
            return Err(anyhow!(
                "parser HIR function return row {row} published method signature flags with a method name token that does not follow the function span start"
            ));
        }
    }

    let mut return_type_owner = vec![INVALID; row_count];
    for owner in 0..row_count {
        let return_type_node = return_type_nodes[owner];
        if return_type_node == INVALID {
            continue;
        }

        if !is_hir_function_return_owner(kinds[owner], item_kinds[owner]) {
            return Err(anyhow!(
                "parser HIR function return row {owner} published a return type without a function or method owner"
            ));
        }
        if !has_non_empty_span(owner) || node_file_ids[owner] == INVALID {
            return Err(anyhow!(
                "parser HIR function return row {owner} published a return type without a source-addressable function owner"
            ));
        }
        if is_hir_function_item_kind(item_kinds[owner])
            && item_file_ids[owner] != node_file_ids[owner]
        {
            return Err(anyhow!(
                "parser HIR function return row {owner} has inconsistent owner item and node file ids"
            ));
        }
        let (owner_name_token, owner_name_label) = if is_hir_function_item_kind(item_kinds[owner]) {
            let name_token = item_name_tokens[owner];
            if name_token == INVALID
                || name_token < token_pos[owner]
                || name_token >= token_end[owner]
            {
                return Err(anyhow!(
                    "parser HIR function return row {owner} published a return type without a source-addressable function name token"
                ));
            }
            (name_token, "function")
        } else {
            let name_token = method_name_tokens[owner];
            if name_token == INVALID
                || name_token < token_pos[owner]
                || name_token >= token_end[owner]
            {
                return Err(anyhow!(
                    "parser HIR function return row {owner} published a return type without a source-addressable method name token"
                ));
            }
            (name_token, "method")
        };
        if owner_name_token <= token_pos[owner] {
            return Err(anyhow!(
                "parser HIR function return row {owner} published a {owner_name_label} name token that does not follow the function span start"
            ));
        }

        if return_type_node as usize >= row_count || return_type_node as usize == owner {
            return Err(anyhow!(
                "parser HIR function return row {owner} published no in-table return type node"
            ));
        }
        let return_type_node = return_type_node as usize;
        let previous_owner = return_type_owner[return_type_node];
        if previous_owner != INVALID {
            return Err(anyhow!(
                "parser HIR function return row {owner} shares return type row {return_type_node} with owner row {previous_owner}"
            ));
        }
        return_type_owner[return_type_node] = owner as u32;
        if kinds[return_type_node] != HIR_NODE_TYPE
            || type_forms[return_type_node] == HIR_TYPE_FORM_NONE
        {
            return Err(anyhow!(
                "parser HIR function return row {owner} points at row {return_type_node} without a concrete type record"
            ));
        }
        if !has_non_empty_span(return_type_node) {
            return Err(anyhow!(
                "parser HIR function return row {owner} points at return type row {return_type_node} without a non-empty token span"
            ));
        }
        if node_file_ids[return_type_node] != node_file_ids[owner]
            || type_file_ids[return_type_node] != node_file_ids[owner]
        {
            return Err(anyhow!(
                "parser HIR function return row {owner} points at return type row {return_type_node} with a different file id"
            ));
        }
        if token_pos[return_type_node] < token_pos[owner]
            || token_end[return_type_node] > token_end[owner]
        {
            return Err(anyhow!(
                "parser HIR function return row {owner} points at return type row {return_type_node} outside the function span"
            ));
        }
        if token_pos[return_type_node] <= owner_name_token {
            return Err(anyhow!(
                "parser HIR function return row {owner} points at return type row {return_type_node} that does not follow the {owner_name_label} name token"
            ));
        }
    }

    Ok(())
}

/// Validates struct declaration field owner, ordinal, and type records.
pub fn validate_hir_struct_declaration_field_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    type_file_ids: &[u32],
    item_kinds: &[u32],
    item_file_ids: &[u32],
    parent_structs: &[u32],
    ordinals: &[u32],
    type_nodes: &[u32],
    first_fields: &[u32],
    counts: &[u32],
) -> Result<()> {
    let row_count = counts.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || type_forms.len() != row_count
        || type_file_ids.len() != row_count
        || item_kinds.len() != row_count
        || item_file_ids.len() != row_count
        || parent_structs.len() != row_count
        || ordinals.len() != row_count
        || type_nodes.len() != row_count
        || first_fields.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR struct declaration field record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let require_span = |node: usize, label: &str| -> Result<()> {
        if !has_non_empty_span(node) {
            return Err(anyhow!(
                "parser HIR struct declaration {label} row {node} lacks a non-empty token span"
            ));
        }
        if node_file_ids[node] == INVALID {
            return Err(anyhow!(
                "parser HIR struct declaration {label} row {node} lacks a source file id"
            ));
        }
        Ok(())
    };

    let require_struct_owner = |owner: usize| -> Result<()> {
        if kinds[owner] != HIR_NODE_STRUCT_ITEM || item_kinds[owner] != HIR_ITEM_KIND_STRUCT {
            return Err(anyhow!(
                "parser HIR struct declaration row {owner} is not backed by a parser-owned struct item record"
            ));
        }
        require_span(owner, "owner")?;
        if item_file_ids[owner] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR struct declaration row {owner} has inconsistent item and node file ids"
            ));
        }
        Ok(())
    };

    let mut actual_counts = vec![0u32; row_count];
    let mut ordinal_keys = Vec::new();
    for (field_node, &owner) in parent_structs.iter().enumerate() {
        if owner == INVALID {
            if ordinals[field_node] != INVALID {
                return Err(anyhow!(
                    "parser HIR struct field row {field_node} published a field ordinal without a struct owner"
                ));
            }
            if type_nodes[field_node] != INVALID {
                return Err(anyhow!(
                    "parser HIR struct field row {field_node} published a field type edge without a struct owner"
                ));
            }
            continue;
        }

        let owner = owner as usize;
        if owner >= row_count {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} published owner {owner}, outside {row_count} readback rows"
            ));
        }
        require_struct_owner(owner)?;
        let owner_count = counts[owner];
        if owner_count == 0 {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} points at owner {owner} with zero field count"
            ));
        }
        if owner_count as usize > row_count {
            return Err(anyhow!(
                "parser HIR struct declaration row {owner} published {owner_count} fields, exceeding {row_count} readback rows"
            ));
        }

        if kinds[field_node] != HIR_NODE_NONE {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} has HIR kind {}, not a parser-owned struct declaration field record",
                kinds[field_node]
            ));
        }
        require_span(field_node, "field")?;
        if node_file_ids[field_node] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} published a different file id than owner {owner}"
            ));
        }
        if token_pos[field_node] < token_pos[owner] || token_end[field_node] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} falls outside owner {owner} span"
            ));
        }

        let ordinal = ordinals[field_node];
        if ordinal >= owner_count {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} published ordinal {ordinal}, outside owner {owner} count {owner_count}"
            ));
        }

        let type_node = type_nodes[field_node];
        if type_node == INVALID || type_node as usize >= row_count {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} published no in-table type node"
            ));
        }
        let type_node = type_node as usize;
        if kinds[type_node] != HIR_NODE_TYPE || type_forms[type_node] == HIR_TYPE_FORM_NONE {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} type row {type_node} is not a concrete type record"
            ));
        }
        require_span(type_node, "field type")?;
        if node_file_ids[type_node] != node_file_ids[field_node]
            || type_file_ids[type_node] != node_file_ids[field_node]
        {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} type row {type_node} has a different file id"
            ));
        }
        if token_pos[type_node] < token_pos[field_node]
            || token_end[type_node] > token_end[field_node]
        {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} type row {type_node} falls outside the field span"
            ));
        }
        if token_pos[type_node] <= token_pos[field_node] {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} type row {type_node} does not follow the field name token"
            ));
        }

        actual_counts[owner] += 1;
        ordinal_keys.push((owner, ordinal, field_node));
    }

    ordinal_keys.sort_unstable();
    for pair in ordinal_keys.windows(2) {
        let (owner, ordinal, first_row) = pair[0];
        let (next_owner, next_ordinal, _) = pair[1];
        if owner == next_owner && ordinal == next_ordinal {
            return Err(anyhow!(
                "parser HIR struct declaration row {owner} published duplicate field ordinal {ordinal} at row {first_row}"
            ));
        }
    }

    for (owner, &count) in counts.iter().enumerate() {
        if count == 0 {
            if first_fields[owner] != INVALID {
                return Err(anyhow!(
                    "parser HIR struct declaration row {owner} published first field without a field count"
                ));
            }
            continue;
        }
        require_struct_owner(owner)?;
        if count as usize > row_count {
            return Err(anyhow!(
                "parser HIR struct declaration row {owner} published {count} fields, exceeding {row_count} readback rows"
            ));
        }

        let first = first_fields[owner];
        if first == INVALID || first as usize >= row_count {
            return Err(anyhow!(
                "parser HIR struct declaration row {owner} published field count {count} without an in-table first field"
            ));
        }
        let first = first as usize;
        if parent_structs[first] as usize != owner || ordinals[first] != 0 {
            return Err(anyhow!(
                "parser HIR struct declaration row {owner} first field row {first} is not ordinal zero for that owner"
            ));
        }
        if actual_counts[owner] != count {
            return Err(anyhow!(
                "parser HIR struct declaration row {owner} published count {count} but read back {} owned field rows",
                actual_counts[owner]
            ));
        }

        let mut previous_field: Option<usize> = None;
        for expected_ordinal in 0..count {
            let field = ordinal_keys
                .binary_search_by_key(&(owner, expected_ordinal), |&(owner, ordinal, _)| {
                    (owner, ordinal)
                })
                .ok()
                .map(|index| ordinal_keys[index].2)
                .ok_or_else(|| {
                    anyhow!(
                        "parser HIR struct declaration row {owner} field ordinals are not contiguous from zero"
                    )
                })?;
            if let Some(previous) = previous_field {
                if token_pos[field] <= token_pos[previous] || token_end[previous] > token_pos[field]
                {
                    return Err(anyhow!(
                        "parser HIR struct declaration row {owner} fields overlap or are not in source order at row {field}"
                    ));
                }
            }
            previous_field = Some(field);
        }
    }

    Ok(())
}

/// Validates struct literal field owner, value, count, and next-link records.
pub fn validate_hir_struct_literal_field_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    head_nodes: &[u32],
    first_fields: &[u32],
    counts: &[u32],
    parent_literals: &[u32],
    value_nodes: &[u32],
    next_fields: &[u32],
) -> Result<()> {
    let row_count = counts.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || head_nodes.len() != row_count
        || first_fields.len() != row_count
        || parent_literals.len() != row_count
        || value_nodes.len() != row_count
        || next_fields.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR struct literal field record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let require_span = |node: usize, label: &str| -> Result<()> {
        if !has_non_empty_span(node) {
            return Err(anyhow!(
                "parser HIR struct literal {label} row {node} lacks a non-empty token span"
            ));
        }
        Ok(())
    };

    for row in 0..row_count {
        let head = head_nodes[row];
        if kinds[row] != HIR_NODE_STRUCT_LITERAL_EXPR {
            if head != INVALID {
                return Err(anyhow!(
                    "parser HIR struct literal row {row} published a head node without a struct-literal HIR owner"
                ));
            }
            continue;
        }

        require_span(row, "owner")?;
        if node_file_ids[row] == INVALID {
            return Err(anyhow!(
                "parser HIR struct literal row {row} published a head node without a node file id"
            ));
        }
        if head == INVALID || head as usize >= row_count || head as usize == row {
            return Err(anyhow!(
                "parser HIR struct literal row {row} published no in-table head path node"
            ));
        }

        let head = head as usize;
        require_span(head, "head")?;
        if node_file_ids[head] != node_file_ids[row] {
            return Err(anyhow!(
                "parser HIR struct literal row {row} head row {head} published a different file id"
            ));
        }
        if token_pos[head] < token_pos[row] || token_end[head] > token_end[row] {
            return Err(anyhow!(
                "parser HIR struct literal row {row} head row {head} falls outside owner row {row} span"
            ));
        }
        if !matches!(kinds[head], HIR_NODE_PATH_EXPR | HIR_NODE_NAME_EXPR) {
            return Err(anyhow!(
                "parser HIR struct literal row {row} head row {head} has non-path/name HIR kind {}",
                kinds[head]
            ));
        }
    }

    let mut actual_counts = vec![0u32; row_count];
    for (field_node, &owner) in parent_literals.iter().enumerate() {
        if owner == INVALID {
            if next_fields[field_node] != INVALID {
                return Err(anyhow!(
                    "parser HIR struct literal field row {field_node} published next field without an owner"
                ));
            }
            let value_node = value_nodes[field_node];
            if value_node != INVALID {
                return Err(anyhow!(
                    "parser HIR struct literal field row {field_node} published value node without an owner"
                ));
            }
            continue;
        }

        let owner = owner as usize;
        if owner >= row_count {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} published owner {owner}, outside {row_count} readback rows"
            ));
        }
        if kinds[owner] != HIR_NODE_STRUCT_LITERAL_EXPR {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} points at owner {owner} that is not a struct-literal HIR row"
            ));
        }
        if kinds[field_node] != HIR_NODE_NONE {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} has HIR kind {}, not a parser-owned struct-literal field record",
                kinds[field_node]
            ));
        }

        let owner_count = counts[owner];
        if owner_count == 0 {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} points at owner {owner} with zero field count"
            ));
        }
        require_span(owner, "owner")?;
        require_span(field_node, "field")?;
        if node_file_ids[owner] == INVALID || node_file_ids[field_node] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} published a different file id than owner {owner}"
            ));
        }
        if token_pos[field_node] < token_pos[owner] || token_end[field_node] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} falls outside owner {owner} span"
            ));
        }
        if owner_count as usize > row_count {
            return Err(anyhow!(
                "parser HIR struct literal row {owner} published {owner_count} fields, exceeding {row_count} readback rows"
            ));
        }

        let value_node = value_nodes[field_node];
        if value_node == INVALID || value_node as usize >= row_count {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} published a field without an in-table value expression"
            ));
        }
        if kinds[value_node as usize] != HIR_NODE_EXPR {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} value row {value_node} is not an expression HIR row"
            ));
        }
        let value_node = value_node as usize;
        require_span(value_node, "field value")?;
        if node_file_ids[value_node] != node_file_ids[field_node] {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} value row {value_node} published a different file id"
            ));
        }
        if token_pos[value_node] < token_pos[field_node]
            || token_end[value_node] > token_end[field_node]
        {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} value row {value_node} falls outside the field span"
            ));
        }

        let next = next_fields[field_node];
        if next != INVALID && next as usize >= row_count {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} published next field {next}, outside {row_count} readback rows"
            ));
        }
        actual_counts[owner] += 1;
    }

    for (owner, &count) in counts.iter().enumerate() {
        if count == 0 {
            if first_fields[owner] != INVALID {
                return Err(anyhow!(
                    "parser HIR struct literal row {owner} published first field without a field count"
                ));
            }
            continue;
        }
        if kinds[owner] != HIR_NODE_STRUCT_LITERAL_EXPR {
            return Err(anyhow!(
                "parser HIR struct literal row {owner} published field count {count} without a struct-literal HIR owner"
            ));
        }
        require_span(owner, "owner")?;
        if count as usize > row_count {
            return Err(anyhow!(
                "parser HIR struct literal row {owner} published {count} fields, exceeding {row_count} readback rows"
            ));
        }

        let first = first_fields[owner];
        if first == INVALID || first as usize >= row_count {
            return Err(anyhow!(
                "parser HIR struct literal row {owner} published field count {count} without an in-table first field"
            ));
        }
        let first = first as usize;
        let head = head_nodes[owner];
        if head == INVALID || head as usize >= row_count {
            return Err(anyhow!(
                "parser HIR struct literal row {owner} published field count {count} without an in-table head path node"
            ));
        }
        let head = head as usize;
        if token_end[head] > token_pos[first] {
            return Err(anyhow!(
                "parser HIR struct literal row {owner} head row {head} does not precede first field row {first}"
            ));
        }
        if actual_counts[owner] != count {
            return Err(anyhow!(
                "parser HIR struct literal row {owner} published count {count} but read back {} owned field rows",
                actual_counts[owner]
            ));
        }

        let mut field = first;
        for expected_position in 0..count {
            if parent_literals[field] as usize != owner {
                return Err(anyhow!(
                    "parser HIR struct literal row {owner} field chain row {field} does not point back to that owner"
                ));
            }
            let value_node = value_nodes[field];
            if value_node == INVALID || value_node as usize >= row_count {
                return Err(anyhow!(
                    "parser HIR struct literal row {owner} field chain row {field} has no in-table value expression"
                ));
            }

            let next = next_fields[field];
            if expected_position + 1 == count {
                if next != INVALID {
                    return Err(anyhow!(
                        "parser HIR struct literal row {owner} final field row {field} did not terminate the field chain"
                    ));
                }
            } else {
                if next == INVALID || next as usize >= row_count {
                    return Err(anyhow!(
                        "parser HIR struct literal row {owner} field chain ended before count {count}"
                    ));
                }
                let next = next as usize;
                if parent_literals[next] as usize != owner {
                    return Err(anyhow!(
                        "parser HIR struct literal row {owner} field chain row {next} does not point back to that owner"
                    ));
                }
                if token_pos[next] <= token_pos[field] || token_end[field] > token_pos[next] {
                    return Err(anyhow!(
                        "parser HIR struct literal row {owner} field chain rows overlap or are not in source order at row {field}"
                    ));
                }
                field = next;
            }
        }
    }

    Ok(())
}

/// Validates parser-owned item path span and owner records.
pub fn validate_hir_item_path_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    item_kinds: &[u32],
    item_file_ids: &[u32],
    path_starts: &[u32],
    path_ends: &[u32],
    path_nodes: &[u32],
    import_target_kinds: &[u32],
) -> Result<()> {
    let row_count = item_kinds.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || item_file_ids.len() != row_count
        || path_starts.len() != row_count
        || path_ends.len() != row_count
        || path_nodes.len() != row_count
        || import_target_kinds.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR item path record arrays have inconsistent lengths"
        ));
    }

    let mut path_node_owners = vec![INVALID; row_count];
    for row in 0..row_count {
        let item_kind = item_kinds[row];
        let import_target_kind = import_target_kinds[row];
        if item_kind != HIR_ITEM_KIND_IMPORT {
            if import_target_kind != HIR_ITEM_IMPORT_TARGET_NONE {
                return Err(anyhow!(
                    "parser HIR item row {row} published import-target metadata for non-import item kind {item_kind}"
                ));
            }
        } else {
            match import_target_kind {
                HIR_ITEM_IMPORT_TARGET_PATH => {}
                HIR_ITEM_IMPORT_TARGET_NONE => {
                    return Err(anyhow!(
                        "parser HIR import item row {row} published no import target record"
                    ));
                }
                HIR_ITEM_IMPORT_TARGET_STRING => {
                    return Err(anyhow!(
                        "parser HIR import item row {row} published unsupported string import target without a parser-owned path record"
                    ));
                }
                other => {
                    return Err(anyhow!(
                        "parser HIR import item row {row} published unknown import target kind {other}"
                    ));
                }
            }
        }

        let expects_path = item_kind == HIR_ITEM_KIND_MODULE
            || (item_kind == HIR_ITEM_KIND_IMPORT
                && import_target_kind == HIR_ITEM_IMPORT_TARGET_PATH);
        if !expects_path {
            if path_starts[row] != INVALID
                || path_ends[row] != INVALID
                || path_nodes[row] != INVALID
            {
                return Err(anyhow!(
                    "parser HIR item row {row} published a path record without a module/import path owner"
                ));
            }
            continue;
        }
        let expected_owner_kind = if item_kind == HIR_ITEM_KIND_MODULE {
            HIR_NODE_MODULE_ITEM
        } else {
            HIR_NODE_IMPORT_ITEM
        };
        if kinds[row] != expected_owner_kind {
            return Err(anyhow!(
                "parser HIR item path row {row} published item kind {item_kind} on HIR kind {}, expected path owner kind {expected_owner_kind}",
                kinds[row]
            ));
        }

        if token_pos[row] == INVALID
            || token_end[row] == INVALID
            || token_pos[row] >= token_end[row]
        {
            return Err(anyhow!(
                "parser HIR item path row {row} published a path owner without a non-empty item span"
            ));
        }
        if node_file_ids[row] == INVALID || item_file_ids[row] != node_file_ids[row] {
            return Err(anyhow!(
                "parser HIR item path row {row} has inconsistent item and node file ids"
            ));
        }

        let path_start = path_starts[row];
        let path_end = path_ends[row];
        if path_start == INVALID
            || path_end == INVALID
            || path_start >= path_end
            || path_start <= token_pos[row]
            || path_end > token_end[row]
        {
            return Err(anyhow!(
                "parser HIR item path row {row} published a path span outside its item span"
            ));
        }

        let path_node = path_nodes[row];
        if path_node == INVALID || path_node as usize >= row_count {
            return Err(anyhow!(
                "parser HIR item path row {row} published no in-table path node"
            ));
        }
        let path_node = path_node as usize;
        if kinds[path_node] != HIR_NODE_PATH_EXPR {
            return Err(anyhow!(
                "parser HIR item path row {row} path node {path_node} is not a path HIR row"
            ));
        }
        if node_file_ids[path_node] != item_file_ids[row] {
            return Err(anyhow!(
                "parser HIR item path row {row} path node {path_node} has a different file id"
            ));
        }
        if token_pos[path_node] != path_start || token_end[path_node] != path_end {
            return Err(anyhow!(
                "parser HIR item path row {row} path node {path_node} does not anchor the published path span"
            ));
        }
        let previous_owner = path_node_owners[path_node];
        if previous_owner != INVALID {
            return Err(anyhow!(
                "parser HIR item path row {row} shares path node {path_node} with item path row {previous_owner}"
            ));
        }
        path_node_owners[path_node] = row as u32;
    }

    Ok(())
}
