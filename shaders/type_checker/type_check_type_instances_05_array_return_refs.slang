// HIR identifier array-return projection.
//
// This pass consumes parser-owned return-statement records, visible-decl
// records, declaration type refs, and function return type refs. It publishes
// the array-return sentinel for `return values;` only when the returned
// declaration has the same bounded array instance as the enclosing function
// return type. It does not inspect token kinds, token spelling, source bytes,
// or expression punctuation.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;

RWStructuredBuffer<uint> call_return_type;

static const uint INVALID = 0xffffffffu;
static const uint ARRAY_RETURN_OK = 0xfffffffeu;

static const uint HIR_FN = 3u;
static const uint HIR_RETURN_STMT = 9u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_RETURN = 2u;

static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_LEN_LITERAL = 1u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
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
    return token != INVALID && token < gParams.n_tokens;
}

uint stmt_slot(uint node, uint slot)
{
    return node * STMT_RECORD_STRIDE + slot;
}

uint owning_function_node(uint node)
{
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        if (!valid_node(cur))
            return INVALID;
        if (hir_kind[cur] == HIR_FN)
            return cur;

        uint p = parent[cur];
        if (!valid_node(p) || p == cur)
            return INVALID;
        cur = p;
    }
    return INVALID;
}

uint bounded_array_instance_from_ref(uint tag, uint payload)
{
    if (tag != TYPE_REF_INSTANCE || !valid_token(payload))
        return INVALID;
    if (type_instance_kind[payload] != TYPE_INSTANCE_ARRAY)
        return INVALID;
    if (type_instance_len_kind[payload] != TYPE_LEN_LITERAL)
        return INVALID;
    return payload;
}

bool same_type_ref(uint lhs_tag, uint lhs_payload, uint rhs_tag, uint rhs_payload)
{
    return lhs_tag == rhs_tag && lhs_payload == rhs_payload;
}

bool same_bounded_array_instance(uint lhs, uint rhs)
{
    lhs = valid_token(lhs) ? lhs : INVALID;
    rhs = valid_token(rhs) ? rhs : INVALID;
    if (lhs == INVALID || rhs == INVALID)
        return false;
    if (type_instance_kind[lhs] != TYPE_INSTANCE_ARRAY ||
        type_instance_kind[rhs] != TYPE_INSTANCE_ARRAY)
        return false;
    if (type_instance_len_kind[lhs] != TYPE_LEN_LITERAL ||
        type_instance_len_kind[rhs] != TYPE_LEN_LITERAL)
        return false;
    if (type_instance_len_payload[lhs] != type_instance_len_payload[rhs])
        return false;
    return same_type_ref(
        type_instance_elem_ref_tag[lhs],
        type_instance_elem_ref_payload[lhs],
        type_instance_elem_ref_tag[rhs],
        type_instance_elem_ref_payload[rhs]);
}

uint function_return_array_instance(uint return_node)
{
    uint fn_node = owning_function_node(return_node);
    if (!valid_node(fn_node))
        return INVALID;

    uint fn_token = hir_token_pos[fn_node];
    if (!valid_token(fn_token))
        return INVALID;

    return bounded_array_instance_from_ref(
        fn_return_ref_tag[fn_token],
        fn_return_ref_payload[fn_token]);
}

uint declaration_array_instance(uint value_token)
{
    if (!valid_token(value_token))
        return INVALID;

    uint decl_token = visible_decl[value_token];
    if (!valid_token(decl_token))
        return INVALID;

    return bounded_array_instance_from_ref(
        decl_type_ref_tag[decl_token],
        decl_type_ref_payload[decl_token]);
}

void publish_identifier_array_return(uint return_node)
{
    if (hir_kind[return_node] != HIR_RETURN_STMT ||
        hir_stmt_record[stmt_slot(return_node, 0u)] != STMT_RECORD_KIND_RETURN)
        return;

    uint return_token = hir_token_pos[return_node];
    if (!valid_token(return_token))
        return;

    uint value_token = hir_stmt_record[stmt_slot(return_node, 3u)];
    uint src_instance = declaration_array_instance(value_token);
    if (src_instance == INVALID)
        return;

    uint dst_instance = function_return_array_instance(return_node);
    if (same_bounded_array_instance(dst_instance, src_instance))
        call_return_type[return_token] = ARRAY_RETURN_OK;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    publish_identifier_array_return(node);
}
