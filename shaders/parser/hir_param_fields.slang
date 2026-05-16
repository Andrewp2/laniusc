// Derive parser-owned function parameter metadata from HIR/tree arrays.
//
// Parameter consumers should use these rows instead of deriving parameter
// identity or ordinal from token neighborhoods.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirParam;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_token_pos;

RWStructuredBuffer<uint4> hir_param_record;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_FN = 3u;
static const uint HIR_PARAM = 4u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirParam.uses_ll1 != 0u ? min(gHirParam.n, ll1_status[5u]) : gHirParam.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint owning_function_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    if (hir_kind[node] == HIR_FN)
        return node;

    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        uint p = parent[cur];
        if (!valid_node(p) || p == cur)
            return INVALID;
        if (hir_kind[p] == HIR_FN)
            return p;
        cur = p;
    }
    return INVALID;
}

uint param_ordinal_in_function(uint param_node, uint fn_node)
{
    uint ordinal = 0u;
    uint n = active_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (node == param_node)
            break;
        if (hir_kind[node] == HIR_PARAM && owning_function_node(node) == fn_node)
            ordinal += 1u;
    }
    return ordinal;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirParam.n)
        return;

    hir_param_record[node] = uint4(INVALID, INVALID, INVALID, INVALID);
    if (!valid_node(node) || hir_kind[node] != HIR_PARAM)
        return;

    uint fn_node = owning_function_node(node);
    if (!valid_node(fn_node))
        return;

    uint name_token = hir_token_pos[node];
    if (name_token == INVALID)
        return;

    hir_param_record[node] = uint4(
        fn_node,
        param_ordinal_in_function(node, fn_node),
        name_token,
        node);
}
