import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_intrinsic_tag_by_name_id;

RWStructuredBuffer<uint> call_intrinsic_tag;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;

static const uint TY_VOID = 1u;

static const uint INTRINSIC_NONE = 0u;
static const uint LANGUAGE_SYMBOL_COUNT = 63u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

uint intrinsic_tag_for_name_id(uint name_id)
{
    if (name_id == INVALID || name_id >= gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
        return INTRINSIC_NONE;
    return language_intrinsic_tag_by_name_id[name_id];
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint path_node_for_callee(uint callee_node)
{
    if (!valid_node(callee_node))
        return INVALID;
    if (compact_hir_core[callee_node].kind == HIR_PATH_EXPR)
        return callee_node;
    if (compact_hir_core[callee_node].kind != HIR_NAME_EXPR)
        return INVALID;
    uint child = compact_hir_links[callee_node].first_child;
    return valid_node(child) && compact_hir_core[child].kind == HIR_PATH_EXPR ? child : INVALID;
}

uint path_leaf_token_for_callee(uint callee_node)
{
    if (!valid_node(callee_node))
        return INVALID;
    uint path_i = path_id_by_owner_hir[callee_node];
    if (path_i == INVALID || path_i >= gParams.n_hir_nodes)
    {
        uint path_node = path_node_for_callee(callee_node);
        path_i = valid_node(path_node) ? path_id_by_owner_hir[path_node] : INVALID;
    }
    if (path_i == INVALID || path_i >= gParams.n_hir_nodes)
        return INVALID;

    uint count = path_segment_count[path_i];
    if (count == 0u)
        return INVALID;

    uint slot = path_segment_base[path_i] + count - 1u;
    uint max_slots = gParams.n_tokens;
    if (slot >= max_slots)
        return INVALID;

    uint token = path_segment_token[slot];
    return valid_token(token) ? token : INVALID;
}

uint call_callee_token(uint call_node)
{
    uint callee_node = compact_hir_payload[call_node].a;
    if (!valid_node(callee_node))
        return INVALID;

    HirCore callee = compact_hir_core[callee_node];
    HirPayload payload = compact_hir_payload[callee_node];
    if (callee.kind == HIR_MEMBER_EXPR)
    {
        uint member_token = payload.c;
        return valid_token(member_token) ? member_token : INVALID;
    }

    uint leaf_token = path_leaf_token_for_callee(callee_node);
    if (valid_token(leaf_token))
        return leaf_token;

    uint callee_token = payload.d;
    if (!valid_token(callee_token))
        callee_token = callee.token_start;
    return valid_token(callee_token) ? callee_token : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_hir_node_count() || compact_hir_core[i].kind != HIR_CALL_EXPR)
        return;

    uint callee_token = call_callee_token(i);
    if (callee_token == INVALID || callee_token >= gParams.n_tokens)
        return;

    uint name_id = name_id_by_token[callee_token];
    if (name_id == INVALID || name_id >= gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
        return;
    uint intrinsic_tag = intrinsic_tag_for_name_id(name_id);
    if (intrinsic_tag == INTRINSIC_NONE)
        return;

    call_intrinsic_tag[callee_token] = intrinsic_tag;
    call_return_type[callee_token] = TY_VOID;
    call_return_type_token[callee_token] = INVALID;
}
