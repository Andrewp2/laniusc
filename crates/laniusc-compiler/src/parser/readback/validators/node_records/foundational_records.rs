use super::super::super::*;

pub fn validate_hir_enum_variant_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    type_file_ids: &[u32],
    item_kinds: &[u32],
    item_file_ids: &[u32],
    parent_enums: &[u32],
    variant_ordinals: &[u32],
    payload_starts: &[u32],
    payload_counts: &[u32],
    payload_nodes: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    let slot_stride = HIR_VARIANT_PAYLOAD_SLOT_STRIDE as usize;
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || type_forms.len() != row_count
        || type_file_ids.len() != row_count
        || item_kinds.len() != row_count
        || item_file_ids.len() != row_count
        || parent_enums.len() != row_count
        || variant_ordinals.len() != row_count
        || payload_starts.len() != row_count
        || payload_counts.len() != row_count
        || payload_nodes.len() != row_count.saturating_mul(slot_stride)
    {
        return Err(anyhow!(
            "parser HIR enum variant record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let require_child_source = |owner: usize, child: usize, label: &str| -> Result<()> {
        if !has_non_empty_span(owner) || node_file_ids[owner] == INVALID {
            return Err(anyhow!(
                "parser HIR enum variant owner row {owner} lacks source-addressable metadata"
            ));
        }
        if !has_non_empty_span(child) || node_file_ids[child] == INVALID {
            return Err(anyhow!(
                "parser HIR enum variant {label} row {child} lacks source-addressable metadata"
            ));
        }
        if node_file_ids[child] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR enum variant {label} row {child} published a different file id than owner row {owner}"
            ));
        }
        if token_pos[child] < token_pos[owner] || token_end[child] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR enum variant {label} row {child} falls outside owner row {owner} span"
            ));
        }
        Ok(())
    };

    let mut variant_ordinal_keys = Vec::new();
    let mut payload_owner = vec![INVALID; row_count];
    for (row, &parent) in parent_enums.iter().enumerate() {
        let payload_base = row * slot_stride;
        let payload_slots = &payload_nodes[payload_base..payload_base + slot_stride];

        if parent == INVALID {
            if variant_ordinals[row] != INVALID {
                return Err(anyhow!(
                    "parser HIR enum variant row {row} published an ordinal without an enum owner"
                ));
            }
            if payload_starts[row] != INVALID
                || payload_counts[row] != 0
                || payload_slots.iter().any(|&payload| payload != INVALID)
            {
                return Err(anyhow!(
                    "parser HIR enum variant row {row} published payload metadata without an enum-variant owner (kind={}, span={}..{}, item_kind={}, payload_start={}, payload_count={}, payload_slots={:?})",
                    kinds[row],
                    token_pos[row],
                    token_end[row],
                    item_kinds[row],
                    payload_starts[row],
                    payload_counts[row],
                    payload_slots
                ));
            }
            continue;
        }

        let parent = parent as usize;
        if parent >= row_count {
            return Err(anyhow!(
                "parser HIR enum variant row {row} published enum owner {parent}, outside {row_count} readback rows"
            ));
        }
        if kinds[parent] != HIR_NODE_ENUM_ITEM || item_kinds[parent] != HIR_ITEM_KIND_ENUM {
            return Err(anyhow!(
                "parser HIR enum variant row {row} points at owner {parent} without an enum item record"
            ));
        }
        if kinds[row] != HIR_NODE_ITEM || item_kinds[row] != HIR_ITEM_KIND_ENUM_VARIANT {
            return Err(anyhow!(
                "parser HIR enum variant row {row} is not backed by a parser-owned enum-variant item record"
            ));
        }
        if item_file_ids[parent] != node_file_ids[parent]
            || item_file_ids[row] != node_file_ids[row]
            || item_file_ids[row] != item_file_ids[parent]
        {
            return Err(anyhow!(
                "parser HIR enum variant row {row} published item/file ids that do not match enum owner {parent}"
            ));
        }
        require_child_source(parent, row, "row")?;

        let ordinal = variant_ordinals[row];
        if ordinal == INVALID {
            return Err(anyhow!(
                "parser HIR enum variant row {row} omitted its source-order ordinal"
            ));
        }
        variant_ordinal_keys.push((parent, ordinal, row));

        let payload_count = payload_counts[row];
        if payload_count > HIR_VARIANT_PAYLOAD_SLOT_STRIDE {
            return Err(anyhow!(
                "parser HIR enum variant row {row} published {payload_count} payloads, exceeding {} flat payload slots",
                HIR_VARIANT_PAYLOAD_SLOT_STRIDE
            ));
        }

        if payload_count == 0 {
            if payload_starts[row] != INVALID
                || payload_slots.iter().any(|&payload| payload != INVALID)
            {
                return Err(anyhow!(
                    "parser HIR enum variant row {row} published payload slots without a payload count"
                ));
            }
            continue;
        }

        let first_payload = payload_slots[0];
        if payload_starts[row] != first_payload {
            return Err(anyhow!(
                "parser HIR enum variant row {row} payload start does not point at ordinal zero"
            ));
        }

        let mut previous_payload: Option<usize> = None;
        for slot in 0..slot_stride {
            let payload = payload_slots[slot];
            if slot >= payload_count as usize {
                if payload != INVALID {
                    return Err(anyhow!(
                        "parser HIR enum variant row {row} retained stale payload slot {slot}"
                    ));
                }
                continue;
            }

            if payload == INVALID || payload as usize >= row_count {
                return Err(anyhow!(
                    "parser HIR enum variant row {row} published payload count {payload_count} without an in-table payload type at ordinal {slot}"
                ));
            }
            let payload = payload as usize;
            if payload_owner[payload] != INVALID {
                return Err(anyhow!(
                    "parser HIR enum variant payload row {payload} appears in multiple variant payload slots"
                ));
            }
            payload_owner[payload] = row as u32;
            if kinds[payload] != HIR_NODE_TYPE || type_forms[payload] == HIR_TYPE_FORM_NONE {
                return Err(anyhow!(
                    "parser HIR enum variant payload row {payload} is not a concrete type record"
                ));
            }
            if type_file_ids[payload] != node_file_ids[payload] {
                return Err(anyhow!(
                    "parser HIR enum variant payload row {payload} type/file id does not match its HIR row"
                ));
            }
            require_child_source(row, payload, "payload")?;
            if let Some(previous) = previous_payload {
                if token_pos[payload] <= token_pos[previous]
                    || token_end[previous] > token_pos[payload]
                {
                    return Err(anyhow!(
                        "parser HIR enum variant row {row} payload slots overlap or are not in source order"
                    ));
                }
            }
            previous_payload = Some(payload);
        }
    }

    variant_ordinal_keys.sort_unstable();
    let mut current_owner = INVALID as usize;
    let mut expected_ordinal = 0u32;
    for (owner, ordinal, row) in variant_ordinal_keys {
        if owner != current_owner {
            current_owner = owner;
            expected_ordinal = 0;
        }
        if ordinal != expected_ordinal {
            return Err(anyhow!(
                "parser HIR enum row {owner} variant ordinals are not contiguous from zero at row {row}"
            ));
        }
        expected_ordinal += 1;
    }

    Ok(())
}

/// Validates semantic HIR parent, sibling, depth, and child-index records.
pub fn validate_hir_semantic_tree_records(
    kinds: &[u32],
    parse_subtree_end: &[u32],
    semantic_prefix_before_node: &[u32],
    semantic_dense_node: &[u32],
    semantic_subtree_end: &[u32],
    semantic_parent: &[u32],
    semantic_first_child: &[u32],
    semantic_next_sibling: &[u32],
    semantic_depth: &[u32],
    semantic_child_index: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if parse_subtree_end.len() != row_count
        || semantic_prefix_before_node.len() != row_count
        || semantic_dense_node.len() != row_count
        || semantic_subtree_end.len() != row_count
        || semantic_parent.len() != row_count
        || semantic_first_child.len() != row_count
        || semantic_next_sibling.len() != row_count
        || semantic_depth.len() != row_count
        || semantic_child_index.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR semantic-tree record arrays have inconsistent lengths"
        ));
    }

    let semantic_count = kinds.iter().filter(|&&kind| kind != HIR_NODE_NONE).count();
    let mut expected_prefix = 0usize;
    for (node, &kind) in kinds.iter().enumerate() {
        let published_prefix = semantic_prefix_before_node[node] as usize;
        if published_prefix != expected_prefix {
            let start = node.saturating_sub(4);
            let end = (node + 5).min(row_count);
            return Err(anyhow!(
                "parser HIR semantic-tree node {node} published prefix {published_prefix}, expected {expected_prefix}; kinds[{start}..{end}]={:?}; semantic_prefix[{start}..{end}]={:?}; dense_prefix={:?}",
                &kinds[start..end],
                &semantic_prefix_before_node[start..end],
                &semantic_dense_node[..semantic_count.min(8)]
            ));
        }
        if kind == HIR_NODE_NONE {
            continue;
        }
        if expected_prefix >= row_count {
            return Err(anyhow!(
                "parser HIR semantic-tree dense row {expected_prefix} exceeds {row_count} readback rows"
            ));
        }
        let dense_node = semantic_dense_node[expected_prefix];
        if dense_node as usize != node {
            return Err(anyhow!(
                "parser HIR semantic-tree dense row {expected_prefix} points at node {dense_node}, expected {node}"
            ));
        }
        expected_prefix += 1;
    }

    let mut next_child_index_by_parent = vec![0u32; semantic_count];
    let mut root_count = 0usize;
    let mut next_root_child_index = 0u32;
    for row in 0..semantic_count {
        let original_node = semantic_dense_node[row] as usize;
        if original_node >= row_count {
            return Err(anyhow!(
                "parser HIR semantic-tree row {row} published original node {original_node}, outside {row_count} readback rows"
            ));
        }
        if kinds[original_node] == HIR_NODE_NONE {
            return Err(anyhow!(
                "parser HIR semantic-tree row {row} points at non-semantic original node {original_node}"
            ));
        }
        if semantic_prefix_before_node[original_node] as usize != row {
            return Err(anyhow!(
                "parser HIR semantic-tree row {row} disagrees with original node {original_node} prefix {}",
                semantic_prefix_before_node[original_node]
            ));
        }

        let subtree_end = semantic_subtree_end[row] as usize;
        if subtree_end <= row || subtree_end > semantic_count {
            return Err(anyhow!(
                "parser HIR semantic-tree row {row} published subtree end {subtree_end}, outside row range"
            ));
        }
        let original_end = parse_subtree_end[original_node] as usize;
        if original_end > row_count {
            return Err(anyhow!(
                "parser HIR semantic-tree row {row} original node {original_node} published parse subtree end {original_end}, outside {row_count} readback rows"
            ));
        }
        let expected_subtree_end = if original_end == row_count {
            semantic_count
        } else {
            semantic_prefix_before_node[original_end] as usize
        }
        .max(row + 1);
        if subtree_end != expected_subtree_end {
            return Err(anyhow!(
                "parser HIR semantic-tree row {row} published subtree end {subtree_end}, expected {expected_subtree_end}"
            ));
        }

        let parent = semantic_parent[row];
        if parent == INVALID {
            root_count += 1;
            if semantic_depth[row] != 0 {
                return Err(anyhow!(
                    "parser HIR semantic-tree root row {row} published depth {}",
                    semantic_depth[row]
                ));
            }
            if semantic_child_index[row] != next_root_child_index {
                return Err(anyhow!(
                    "parser HIR semantic-tree root row {row} published child index {}, expected {next_root_child_index}",
                    semantic_child_index[row]
                ));
            }
            next_root_child_index = next_root_child_index.saturating_add(1);
        } else {
            let parent = parent as usize;
            if parent >= semantic_count {
                return Err(anyhow!(
                    "parser HIR semantic-tree row {row} published parent {parent}, outside {semantic_count} semantic rows"
                ));
            }
            if parent >= row {
                return Err(anyhow!(
                    "parser HIR semantic-tree row {row} published non-preorder parent {parent}"
                ));
            }
            if row >= semantic_subtree_end[parent] as usize {
                return Err(anyhow!(
                    "parser HIR semantic-tree row {row} published parent {parent} whose subtree ends at {}",
                    semantic_subtree_end[parent]
                ));
            }
            let expected_depth = semantic_depth[parent].saturating_add(1);
            if semantic_depth[row] != expected_depth {
                return Err(anyhow!(
                    "parser HIR semantic-tree row {row} published depth {}, expected {expected_depth}",
                    semantic_depth[row]
                ));
            }
            let expected_child_index = next_child_index_by_parent[parent];
            if semantic_child_index[row] != expected_child_index {
                return Err(anyhow!(
                    "parser HIR semantic-tree row {row} published child index {}, expected {expected_child_index}",
                    semantic_child_index[row]
                ));
            }
            next_child_index_by_parent[parent] = expected_child_index.saturating_add(1);
        }

        let expected_first_child =
            if row + 1 < semantic_count && semantic_parent[row + 1] == row as u32 {
                (row + 1) as u32
            } else {
                INVALID
            };
        if semantic_first_child[row] != expected_first_child {
            return Err(anyhow!(
                "parser HIR semantic-tree row {row} published first child {}, expected {expected_first_child}",
                semantic_first_child[row]
            ));
        }

        let expected_next_sibling = if subtree_end < semantic_count
            && semantic_parent[subtree_end] == semantic_parent[row]
        {
            subtree_end as u32
        } else {
            INVALID
        };
        if semantic_next_sibling[row] != expected_next_sibling {
            return Err(anyhow!(
                "parser HIR semantic-tree row {row} published next sibling {}, expected {expected_next_sibling}",
                semantic_next_sibling[row]
            ));
        }
    }

    if semantic_count > 0 && root_count == 0 {
        return Err(anyhow!(
            "parser HIR semantic-tree published semantic rows without a root"
        ));
    }

    Ok(())
}

/// Validates parser-owned type argument owner/count/next chains.
pub fn validate_hir_type_argument_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    starts: &[u32],
    counts: &[u32],
    next_args: &[u32],
) -> Result<()> {
    let row_count = counts.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || type_forms.len() != row_count
        || starts.len() != row_count
        || next_args.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR type argument record arrays have inconsistent lengths"
        ));
    }

    let total_claimed_args = counts.iter().try_fold(0usize, |acc, &count| {
        acc.checked_add(count as usize)
            .ok_or_else(|| anyhow!("parser HIR type argument counts overflowed host usize"))
    })?;
    if total_claimed_args > row_count {
        return Err(anyhow!(
            "parser HIR type argument owner rows claim {total_claimed_args} type argument rows, exceeding {row_count} readback rows"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let mut argument_owner = vec![INVALID; row_count];
    for (owner, &count) in counts.iter().enumerate() {
        if count == 0 {
            if starts[owner] != INVALID {
                return Err(anyhow!(
                    "parser HIR type argument owner row {owner} published a first argument without an argument count"
                ));
            }
            continue;
        }
        if kinds[owner] != HIR_NODE_TYPE {
            return Err(anyhow!(
                "parser HIR type argument owner row {owner} is not a type HIR row"
            ));
        }
        if type_forms[owner] != HIR_TYPE_FORM_PATH {
            return Err(anyhow!(
                "parser HIR type argument owner row {owner} published generic arguments on a non-path type record"
            ));
        }
        if !has_non_empty_span(owner) || node_file_ids[owner] == INVALID {
            return Err(anyhow!(
                "parser HIR type argument owner row {owner} published generic arguments without a source-addressable owner span"
            ));
        }
        if count as usize > row_count {
            return Err(anyhow!(
                "parser HIR type argument owner row {owner} published {count} arguments, exceeding {row_count} readback rows"
            ));
        }

        let start = starts[owner];
        if start == INVALID || start as usize >= row_count {
            return Err(anyhow!(
                "parser HIR type argument owner row {owner} published argument count {count} without an in-table first argument"
            ));
        }

        let mut arg = start as usize;
        let mut previous_arg = None;
        for expected_ordinal in 0..count as usize {
            if arg == owner {
                return Err(anyhow!(
                    "parser HIR type argument owner row {owner} points at itself as an argument"
                ));
            }
            if kinds[arg] != HIR_NODE_TYPE {
                return Err(anyhow!(
                    "parser HIR type argument row {arg} is not a type HIR row"
                ));
            }
            if type_forms[arg] == HIR_TYPE_FORM_NONE {
                return Err(anyhow!(
                    "parser HIR type argument row {arg} has no concrete type record"
                ));
            }
            if !has_non_empty_span(arg) {
                return Err(anyhow!(
                    "parser HIR type argument row {arg} has no source-addressable argument span"
                ));
            }
            if node_file_ids[arg] != node_file_ids[owner] {
                return Err(anyhow!(
                    "parser HIR type argument row {arg} has a different file id than owner row {owner}"
                ));
            }
            if token_pos[arg] < token_pos[owner] || token_end[arg] > token_end[owner] {
                return Err(anyhow!(
                    "parser HIR type argument row {arg} is outside owner row {owner}'s source span"
                ));
            }
            if let Some(previous_arg) = previous_arg {
                if token_pos[arg] <= token_pos[previous_arg]
                    || token_end[previous_arg] > token_pos[arg]
                {
                    return Err(anyhow!(
                        "parser HIR type argument owner row {owner} published argument row {arg} out of source order"
                    ));
                }
            }
            let previous_owner = argument_owner[arg];
            if previous_owner != INVALID {
                return Err(anyhow!(
                    "parser HIR type argument row {arg} appears in multiple owner chains"
                ));
            }
            argument_owner[arg] = owner as u32;
            previous_arg = Some(arg);

            let next = next_args[arg];
            if expected_ordinal + 1 == count as usize {
                if next != INVALID {
                    return Err(anyhow!(
                        "parser HIR type argument owner row {owner} final argument row {arg} did not terminate the argument chain"
                    ));
                }
            } else {
                if next == INVALID || next as usize >= row_count {
                    return Err(anyhow!(
                        "parser HIR type argument owner row {owner} argument chain ended before count {count}"
                    ));
                }
                arg = next as usize;
            }
        }
    }

    for (arg, &next) in next_args.iter().enumerate() {
        if next == INVALID {
            continue;
        }
        if next as usize >= row_count {
            return Err(anyhow!(
                "parser HIR type argument row {arg} published next argument {next}, outside {row_count} readback rows"
            ));
        }
        let owner = argument_owner[arg];
        if owner == INVALID {
            return Err(anyhow!(
                "parser HIR type argument row {arg} published a next argument without belonging to an owner chain"
            ));
        }
        if argument_owner[next as usize] != owner {
            return Err(anyhow!(
                "parser HIR type argument row {arg} published a next argument outside its owner chain"
            ));
        }
    }

    Ok(())
}

/// Validates function parameter owner, ordinal, name, and type records.
pub fn validate_hir_parameter_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    type_file_ids: &[u32],
    owner_fn_nodes: &[u32],
    ordinals: &[u32],
    name_tokens: &[u32],
    record_nodes: &[u32],
    type_nodes: &[u32],
) -> Result<()> {
    let row_count = owner_fn_nodes.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || type_forms.len() != row_count
        || type_file_ids.len() != row_count
        || ordinals.len() != row_count
        || name_tokens.len() != row_count
        || record_nodes.len() != row_count
        || type_nodes.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR parameter record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let mut owner_param_counts = vec![0u32; row_count];
    let mut ordinal_keys = Vec::new();
    for (param_node, &owner) in owner_fn_nodes.iter().enumerate() {
        if owner == INVALID {
            if ordinals[param_node] != INVALID
                || name_tokens[param_node] != INVALID
                || record_nodes[param_node] != INVALID
                || type_nodes[param_node] != INVALID
            {
                return Err(anyhow!(
                    "parser HIR parameter row {param_node} published parameter metadata without an owner function"
                ));
            }
            if kinds[param_node] == HIR_NODE_PARAM {
                return Err(anyhow!(
                    "parser HIR parameter row {param_node} has a parameter HIR kind but no parser-owned parameter record"
                ));
            }
            continue;
        }

        let owner = owner as usize;
        if owner >= row_count {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} published owner function {owner}, outside {row_count} readback rows"
            ));
        }
        if kinds[owner] != HIR_NODE_FN {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} points at owner {owner} without a function HIR row"
            ));
        }
        if kinds[param_node] != HIR_NODE_PARAM {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} published parameter metadata on HIR kind {}",
                kinds[param_node]
            ));
        }
        if record_nodes[param_node] != param_node as u32 {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} did not self-identify its parser-owned record node"
            ));
        }
        if !has_non_empty_span(owner) || node_file_ids[owner] == INVALID {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} points at a function owner without a source-addressable span"
            ));
        }
        if !has_non_empty_span(param_node) || node_file_ids[param_node] == INVALID {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} lacks a source-addressable parameter span"
            ));
        }
        if node_file_ids[param_node] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} published a different file id than owner function {owner}"
            ));
        }
        if token_pos[param_node] < token_pos[owner] || token_end[param_node] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} falls outside owner function {owner} span"
            ));
        }

        let name_token = name_tokens[param_node];
        if name_token == INVALID
            || name_token < token_pos[param_node]
            || name_token >= token_end[param_node]
        {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} published a name token outside its parameter span"
            ));
        }

        let ordinal = ordinals[param_node];
        if ordinal == INVALID {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} published no source-order ordinal"
            ));
        }
        owner_param_counts[owner] = owner_param_counts[owner].checked_add(1).ok_or_else(|| {
            anyhow!("parser HIR parameter counts overflowed host validation state")
        })?;
        ordinal_keys.push((owner, ordinal, param_node));

        let type_node = type_nodes[param_node];
        if type_node == INVALID {
            continue;
        }
        if type_node as usize >= row_count || type_node as usize == param_node {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} published no in-table type edge"
            ));
        }
        let type_node = type_node as usize;
        if kinds[type_node] != HIR_NODE_TYPE || type_forms[type_node] == HIR_TYPE_FORM_NONE {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} points at row {type_node} without a concrete type record"
            ));
        }
        if !has_non_empty_span(type_node) {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} points at type row {type_node} without a non-empty token span"
            ));
        }
        if node_file_ids[type_node] != node_file_ids[param_node]
            || type_file_ids[type_node] != node_file_ids[param_node]
        {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} points at type row {type_node} with a different file id"
            ));
        }
        if token_pos[type_node] < token_pos[param_node]
            || token_end[type_node] > token_end[param_node]
        {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} points at type row {type_node} outside its parameter span"
            ));
        }
    }

    ordinal_keys.sort_unstable();
    let mut index = 0usize;
    while index < ordinal_keys.len() {
        let owner = ordinal_keys[index].0;
        let count = owner_param_counts[owner];
        for expected_ordinal in 0..count {
            if index >= ordinal_keys.len() || ordinal_keys[index].0 != owner {
                return Err(anyhow!(
                    "parser HIR function row {owner} parameter ordinal table ended before count {count}"
                ));
            }
            let (key_owner, ordinal, param_node) = ordinal_keys[index];
            debug_assert_eq!(key_owner, owner);
            if ordinal != expected_ordinal {
                return Err(anyhow!(
                    "parser HIR function row {owner} parameter ordinals are not contiguous from zero"
                ));
            }
            if expected_ordinal > 0 {
                let previous_param_node = ordinal_keys[index - 1].2;
                if token_pos[param_node] <= token_pos[previous_param_node]
                    || token_end[previous_param_node] > token_pos[param_node]
                {
                    return Err(anyhow!(
                        "parser HIR function row {owner} parameter rows overlap or are not in source order"
                    ));
                }
            }
            index += 1;
        }
    }

    Ok(())
}

#[allow(clippy::too_many_arguments)]
/// Validates method owner, receiver, visibility, and signature records.
pub fn validate_hir_method_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    item_kinds: &[u32],
    item_name_tokens: &[u32],
    item_file_ids: &[u32],
    param_owner_fn_nodes: &[u32],
    param_ordinals: &[u32],
    param_name_tokens: &[u32],
    param_type_nodes: &[u32],
    method_owner_nodes: &[u32],
    method_impl_nodes: &[u32],
    method_name_tokens: &[u32],
    method_first_param_tokens: &[u32],
    method_receiver_modes: &[u32],
    method_visibilities: &[u32],
    method_signature_flags: &[u32],
    method_impl_receiver_type_nodes: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || item_kinds.len() != row_count
        || item_name_tokens.len() != row_count
        || item_file_ids.len() != row_count
        || param_owner_fn_nodes.len() != row_count
        || param_ordinals.len() != row_count
        || param_name_tokens.len() != row_count
        || param_type_nodes.len() != row_count
        || method_owner_nodes.len() != row_count
        || method_impl_nodes.len() != row_count
        || method_name_tokens.len() != row_count
        || method_first_param_tokens.len() != row_count
        || method_receiver_modes.len() != row_count
        || method_visibilities.len() != row_count
        || method_signature_flags.len() != row_count
        || method_impl_receiver_type_nodes.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR method record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };
    let valid_receiver_mode = |mode| {
        matches!(
            mode,
            HIR_METHOD_RECEIVER_NONE
                | HIR_METHOD_RECEIVER_SELF
                | HIR_METHOD_RECEIVER_REF_SELF
                | HIR_METHOD_RECEIVER_EXPLICIT
        )
    };
    let valid_visibility =
        |visibility| matches!(visibility, HIR_METHOD_VIS_PRIVATE | HIR_METHOD_VIS_PUBLIC);
    let signature_flag_mask = HIR_METHOD_SIGNATURE_HAS_GENERICS
        | HIR_METHOD_SIGNATURE_HAS_WHERE
        | HIR_METHOD_SIGNATURE_INHERENT_IMPL;

    let mut impl_file_ids = vec![INVALID; row_count];
    for method_node in 0..row_count {
        let owner_node = method_owner_nodes[method_node];
        let impl_node = method_impl_nodes[method_node];
        if owner_node == INVALID {
            if impl_node != INVALID
                || method_name_tokens[method_node] != INVALID
                || method_first_param_tokens[method_node] != INVALID
                || method_receiver_modes[method_node] != HIR_METHOD_RECEIVER_NONE
                || method_visibilities[method_node] != HIR_METHOD_VIS_PRIVATE
                || method_signature_flags[method_node] != 0
            {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published method metadata without a declaration owner"
                ));
            }
            continue;
        }

        let owner_node = owner_node as usize;
        if owner_node >= row_count {
            return Err(anyhow!(
                "parser HIR method row {method_node} published owner {owner_node}, outside {row_count} readback rows"
            ));
        }
        if kinds[method_node] != HIR_NODE_FN {
            return Err(anyhow!(
                "parser HIR method row {method_node} published an owner without a function-signature HIR row"
            ));
        }
        if !has_non_empty_span(method_node) || node_file_ids[method_node] == INVALID {
            return Err(anyhow!(
                "parser HIR method row {method_node} published an owner without a source-addressable function row"
            ));
        }
        if !has_non_empty_span(owner_node)
            || node_file_ids[owner_node] == INVALID
            || node_file_ids[owner_node] != node_file_ids[method_node]
        {
            return Err(anyhow!(
                "parser HIR method row {method_node} published owner {owner_node} without a matching source-addressable owner row"
            ));
        }
        if token_pos[method_node] < token_pos[owner_node]
            || token_end[method_node] > token_end[owner_node]
        {
            return Err(anyhow!(
                "parser HIR method row {method_node} falls outside declaration owner span {owner_node}"
            ));
        }

        let impl_method = impl_node != INVALID;
        if impl_method {
            if impl_node as usize != owner_node {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published impl owner {impl_node} that does not match declaration owner {owner_node}"
                ));
            }
            if item_kinds[method_node] != HIR_ITEM_KIND_NONE {
                return Err(anyhow!(
                    "parser HIR impl method row {method_node} published value item metadata"
                ));
            }
            if item_name_tokens[method_node] != INVALID {
                return Err(anyhow!(
                    "parser HIR impl method row {method_node} published a value item name token"
                ));
            }
        } else {
            if item_kinds[owner_node] != HIR_ITEM_KIND_TRAIT {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published non-impl owner {owner_node} without a trait item row"
                ));
            }
            if item_kinds[method_node] != HIR_ITEM_KIND_NONE {
                return Err(anyhow!(
                    "parser HIR trait method row {method_node} should not publish a value item row"
                ));
            }
        }

        let name_token = method_name_tokens[method_node];
        if name_token == INVALID
            || name_token < token_pos[method_node]
            || name_token >= token_end[method_node]
        {
            return Err(anyhow!(
                "parser HIR method row {method_node} published a method name token outside its function span"
            ));
        }
        if name_token <= token_pos[method_node] {
            return Err(anyhow!(
                "parser HIR method row {method_node} published a method name token that does not follow its function declaration token"
            ));
        }

        let receiver_mode = method_receiver_modes[method_node];
        if !valid_receiver_mode(receiver_mode) {
            return Err(anyhow!(
                "parser HIR method row {method_node} published unknown receiver mode {receiver_mode}"
            ));
        }
        let visibility = method_visibilities[method_node];
        if !valid_visibility(visibility) {
            return Err(anyhow!(
                "parser HIR method row {method_node} published unknown visibility {visibility}"
            ));
        }
        let flags = method_signature_flags[method_node];
        if flags & !signature_flag_mask != 0 {
            return Err(anyhow!(
                "parser HIR method row {method_node} published unknown signature flags {flags}"
            ));
        }

        let first_param_token = method_first_param_tokens[method_node];
        if first_param_token == INVALID {
            if receiver_mode != HIR_METHOD_RECEIVER_NONE {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published receiver mode {receiver_mode} without a first parameter token"
                ));
            }
        } else {
            if first_param_token < token_pos[method_node]
                || first_param_token >= token_end[method_node]
            {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published a first parameter token outside its function span"
                ));
            }
            if first_param_token <= name_token {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published a first parameter token that does not follow its method name token"
                ));
            }
            let ordinal_zero_param =
                param_owner_fn_nodes
                    .iter()
                    .enumerate()
                    .find_map(|(param_node, &owner)| {
                        (owner as usize == method_node
                            && param_ordinals[param_node] == 0
                            && param_name_tokens[param_node] == first_param_token
                            && kinds[param_node] == HIR_NODE_PARAM)
                            .then_some(param_node)
                    });
            let Some(ordinal_zero_param) = ordinal_zero_param else {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published a first parameter token without an ordinal-zero parameter row"
                ));
            };
            if !has_non_empty_span(ordinal_zero_param)
                || node_file_ids[ordinal_zero_param] == INVALID
            {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published ordinal-zero parameter row {ordinal_zero_param} without a source-addressable parameter span"
                ));
            }
            if node_file_ids[ordinal_zero_param] != node_file_ids[method_node] {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published ordinal-zero parameter row {ordinal_zero_param} with a different file id"
                ));
            }
            if token_pos[ordinal_zero_param] < token_pos[method_node]
                || token_end[ordinal_zero_param] > token_end[method_node]
            {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published ordinal-zero parameter row {ordinal_zero_param} outside its function span"
                ));
            }
            if first_param_token < token_pos[ordinal_zero_param]
                || first_param_token >= token_end[ordinal_zero_param]
            {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published a first parameter token outside the ordinal-zero parameter span"
                ));
            }
            if receiver_mode == HIR_METHOD_RECEIVER_EXPLICIT {
                let param_type_node = param_type_nodes[ordinal_zero_param];
                if param_type_node == INVALID
                    || param_type_node as usize >= row_count
                    || kinds[param_type_node as usize] != HIR_NODE_TYPE
                {
                    return Err(anyhow!(
                        "parser HIR method row {method_node} published an explicit first parameter without a parser-owned type record"
                    ));
                }
                let param_type_node = param_type_node as usize;
                if !has_non_empty_span(param_type_node)
                    || node_file_ids[param_type_node] != node_file_ids[ordinal_zero_param]
                    || token_pos[param_type_node] < token_pos[ordinal_zero_param]
                    || token_end[param_type_node] > token_end[ordinal_zero_param]
                {
                    return Err(anyhow!(
                        "parser HIR method row {method_node} published explicit first parameter type row {param_type_node} without source-addressed ownership by ordinal-zero parameter row {ordinal_zero_param}"
                    ));
                }
            }
        }

        if impl_method {
            let previous_file_id = impl_file_ids[owner_node];
            if previous_file_id != INVALID && previous_file_id != node_file_ids[method_node] {
                return Err(anyhow!(
                    "parser HIR method impl owner {owner_node} was shared across source-pack files"
                ));
            }
            impl_file_ids[owner_node] = node_file_ids[method_node];
        }
    }

    for (impl_node, &receiver_type_node) in method_impl_receiver_type_nodes.iter().enumerate() {
        if receiver_type_node == INVALID {
            continue;
        }
        if !has_non_empty_span(impl_node) || node_file_ids[impl_node] == INVALID {
            return Err(anyhow!(
                "parser HIR method impl row {impl_node} published a receiver type without a source-addressable impl owner row"
            ));
        }
        let receiver_type_node = receiver_type_node as usize;
        if receiver_type_node >= row_count {
            return Err(anyhow!(
                "parser HIR method impl row {impl_node} published receiver type {receiver_type_node}, outside {row_count} readback rows"
            ));
        }
        if kinds[receiver_type_node] != HIR_NODE_TYPE {
            return Err(anyhow!(
                "parser HIR method impl row {impl_node} published receiver type row {receiver_type_node} without a type HIR row"
            ));
        }
        if !has_non_empty_span(receiver_type_node) || node_file_ids[receiver_type_node] == INVALID {
            return Err(anyhow!(
                "parser HIR method impl row {impl_node} published receiver type row {receiver_type_node} without a source-addressable type span"
            ));
        }
        if node_file_ids[receiver_type_node] != node_file_ids[impl_node] {
            return Err(anyhow!(
                "parser HIR method impl row {impl_node} published receiver type row {receiver_type_node} with a different file id"
            ));
        }
        if token_pos[receiver_type_node] < token_pos[impl_node] {
            return Err(anyhow!(
                "parser HIR method impl row {impl_node} published receiver type row {receiver_type_node} before the impl owner span"
            ));
        }
        if token_end[receiver_type_node] > token_end[impl_node] {
            return Err(anyhow!(
                "parser HIR method impl row {impl_node} published receiver type row {receiver_type_node} outside the impl owner span"
            ));
        }
        let impl_file_id = impl_file_ids[impl_node];
        if impl_file_id != INVALID && node_file_ids[receiver_type_node] != impl_file_id {
            return Err(anyhow!(
                "parser HIR method impl row {impl_node} published receiver type row {receiver_type_node} with a different file id"
            ));
        }
    }

    Ok(())
}
