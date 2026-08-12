// Follow a bounded run of nearest-semantic-parent links per dispatch.
//
// `value` is the closest dense semantic ancestor discovered so far. `link` is
// the next parse-tree ancestor to compose with if no semantic ancestor has been
// found yet.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_parent_link_in;
StructuredBuffer<uint> hir_semantic_parent_value_in;

RWStructuredBuffer<uint> hir_semantic_parent_link_out;
RWStructuredBuffer<uint> hir_semantic_parent_value_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LINKS_PER_STEP = 16u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirSemantic.uses_status_count != 0u ? min(gHirSemantic.n, tree_count_status[5u]) : gHirSemantic.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirSemantic.n)
        return;

    if (!valid_node(node))
    {
        hir_semantic_parent_link_out[node] = INVALID;
        hir_semantic_parent_value_out[node] = INVALID;
        return;
    }

    uint value = hir_semantic_parent_value_in[node];
    uint link = hir_semantic_parent_link_in[node];

    if (valid_node(value) || !valid_node(link) || link == node)
    {
        hir_semantic_parent_value_out[node] = valid_node(value) ? value : INVALID;
        hir_semantic_parent_link_out[node] = INVALID;
        return;
    }

    for (uint hop = 0u; hop < LINKS_PER_STEP; ++hop)
    {
        if (valid_node(value) || !valid_node(link) || link == node)
            break;
        uint ancestor_value = hir_semantic_parent_value_in[link];
        uint ancestor_link = hir_semantic_parent_link_in[link];
        if (valid_node(ancestor_value))
        {
            value = ancestor_value;
            link = INVALID;
            break;
        }
        link = valid_node(ancestor_link) ? ancestor_link : INVALID;
    }

    hir_semantic_parent_value_out[node] = valid_node(value) ? value : INVALID;
    hir_semantic_parent_link_out[node] = link;
}
