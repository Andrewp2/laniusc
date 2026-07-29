// Compare canonical dependency types with local parser-owned type trees as a
// flattened preorder relation. Canonical interface rows are reverse preorder,
// while local semantic HIR rows are preorder, so each lane maps the same
// relative ordinal from opposite ends. Pointer-jumped subtree starts make the
// span independent of nesting depth.

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
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> dependency_counts;
StructuredBuffer<uint> dependency_call_compare_scan_input;
StructuredBuffer<uint> dependency_call_compare_prefix;
StructuredBuffer<uint> dependency_call_compare_total;
StructuredBuffer<uint> dependency_call_compare_expected_type;
StructuredBuffer<uint> dependency_call_compare_actual_instance;
StructuredBuffer<uint> dependency_call_compare_error_token;
StructuredBuffer<uint> dependency_type_words;
StructuredBuffer<uint> canonical_type_roots;
StructuredBuffer<uint> canonical_type_subtree_start;
StructuredBuffer<uint> type_semantic_row_by_token;
StructuredBuffer<uint> type_semantic_prefix;
StructuredBuffer<uint> type_semantic_count_out;
StructuredBuffer<uint> type_semantic_row_by_ordinal;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_external_canonical;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> call_generic_claim_count_out;
StructuredBuffer<uint> call_generic_claim_callee;
StructuredBuffer<uint> call_generic_claim_slot;
StructuredBuffer<uint> call_generic_claim_ref_tag;
StructuredBuffer<uint> call_generic_claim_ref_payload;
StructuredBuffer<uint> call_generic_claim_order;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_WORDS = 9u;
static const uint INTERFACE_TYPE_SCALAR = 1u;
static const uint INTERFACE_TYPE_GENERIC_PARAMETER = 2u;
static const uint INTERFACE_TYPE_DECLARATION = 3u;
static const uint INTERFACE_TYPE_ARRAY = 4u;
static const uint INTERFACE_TYPE_SLICE = 5u;
static const uint INTERFACE_TYPE_REFERENCE = 6u;
static const uint HIR_TYPE_FORM_PATH = 1u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint HIR_TYPE_FORM_SLICE = 3u;
static const uint HIR_TYPE_FORM_REF = 4u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint GENERIC_CLAIM_CAPACITY_MULTIPLIER = 32u;

uint active_hir_count()
{
    return gParams.hir_capacity == 0u ? 0u : min(gParams.hir_capacity, hir_status[5u]);
}

uint saturating_add(uint lhs, uint rhs)
{
    return lhs > 0xffffffffu - rhs ? 0xffffffffu : lhs + rhs;
}

uint request_node_for_row(uint row)
{
    uint lo = 0u;
    uint hi = active_hir_count();
    for (uint step = 0u; step < 32u && lo < hi; step += 1u)
    {
        uint mid = lo + (hi - lo) / 2u;
        uint end = saturating_add(
            dependency_call_compare_prefix[mid],
            dependency_call_compare_scan_input[mid]);
        if (end <= row)
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo >= active_hir_count())
        return INVALID;
    uint begin = dependency_call_compare_prefix[lo];
    uint end = saturating_add(begin, dependency_call_compare_scan_input[lo]);
    return row >= begin && row < end ? lo : INVALID;
}

uint local_semantic_row(uint instance, uint relative_ordinal)
{
    if (instance >= gParams.visible_capacity)
        return INVALID;
    uint root = type_semantic_row_by_token[instance];
    uint semantic_count = min(hir_semantic_count[0u], active_hir_count());
    if (root >= semantic_count)
        return INVALID;
    uint ordinal = saturating_add(type_semantic_prefix[root], relative_ordinal);
    if (ordinal >= type_semantic_count_out[0u])
        return INVALID;
    uint row = type_semantic_row_by_ordinal[ordinal];
    return row < semantic_count ? row : INVALID;
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

bool local_nominal_matches(uint expected, uint tag, uint payload)
{
    if (tag == TYPE_REF_EXTERNAL_CANONICAL)
        return canonical_nominal_matches(expected, payload);
    if (tag != TYPE_REF_INSTANCE || payload >= gParams.visible_capacity ||
        type_instance_kind[payload] != TYPE_INSTANCE_NAMED)
        return false;
    uint canonical = type_instance_external_canonical[payload];
    return canonical != INVALID && canonical_nominal_matches(expected, canonical);
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

uint generic_claim_row(uint callee, uint slot)
{
    uint count = min(call_generic_claim_count_out[0u], generic_claim_capacity());
    uint lo = 0u;
    uint hi = count;
    for (uint step = 0u; step < 32u && lo < hi; step += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        uint row = call_generic_claim_order[mid];
        if (row >= count || !claim_key_less(row, callee, slot))
            hi = mid;
        else
            lo = mid + 1u;
    }
    if (lo >= count)
        return INVALID;
    uint row = call_generic_claim_order[lo];
    return row < count && call_generic_claim_callee[row] == callee &&
           call_generic_claim_slot[row] == slot
        ? row
        : INVALID;
}

bool generic_claim_matches(uint callee, uint slot, uint form, uint tag, uint payload)
{
    uint row = generic_claim_row(callee, slot);
    if (row == INVALID)
        return false;
    uint claim_tag = call_generic_claim_ref_tag[row];
    uint claim_payload = call_generic_claim_ref_payload[row];
    if (claim_tag == TYPE_REF_SCALAR)
        return form == HIR_TYPE_FORM_PATH && tag == TYPE_REF_SCALAR &&
               payload == claim_payload;
    if (claim_tag == TYPE_REF_EXTERNAL_CANONICAL)
        return form == HIR_TYPE_FORM_PATH &&
               local_nominal_matches(claim_payload, tag, payload);
    if (claim_tag != TYPE_REF_INSTANCE || claim_payload >= gParams.visible_capacity ||
        tag != TYPE_REF_INSTANCE || payload >= gParams.visible_capacity)
        return false;
    uint claim_kind = type_instance_kind[claim_payload];
    bool matches = claim_kind == type_instance_kind[payload] &&
                   type_instance_arg_count[claim_payload] == type_instance_arg_count[payload];
    if (matches && claim_kind == TYPE_INSTANCE_ARRAY)
        matches = type_instance_len_kind[claim_payload] == type_instance_len_kind[payload] &&
                  type_instance_len_payload[claim_payload] == type_instance_len_payload[payload];
    if (matches && claim_kind != TYPE_INSTANCE_ARRAY && claim_kind != TYPE_INSTANCE_SLICE)
    {
        uint claim_nominal = type_instance_external_canonical[claim_payload];
        uint local_nominal = type_instance_external_canonical[payload];
        matches = claim_nominal != INVALID && local_nominal != INVALID &&
                  canonical_nominal_matches(claim_nominal, local_nominal);
    }
    return matches;
}

bool node_matches(uint expected_row, uint local_row, uint callee)
{
    uint type_count = dependency_counts[4u];
    uint semantic_count = min(hir_semantic_count[0u], active_hir_count());
    if (expected_row >= type_count || local_row >= semantic_count)
        return false;
    uint expected = canonical_type_roots[expected_row];
    if (expected >= type_count)
        return false;
    uint local_node = hir_semantic_dense_node[local_row];
    if (local_node >= active_hir_count())
        return false;
    uint token = hir_token_pos[local_node];
    if (token >= gParams.visible_capacity)
        return false;
    uint base = expected * TYPE_WORDS;
    uint kind = dependency_type_words[base];
    uint edge_count = dependency_type_words[base + 4u];
    uint form = hir_type_form[local_node];
    uint tag = type_expr_ref_tag[token];
    uint payload = type_expr_ref_payload[token];
    if (kind == INTERFACE_TYPE_GENERIC_PARAMETER)
        return generic_claim_matches(
            callee,
            dependency_type_words[base + 1u],
            form,
            tag,
            payload);
    if (kind == INTERFACE_TYPE_SCALAR)
        return form == HIR_TYPE_FORM_PATH && tag == TYPE_REF_SCALAR &&
               payload == dependency_type_words[base + 1u] && edge_count == 0u;
    if (kind == INTERFACE_TYPE_DECLARATION)
    {
        if (tag == TYPE_REF_EXTERNAL_CANONICAL && payload < type_count &&
            canonical_type_roots[payload] == expected)
            return form == HIR_TYPE_FORM_PATH;
        uint actual_count = tag == TYPE_REF_INSTANCE && payload < gParams.visible_capacity
            ? type_instance_arg_count[payload]
            : 0u;
        return form == HIR_TYPE_FORM_PATH && local_nominal_matches(expected, tag, payload) &&
               actual_count == edge_count;
    }
    if (kind == INTERFACE_TYPE_REFERENCE)
        return form == HIR_TYPE_FORM_REF && edge_count == 1u;
    if (tag != TYPE_REF_INSTANCE || payload >= gParams.visible_capacity)
        return false;
    if (kind == INTERFACE_TYPE_ARRAY)
        return form == HIR_TYPE_FORM_ARRAY && type_instance_kind[payload] == TYPE_INSTANCE_ARRAY &&
               edge_count == 1u &&
               type_instance_len_kind[payload] == dependency_type_words[base + 5u] &&
               type_instance_len_payload[payload] == dependency_type_words[base + 6u];
    if (kind == INTERFACE_TYPE_SLICE)
        return form == HIR_TYPE_FORM_SLICE && type_instance_kind[payload] == TYPE_INSTANCE_SLICE &&
               edge_count == 1u;
    return false;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (row >= dependency_call_compare_total[0u])
        return;
    uint request = request_node_for_row(row);
    if (request == INVALID)
        return;
    uint expected_root = dependency_call_compare_expected_type[request];
    uint type_count = dependency_counts[4u];
    if (expected_root >= type_count)
        return;
    uint relative = row - dependency_call_compare_prefix[request];
    uint start = canonical_type_subtree_start[expected_root];
    uint expected = relative <= expected_root && expected_root - relative >= start
        ? expected_root - relative
        : INVALID;
    uint local_row = local_semantic_row(
        dependency_call_compare_actual_instance[request], relative);
    uint callee = dependency_call_compare_error_token[request];
    if (!node_matches(expected, local_row, callee))
        record_min_token_error(
            status,
            dependency_call_compare_error_token[request],
            ERR_ASSIGN_MISMATCH,
            0u);
}
