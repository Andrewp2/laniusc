// Parallel linked-prefix step for same-source-end expression ancestors.

import tree_pareas;

struct Params { uint n_items; uint n_blocks; uint key_step; uint reserved; };
ConstantBuffer<Params> gExprRadix;
StructuredBuffer<uint> expr_same_end_link_in;
StructuredBuffer<uint> expr_same_end_rank_in;
RWStructuredBuffer<uint> expr_same_end_link_out;
RWStructuredBuffer<uint> expr_same_end_rank_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

bool valid_node(uint node)
{
    return node != INVALID && node < gExprRadix.n_items;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    if (node >= gExprRadix.n_items)
        return;

    uint link = expr_same_end_link_in[node];
    uint rank = expr_same_end_rank_in[node];
    uint ancestor_link = valid_node(link) ? expr_same_end_link_in[link] : INVALID;
    uint ancestor_rank = valid_node(link) ? expr_same_end_rank_in[link] : 0u;

    uint next_link;
    uint next_rank;
    pareas_linked_prefix_count_step(
        link,
        rank,
        ancestor_link,
        ancestor_rank,
        next_link,
        next_rank);
    expr_same_end_link_out[node] = next_link;
    expr_same_end_rank_out[node] = next_rank;
}
