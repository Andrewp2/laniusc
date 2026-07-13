use super::super::super::*;

fn is_hir_expression_kind(kind: u32) -> bool {
    matches!(
        kind,
        HIR_NODE_EXPR
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
            | HIR_NODE_STRUCT_LITERAL_EXPR
            | HIR_NODE_PATH_EXPR
            | HIR_NODE_MATCH_EXPR
    )
}

fn is_hir_expr_value_form(form: u32) -> bool {
    matches!(
        form,
        HIR_EXPR_FORM_NAME
            | HIR_EXPR_FORM_INT
            | HIR_EXPR_FORM_TRUE
            | HIR_EXPR_FORM_FALSE
            | HIR_EXPR_FORM_FLOAT
            | HIR_EXPR_FORM_STRING
            | HIR_EXPR_FORM_CHAR
    )
}

fn is_hir_expr_literal_form(form: u32) -> bool {
    matches!(
        form,
        HIR_EXPR_FORM_INT
            | HIR_EXPR_FORM_TRUE
            | HIR_EXPR_FORM_FALSE
            | HIR_EXPR_FORM_FLOAT
            | HIR_EXPR_FORM_STRING
            | HIR_EXPR_FORM_CHAR
    )
}

fn is_hir_expr_unary_form(form: u32) -> bool {
    matches!(form, HIR_EXPR_FORM_NOT | HIR_EXPR_FORM_NEG)
}

fn is_hir_expr_binary_form(form: u32) -> bool {
    matches!(
        form,
        HIR_EXPR_FORM_EQ
            | HIR_EXPR_FORM_NE
            | HIR_EXPR_FORM_LT
            | HIR_EXPR_FORM_GT
            | HIR_EXPR_FORM_LE
            | HIR_EXPR_FORM_GE
            | HIR_EXPR_FORM_ADD
            | HIR_EXPR_FORM_SUB
            | HIR_EXPR_FORM_MUL
            | HIR_EXPR_FORM_AND
            | HIR_EXPR_FORM_OR
            | HIR_EXPR_FORM_MOD
            | HIR_EXPR_FORM_DIV
            | HIR_EXPR_FORM_BIT_OR
            | HIR_EXPR_FORM_BIT_XOR
            | HIR_EXPR_FORM_BIT_AND
            | HIR_EXPR_FORM_SHL
            | HIR_EXPR_FORM_SHR
    )
}

fn is_hir_expr_range_form(form: u32) -> bool {
    matches!(
        form,
        HIR_EXPR_FORM_RANGE
            | HIR_EXPR_FORM_RANGE_FROM
            | HIR_EXPR_FORM_RANGE_TO
            | HIR_EXPR_FORM_RANGE_FULL
            | HIR_EXPR_FORM_RANGE_INCLUSIVE
            | HIR_EXPR_FORM_RANGE_TO_INCLUSIVE
    )
}

/// Validates expression form, operand, and literal value-token records.
pub fn validate_hir_expression_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    expr_forms: &[u32],
    left_nodes: &[u32],
    right_nodes: &[u32],
    value_tokens: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || expr_forms.len() != row_count
        || left_nodes.len() != row_count
        || right_nodes.len() != row_count
        || value_tokens.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR expression record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let require_expression_owner = |node: usize, label: &str| -> Result<()> {
        if !is_hir_expression_kind(kinds[node]) {
            return Err(anyhow!(
                "parser HIR expression row {node} published {label} without an expression HIR row"
            ));
        }
        if !has_non_empty_span(node) || node_file_ids[node] == INVALID {
            return Err(anyhow!(
                "parser HIR expression row {node} published {label} without a source-addressable expression row"
            ));
        }
        Ok(())
    };

    let require_empty = |node: usize, label: &str| -> Result<()> {
        if left_nodes[node] != INVALID
            || right_nodes[node] != INVALID
            || value_tokens[node] != INVALID
        {
            return Err(anyhow!(
                "parser HIR expression row {node} published {label} with non-empty operands"
            ));
        }
        Ok(())
    };

    let require_no_right_or_value = |node: usize, label: &str| -> Result<()> {
        if right_nodes[node] != INVALID || value_tokens[node] != INVALID {
            return Err(anyhow!(
                "parser HIR expression row {node} published {label} with non-empty reserved operands"
            ));
        }
        Ok(())
    };

    let require_no_value = |node: usize, label: &str| -> Result<()> {
        if value_tokens[node] != INVALID {
            return Err(anyhow!(
                "parser HIR expression row {node} published {label} with a non-empty value token"
            ));
        }
        Ok(())
    };

    let require_no_left = |node: usize, left: u32, label: &str| -> Result<()> {
        if left != INVALID {
            return Err(anyhow!(
                "parser HIR expression row {node} published {label} with a non-empty left operand"
            ));
        }
        Ok(())
    };

    let require_no_right = |node: usize, right: u32, label: &str| -> Result<()> {
        if right != INVALID {
            return Err(anyhow!(
                "parser HIR expression row {node} published {label} with a non-empty right operand"
            ));
        }
        Ok(())
    };

    let require_value_token = |node: usize, token: u32, label: &str| -> Result<()> {
        if token == INVALID || token < token_pos[node] || token >= token_end[node] {
            return Err(anyhow!(
                "parser HIR expression row {node} published {label} value token outside its expression span"
            ));
        }
        Ok(())
    };

    let require_expression_edge = |owner: usize, node: u32, label: &str| -> Result<usize> {
        if node == INVALID || node as usize >= row_count {
            return Err(anyhow!(
                "parser HIR expression row {owner} published {label} without an in-table parser-owned expression row"
            ));
        }
        let node = node as usize;
        if node == owner {
            return Err(anyhow!(
                "parser HIR expression row {owner} published {label} as a self edge"
            ));
        }
        if !is_hir_expression_kind(kinds[node]) {
            return Err(anyhow!(
                "parser HIR expression row {owner} published {label} row {node} with non-expression HIR kind {}",
                kinds[node]
            ));
        }
        if !has_non_empty_span(node) {
            return Err(anyhow!(
                "parser HIR expression row {owner} published {label} row {node} without a non-empty token span"
            ));
        }
        if node_file_ids[owner] == INVALID || node_file_ids[node] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR expression row {owner} published {label} row {node} with a different file id"
            ));
        }
        if token_pos[node] < token_pos[owner] || token_end[node] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR expression row {owner} published {label} row {node} outside the owner expression span (owner={}..{}, operand={}..{})",
                token_pos[owner],
                token_end[owner],
                token_pos[node],
                token_end[node]
            ));
        }
        Ok(node)
    };

    let require_ordered_expression_pair = |owner: usize,
                                           left: usize,
                                           right: usize,
                                           label: &str|
     -> Result<()> {
        if token_pos[right] <= token_pos[left] || token_end[left] > token_pos[right] {
            return Err(anyhow!(
                "parser HIR expression row {owner} published {label} operands out of source order"
            ));
        }
        Ok(())
    };

    for row in 0..row_count {
        let form = expr_forms[row];
        match form {
            HIR_EXPR_FORM_NONE => {
                if matches!(kinds[row], HIR_NODE_NAME_EXPR | HIR_NODE_LITERAL_EXPR) {
                    return Err(anyhow!(
                        "parser HIR expression row {row} has expression leaf HIR kind {} but no parser-owned expression record",
                        kinds[row]
                    ));
                }
                require_empty(row, "no expression record")?;
            }
            HIR_EXPR_FORM_FORWARD => {
                require_expression_owner(row, "forward record")?;
                require_expression_edge(row, left_nodes[row], "forward target")?;
                require_no_right_or_value(row, "forward record")?;
            }
            form if is_hir_expr_value_form(form) => {
                require_expression_owner(row, "value record")?;
                if form == HIR_EXPR_FORM_NAME
                    && !matches!(kinds[row], HIR_NODE_NAME_EXPR | HIR_NODE_PATH_EXPR)
                {
                    return Err(anyhow!(
                        "parser HIR expression row {row} published name value form on incompatible HIR kind {}",
                        kinds[row]
                    ));
                }
                if is_hir_expr_literal_form(form) && kinds[row] != HIR_NODE_LITERAL_EXPR {
                    return Err(anyhow!(
                        "parser HIR expression row {row} published literal value form {form} on incompatible HIR kind {}",
                        kinds[row]
                    ));
                }
                if left_nodes[row] != INVALID || right_nodes[row] != INVALID {
                    return Err(anyhow!(
                        "parser HIR expression row {row} published value record with non-empty child edges"
                    ));
                }
                require_value_token(row, value_tokens[row], "value record")?;
            }
            form if is_hir_expr_unary_form(form) => {
                require_expression_owner(row, "unary record")?;
                require_expression_edge(row, left_nodes[row], "unary operand")?;
                require_no_right_or_value(row, "unary record")?;
            }
            form if is_hir_expr_binary_form(form) => {
                require_expression_owner(row, "binary record")?;
                let left = require_expression_edge(row, left_nodes[row], "binary left operand")?;
                let right = require_expression_edge(row, right_nodes[row], "binary right operand")?;
                require_ordered_expression_pair(row, left, right, "binary")?;
                require_no_value(row, "binary record")?;
            }
            form if is_hir_expr_range_form(form) => {
                require_expression_owner(row, "range record")?;
                let has_start = matches!(
                    form,
                    HIR_EXPR_FORM_RANGE | HIR_EXPR_FORM_RANGE_FROM | HIR_EXPR_FORM_RANGE_INCLUSIVE
                );
                let has_end = matches!(
                    form,
                    HIR_EXPR_FORM_RANGE
                        | HIR_EXPR_FORM_RANGE_TO
                        | HIR_EXPR_FORM_RANGE_INCLUSIVE
                        | HIR_EXPR_FORM_RANGE_TO_INCLUSIVE
                );
                let left = if has_start {
                    Some(require_expression_edge(
                        row,
                        left_nodes[row],
                        "range start operand",
                    )?)
                } else {
                    require_no_left(row, left_nodes[row], "range record")?;
                    None
                };
                let right = if has_end {
                    Some(require_expression_edge(
                        row,
                        right_nodes[row],
                        "range end operand",
                    )?)
                } else {
                    require_no_right(row, right_nodes[row], "range record")?;
                    None
                };
                if let (Some(left), Some(right)) = (left, right) {
                    require_ordered_expression_pair(row, left, right, "range")?;
                }
                require_no_value(row, "range record")?;
            }
            HIR_EXPR_FORM_INDEX => {
                require_expression_owner(row, "index record")?;
                let base = require_expression_edge(row, left_nodes[row], "index base")?;
                let index = require_expression_edge(row, right_nodes[row], "index expression")?;
                require_ordered_expression_pair(row, base, index, "index")?;
                if token_pos[row] != token_pos[base] {
                    return Err(anyhow!(
                        "parser HIR expression row {row} index span does not start at base row {base}"
                    ));
                }
                require_no_value(row, "index record")?;
            }
            other => {
                return Err(anyhow!(
                    "parser HIR expression row {row} published unknown expression record form {other}"
                ));
            }
        }
    }

    Ok(())
}

/// Validates expression result-root records.
pub fn validate_hir_expression_result_root_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    result_roots: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || result_roots.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR expression-result-root arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    for (row, &root) in result_roots.iter().enumerate() {
        if root == INVALID {
            continue;
        }
        if !is_hir_expression_kind(kinds[row]) {
            return Err(anyhow!(
                "parser HIR expression-result row {row} published a result root without an expression HIR row"
            ));
        }
        let root = root as usize;
        if root >= row_count {
            return Err(anyhow!(
                "parser HIR expression-result row {row} published result root {root}, outside {row_count} readback rows"
            ));
        }
        if !is_hir_expression_kind(kinds[root]) {
            return Err(anyhow!(
                "parser HIR expression-result row {row} published non-expression result root {root} with HIR kind {}",
                kinds[root]
            ));
        }
        if !has_non_empty_span(row) || !has_non_empty_span(root) {
            return Err(anyhow!(
                "parser HIR expression-result row {row} published result root {root} without source-addressable spans"
            ));
        }
        if node_file_ids[row] == INVALID
            || node_file_ids[root] == INVALID
            || node_file_ids[row] != node_file_ids[root]
        {
            return Err(anyhow!(
                "parser HIR expression-result row {row} published result root {root} with a different file id"
            ));
        }
        if token_pos[root] < token_pos[row] || token_end[root] > token_end[row] {
            return Err(anyhow!(
                "parser HIR expression-result row {row} published result root {root} outside the expression span"
            ));
        }
        if result_roots[root] != root as u32 {
            let next_root = result_roots[root];
            return Err(anyhow!(
                "parser HIR expression-result row {row} published non-canonical result root {root} whose root row points to {next_root}"
            ));
        }
    }

    Ok(())
}

fn is_hir_match_pattern_kind(kind: u32) -> bool {
    matches!(kind, HIR_NODE_NAME_EXPR | HIR_NODE_LITERAL_EXPR)
}

fn expected_statement_record_kind_for_hir_kind(kind: u32) -> Option<u32> {
    match kind {
        HIR_NODE_LET_STMT => Some(HIR_STMT_RECORD_KIND_LET),
        HIR_NODE_RETURN_STMT => Some(HIR_STMT_RECORD_KIND_RETURN),
        HIR_NODE_IF_STMT => Some(HIR_STMT_RECORD_KIND_IF),
        HIR_NODE_CONST_ITEM => Some(HIR_STMT_RECORD_KIND_CONST),
        HIR_NODE_WHILE_STMT => Some(HIR_STMT_RECORD_KIND_WHILE),
        HIR_NODE_FOR_STMT => Some(HIR_STMT_RECORD_KIND_FOR),
        HIR_NODE_BREAK_STMT => Some(HIR_STMT_RECORD_KIND_BREAK),
        HIR_NODE_CONTINUE_STMT => Some(HIR_STMT_RECORD_KIND_CONTINUE),
        _ => None,
    }
}

/// Validates call callee, argument owner, ordinal, and span records.
pub fn validate_hir_call_argument_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    callee_nodes: &[u32],
    starts: &[u32],
    arg_ends: &[u32],
    counts: &[u32],
    parent_calls: &[u32],
    ordinals: &[u32],
) -> Result<()> {
    let row_count = counts.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || callee_nodes.len() != row_count
        || starts.len() != row_count
        || arg_ends.len() != row_count
        || parent_calls.len() != row_count
        || ordinals.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR call argument record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let require_call_source = |call_node: usize| -> Result<()> {
        if !has_non_empty_span(call_node) {
            return Err(anyhow!(
                "parser HIR call row {call_node} published call metadata without a non-empty token span"
            ));
        }
        if node_file_ids[call_node] == INVALID {
            return Err(anyhow!(
                "parser HIR call row {call_node} published call metadata without a source file id"
            ));
        }
        Ok(())
    };

    let require_child_source = |owner: usize, child: usize, label: &str| -> Result<()> {
        require_call_source(owner)?;
        if !has_non_empty_span(child) {
            return Err(anyhow!(
                "parser HIR call row {owner} published {label} row {child} without a non-empty token span"
            ));
        }
        if node_file_ids[child] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR call row {owner} published {label} row {child} with a different file id"
            ));
        }
        if token_pos[child] < token_pos[owner] || token_end[child] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR call row {owner} published {label} row {child} outside the call expression span"
            ));
        }
        Ok(())
    };

    for (call_node, &callee) in callee_nodes.iter().enumerate() {
        if kinds[call_node] != HIR_NODE_CALL_EXPR {
            if callee != INVALID || starts[call_node] != INVALID || counts[call_node] != 0 {
                return Err(anyhow!(
                    "parser HIR call row {call_node} published call metadata without a call-expression HIR owner"
                ));
            }
            continue;
        }
        require_call_source(call_node)?;

        if callee == INVALID || callee as usize >= row_count {
            return Err(anyhow!(
                "parser HIR call row {call_node} published a call expression without an in-table callee"
            ));
        }
        if callee as usize == call_node {
            return Err(anyhow!(
                "parser HIR call row {call_node} points at itself as the call callee"
            ));
        }
        let callee = callee as usize;
        if !is_hir_expression_kind(kinds[callee]) {
            return Err(anyhow!(
                "parser HIR call row {call_node} published callee row {callee} with non-expression HIR kind {}",
                kinds[callee]
            ));
        }
        require_child_source(call_node, callee, "callee")?;
        if token_pos[call_node] != token_pos[callee] {
            return Err(anyhow!(
                "parser HIR call row {call_node} span does not start at callee row {callee}"
            ));
        }
    }

    let mut actual_counts = vec![0u32; row_count];
    let mut ordinal_keys = Vec::new();
    for (arg_node, &owner) in parent_calls.iter().enumerate() {
        if owner == INVALID {
            if ordinals[arg_node] != INVALID || arg_ends[arg_node] != INVALID {
                return Err(anyhow!(
                    "parser HIR call argument row {arg_node} published argument metadata without an owner"
                ));
            }
            continue;
        }
        let owner = owner as usize;
        if owner >= row_count {
            return Err(anyhow!(
                "parser HIR call argument row {arg_node} published owner {owner}, outside {row_count} readback rows"
            ));
        }
        if kinds[owner] != HIR_NODE_CALL_EXPR {
            return Err(anyhow!(
                "parser HIR call argument row {arg_node} points at owner {owner} without a call-expression HIR owner"
            ));
        }
        if kinds[arg_node] != HIR_NODE_EXPR {
            return Err(anyhow!(
                "parser HIR call argument row {arg_node} is not an expression HIR row"
            ));
        }
        require_child_source(owner, arg_node, "argument")?;
        if arg_ends[arg_node] == INVALID {
            return Err(anyhow!(
                "parser HIR call argument row {arg_node} omitted its parser-owned argument end token"
            ));
        }
        if arg_ends[arg_node] != token_end[arg_node] {
            return Err(anyhow!(
                "parser HIR call argument row {arg_node} published argument end token {} that does not match its HIR span end {}",
                arg_ends[arg_node],
                token_end[arg_node]
            ));
        }
        if arg_ends[arg_node] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR call argument row {arg_node} published argument end token outside owner {owner} call span"
            ));
        }

        let owner_count = counts[owner];
        if owner_count == 0 {
            return Err(anyhow!(
                "parser HIR call argument row {arg_node} points at owner {owner} with zero argument count"
            ));
        }

        let ordinal = ordinals[arg_node];
        if ordinal >= owner_count {
            return Err(anyhow!(
                "parser HIR call argument row {arg_node} published ordinal {ordinal}, outside owner {owner} count {owner_count}"
            ));
        }
        actual_counts[owner] += 1;
        ordinal_keys.push((owner, ordinal, arg_node));
    }
    ordinal_keys.sort_unstable_by_key(|&(owner, ordinal, _)| (owner, ordinal));
    for pair in ordinal_keys.windows(2) {
        let (owner, ordinal, _) = pair[0];
        let (next_owner, next_ordinal, _) = pair[1];
        if owner == next_owner && ordinal == next_ordinal {
            return Err(anyhow!(
                "parser HIR call row {owner} published duplicate argument ordinal {ordinal}"
            ));
        }
    }

    for (owner, &count) in counts.iter().enumerate() {
        if count == 0 {
            if starts[owner] != INVALID {
                return Err(anyhow!(
                    "parser HIR call row {owner} published a first argument without an argument count"
                ));
            }
            continue;
        }
        if kinds[owner] != HIR_NODE_CALL_EXPR {
            return Err(anyhow!(
                "parser HIR call row {owner} published argument count {count} without a call-expression HIR owner"
            ));
        }
        let start = starts[owner];
        if start == INVALID || start as usize >= row_count {
            return Err(anyhow!(
                "parser HIR call row {owner} published argument count {count} without an in-table first argument"
            ));
        }
        let start = start as usize;
        if parent_calls[start] as usize != owner || ordinals[start] != 0 {
            return Err(anyhow!(
                "parser HIR call row {owner} first argument row {start} is not ordinal zero for that owner"
            ));
        }
        if token_pos[start] < token_pos[owner] || token_end[start] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR call row {owner} first argument row {start} is outside the call expression span"
            ));
        }
        let callee = callee_nodes[owner] as usize;
        if callee >= row_count {
            return Err(anyhow!(
                "parser HIR call row {owner} published argument metadata without an in-table callee"
            ));
        }
        if token_end[callee] > token_pos[start] {
            return Err(anyhow!(
                "parser HIR call row {owner} published callee row {callee} that does not precede first argument row {start}"
            ));
        }
        if actual_counts[owner] != count {
            return Err(anyhow!(
                "parser HIR call row {owner} published count {count} but read back {} owned argument rows",
                actual_counts[owner]
            ));
        }
        let mut previous_arg = start;
        for expected_ordinal in 1..count {
            let next_arg = ordinal_keys
                .binary_search_by_key(&(owner, expected_ordinal), |&(owner, ordinal, _)| {
                    (owner, ordinal)
                })
                .ok()
                .map(|index| ordinal_keys[index].2)
                .ok_or_else(|| {
                    anyhow!(
                        "parser HIR call row {owner} argument ordinals are not contiguous from zero"
                    )
                })?;
            if token_pos[next_arg] <= token_pos[previous_arg]
                || token_end[previous_arg] > token_pos[next_arg]
            {
                return Err(anyhow!(
                    "parser HIR call row {owner} argument rows overlap or are not in source order at row {next_arg}"
                ));
            }
            previous_arg = next_arg;
        }
    }

    Ok(())
}

/// Validates array literal element owner, ordinal, and context records.
pub fn validate_hir_array_literal_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    first_elements: &[u32],
    counts: &[u32],
    parent_literals: &[u32],
    ordinals: &[u32],
    next_elements: &[u32],
) -> Result<()> {
    let row_count = counts.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || first_elements.len() != row_count
        || parent_literals.len() != row_count
        || ordinals.len() != row_count
        || next_elements.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR array literal record arrays have inconsistent lengths"
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
                "parser HIR array literal {label} row {node} lacks a non-empty token span"
            ));
        }
        if node_file_ids[node] == INVALID {
            return Err(anyhow!(
                "parser HIR array literal {label} row {node} lacks a source file id"
            ));
        }
        Ok(())
    };

    for (row, &kind) in kinds.iter().enumerate() {
        if kind == HIR_NODE_ARRAY_EXPR {
            require_span(row, "owner")?;
        }
    }

    let mut actual_counts = vec![0u32; row_count];
    for (element_node, &owner) in parent_literals.iter().enumerate() {
        if owner == INVALID {
            if ordinals[element_node] != INVALID || next_elements[element_node] != INVALID {
                return Err(anyhow!(
                    "parser HIR array element row {element_node} published element metadata without an owner"
                ));
            }
            continue;
        }

        let owner = owner as usize;
        if owner >= row_count {
            return Err(anyhow!(
                "parser HIR array element row {element_node} published owner {owner}, outside {row_count} readback rows"
            ));
        }
        if kinds[owner] != HIR_NODE_ARRAY_EXPR {
            return Err(anyhow!(
                "parser HIR array element row {element_node} points at owner {owner} without an array-literal HIR owner"
            ));
        }
        if !is_hir_expression_kind(kinds[element_node]) {
            return Err(anyhow!(
                "parser HIR array element row {element_node} is not an expression HIR row"
            ));
        }

        let owner_count = counts[owner];
        if owner_count == 0 {
            return Err(anyhow!(
                "parser HIR array element row {element_node} points at owner {owner} with zero element count"
            ));
        }
        require_span(owner, "owner")?;
        require_span(element_node, "element")?;
        if node_file_ids[element_node] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR array element row {element_node} published a different file id than owner {owner}"
            ));
        }
        if token_pos[element_node] < token_pos[owner] || token_end[element_node] > token_end[owner]
        {
            return Err(anyhow!(
                "parser HIR array element row {element_node} falls outside owner {owner} span"
            ));
        }
        if owner_count as usize > row_count {
            return Err(anyhow!(
                "parser HIR array literal row {owner} published {owner_count} elements, exceeding {row_count} readback rows"
            ));
        }

        let ordinal = ordinals[element_node];
        if ordinal >= owner_count {
            return Err(anyhow!(
                "parser HIR array element row {element_node} published ordinal {ordinal}, outside owner {owner} count {owner_count}"
            ));
        }
        let next = next_elements[element_node];
        if next != INVALID && next as usize >= row_count {
            return Err(anyhow!(
                "parser HIR array element row {element_node} published next element {next}, outside {row_count} readback rows"
            ));
        }
        actual_counts[owner] += 1;
    }

    for (owner, &count) in counts.iter().enumerate() {
        if count == 0 {
            if first_elements[owner] != INVALID {
                return Err(anyhow!(
                    "parser HIR array literal row {owner} published first element without an element count"
                ));
            }
            continue;
        }
        if kinds[owner] != HIR_NODE_ARRAY_EXPR {
            return Err(anyhow!(
                "parser HIR array literal row {owner} published element count {count} without an array-literal HIR owner"
            ));
        }
        require_span(owner, "owner")?;
        if count as usize > row_count {
            return Err(anyhow!(
                "parser HIR array literal row {owner} published {count} elements, exceeding {row_count} readback rows"
            ));
        }

        let first = first_elements[owner];
        if first == INVALID || first as usize >= row_count {
            return Err(anyhow!(
                "parser HIR array literal row {owner} published element count {count} without an in-table first element"
            ));
        }
        let first = first as usize;
        if token_pos[first] <= token_pos[owner] {
            return Err(anyhow!(
                "parser HIR array literal row {owner} first element row {first} does not follow the array literal start token"
            ));
        }
        if actual_counts[owner] != count {
            return Err(anyhow!(
                "parser HIR array literal row {owner} published count {count} but read back {} owned element rows",
                actual_counts[owner]
            ));
        }

        let mut element = first;
        for expected_ordinal in 0..count {
            if parent_literals[element] as usize != owner {
                return Err(anyhow!(
                    "parser HIR array literal row {owner} element chain row {element} does not point back to that owner"
                ));
            }
            if ordinals[element] != expected_ordinal {
                return Err(anyhow!(
                    "parser HIR array literal row {owner} element chain is not contiguous from zero"
                ));
            }

            let next = next_elements[element];
            if expected_ordinal + 1 == count {
                if next != INVALID {
                    return Err(anyhow!(
                        "parser HIR array literal row {owner} final element row {element} did not terminate the element chain"
                    ));
                }
            } else {
                if next == INVALID || next as usize >= row_count {
                    return Err(anyhow!(
                        "parser HIR array literal row {owner} element chain ended before count {count}"
                    ));
                }
                let next = next as usize;
                if parent_literals[next] as usize != owner {
                    return Err(anyhow!(
                        "parser HIR array literal row {owner} element chain row {next} does not point back to that owner"
                    ));
                }
                if token_pos[next] <= token_pos[element] || token_end[element] > token_pos[next] {
                    return Err(anyhow!(
                        "parser HIR array literal row {owner} element chain overlaps or is not in source order at row {element}"
                    ));
                }
                element = next;
            }
        }
    }

    Ok(())
}

/// Validates member receiver/name token records.
pub fn validate_hir_member_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    receiver_nodes: &[u32],
    receiver_tokens: &[u32],
    member_name_tokens: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || receiver_nodes.len() != row_count
        || receiver_tokens.len() != row_count
        || member_name_tokens.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR member record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    for row in 0..row_count {
        let receiver = receiver_nodes[row];
        let receiver_token = receiver_tokens[row];
        let member_token = member_name_tokens[row];

        if kinds[row] != HIR_NODE_MEMBER_EXPR {
            if receiver != INVALID || receiver_token != INVALID || member_token != INVALID {
                return Err(anyhow!(
                    "parser HIR member row {row} published member metadata without a member-expression HIR owner"
                ));
            }
            continue;
        }

        if !has_non_empty_span(row) {
            return Err(anyhow!(
                "parser HIR member row {row} published a member expression without a non-empty token span"
            ));
        }
        if node_file_ids[row] == INVALID {
            return Err(anyhow!(
                "parser HIR member row {row} published a member expression without a source file id"
            ));
        }
        if receiver == INVALID || receiver as usize >= row_count || receiver as usize == row {
            return Err(anyhow!(
                "parser HIR member row {row} published no in-table receiver expression"
            ));
        }
        let receiver = receiver as usize;
        if !is_hir_expression_kind(kinds[receiver]) {
            return Err(anyhow!(
                "parser HIR member row {row} receiver row {receiver} has non-expression HIR kind {}",
                kinds[receiver]
            ));
        }
        if !has_non_empty_span(receiver) {
            return Err(anyhow!(
                "parser HIR member row {row} receiver row {receiver} lacks a non-empty token span"
            ));
        }
        if node_file_ids[receiver] != node_file_ids[row] {
            return Err(anyhow!(
                "parser HIR member row {row} receiver row {receiver} has a different file id"
            ));
        }
        if token_pos[receiver] < token_pos[row] || token_end[receiver] > token_end[row] {
            return Err(anyhow!(
                "parser HIR member row {row} receiver row {receiver} is outside the member expression span"
            ));
        }
        if token_pos[row] != token_pos[receiver] {
            return Err(anyhow!(
                "parser HIR member row {row} member expression span does not start at receiver row {receiver}"
            ));
        }
        if receiver_token == INVALID || member_token == INVALID || receiver_token >= member_token {
            return Err(anyhow!(
                "parser HIR member row {row} published unordered receiver/member tokens"
            ));
        }
        if receiver_token < token_pos[receiver] || receiver_token >= token_end[receiver] {
            return Err(anyhow!(
                "parser HIR member row {row} receiver token is outside receiver row {receiver}"
            ));
        }
        if token_end[receiver] >= member_token {
            return Err(anyhow!(
                "parser HIR member row {row} receiver row {receiver} does not leave a member separator before the member-name token (receiver span={}..{}, member token={member_token}, member span={}..{})",
                token_pos[receiver],
                token_end[receiver],
                token_pos[row],
                token_end[row],
            ));
        }
        if member_token < token_pos[row] || member_token >= token_end[row] {
            return Err(anyhow!(
                "parser HIR member row {row} member-name token is outside the member expression span"
            ));
        }
        if token_end[row] != member_token + 1 {
            return Err(anyhow!(
                "parser HIR member row {row} member expression span does not end at the member-name token"
            ));
        }
    }

    Ok(())
}

/// Validates match scrutinee, arm, payload, and result records.
pub fn validate_hir_match_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    scrutinee_nodes: &[u32],
    arm_starts: &[u32],
    arm_counts: &[u32],
    arm_next: &[u32],
    arm_pattern_nodes: &[u32],
    arm_payload_starts: &[u32],
    arm_payload_counts: &[u32],
    arm_result_nodes: &[u32],
    payload_owner_arms: &[u32],
    payload_match_nodes: &[u32],
    payload_ordinals: &[u32],
) -> Result<()> {
    let row_count = arm_counts.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || scrutinee_nodes.len() != row_count
        || arm_starts.len() != row_count
        || arm_next.len() != row_count
        || arm_pattern_nodes.len() != row_count
        || arm_payload_starts.len() != row_count
        || arm_payload_counts.len() != row_count
        || arm_result_nodes.len() != row_count
        || payload_owner_arms.len() != row_count
        || payload_match_nodes.len() != row_count
        || payload_ordinals.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR match record arrays have inconsistent lengths"
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
                "parser HIR match {label} row {node} lacks a non-empty token span"
            ));
        }
        if node_file_ids[node] == INVALID {
            return Err(anyhow!(
                "parser HIR match {label} row {node} lacks a source file id"
            ));
        }
        Ok(())
    };

    let require_child_source = |owner: usize, child: usize, label: &str| -> Result<()> {
        require_span(owner, "owner")?;
        require_span(child, label)?;
        if node_file_ids[child] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR match {label} row {child} published a different file id than owner row {owner}"
            ));
        }
        if token_pos[child] < token_pos[owner] || token_end[child] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR match {label} row {child} falls outside owner row {owner} span"
            ));
        }
        Ok(())
    };

    let require_source_precedes = |owner: usize,
                                   left: usize,
                                   right: usize,
                                   left_label: &str,
                                   right_label: &str|
     -> Result<()> {
        if token_end[left] > token_pos[right] {
            return Err(anyhow!(
                "parser HIR match row {owner} published {left_label} row {left} that does not precede {right_label} row {right}"
            ));
        }
        Ok(())
    };

    let total_claimed_arms = arm_counts.iter().try_fold(0usize, |acc, &count| {
        acc.checked_add(count as usize)
            .ok_or_else(|| anyhow!("parser HIR match arm counts overflowed host usize"))
    })?;
    if total_claimed_arms > row_count {
        return Err(anyhow!(
            "parser HIR match rows claim {total_claimed_arms} arm rows, exceeding {row_count} readback rows"
        ));
    }

    let total_claimed_payloads = arm_payload_counts.iter().try_fold(0usize, |acc, &count| {
        acc.checked_add(count as usize)
            .ok_or_else(|| anyhow!("parser HIR match payload counts overflowed host usize"))
    })?;
    if total_claimed_payloads > row_count {
        return Err(anyhow!(
            "parser HIR match arms claim {total_claimed_payloads} payload rows, exceeding {row_count} readback rows"
        ));
    }

    let mut arm_owner = vec![INVALID; row_count];
    let mut arm_ordinal = vec![INVALID; row_count];
    for (match_node, &count) in arm_counts.iter().enumerate() {
        if count == 0 {
            if kinds[match_node] == HIR_NODE_MATCH_EXPR {
                return Err(anyhow!(
                    "parser HIR match row {match_node} has a match-expression HIR kind but no parser-owned match record"
                ));
            }
            if scrutinee_nodes[match_node] != INVALID {
                return Err(anyhow!(
                    "parser HIR match row {match_node} published a scrutinee without a match-expression HIR owner"
                ));
            }
            if arm_starts[match_node] != INVALID {
                return Err(anyhow!(
                    "parser HIR match row {match_node} published a first arm without an arm count"
                ));
            }
            continue;
        }

        if kinds[match_node] != HIR_NODE_MATCH_EXPR {
            return Err(anyhow!(
                "parser HIR match row {match_node} published arm count {count} without a match-expression HIR owner"
            ));
        }
        require_span(match_node, "expression")?;
        let scrutinee = scrutinee_nodes[match_node];
        if scrutinee == INVALID || scrutinee as usize >= row_count {
            return Err(anyhow!(
                "parser HIR match row {match_node} published arm count {count} without an in-table scrutinee expression"
            ));
        }
        if kinds[scrutinee as usize] != HIR_NODE_EXPR {
            return Err(anyhow!(
                "parser HIR match row {match_node} scrutinee row {scrutinee} is not an expression HIR row"
            ));
        }
        require_child_source(match_node, scrutinee as usize, "scrutinee")?;

        let start = arm_starts[match_node];
        if start == INVALID || start as usize >= row_count {
            return Err(anyhow!(
                "parser HIR match row {match_node} published arm count {count} without an in-table first arm"
            ));
        }

        let mut arm = start as usize;
        for expected_ordinal in 0..count as usize {
            if arm_owner[arm] != INVALID {
                return Err(anyhow!(
                    "parser HIR match arm row {arm} appears in multiple match arm chains"
                ));
            }
            if kinds[arm] != HIR_NODE_NONE {
                return Err(anyhow!(
                    "parser HIR match arm row {arm} has HIR kind {}, not a parser-owned match arm row",
                    kinds[arm]
                ));
            }
            arm_owner[arm] = match_node as u32;
            arm_ordinal[arm] = expected_ordinal as u32;
            require_child_source(match_node, arm, "arm")?;
            if expected_ordinal == 0 {
                require_source_precedes(
                    match_node,
                    scrutinee as usize,
                    arm,
                    "scrutinee",
                    "first arm",
                )?;
            }

            let pattern_node = arm_pattern_nodes[arm];
            if pattern_node == INVALID || pattern_node as usize >= row_count {
                return Err(anyhow!(
                    "parser HIR match arm row {arm} published no in-table pattern node"
                ));
            }
            if !is_hir_match_pattern_kind(kinds[pattern_node as usize]) {
                return Err(anyhow!(
                    "parser HIR match arm row {arm} pattern row {pattern_node} has non-pattern HIR kind {}",
                    kinds[pattern_node as usize]
                ));
            }
            require_child_source(arm, pattern_node as usize, "arm pattern")?;
            let result_node = arm_result_nodes[arm];
            if result_node == INVALID || result_node as usize >= row_count {
                return Err(anyhow!(
                    "parser HIR match arm row {arm} published no in-table result expression"
                ));
            }
            if kinds[result_node as usize] != HIR_NODE_EXPR {
                return Err(anyhow!(
                    "parser HIR match arm row {arm} result row {result_node} is not an expression HIR row"
                ));
            }
            require_child_source(arm, result_node as usize, "arm result")?;
            require_source_precedes(
                arm,
                pattern_node as usize,
                result_node as usize,
                "pattern",
                "result expression",
            )?;

            let next = arm_next[arm];
            if expected_ordinal + 1 == count as usize {
                if next != INVALID {
                    return Err(anyhow!(
                        "parser HIR match row {match_node} final arm row {arm} did not terminate the arm chain"
                    ));
                }
            } else {
                if next == INVALID || next as usize >= row_count {
                    return Err(anyhow!(
                        "parser HIR match row {match_node} arm chain ended before count {count}"
                    ));
                }
                let next = next as usize;
                if token_pos[next] <= token_pos[arm] {
                    return Err(anyhow!(
                        "parser HIR match row {match_node} arm chain is not in source order at row {arm}"
                    ));
                }
                require_source_precedes(match_node, arm, next, "arm", "next arm")?;
                arm = next;
            }
        }
    }

    let mut actual_payload_counts = vec![0u32; row_count];
    let mut payload_ordinal_keys = Vec::new();
    for (payload_node, &owner) in payload_owner_arms.iter().enumerate() {
        if owner == INVALID {
            if arm_owner[payload_node] != INVALID {
                if payload_match_nodes[payload_node] != arm_owner[payload_node]
                    || payload_ordinals[payload_node] != arm_ordinal[payload_node]
                {
                    return Err(anyhow!(
                        "parser HIR match arm row {payload_node} published arm rank metadata that disagrees with its match arm chain"
                    ));
                }
            } else if payload_match_nodes[payload_node] != INVALID
                || payload_ordinals[payload_node] != INVALID
            {
                return Err(anyhow!(
                    "parser HIR match payload row {payload_node} published payload metadata without an owner arm"
                ));
            }
            continue;
        }

        let owner = owner as usize;
        if owner >= row_count {
            return Err(anyhow!(
                "parser HIR match payload row {payload_node} published owner arm {owner}, outside {row_count} readback rows"
            ));
        }
        let match_node = arm_owner[owner];
        if match_node == INVALID {
            return Err(anyhow!(
                "parser HIR match payload row {payload_node} points at arm row {owner} outside any match arm chain"
            ));
        }
        if payload_match_nodes[payload_node] != match_node {
            return Err(anyhow!(
                "parser HIR match payload row {payload_node} published match {}, but owner arm {owner} belongs to match {match_node}",
                payload_match_nodes[payload_node]
            ));
        }

        let owner_count = arm_payload_counts[owner];
        if owner_count == 0 {
            return Err(anyhow!(
                "parser HIR match payload row {payload_node} points at arm row {owner} with zero payload count"
            ));
        }
        let ordinal = payload_ordinals[payload_node];
        if ordinal >= owner_count {
            return Err(anyhow!(
                "parser HIR match payload row {payload_node} published ordinal {ordinal}, outside owner arm {owner} count {owner_count}"
            ));
        }
        if !is_hir_match_pattern_kind(kinds[payload_node]) {
            return Err(anyhow!(
                "parser HIR match payload row {payload_node} has non-pattern HIR kind {}",
                kinds[payload_node]
            ));
        }
        require_child_source(owner, payload_node, "payload")?;
        let pattern_node = arm_pattern_nodes[owner] as usize;
        if token_pos[payload_node] < token_pos[pattern_node]
            || token_end[payload_node] > token_end[pattern_node]
        {
            return Err(anyhow!(
                "parser HIR match payload row {payload_node} falls outside owner arm {owner} pattern row {pattern_node} span"
            ));
        }
        if token_pos[payload_node] <= token_pos[pattern_node] {
            return Err(anyhow!(
                "parser HIR match payload row {payload_node} does not start after owner arm {owner} pattern head row {pattern_node}"
            ));
        }

        actual_payload_counts[owner] += 1;
        payload_ordinal_keys.push((owner, ordinal, payload_node));
    }

    payload_ordinal_keys.sort_unstable_by_key(|&(owner, ordinal, _)| (owner, ordinal));
    for pair in payload_ordinal_keys.windows(2) {
        let (owner, ordinal, payload_node) = pair[0];
        let (next_owner, next_ordinal, _) = pair[1];
        if owner == next_owner && ordinal == next_ordinal {
            return Err(anyhow!(
                "parser HIR match arm row {owner} published duplicate payload ordinal {ordinal} at row {payload_node}"
            ));
        }
    }

    for arm in 0..row_count {
        if arm_owner[arm] == INVALID {
            if arm_pattern_nodes[arm] != INVALID
                || arm_result_nodes[arm] != INVALID
                || arm_next[arm] != INVALID
                || arm_payload_starts[arm] != INVALID
                || arm_payload_counts[arm] != 0
            {
                return Err(anyhow!(
                    "parser HIR match arm row {arm} published arm metadata without belonging to a match"
                ));
            }
            continue;
        }

        let payload_count = arm_payload_counts[arm];
        if payload_count == 0 {
            if arm_payload_starts[arm] != INVALID {
                return Err(anyhow!(
                    "parser HIR match arm row {arm} published a first payload without a payload count"
                ));
            }
            continue;
        }

        let payload_start = arm_payload_starts[arm];
        if payload_start == INVALID || payload_start as usize >= row_count {
            return Err(anyhow!(
                "parser HIR match arm row {arm} published payload count {payload_count} without an in-table first payload"
            ));
        }
        if payload_owner_arms[payload_start as usize] as usize != arm
            || payload_ordinals[payload_start as usize] != 0
        {
            return Err(anyhow!(
                "parser HIR match arm row {arm} first payload row {payload_start} is not ordinal zero for that arm"
            ));
        }
        if actual_payload_counts[arm] != payload_count {
            return Err(anyhow!(
                "parser HIR match arm row {arm} published payload count {payload_count} but read back {} owned payload rows",
                actual_payload_counts[arm]
            ));
        }

        let mut previous_payload: Option<usize> = None;
        for expected_ordinal in 0..payload_count {
            let payload = payload_ordinal_keys
                .binary_search_by_key(&(arm, expected_ordinal), |&(owner, ordinal, _)| {
                    (owner, ordinal)
                })
                .ok()
                .map(|index| payload_ordinal_keys[index].2)
                .ok_or_else(|| {
                    anyhow!(
                        "parser HIR match arm row {arm} payload ordinals are not contiguous from zero"
                    )
                })?;
            if let Some(previous_payload) = previous_payload {
                if token_pos[payload] <= token_pos[previous_payload] {
                    return Err(anyhow!(
                        "parser HIR match arm row {arm} payload ordinals are not in source order at row {payload}"
                    ));
                }
                if token_end[previous_payload] > token_pos[payload] {
                    return Err(anyhow!(
                        "parser HIR match arm row {arm} payload rows overlap before row {payload}"
                    ));
                }
            }
            previous_payload = Some(payload);
        }
    }

    Ok(())
}

/// Validates statement record kind, operands, and scope-end records.
pub fn validate_hir_statement_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    stmt_kinds: &[u32],
    operand0: &[u32],
    operand1: &[u32],
    operand2: &[u32],
    stmt_scope_end: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || stmt_kinds.len() != row_count
        || operand0.len() != row_count
        || operand1.len() != row_count
        || operand2.len() != row_count
        || stmt_scope_end.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR statement record arrays have inconsistent lengths"
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
                "parser HIR statement row {node} published {label} without a non-empty token span"
            ));
        }
        Ok(())
    };

    let require_statement_kind = |node: usize, expected: u32, label: &str| -> Result<()> {
        if kinds[node] != expected {
            return Err(anyhow!(
                "parser HIR statement row {node} published {label} on HIR kind {}, expected {expected}",
                kinds[node]
            ));
        }
        Ok(())
    };

    let require_empty_operands = |node: usize, label: &str| -> Result<()> {
        if operand0[node] != INVALID || operand1[node] != INVALID || operand2[node] != INVALID {
            return Err(anyhow!(
                "parser HIR statement row {node} published {label} with non-empty operands ({}, {}, {}) on HIR kind {} span {}..{}",
                operand0[node],
                operand1[node],
                operand2[node],
                kinds[node],
                token_pos[node],
                token_end[node],
            ));
        }
        Ok(())
    };

    let require_token_inside = |owner: usize, token: u32, label: &str| -> Result<()> {
        require_span(owner, label)?;
        if token == INVALID || token < token_pos[owner] || token >= token_end[owner] {
            return Err(anyhow!(
                "parser HIR statement row {owner} published {label} token outside its statement span"
            ));
        }
        Ok(())
    };

    let require_empty_scope_end = |node: usize, label: &str| -> Result<()> {
        if stmt_scope_end[node] != INVALID {
            return Err(anyhow!(
                "parser HIR statement row {node} published {label} with a declaration scope end"
            ));
        }
        Ok(())
    };

    let require_scope_end_after_owner = |node: usize, label: &str| -> Result<()> {
        require_span(node, label)?;
        let end = stmt_scope_end[node];
        if end == INVALID || end < token_end[node] {
            return Err(anyhow!(
                "parser HIR statement row {node} published {label} without a parser-owned declaration scope end after its statement span"
            ));
        }
        Ok(())
    };

    let require_node_edge = |owner: usize,
                             node: u32,
                             allowed_kinds: &[u32],
                             require_inside_owner: bool,
                             label: &str|
     -> Result<usize> {
        if node == INVALID || node as usize >= row_count {
            return Err(anyhow!(
                "parser HIR statement row {owner} published {label} node {node} without an in-table parser-owned node (rows={row_count}, owner kind={}, span={}..{}, operands=({}, {}, {}))",
                kinds[owner],
                token_pos[owner],
                token_end[owner],
                operand0[owner],
                operand1[owner],
                operand2[owner]
            ));
        }
        let node = node as usize;
        require_span(owner, label)?;
        require_span(node, label)?;
        if node_file_ids[owner] == INVALID || node_file_ids[node] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR statement row {owner} published {label} row {node} with a different file id"
            ));
        }
        if require_inside_owner
            && (token_pos[node] < token_pos[owner] || token_end[node] > token_end[owner])
        {
            return Err(anyhow!(
                "parser HIR statement row {owner} published {label} row {node} outside its statement span"
            ));
        }
        if !allowed_kinds.is_empty() && !allowed_kinds.contains(&kinds[node]) {
            return Err(anyhow!(
                "parser HIR statement row {owner} published {label} row {node} with HIR kind {}",
                kinds[node]
            ));
        }
        Ok(node)
    };

    let require_expression_edge = |owner: usize, node: u32, label: &str| -> Result<usize> {
        let node = require_node_edge(owner, node, &[], true, label)?;
        if !is_hir_expression_kind(kinds[node]) {
            return Err(anyhow!(
                "parser HIR statement row {owner} published {label} row {node} with non-expression HIR kind {}",
                kinds[node]
            ));
        }
        Ok(node)
    };

    for row in 0..row_count {
        if stmt_kinds[row] != HIR_STMT_RECORD_KIND_NONE {
            require_span(row, "statement record")?;
            if node_file_ids[row] == INVALID {
                return Err(anyhow!(
                    "parser HIR statement row {row} published a statement record without a node file id"
                ));
            }
        } else if let Some(expected_kind) = expected_statement_record_kind_for_hir_kind(kinds[row])
        {
            return Err(anyhow!(
                "parser HIR statement row {row} has concrete HIR statement kind {} but no parser-owned statement record kind {expected_kind}",
                kinds[row]
            ));
        }

        match stmt_kinds[row] {
            HIR_STMT_RECORD_KIND_NONE => {
                require_empty_operands(row, "no statement record")?;
                require_empty_scope_end(row, "no statement record")?;
            }
            HIR_STMT_RECORD_KIND_LET => {
                require_statement_kind(row, HIR_NODE_LET_STMT, "let record")?;
                require_token_inside(row, operand0[row], "let declaration")?;
                require_scope_end_after_owner(row, "let declaration")?;
                if operand1[row] != INVALID {
                    require_expression_edge(row, operand1[row], "let initializer")?;
                }
                if operand2[row] != INVALID {
                    require_node_edge(
                        row,
                        operand2[row],
                        &[HIR_NODE_TYPE],
                        true,
                        "let declared type",
                    )?;
                }
            }
            HIR_STMT_RECORD_KIND_RETURN => {
                require_statement_kind(row, HIR_NODE_RETURN_STMT, "return record")?;
                require_empty_scope_end(row, "return record")?;
                if operand1[row] != INVALID {
                    return Err(anyhow!(
                        "parser HIR statement row {row} published return record with a non-empty reserved operand"
                    ));
                }
                if operand0[row] == INVALID {
                    if operand2[row] != INVALID {
                        return Err(anyhow!(
                            "parser HIR statement row {row} published a return value token without a return expression"
                        ));
                    }
                } else {
                    let return_expression =
                        require_expression_edge(row, operand0[row], "return expression")?;
                    require_token_inside(row, operand2[row], "return value")?;
                    if operand2[row] < token_pos[return_expression]
                        || operand2[row] >= token_end[return_expression]
                    {
                        return Err(anyhow!(
                            "parser HIR statement row {row} published return value token outside its return expression span"
                        ));
                    }
                }
            }
            HIR_STMT_RECORD_KIND_IF => {
                require_statement_kind(row, HIR_NODE_IF_STMT, "if record")?;
                require_empty_scope_end(row, "if record")?;
                let condition = require_expression_edge(row, operand0[row], "if condition")?;
                let then_block =
                    require_node_edge(row, operand1[row], &[HIR_NODE_BLOCK], false, "if then arm")?;
                if token_end[condition] > token_pos[then_block] {
                    return Err(anyhow!(
                        "parser HIR statement row {row} published if condition row {condition} that overlaps the then block"
                    ));
                }
                if operand2[row] != INVALID {
                    let else_block = require_node_edge(
                        row,
                        operand2[row],
                        &[HIR_NODE_BLOCK],
                        false,
                        "if else block",
                    )?;
                    if else_block == then_block {
                        return Err(anyhow!(
                            "parser HIR statement row {row} published the same block row for if then and else arms"
                        ));
                    }
                    if token_pos[else_block] < token_end[then_block] {
                        return Err(anyhow!(
                            "parser HIR statement row {row} published if else block before the then arm ended"
                        ));
                    }
                }
            }
            HIR_STMT_RECORD_KIND_CONST => {
                require_statement_kind(row, HIR_NODE_CONST_ITEM, "const record")?;
                require_token_inside(row, operand0[row], "const declaration")?;
                require_expression_edge(row, operand1[row], "const value")?;
                require_node_edge(
                    row,
                    operand2[row],
                    &[HIR_NODE_TYPE],
                    true,
                    "const declared type",
                )?;
                if stmt_scope_end[row] != INVALID {
                    require_scope_end_after_owner(row, "const declaration")?;
                }
            }
            HIR_STMT_RECORD_KIND_ASSIGN => {
                require_statement_kind(row, HIR_NODE_STMT, "assignment record")?;
                require_empty_scope_end(row, "assignment record")?;
                let target = require_expression_edge(row, operand0[row], "assignment target")?;
                let rhs = require_expression_edge(row, operand1[row], "assignment rhs")?;
                if token_end[target] > token_pos[rhs] {
                    return Err(anyhow!(
                        "parser HIR statement row {row} published assignment target row {target} that overlaps or follows rhs row {rhs}"
                    ));
                }
                let op = operand2[row];
                if !(HIR_ASSIGN_OP_SET..=HIR_ASSIGN_OP_BOR).contains(&op) {
                    return Err(anyhow!(
                        "parser HIR statement row {row} published assignment operator {op} outside the supported operator range"
                    ));
                }
            }
            HIR_STMT_RECORD_KIND_WHILE => {
                require_statement_kind(row, HIR_NODE_WHILE_STMT, "while record")?;
                require_empty_scope_end(row, "while record")?;
                let condition = require_expression_edge(row, operand0[row], "while condition")?;
                let body =
                    require_node_edge(row, operand1[row], &[HIR_NODE_BLOCK], false, "while body")?;
                if token_end[condition] > token_pos[body] {
                    return Err(anyhow!(
                        "parser HIR statement row {row} published while condition row {condition} that overlaps the body block"
                    ));
                }
                if operand2[row] != INVALID {
                    return Err(anyhow!(
                        "parser HIR statement row {row} published while record with a non-empty reserved operand"
                    ));
                }
            }
            HIR_STMT_RECORD_KIND_FOR => {
                require_statement_kind(row, HIR_NODE_FOR_STMT, "for record")?;
                require_token_inside(row, operand0[row], "for binding")?;
                let iterable =
                    require_expression_edge(row, operand1[row], "for iterable expression")?;
                let body =
                    require_node_edge(row, operand2[row], &[HIR_NODE_BLOCK], false, "for body")?;
                require_scope_end_after_owner(row, "for binding")?;
                if stmt_scope_end[row] != token_end[body] {
                    return Err(anyhow!(
                        "parser HIR statement row {row} published for declaration scope end that does not match the body block end"
                    ));
                }
                if token_end[iterable] > token_pos[body] {
                    return Err(anyhow!(
                        "parser HIR statement row {row} published for iterable expression row {iterable} after the body block started"
                    ));
                }
            }
            HIR_STMT_RECORD_KIND_BREAK => {
                require_statement_kind(row, HIR_NODE_BREAK_STMT, "break record")?;
                require_span(row, "break record")?;
                require_empty_operands(row, "break record")?;
                require_empty_scope_end(row, "break record")?;
            }
            HIR_STMT_RECORD_KIND_CONTINUE => {
                require_statement_kind(row, HIR_NODE_CONTINUE_STMT, "continue record")?;
                require_span(row, "continue record")?;
                require_empty_operands(row, "continue record")?;
                require_empty_scope_end(row, "continue record")?;
            }
            other => {
                return Err(anyhow!(
                    "parser HIR statement row {row} published unknown statement record kind {other}"
                ));
            }
        }
    }

    Ok(())
}

/// Validates const item statement ownership records.
pub fn validate_hir_const_item_statement_records(
    kinds: &[u32],
    item_kinds: &[u32],
    item_name_tokens: &[u32],
    stmt_kinds: &[u32],
    stmt_decl_tokens: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if item_kinds.len() != row_count
        || item_name_tokens.len() != row_count
        || stmt_kinds.len() != row_count
        || stmt_decl_tokens.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR const item/statement record arrays have inconsistent lengths"
        ));
    }

    for row in 0..row_count {
        let has_const_item = item_kinds[row] == HIR_ITEM_KIND_CONST;
        let has_const_stmt = stmt_kinds[row] == HIR_STMT_RECORD_KIND_CONST;

        if has_const_item {
            if kinds[row] != HIR_NODE_CONST_ITEM {
                return Err(anyhow!(
                    "parser HIR const item row {row} published item metadata on HIR kind {}",
                    kinds[row]
                ));
            }
            if !has_const_stmt {
                return Err(anyhow!(
                    "parser HIR const item row {row} published const item metadata without a const statement record"
                ));
            }
        }

        if has_const_stmt {
            if kinds[row] != HIR_NODE_CONST_ITEM {
                return Err(anyhow!(
                    "parser HIR const statement row {row} published const statement metadata on HIR kind {}",
                    kinds[row]
                ));
            }
            if !has_const_item {
                return Err(anyhow!(
                    "parser HIR const statement row {row} published a const statement record without const item metadata"
                ));
            }
            if item_name_tokens[row] == INVALID || stmt_decl_tokens[row] != item_name_tokens[row] {
                return Err(anyhow!(
                    "parser HIR const statement row {row} declaration token does not match its item name token"
                ));
            }
        }
    }

    Ok(())
}

/// Validates nearest statement, block, control, loop, and function relations.
pub fn validate_hir_context_relation_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    stmt_record_kinds: &[u32],
    nearest_stmt_nodes: &[u32],
    nearest_block_nodes: &[u32],
    nearest_control_nodes: &[u32],
    nearest_loop_nodes: &[u32],
    nearest_fn_nodes: &[u32],
    call_context_stmt_nodes: &[u32],
    array_lit_context_stmt_nodes: &[u32],
    struct_lit_context_stmt_nodes: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || stmt_record_kinds.len() != row_count
        || nearest_stmt_nodes.len() != row_count
        || nearest_block_nodes.len() != row_count
        || nearest_control_nodes.len() != row_count
        || nearest_loop_nodes.len() != row_count
        || nearest_fn_nodes.len() != row_count
        || call_context_stmt_nodes.len() != row_count
        || array_lit_context_stmt_nodes.len() != row_count
        || struct_lit_context_stmt_nodes.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR context-relation record arrays have inconsistent lengths: kinds={row_count} token_pos={} token_end={} file_ids={} stmt_kinds={} nearest_stmt={} nearest_block={} nearest_control={} nearest_loop={} nearest_fn={} call_context={} array_context={} struct_context={}",
            token_pos.len(),
            token_end.len(),
            node_file_ids.len(),
            stmt_record_kinds.len(),
            nearest_stmt_nodes.len(),
            nearest_block_nodes.len(),
            nearest_control_nodes.len(),
            nearest_loop_nodes.len(),
            nearest_fn_nodes.len(),
            call_context_stmt_nodes.len(),
            array_lit_context_stmt_nodes.len(),
            struct_lit_context_stmt_nodes.len(),
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let has_statement_record = |node: usize| {
        if kinds[node] == HIR_NODE_STMT {
            return stmt_record_kinds[node] == HIR_STMT_RECORD_KIND_ASSIGN
                || (stmt_record_kinds[node] == HIR_STMT_RECORD_KIND_NONE
                    && nearest_block_nodes[node] != INVALID);
        }
        match expected_statement_record_kind_for_hir_kind(kinds[node]) {
            Some(expected) => stmt_record_kinds[node] == expected,
            None => false,
        }
    };

    let require_relation = |row: usize, related: u32, label: &str| -> Result<Option<usize>> {
        if related == INVALID {
            return Ok(None);
        }
        let related = related as usize;
        if related >= row_count {
            return Err(anyhow!(
                "parser HIR context row {row} published {label} relation {related}, outside {row_count} readback rows"
            ));
        }
        if !has_non_empty_span(row) || !has_non_empty_span(related) {
            return Err(anyhow!(
                "parser HIR context row {row} published {label} relation {related} without source-addressable spans"
            ));
        }
        if node_file_ids[row] == INVALID
            || node_file_ids[related] == INVALID
            || node_file_ids[row] != node_file_ids[related]
        {
            return Err(anyhow!(
                "parser HIR context row {row} published {label} relation {related} with a different file id"
            ));
        }
        if token_pos[related] > token_pos[row] || token_end[row] > token_end[related] {
            return Err(anyhow!(
                "parser HIR context row {row} published {label} relation {related} outside the related node span"
            ));
        }
        Ok(Some(related))
    };

    let relation_contains = |outer: usize, inner: usize| -> bool {
        has_non_empty_span(outer)
            && has_non_empty_span(inner)
            && node_file_ids[outer] != INVALID
            && node_file_ids[outer] == node_file_ids[inner]
            && token_pos[outer] <= token_pos[inner]
            && token_end[inner] <= token_end[outer]
    };

    let require_context_contains = |row: usize,
                                    outer: Option<usize>,
                                    inner: Option<usize>,
                                    outer_label: &str,
                                    inner_label: &str|
     -> Result<()> {
        let (Some(outer), Some(inner)) = (outer, inner) else {
            return Ok(());
        };
        if !relation_contains(outer, inner) {
            return Err(anyhow!(
                "parser HIR context row {row} published {outer_label} relation {outer} that does not contain {inner_label} relation {inner}"
            ));
        }
        Ok(())
    };

    let require_context_peer_relation = |row: usize,
                                         context: usize,
                                         row_relation_value: u32,
                                         context_relation_value: u32,
                                         relation_label: &str,
                                         context_label: &str|
     -> Result<()> {
        let context_relation = require_relation(context, context_relation_value, relation_label)?;
        let row_relation = require_relation(row, row_relation_value, relation_label)?;
        match (row_relation, context_relation) {
            (None, None) => {}
            (None, Some(context_relation)) => {
                return Err(anyhow!(
                    "parser HIR context row {row} published {context_label} relation {context} without matching {relation_label} relation {context_relation}"
                ));
            }
            (Some(row_relation), None) => {
                return Err(anyhow!(
                    "parser HIR context row {row} published {context_label} relation {context} with extra {relation_label} relation {row_relation} that the context row omitted"
                ));
            }
            (Some(row_relation), Some(context_relation)) if row_relation != context_relation => {
                return Err(anyhow!(
                    "parser HIR context row {row} published {context_label} relation {context} with {relation_label} relation {row_relation} that disagrees with context {relation_label} relation {context_relation}"
                ));
            }
            (Some(_), Some(_)) => {}
        }
        Ok(())
    };

    for row in 0..row_count {
        let nearest_statement =
            require_relation(row, nearest_stmt_nodes[row], "nearest statement")?;
        if let Some(stmt) = nearest_statement {
            if !has_statement_record(stmt) {
                return Err(anyhow!(
                    "parser HIR context row {row} nearest statement relation {stmt} is not backed by a parser-owned statement record (stmt_hir_kind={}, stmt_record_kind={}, stmt_nearest_block={})",
                    kinds[stmt],
                    stmt_record_kinds[stmt],
                    nearest_block_nodes[stmt]
                ));
            }
        }
        if has_statement_record(row) {
            match nearest_statement {
                Some(stmt) if stmt == row => {}
                Some(stmt) => {
                    return Err(anyhow!(
                        "parser HIR context row {row} statement row published nearest statement relation {stmt} instead of itself"
                    ));
                }
                None => {
                    return Err(anyhow!(
                        "parser HIR context row {row} statement row omitted its nearest statement self relation"
                    ));
                }
            }
        }

        let nearest_block = require_relation(row, nearest_block_nodes[row], "nearest block")?;
        if let Some(block) = nearest_block {
            if kinds[block] != HIR_NODE_BLOCK {
                return Err(anyhow!(
                    "parser HIR context row {row} nearest block relation {block} has HIR kind {}",
                    kinds[block]
                ));
            }
        }
        if kinds[row] == HIR_NODE_BLOCK {
            match nearest_block {
                Some(block) if block == row => {}
                Some(block) => {
                    return Err(anyhow!(
                        "parser HIR context row {row} block row published nearest block relation {block} instead of itself"
                    ));
                }
                None => {
                    return Err(anyhow!(
                        "parser HIR context row {row} block row omitted its nearest block self relation"
                    ));
                }
            }
        }
        if has_statement_record(row) && kinds[row] != HIR_NODE_CONST_ITEM && nearest_block.is_none()
        {
            return Err(anyhow!(
                "parser HIR context row {row} statement row omitted its nearest block relation (kind={}, span={}..{})",
                kinds[row],
                token_pos[row],
                token_end[row]
            ));
        }

        let nearest_control =
            require_relation(row, nearest_control_nodes[row], "nearest enclosing control")?;
        if let Some(control) = nearest_control {
            if control == row {
                return Err(anyhow!(
                    "parser HIR context row {row} published itself as nearest enclosing control"
                ));
            }
            if !matches!(
                kinds[control],
                HIR_NODE_IF_STMT | HIR_NODE_WHILE_STMT | HIR_NODE_FOR_STMT | HIR_NODE_MATCH_EXPR
            ) {
                return Err(anyhow!(
                    "parser HIR context row {row} nearest enclosing control relation {control} has HIR kind {}",
                    kinds[control]
                ));
            }
            if expected_statement_record_kind_for_hir_kind(kinds[control]).is_some()
                && !has_statement_record(control)
            {
                return Err(anyhow!(
                    "parser HIR context row {row} nearest enclosing control relation {control} is not backed by a parser-owned control statement record"
                ));
            }
        }

        let nearest_loop = require_relation(row, nearest_loop_nodes[row], "nearest loop")?;
        if let Some(loop_node) = nearest_loop {
            if !matches!(kinds[loop_node], HIR_NODE_WHILE_STMT | HIR_NODE_FOR_STMT) {
                return Err(anyhow!(
                    "parser HIR context row {row} nearest loop relation {loop_node} has HIR kind {}",
                    kinds[loop_node]
                ));
            }
            if !has_statement_record(loop_node) {
                return Err(anyhow!(
                    "parser HIR context row {row} nearest loop relation {loop_node} is not backed by a parser-owned loop statement record"
                ));
            }
        }
        if matches!(kinds[row], HIR_NODE_WHILE_STMT | HIR_NODE_FOR_STMT) {
            match nearest_loop {
                Some(loop_node) if loop_node == row => {}
                Some(loop_node) => {
                    return Err(anyhow!(
                        "parser HIR context row {row} loop row published nearest loop relation {loop_node} instead of itself"
                    ));
                }
                None => {
                    return Err(anyhow!(
                        "parser HIR context row {row} loop row omitted its nearest loop self relation"
                    ));
                }
            }
        }
        if let Some(control) = nearest_control {
            if matches!(kinds[control], HIR_NODE_WHILE_STMT | HIR_NODE_FOR_STMT) {
                let loop_row_owns_itself =
                    matches!(kinds[row], HIR_NODE_WHILE_STMT | HIR_NODE_FOR_STMT)
                        && nearest_loop == Some(row)
                        && relation_contains(control, row);
                if !loop_row_owns_itself {
                    match nearest_loop {
                        Some(loop_node) if loop_node == control => {}
                        Some(loop_node) => {
                            return Err(anyhow!(
                                "parser HIR context row {row} nearest loop relation {loop_node} disagrees with loop enclosing control {control}"
                            ));
                        }
                        None => {
                            return Err(anyhow!(
                                "parser HIR context row {row} omitted nearest loop relation for loop enclosing control {control}"
                            ));
                        }
                    }
                }
            }
        }
        if matches!(kinds[row], HIR_NODE_BREAK_STMT | HIR_NODE_CONTINUE_STMT)
            || matches!(
                stmt_record_kinds[row],
                HIR_STMT_RECORD_KIND_BREAK | HIR_STMT_RECORD_KIND_CONTINUE
            )
        {
            if nearest_loop.is_none() {
                return Err(anyhow!(
                    "parser HIR context row {row} loop-control statement omitted its nearest loop relation"
                ));
            }
        }
        let nearest_function = require_relation(row, nearest_fn_nodes[row], "nearest function")?;
        if let Some(function) = nearest_function {
            if kinds[function] != HIR_NODE_FN {
                return Err(anyhow!(
                    "parser HIR context row {row} nearest function relation {function} has HIR kind {}",
                    kinds[function]
                ));
            }
        }
        if kinds[row] == HIR_NODE_FN {
            match nearest_function {
                Some(function) if function == row => {}
                Some(function) => {
                    return Err(anyhow!(
                        "parser HIR context row {row} function row published nearest function relation {function} instead of itself"
                    ));
                }
                None => {
                    return Err(anyhow!(
                        "parser HIR context row {row} function row omitted its nearest function self relation"
                    ));
                }
            }
        }
        if kinds[row] == HIR_NODE_RETURN_STMT
            || stmt_record_kinds[row] == HIR_STMT_RECORD_KIND_RETURN
        {
            if nearest_function.is_none() {
                return Err(anyhow!(
                    "parser HIR context row {row} return statement omitted its nearest function relation (kind={}, span={}..{}, nearest_stmt={:?}, nearest_block={:?}, nearest_control={:?}, nearest_loop={:?}, raw_nearest_fn={})",
                    kinds[row],
                    token_pos[row],
                    token_end[row],
                    nearest_statement,
                    nearest_block,
                    nearest_control,
                    nearest_loop,
                    nearest_fn_nodes[row]
                ));
            }
        }

        if matches!(kinds[row], HIR_NODE_WHILE_STMT | HIR_NODE_FOR_STMT)
            && nearest_loop == Some(row)
        {
            if let Some(control) = nearest_control
                && !relation_contains(control, row)
            {
                return Err(anyhow!(
                    "parser HIR context row {row} loop statement is outside nearest enclosing control relation {control}"
                ));
            }
        } else {
            require_context_contains(
                row,
                nearest_loop,
                nearest_control,
                "nearest loop",
                "nearest enclosing control",
            )?;
        }
        require_context_contains(
            row,
            nearest_function,
            nearest_statement,
            "nearest function",
            "nearest statement",
        )?;
        require_context_contains(
            row,
            nearest_function,
            nearest_block,
            "nearest function",
            "nearest block",
        )?;
        if kinds[row] != HIR_NODE_BLOCK {
            require_context_contains(
                row,
                nearest_block,
                nearest_statement,
                "nearest block",
                "nearest statement",
            )?;
        }
        require_context_contains(
            row,
            nearest_function,
            nearest_control,
            "nearest function",
            "nearest enclosing control",
        )?;
        require_context_contains(
            row,
            nearest_function,
            nearest_loop,
            "nearest function",
            "nearest loop",
        )?;
    }

    for (contexts, owner_kind, label) in [
        (
            call_context_stmt_nodes,
            HIR_NODE_CALL_EXPR,
            "call contextual statement",
        ),
        (
            array_lit_context_stmt_nodes,
            HIR_NODE_ARRAY_EXPR,
            "array literal contextual statement",
        ),
        (
            struct_lit_context_stmt_nodes,
            HIR_NODE_STRUCT_LITERAL_EXPR,
            "struct literal contextual statement",
        ),
    ] {
        for (row, &context) in contexts.iter().enumerate() {
            if kinds[row] != owner_kind {
                if context != INVALID {
                    return Err(anyhow!(
                        "parser HIR context row {row} published {label} without the matching owner HIR kind"
                    ));
                }
                continue;
            }

            let Some(context) = require_relation(row, context, label)? else {
                if let Some(nearest_stmt) =
                    require_relation(row, nearest_stmt_nodes[row], "nearest statement")?
                {
                    return Err(anyhow!(
                        "parser HIR context row {row} omitted {label} relation even though nearest statement {nearest_stmt} is available"
                    ));
                }
                continue;
            };
            if !has_statement_record(context) {
                return Err(anyhow!(
                    "parser HIR context row {row} published {label} relation {context} without a parser-owned statement relation"
                ));
            }
            let Some(nearest_stmt) =
                require_relation(row, nearest_stmt_nodes[row], "nearest statement")?
            else {
                return Err(anyhow!(
                    "parser HIR context row {row} published {label} relation {context} without a parser-owned nearest statement relation"
                ));
            };
            if nearest_stmt != context {
                return Err(anyhow!(
                    "parser HIR context row {row} published {label} relation {context} that disagrees with nearest statement {nearest_stmt}"
                ));
            }
            require_context_peer_relation(
                row,
                context,
                nearest_block_nodes[row],
                nearest_block_nodes[context],
                "nearest block",
                label,
            )?;
            require_context_peer_relation(
                row,
                context,
                nearest_fn_nodes[row],
                nearest_fn_nodes[context],
                "nearest function",
                label,
            )?;
            require_context_peer_relation(
                row,
                context,
                nearest_loop_nodes[row],
                nearest_loop_nodes[context],
                "nearest loop",
                label,
            )?;
            let row_control =
                require_relation(row, nearest_control_nodes[row], "nearest enclosing control")?;
            let context_control = require_relation(
                context,
                nearest_control_nodes[context],
                "nearest enclosing control",
            )?;
            let context_is_control = matches!(
                kinds[context],
                HIR_NODE_IF_STMT | HIR_NODE_WHILE_STMT | HIR_NODE_FOR_STMT | HIR_NODE_MATCH_EXPR
            );
            match (row_control, context_control) {
                (Some(row_control), _) if context_is_control && row_control == context => {}
                (Some(row_control), _) if relation_contains(context, row_control) => {}
                (None, None) => {}
                (None, Some(context_control)) => {
                    return Err(anyhow!(
                        "parser HIR context row {row} published {label} relation {context} without matching nearest enclosing control relation {context_control}"
                    ));
                }
                (Some(row_control), None) => {
                    return Err(anyhow!(
                        "parser HIR context row {row} published {label} relation {context} with extra nearest enclosing control relation {row_control} that the context row omitted"
                    ));
                }
                (Some(row_control), Some(context_control)) if row_control != context_control => {
                    return Err(anyhow!(
                        "parser HIR context row {row} published {label} relation {context} with nearest enclosing control relation {row_control} that disagrees with context nearest enclosing control relation {context_control}"
                    ));
                }
                (Some(_), Some(_)) => {}
            }
        }
    }

    Ok(())
}
