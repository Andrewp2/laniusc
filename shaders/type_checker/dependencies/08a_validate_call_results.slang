// Validate direct dependency-call results against the enclosing function's
// authoritative return type. Compound children are published into the same
// prefix-scanned comparison relation used for dependency-call arguments.

import gpu_index;
import status;

struct Params
{
    uint declaration_count;
    uint import_capacity;
    uint visible_capacity;
    uint lookup_capacity;
    uint source_len;
    uint path_capacity;
    uint namespace;
    uint hir_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_subtree_end;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> call_dependency_decl;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_instance_external_canonical;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> dependency_counts;
StructuredBuffer<uint> dependency_type_words;
StructuredBuffer<uint> canonical_type_roots;
StructuredBuffer<uint> canonical_type_subtree_start;
StructuredBuffer<uint> type_semantic_row_by_token;
StructuredBuffer<uint> type_semantic_scan_input;
StructuredBuffer<uint> type_semantic_prefix;
StructuredBuffer<uint> type_semantic_count_out;
StructuredBuffer<uint> call_generic_claim_count_out;
StructuredBuffer<uint> call_generic_claim_callee;
StructuredBuffer<uint> call_generic_claim_slot;
StructuredBuffer<uint> call_generic_claim_type;
StructuredBuffer<uint> call_generic_claim_ref_tag;
StructuredBuffer<uint> call_generic_claim_ref_payload;
StructuredBuffer<uint> call_generic_claim_order;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;
RWStructuredBuffer<uint> aggregate_compare_scan_input;
RWStructuredBuffer<uint> aggregate_compare_expected_instance;
RWStructuredBuffer<uint> aggregate_compare_actual_instance;
RWStructuredBuffer<uint> aggregate_compare_error_token;
RWStructuredBuffer<uint> aggregate_compare_error_detail;
RWStructuredBuffer<uint> dependency_call_compare_scan_input;
RWStructuredBuffer<uint> dependency_call_compare_expected_type;
RWStructuredBuffer<uint> dependency_call_compare_actual_instance;
RWStructuredBuffer<uint> dependency_call_compare_error_token;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_WORDS = 9u;
static const uint STMT_WORDS = 4u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint HIR_CALL_EXPR = 19u;
static const uint INTERFACE_TYPE_GENERIC_PARAMETER = 2u;
static const uint INTERFACE_TYPE_DECLARATION = 3u;
static const uint INTERFACE_TYPE_ARRAY = 4u;
static const uint INTERFACE_TYPE_SLICE = 5u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint GENERIC_CLAIM_CAPACITY_MULTIPLIER = 32u;

uint active_hir_count()
{
    return gParams.hir_capacity == 0u ? 0u : min(gParams.hir_capacity, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.visible_capacity;
}

bool canonical_nominal_matches(uint expected_type_i, uint actual_type_i)
{
    uint type_count = dependency_counts[4u];
    if (expected_type_i >= type_count || actual_type_i >= type_count)
        return false;
    uint expected = canonical_type_roots[expected_type_i];
    uint actual = canonical_type_roots[actual_type_i];
    uint expected_base = expected * TYPE_WORDS;
    uint actual_base = actual * TYPE_WORDS;
    return dependency_type_words[expected_base] == INTERFACE_TYPE_DECLARATION &&
           dependency_type_words[actual_base] == INTERFACE_TYPE_DECLARATION &&
           dependency_type_words[expected_base + 1u] == dependency_type_words[actual_base + 1u] &&
           dependency_type_words[expected_base + 2u] == dependency_type_words[actual_base + 2u] &&
           dependency_type_words[expected_base + 8u] == dependency_type_words[actual_base + 8u];
}

uint canonical_subtree_count(uint root)
{
    uint type_count = dependency_counts[4u];
    if (root >= type_count)
        return INVALID;
    uint start = canonical_type_subtree_start[root];
    return start <= root ? root - start + 1u : INVALID;
}

uint local_type_subtree_count(uint instance)
{
    if (!valid_token(instance))
        return INVALID;
    uint root = type_semantic_row_by_token[instance];
    uint semantic_count = min(hir_semantic_count[0u], active_hir_count());
    if (root >= semantic_count || type_semantic_scan_input[root] == 0u)
        return INVALID;
    uint end = hir_semantic_subtree_end[root];
    if (end <= root || end > semantic_count)
        return INVALID;
    uint begin_ordinal = type_semantic_prefix[root];
    uint end_ordinal = end == semantic_count
        ? type_semantic_count_out[0u]
        : type_semantic_prefix[end];
    return end_ordinal > begin_ordinal ? end_ordinal - begin_ordinal : INVALID;
}

void mismatch(uint token)
{
    record_min_token_error(status, valid_token(token) ? token : 0u, ERR_ASSIGN_MISMATCH, 0u);
}

uint generic_claim_capacity()
{
    uint base = max(gParams.visible_capacity, gParams.hir_capacity);
    return base > 0xffffffffu / GENERIC_CLAIM_CAPACITY_MULTIPLIER
        ? 0xffffffffu
        : base * GENERIC_CLAIM_CAPACITY_MULTIPLIER;
}

bool claim_key_less(uint row, uint callee, uint slot)
{
    uint row_callee = call_generic_claim_callee[row];
    return row_callee < callee ||
        (row_callee == callee && call_generic_claim_slot[row] < slot);
}

void substitute_direct_generic_call(uint call_node)
{
    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node))
        return;
    uint callee_token = hir_token_pos[callee_node];
    if (!valid_token(callee_token) || call_dependency_decl[callee_token] == INVALID ||
        decl_type_ref_tag[callee_token] != TYPE_REF_EXTERNAL_CANONICAL)
        return;
    uint return_i = decl_type_ref_payload[callee_token];
    uint type_count = dependency_counts[4u];
    if (return_i >= type_count)
        return;
    uint return_root = canonical_type_roots[return_i];
    uint return_base = return_root * TYPE_WORDS;
    if (dependency_type_words[return_base] != INTERFACE_TYPE_GENERIC_PARAMETER)
        return;
    uint slot = dependency_type_words[return_base + 1u];
    uint count = min(call_generic_claim_count_out[0u], generic_claim_capacity());
    uint lo = 0u;
    uint hi = count;
    for (uint step = 0u; step < 32u; step += 1u)
    {
        if (lo >= hi)
            break;
        uint mid = lo + ((hi - lo) >> 1u);
        uint row = call_generic_claim_order[mid];
        if (row >= count || !claim_key_less(row, callee_token, slot))
            hi = mid;
        else
            lo = mid + 1u;
    }
    if (lo >= count)
        return;
    uint row = call_generic_claim_order[lo];
    if (row >= count || call_generic_claim_callee[row] != callee_token ||
        call_generic_claim_slot[row] != slot)
        return;
    uint inferred = call_generic_claim_type[row];
    uint inferred_tag = call_generic_claim_ref_tag[row];
    uint inferred_payload = call_generic_claim_ref_payload[row];
    if (inferred == 0u && inferred_tag == 0u)
        return;
    call_return_type[callee_token] = inferred_tag == TYPE_REF_INSTANCE ? 0u : inferred;
    if (inferred_tag != 0u)
    {
        call_return_type_token[callee_token] = callee_token;
        decl_type_ref_tag[callee_token] = inferred_tag;
        decl_type_ref_payload[callee_token] = inferred_payload;
    }
    else
    {
        call_return_type_token[callee_token] = INVALID;
        decl_type_ref_tag[callee_token] = TYPE_REF_SCALAR;
        decl_type_ref_payload[callee_token] = inferred;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (valid_node(node) && hir_kind[node] == HIR_CALL_EXPR)
    {
        substitute_direct_generic_call(node);
        return;
    }
    if (!valid_node(node) || hir_stmt_record[node * STMT_WORDS] != STMT_RECORD_KIND_RETURN)
        return;
    uint expr = hir_stmt_record[node * STMT_WORDS + 1u];
    if (!valid_node(expr))
        return;
    uint root = hir_expr_result_root_node[expr];
    if (!valid_node(root))
        root = expr;
    if (hir_kind[root] != HIR_CALL_EXPR)
        return;
    uint callee_node = hir_call_callee_node[root];
    if (!valid_node(callee_node))
        return;
    uint callee_token = hir_token_pos[callee_node];
    if (!valid_token(callee_token) || call_dependency_decl[callee_token] == INVALID)
        return;
    uint actual_tag = decl_type_ref_tag[callee_token];
    uint actual_payload = decl_type_ref_payload[callee_token];
    uint return_token = hir_token_pos[node];
    uint encoded_fn = valid_token(return_token) ? enclosing_fn[return_token] : 0u;
    uint fn_token = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    if (!valid_token(fn_token))
        return;

    uint expected_tag = fn_return_ref_tag[fn_token];
    uint expected_payload = fn_return_ref_payload[fn_token];
    if (actual_tag == TYPE_REF_INSTANCE && valid_token(actual_payload))
    {
        if (expected_tag != TYPE_REF_INSTANCE || !valid_token(expected_payload))
        {
            mismatch(callee_token);
            return;
        }
        uint actual_nominal = type_instance_external_canonical[actual_payload];
        uint expected_nominal = type_instance_external_canonical[expected_payload];
        uint child_count = type_instance_arg_count[actual_payload];
        if (actual_nominal == INVALID || expected_nominal == INVALID ||
            !canonical_nominal_matches(actual_nominal, expected_nominal) ||
            child_count != type_instance_arg_count[expected_payload])
        {
            mismatch(callee_token);
            return;
        }
        if (child_count != 0u)
        {
            aggregate_compare_scan_input[node] = child_count;
            aggregate_compare_expected_instance[node] = expected_payload;
            aggregate_compare_actual_instance[node] = actual_payload;
            aggregate_compare_error_token[node] = callee_token;
            aggregate_compare_error_detail[node] = 0u;
        }
        return;
    }
    if (actual_tag != TYPE_REF_EXTERNAL_CANONICAL)
        return;

    uint actual_canonical = actual_payload;
    uint type_count = dependency_counts[4u];
    if (actual_canonical >= type_count)
    {
        mismatch(callee_token);
        return;
    }
    uint actual_root = canonical_type_roots[actual_canonical];
    uint actual_base = actual_root * TYPE_WORDS;
    // The same pass first substitutes call nodes and is dispatched again after
    // a storage barrier for return validation. A return lane may observe the
    // pre-substitution generic root during the first dispatch; defer it rather
    // than racing the call lane and recording a false mismatch.
    if (dependency_type_words[actual_base] == INTERFACE_TYPE_GENERIC_PARAMETER)
        return;
    uint actual_count = dependency_type_words[actual_base + 4u];
    if (expected_tag == TYPE_REF_EXTERNAL_CANONICAL)
    {
        uint expected_root = expected_payload < type_count
            ? canonical_type_roots[expected_payload]
            : INVALID;
        bool matches = expected_root != INVALID &&
            canonical_nominal_matches(actual_root, expected_root) &&
            dependency_type_words[expected_root * TYPE_WORDS + 4u] == actual_count;
        if (!matches || actual_count != 0u)
            mismatch(callee_token);
        return;
    }
    if (expected_tag != TYPE_REF_INSTANCE || !valid_token(expected_payload))
        return;
    uint actual_kind = dependency_type_words[actual_base];
    bool matches = false;
    if (actual_kind == INTERFACE_TYPE_DECLARATION)
    {
        uint expected_nominal = type_instance_external_canonical[expected_payload];
        matches = expected_nominal != INVALID &&
            canonical_nominal_matches(actual_root, expected_nominal) &&
            type_instance_arg_count[expected_payload] == actual_count;
    }
    else if (actual_kind == INTERFACE_TYPE_ARRAY || actual_kind == INTERFACE_TYPE_SLICE)
    {
        uint expected_kind = actual_kind == INTERFACE_TYPE_ARRAY
            ? TYPE_INSTANCE_ARRAY
            : TYPE_INSTANCE_SLICE;
        matches = type_instance_kind[expected_payload] == expected_kind && actual_count == 1u;
        if (matches && actual_kind == INTERFACE_TYPE_ARRAY)
            matches = type_instance_len_kind[expected_payload] ==
                          dependency_type_words[actual_base + 5u] &&
                      type_instance_len_payload[expected_payload] ==
                          dependency_type_words[actual_base + 6u];
    }
    if (!matches)
    {
        mismatch(callee_token);
        return;
    }
    if (actual_count != 0u)
    {
        uint actual_subtree_count = canonical_subtree_count(actual_root);
        uint expected_subtree_count = local_type_subtree_count(expected_payload);
        if (actual_subtree_count == INVALID || actual_subtree_count != expected_subtree_count)
        {
            mismatch(callee_token);
            return;
        }
        dependency_call_compare_scan_input[node] = actual_subtree_count;
        dependency_call_compare_expected_type[node] = actual_root;
        dependency_call_compare_actual_instance[node] = expected_payload;
        dependency_call_compare_error_token[node] = callee_token;
    }
}
