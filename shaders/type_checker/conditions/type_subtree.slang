// Compare recursively nested local type instances as one flattened preorder
// relation. The parser owns semantic preorder and subtree bounds; preceding
// scans compact only type nodes and expand comparison requests. Consequently
// every lane compares one corresponding type node with no depth walk or cap.

import gpu_index;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> aggregate_compare_count_out;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> type_subtree_compare_scan_input;
StructuredBuffer<uint> type_subtree_compare_prefix;
StructuredBuffer<uint> type_subtree_compare_count_out;
StructuredBuffer<uint> type_subtree_compare_left_root;
StructuredBuffer<uint> type_subtree_compare_right_root;
StructuredBuffer<uint> type_subtree_compare_error_token;
StructuredBuffer<uint> type_subtree_compare_error_detail;
StructuredBuffer<uint> type_semantic_prefix;
StructuredBuffer<uint> type_semantic_count_out;
StructuredBuffer<uint> type_semantic_row_by_ordinal;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_const_param_slot_by_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_external_canonical;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_LEN_LITERAL = 1u;
static const uint TYPE_LEN_CONST_PARAM = 2u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint saturating_add(uint lhs, uint rhs)
{
    return lhs > 0xffffffffu - rhs ? 0xffffffffu : lhs + rhs;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint active_request_count()
{
    return min(aggregate_compare_count_out[0u], gParams.n_hir_nodes);
}

uint request_for_compare_row(uint row)
{
    uint lo = 0u;
    uint hi = active_request_count();
    for (uint step = 0u; step < 32u && lo < hi; step += 1u)
    {
        uint mid = lo + (hi - lo) / 2u;
        uint end = saturating_add(
            type_subtree_compare_prefix[mid],
            type_subtree_compare_scan_input[mid]);
        if (end <= row)
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo >= active_request_count())
        return INVALID;
    uint begin = type_subtree_compare_prefix[lo];
    uint end = saturating_add(begin, type_subtree_compare_scan_input[lo]);
    return row >= begin && row < end ? lo : INVALID;
}

uint semantic_row_at(uint root, uint relative_ordinal)
{
    uint semantic_count = min(hir_semantic_count[0u], gParams.n_hir_nodes);
    if (root >= semantic_count)
        return INVALID;
    uint ordinal = saturating_add(type_semantic_prefix[root], relative_ordinal);
    if (ordinal >= type_semantic_count_out[0u])
        return INVALID;
    uint row = type_semantic_row_by_ordinal[ordinal];
    return row < semantic_count ? row : INVALID;
}

bool same_generic_slot(uint lhs, uint rhs, bool is_const)
{
    if (!valid_token(lhs) || !valid_token(rhs))
        return false;
    uint lhs_slot = is_const
        ? type_const_param_slot_by_token[lhs]
        : type_generic_param_slot_by_token[lhs];
    uint rhs_slot = is_const
        ? type_const_param_slot_by_token[rhs]
        : type_generic_param_slot_by_token[rhs];
    return lhs_slot != INVALID && lhs_slot == rhs_slot;
}

bool same_array_length(uint lhs_instance, uint rhs_instance)
{
    uint lhs_kind = type_instance_len_kind[lhs_instance];
    uint rhs_kind = type_instance_len_kind[rhs_instance];
    if (lhs_kind != rhs_kind)
        return false;
    uint lhs = type_instance_len_payload[lhs_instance];
    uint rhs = type_instance_len_payload[rhs_instance];
    if (lhs_kind == TYPE_LEN_CONST_PARAM)
        return same_generic_slot(lhs, rhs, true);
    return lhs_kind == TYPE_LEN_LITERAL && lhs == rhs;
}

bool same_named_identity(uint lhs_instance, uint rhs_instance)
{
    uint lhs_decl = type_instance_decl_token[lhs_instance];
    uint rhs_decl = type_instance_decl_token[rhs_instance];
    if (valid_token(lhs_decl) || valid_token(rhs_decl))
        return valid_token(lhs_decl) && lhs_decl == rhs_decl;
    uint lhs_external = type_instance_external_canonical[lhs_instance];
    uint rhs_external = type_instance_external_canonical[rhs_instance];
    return lhs_external != INVALID && lhs_external == rhs_external;
}

bool same_instance(uint lhs, uint rhs)
{
    if (lhs == rhs)
        return valid_token(lhs);
    if (!valid_token(lhs) || !valid_token(rhs))
        return false;
    uint lhs_kind = type_instance_kind[lhs];
    if (lhs_kind == 0u || lhs_kind != type_instance_kind[rhs])
        return false;
    if (lhs_kind == TYPE_INSTANCE_NAMED)
        return same_named_identity(lhs, rhs) &&
               type_instance_arg_count[lhs] == type_instance_arg_count[rhs];
    if (lhs_kind == TYPE_INSTANCE_ARRAY)
        return same_array_length(lhs, rhs);
    return lhs_kind == TYPE_INSTANCE_SLICE;
}

bool same_type_node(uint lhs_row, uint rhs_row)
{
    uint semantic_count = min(hir_semantic_count[0u], gParams.n_hir_nodes);
    if (lhs_row >= semantic_count || rhs_row >= semantic_count)
        return false;
    uint lhs_node = hir_semantic_dense_node[lhs_row];
    uint rhs_node = hir_semantic_dense_node[rhs_row];
    if (lhs_node >= gParams.n_hir_nodes || rhs_node >= gParams.n_hir_nodes ||
        hir_type_form[lhs_node] != hir_type_form[rhs_node])
        return false;
    uint lhs_token = hir_token_pos[lhs_node];
    uint rhs_token = hir_token_pos[rhs_node];
    if (!valid_token(lhs_token) || !valid_token(rhs_token))
        return false;
    uint lhs_tag = type_expr_ref_tag[lhs_token];
    uint rhs_tag = type_expr_ref_tag[rhs_token];
    if (lhs_tag == TYPE_REF_INVALID || lhs_tag != rhs_tag)
        return false;
    uint lhs_payload = type_expr_ref_payload[lhs_token];
    uint rhs_payload = type_expr_ref_payload[rhs_token];
    if (lhs_tag == TYPE_REF_GENERIC_PARAM)
        return same_generic_slot(lhs_payload, rhs_payload, false);
    if (lhs_tag == TYPE_REF_INSTANCE)
        return same_instance(lhs_payload, rhs_payload);
    return lhs_payload == rhs_payload;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (row >= type_subtree_compare_count_out[0u])
        return;
    uint request = request_for_compare_row(row);
    if (request == INVALID)
        return;
    uint relative = row - type_subtree_compare_prefix[request];
    uint lhs_row = semantic_row_at(type_subtree_compare_left_root[request], relative);
    uint rhs_row = semantic_row_at(type_subtree_compare_right_root[request], relative);
    if (!same_type_node(lhs_row, rhs_row))
    {
        record_min_token_error(
            status,
            type_subtree_compare_error_token[request],
            ERR_ASSIGN_MISMATCH,
            type_subtree_compare_error_detail[request]);
    }
}
