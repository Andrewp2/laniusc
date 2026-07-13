// Validate arbitrary-width top-level generic arguments in trait method
// signatures. The peer-root pass publishes impl-type -> trait-type relations;
// this pass assigns one invocation to every parser-owned type-argument row.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_type_arg_owner;
StructuredBuffer<uint> hir_type_arg_rank;
StructuredBuffer<uint> hir_type_root_owner;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_type_path_leaf_node;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> predicate_bound_first_arg_token;
StructuredBuffer<uint> predicate_bound_second_arg_token;

RWStructuredBuffer<uint> predicate_method_validation_owner_node;
RWStructuredBuffer<uint> predicate_method_validation_peer_node;
RWStructuredBuffer<uint> predicate_method_validation_status;
RWStructuredBuffer<uint> predicate_method_validation_detail_token;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_ERROR = 4u;
static const uint PREDICATE_ARG_TYPE_CODE_BIT = 0x80000000u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint PREDICATE_STATUS_OK = 0u;
static const uint PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH = 8u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0u], gParams.n_tokens);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

uint type_leaf_token(uint type_node)
{
    uint leaf = valid_node(type_node) ? hir_type_path_leaf_node[type_node] : INVALID;
    uint token = valid_node(leaf) ? hir_token_pos[leaf] : INVALID;
    return valid_token(token) ? token : INVALID;
}

uint arg_row(uint type_node, uint ordinal)
{
    uint token = type_leaf_token(type_node);
    uint start = valid_token(token) ? type_instance_arg_row_start[token] : INVALID;
    uint row = start == INVALID ? INVALID : start + ordinal;
    return row != INVALID && row < type_instance_arg_row_count_out[0u] ? row : INVALID;
}

uint decl_token_from_type_code(uint ty)
{
    if (ty >= TY_STRUCT_BASE && ty < TY_ENUM_BASE)
        return ty - TY_STRUCT_BASE;
    if (ty >= TY_ENUM_BASE && ty < TY_GENERIC_BASE)
        return ty - TY_ENUM_BASE;
    return INVALID;
}

uint nominal_payload(uint payload)
{
    if (!valid_token(payload))
        return payload;
    uint decl = type_instance_decl_token[payload];
    if (decl != INVALID)
        return decl;
    decl = decl_token_from_type_code(module_type_path_type[payload]);
    return decl != INVALID ? decl : payload;
}

bool ref_values_definitely_mismatch(
    uint left_tag,
    uint left_payload,
    uint right_tag,
    uint right_payload)
{
    if (left_tag == TYPE_REF_INVALID || right_tag == TYPE_REF_INVALID ||
        left_tag == TYPE_REF_GENERIC_PARAM || right_tag == TYPE_REF_GENERIC_PARAM)
        return false;
    if (left_tag != right_tag)
        return true;

    if (left_tag == TYPE_REF_INSTANCE)
    {
        left_payload = nominal_payload(left_payload);
        right_payload = nominal_payload(right_payload);
    }
    return left_payload != right_payload;
}

bool predicate_arg_ref(uint arg, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (arg != INVALID && (arg & PREDICATE_ARG_TYPE_CODE_BIT) != 0u)
    {
        tag = TYPE_REF_SCALAR;
        payload = arg & ~PREDICATE_ARG_TYPE_CODE_BIT;
        return true;
    }
    if (!valid_token(arg))
        return false;
    tag = type_expr_ref_tag[arg];
    payload = type_expr_ref_payload[arg];
    return tag != TYPE_REF_INVALID && tag != TYPE_REF_ERROR;
}

uint predicate_trait_arg_for_slot(uint impl_owner, uint slot)
{
    if (slot == 0u)
        return predicate_bound_first_arg_token[impl_owner];
    if (slot == 1u)
        return predicate_bound_second_arg_token[impl_owner];
    return INVALID;
}

bool rows_definitely_mismatch(uint left_row, uint right_row, uint impl_owner)
{
    if (left_row == INVALID || right_row == INVALID)
        return false;

    uint left_tag = type_instance_arg_row_ref_tag[left_row];
    uint left_payload = type_instance_arg_row_ref_payload[left_row];
    uint right_tag = type_instance_arg_row_ref_tag[right_row];
    uint right_payload = type_instance_arg_row_ref_payload[right_row];
    if (left_tag == TYPE_REF_GENERIC_PARAM && valid_token(left_payload))
    {
        uint slot = type_generic_param_slot_by_token[left_payload];
        uint expected_tag;
        uint expected_payload;
        if (slot == INVALID ||
            !predicate_arg_ref(
                predicate_trait_arg_for_slot(impl_owner, slot),
                expected_tag,
                expected_payload))
            return false;
        return ref_values_definitely_mismatch(
            expected_tag,
            expected_payload,
            right_tag,
            right_payload);
    }
    return ref_values_definitely_mismatch(
        left_tag,
        left_payload,
        right_tag,
        right_payload);
}

uint semantic_row_for_node(uint node)
{
    uint count = min(hir_semantic_count[0u], active_hir_node_count());
    uint lo = 0u;
    uint hi = count;
    while (lo < hi)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (hir_semantic_dense_node[mid] < node)
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo < count && hir_semantic_dense_node[lo] == node ? lo : INVALID;
}

bool nodes_definitely_mismatch(uint left_node, uint right_node, uint impl_owner)
{
    uint left_token = type_leaf_token(left_node);
    uint right_token = type_leaf_token(right_node);
    if (!valid_token(left_token) || !valid_token(right_token))
        return false;

    uint left_tag = type_expr_ref_tag[left_token];
    uint left_payload = type_expr_ref_payload[left_token];
    uint right_tag = type_expr_ref_tag[right_token];
    uint right_payload = type_expr_ref_payload[right_token];
    if (left_tag == TYPE_REF_GENERIC_PARAM && valid_token(left_payload))
    {
        uint slot = type_generic_param_slot_by_token[left_payload];
        uint expected_tag;
        uint expected_payload;
        if (slot == INVALID ||
            !predicate_arg_ref(
                predicate_trait_arg_for_slot(impl_owner, slot),
                expected_tag,
                expected_payload))
            return false;
        return ref_values_definitely_mismatch(
            expected_tag, expected_payload, right_tag, right_payload);
    }
    return ref_values_definitely_mismatch(
        left_tag, left_payload, right_tag, right_payload);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint arg_node = linear_thread_id(dtid);
    if (!valid_node(arg_node))
        return;

    uint impl_type = hir_type_root_owner[arg_node];
    if (!valid_node(impl_type) ||
        predicate_method_validation_status[impl_type] != PREDICATE_STATUS_OK)
        return;

    uint trait_type = predicate_method_validation_peer_node[impl_type];
    uint impl_owner = predicate_method_validation_owner_node[impl_type];
    if (!valid_node(trait_type) || !valid_node(impl_owner))
        return;

    uint impl_root_row = semantic_row_for_node(impl_type);
    uint impl_arg_row = semantic_row_for_node(arg_node);
    uint trait_root_row = semantic_row_for_node(trait_type);
    if (impl_root_row == INVALID || impl_arg_row == INVALID ||
        trait_root_row == INVALID || impl_arg_row < impl_root_row)
        return;

    uint trait_row = trait_root_row + (impl_arg_row - impl_root_row);
    uint semantic_count = min(hir_semantic_count[0u], active_hir_node_count());
    if (trait_row >= semantic_count)
        return;
    uint trait_arg_node = hir_semantic_dense_node[trait_row];
    if (!valid_node(trait_arg_node) ||
        trait_arg_node >= subtree_end[trait_type] ||
        !nodes_definitely_mismatch(trait_arg_node, arg_node, impl_owner))
        return;

    predicate_method_validation_owner_node[arg_node] = impl_owner;
    predicate_method_validation_peer_node[arg_node] = trait_type;
    predicate_method_validation_status[arg_node] = PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH;
    predicate_method_validation_detail_token[arg_node] =
        predicate_method_validation_detail_token[impl_type];
}
