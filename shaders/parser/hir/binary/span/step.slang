// Follow a bounded run of binary-expression left-span links per dispatch, for
// the compacted rows whose chain outlived the seed's local walk. Every other
// semantic row keeps the record the seed wrote into both ping-pong buffers.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirExpr;

StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_list_rank_node;
StructuredBuffer<uint> hir_list_rank_count;
StructuredBuffer<uint> hir_binary_span_link_in;
StructuredBuffer<uint> hir_binary_span_start_in;

RWStructuredBuffer<uint> hir_binary_span_link_out;
RWStructuredBuffer<uint> hir_binary_span_start_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LINKS_PER_STEP = 16u;

uint active_row_count()
{
    return min(gHirExpr.n, hir_semantic_count[0u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint item = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    if (item >= gHirExpr.n || item >= hir_list_rank_count[0u])
        return;
    uint row = hir_list_rank_node[item];
    uint active = active_row_count();
    if (row >= active)
        return;

    uint link = hir_binary_span_link_in[row];
    uint start = hir_binary_span_start_in[row];
    for (uint hop = 0u; hop < LINKS_PER_STEP && link < active && link != row; ++hop)
    {
        uint linked_start = hir_binary_span_start_in[link];
        if (linked_start != INVALID && (start == INVALID || linked_start < start))
            start = linked_start;
        uint linked_link = hir_binary_span_link_in[link];
        link = linked_link < active && linked_link != row ? linked_link : INVALID;
    }
    hir_binary_span_link_out[row] = link < active && link != row ? link : INVALID;
    hir_binary_span_start_out[row] = start;
}
