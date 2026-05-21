// Seed parser-owned function-parameter links from grammar tree records.
//
// Parameter lists are right-recursive. First parameters seed the owning
// function, and later parameters point at their previous parameter. A separate
// pointer-jump pass computes owners and ordinals.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirParam;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;

RWStructuredBuffer<uint> hir_param_owner_a;
RWStructuredBuffer<uint> hir_param_link_a;
RWStructuredBuffer<uint> hir_param_rank_a;
RWStructuredBuffer<uint> hir_param_previous;
RWStructuredBuffer<uint> hir_param_owner_b;
RWStructuredBuffer<uint> hir_param_link_b;
RWStructuredBuffer<uint> hir_param_rank_b;

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

uint parent_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint p = parent[node];
    return valid_node(p) ? p : INVALID;
}

uint first_child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = first_child[node];
    return valid_node(child) ? child : INVALID;
}

bool is_param_container(uint prod)
{
    return prod == PROD_PARAMS_SOME ||
           prod == PROD_PARAMS_AFTER_COMMA_MORE;
}

uint param_from_container(uint container)
{
    if (!valid_node(container) || !is_param_container(node_kind[container]))
        return INVALID;
    uint param = first_child_node(container);
    return valid_node(param) && hir_kind[param] == HIR_PARAM ? param : INVALID;
}

uint owner_seed_for_first_param_container(uint container)
{
    if (!valid_node(container) || node_kind[container] != PROD_PARAMS_SOME)
        return INVALID;
    uint fn_node = parent_node(container);
    return valid_node(fn_node) && hir_kind[fn_node] == HIR_FN ? fn_node : INVALID;
}

uint previous_param_for_after_comma_container(uint container)
{
    if (!valid_node(container) ||
        node_kind[container] != PROD_PARAMS_AFTER_COMMA_MORE)
        return INVALID;

    uint more = parent_node(container);
    uint previous_container = parent_node(more);
    return param_from_container(previous_container);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirParam.n)
        return;

    hir_param_owner_a[node] = INVALID;
    hir_param_link_a[node] = INVALID;
    hir_param_rank_a[node] = 0u;
    hir_param_previous[node] = INVALID;
    hir_param_owner_b[node] = INVALID;
    hir_param_link_b[node] = INVALID;
    hir_param_rank_b[node] = 0u;

    if (!valid_node(node) || hir_kind[node] != HIR_PARAM)
        return;

    uint container = parent_node(node);
    uint prod = valid_node(container) ? node_kind[container] : INVALID;
    if (prod == PROD_PARAMS_SOME)
    {
        hir_param_owner_a[node] = owner_seed_for_first_param_container(container);
        return;
    }

    if (prod == PROD_PARAMS_AFTER_COMMA_MORE)
    {
        uint previous = previous_param_for_after_comma_container(container);
        if (valid_node(previous))
        {
            hir_param_link_a[node] = previous;
            hir_param_rank_a[node] = 1u;
            hir_param_previous[node] = previous;
        }
    }
}
