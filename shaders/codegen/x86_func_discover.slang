import utils;

// Direct x86_64 function discovery.
//
// This pass maps GPU HIR function nodes and owning-function records for the
// native backend. It consumes the backend tree projection, not parser parent
// pointers directly, so later stages can converge on the same Pareas-style node
// property record.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint4> x86_node_tree_record;
StructuredBuffer<uint> x86_node_tree_status;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_item_decl_token;
StructuredBuffer<uint> fn_entrypoint_tag;

RWStructuredBuffer<uint> x86_func_meta;
RWStructuredBuffer<uint> x86_node_func;
RWStructuredBuffer<uint4> x86_func_record;
RWStructuredBuffer<uint> x86_func_lookup_key;
RWStructuredBuffer<uint> x86_func_lookup_node;

static const uint INVALID = 0xffffffffu;
static const uint HIR_FN = 3u;
static const uint ENTRYPOINT_MAIN = 1u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_NODE_TREE_OK = 1u;

static const uint FUNC_META_FUNC_COUNT = 0u;
static const uint FUNC_META_MAIN_COUNT = 1u;
static const uint FUNC_META_MAIN_NODE = 4u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool is_main_function_node(uint node_i)
{
    return hir_kind[node_i] == HIR_FN && fn_entrypoint_tag[node_i] == ENTRYPOINT_MAIN;
}

bool valid_node(uint node_i)
{
    return node_i != INVALID && node_i < active_hir_node_count();
}

bool valid_token(uint token_i)
{
    return token_i != INVALID && token_i < gParams.n_tokens;
}

bool node_tree_ok()
{
    return x86_node_tree_status[0u] == X86_NODE_TREE_OK &&
           x86_node_tree_status[1u] == 0u;
}

uint lookup_capacity()
{
    return max(gParams.n_tokens * 2u, 1u);
}

uint owning_function_node(uint node_i)
{
    if (!valid_node(node_i))
        return INVALID;
    if (hir_kind[node_i] == HIR_FN)
        return node_i;

    uint cur = node_i;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        uint p = x86_node_tree_record[cur].x;
        if (!valid_node(p) || p == cur)
            return INVALID;
        if (hir_kind[p] == HIR_FN)
            return p;
        cur = p;
    }
    return INVALID;
}

void publish_function_lookup(uint node_i)
{
    if (hir_kind[node_i] != HIR_FN)
        return;

    uint resolver_target_token = hir_item_decl_token[node_i];
    if (!valid_token(resolver_target_token))
        return;

    uint key = resolver_target_token;
    uint cap = lookup_capacity();
    uint start_slot = key % cap;
    [loop]
    for (uint probe = 0u; probe < cap; probe += 1u)
    {
        uint slot = (start_slot + probe) % cap;
        uint old_node = INVALID;
        InterlockedCompareExchange(x86_func_lookup_node[slot], INVALID, node_i, old_node);
        if (old_node == INVALID)
        {
            x86_func_lookup_key[slot] = key;
            return;
        }
        if (x86_func_lookup_key[slot] == key)
        {
            uint old_min = INVALID;
            InterlockedMin(x86_func_lookup_node[slot], node_i, old_min);
            return;
        }
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (!node_tree_ok() || node_i >= active_hir_node_count())
        return;

    uint owner = owning_function_node(node_i);
    x86_node_func[node_i] = owner;

    if (hir_kind[node_i] != HIR_FN)
        return;

    x86_func_record[node_i] = uint4(node_i, fn_entrypoint_tag[node_i], hir_item_decl_token[node_i], 0u);
    publish_function_lookup(node_i);

    uint old_count = 0u;
    InterlockedAdd(x86_func_meta[FUNC_META_FUNC_COUNT], 1u, old_count);

    if (!is_main_function_node(node_i))
        return;

    uint old_main_count = 0u;
    InterlockedAdd(x86_func_meta[FUNC_META_MAIN_COUNT], 1u, old_main_count);
    InterlockedMin(x86_func_meta[FUNC_META_MAIN_NODE], node_i);
}
