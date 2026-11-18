// Scatter the match family's rows (prefix_00_local.slang) into a dense
// worklist and publish the indirect dispatch args every family kernel uses.

import prefix_scan;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirMatch;

StructuredBuffer<uint> tree_count_status;
// One mark bit per node (prefix_00_local.slang).
StructuredBuffer<uint> hir_match_rank_flag;
StructuredBuffer<uint> hir_match_rank_block_prefix;

RWStructuredBuffer<uint> hir_match_rank_node;
RWStructuredBuffer<uint> hir_match_rank_count;
RWStructuredBuffer<uint> hir_match_rank_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirMatch.uses_status_count != 0u ? min(gHirMatch.n, tree_count_status[5u])
                                    : gHirMatch.n;
}

uint block_count()
{
    return (gHirMatch.n + WG_SIZE - 1u) / WG_SIZE;
}

void write_dispatch_args(uint active_records)
{
    uint groups = (active_records + WG_SIZE - 1u) / WG_SIZE;
    hir_match_rank_dispatch_args[0u] = min(groups, MAX_GROUPS_X);
    hir_match_rank_dispatch_args[1u] =
        groups == 0u ? 0u : max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    hir_match_rank_dispatch_args[2u] = groups == 0u ? 0u : 1u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node == 0u)
    {
        uint rank_count = inclusive_scan_total(block_count(), hir_match_rank_block_prefix);
        hir_match_rank_count[0u] = rank_count;
        write_dispatch_args(rank_count);
    }

    uint active = active_node_count();
    if (node >= gHirMatch.n || node >= active)
        return;
    uint word_i = node >> 5u;
    uint word = hir_match_rank_flag[word_i];
    uint bit = node & 31u;
    if (((word >> bit) & 1u) == 0u)
        return;

    uint block_i = node / WG_SIZE;
    uint block_base = block_i == 0u ? 0u : hir_match_rank_block_prefix[block_i - 1u];
    uint local = countbits(word & ((1u << bit) - 1u));
    for (uint w = block_i * (WG_SIZE / 32u); w < word_i; ++w)
        local += countbits(hir_match_rank_flag[w]);
    uint dense_row = block_base + local;
    if (dense_row < gHirMatch.n)
        hir_match_rank_node[dense_row] = node;
}
