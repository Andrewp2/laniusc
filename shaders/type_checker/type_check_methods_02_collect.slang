// GPU method declaration collection from parser/HIR tree records.
//
// Scheduling contract:
// - Dispatch after parser HIR nodes and tree parent links are available.
// - This pass records fn_item nodes whose parent production is impl_method.
// - Later passes attach module ids, interned method name ids, and receiver
//   type refs from GPU module/name/type tables.
// - It does not inspect source bytes, hash token text, scan impl token bodies,
//   build a direct lookup table, or decide whether a call resolves.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;

RWStructuredBuffer<uint> method_decl_impl_node;
RWStructuredBuffer<uint> method_decl_name_token;
RWStructuredBuffer<uint> method_decl_param_offset;
RWStructuredBuffer<uint> method_decl_receiver_mode;
RWStructuredBuffer<uint> method_decl_visibility;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_FN = 3u;
static const uint HIR_PARAM = 4u;

static const uint PROD_FN_ITEM = 12u;
static const uint PROD_IMPL_ITEM = 15u;
static const uint PROD_IMPL_METHOD = 20u;
static const uint PROD_IMPL_METHOD_PUB = 21u;
static const uint PROD_PARAM_LIST = 52u;
static const uint PROD_PARAM_IDENT = 53u;
static const uint PROD_PARAM_SELF = 54u;
static const uint PROD_PARAM_REF_SELF = 55u;

static const uint METHOD_RECEIVER_NONE = 0u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint METHOD_RECEIVER_EXPLICIT = 3u;

static const uint METHOD_VIS_PRIVATE = 0u;
static const uint METHOD_VIS_PUBLIC = 1u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_hir_node_count();
}

uint node_production(uint i)
{
    return valid_node(i) ? node_kind[i] : INVALID;
}

uint first_child_node(uint i)
{
    uint child = valid_node(i) ? first_child[i] : INVALID;
    return valid_node(child) ? child : INVALID;
}

uint next_sibling_node(uint i)
{
    uint sibling = valid_node(i) ? next_sibling[i] : INVALID;
    return valid_node(sibling) ? sibling : INVALID;
}

uint parent_node(uint i)
{
    uint p = valid_node(i) ? parent[i] : INVALID;
    return valid_node(p) ? p : INVALID;
}

bool is_impl_method_production(uint prod)
{
    return prod == PROD_IMPL_METHOD || prod == PROD_IMPL_METHOD_PUB;
}

bool is_param_production(uint prod)
{
    return prod == PROD_PARAM_IDENT || prod == PROD_PARAM_SELF || prod == PROD_PARAM_REF_SELF;
}

uint ancestor_impl_node(uint i)
{
    uint cur = i;
    [loop]
    for (uint guard = 0u; guard < 32u; guard += 1u)
    {
        uint p = parent_node(cur);
        if (p == INVALID)
            return INVALID;
        if (node_kind[p] == PROD_IMPL_ITEM)
            return p;
        cur = p;
    }
    return INVALID;
}

uint first_method_param_token(uint fn_node)
{
    uint child = first_child_node(fn_node);
    [loop]
    for (uint guard = 0u; guard < 16u && child != INVALID; guard += 1u)
    {
        if (node_kind[child] == PROD_PARAM_LIST)
        {
            uint param = first_child_node(child);
            if (param != INVALID && hir_kind[param] == HIR_PARAM &&
                is_param_production(node_kind[param]))
                return hir_token_pos[param];
            return INVALID;
        }
        child = next_sibling_node(child);
    }
    return INVALID;
}

uint method_receiver_mode(uint fn_node)
{
    uint child = first_child_node(fn_node);
    [loop]
    for (uint guard = 0u; guard < 16u && child != INVALID; guard += 1u)
    {
        if (node_kind[child] == PROD_PARAM_LIST)
        {
            uint param = first_child_node(child);
            if (param == INVALID || hir_kind[param] != HIR_PARAM)
                return METHOD_RECEIVER_NONE;
            uint prod = node_kind[param];
            if (prod == PROD_PARAM_SELF)
                return METHOD_RECEIVER_SELF;
            if (prod == PROD_PARAM_REF_SELF)
                return METHOD_RECEIVER_REF_SELF;
            if (prod == PROD_PARAM_IDENT)
                return METHOD_RECEIVER_EXPLICIT;
            return METHOD_RECEIVER_NONE;
        }
        child = next_sibling_node(child);
    }
    return METHOD_RECEIVER_NONE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_hir_node_count())
        return;

    if (node_kind[i] != PROD_FN_ITEM || hir_kind[i] != HIR_FN)
        return;

    uint method_parent = parent_node(i);
    if (method_parent == INVALID || !is_impl_method_production(node_kind[method_parent]))
        return;

    uint impl_node = ancestor_impl_node(i);
    uint fn_token = hir_token_pos[i];
    if (fn_token == INVALID || impl_node == INVALID || fn_token >= gParams.n_tokens)
        return;

    method_decl_impl_node[fn_token] = impl_node;
    method_decl_name_token[fn_token] = fn_token + 1u;
    method_decl_param_offset[fn_token] = first_method_param_token(i);
    method_decl_receiver_mode[fn_token] = method_receiver_mode(i);
    method_decl_visibility[fn_token] =
        node_kind[method_parent] == PROD_IMPL_METHOD_PUB ? METHOD_VIS_PUBLIC : METHOD_VIS_PRIVATE;
}
